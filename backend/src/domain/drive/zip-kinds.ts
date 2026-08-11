/**
 * Classifies paths inside a PDData ZIP and decides what lands in Postgres.
 *
 * High-rate streams are catalogued in `upload_files` but their rows are not
 * loaded (MIGRATION_PLAN.md §6.5). Active tests and self-report become
 * structured rows.
 */
export type ZipEntryKind =
  | 'finger_tapping'
  | 'fingers_test'
  | 'hand_turning'
  | 'leg_agility'
  | 'spiral_tracing'
  | 'tmt'
  | 'voice_test'
  | 'questionnaire'
  | 'medication'
  | 'physical_activity'
  | 'sleep'
  | 'heart_rate'
  | 'profile'
  | 'stream'
  | 'voice_audio'
  | 'json'
  | 'marker'
  | 'other';

/** Basenames whose rows become structured Postgres data. */
const STRUCTURED: Record<string, ZipEntryKind> = {
  'finger_tapping.csv': 'finger_tapping',
  'fingers_test.csv': 'fingers_test',
  'hand_turning.csv': 'hand_turning',
  'leg_agility.csv': 'leg_agility',
  'spiral_tracing.csv': 'spiral_tracing',
  'tmt_results.csv': 'tmt',
  'voice_test.csv': 'voice_test',
  'questionnaire.csv': 'questionnaire',
  'medication.csv': 'medication',
  'physical_activity.csv': 'physical_activity',
  'sleep.csv': 'sleep',
  'heart_rate.csv': 'heart_rate',
  'profile.csv': 'profile',
};

/** Catalogued only — rows stay in the ZIP / object store. */
const STREAMS = new Set([
  'sensors.csv',
  'passive_sensors.csv',
  'touch_events.csv',
  'touch.csv',
  'key_events.csv',
  'apps.csv',
  'screen_state.csv',
  'face_distance.csv',
  'face_distance_refined.csv',
  'gaze_tracking.csv',
  'blink_log.csv',
  'beanie_imu.csv',
  'beanie_temperature.csv',
  'gait_metrics.csv',
  'pedometer.csv',
  'motion_activity.csv',
  'sensorkit_accelerometer.csv',
  'sensorkit_rotation_rate.csv',
  'sensorkit_keyboard_metrics.csv',
  'sensorkit_device_usage.csv',
  'voice_log.csv',
]);

export function basenameOf(pathInZip: string): string {
  const parts = pathInZip.replace(/\\/g, '/').split('/');
  return parts[parts.length - 1] ?? pathInZip;
}

export function classifyZipEntry(pathInZip: string): ZipEntryKind {
  const name = basenameOf(pathInZip);
  if (name === '.uploaded' || name === '.uploading' || name === '.uploaded_v2') return 'marker';
  if (STRUCTURED[name]) return STRUCTURED[name]!;
  if (STREAMS.has(name)) return 'stream';
  if (name.endsWith('.m4a')) return 'voice_audio';
  if (name.endsWith('.json')) return 'json';
  if (name.endsWith('.csv')) return 'other';
  return 'other';
}

export function isStructuredKind(kind: ZipEntryKind): boolean {
  return kind in STRUCTURED || Object.values(STRUCTURED).includes(kind);
}

export function structuredKinds(): ZipEntryKind[] {
  return [...new Set(Object.values(STRUCTURED))];
}
