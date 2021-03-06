//
//  MKPolyline.h
//  MapKit
//
//  Created by H. Nikolaus Schaller on 04.10.10.
//  Copyright 2009 Golden Delicious Computers GmbH&Co. KG. All rights reserved.
//

#import <MapKit/MKMultiPoint.h>

@interface MKPolyline : MKMultiPoint <MKOverlay>
{
}

+ (MKPolyline *) polylineWithCoordinates:(CLLocationCoordinate2D *) coords count:(NSUInteger) count;
+ (MKPolyline *) polylineWithPoints:(MKMapPoint *) points count:(NSUInteger) count;

@end

// EOF
