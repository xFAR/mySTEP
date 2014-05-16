//
//  compile.m
//  objc2pp
//
//  Created by H. Nikolaus Schaller on 14.03.13.
//  Copyright 2013 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//

#import "Compile.h"

// here we can simplify the tree before any processing
// a -> b   ===> (*a).b
// a[b]		===> *(a+b)

@implementation Node (Compile)

+ (NSArray *) compileTargets;
{
	static NSArray *targets=nil;
	if(!targets)
		targets=[[NSArray alloc] initWithObjects:
				 @"C",	// translate (expand) to C code
				 @"objc1",	// translate (expand) to ObjC-1.0
				 @"objc2",	// translate (simplify) to ObjC-2.0
				 @"arm",	// translate to ARM asm statements
				 nil];
	return targets;
}

- (void) registerAssign
{ // assign explicit 'register' and temporary stack variables
	
}

- (void) compile:(NSString *) target;
{
	[self treeWalk:[@"compile_" stringByAppendingString:target]];
}

- (void) compile_arm_default;
{ // translate to asm() statements
	Node *n=[Node node:@"asm"];
	[n addChild:[Node leaf:@"string" value:[NSString stringWithFormat:@"some asm statement for %@", [self type]]]];
	[self replaceBy:n];
}

@end