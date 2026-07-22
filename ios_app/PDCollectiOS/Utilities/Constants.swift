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

        /// start_time_ms, timestamp_ms, test_type, total_time_ms, wrong_target_errors, lift_off_errors, segment_timings_json, finger_path_json, path_data_json
        /// v2: "errors" (lift-offs only) split into two columns so both
        /// clinically-relevant TMT error types are captured, matching Android
        /// exactly (previously Android's single "errors" column counted
        /// wrong-target touches instead — same column name, two different
        /// meanings across platforms).
        static let tmtResultsHeader     = "start_time_ms,timestamp_ms,test_type,total_time_ms,wrong_target_errors,lift_off_errors,segment_timings_json,finger_path_json,path_data_json\n"

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
        static let voiceLogFile         = "voice_log.csv"
        static let sleepFile            = "sleep.csv"
        static let pedometerFile        = "pedometer.csv"
        static let motionActivityFile   = "motion_activity.csv"
        static let blinkLogFile         = "blink_log.csv"
        static let gazeFile             = "gaze_tracking.csv"

        // ── Passive / sensor headers ──────────────────────────────────────
        static let questionnaireHeader  = "timestamp_ms,date,time,q1_text,q2_score,q3_score,q4_score,q5_score,q6_sleep_yesno,q6_sleep_score,q6_smell_yesno,q6_smell_score,q6_const_yesno,q6_const_score,q6_anxiety_yesno,q6_anxiety_score,q6_depr_yesno,q6_depr_score\n"
        static let sensorsHeader        = "timestamp_ns,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z\n"
        static let gaitMetricsHeader    = "date,walking_speed_ms,step_length_m,walking_steadiness,double_support_pct,asymmetry_pct,heart_rate_bpm,hrv_sdnn_ms\n"
        static let passiveSensorsHeader = "timestamp_ns,acc_x,acc_y,acc_z,gyro_x,gyro_y,gyro_z\n"
        static let touchHeader          = "timestamp_ms,action,x,y,pressure,tap_interval_ms\n"
        static let appsHeader           = "timestamp_ms,event,bundle_id,duration_ms\n"
        static let faceDistanceHeader   = "timestamp_ms,distance_ratio,face_x,face_y,confidence,roll_deg,yaw_deg\n"
        static let gazeHeader           = "timestamp_ms,left_gaze_x,left_gaze_y,right_gaze_x,right_gaze_y,left_blink,right_blink,look_at_x,look_at_y,look_at_z,method\n"
        static let heartRateHeader      = "timestamp_ms,bpm,rr_interval_ms,device_address,device_name\n"
        static let beanieTemperatureHeader = "timestamp_ms,device_name,device_address,profile_name,inner_c,outer_c,tskin_c,heat_flux_cal_per_sec,battery_pct,ml_prediction,ml_confidence\n"
        static let beanieImuHeader      = "timestamp_ms,device_name,device_address,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,ax_g,ay_g,az_g,accel_mag_g,gx_dps,gy_dps,gz_dps,gyro_mag_dps\n"
        static let keyEventsHeader      = "timestamp_ms,key_class,is_backspace,source_app\n"
        static let medicationHeader     = "timestamp_ms,taken_ms,med_name,dosage\n"
        // v2 (July 2026): added source/duration/calories/avg_heart_rate — matches
        // Android's PHYSICAL_ACTIVITY_HEADER exactly. Manual entries fill the new
        // columns with "Manual,,,".
        static let physicalActivityHeader = "timestamp_ms,activity_type,time_of_day_ms,source,duration_min,calories,avg_heart_rate\n"
        static let profileHeader        = "timestamp_ms,user_id,age,gender,dominant_hand,affected_side,medications_json\n"
        /// timestamp_ms, filename, story_headline, duration_ms — matches Android exactly.
        static let voiceLogHeader       = "timestamp_ms,filename,story_headline,duration_ms\n"
        /// timestamp_ms, context, left_trough_prob, right_trough_prob, blink_rate_per_min — matches Android exactly.
        static let blinkLogHeader       = "timestamp_ms,context,left_trough_prob,right_trough_prob,blink_rate_per_min\n"
        // Imported sleep sessions (Apple Health / Health Connect — which in
        // turn surface Garmin Connect, Oura, AutoSleep, etc., whichever the
        // user has syncing into the platform's health store). "provider" is
        // the specific app that recorded the night (e.g. "Garmin Connect"),
        // blank if the source doesn't expose one. Stage columns are 0 (not
        // blank) when a source has no stage detail at all — matches Android
        // exactly.
        static let sleepHeader = "timestamp_ms,source,provider,sleep_start_ms,sleep_end_ms,time_in_bed_min,total_sleep_min,light_min,deep_min,rem_min,awake_min,unspecified_min\n"
        // iOS-only: hourly step/walking backfill from CMPedometer (the M-series
        // co-processor iOS tracks around the clock, independent of whether this
        // app is open). Supplements passive_sensors.csv, which on iOS only
        // covers the hours the app was actually in the foreground — unlike
        // Android, which collects passive_sensors.csv all day via a foreground
        // Service. One row per hour that had any steps; empty hours are
        // skipped rather than written as zero rows.
        static let pedometerHeader = "timestamp_ms,period_start_ms,period_end_ms,steps,distance_m,floors_ascended,floors_descended,current_pace_s_per_m,current_cadence_steps_per_s\n"
        // iOS-only: all-day activity-type context (walking/running/stationary/
        // automotive/cycling + confidence) from CMMotionActivityManager — the
        // same always-on co-processor CMPedometer taps, but classifying *what
        // kind* of movement was happening rather than just counting steps.
        // Multiple flags can be true on one row (Apple's own model allows
        // ambiguous transitions, e.g. walking+automotive uncertainty).
        static let motionActivityHeader = "timestamp_ms,activity_start_ms,confidence,stationary,walking,running,automotive,cycling,unknown\n"
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
