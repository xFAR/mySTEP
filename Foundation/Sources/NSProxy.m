/* 
   NSProxy.m

   Abstract class of objects that act as stand-ins for other objects

   Copyright (C) 1997 Free Software Foundation, Inc.

   Author:	Richard Frith-Macdonald <richard@brainstorm.co.uk>
   Date:	August 1997

   This file is part of the mySTEP Library and is provided
   under the terms of the GNU Library General Public License.
*/

#import <Foundation/NSInvocation.h>
#import <Foundation/NSProxy.h>
#import <Foundation/NSMethodSignature.h>
#import <Foundation/NSAutoreleasePool.h>
#import <Foundation/NSException.h>

#import "NSPrivate.h"

@implementation NSProxy

+ (id) allocWithZone:(NSZone *) z;	{ return (NSProxy *) NSAllocateObject(self, 0, z?z:NSDefaultMallocZone()); }
+ (id) alloc					{ return [self allocWithZone:NSDefaultMallocZone()]; }
- (NSZone *) zone;				{ return NSDefaultMallocZone(); }	// no zones implemented
+ (void) release				{ return; }
+ (id) autorelease				{ return self; }
+ (id) retain					{ return self; }
+ (Class) superclass			{ return class_getSuperclass(self); }
+ (Class) class					{ return self; }
+ (void) load					{ return; }

+ (NSString *) description
{
	return [NSString stringWithFormat: @"<@class %s>", class_getName(self)];
}

+ (BOOL) respondsToSelector:(SEL)aSelector
{
	return (class_getClassMethod(self, aSelector) != NULL);
}

+ (NSUInteger) retainCount		{ return UINT_MAX; }
- (NSUInteger) retainCount	{ return (((_object_layout)(self))[-1].retained)+1; }

// NOTE: it appears that init is not defined on OSX!

- (id) init						{ return self; }
- (id) copyWithZone:(NSZone *) zone	{ return [self retain]; }
- (id) self						{ return self; }
- (Class) superclass			{ return class_getSuperclass(object_getClass(self)); }
- (Class) class					{ return object_getClass(self); }
- (void) dealloc				{ NSDeallocateObject((NSObject*)self); }
- (void) finalize			{ return; }

- (id) autorelease
{
	[NSAutoreleasePool addObject:self];
	return self;
}

- (oneway void) release
{
	if (((_object_layout)(self))[-1].retained == 0)				// if ref count becomes zero (was 1)
			{
				((_object_layout)(self))[-1].retained--;
				[self dealloc];
			}
	else
		((_object_layout)(self))[-1].retained--;
}

- (id) retain
{
	((_object_layout)(self))[-1].retained++;
	return self;
}

#if 0	// forwarded automatically if we don't implement this here...
- (BOOL) conformsToProtocol:(Protocol*)aProtocol
{ // default: pack into a request and forward
	NSInvocation *inv;
	NSMethodSignature *sig;
	BOOL result;
//	sig = [self methodSignatureForSelector:@selector(conformsToProtocol:)];
	sig = [NSObject instanceMethodSignatureForSelector:@selector(conformsToProtocol:)];
	inv = [NSInvocation invocationWithMethodSignature:sig];
	[inv setSelector:@selector(conformsToProtocol:)];
	[inv setArgument:aProtocol atIndex:2];
	[self forwardInvocation:inv];
	[inv getReturnValue:&result];
	return result;
}
#endif

+ (BOOL) conformsToProtocol:(Protocol*)aProtocol;
{
//	NIMP;
	return NO;
}

- (NSString*) descriptionWithLocale:(id)locale indent:(NSUInteger)indent;
{ // called in decription of NSArray etc. - don't bother the distant object with that
	return [self descriptionWithLocale:locale];
}

- (NSString*) descriptionWithLocale:(id)locale;
{ // called in decription of NSArray etc. - don't bother the distant object with that
	return [self description];
}

- (NSString*) description
{
	return [NSString stringWithFormat: @"<%@ %lx>", NSStringFromClass([self class]), (unsigned long)self];
}

- (void) forwardInvocation:(NSInvocation*)anInvocation
{ // default NSProxy can't forward anything
	[NSException raise: NSInvalidArgumentException
				format:@"NSProxy can't forwardInvocation:%@", anInvocation];
}

// convert runtime forwarding arguments into NSInvocation

- (retval_t) forward:(SEL) aSel :(arglist_t) argFrame
{
	NSInvocation *inv;
#if 1
	NSLog(@"NSProxy %p forward:@selector(%p:%@) :... through %@", self, aSel, NSStringFromSelector(aSel), self);
#endif
	if(aSel == 0)
		[NSException raise:NSInvalidArgumentException
					format:@"NSProxy forward:: %@ NULL selector", NSStringFromSelector(_cmd)];
	// FIXME: Cocoa is said to discard the call if methodSignature returns nil - but how do we get a retval_t??
	// well, retval can be a pointer to a long[4] initialized to 0
	inv=[[NSInvocation alloc] _initWithMethodSignature:[self methodSignatureForSelector:aSel] andArgFrame:argFrame];
	if(!inv)
		{ // unknown to system
		[NSException raise:NSInvalidArgumentException
					format:@"NSProxy forward:: [%@ -%@]: selector not recognized", 
					NSStringFromClass([self class]), 
					NSStringFromSelector(aSel)];
		return nil;
		}
	[self forwardInvocation:inv];
#if 0
	NSLog(@"invocation forwarded. Returning result");
	NSLog(@"returnFrame=%08x", [inv _returnValue]);
#endif
	return [inv _returnValue];	// this also invalidates the argFrame
}

- (BOOL) isKindOfClass:(Class)aClass
{
	return _classIsKindOfClass([self class], aClass);
}

- (BOOL) isMemberOfClass:(Class)aClass		{ return ([self class] == aClass); }

- (id) _nimp:(SEL) cmd;
{
	[NSException raise:NSInvalidArgumentException
				format:@"*** %@[%@ %@]: not implemented",
					class_isMetaClass(object_getClass(self))?@"+":@"-",
		NSStringFromClass([self class]),
		NSStringFromSelector(cmd)];
	return nil;
}

- (id) notImplemented:(SEL)aSel
{
	return [self _nimp:aSel];
}

- (BOOL) isProxy							{ return YES; }
- (NSUInteger) hash						{ return (unsigned int)self; }

// which of these should be forwarded as well?

#if 0	// all these...
- (BOOL) isEqual:(id)anObject				{ return (self == anObject); }
#endif

- (NSMethodSignature *) methodSignatureForSelector:(SEL)aSelector
{ // default implementation raises exception
	[NSException raise: NSInvalidArgumentException format: @"-[NSProxy %s] called!", sel_getName(_cmd)];
	return nil;
}

#if 0	// simply forward as well
// FIXME: this does not properly forward!

- (id) performSelector:(SEL)aSelector
{
	IMP msg = objc_msg_lookup(self, aSelector);
	if(!msg)
		{
		[NSException raise: NSGenericException 
					 format: @"invalid selector passed to %s",
						sel_getName(_cmd)];
		return nil;
		}
	return (*msg)(self, aSelector);
}

- (id) performSelector:(SEL)aSelector withObject:(id)anObject
{
	IMP msg = objc_msg_lookup(self, aSelector);

	if(!msg)
		{
		[NSException raise: NSGenericException
					 format: @"invalid selector passed to %s",
								sel_getName(_cmd)];
		return nil;
		}
	return (*msg)(self, aSelector, anObject);
}

- (id) performSelector:(SEL)aSelector
	    withObject:(id)anObject
	    withObject:(id)anotherObject
{
	IMP msg = objc_msg_lookup(self, aSelector);

	if (!msg)
		{
		[NSException raise: NSGenericException
					 format: @"invalid selector passed to %s",
							sel_getName(_cmd)];
		return nil;
		}
	return (*msg)(self, aSelector, anObject, anotherObject);
}

- (BOOL) respondsToSelector:(SEL)aSelector
{
	return (class_getInstanceMethod(self, aSelector) != NULL);
//	[NSException raise: NSInvalidArgumentException format: @"-[NSProxy %s] called!", sel_getName(_cmd)];
//	return NO;
}
#endif

@end
