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

    // MARK: - CSV — ALL filenames and headers match Android exactly
    enum CSV {

        // ── Active test files (match Android filenames) ──────────────────
        static let fingerTappingFile    = "finger_tapping.csv"
        static let handTurningFile      = "hand_turning.csv"
        static let legAgilityFile       = "leg_agility.csv"
        static let spiralTracingFile    = "spiral_tracing.csv"
        static let tmtResultsFile       = "tmt_results.csv"

        // ── Active test headers (match Android exactly) ───────────────────
        /// timestamp_ms, elapsed_ms, event, button_id, side, dominant_hand, affected_side
        static let fingerTappingHeader  = "timestamp_ms,elapsed_ms,event,button_id,side,dominant_hand,affected_side\n"

        /// timestamp_ms, elapsed_ms, event, gx, gy, gz, ax, ay, az, side, dominant_hand, affected_side
        static let handTurningHeader    = "timestamp_ms,elapsed_ms,event,gx,gy,gz,ax,ay,az,side,dominant_hand,affected_side\n"

        /// identical schema to hand_turning
        static let legAgilityHeader     = "timestamp_ms,elapsed_ms,event,gx,gy,gz,ax,ay,az,side,dominant_hand,affected_side\n"

        /// timestamp_ms, elapsed_ms, event, x, y, action, side, dominant_hand, affected_side
        static let spiralTracingHeader  = "timestamp_ms,elapsed_ms,event,x,y,action,side,dominant_hand,affected_side\n"

        /// start_time_ms, timestamp_ms, test_type, total_time_ms, errors, segment_timings_json, finger_path_json, path_data_json
        static let tmtResultsHeader     = "start_time_ms,timestamp_ms,test_type,total_time_ms,errors,segment_timings_json,finger_path_json,path_data_json\n"

        // ── Passive / sensor files ─────────────────────────────────────────
        static let questionnaireFile    = "questionnaire.csv"
        static let sensorsFile          = "sensors.csv"
        static let gaitMetricsFile      = "gait_metrics.csv"
        static let passiveSensorsFile   = "passive_sensors.csv"
        static let touchFile            = "touch.csv"
        static let appsFile             = "apps.csv"
        static let faceDistanceFile     = "face_distance.csv"
        static let heartRateFile        = "heart_rate.csv"
        static let beanieTemperatureFile = "beanie_temperature.csv"
        static let beanieImuFile        = "beanie_imu.csv"
        static let keyEventsFile        = "key_events.csv"
        static let medicationFile       = "medication.csv"
        static let physicalActivityFile = "physical_activity.csv"
        static let profileFile          = "profile.csv"

        // ── Passive / sensor headers ──────────────────────────────────────
        static let questionnaireHeader  = "timestamp,symptoms,motor,sleep,mood,overall,notes\n"
        static let sensorsHeader        = "timestamp_ns,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z\n"
        static let gaitMetricsHeader    = "date,walking_speed_ms,step_length_m,walking_steadiness,double_support_pct,asymmetry_pct,heart_rate_bpm,hrv_sdnn_ms\n"
        static let passiveSensorsHeader = "timestamp_ns,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z\n"
        static let touchHeader          = "timestamp_ms,action,x,y,pressure,tap_interval_ms\n"
        static let appsHeader           = "timestamp_ms,event,bundle_id,duration_ms\n"
        static let faceDistanceHeader   = "timestamp_ms,distance_ratio,face_x,face_y,confidence,roll_deg,yaw_deg\n"
        static let heartRateHeader      = "timestamp_ms,bpm,rr_interval_ms,device_address,device_name\n"
        static let beanieTemperatureHeader = "timestamp_ms,device_name,device_address,profile_name,inner_c,outer_c,tskin_c,heat_flux_cal_per_sec,battery_pct\n"
        static let beanieImuHeader      = "timestamp_ms,device_name,device_address,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,ax_g,ay_g,az_g,accel_mag_g,gx_dps,gy_dps,gz_dps,gyro_mag_dps\n"
        static let keyEventsHeader      = "timestamp_ms,key_class,is_backspace,source_app\n"
        static let medicationHeader     = "timestamp_ms,taken_ms,med_name,dosage\n"
        static let physicalActivityHeader = "timestamp_ms,activity_type,time_of_day_ms\n"
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
