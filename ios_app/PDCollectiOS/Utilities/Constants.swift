import Foundation

enum Constants {
    static let googleAppsScriptURL = "https://script.google.com/macros/s/AKfycbxwRiXDXhUmKER4wdplH2lwtEeLXDlKfP0AZQaU2fqzcmgwjD7NHAr_RkDHdUsTgudXQw/exec"
    static let driveFolderId = "1QLsYUTmXIha7rn7wNIJDXVTtrcWoXdly"
    static let appName = "PDCollect"

    // MARK: - Background Task Identifiers (must match Info.plist)
    enum BGTask {
        static let refresh    = "com.pdcollect.ios.bg-refresh"
        static let processing = "com.pdcollect.ios.bg-processing"
    }

    // MARK: - CSV
    enum CSV {
        // Active-test outputs (existing)
        static let testResultsFile     = "test_results.csv"
        static let questionnaireFile   = "questionnaire.csv"
        static let sensorsFile         = "sensors.csv"
        static let gaitMetricsFile     = "gait_metrics.csv"

        // Passive collection outputs (new — matches Android)
        static let passiveSensorsFile  = "passive_sensors.csv"  // continuous accel/gyro
        static let touchFile           = "touch.csv"
        static let appsFile            = "apps.csv"
        static let faceDistanceFile    = "face_distance.csv"

        // Headers
        static let testResultsHeader   = "timestamp,test_type,part,score,duration_ms,errors,details,platform\n"
        static let questionnaireHeader  = "timestamp,symptoms,motor,sleep,mood,overall,notes\n"
        static let sensorsHeader        = "timestamp_ns,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z\n"
        static let gaitMetricsHeader    = "date,walking_speed_ms,step_length_m,walking_steadiness,double_support_pct,asymmetry_pct,heart_rate_bpm,hrv_sdnn_ms\n"

        // Passive sensor header (same columns as active — reuses SensorReading.csvRow)
        static let passiveSensorsHeader = "timestamp_ns,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z\n"

        // Touch — matches Android touch.csv: timestamp_ms,action,x,y,pressure,tap_interval_ms
        static let touchHeader          = "timestamp_ms,action,x,y,pressure,tap_interval_ms\n"

        // Apps — matches Android apps.csv: timestamp_ms,event,bundle_id,duration_ms
        static let appsHeader           = "timestamp_ms,event,bundle_id,duration_ms\n"

        // Face distance — matches Android face_distance.csv
        static let faceDistanceHeader   = "timestamp_ms,distance_ratio,face_x,face_y,confidence,roll_deg,yaw_deg\n"

        // Heart rate — matches Android heart_rate.csv
        static let heartRateFile        = "heart_rate.csv"
        static let heartRateHeader      = "timestamp_ms,bpm,rr_interval_ms,device_address,device_name\n"

        // Beanie temperature — matches Android beanie_temperature.csv
        static let beanieTemperatureFile = "beanie_temperature.csv"
        static let beanieTemperatureHeader = "timestamp_ms,device_name,device_address,profile_name,inner_c,outer_c,tskin_c,heat_flux_cal_per_sec,battery_pct\n"

        // Beanie IMU — matches Android beanie_imu.csv
        static let beanieImuFile        = "beanie_imu.csv"
        static let beanieImuHeader      = "timestamp_ms,device_name,device_address,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,ax_g,ay_g,az_g,accel_mag_g,gx_dps,gy_dps,gz_dps,gyro_mag_dps\n"

        // Keystroke events — matches Android key_events.csv (privacy-first: only key class, never actual characters)
        static let keyEventsFile        = "key_events.csv"
        static let keyEventsHeader      = "timestamp_ms,key_class,is_backspace,source_app\n"

        // Medication intake events — matches Android medication.csv
        static let medicationFile       = "medication.csv"
        static let medicationHeader     = "timestamp_ms,taken_ms,med_name,dosage\n"

        // Physical activity (user-reported) — matches Android physical_activity.csv
        static let physicalActivityFile = "physical_activity.csv"
        static let physicalActivityHeader = "timestamp_ms,activity_type,time_of_day_ms\n"

        // Profile snapshot — matches Android profile.csv
        static let profileFile          = "profile.csv"
        static let profileHeader        = "timestamp_ms,user_id,age,gender,dominant_hand,affected_side,medications_json\n"
    }

    // MARK: - Test Durations
    enum TestDuration {
        static let fingerTapping: Double = 10
        static let handTurning: Double   = 10
        static let legAgility: Double    = 10
    }

    // MARK: - TMT
    enum TMT {
        static let targetCount  = 10
        static let targetRadius: CGFloat = 28
        static let minSpacing: CGFloat   = 80
    }
}
