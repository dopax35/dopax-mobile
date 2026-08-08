#import "SRSafetyHelper.h"

#ifndef DISABLE_SENSORKIT
#import <SensorKit/SensorKit.h>
#endif

@implementation SRSafetyHelper

+ (nullable id)safeCreateSensorReaderForSensorName:(NSString *)sensorName {
#ifndef DISABLE_SENSORKIT
    @try {
        if (@available(iOS 14.0, *)) {
            SRSensor sensor = nil;
            if ([sensorName isEqualToString:(NSString *)SRSensorAccelerometer]) {
                sensor = SRSensorAccelerometer;
            } else if ([sensorName isEqualToString:(NSString *)SRSensorRotationRate]) {
                sensor = SRSensorRotationRate;
            } else if ([sensorName isEqualToString:(NSString *)SRSensorKeyboardMetrics]) {
                sensor = SRSensorKeyboardMetrics;
            } else if ([sensorName isEqualToString:(NSString *)SRSensorDeviceUsageReport]) {
                sensor = SRSensorDeviceUsageReport;
            } else {
                sensor = (SRSensor)sensorName;
            }
            
            if (sensor != nil) {
                return [[SRSensorReader alloc] initWithSensor:sensor];
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[SRSafetyHelper] Failed to create SRSensorReader for %@: %@", sensorName, exception.reason);
    }
#endif
    return nil;
}

@end
