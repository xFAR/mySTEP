/*
    NSCalendar.h
    mySTEP

    Created by Dr. H. Nikolaus Schaller on Wed Dec 28 2005.
    Copyright (c) 2005 DSITRI.
 
	Author:	Fabian Spillner <fabian.spillner@gmail.com>
	Date:	20. April 2008 - aligned with 10.5
 
    This file is part of the mySTEP Library and is provided
    under the terms of the GNU Library General Public License.
*/

#import <Foundation/NSObject.h>
#import <Foundation/NSDate.h>
#import <Foundation/NSLocale.h>

@class NSDateComponents;

typedef NSUInteger NSCalendarUnit;

enum {
	NSEraCalendarUnit				= 1 << 1,
	NSYearCalendarUnit				= 1 << 2,
	NSMonthCalendarUnit				= 1 << 3,
	NSDayCalendarUnit				= 1 << 4,
	NSHourCalendarUnit				= 1 << 5,
	NSMinuteCalendarUnit			= 1 << 6,
	NSSecondCalendarUnit			= 1 << 7,
	NSWeekCalendarUnit				= 1 << 8,
	NSWeekdayCalendarUnit			= 1 << 9,
	NSWeekdayOrdinalCalendarUnit	= 1 << 10
};

enum
{
	NSWrapCalendarComponents = 1,
};

@interface NSCalendar : NSObject

+ (id) autoupdatingCurrentCalendar;
+ (id) currentCalendar;

- (NSString *) calendarIdentifier;
- (NSDateComponents *) components:(NSUInteger) flags fromDate:(NSDate *) date;
- (NSDateComponents *) components:(NSUInteger) flags 
						 fromDate:(NSDate *) fromDate 
						   toDate:(NSDate *) toDate 
						  options:(NSUInteger) options;
- (NSDate *) dateByAddingComponents:(NSDateComponents *) components 
							 toDate:(NSDate *) toDate 
							options:(NSUInteger) options;
- (NSDate *) dateFromComponents:(NSDateComponents *) components;
- (NSUInteger) firstWeekday;
- (id) initWithCalendarIdentifier:(NSString *) str;
- (NSLocale *) locale;
- (NSRange) maximumRangeOfUnit:(NSCalendarUnit) calendarUnit;
- (NSUInteger) minimumDaysInFirstWeek;
- (NSRange) minimumRangeOfUnit:(NSCalendarUnit) unit;
- (NSUInteger) ordinalityOfUnit:(NSCalendarUnit) smaller 
						 inUnit:(NSCalendarUnit) larger 
						forDate:(NSDate *) date;
- (NSRange) rangeOfUnit:(NSCalendarUnit) smaller inUnit:(NSCalendarUnit) larger forDate:(NSDate *) date;
- (BOOL) rangeOfUnit:(NSCalendarUnit) unit startDate:(NSDate **) datep interval:(NSTimeInterval *) tip forDate:(NSDate *) date;
- (void) setFirstWeekday:(NSUInteger) weekday;
- (void) setLocale:(NSLocale *) locale;
- (void) setMinimumDaysInFirstWeek:(NSUInteger) minDayInFirstWeek;
- (void) setTimeZone:(NSTimeZone *) timezone;
- (NSTimeZone *) timeZone;

@end


enum {
	NSUndefinedDateComponent = 0x7fffffff
};


@interface NSDateComponents : NSObject <NSCopying, NSCoding>

- (NSInteger) era;
- (NSInteger) year;
- (NSInteger) month;
- (NSInteger) day;
- (NSInteger) hour;
- (NSInteger) minute;
- (NSInteger) second;
- (NSInteger) week;
- (NSInteger) weekday;
- (NSInteger) weekdayOrdinal;

- (void) setEra:(NSInteger) value;
- (void) setYear:(NSInteger) value;
- (void) setMonth:(NSInteger) value;
- (void) setDay:(NSInteger) value;
- (void) setHour:(NSInteger) value;
- (void) setMinute:(NSInteger) value;
- (void) setSecond:(NSInteger) value;
- (void) setWeek:(NSInteger) value;
- (void) setWeekday:(NSInteger) value;
- (void) setWeekdayOrdinal:(NSInteger) value;

@end
