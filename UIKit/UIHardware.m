//
//  UIHardware.m
//  mySTEP
//
//  Created by Dr. H. Nikolaus Schaller on Thu Mar 06 2008.
//  Copyright (c) 2008 Golden Delicious Computers GmbH&Co KG. All rights reserved.
//
//  based on http://www.cocoadev.com/index.pl?UIKit
//
//  Licenced under LGPL
//

#import <UIKit/UIKit.h>

@implementation UIHardware

+ (CGRect) fullScreenApplicationContentRect;
{
	NSScreen *s=[NSScreen mainScreen];
	if(!s)
		s=[[NSScreen screens] objectAtIndex:0];
	return [s frame];
}

+ (int) deviceOrientation:(BOOL) flag;
{
	// FIXME: a correct implementation needs support of non-standard API
	return 1;	// normal
}

@end
