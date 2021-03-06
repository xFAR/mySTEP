/* 
 NSConnection.m
 
 Implementation of connection object for remote object messaging
 
 Copyright (C) 1994, 1995, 1996, 1997 Free Software Foundation, Inc.
 
 Created by:  Andrew Kachites McCallum <mccallum@gnu.ai.mit.edu>
 Date: July 1994
 OPENSTEP rewrite by: Richard Frith-Macdonald <richard@brainstorm.co.uk>
 Date: August 1997
 
 Changed to encode/decode NSInvocations:
 Dr. H. Nikolaus Schaller <hns@computer.org>
 Date: October 2003
 
 Complete rewrite:
 Dr. H. Nikolaus Schaller <hns@computer.org>
 Date: Jan 2006
 Some implementation expertise comes from from Crashlogs found on the Internet: Google for "Thread 0 Crashed dispatchInvocation" - and examples of "class dump"
 Everything else from good guessing and inspecting data that is exchanged
 Date: Oct 2009
 Heavily reworked to be more compatible to Cocoa
 Date: May 2012
 Debugged to be more compatible to Cocoa
 
 This file is part of the mySTEP Library and is provided
 under the terms of the GNU Library General Public License.
 
 */

#import <Foundation/NSRunLoop.h>
#import <Foundation/NSConnection.h>
#import <Foundation/NSDistantObject.h>

#import "NSPrivate.h"

#import <Foundation/NSPort.h>
#import <Foundation/NSPortCoder.h>
#import <Foundation/NSPortMessage.h>
#import <Foundation/NSHashTable.h>
#import <Foundation/NSMapTable.h>
#import <Foundation/NSData.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSValue.h>
#import <Foundation/NSString.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSException.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSThread.h>
#import <Foundation/NSNotification.h>
#import <Foundation/NSInvocation.h>
#import <Foundation/NSMethodSignature.h>

// for statstics...
NSString *NSConnectionRepliesReceived = @"NSConnectionRepliesReceived";
NSString *NSConnectionRepliesSent = @"NSConnectionRepliesSent";
NSString *NSConnectionRequestsReceived = @"NSConnectionRequestsReceived";
NSString *NSConnectionRequestsSent = @"NSConnectionRequestsSent";
// mySTEP extensions
// NSString *NSConnectionLocalCount = @"NSConnectionLocalCount";
// NSString *NSConnectionProxyCount = @"NSConnectionProxyCount";

NSString *const NSFailedAuthenticationException = @"NSFailedAuthenticationException";

#define FLAGS_INTERNAL	0x0e2ffee2	// have seen this only once

#define FLAGS_REQUEST	0x0e1ffeed
#define FLAGS_RESPONSE	0x0e2ffece

@implementation NSDistantObjectRequest (NSUndocumented)

- (id) initWithInvocation:(NSInvocation *) inv conversation:(NSObject *) conv sequence:(NSUInteger) seq importedObjects:(NSMutableArray *) obj connection:(NSConnection *) conn;
{ // private initializer
	if((self=[super init]))
		{
		_invocation=[inv retain];
		_conversation=[conv retain];
		_imports=[obj retain];
		_connection=[conn retain];
		_sequence=seq;
		}
	return self;
}

@end

@implementation NSDistantObjectRequest

- (NSConnection *) connection; { return _connection; }
- (id) conversation; { return _conversation; }
// - (NSMutableArray *) importedObjects; { return _imports; }
- (NSInvocation *) invocation; { return _invocation; }
// - (unsigned int) sequence; { return _sequence; }

- (void) dealloc;
{
	[_invocation release];
	[_conversation release];
	[_imports release];
	[_connection release];
	[super dealloc];
}

- (void) replyWithException:(NSException *) exception;
{
#if 1
	NSLog(@"replyWithException: %@", exception);
#endif
	[_connection returnResult:_invocation exception:exception sequence:_sequence imports:_imports];
}

@end

@implementation NSConcreteDistantObjectRequest

@end

NSString *const NSConnectionDidDieNotification=@"NSConnectionDidDieNotification";
NSString *const NSConnectionDidInitializeNotification=@"NSConnectionDidInitializeNotification";

@interface NSInvocation (private)
- (void) _log:(NSString *) str;
@end

@implementation NSConnection

// FIXME: _allConnections could/should use a NSMapTable keyed by a combination of receivePort and sendPort (e.g. string catenation)
// but as long as we just have a handful of connections, a linear search is probably faster than string operations

static NSHashTable *_allConnections;	// used as a cache
static id _currentConversation;

static NSUInteger _sequence;	// global sequence number

+ (NSArray *) allConnections;
{
#if 0
	NSLog(@"allConnections");
#endif
	return NSAllHashTableObjects(_allConnections);
}

+ (NSConnection *) connectionWithReceivePort:(NSPort *) receivePort
									sendPort:(NSPort *) sendPort;
{
	return [[[self alloc] initWithReceivePort:receivePort sendPort:sendPort] autorelease];
}

+ (NSConnection *) connectionWithRegisteredName:(NSString *) n
										   host:(NSString *) h;
{
	return [self connectionWithRegisteredName:n host:h usingNameServer:nil];
}

+ (NSConnection *) connectionWithRegisteredName:(NSString *)name
										   host:(NSString *)hostName
								usingNameServer:(NSPortNameServer *)server;
{
#if 0
	NSLog(@"connectionWithRegisteredName:%@ host:%@ usingNameServer:%@", name, hostName, server);
#endif
	if(!server)
		{
		if(hostName)
			server=[NSSocketPortNameServer sharedInstance];
		else
			server=[NSPortNameServer systemDefaultPortNameServer];
		}
#if 0
	NSLog(@"  ->server:%@", server);
#endif
	return [self connectionWithReceivePort:nil sendPort:[server portForName:name host:hostName]];
}

+ (id) currentConversation; { return _currentConversation; }

+ (NSConnection *) defaultConnection;
{ // there is one per thread
	static NSString *key=@"NSPerThreadConnection";
	NSMutableDictionary *dict=[[NSThread currentThread] threadDictionary];
	NSConnection *defaultConnection=[dict objectForKey:key];
	if(!defaultConnection)
		{ // allocate
			NSPort *port=[NSPort new];	// select port by system
			defaultConnection=[[self alloc] initWithReceivePort:port sendPort:port];
			[dict setObject:defaultConnection forKey:key];
			[port release];
			[defaultConnection release];
		}
	return defaultConnection;
}

+ (NSDistantObject *) rootProxyForConnectionWithRegisteredName:(NSString*)name
														  host:(NSString*)host;
{
	return [self rootProxyForConnectionWithRegisteredName:name host:host usingNameServer:nil];
}

+ (NSDistantObject *) rootProxyForConnectionWithRegisteredName:(NSString *)name
														  host:(NSString *)hostName
											   usingNameServer:(NSPortNameServer *)server;
{
	return [[self connectionWithRegisteredName:name host:hostName usingNameServer:server] rootProxy];
}

+ (id) serviceConnectionWithName:(NSString *) name rootObject:(id) root usingNameServer:(NSPortNameServer *) server;
{
	NSPort *port;
	NSConnection *connection;
#if 0
	NSLog(@"portNameServer=%@", server);
#endif
#if 0
	if([server isKindOfClass:NSClassFromString(@"NSMachBootstrapServer")])
		port=[NSMachPort port];		// assign free port
	else
#endif
	if([server isKindOfClass:[NSSocketPortNameServer class]])
		port=[NSSocketPort port];		// assign free IP port number
	else
		port=[NSMessagePort port];	// assign free port
	if(!port || ![server registerPort:port name:name])	// register
		return nil;	// did not register
	connection=[NSConnection connectionWithReceivePort:port sendPort:nil];	// create connection
	[connection setRootObject:root];
	return connection;
}

+ (id) serviceConnectionWithName:(NSString *) name rootObject:(id) root;
{
	return [self serviceConnectionWithName:name rootObject:root usingNameServer:[NSPortNameServer systemDefaultPortNameServer]];
}

/*
 * CHECKME:
 * basically we receive responses that we did send on our send-port (!)
 * and if the peer sends us a request, we will also receive it on our send-port
 * the receive-port is only for new connections
 * so it could be sufficient to schedule the send-port (!) only - which is the same as the receive-port if we are vended as a connection endpoint
 */

- (void) addRequestMode:(NSString *) mode;
{ // schedule additional mode in all known runloops
#if 0
	NSLog(@"addRequestMode %@ to %@", mode, _modes);
#endif
	NSEnumerator *e=[_runLoops objectEnumerator];
	NSRunLoop *runLoop;
	[_modes addObject:mode];
	while((runLoop=[e nextObject]))
		{
		[_receivePort addConnection:self toRunLoop:runLoop forMode:mode];
		if(_receivePort != _sendPort)
			[_sendPort addConnection:self toRunLoop:runLoop forMode:mode];
		}
}

- (void) addPortsToRunLoop:(NSRunLoop *) runLoop
{
	NSEnumerator *e=[_modes objectEnumerator];
	NSString *mode;
	[_receivePort addConnection:self toRunLoop:runLoop forMode:NSConnectionReplyMode];	
	while((mode=[e nextObject]))
		[_receivePort addConnection:self toRunLoop:runLoop forMode:mode];	
	if(_receivePort != _sendPort)
		{
		[_sendPort addConnection:self toRunLoop:runLoop forMode:NSConnectionReplyMode];	
		while((mode=[e nextObject]))
			[_sendPort addConnection:self toRunLoop:runLoop forMode:mode];	
		}
}

- (void) addRunLoop:(NSRunLoop *) runLoop;
{ // schedule in new runloop in all known modes
#if 0
	NSLog(@"addRunLoop: %@ to %@", runLoop, _runLoops);
#endif
	if(![_runLoops containsObject:runLoop])
		{
			NSEnumerator *e=[_modes objectEnumerator];
			NSString *mode;
			[_runLoops addObject:runLoop];
			while((mode=[e nextObject]))
				{
				[_receivePort addConnection:self toRunLoop:runLoop forMode:mode];
				if(_receivePort != _sendPort)
					[_sendPort addConnection:self toRunLoop:runLoop forMode:mode];
				}
		}
}

- (id) delegate; { return _delegate; }
- (void) enableMultipleThreads; { _multipleThreadsEnabled=YES; }
- (BOOL) independentConversationQueueing; { return _independentConversationQueueing; }

/*
 * receivePort: on this port we can receive requests from some other NSConnection
 *   i.e. we vend our rootObject and return responses to incoming requests
 *   all scheduling methods control the receivePort
 *
 * sendPort: on this port, we send out invocations to some other NSConnection
 *   i.e. we ask for its rootProxy and reveice repsonses for outgoing requests
 *   this port is (temporarily) scheduled in NSConnectionReplyMode
 *
 * if sendPort == nil or sendPort == receivePort, we are only serving (vending)
 *   a rootObject
 *
 * if receivePort == nil, we are a pure client and create a (unpublished)
 *   receivePort of the same class
 *
 * in summary: send/receive does not refer to the transmission direction of
 *   the underlaying NSPortMessages but for distributed object messages and
 *   NSConnection setup
 */

- (id) initWithReceivePort:(NSPort *)receivePort
				  sendPort:(NSPort *)sendPort;
{
#if 1	// disable DO
	[self release];
	return nil;
#endif
#if 0
	NSLog(@"NSConnection -initWithReceivePort:%@ sendPort:%@", receivePort, sendPort);
	NSLog(@"existing connections: %@", [NSConnection allConnections]);
	[NSInvocation class];	// run +initialize
#endif
	if((self=[super init]))
		{
		NSNotificationCenter *nc=[NSNotificationCenter defaultCenter];
		NSConnection *c;
		Class sc=[self class];
		if(!sendPort)
			{
			if(!receivePort)
				{ // neither port is defined
#if 1
					NSLog(@"NSConnection -init: two nil ports detected (recv=%@ send=%@)", receivePort, sendPort);
#endif
					[self release];
					return nil;
				}
			sendPort=receivePort;	// make same
			}
		else if(!receivePort)
			{
			receivePort=[[[sendPort class] new] autorelease];
			NSLog(@"new receivePort: %@", receivePort);
			}
		if((c=[sc lookUpConnectionWithReceivePort:receivePort sendPort:sendPort]))
			{ // already exists
#if 0
				NSLog(@"NSConnection -init: connection exists");
#endif
				/* check for new thread
				 if(_multipleThreadsEnabled)
				 {
				 if(![self hasRunloop:rl])
				 [self addRunLoop:rl];
				 }
				*/
				[self release];
				return [c retain];	// use existing object
			}
		else if((c=[sc lookUpConnectionWithReceivePort:sendPort sendPort:receivePort]))
			{ // reverse direction exists
#if 1
				NSLog(@"NSConnection -init: reverse connection exists; not implemented");
#endif
				// _isLocal=YES;	// enable local communication/forwarding
				// _forward=[c retain];
				[self release];
				return nil;
			}
		else if(receivePort != sendPort && (c=[sc lookUpConnectionWithReceivePort:receivePort sendPort:receivePort]))
			{ // parent connection exists - copy root object and all configs
#if 0
				NSLog(@"NSConnection -init: parent connection exists, make new connection");
#endif
				// FIXME: which one is correct?
				if([_delegate respondsToSelector:@selector(connection:shouldMakeNewConnection:)] &&
				   ![_delegate connection:c shouldMakeNewConnection:self])
					{ // did veto
						[self release];
						return nil;
					}
				if(([_delegate respondsToSelector:@selector(connection:shouldMakeNewConnection:)] &&
					![_delegate connection:self shouldMakeNewConnection:c])	// preferred delegate method
				   ||
				   ([_delegate respondsToSelector:@selector(makeNewConnection:sender:)] &&
					![_delegate makeNewConnection:c sender:self]))	// this appears to be deprecated
					{ // did veto
						[self release];
						return nil;
					}
				_receivePort=[receivePort retain];
				_sendPort=[sendPort retain];
				_rootObject=[c->_rootObject retain];
				_delegate=c->_delegate;
				_modes=[c->_modes mutableCopy];		// we share the receivePort which is already scheduled in these modes and runloops
				_runLoops=[c->_runLoops mutableCopy];
				_requestTimeout=c->_requestTimeout;
				_replyTimeout=c->_replyTimeout;
				_replyTimeout=c->_replyTimeout;
				_multipleThreadsEnabled=c->_multipleThreadsEnabled;
				_independentConversationQueueing=c->_independentConversationQueueing;
				// _isLocal=c->_isLocal;
			}
		else
			{
#if 0
			NSLog(@"really new connection");
#endif
			_receivePort=[receivePort retain];
			_sendPort=[sendPort retain];
			_modes=[[NSMutableArray alloc] initWithCapacity:10];
			_runLoops=[[NSMutableArray alloc] initWithCapacity:10];
			_replyTimeout=_requestTimeout=99999999.0;	// set defaults
			_multipleThreadsEnabled=NO;
			_independentConversationQueueing=NO;
#if 0
			NSLog(@"schedule receive port %@", _receivePort);
#endif
			[self addRequestMode:NSDefaultRunLoopMode];		// schedule receive port in current runloop
			[self addRunLoop:[NSRunLoop currentRunLoop]];
			}
		[_receivePort setDelegate:_receivePort];		// make receivePort process handlePortMessage
		// shouldn't we also observe the receivePort?
		[nc addObserver:self selector:@selector(_portInvalidated:) name:NSPortDidBecomeInvalidNotification object:_sendPort];	// if we can't send any more
		_isValid=YES;
		// or should we be retained by all proxy objects???
		[self retain];	// make us persistent at least until we are invalidated
		// FIXME: how do we manage memory? we retain a NSDistantObject as soon as we have vended it once since we don't know
		// when the peer finally releases the last handle
		// I have not seen that any retain/release messages are exchanged
		// and although the NSDistantObject has a flag of unknown meaning, it is not sure that it is indeed a "keep alive" flag
		// so we retain any vended object here and it will only disappear if the client closes the connection
//		_localObjects=NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 10);	// don't retain local proxies
		_localObjects=NSCreateMapTable(NSNonRetainedObjectMapKeyCallBacks, NSObjectMapValueCallBacks, 10);	// retain local proxies
		_localObjectsByRemote=NSCreateMapTable(NSIntMapKeyCallBacks, NSNonRetainedObjectMapValueCallBacks, 10);	// don't retain local proxies
		// for remote objects is is different: we can retain them if we need to send them back
		// and we can release them if we don't need them any more
		// if the client decides to send it to us another time, we simply create a new "token" proxy
		_remoteObjects=NSCreateMapTable(NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 10);	// retain remote proxies
		_responses=NSCreateMapTable(NSIntMapKeyCallBacks, NSObjectMapValueCallBacks, 10);	// map sequence number to response portcoder
		if(!_allConnections)
			_allConnections=NSCreateHashTable(NSNonOwnedPointerHashCallBacks, 10);	// allocate - don't retain connections in hash table
		NSHashInsertKnownAbsent(_allConnections, self);	// add us to connections list
#if 0
		NSLog(@"new NSConnection: %p send=%p recv=%p", self, _sendPort, _receivePort);
#endif
		[nc postNotificationName:NSConnectionDidInitializeNotification object:self];
#if 0
		NSLog(@"initialized: %p:%@", self, self);
#endif
		}
	return self;
}

- (id) init;
{ // init with default ports
	NSPort *port=[NSPort new];
#if 0
	NSLog(@"NSConnection -init: port=%@", port);
#endif
	self=[self initWithReceivePort:port sendPort:port];	// make a connection for vending objects
	[port release];
	return self;
}

#if 0
- (void) release;
{
	NSLog(@"release %p %u:%@", self, [self retainCount], self);
	[super release];
}
#endif

- (void) dealloc;
{
#if 0
	NSLog(@"dealloc %p:%@", self, self);
#endif
	if(_isValid)
		{ // this should not really occur since we are retained as an observer as long as we are valid!
			NSLog(@"dealloc without invalidate: %p %@", self, self);
			abort();
			[self invalidate];		
		}
#if 0
	NSLog(@"proxy connection: %p", _proxy);
	NSLog(@"local objects: %p", _localObjects);
	NSLog(@"local objects: %p", NSAllHashTableValues(_localObjects));
	NSLog(@"local objects count: %u", NSCountMapTable(_localObjects));
	NSLog(@"remote objects: %p", _remoteObjects);
	NSLog(@"remote objects count: %u", NSCountMapTable(_remoteObjects));
	NSLog(@"remote objects: %@", NSAllHashTableValues(_remoteObjects));
#endif
	//	[_proxy release];
	// this could also be done in invalidate
	if(_localObjects)
		{
		NSLog(@"local objects=%@", NSAllMapTableValues(_localObjects));
		NSAssert(NSCountMapTable(_localObjects) == 0, @"local objects still use this connection"); // should be empty before we can be released...
		NSFreeMapTable(_localObjects);
		NSFreeMapTable(_localObjectsByRemote);
		}
	if(_remoteObjects)
		{
		NSLog(@"remote objects=%@", NSAllMapTableValues(_remoteObjects));
		NSAssert(NSCountMapTable(_remoteObjects) == 0, @"remote objects still use this connection"); // should be empty before we can be released...
		NSFreeMapTable(_remoteObjects);
		}
	if(_responses) NSFreeMapTable(_responses);
	// releasing from all modes/runloops automatically unschedules the port!
	[_modes release];
	[_runLoops release];
	// [_delegate release];	// not retained
	[_receivePort release];	// we are already removed as receivePort observer by -invalidate
	[_sendPort release];
	[_rootObject release];
	[_requestQueue release];
	[super dealloc];
}

- (NSString *) description;
{
	return [NSString stringWithFormat:@"%p:%@\n  recv=%@\n  send=%@\n  root=%@\n  delegate=%@\n  modes=%@\n  runLoops=%@\n  req=%.2lf\n  reply=%.2lf\n  flags:%@%@%@",
			self,
			NSStringFromClass(object_getClass(self)),
			_receivePort,
			_sendPort,
			_rootObject,
			_delegate,
			_modes,
			_runLoops,
			_requestTimeout, _replyTimeout,
			_multipleThreadsEnabled?@" multiple-threads":@"",
			_isValid?@" valid":@"",
			_independentConversationQueueing?@" indep-queueing":@""
			];
}

- (void) invalidate;
{
	NSUInteger cnt;
#if 0
	NSLog(@"invalidate %p:%@ (_isValid=%d)", self, self, _isValid);
#endif
	if(!_isValid)
		return;	// already invalidated
	_isValid=NO;	// don't loop through notifications...
	[[NSNotificationCenter defaultCenter] removeObserver:self name:NSPortDidBecomeInvalidNotification object:_sendPort];
	cnt=[_runLoops count];
	while(cnt-- > 0)
		{ // can't enumerate if we remove objects from the array
		NSRunLoop *rl=[_runLoops objectAtIndex:cnt];
		[_sendPort removeFromRunLoop:rl forMode:NSConnectionReplyMode];		
		[self removeRunLoop:rl];
		}
#if 0
	NSLog(@"send NSConnectionDidDieNotification for %p:%@", self, self);
#endif
	[[NSNotificationCenter defaultCenter] postNotificationName:NSConnectionDidDieNotification object:self];
	if(_responses)
		NSFreeMapTable(_responses);
	_responses=nil;
	[_receivePort release];
	_receivePort=nil;		// we don't need it any more
	[_sendPort release];
	_sendPort=nil;
	if(_allConnections)
		NSHashRemove(_allConnections, self);	// remove us from the connections table
#if 1
	NSLog(@"NSConnection did invalidate %p", self);
#endif
	[self release];	// this will dealloc when all other retains (e.g. in NSDistantObject) are done
}

- (BOOL) isValid; { return _isValid; }

- (NSArray *) localObjects; { return NSAllMapTableKeys(_localObjects); }	// the objects and not the proxies

- (NSArray *) remoteObjects; { return NSAllMapTableValues(_remoteObjects); }

- (BOOL) multipleThreadsEnabled; { return _multipleThreadsEnabled; }

- (NSPort *) receivePort; { return _receivePort; }

- (BOOL) registerName:(NSString *)name; { return [self registerName:name withNameServer:nil]; }

- (BOOL) registerName:(NSString *)name withNameServer:(NSPortNameServer *)server;
{
	if(!_isValid)
		return NO;
	if(!server)
		server=[NSPortNameServer systemDefaultPortNameServer];
	if(![server registerPort:_receivePort name:name])
		{
		NSLog(@"can't register name %@ with portnameserver (may be registered by other process)", name);
		return NO;
		}
	return YES;
}

- (void) removeRequestMode:(NSString*)mode;
{
	NSEnumerator *e=[_runLoops objectEnumerator];
	NSRunLoop *runLoop;
	while((runLoop=[e nextObject]))
		{
		[_receivePort removeConnection:self fromRunLoop:runLoop forMode:mode];
		if(_receivePort != _sendPort)
			[_sendPort removeConnection:self fromRunLoop:runLoop forMode:mode];
		}
	[_modes removeObject:mode];
}

- (void) removePortsFromRunLoop:(NSRunLoop *) runLoop
{
	NSEnumerator *e=[_modes objectEnumerator];
	NSString *mode;
	[_receivePort removeConnection:self fromRunLoop:runLoop forMode:NSConnectionReplyMode];	
	while((mode=[e nextObject]))
		[_receivePort removeConnection:self fromRunLoop:runLoop forMode:mode];	
	if(_receivePort != _sendPort)
		{
		[_sendPort removeConnection:self fromRunLoop:runLoop forMode:NSConnectionReplyMode];	
		while((mode=[e nextObject]))
			[_sendPort removeConnection:self fromRunLoop:runLoop forMode:mode];	
		}
}

- (void) removeRunLoop:(NSRunLoop *)runLoop;
{
	if([_runLoops containsObject:runLoop])
		{ // remove from all modes
			NSEnumerator *e=[_modes objectEnumerator];
			NSString *mode;
			while((mode=[e nextObject]))
				{
				[_receivePort removeConnection:self fromRunLoop:runLoop forMode:mode];
				if(_receivePort != _sendPort)
					[_sendPort removeConnection:self fromRunLoop:runLoop forMode:mode];
				}
			[_runLoops removeObject:runLoop];
		}
}

- (NSTimeInterval) replyTimeout; { return _replyTimeout; }

- (NSArray *) requestModes; { return _modes; }

- (NSTimeInterval) requestTimeout; { return _requestTimeout; }

- (id) rootObject;
{
#if 0
	NSLog(@"*** asked for rootObject:");
	NSLog(@"***   self=%p", self);
	NSLog(@"***   _cmd=%p", _cmd);
	NSLog(@"***   rootObject=%p", _rootObject);
	NSLog(@"***   connections=%@", [NSConnection allConnections]);
#endif
	NSAssert(self != nil, @"self is not set correctly; NSInvocation may be broken");
	return _rootObject;
}

- (NSDistantObject *) rootProxy;
{ // this generates a proxy
	NSConnection *conn=(NSConnection *) [NSDistantObject proxyWithTarget:(id) 0 connection:self];	// get first remote object (id == 0) which represents the NSConnection
	NSDistantObject *proxy=[conn rootObject];	// this ends up in forwardInvocation: and asks other side for a reference to their root object
#if 0
	NSLog(@"root object: %p", proxy);
#endif
#if 0	// for unknown reasons this may also ask _localClassNameForClass from the result
	// this may also be a side-effect of actively using the proxy the first time by NSLog(@"proxy=%@", proxy);
	[proxy _localClassNameForClass];
#endif
	return proxy;
}

- (void) runInNewThread;
{
	if(!_isValid)
		return;	// rise exception?
	[self removeRunLoop:[NSRunLoop currentRunLoop]];
	[NSThread detachNewThreadSelector:@selector(_executeInNewThread) toTarget:self withObject:nil];
}

- (NSPort *) sendPort; { return _sendPort; }
- (void) setDelegate:(id) anObj; { _delegate=anObj; }

- (void) setIndependentConversationQueueing:(BOOL) flag;
{
	_independentConversationQueueing=flag;
	if(flag)
		NIMP;	// FIXME!
}

- (void) setReplyTimeout:(NSTimeInterval)seconds; { _replyTimeout=seconds; }
- (void) setRequestTimeout:(NSTimeInterval)seconds; { _requestTimeout=seconds; }

- (void) setRootObject:(id) anObj;
{
	ASSIGN(_rootObject, anObj);
	if(anObj)
		[self addPortsToRunLoop:[_runLoops objectAtIndex:0]];	// checkme - loop over all???
	else
		[self removePortsFromRunLoop:[_runLoops objectAtIndex:0]];	// checkme - loop over all???
}

- (NSDictionary *) statistics;
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			[NSNumber numberWithUnsignedInt:_repliesReceived], @"NSConnectionRepliesReceived",
			[NSNumber numberWithUnsignedInt:_repliesSent], @"NSConnectionRepliesSent",
			[NSNumber numberWithUnsignedInt:_requestsReceived], @"NSConnectionRequestsReceived",
			[NSNumber numberWithUnsignedInt:_requestsSent], @"NSConnectionRequestsSent",
			nil
			];
}

@end

@implementation NSConnection (NSUndocumented)

// found in http://opensource.apple.com/source/objc4/objc4-371/runtime/objc-sel-table.h

// private methods
// all of them have been identified to exist in MacOS X Core Dumps
// by Googling for 'NSConnection core dump'
// or class-dumps found on the net

// according to http://www.cocoabuilder.com/archive/cocoa/225353-distributed-objects-with-garbage-collection-on-ppc.html
// these also seem to set up and tear down the runloop scheduling

- (void) _incrementLocalProxyCount
{
	if(_localProxyCount == 0)
		NSLog(@"first local proxy created");
	_localProxyCount++;
}

- (void) _decrementLocalProxyCount 
{
	_localProxyCount--;
	if(_localProxyCount == 0)
		NSLog(@"last local proxy destroyed");
}

+ (NSConnection *) lookUpConnectionWithReceivePort:(NSPort *) receivePort
										  sendPort:(NSPort *) sendPort;
{ // look up if we already know this connection
	// FIXME: this should use a NSMapTable with struct { NSPort *recv, *send; } as key/hash
	// but as long as we just have 2-3 connection objects this does not really matter
	if(_allConnections)
		{
		NSHashEnumerator e=NSEnumerateHashTable(_allConnections);
		NSConnection *c;
		while((c=(NSConnection *) NSNextHashEnumeratorItem(&e)))
			{
			if([c receivePort] == receivePort && [c sendPort] == sendPort)
				return c;	// found!
			}
		}
	return nil;	// not found
}

- (void) _executeInNewThread;
{
	NSRunLoop *crlp=[NSRunLoop currentRunLoop];
#if 1
	NSLog(@"_executeInNewThread");
#endif
	// anything else to set up?
	[self addRunLoop:crlp];
	[crlp run];	// and run in separate thread to await incoming connections and requests
	NSLog(@"_executeInNewThread run finished");
}

- (void) _portInvalidated:(NSNotification *) n;
{
#if 1
	NSLog(@"_portInvalidated: %@", n);
#endif
	[self invalidate];
}

- (id) newConversation;
{ // ask delegate or DIY
	// FIXME: how does the currentConversation work?
	if([_delegate respondsToSelector:@selector(createConversationForConnection:)])
		_currentConversation=[_delegate createConversationForConnection:self];	// we have to assume that it is ***not*** autoreleased!
	else
		_currentConversation=[NSObject new];
	return _currentConversation;
}

- (NSPortCoder *) portCoderWithComponents:(NSArray *) components
{
	return [[[NSPortCoder alloc] initWithReceivePort:_receivePort
											sendPort:_sendPort
										  components:components] autorelease];
}

// FIXME: what do we do with the 'internal' flag?
// IDEA: it may modify exception handling
// and it may be used when sening a methodDescription request

- (void) sendInvocation:(NSInvocation *) i internal:(BOOL) internal;
{ // send invocation and handle result - this might be called reentrant!
	BOOL isOneway=NO;
	NSRunLoop *rl=[NSRunLoop currentRunLoop];
	//	unsigned long flags=internal?FLAGS_INTERNAL:FLAGS_REQUEST;
	unsigned long flags=FLAGS_REQUEST;
	NSPortCoder *portCoder;
#if 1	// special logging
	NSLog(@"*** (conn=%p) sendInvocation:%@", self, i);
#if 1
	[i _log:@"sendInvocation"];	// log incl. stack
	{
	NSMethodSignature *sig=[i methodSignature];
	NSUInteger cnt=[sig numberOfArguments];
	int j;
	for(j=0; j<cnt; j++)
		{
		const char *type=[sig getArgumentTypeAtIndex:j];
		if(*type == _C_ID)
			{
			id val;
			[i getArgument:&val atIndex:j];
			NSLog(@"%u: %@", j, val);
			}
		else
			NSLog(@"%u: %s", j, type);
		}
	}
#endif
#endif
#if 0
	printf("i: %s\n", [[self description] UTF8String]);
#endif
	
	NSAssert(i, @"missing invocation to send");
	/*	if(_isLocal)
	 { // we have been initialized with reversed ports, i.e. local connection
	 [i invoke];
	 return;
	 }
	 */
	isOneway=[[i methodSignature] isOneway];
	portCoder=[self portCoderWithComponents:nil];	// for encoding
	[portCoder encodeValueOfObjCType:@encode(unsigned long) at:&flags];
	++_sequence;	// we will wait for a response to appear...
	[portCoder encodeValueOfObjCType:@encode(unsigned long) at:&_sequence];
	[portCoder encodeObject:i];		// encode invocation
	// FINDME: what is this? Is this part of encoding an NSInvocation?
	[portCoder encodeObject:nil];
	[portCoder encodeObject:nil];
	[self finishEncoding:portCoder];	// should add authentication
	NS_DURING
	[self retain];	// otherwise we may be deallocated by -invalidate
#if 0
	NSLog(@"*** (conn=%p) send request to %@", self, [portCoder _sendPort]);
#endif
#if 0
	NSLog(@"timeIntervalSinceReferenceDate=%f", [NSDate timeIntervalSinceReferenceDate]);
	NSLog(@"time=%f", [NSDate timeIntervalSinceReferenceDate]+_requestTimeout);
#endif
	[_sendPort addConnection:self toRunLoop:rl forMode:NSConnectionReplyMode];	// schedule the send port so that we can receive from it
	// is the previous delegate restored?
	[_sendPort setDelegate:_receivePort];	// make us handlePortMessage: (implemented in NSPortCoder)
	[portCoder sendBeforeTime:[NSDate timeIntervalSinceReferenceDate]+_requestTimeout sendReplyPort:/*YES*/NO];		// encode and send - raises exception on timeout
	_requestsSent++;
	[portCoder invalidate];	// release internal memory immediately
	if(!isOneway)
		{ // wait for response to arrive (it may already have arrived since sendBeforeTime also runs the loop in NSConnectionReplyMode)
			NSDate *until=[NSDate dateWithTimeIntervalSinceNow:_replyTimeout];
			NSException *ex;
#if 0
			NSLog(@"*** (conn=%p) waiting for response before %@ in runloop %@ from %@", self, [NSDate dateWithTimeIntervalSinceNow:_replyTimeout], rl, _receivePort);
#endif
			while(YES)	// loop until we can extract a matching response for our sequence number from the receive queue...
				{ // not yet timed out and current conversation is not yet completed
#if 0
					NSLog(@"*** (conn=%p) loop for response %u in %@ at %@: %@", self, _sequence, NSConnectionReplyMode, _receivePort, rl);
#endif
					if(![self isValid])
						[NSException raise:NSPortReceiveException format:@"NSConnection became invalid"];						
					if(![_sendPort isValid])
						[NSException raise:NSPortReceiveException format:@"sendInvocation: receive port became invalid"];						
					portCoder=NSMapGet(_responses, (const void *) _sequence);
					if(portCoder)
						{ // the response we are waiting for has arrived!
							[portCoder retain];	// we will need it for a little time...
							NSMapRemove(_responses, (const void *) _sequence);
							break;	// break the loop and decode the response
						}
					if(![rl runMode:NSConnectionReplyMode beforeDate:until])
						[NSException raise:NSPortReceiveException format:@"sendInvocation: receive runloop error"];
#if 0
					NSLog(@"responses %@", NSAllMapTableValues(_responses));
#endif
					if([until timeIntervalSinceNow] < 0)
						[NSException raise:NSPortTimeoutException format:@"did not receive response within %.0f seconds", _replyTimeout];
				}
#if 0
			NSLog(@"*** (conn=%p) runloop done for mode: %@", self, NSConnectionReplyMode);
#endif
#if 0
			NSLog(@"decode response from: %@ -> %@", portCoder);
#endif
			// FIXME: align with returnResult:
			ex=[portCoder decodeObject];	// what is this? most likely the Exception to raise
#if 0
			NSLog(@"ex=%@", ex);
#endif
			[portCoder decodeReturnValue:i];	// decode return value into our original invocation
			// FIXME: is there another object to be decoded? the inout list?
			if(![portCoder verifyWithDelegate:_delegate])
				{
				[portCoder release];
				[NSException raise:NSFailedAuthenticationException format:@"authentication of response failed"];				
				}
			[portCoder invalidate];
			[portCoder release];
			[ex raise];	// if there is something to raise...
		}
	else
		{
#if 0
		NSLog(@"no need to wait for response because it is a oneway method call");
#endif
		}
	[_sendPort removeFromRunLoop:rl forMode:NSConnectionReplyMode];
	[self release];
	NS_HANDLER
	NSLog(@"Exception in sendInvocation %@: %@", i, [localException reason]);
	[_sendPort removeFromRunLoop:rl forMode:NSConnectionReplyMode];
	[self release];
	[localException raise];		// re-raise exception
	NS_ENDHANDLER
}

- (void) sendInvocation:(NSInvocation *) i;
{
	[self sendInvocation:i internal:NO];
}

- (void) handlePortCoder:(NSPortCoder *) coder;
{ // request received on this connection
	NSAutoreleasePool *arp=[NSAutoreleasePool new];
	unsigned int flags;
	NSUInteger seq;
#if 0
	NSLog(@"%p: handlePortCoder: %@", self, coder);
#endif
	NS_DURING
	[coder decodeValueOfObjCType:@encode(unsigned int) at:&flags];
#if 0
	NSLog(@"found flag = %d 0x%08x", flags, flags);
#endif
	[coder decodeValueOfObjCType:@encode(unsigned int) at:&seq];	// that is sequential (0, 1, ...)
#if 0
	NSLog(@"%p: found seq number = %d", self, seq);
#endif
	switch(flags) {
		case FLAGS_INTERNAL:	// connection setup (just allocates this NSConnection)
			break;
		case FLAGS_REQUEST:	// request received
			_requestsReceived++;
			[self handleRequest:coder sequence:seq];
			break;
		case FLAGS_RESPONSE:	// response received
			_repliesReceived++;
			NSMapInsert(_responses, (void *) seq, (void *) coder);	// put response into sequence queue/dictionary
			NSLog(@"%p: response queued %lu", self, (unsigned long)seq);
			break;
		default:
			NSLog(@"%p: unknown flags received: %08x", self, flags);
	}
	NS_HANDLER
	NSLog(@"Exception in handlePortCoder: %@", localException);
	NS_ENDHANDLER
	[arp release];
}

- (void) handleRequest:(NSPortCoder *) coder sequence:(NSInteger) seq;
{ // what can/should we do with the sequence number? This is used to keep the order when queueing requests
	NSInvocation *inv;
	NSException *exception;	// exception response (an NSException created in the current ARP)
	id imports=nil;
	NSMethodSignature *sig;
	NSDistantObjectRequest *req;
	BOOL enqueue;
	BOOL isOneway=NO;
#if 0
	NSLog(@"handleRequest (seq=%d): %@", seq, coder);
	NSLog(@"message=%@", [[coder components] objectAtIndex:0]);
#endif	
	inv=[coder decodeObject];	// ?? could not confirm recently: the first remote call for [client rootProxy] passes nil here (to establish the connection?)
	if(inv)
		{
		NSMethodSignature *tsig;
		sig=[inv methodSignature];	// how the invocation was initialized
#if 0
		NSLog(@"inv.argumentsRetained=%@", [inv argumentsRetained]?@"yes":@"no");
		NSLog(@"inv.selector='%@'", NSStringFromSelector([inv selector]));
		NSLog(@"inv.target=%p", [inv target]);	// don't try to call any method on the target here since it is a NSDistantObject...
		NSLog(@"inv.target.class=%@", NSStringFromClass([[inv target] class]));
		NSLog(@"inv.methodSignature.numberOfArguments=%d", [[inv methodSignature] numberOfArguments]);
		NSLog(@"inv.methodSignature.methodReturnLength=%d", [[inv methodSignature] methodReturnLength]);
		NSLog(@"inv.methodSignature.frameLength=%d", [[inv methodSignature] frameLength]);
		NSLog(@"inv.methodSignature.isoneway=%d", [[inv methodSignature] isOneway]);
		NSLog(@"inv.methodSignature.methodReturnType=%s", [[inv methodSignature] methodReturnType]);
#endif
		// here, we can decode up to 3 more objects until the coder reports no more data
		// they may have to do something with the current conversation and/or with the importedObjects
		// but I don't know yet.
		NS_DURING
		NSLog(@"1st extra %@", [coder decodeRetainedObject]);	// one more?
		// 2nd has been seen missing in test code where last decodeRetainedObject did have flag3=0 
		NSLog(@"2nd extra %@", [coder decodeRetainedObject]);	// one more?
		//			NSLog(@"3rd %@", [coder decodeRetainedObject]);	// one more?
		NS_HANDLER
		NSLog(@"decoding exception: %@", localException);
		NS_ENDHANDLER
		// it appears that this has been found in some stack traces
#if WHAT_DO_WE_NEED_THIS_FOR
		isOneway=[sig isOneway];
		// shouldn't we skip enqueueing if it isOneway?
#endif
		// CHECKME: do we really need to check that by creating yet another methodSignature object???
		tsig=[[inv target] methodSignatureForSelector:[inv selector]];
		if(![sig isEqual:tsig])
			NSLog(@"signature mismatch: %@ vs. %@", sig, tsig); // should raise exception: local method signature is different from remote
		[self _cleanupAndAuthenticate:coder sequence:seq conversation:&_currentConversation invocation:inv raise:YES];
		}
	enqueue=![self _shouldDispatch:&_currentConversation invocation:inv sequence:seq coder:coder];	// this will allocate the conversation if needed and tell if we should dispatch immediately
//#if __APPLE__
	req=[[NSConcreteDistantObjectRequest alloc] initWithInvocation:inv conversation:_currentConversation sequence:seq importedObjects:imports connection:self];
//#else
//	req=[[NSDistantObjectRequest alloc] initWithInvocation:inv conversation:_currentConversation sequence:seq importedObjects:imports connection:self];
//#endif
	if(enqueue)
		{ //should not dispatch, i.e. enqueue
			// hm - do we have a global queue or one per NSConnection??? if local: why do we then save the connection within NSDistantObjectRequest
			// according to the description it appears there is one queue per NSThread shared by all NSConnections known to that NSThread
			// so we should not have an iVar but use [[NSThread currentThread] threadDictionary]
			
//			static NSString *key=@"NSPerThreadConnectionQueue";	// CHECKME how the key is called!!!
//			NSMutableDictionary *dict=[[NSThread currentThread] threadDictionary];
//			NSMutableArray *requestQueue=[dict objectForKey:key];
			
			if(!_requestQueue)
				_requestQueue=[NSMutableArray new];
			[inv retainArguments];	// retain any NSDistantObject we have received
			[_requestQueue addObject:req];
#if 0
			NSLog(@"*** (conn=%p) queued: %@", self, req);
#endif
			[req release];
			return;
		}
	while(YES)
		{
		if(![_delegate respondsToSelector:@selector(connection:handleRequest:)] || ![_delegate connection:self handleRequest:req])
			{ // not handled by delegate
				inv=[req invocation];
#if 0
				NSLog(@"*** (conn=%p) request received ***", self);
#endif
				NS_DURING {
#if 0
					[inv _log:@"handleRequest"];
#endif
					[[req connection] dispatchInvocation:inv];	// make a call to the local object(s)
					exception=nil;	// no exception
				}
				NS_HANDLER {
					exception=localException;	// dispatching did result in an exception					
				}
				NS_ENDHANDLER
				[req replyWithException:exception];
			}
#if 0
		NSLog(@"request queue %@", _requestQueue);
#endif
		[req release];
		if([_requestQueue count] == 0)
			break;	// empty
		req=[[_requestQueue objectAtIndex:0] retain];
		[_requestQueue removeObjectAtIndex:0];	// pull next request from queue
		}
	[_currentConversation release];
	_currentConversation=nil;	// done
}

/*
 * NOTE: it has been verified by stack traces that an
 * invocation dispatched to a NSDistantObject target
 * will call -invoke twice, i.e. the NSDistantObject
 * will get a forwardInvocation: call because it does
 * not implement the method and that will result in
 * [i invokeWithTarget:[distantObject localObject]]
 */

- (void) dispatchInvocation:(NSInvocation *) i;
{
#if 1
	NSLog(@"--- dispatchInvocation: %@", i);
#endif
#if 1
	NSLog(@"target=%p %@", [i target], NSStringFromClass([[i target] class]));
	NSLog(@"selector=%@", NSStringFromSelector([i selector]));
#endif
#if 1	 // this is a workaround since our -invoke does not work as described in the comment NOTE above this method
	if([[i target] isKindOfClass:[NSDistantObject class]])
		{
		NSLog(@"target is NSDistantObject");
		// this should only happen for local NSDistantObjects!
		[(NSDistantObject *) [i target] forwardInvocation:i];	// call with _local as the target
		}
	else
#endif
	[i invoke];
#if 0
	NSLog(@"--- done with dispatchInvocation: %@", i);
#endif
}

- (void) returnResult:(NSInvocation *) result exception:(NSException *) exception sequence:(NSUInteger) seq imports:(NSArray *) imports
{
	NSMethodSignature *sig=[result methodSignature];
	BOOL isOneway=[sig isOneway];
#if 0
	NSLog(@"returnResult: %@", result);
	NSLog(@"   exception: %@", exception);
	NSLog(@"    sequence: %u", seq);
	NSLog(@"     imports: %@", imports);
#endif
	if(!isOneway)
		{ // there is something to return...
			NSPortCoder *pc=[self portCoderWithComponents:nil];	// for encoding
			unsigned long flags=FLAGS_RESPONSE;
#if 0
			NSLog(@"port coder=%@", pc);
#endif
			[pc encodeValueOfObjCType:@encode(unsigned int) at:&flags];
			[pc encodeValueOfObjCType:@encode(unsigned int) at:&seq];
			[pc encodeObject:nil];	// is this the exception or the inout objects list?
			[pc encodeReturnValue:result];	// encode result (separately from NSInvocation)
			[pc encodeObject:exception];
			// [pc encodeObject:imports];
			[self finishEncoding:pc];
#if 0
			// CHECKME: is this timeout correct? We are sending a reply...
			NSLog(@"replyTimeout=%f", _replyTimeout);
			NSLog(@"timeIntervalSince1970=%f", [[NSDate date] timeIntervalSince1970]);
			NSLog(@"timeIntervalSinceRefDate=%f", [[NSDate date] timeIntervalSinceReferenceDate]);
			NSLog(@"time=%f", [NSDate timeIntervalSinceReferenceDate]+_replyTimeout);
			// flags must be YES or we get a timeout (!) exception
#endif
#if 1
			NSLog(@"now sending %@", [pc components]);
#endif
			[pc sendBeforeTime:[NSDate timeIntervalSinceReferenceDate]+_replyTimeout sendReplyPort:NO];	// send response on sendPort
			_repliesSent++;
			[pc invalidate];
#if 0
			NSLog(@"sent");
#endif
		}
}

- (void) finishEncoding:(NSPortCoder *) coder;
{
#if 0
	NSLog(@"delegate %@", _delegate);
	NSLog(@"coder %@", coder);
	NSLog(@"components1 %@", [coder components]);
#endif
	[coder authenticateWithDelegate:_delegate];
	// [somearray addObject:something];
#if 0
	NSLog(@"components2 %@", [coder components]);
#endif
}

- (BOOL) _cleanupAndAuthenticate:(NSPortCoder *) coder sequence:(NSUInteger) seq conversation:(id *) conversation invocation:(NSInvocation *) inv raise:(BOOL) raise;
{
	BOOL r=[coder verifyWithDelegate:_delegate];
#if 0
	NSLog(@"_cleanupAndAuthenticate sequence=%u", seq);
	NSLog(@"verifyWithDelegate => %@ delegate = %@", r?@"YES":@"NO", _delegate);
	NSLog(@"components3 %@", [coder components]);
	NSLog(@"conversation %@", *conversation);
	r=YES;
#endif
	[coder invalidate];	// no longer needed
	if(!r && raise)
		[NSException raise:NSFailedAuthenticationException format:@"authentication of request failed for connection %@ sequence %u on selector %@", self, seq, NSStringFromSelector([inv selector])];	// who receives this exception and/or is it ignored?
	// ...
	// do we release/nullify *conversation here if queue is empty???
	return r;
}

- (BOOL) _shouldDispatch:(id *) conversation invocation:(NSInvocation *) invocation sequence:(NSUInteger) seq coder:(NSCoder *) coder;
{
	SEL sel=[invocation selector];
	// it looks like special rules for 2 selectors...
	// a guess is that we process methodDescriptionForSelector: and _localClassNameForClass here
	// it may be required or harmless that some selectors are never queued up
	// lastConversationInfo ()
	// there is at least one other condition involved. seq > 0?
	if(!_independentConversationQueueing)
		return YES;	// dispatch always
#if MAYBE
	sig=[inv methodSignature];
	if([sig isOneway])
		return YES;	// dispatch always immediately
#endif
	if(*conversation)
		return NO;	// must enqueue
	*conversation=[self newConversation];	// create new conversation
	return YES;	// but dispatch this call
}

- (BOOL) hasRunloop:(NSRunLoop *) obj
{
	return [_runLoops indexOfObjectIdenticalTo:obj] != NSNotFound;
}

- (void) addClassNamed:(char *) name version:(NSInteger) version
{
	NSLog(@"-[NSConnection addClassNamed:%s version:%ld]", name, (long)version);
}

- (NSInteger) versionForClassNamed:(NSString *) className
{
	Class class;
	NSNumber *version;
#if 1
	NSLog(@"-[NSConnection versionForClassName:%@]", className);
#endif
#if FIXME
	version=[_classVersions objectForKey:className];
	if(version)
		return [version intValue];	// defined by sender
#endif
	class=NSClassFromString(className);
	if(!class)
		return NSNotFound;	// unknown class
	return [class version];	// default defined by class
}

@end

@implementation NSConnection (NSPrivate)

// this are our own private methods to make it work

- (NSDistantObject *) _getLocal:(id) target;
{ // get proxy object for local object - if known
#if 1
	NSLog(@"_getLocal: %p", target);
	NSLog(@"   -> %p", NSMapGet(_localObjects, (void *) target));
#if 0
	NSLog(@"   -> %@", NSMapGet(_localObjects, (void *) target));
#endif
#endif
	return NSMapGet(_localObjects, (void *) target);
}

- (NSDistantObject *) _getLocalByRemote:(id) remote;
{ // get proxy object for local object - if known
	// we could do the NSConnection fallback here
	return NSMapGet(_localObjectsByRemote, (void *) remote);
}

- (void) _addLocalDistantObject:(NSDistantObject *) obj forLocal:(id) target andRemote:(id) remote;
{
#if 1
	NSLog(@"_addLocalDistantObject: forLocal: %p andRemote: %p", target, remote);
#endif
	NSMapInsert(_localObjects, (void *) target, obj);
	NSMapInsert(_localObjectsByRemote, (void *) remote, obj);
}

- (void) _removeLocalDistantObjectForLocal:(id) target andRemote:(id) remote;
{
#if 1
	NSLog(@"_removeLocalDistantObjectForLocal: %p andRemote: %p", target, remote);
#endif
	NSMapRemove(_localObjectsByRemote, (void *) remote);
	NSMapRemove(_localObjects, (void *) target);
}

// map target id's (may be casted from int) to the distant objects
// note that the distant object retains this connection, but not vice versa!

- (NSDistantObject *) _getRemote:(id) target;
{ // get proxy for remote target - if known
#if 1
	NSLog(@"_getRemote: %p", target);
	NSLog(@"   -> %p", NSMapGet(_remoteObjects, (void *) target));
	//	NSLog(@"   -> %@", NSMapGet(_remoteObjects, (void *) target));
#endif
	return NSMapGet(_remoteObjects, (void *) target);
}

- (void) _addRemoteDistantObject:(NSDistantObject *) obj forRemote:(id) target;
{
#if 1
	NSLog(@"_addRemoteDistantObject: forRemote: %p", target);
#endif
	NSMapInsert(_remoteObjects, (void *) target, obj);
	//	if((unsigned int) target >= _nextReference)
	//		_nextReference=((unsigned int) target)+1;
}

- (void) _removeRemoteDistantObjectForRemote:(id) target;
{
#if 1
	NSLog(@"_removeRemoteDistantObjectForRemote: %p", target);
#endif
	NSMapRemove(_remoteObjects, (void *) target);
}

@end
