package com.pdcollect.app.util

import android.os.SystemClock
import com.pdcollect.app.data.UserProfile

/**
 * Encapsulates the timing + metadata that every motor-test CSV row needs.
 *
 * Why this exists:
 *   The four motor tests (Spiral / Hand Turning / Finger Tapping / Leg
 *   Agility) each have their own per-row sensor columns, but they all need
 *   the SAME wrapper:
 *
 *     timestamp_ms, elapsed_ms, event,  ...sensor cols...,  side, dominant_hand, affected_side
 *
 *   Doing this in one helper keeps the four activities in lock-step:
 *   any time we change the schema we change it once.
 *
 *   It also fixes a real correctness bug: previously the activities only
 *   wrote rows when the user produced a sample (e.g. first touched the
 *   spiral canvas), so the analyst had no way to know *when the test was
 *   presented*. That latency is itself a PD-relevant signal. This class
 *   captures `wallStartMs` + a monotonic origin at construction (which the
 *   activities call when the test UI is first shown), so a START event can
 *   be emitted before any user input arrives.
 *
 * Time bases:
 *   - `timestamp_ms` is wall-clock (System.currentTimeMillis). Useful for
 *     cross-CSV alignment (e.g. matching a tap to a sensor sample).
 *   - `elapsed_ms` is monotonic from SystemClock.elapsedRealtimeNanos.
 *     Use this for any *within-trial* duration math — wall-clock can jump
 *     forward or backward if NTP fires mid-trial.
 */
class MotorTestSession(
    profile: UserProfile,
    /** Limb being tested in this trial: [Constants.PARTICIPANT_HAND_RIGHT] or _LEFT. */
    val side: String
) {
    val wallStartMs: Long = System.currentTimeMillis()
    private val monoStartNs: Long = SystemClock.elapsedRealtimeNanos()
    private val dominantHand: String = profile.dominantHand
    private val affectedSide: String = profile.affectedSide

    /** Monotonic ms since this session was constructed. */
    fun elapsedMs(): Long = (SystemClock.elapsedRealtimeNanos() - monoStartNs) / 1_000_000L

    /** CSV tail shared by every row of this trial. */
    private fun trailer(): String = "$side,$dominantHand,$affectedSide"

    /**
     * START row — emitted the moment the test UI is presented to the user.
     * Sensor columns are blanked. The analyst can compute "time to first
     * input" as (first SAMPLE row's elapsed_ms) - 0.
     *
     * @param blanksForSensorColumns one empty placeholder per sensor column
     *        in the test's header (e.g. 2 for Spiral's x,y; 6 for HandTurning's
     *        gx,gy,gz,ax,ay,az; 1 for FingerTapping's button_id). Caller knows
     *        its own schema.
     */
    fun startRow(blanksForSensorColumns: Int): String = buildString {
        append(wallStartMs); append(",0,START,")
        repeat(blanksForSensorColumns) { append(',') }
        append(trailer())
    }

    /**
     * SAMPLE row — caller supplies the per-test sensor payload as a
     * pre-formatted CSV fragment (no leading or trailing comma).
     */
    fun sampleRow(sensorCsv: String): String {
        val ts = System.currentTimeMillis()
        val el = elapsedMs()
        return "$ts,$el,SAMPLE,$sensorCsv,${trailer()}"
    }

    /**
     * END row — emitted when the trial completes (timer finished or user
     * tapped Finish). Sensor columns are blanked.
     */
    fun endRow(blanksForSensorColumns: Int): String = buildString {
        append(System.currentTimeMillis()); append(',')
        append(elapsedMs()); append(',').append("END").append(',')
        repeat(blanksForSensorColumns) { append(',') }
        append(trailer())
    }
}
