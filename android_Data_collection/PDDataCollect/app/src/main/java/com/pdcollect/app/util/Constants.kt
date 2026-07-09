package com.pdcollect.app.util

object Constants {
    // Storage
    const val BASE_DIR = "PDCollect"
    const val SENSORS_FILE = "sensors.csv"
    const val TOUCH_FILE = "touch_events.csv"
    const val KEYS_FILE = "key_events.csv"
    const val APPS_FILE = "apps.csv"
    const val SCREEN_STATE_FILE = "screen_state.csv"
    const val TMT_RESULTS_FILE = "tmt_results.csv"
    const val FACE_DISTANCE_FILE = "face_distance_refined.csv"
    const val PROFILE_FILE = "profile.csv"
    const val QUESTIONNAIRE_FILE = "questionnaire.csv"
    const val TEST_FINGER_TAPPING_FILE = "finger_tapping.csv"
    const val TEST_HAND_TURNING_FILE = "hand_turning.csv"
    const val TEST_SPIRAL_FILE = "spiral_tracing.csv"
    const val TEST_LEG_AGILITY_FILE = "leg_agility.csv"
    const val MEDICATION_FILE = "medication.csv"
    const val PHYSICAL_ACTIVITY_FILE = "physical_activity.csv"
    const val SLEEP_FILE = "sleep.csv"
    const val HR_FILE = "heart_rate.csv"
    const val BLINK_FILE = "blink_log.csv"
    const val VOICE_LOG_FILE = "voice_log.csv"
    const val BEANIE_TEMP_FILE = "beanie_temperature.csv"
    const val BEANIE_IMU_FILE = "beanie_imu.csv"

    // CSV Headers
    const val SENSORS_HEADER = "timestamp_ns,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z,mag_x,mag_y,mag_z"
    const val TOUCH_HEADER = "timestamp_ms,event_type,x,y,source_app"
    // Redacted: `key_class` is one of "char","digit","space","punct","backspace",
    // "enter","other" — never the literal character typed.
    const val KEYS_HEADER = "timestamp_ms,key_class,is_backspace,source_app"
    const val APPS_HEADER = "timestamp_ms,event_type,package_name,class_name"
    // v3: "errors" (wrong-target touches only) split into two columns so both
    // clinically-relevant TMT error types are captured, matching iOS exactly
    // (previously iOS's single "errors" column counted lift-offs instead —
    // same column name, two different meanings across platforms).
    const val TMT_HEADER = "start_time_ms,timestamp_ms,test_type,total_time_ms,wrong_target_errors,lift_off_errors,segment_timings_json,finger_path_json,path_data_json"
    const val FACE_DISTANCE_HEADER = "timestamp_ms,context,face_detected,landmarks_detected,eye_distance_px,focal_length_px,estimated_cm,confidence,head_euler_y,head_euler_z,method"
    const val PROFILE_HEADER = "timestamp_ms,user_id,age,gender,dominant_hand,affected_side,medications_json"
    const val QUESTIONNAIRE_HEADER = "timestamp_ms,date,time,q1_text,q2_score,q3_score,q4_score,q5_score,q6_sleep_yesno,q6_sleep_score,q6_smell_yesno,q6_smell_score,q6_const_yesno,q6_const_score,q6_anxiety_yesno,q6_anxiety_score,q6_depr_yesno,q6_depr_score"
    // Motor-test schemas v2:
    //   - timestamp_ms     wall-clock at the row (System.currentTimeMillis)
    //   - elapsed_ms       monotonic ms since the START event of *this* trial.
    //                      Use this for any timing analysis — wall-clock can
    //                      jump if the device NTP-syncs mid-trial.
    //   - event            START / SAMPLE / END   (START marks "test presented
    //                      to user", which is what the analyst needs to compute
    //                      reaction latency vs. first sample.)
    //   - side             Right / Left  — which limb is being tested
    //   - dominant_hand    Right / Left / Unknown — participant's dominance
    //   - affected_side    Right / Left / Both / None / Unknown — PD-affected
    //                      side per participant self-report
    // Per-test sensor columns are blank on START / END rows.
    // NOTE: column order keeps `side,dominant_hand,affected_side` as the
    // trailer (matching the other motor-test schemas) so MotorTestSession
    // can format every test the same way.
    const val FINGER_TAPPING_HEADER = "timestamp_ms,elapsed_ms,event,button_id,side,dominant_hand,affected_side"
    const val HAND_TURNING_HEADER = "timestamp_ms,elapsed_ms,event,gx,gy,gz,ax,ay,az,side,dominant_hand,affected_side"
    const val SPIRAL_HEADER = "timestamp_ms,elapsed_ms,event,x,y,action,side,dominant_hand,affected_side"
    const val LEG_AGILITY_HEADER = "timestamp_ms,elapsed_ms,event,gx,gy,gz,ax,ay,az,side,dominant_hand,affected_side"
    const val MEDICATION_HEADER = "timestamp_ms,taken_ms,med_name,dosage"
    // v2 (July 2026): added source/duration/calories/avg_heart_rate so imports
    // from Health Connect / Strava carry richer data than a manual log entry.
    // Manual entries fill the new columns with "Manual,,,"
    const val PHYSICAL_ACTIVITY_HEADER = "timestamp_ms,activity_type,time_of_day_ms,source,duration_min,calories,avg_heart_rate"
    // Imported sleep sessions (Health Connect — which in turn surfaces
    // Garmin Connect, Samsung Health, Fitbit, etc., whichever the user has
    // syncing into Health Connect). "provider" is the specific app that
    // recorded the night (e.g. "Garmin Connect"), blank if it can't be
    // resolved. Stage columns are 0 (not blank) when a source has no stage
    // detail at all — matches iOS exactly.
    const val SLEEP_HEADER = "timestamp_ms,source,provider,sleep_start_ms,sleep_end_ms,time_in_bed_min,total_sleep_min,light_min,deep_min,rem_min,awake_min,unspecified_min"
    const val HR_HEADER = "timestamp_ms,bpm,rr_interval_ms,device_address,device_name"
    const val BLINK_HEADER = "timestamp_ms,context,left_trough_prob,right_trough_prob,blink_rate_per_min"
    const val VOICE_LOG_HEADER = "timestamp_ms,filename,story_headline,duration_ms"
    const val BEANIE_TEMP_HEADER = "timestamp_ms,device_name,device_address,profile_name,inner_c,outer_c,tskin_c,heat_flux_cal_per_sec,battery_pct,ml_prediction,ml_confidence"
    const val BEANIE_IMU_HEADER = "timestamp_ms,device_name,device_address,ax_raw,ay_raw,az_raw,gx_raw,gy_raw,gz_raw,ax_g,ay_g,az_g,accel_mag_g,gx_dps,gy_dps,gz_dps,gyro_mag_dps"

    const val GRAPH_CACHE_FILE = "dashboard_graph_cache.json"

    const val LOOKBACK_DAYS = 365

    // Temporarily disabled (July 2026) — flip back to true to re-enable the
    // Shelly pillbox-sensor BLE scanning/pairing feature. Checked at every
    // entry point (ShellyBleScanner.startScanning() itself, PDCollectService's
    // passive-scan lifecycle, and the "Pair Pillbox Sensor" button in
    // Settings/Profile Setup) so flipping this one flag is sufficient to
    // fully turn the feature back on or off. iOS has no Shelly integration
    // at all, so there's nothing to gate on that platform.
    const val SHELLY_BLE_ENABLED = false

    val PHYSICAL_ACTIVITY_TYPES = listOf("Running", "Bike", "Swimming", "Weight Training", "Pilates", "Other")
    // Sensor collection
    const val SENSOR_BUFFER_FLUSH_INTERVAL_MS = 5000L
    const val SENSOR_BUFFER_MAX_SIZE = 500
    // Keep full-fidelity passive motion capture; use batching to reduce wakeups
    // without dropping rows or rounding away signal detail.
    const val SENSOR_BATCH_LATENCY_US = 5_000_000
    const val SENSOR_DELAY_US = 20_000 // 50 Hz = 20 ms period

    // Face distance
    /** 1 Hz — one sample every 1000 ms. */
    const val FACE_CAPTURE_INTERVAL_MS = 1000L
    const val FACE_DISTANCE_MODE_OFF = "off"
    const val FACE_DISTANCE_MODE_APP_FOREGROUND = "app_foreground"
    const val FACE_DISTANCE_MODE_ALWAYS = "always"
    const val FACE_DISTANCE_MODE_TMT_ONLY = "tmt_only"
    const val FACE_DISTANCE_CONTEXT_APP_FOREGROUND = "dopax_foreground"
    const val FACE_DISTANCE_CONTEXT_ALWAYS = "always_on"
    const val FACE_DISTANCE_CONTEXT_TMT = "tmt"
    const val RAW_RETENTION_DAYS = 7

    /** Broadcast sent by DataAccessibilityService whenever the foreground app changes.
     *  Extra: [EXTRA_FOREGROUND_PACKAGE] — the new foreground package name. */
    const val ACTION_FOREGROUND_APP_CHANGED = "com.pdcollect.app.FOREGROUND_APP_CHANGED"
    const val EXTRA_FOREGROUND_PACKAGE = "foreground_package"

    // TMT Reminders
    const val TMT_MORNING_HOUR = 10
    const val TMT_MORNING_MINUTE = 0
    const val TMT_AFTERNOON_HOUR = 16
    const val TMT_AFTERNOON_MINUTE = 0

    // Notification
    const val CHANNEL_SENSOR = "sensor_collection"
    const val CHANNEL_TMT = "tmt_reminder"
    const val CHANNEL_FACE = "face_distance"
    const val CHANNEL_HR = "hr_monitor"
    const val CHANNEL_BEANIE = "beanie_monitor"
    const val CHANNEL_EVENING = "evening_reminder"
    const val NOTIFICATION_ID_SENSOR = 1001
    const val NOTIFICATION_ID_TMT = 1003
    const val NOTIFICATION_ID_FACE = 1004
    const val NOTIFICATION_ID_HR = 1005
    const val NOTIFICATION_ID_BEANIE = 1006
    const val NOTIFICATION_ID_BATTERY_REMINDER = 1007
    const val NOTIFICATION_ID_EVENING_REMINDER = 1008

    // SharedPreferences
    const val PREFS_NAME = "pd_collect_prefs"
    const val PREF_CONSENT_GIVEN = "consent_given"
    const val PREF_PROFILE_COMPLETE = "profile_complete"
    const val PREF_USER_ID = "user_id"
    const val PREF_AGE = "age"
    const val PREF_GENDER = "gender"
    const val PREF_MEDICATIONS = "medications"
    const val PREF_KEYLOGGING_ENABLED = "keylogging_enabled"
    const val PREF_FACE_DISTANCE_ENABLED = "face_distance_enabled"
    const val PREF_FACE_DISTANCE_MODE = "face_distance_mode"
    const val PREF_PASSIVE_COLLECTION_ACTIVE = "passive_collection_active"
    const val PREF_AUTO_UPLOAD_ENABLED = "auto_upload_enabled"
    const val PREF_TEST_TIME_MORNING = "pref_test_time_morning"
    const val PREF_TEST_TIME_NOON = "pref_test_time_noon"
    const val PREF_TEST_TIME_RANDOM = "pref_test_time_random"
    const val PREF_HR_DEVICE_ADDRESS = "pref_hr_device_address"
    const val PREF_HR_DEVICE_NAME = "pref_hr_device_name"
    const val PREF_BEANIE_DEVICE_ADDRESS = "pref_beanie_device_address"
    const val PREF_BEANIE_DEVICE_NAME = "pref_beanie_device_name"
    const val PREF_HAS_SEEN_WALKTHROUGH = "pref_has_seen_walkthrough"

    // Participant body-side metadata. Captured once at profile setup, editable
    // in Settings, and stamped into every motor-test CSV row so analysts can
    // separate "tested right hand" from "tested dominant hand" from "tested
    // affected hand". Values use the PARTICIPANT_HAND_* / PARTICIPANT_SIDE_*
    // constants below — never raw localized strings.
    const val PREF_DOMINANT_HAND = "pref_dominant_hand"
    const val PREF_AFFECTED_SIDE = "pref_affected_side"

    // Canonical, locale-independent values that go into the CSV files.
    const val PARTICIPANT_HAND_RIGHT = "Right"
    const val PARTICIPANT_HAND_LEFT = "Left"
    const val PARTICIPANT_HAND_UNKNOWN = "Unknown"

    const val PARTICIPANT_SIDE_RIGHT = "Right"
    const val PARTICIPANT_SIDE_LEFT = "Left"
    const val PARTICIPANT_SIDE_BOTH = "Both"
    const val PARTICIPANT_SIDE_NONE = "None"
    const val PARTICIPANT_SIDE_UNKNOWN = "Unknown"
}
