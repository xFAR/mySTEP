//
//  MyDocument.h
//  MapKitTest
//
//  Created by H. Nikolaus Schaller on 07.10.10.
//  Copyright 2010 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//


#import <Cocoa/Cocoa.h>
#import <MapKit/MapKit.h>

@interface MyDocument : NSDocument <CLLocationManagerDelegate, MKMapViewDelegate>
{
	CLLocationManager *loc;
	IBOutlet MKMapView *map; 
}

- (IBAction) rotateLeft:(id) sender;
- (IBAction) rotateRight:(id) sender;

@end
