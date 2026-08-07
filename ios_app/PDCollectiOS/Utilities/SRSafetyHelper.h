#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SRSafetyHelper : NSObject

+ (nullable id)safeCreateSensorReaderForSensorName:(NSString *)sensorName;

@end

NS_ASSUME_NONNULL_END
