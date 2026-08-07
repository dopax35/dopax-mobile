#import "SRSafetyHelper.h"
#import <SensorKit/SensorKit.h>

@implementation SRSafetyHelper

+ (nullable id)safeCreateSensorReaderForSensorName:(NSString *)sensorName {
    @try {
        if (@available(iOS 14.0, *)) {
            SRSensor sensor = (SRSensor)sensorName;
            return [[SRSensorReader alloc] initWithSensor:sensor];
        }
    } @catch (NSException *exception) {
        NSLog(@"[SRSafetyHelper] Failed to create SRSensorReader for %@: %@", sensorName, exception.reason);
    }
    return nil;
}

@end
