//
//  NSStringTest.m
//  Foundation
//
//  Created by H. Nikolaus Schaller on 28.03.09.
//  Copyright 2009 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "NSStringTest.h"


@implementation NSStringTest

#define TEST(NAME, INPUT, METHOD, OUTPUT) - (void) test##NAME; { STAssertEqualObjects(OUTPUT, [INPUT METHOD], nil); }
#define TEST2(NAME, INPUT, ARG, METHOD, OUTPUT) - (void) test##NAME; { STAssertEqualObjects(OUTPUT, [INPUT METHOD:ARG], nil); }

// test creation, conversions, add, mutability etc.

TEST(lowercaseString1, @"LowerCase", lowercaseString, @"lowercase");
TEST(lowercaseString2, @"Lower Case", lowercaseString, @"lower case");
TEST(lowercaseString3, @"Lower Case ÄÖÜ", lowercaseString, @"lower case äöü");
TEST(lowercaseString4, @"lowercase", lowercaseString, @"lowercase");
TEST(lowercaseString5, @"", lowercaseString, @"");

TEST(stringByDeletingLastPathComponent1, @"/tmp/scratch.tiff", stringByDeletingLastPathComponent, @"/tmp");
TEST(stringByDeletingLastPathComponent2, @"tmp/scratch.tiff", stringByDeletingLastPathComponent, @"tmp");
TEST(stringByDeletingLastPathComponent3, @"/tmp/lock/", stringByDeletingLastPathComponent, @"/tmp");
TEST(stringByDeletingLastPathComponent4, @"/tmp/", stringByDeletingLastPathComponent, @"/");
TEST(stringByDeletingLastPathComponent5, @"/tmp", stringByDeletingLastPathComponent, @"/");
TEST(stringByDeletingLastPathComponent6, @"/", stringByDeletingLastPathComponent, @"/");
TEST(stringByDeletingLastPathComponent7, @"scratch.tiff", stringByDeletingLastPathComponent, @"");

TEST(stringByDeletingLastPathComponent8, @"//tmp/scratch.tiff", stringByDeletingLastPathComponent, @"/tmp");
TEST(stringByDeletingLastPathComponent9, @"//", stringByDeletingLastPathComponent, @"/");
// TEST(stringByDeletingLastPathComponent10, [NSNull null], stringByDeletingLastPathComponent, @"exception...");

TEST2(componentsSeparatedByString1, @"a:b", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"a", @"b", nil]));
TEST2(componentsSeparatedByString2, @"ab", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"ab", nil]));
TEST2(componentsSeparatedByString3, @":b", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"", @"b", nil]));
TEST2(componentsSeparatedByString4, @"a:", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"a", @"", nil]));
TEST2(componentsSeparatedByString5, @"a::b", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"a", @"", @"b", nil]));
TEST2(componentsSeparatedByString6, @"a:::b", @"::", componentsSeparatedByString, ([NSArray arrayWithObjects:@"a", @":b", nil]));
TEST2(componentsSeparatedByString7, @"a::::b", @"::", componentsSeparatedByString, ([NSArray arrayWithObjects:@"a", @"", @"b", nil]));
TEST2(componentsSeparatedByString8, @":", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"", @"", nil]));
TEST2(componentsSeparatedByString9, @"", @":", componentsSeparatedByString, ([NSArray arrayWithObjects:@"", nil]));

// add many more such tests


@end
