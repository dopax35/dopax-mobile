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
        static let testResultsHeader   = "timestamp,test_type,part,score,duration_ms,errors,details\n"
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
