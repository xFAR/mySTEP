/* 
   NSRunLoop.m

   Implementation of object for waiting on several input sources.

   Copyright (C) 1996, 1997 Free Software Foundation, Inc.

   Author:	Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
   Date:	March 1996
   GNUstep: Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date:	August 1997
   mySTEP:	Felipe A. Rodriguez <farz@mindspring.com>
   Date:	April 1999

   This file is part of the mySTEP Library and is provided
   under the terms of the GNU Library General Public License.
*/

#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSTimer.h>
#import <Foundation/NSNotificationQueue.h>
#import <Foundation/NSRunLoop.h>
#import <Foundation/NSThread.h>
#import "NSPrivate.h"

#include <time.h>
#include <sys/time.h>
#include <sys/types.h>

// Class variables
static NSThread *__currentThread = nil;
static NSRunLoop *__currentRunLoop = nil;
NSString *NSDefaultRunLoopMode = @"NSDefaultRunLoopMode";


//*****************************************************************************
//
// 		_NSRunLoopPerformer 
//
//*****************************************************************************

@interface _NSRunLoopPerformer: NSObject
{										// The RunLoopPerformer class is used
	SEL selector;						// to hold information about messages
	id target;							// which are due to be sent to objects
	id argument;						// once a particular runloop iteration 
	unsigned order;						// has passed.
@public
	NSArray	*modes;
	NSTimer	*timer;		// nonretained pointer!
}

- (id) initWithSelector:(SEL)aSelector
				 target:(id)target
				 argument:(id)argument
				 order:(unsigned int)order
				 modes:(NSArray*)modes;
- (void) invalidate;
- (BOOL) matchesTarget:(id)aTarget;
- (BOOL) matchesSelector:(SEL)aSelector
				  target:(id)aTarget
				  argument:(id)anArgument;
- (unsigned int) order;
- (void) setTimer:(NSTimer*)timer;
- (NSArray*) modes;
- (NSTimer*) timer;
- (void) fire;

@end

@interface NSRunLoop (Private)

- (NSMutableArray*) _timedPerformers;

@end

@implementation _NSRunLoopPerformer

- (void) dealloc
{
#if 0
	NSLog(@"%@ dealloc", self);
	NSLog(@"timer: %@", timer);
#endif
	[timer invalidate];	// if any
	[target release];
	[argument release];
	[modes release];
	[super dealloc];
}

- (NSString *) description;
{
	return [NSString stringWithFormat:@"%@ timer:(%p) target:%@ selector:%@",
		NSStringFromClass([self class]),
		timer,
		target,
		NSStringFromSelector(selector)];
}

- (void) invalidate
{
#if 0
	NSLog(@"invalidate %@", self);
#endif
	[timer invalidate];	// invalidate our timer (if any)
	timer=nil;
}

- (void) fire
{ // untimed performers are being processed or timer has fired
#if 0
	NSLog(@"fire %@ retainCount=%d", self, [self retainCount]);
#endif
	if(timer != nil)
		{
#if 0
		NSLog(@"remove self from list of timed performers: %@", [[NSRunLoop currentRunLoop] _timedPerformers]);
#endif
		[[[NSRunLoop currentRunLoop] _timedPerformers] removeObjectIdenticalTo:self];	// remove us from performers list
		}
	[target performSelector:selector withObject:argument];
}

- (id) initWithSelector:(SEL)aSelector
				 target:(id)aTarget
			   argument:(id)anArgument
				  order:(unsigned int)theOrder
				  modes:(NSArray*)theModes
{
	if((self = [super init]))
		{
		selector = aSelector;
		target = [aTarget retain];
		argument = [anArgument retain];
		order = theOrder;
		modes = [theModes copy];
		}
	return self;
}

- (BOOL) matchesTarget:(id)aTarget
{
	return (target == aTarget);
}

- (BOOL) matchesSelector:(SEL)aSelector
				  target:(id)aTarget
				argument:(id)anArgument
{ 
#if 0
	NSLog(@"%s == %s?", sel_get_name(aSelector), sel_get_name(selector));
	NSLog(@"%@ == %@?", target, aTarget);
	NSLog(@"%@ == %@?", argument, anArgument);
#endif
	return (target == aTarget) && SEL_EQ(aSelector, selector) && (argument == anArgument || [argument isEqual:anArgument]);
}

- (NSArray*) modes						{ return modes; }
- (NSTimer*) timer						{ return timer; }
- (unsigned int) order					{ return order; }
- (void) setTimer:(NSTimer*)t
{
#if 0
	NSLog(@"timer %p := %p", timer, t);
#endif
	timer=t;	// we are retained by the timer - and not vice versa
}

@end /* _NSRunLoopPerformer */

@implementation NSRunLoop

+ (NSRunLoop *) currentRunLoop
{
	NSString *key = @"NSRunLoopThreadKey";
	NSThread *t = [NSThread currentThread];
	if(__currentThread != t)
		{
		__currentThread = t;

		if((__currentRunLoop = [[t threadDictionary] objectForKey:key]) == nil)					
			{										// if current thread has no
			__currentRunLoop = [NSRunLoop new];		// run loop create one
			[[t threadDictionary] setObject:__currentRunLoop forKey:key];
			[__currentRunLoop release];
		}	}

	return __currentRunLoop;
}

- (id) init											// designated initializer
{
	self=[super init];
	if(self)
		{
		_mode_2_timers = NSCreateMapTable (NSNonRetainedObjectMapKeyCallBacks,
										   NSObjectMapValueCallBacks, 0);
		_mode_2_inputwatchers = NSCreateMapTable (NSObjectMapKeyCallBacks,
											 NSObjectMapValueCallBacks, 0);
		_mode_2_outputwatchers = NSCreateMapTable (NSObjectMapKeyCallBacks,
												  NSObjectMapValueCallBacks, 0);
		rfd_2_object = NSCreateMapTable (NSIntMapKeyCallBacks,
										 NSObjectMapValueCallBacks, 0);
		wfd_2_object = NSCreateMapTable (NSIntMapKeyCallBacks,
										 NSObjectMapValueCallBacks, 0);
		_performers = [[NSMutableArray alloc] initWithCapacity:8];
		_timedPerformers = [[NSMutableArray alloc] initWithCapacity:8];
		}
	return self;
}

- (void) dealloc
{
	NSFreeMapTable(_mode_2_timers);
	NSFreeMapTable(_mode_2_inputwatchers);
	NSFreeMapTable(_mode_2_outputwatchers);
	NSFreeMapTable (rfd_2_object);
	NSFreeMapTable (wfd_2_object);
	[_performers release];
	[_timedPerformers release];
	[super dealloc];
}

- (void) addTimer:(NSTimer *)timer forMode:(NSString*)mode		// Add timer. It is removed when it becomes invalid
{
	NSMutableArray *timers = NSMapGet(_mode_2_timers, mode);
#if 0
	NSLog(@"addTimer %@ forMode:%@", timer, mode);
#endif
	if(!timers)
		{
		timers = [NSMutableArray new];
		NSMapInsert(_mode_2_timers, mode, timers);
		[timers release];
		}
	if([timers containsObject:timer])
		NSLog(@"trying to add timer twice: %@", timer);
	[timers addObject:timer];	// append timer
#if 0
	NSLog(@"timers: %@", timers);
#endif
}

- (BOOL) _runLoopForMode:(NSString*)mode beforeDate:(NSDate*)before limitDate:(NSDate **) limit;
{ // this is the core runloop call that runs the loop at least once - blocking or non-blocking
	NSTimeInterval ti;					// Listen to input sources.
	struct timeval timeout;
	void *select_timeout;
	NSMutableArray *watchers;
	// fd_set fds;						// file descriptors we will listen to. 
	fd_set read_fds;					// Copy for listening to read-ready fds.
	fd_set exception_fds;				// Copy for listening to exception fds.
	fd_set write_fds;					// Copy for listening for write-ready fds.
	int select_return;
	int fd_index;
	int num_inputs = 0;
	int count = [_performers count];
	id saved_mode=_current_mode;	// an input handler might run the same loop recursively!
	int i, loop;
	NSMutableArray *timers;
	NSAutoreleasePool *arp;
	
	NSAssert(mode, NSInvalidArgumentException);
#if 0
	NSLog(@"_runLoopForMode:%@ beforeDate:%@ limitDate:%p", mode, before, limit);
#endif
	if(limit)
		*limit=[NSDate distantFuture];	// default
	arp=[NSAutoreleasePool new];
#if 0
	NSLog(@"_checkPerformersAndTimersForMode:%@ count=%d", mode, count);
#endif
	_current_mode = mode;
	for(loop = 0, i=0; loop < count; loop++)
		{ // check for performers to fire
		_NSRunLoopPerformer *item = [_performers objectAtIndex: i];
		if([item->modes containsObject:mode])
			{ // here we have untimed performers only - timed performers will be triggered by timer
			[item retain];
			[_performers removeObjectAtIndex:i];	// remove before firing - it may add a new one
			[item fire];
			[item release];
			}
		else									// inc cntr only if obj is not
			i++;								// removed else we will run off
		}										// the end of the array
	
	if((timers = NSMapGet(_mode_2_timers, mode)))									
		{ // get all timers for this mode
		i = [timers count];		
		while(i-- > 0)
			{ // process backwards because we might remove the timer
			NSTimer *min_timer = [timers objectAtIndex:i];
			NSTimeInterval timeFromNow;
#if 0
			NSLog(@"%d: check %@ forMode:%@", i, min_timer, mode);
#endif
#if 0
			NSLog(@"retainCount=%d", [min_timer retainCount]);
#endif
			if(min_timer->_is_valid)
				{ // still valid (may be left over with negative interval from firing while we did run in other mode)
				NSDate *fire=[min_timer fireDate];
				timeFromNow=[fire timeIntervalSinceNow];
				if(timeFromNow > 0.0)
					{ // not yet elapsed
					if(limit && [fire timeIntervalSinceReferenceDate] < [*limit timeIntervalSinceReferenceDate])
						*limit=fire;	// timer with earlier trigger date found
					continue;
					}
				[min_timer fire];	// this might fire an attached timed performer object
				}
			if(!min_timer->_is_valid)
				{ // now invalid after firing (i.e. we are not a repeating timer)
#if 0
				NSLog(@"%d[%d] remove %@", i, [timers count], min_timer);
#endif
				[timers removeObjectAtIndex:i];	// this should dealloc the timer (and a timed performer) if it is the last mode we have checked
				}
			}
		}
	
	if(limit)
		[*limit retain];	// protect against being dealloc'ed when we clear up the private ARP

	if(!before || (ti = [before timeIntervalSinceNow]) <= 0.0)		// Determine time to wait and
		{															// set SELECT_TIMEOUT.	Don't
		timeout.tv_sec = 0;											// wait if no limit date or it lies in the past. i.e.		
		timeout.tv_usec = 0;										// call select() once with 0 timeout effectively polling inputs
		select_timeout = &timeout;
#if 0
		NSLog(@"_runLoopForMode:%@ beforeDate:%@ - don't wait", mode, limit_date);
#endif
    	}
	else if (ti < LONG_MAX)
		{ // Wait until the LIMIT_DATE.
		NSDebugLog(@"NSRunLoop accept input %f seconds from now %f", 						
				   [before timeIntervalSinceReferenceDate], ti);
		timeout.tv_sec = ti;
		timeout.tv_usec = (ti - timeout.tv_sec) * 1000000.0;
		select_timeout = &timeout;
		}
	else
		{ // Wait very long, i.e. forever
		NSDebugLog(@"NSRunLoop accept input waiting forever");
		select_timeout = NULL;
		}
	
	FD_ZERO (&read_fds);						// Initialize the set of FDS
	FD_ZERO (&write_fds);						// we'll pass to select()
	
	if((watchers = NSMapGet(_mode_2_inputwatchers, mode)))
		{										// Do the pre-listening set-up
		int	i=[watchers count];					// for the file descriptors of
												// this mode.
		while(i-- > 0)
			{
			NSObject *watcher = [watchers objectAtIndex:i];
			int fd=[watcher _readFileDescriptor];
#if 0
			NSLog(@"watch fd=%d for input", fd);
#endif
			if(fd >= 0 && fd < FD_SETSIZE)
				{
				FD_SET(fd, &read_fds);
				NSMapInsert(rfd_2_object, (void*)fd, watcher);
				num_inputs++;
				}
			}
		}
	if((watchers = NSMapGet(_mode_2_outputwatchers, mode)))
		{										// Do the pre-listening set-up
		int	i=[watchers count];					// for the file descriptors of
												// this mode.
		while(i-- > 0)
			{
			NSObject *watcher = [watchers objectAtIndex:i];
			int fd=[watcher _writeFileDescriptor];
#if 0
			NSLog(@"watch fd=%d for output", fd);
#endif
			if(fd >= 0 && fd < FD_SETSIZE)
				{
				FD_SET(fd, &write_fds);
				NSMapInsert(wfd_2_object, (void*)fd, watcher);
				num_inputs++;
				}
			}
		}
	
	if(num_inputs == 0)
		{
		_current_mode = saved_mode;
		[arp release];
		if(limit) [*limit autorelease];
		return NO;	// don't wait - we have no watchers
		}

	// CHECKME: should we introduce sepatate watchers for exceptions?
	
	exception_fds = read_fds;			// the file descriptors in _FDS.
	
	if(num_inputs == 0 && [NSNotificationQueue _runLoopMore])			// Detect if the NSRunLoop
		{											// is idle, and if needed
		timeout.tv_sec = 0;							// dispatch notifications
		timeout.tv_usec = 0;						// from NSNotificationQue's
		select_timeout = &timeout;					// idle queue?
		}
	
	select_return = select(FD_SETSIZE, &read_fds, &write_fds, &exception_fds, select_timeout);
#if 0
	NSLog(@"NSRunLoop select returned %d", select_return);
#endif
	if(select_return < 0)
		{
		if(errno == EINTR)							// a signal was caught
			select_return = 0;
		else										// Some kind of exceptional
			{										// condition has occurred
			perror("NSRunLoop acceptInputForMode:beforeDate: during select()");
			abort();
			}
		}
	
	if(select_return == 0)
		[NSNotificationQueue _runLoopIdle]; 
	else 
		{ // Inspect all file descriptors where select() says they are ready, notify the respective object for each ready fd.
		for (fd_index = 0; fd_index < FD_SETSIZE /* FIXME:can't we limit to select_return? */; fd_index++)
			{
			if (FD_ISSET (fd_index, &write_fds))
				{
				NSObject *w = NSMapGet(wfd_2_object, (void*)fd_index);
				NSAssert(w, NSInternalInconsistencyException);
#if 0
				NSLog(@"_writeFileDescriptorReady: %@", w);
#endif
				[w _writeFileDescriptorReady];	// notify
				}
			
			if (FD_ISSET (fd_index, &read_fds))
				{
				NSObject *w = NSMapGet(rfd_2_object, (void*)fd_index);
				NSAssert(w, NSInternalInconsistencyException);
#if 0
				NSLog(@"_readFileDescriptorReady: %@", w);
#endif
				[w _readFileDescriptorReady];	// notify
				}
			}
		[NSNotificationQueue _runLoopASAP];
		}
	
	NSResetMapTable (rfd_2_object);					// Clean up before return.
	NSResetMapTable (wfd_2_object);
#if 0
	NSLog(@"acceptInput done");
#endif
	_current_mode = saved_mode;	// restore
	[arp release];
	if(limit) [*limit autorelease];
	return YES;
}

- (NSDate *) limitDateForMode:(NSString *)mode
{  // determine the earliest timeout of all timers in this mode to end the accept loop
	NSDate *limit;
	[self _runLoopForMode:mode beforeDate:nil limitDate:&limit];	// run once, non-blocking
	return limit;
#if OLD
	NSMutableArray *timers;
	NSTimer *timerWithNearestFireDate = nil;
	static NSDate *distFuture;
#if 0
	NSLog(@"limitDateForMode: %@", mode);
#endif
	// CHECKME: what should we return if we have performers?
	// FIXME: check if there are any watchers for this mode - if none, return nil
	// FIXME: find an ingenious way to avoid all those double float comparisons!
	// ideas:
	// - insert-sort timers when they are scheduled
	// - keep next timer in a cache and go through list only if that timer has triggered or we have scheduled one
	//
	if((timers = NSMapGet(_mode_2_timers, mode)))									
		{										
		NSTimeInterval minTime = 0.0;
		NSEnumerator *e=[timers objectEnumerator];
		NSTimer *min_timer; 
		while((min_timer=[e nextObject]))
			{ // process backwards
			NSTimeInterval timeFromNow;
			if(!min_timer->_is_valid)	// if timer is not valid ignore
				continue;
			timeFromNow = [min_timer->_fireDate timeIntervalSinceNow];
			if((timerWithNearestFireDate == nil || timeFromNow < minTime))
				{ // detect the timer with the earliest fire date
				timerWithNearestFireDate = min_timer;	// earlier one found
				minTime = timeFromNow;
				}
			}
		}					 	
	if(timerWithNearestFireDate)
		return [[timerWithNearestFireDate->_fireDate retain] autorelease];	// if the timer finally fires, limitDate will be released!
	if(!distFuture) distFuture=[[NSDate distantFuture] retain];	// cache the pointer
	return distFuture;
#endif
}

#if OLD
- (void) _checkPerformersAndTimersForMode:(NSString *) mode
{ // check if any timer is to fire now
	int count = [_performers count];
	id saved_mode=_current_mode;
	int i, loop;
	NSMutableArray *timers;
	NSAutoreleasePool *arp=[NSAutoreleasePool new];
#if 0
	NSLog(@"_checkPerformersAndTimersForMode:%@ count=%d", mode, count);
#endif
	_current_mode = mode;
	for(loop = 0, i=0; loop < count; loop++)
		{ // check for performers to fire
		_NSRunLoopPerformer *item = [_performers objectAtIndex: i];
		if([item->modes containsObject:mode])
			{ // here we have untimed performers only - timed performers will be triggered by timer
			[item retain];
			[_performers removeObjectAtIndex:i];	// remove before firing - it may add a new one
			[item fire];
			[item release];
			}
		else									// inc cntr only if obj is not
			i++;								// removed else we will run off
		}										// the end of the array

	if((timers = NSMapGet(_mode_2_timers, mode)))									
		{ // get all timers for this mode
		i = [timers count];		
		while(i-- > 0)
			{ // process backwards because we might remove the timer
			NSTimer *min_timer = [timers objectAtIndex:i];
			NSTimeInterval timeFromNow;
#if 0
			NSLog(@"%d: check %@ forMode:%@", i, min_timer, mode);
#endif
#if 0
			NSLog(@"retainCount=%d", [min_timer retainCount]);
#endif
			if(min_timer->_is_valid)
				{ // still valid (may be left over from firing on other mode)
				timeFromNow = [[min_timer fireDate] timeIntervalSinceNow];
				if(timeFromNow > 0.0)
					continue;		// not yet elapsed
				[min_timer fire];	// this might fire an attached timed performer object
				}
			if(!min_timer->_is_valid)
				{ // now invalid after firing (i.e. not a repeating timer)
#if 0
				NSLog(@"%d[%d] remove %@", i, [timers count], min_timer);
#endif
				[timers removeObjectAtIndex:i];	// this should dealloc the timer (and a timed performer) if it is the last mode we have checked
				}
			}
		}
	_current_mode = saved_mode;
	[arp release];
#if 0
	NSLog(@" checked and ARP released");
#endif
}
#endif

- (void) acceptInputForMode:(NSString*)mode beforeDate:(NSDate *)limit_date
{
	[self _runLoopForMode:mode beforeDate:limit_date limitDate:NULL];	// run blocking until limit_date
#if OLD
	NSTimeInterval ti;								// Listen to input sources.
	struct timeval timeout;
	void *select_timeout;
	NSMutableArray *watchers;
	// fd_set fds;							// file descriptors we will listen to. 
	fd_set read_fds;					// Copy for listening to read-ready fds.
	fd_set exception_fds;				// Copy for listening to exception fds.
	fd_set write_fds;					// Copy for listening for write-ready fds.
	int select_return;
	int fd_index;
	int num_inputs = 0;
	id saved_mode=_current_mode;	// an input handler might run the same loop recursively!

	NSAssert(mode, NSInvalidArgumentException);
#if 0
	NSLog(@"acceptInputForMode:%@ beforeDate:%@", mode, limit_date);
#endif
	_current_mode = mode;
	if (!limit_date || (ti = [limit_date timeIntervalSinceNow]) <= 0.0)		// Determine time to wait and
		{																	// set SELECT_TIMEOUT.	Don't
		timeout.tv_sec = 0;													// wait if no limit date or it lies in the past. i.e.		
		timeout.tv_usec = 0;												// call select() once with 0 timeout effectively polling inputs
		select_timeout = &timeout;
#if 0
		NSLog(@"acceptInputForMode:%@ beforeDate:%@ - don't wait", mode, limit_date);
#endif
    	}
	else if (ti < LONG_MAX)
		{ // Wait until the LIMIT_DATE.
		NSDebugLog(@"NSRunLoop accept input %f seconds from now %f", 						
				   [limit_date timeIntervalSinceReferenceDate], ti);
		timeout.tv_sec = ti;
		timeout.tv_usec = (ti - timeout.tv_sec) * 1000000.0;
		select_timeout = &timeout;
		}
#if OLD
	else if(ti <= 0.0)					// past; return immediately
		{ 								// without polling any inputs.
		_current_mode = saved_mode;
		return;
		}
#endif
	else
		{ // Wait very long, i.e. forever
		NSDebugLog(@"NSRunLoop accept input waiting forever");
		select_timeout = NULL;
		}
	
	FD_ZERO (&read_fds);						// Initialize the set of FDS
	FD_ZERO (&write_fds);						// we'll pass to select()

	if((watchers = NSMapGet(_mode_2_inputwatchers, mode)))
		{										// Do the pre-listening set-up
		int	i;									// for the file descriptors of
												// this mode.
		for (i = [watchers count]; i > 0; i--)
			{
			NSObject *watcher = [watchers objectAtIndex:(i-1)];
			int fd2=-1;
			int fd=[watcher _readFileDescriptor:&fd2];
#if 0
			NSLog(@"watch fd=%d and fd2=%d for input", fd, fd2);
#endif
			if(fd >= 0 && fd < FD_SETSIZE)
				{
				FD_SET(fd, &read_fds);
				NSMapInsert(rfd_2_object, (void*)fd, watcher);
				num_inputs++;
				}
			if(fd2 >= 0 && fd2 < FD_SETSIZE)
				{
				FD_SET(fd2, &read_fds);
				NSMapInsert(rfd_2_object, (void*)fd2, watcher);
				num_inputs++;
				}
			}
		}
	if((watchers = NSMapGet(_mode_2_outputwatchers, mode)))
		{										// Do the pre-listening set-up
		int	i;									// for the file descriptors of
												// this mode.
		for (i = [watchers count]; i > 0; i--)
			{
			NSObject *watcher = [watchers objectAtIndex:(i-1)];
			int fd=[watcher _writeFileDescriptor];
#if 0
			NSLog(@"watch fd=%d for output", fd);
#endif
			if(fd >= 0 && fd < FD_SETSIZE)
				{
				FD_SET(fd, &write_fds);
				NSMapInsert(wfd_2_object, (void*)fd, watcher);
				num_inputs++;
				}
			}
		}
	
	// CHECKME: should we introduce sepatate watchers for exceptions?
	
	exception_fds = read_fds;			// the file descriptors in _FDS.
	
	if(num_inputs == 0 && [NSNotificationQueue _runLoopMore])			// Detect if the NSRunLoop
		{											// is idle, and if needed
		timeout.tv_sec = 0;							// dispatch notifications
		timeout.tv_usec = 0;						// from NSNotificationQue's
		select_timeout = &timeout;					// idle queue?
		}

	select_return = select(FD_SETSIZE, &read_fds, &write_fds, &exception_fds, select_timeout);
#if 0
	NSLog(@"NSRunLoop select returned %d", select_return);
#endif
	if(select_return < 0)
		{
		if(errno == EINTR)							// a signal was caught
			select_return = 0;
		else										// Some kind of exceptional
			{										// condition has occurred
			perror("NSRunLoop acceptInputForMode:beforeDate: during select()");
			abort();
			}
		}

	if(select_return == 0)
		[NSNotificationQueue _runLoopIdle]; 
	else 
		{ // Inspect all file descriptors select() says are ready, notify the respective object for each ready fd.
		for (fd_index = 0; fd_index < FD_SETSIZE /* FIXME:can't we limit to select_return? */; fd_index++)
			{
			if (FD_ISSET (fd_index, &write_fds))
				{
				NSObject *w = NSMapGet(wfd_2_object, (void*)fd_index);
				NSAssert(w, NSInternalInconsistencyException);
#if 0
				NSLog(@"_writeFileDescriptorReady: %@", w);
#endif
				[w _writeFileDescriptorReady:fd_index];	// notify
				}
	
			if (FD_ISSET (fd_index, &read_fds))
				{
				NSObject *w = NSMapGet(rfd_2_object, (void*)fd_index);
				NSAssert(w, NSInternalInconsistencyException);
#if 0
				NSLog(@"_readFileDescriptorReady: %@", w);
#endif
				[w _readFileDescriptorReady:fd_index];	// notify
				}
			}
		[NSNotificationQueue _runLoopASAP];
		}

	NSResetMapTable (rfd_2_object);					// Clean up before return.
	NSResetMapTable (wfd_2_object);
#if 0
	NSLog(@"acceptInput done");
#endif
	_current_mode = saved_mode;	// restore
#endif
}

- (BOOL) runMode:(NSString *)mode beforeDate:(NSDate *)date
{ // block until date or input becomes available - postpones timers! until input arrives or date is reached
#if 0
	NSLog(@"runMode:%@ beforeDate:%@", mode, date);
#endif
	if([((NSArray *)NSMapGet(_mode_2_inputwatchers, mode)) count]+[((NSArray *)NSMapGet(_mode_2_outputwatchers, mode)) count] == 0)
		{
#if 0
		NSLog(@"runMode:%@ beforeDate:%@ - no watchers for this mode!", mode, date);
#endif
		return NO;	// we have no watchers for this mode
		}
#if 0
	NSLog(@"  earlier date is %@", date);
#endif
	[self _runLoopForMode:mode beforeDate:date limitDate:NULL];	// run blocking until date

//	[self acceptInputForMode:mode beforeDate:date];	// Wait, listening to our input sources.
#if 0
	NSLog(@"  acceptInputForMode done");
#endif
//	[self _checkPerformersAndTimersForMode:mode];	// check for any performers and timers to fire
#if 0
	NSLog(@"  _checkPerformersAndTimersForMode done");
#endif
	return YES;
}

- (void) runUntilDate:(NSDate *)date
{ // run until date handling timers
	volatile double ti = [date timeIntervalSinceNow];
#if 0
	NSLog(@"runUntilDate:%@", date);
#endif	
	while(ti > 0)	// Positive values are in the future.
		{
		NSAutoreleasePool *pool = [NSAutoreleasePool new];
		NSDate *d;
#if 0
		NSLog(@"NSRunLoop run until date %f seconds from now\n", ti);
#endif
		d=[self limitDateForMode:NSDefaultRunLoopMode];	// Determine time to wait before first limit date (i.e. the first timer)
#if 0
		NSLog(@"  limit date is %@", d);
#endif
		if(d)
			d=[d earlierDate:date];	// Use the earlier of the two dates we have.
		else
			d=date;	// no timers
		if(![self runMode:NSDefaultRunLoopMode beforeDate:d])	// block for input or next timer
			{ // no input sources 
			[pool release];
			break;
			}
		[pool release];
		ti = [date timeIntervalSinceNow];
		}
}

- (void) run				{ [self runUntilDate:[NSDate distantFuture]]; }
- (NSString*) currentMode	{ return _current_mode; }	// nil when !running
- (void) configureAsServer	{ return; }
- (NSMutableArray*) _timedPerformers			{ return _timedPerformers; }

- (void) cancelPerformSelectorsWithTarget:(id)target;
{
	int i = [_performers count];
	[target retain];
	while(i-- > 0)
		{
		_NSRunLoopPerformer *item = [_performers objectAtIndex:i];		
		if ([item matchesTarget:target])
			{
			[item invalidate];
			[_performers removeObjectAtIndex:i];
			}
		}
	[target release];
}

- (void) cancelPerformSelector:(SEL)aSelector
						target:target
						argument:argument
{
	int i = [_performers count];
	[target retain];
	[argument retain];
	while(i-- > 0)
		{
		_NSRunLoopPerformer *item = [_performers objectAtIndex:i];
		if ([item matchesSelector:aSelector target:target argument:argument])
			{
			[item invalidate];
			[_performers removeObjectAtIndex:i];
			}
		}
	[argument release];
	[target release];
}

- (void) performSelector:(SEL)aSelector
				  target:target
				  argument:argument
				  order:(unsigned int)order
				  modes:(NSArray*)modes
{
	_NSRunLoopPerformer *item;
	int i, count = [_performers count];
	item = [[_NSRunLoopPerformer alloc] initWithSelector: aSelector
									   target: target
									   argument: argument
									   order: order
									   modes: modes];

	if (count == 0)									// Add new item to list - 
		[_performers addObject:item];				// reverse ordering
	else
		{
		for (i = 0; i < count; i++)
			{
			if ([[_performers objectAtIndex:i] order] <= order)
				{
				[_performers insertObject:item atIndex:i];
				break;
				}
			}
		if (i == count)
			[_performers addObject:item];
		}
	[item release];	// should have been added or inserted
}

- (void) _addInputWatcher:(id) watcher forMode:(NSString *) mode;
{ // each observer should be added only once for each fd/mode - but this implementation takes care that it still works
	NSMutableArray *watchers = NSMapGet(_mode_2_inputwatchers, mode);
	NSAssert(mode != nil, @"trying to add input watcher for nil mode");
#if 0
	NSLog(@"_addInputWatcher:%@ forMode:%@", watcher, mode);
#endif
	if(!watchers)
		{ // first for this mode
		watchers = [NSMutableArray new];
		NSMapInsert(_mode_2_inputwatchers, mode, watchers);
		[watchers release];
		}
	[watchers addObject:watcher];
#if 0
	NSLog(@"watchers=%@", watchers);
#endif
}

- (void) _removeInputWatcher:(id) watcher forMode:(NSString *) mode;
{
	NSMutableArray *watchers = NSMapGet(_mode_2_inputwatchers, mode);
	NSAssert(mode != nil, @"trying to remove input watcher for nil mode");
#if 0
	NSLog(@"_removeInputWatcher:%@ forMode:%@", watcher, mode);
#endif
	if(watchers)
		{ // remove first one only!
		unsigned int idx=[watchers indexOfObjectIdenticalTo:watcher];
		if(idx != NSNotFound)
			[watchers removeObjectAtIndex:idx];	// remove only one instance!
		}
#if 0
	NSLog(@"watchers=%@", watchers);
#endif
}

- (void) _addOutputWatcher:(id) watcher forMode:(NSString *) mode;
{ // each observer should be added only once for each fd/mode
	NSMutableArray *watchers = NSMapGet(_mode_2_outputwatchers, mode);
	if(!watchers)
		{ // first for this mode
		watchers = [NSMutableArray new];
		NSMapInsert (_mode_2_outputwatchers, mode, watchers);
		[watchers release];
		}
	[watchers addObject:watcher];
}

- (void) _removeOutputWatcher:(id) watcher forMode:(NSString *) mode;
{
	NSMutableArray *watchers = NSMapGet(_mode_2_outputwatchers, mode);
#if 0
	NSLog(@"_removeOutputWatcher:%@ forMode:%@", watcher, mode);
#endif
	if(watchers)
		{ // remove first one only!
		unsigned int idx=[watchers indexOfObjectIdenticalTo:watcher];
		if(idx != NSNotFound)
			[watchers removeObjectAtIndex:idx];	// remove only one instance!
		}
}

- (void) _removeWatcher:(id) watcher;
{ // remove from all modes as input and as output watchers
	NSEnumerator *e;
	NSString *mode;
	e=[NSAllMapTableKeys(_mode_2_inputwatchers) objectEnumerator];
	while((mode=[e nextObject]))
		[(NSMutableArray *) NSMapGet(_mode_2_inputwatchers, mode) removeObjectIdenticalTo:watcher];		// removes all occurrences
	e=[NSAllMapTableKeys(_mode_2_outputwatchers) objectEnumerator];
	while((mode=[e nextObject]))
		[(NSMutableArray *) NSMapGet(_mode_2_outputwatchers, mode) removeObjectIdenticalTo:watcher];	// removes all occurrences
}

- (void) removePort:(NSPort *)aPort forMode:(NSString *)mode;
{ // we do this indirectly
	[aPort removeFromRunLoop:self forMode:mode];
}

- (void) addPort:(NSPort *)aPort forMode:(NSString *)mode;
{ // add default callbacks (if present)
	[aPort scheduleInRunLoop:self forMode:mode];
}

@end  /* NSRunLoop */


//*****************************************************************************
//
// 		NSObject (TimedPerformers) 
//
//*****************************************************************************

@implementation NSObject (TimedPerformers)

+ (void) cancelPreviousPerformRequestsWithTarget:(id) target;
{
	NSMutableArray *array = [[NSRunLoop currentRunLoop] _timedPerformers];
	int i=[array count];
#if 0
	NSLog(@"cancel target %@ for timed performers %@", target, array);
#endif
//	[target retain];
	while(i-- > 0)
		{
		_NSRunLoopPerformer *o = [array objectAtIndex:i];
		if([o matchesTarget:target])
			{
#if 0
			NSLog(@"cancelled all for %@", target);
#endif
			[o invalidate];
			[array removeObjectAtIndex:i];	// this will not yet release the performer since we are the retained target of the timer
			}
		}
//	[target release];
}

+ (void) cancelPreviousPerformRequestsWithTarget:(id)target
										selector:(SEL)aSelector
										object:(id)arg
{
	NSMutableArray *array = [[NSRunLoop currentRunLoop] _timedPerformers];
	int i=[array count];

//	[target retain];
//	[arg retain];
	while(i-- > 0)
		{
		_NSRunLoopPerformer *o = [array objectAtIndex:i];
		if([o matchesSelector:aSelector target:target argument:arg])
			{
#if 0
			NSLog(@"cancelled %@", NSStringFromSelector(aSelector));
#endif
			[o invalidate];
			[array removeObjectAtIndex:i];
			}
		}
//	[arg release];
//	[target release];
}

- (void) performSelector:(SEL)aSelector
	      	  withObject:(id)argument
	      	  afterDelay:(NSTimeInterval)seconds
{
	NSMutableArray *array = [[NSRunLoop currentRunLoop] _timedPerformers];
	_NSRunLoopPerformer *item;
#if 0
	NSLog(@"%@: %lf", NSStringFromSelector(_cmd), seconds);
#endif
	item = [[_NSRunLoopPerformer alloc] initWithSelector: aSelector
												  target: self
												argument: argument
												   order: 0
												   modes: nil];
	[array addObject: item];	// 1st retain
	[item setTimer: [NSTimer scheduledTimerWithTimeInterval: seconds
							 target: item	// we will be a 2nd time retained by the timer - and not vice versa
							 selector: @selector(fire)
							 userInfo: nil
							 repeats: NO]];
	[item release];
#if 0
	NSLog(@"%@ retainCount=%d", item, [item retainCount]);
#endif
}

- (void) performSelector:(SEL)aSelector
			  withObject:(id)argument
			  afterDelay:(NSTimeInterval)seconds
			  inModes:(NSArray*)modes
{
	int i, count;
	if ((modes != nil) && ((count = [modes count]) > 0))	// HNS
		{
		NSRunLoop *loop = [NSRunLoop currentRunLoop];
		NSMutableArray *array = [loop _timedPerformers];
		_NSRunLoopPerformer *item;
		NSTimer *timer;

		item = [[_NSRunLoopPerformer alloc] initWithSelector: aSelector
										   target: self
										   argument: argument
										   order: 0
										   modes: nil];
		[array addObject: item];	// first retain
		timer = [NSTimer timerWithTimeInterval: seconds
						 target: item	// second retain
						 selector: @selector(fire)
						 userInfo: nil
						 repeats: NO];
		[item setTimer: timer];
		[item release];
		// schedule timer in specified modes
		for (i = 0; i < count; i++)
			[loop addTimer: timer forMode: [modes objectAtIndex: i]];
		}
}

@end /* NSObject (TimedPerformers) */
