/* 
    Interface of NSDistributedNotificationCenter class
    Copyright (C) 1998 Free Software Foundation, Inc.

    Written by:  Richard Frith-Macdonald <richard@brainstorm.co.uk>
    Created: October 1998

    H.N.Schaller, Dec 2005 - API revised to be compatible to 10.4
 
    Author:	Fabian Spillner <fabian.spillner@gmail.com>
    Date:	28. April 2008 - aligned with 10.5
 
    This file is part of the GNUstep Base Library.

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Library General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Library General Public License for more details.

    You should have received a copy of the GNU Library General Public
    License along with this library; if not, write to the Free
    Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/

#ifndef __NSDistributedNotificationCenter_h_GNUSTEP_BASE_INCLUDE
#define __NSDistributedNotificationCenter_h_GNUSTEP_BASE_INCLUDE

#import <Foundation/NSObject.h>
#import <Foundation/NSLock.h>
#import <Foundation/NSNotification.h>

typedef enum _NSNotificationSuspensionBehavior
{
	NSNotificationSuspensionBehaviorDrop,
	NSNotificationSuspensionBehaviorCoalesce,
	NSNotificationSuspensionBehaviorHold,
	NSNotificationSuspensionBehaviorDeliverImmediately
} NSNotificationSuspensionBehavior;

enum
{
	NSNotificationDeliverImmediately=0x01,
	NSNotificationPostToAllSessions=0x02
};

extern NSString *NSLocalNotificationCenterType;

@interface NSDistributedNotificationCenter : NSNotificationCenter
{
	NSRecursiveLock *_centerLock;	/* For thread safety.		*/
	NSString		*_type;			/* Type of notification center.	*/
	id				_remote;		/* Proxy for center.		*/
	BOOL			_suspended;		/* Is delivery suspended?	*/
}

+ (NSNotificationCenter *) notificationCenterForType:(NSString *) type;

- (void) addObserver:(id) anObserver
			selector:(SEL) aSelector
				name:(NSString *) notificationName
			  object:(NSString *) anObject
  suspensionBehavior:(NSNotificationSuspensionBehavior) suspensionBehavior;
- (void) postNotificationName:(NSString *) notificationName
					   object:(NSString *) anObject
					 userInfo:(NSDictionary *) userInfo
		   deliverImmediately:(BOOL) deliverImmediately;
- (void) postNotificationName:(NSString *) name
					   object:(NSString *) anObject
					 userInfo:(NSDictionary *) userInfo
					  options:(NSUInteger) options;
- (void) setSuspended:(BOOL) flag;
- (BOOL) suspended;

@end

#endif
