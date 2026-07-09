package com.pdcollect.app.logic

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Date

/**
 * ActivityEngine — Android port of iOS ActivityEngine.swift (V5_I7T3P4 model).
 *
 * ── Model spec (activity_model.tflite = IMUTempClassifier_V5_I7T3P4) ─────────
 *   Input 0: serving_default_imu_input     float32[1, 250, 7]
 *            channels: ax(g), ay(g), az(g), accel_mag(g), gx(°/s), gy(°/s), gz(°/s)
 *            Scaling: accel = raw_int16 / 4096.0 → g  (BMI323 ±8g)
 *                     gyro  = raw_int16 / 16.384  → °/s (BMI323 ±2000°/s)
 *                     accel_mag = sqrt(ax²+ay²+az²) — derived, NOT from firmware
 *
 *   Input 1: serving_default_temp_input    float32[1, 3]
 *            [0] tSkin          — TskinSynthesizer-smoothed skin temperature (°C), NOT
 *                                 the raw BeaniePacketParser.TemperatureSample.tskinC.
 *                                 BeanieService.handleTemperatureFrame() runs each
 *                                 packet's innerC/outerC through TskinSynthesizer.update()
 *                                 and passes the result's synthC here. CSV logging
 *                                 (beanie_temperature.csv) still records the raw
 *                                 sample.tskinC unchanged — only the model input is
 *                                 smoothed. iOS mirrors this exactly (its own
 *                                 TskinSynthesizer.swift port, same call pattern in
 *                                 BeanieBluetoothService), so both platforms feed the
 *                                 model the same kind of value despite iOS's reference
 *                                 project having since moved to a different ThermalEngine.
 *            [1] outerC         — raw outer sensor temperature (°C)
 *            [2] heatFluxCalPerSec — BSA-scaled heat flux (cal/s)
 *                                   = profile.heatFluxK × bsaScaleFactor × 1000 × (inner−outer)
 *
 *   Input 2: serving_default_posture_input float32[1, 250, 4]
 *            channels: headAngle(deg), fwdFrac, backFrac, latFrac
 *            Sourced from PostureEngine.generatePostureSeries(250)
 *
 *   Output 0: Identity  float32[1, 5]  — softmax over 5 classes
 *   Classes:  ["Running", "Walking", "Sitting", "Standing", "Stairs"]
 *
 * ── Input index ordering ──────────────────────────────────────────────────────
 *   TFLite runForMultipleInputsOutputs() matches inputs by array index.
 *   imu=arrayOf[0], temp=arrayOf[1], posture=arrayOf[2].
 *
 * ── iOS differences ───────────────────────────────────────────────────────────
 *   iOS uses named CoreML inputs so order doesn't matter.
 *   Android must supply inputs in index order (0, 1, 2) precisely.
 *   Both platforms use the same channel ordering inside each tensor.
 */

/**
 * iOS parity: InferenceInputs — snapshot of averaged sensor values fed to the model.
 */
data class InferenceInputs(
    val accelXAvg:    Float = 0f,
    val accelYAvg:    Float = 0f,
    val accelZAvg:    Float = 0f,
    val gyroXAvg:     Float = 0f,
    val gyroYAvg:     Float = 0f,
    val gyroZAvg:     Float = 0f,
    val headAngleAvg: Float = 0f,
    val fwdAvg:       Float = 0f,
    val backAvg:      Float = 0f,
    val latAvg:       Float = 0f,
    val tSkin:        Double = 0.0,
    val outerTemp:    Double = 0.0,
    val heatFlux:     Double = 0.0
)

class ActivityEngine private constructor(private val context: Context) {

    @Suppress("StaticFieldLeak")   // stores applicationContext, not Activity — safe
    companion object {
        private const val TAG = "ActivityEngine"

        private const val MODEL_FILE      = "activity_model.tflite"
        private const val LONG_MODEL_FILE = "long_activity_model.tflite"

        // ── V5_I7T3P4 tensor dimensions ───────────────────────────────────────
        private const val IMU_SAMPLES      = 250
        private const val IMU_CHANNELS     = 7   // ax,ay,az,accel_mag,gx,gy,gz
        private const val TEMP_FEATURES    = 3   // tSkin, outerC, heatFluxCalPerSec
        private const val POSTURE_SAMPLES  = 250
        private const val POSTURE_CHANNELS = 4   // headAngle, fwdFrac, backFrac, latFrac
        private const val NUM_CLASSES      = 5   // Running,Walking,Sitting,Standing,Stairs

        // ── V1_1000 long-window tensor dimensions ─────────────────────────────
        private const val LONG_IMU_SAMPLES     = 1000
        private const val LONG_POSTURE_SAMPLES = 1000
        private const val LONG_NUM_CLASSES     = 3   // Car, Eating, Scooter

        // ── ActivityInferenceManager strip logic constants ────────────────────
        private const val MIN_CONFIDENCE_TO_KEEP_PENDING = 0.65
        private const val STALE_PENDING_SECONDS          = 20.0  // iOS: 20s

        // iOS parity: 10s cooldown after user taps ✓ or ✗ before showing next strip.
        private const val CONFIRM_COOLDOWN_MS = 10_000L

        @Volatile private var instance: ActivityEngine? = null
        fun getInstance(context: Context): ActivityEngine =
            instance ?: synchronized(this) {
                instance ?: ActivityEngine(context.applicationContext).also { instance = it }
            }

        const val EXTRA_ACTIVITY_LABEL = "extra_activity_label"
        const val EXTRA_ACTIVITY_CONFIDENCE = "extra_activity_confidence"
    }

    // ── Published outputs ──────────────────────────────────────────────────────
    val labels = listOf("Running", "Walking", "Sitting", "Standing", "Stairs")

    private val _currentActivity  = MutableStateFlow("")
    val currentActivity: StateFlow<String> = _currentActivity.asStateFlow()

    private val _confidence       = MutableStateFlow(0.0)
    val confidence: StateFlow<Double> = _confidence.asStateFlow()

    private val _allProbabilities = MutableStateFlow(List(NUM_CLASSES) { 0.0 })
    val allProbabilities: StateFlow<List<Double>> = _allProbabilities.asStateFlow()

    private val _isReady          = MutableStateFlow(false)
    val isReady: StateFlow<Boolean> = _isReady.asStateFlow()

    // iOS parity: debug snapshot of averaged inputs from the most recent inference call.
    private val _lastInferenceInputs = MutableStateFlow(InferenceInputs())
    val lastInferenceInputs: StateFlow<InferenceInputs> = _lastInferenceInputs.asStateFlow()

    // ── Long model outputs (V1_1000 — Car, Eating, Scooter) ──────────────────
    val longlabels = listOf("Car", "Eating", "Scooter")

    private val _longCurrentActivity  = MutableStateFlow("")
    val longCurrentActivity: StateFlow<String> = _longCurrentActivity.asStateFlow()

    private val _longConfidence       = MutableStateFlow(0.0)
    val longConfidence: StateFlow<Double> = _longConfidence.asStateFlow()

    private val _longAllProbabilities = MutableStateFlow(List(LONG_NUM_CLASSES) { 0.0 })
    val longAllProbabilities: StateFlow<List<Double>> = _longAllProbabilities.asStateFlow()

    private val _isLongReady          = MutableStateFlow(false)
    val isLongReady: StateFlow<Boolean> = _isLongReady.asStateFlow()

    // ── Internal state ─────────────────────────────────────────────────────────
    private var interpreter:     org.tensorflow.lite.Interpreter? = null
    private var longInterpreter: org.tensorflow.lite.Interpreter? = null
    private val engineScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // iOS parity: only push a new pending prediction when the label changes or
    // the strip was explicitly reset after a user confirm/correct interaction.
    private var lastPushedActivity = ""

    // iOS parity: after user confirms or corrects, suppress new check/x prompts
    // for CONFIRM_COOLDOWN_MS (10s) so the strip doesn't re-surface immediately.
    private var confirmCooldownUntil = 0L

    // iOS parity: in-flight guard — prevents stacking concurrent inference calls
    @Volatile private var inferenceInFlight = false

    // iOS parity: packet throttle — fire inference every 2nd live temp packet
    private var livePacketCount = 0

    init { loadModelAsync() }

    // ── Model loading ──────────────────────────────────────────────────────────

    private fun loadModelAsync() {
        engineScope.launch {
            val assetList = context.assets.list("") ?: emptyArray()

            // ── Standard V5_I7T3P4 model ──────────────────────────────────────
            if (MODEL_FILE !in assetList) {
                Log.w(TAG, "[$MODEL_FILE] not found in assets — inference disabled.\n" +
                        "Rename activity_model_V5_I7T3P4.tflite → activity_model.tflite\n" +
                        "and place it in app/src/main/assets/")
            } else {
                try {
                    val bytes = context.assets.open(MODEL_FILE).use { it.readBytes() }
                    val buf = ByteBuffer.allocateDirect(bytes.size).apply {
                        order(ByteOrder.nativeOrder()); put(bytes); rewind()
                    }
                    val opts = org.tensorflow.lite.Interpreter.Options().apply { numThreads = 2 }
                    interpreter = org.tensorflow.lite.Interpreter(buf, opts)
                    _isReady.value = true
                    Log.i(TAG, "[$MODEL_FILE] loaded ✅ " +
                            "imu[1,250,7]=idx0 temp[1,3]=idx1 posture[1,250,4]=idx2 → 5 classes")
                } catch (e: Exception) {
                    Log.e(TAG, "Standard model load failed: $e")
                }
            }

            // ── Long V1_1000 model (optional — gracefully absent) ─────────────
            if (LONG_MODEL_FILE in assetList) {
                try {
                    val bytes = context.assets.open(LONG_MODEL_FILE).use { it.readBytes() }
                    val buf = ByteBuffer.allocateDirect(bytes.size).apply {
                        order(ByteOrder.nativeOrder()); put(bytes); rewind()
                    }
                    val opts = org.tensorflow.lite.Interpreter.Options().apply { numThreads = 2 }
                    longInterpreter = org.tensorflow.lite.Interpreter(buf, opts)
                    _isLongReady.value = true
                    Log.i(TAG, "[$LONG_MODEL_FILE] loaded ✅ " +
                            "V1_1000: imu[1,1000,7] temp[1,3] posture[1,1000,4] → 3 classes (Car/Eating/Scooter)")
                } catch (e: Exception) {
                    Log.e(TAG, "Long model load failed: $e")
                }
            } else {
                Log.d(TAG, "[$LONG_MODEL_FILE] not in assets — long-model inference disabled.")
            }
        }
    }

    // ── iOS parity: resetLastPushedActivity ────────────────────────────────────

    fun resetLastPushedActivity() {
        lastPushedActivity   = ""
        confirmCooldownUntil = System.currentTimeMillis() + CONFIRM_COOLDOWN_MS
    }

    // ── Inference entry point ──────────────────────────────────────────────────

    fun startInference(
        imuMatrix:          Array<FloatArray>,
        tSkin:              Double,
        outerC:             Double,
        heatFluxCalPerSec:  Double,
        postureSeries:      List<FloatArray>,
        windowStartMs:      Long = 0L,
        windowEndMs:        Long = 0L
    ) {
        // iOS parity: livePacketCount % 2 gate — fire on every 2nd call (~10s).
        livePacketCount++
        if (livePacketCount % 2 != 0) return

        Log.d(TAG, "startInference: isReady=${_isReady.value} " +
                "imu=${imuMatrix.size} posture=${postureSeries.size} " +
                "tSkin=${"%.1f".format(tSkin)} flux=${"%.3f".format(heatFluxCalPerSec)}")

        val interp = interpreter ?: run {
            Log.w(TAG, "startInference: interpreter null — model not yet loaded")
            return
        }
        if (!_isReady.value)          { Log.w(TAG, "startInference: isReady=false"); return }
        if (inferenceInFlight)        { Log.d(TAG, "startInference: in-flight, skipping"); return }
        if (imuMatrix.size < IMU_SAMPLES) {
            Log.w(TAG, "startInference: ${imuMatrix.size} IMU rows < $IMU_SAMPLES needed"); return
        }
        if (postureSeries.size < POSTURE_SAMPLES) {
            Log.d(TAG, "startInference: ${postureSeries.size} posture rows < $POSTURE_SAMPLES — " +
                    "posture buffer still filling, inference skipped")
            return
        }

        // Long model: check if we have 1000 samples available
        val canRunLong = _isLongReady.value &&
                longInterpreter != null &&
                imuMatrix.size >= LONG_IMU_SAMPLES &&
                postureSeries.size >= LONG_POSTURE_SAMPLES

        inferenceInFlight = true
        engineScope.launch {
            try {
                runInference(interp, imuMatrix, tSkin, outerC, heatFluxCalPerSec,
                    postureSeries, windowStartMs, windowEndMs)
                if (canRunLong) {
                    longInterpreter?.let { li ->
                        runLongInference(li, imuMatrix, tSkin, outerC, heatFluxCalPerSec, postureSeries)
                    }
                }
            } catch (e: Exception) {
                Log.e(TAG, "Inference failed: $e", e)
            } finally {
                inferenceInFlight = false
            }
        }
    }

    // ── Internal: build tensors and run the model ──────────────────────────────

    private fun runInference(
        interp:             org.tensorflow.lite.Interpreter,
        imuMatrix:          Array<FloatArray>,
        tSkin:              Double,
        outerC:             Double,
        heatFluxCalPerSec:  Double,
        postureSeries:      List<FloatArray>,
        windowStartMs:      Long,
        windowEndMs:        Long
    ) {
        // ── Input 0: imu_input — float32[1, 250, 7] ──────────────────────────
        val imuBuffer = ByteBuffer
            .allocateDirect(IMU_SAMPLES * IMU_CHANNELS * 4)
            .order(ByteOrder.nativeOrder())
        for (row in imuMatrix.takeLast(IMU_SAMPLES)) {
            check(row.size == IMU_CHANNELS) {
                "IMU row has ${row.size} channels, expected $IMU_CHANNELS"
            }
            for (v in row) imuBuffer.putFloat(v)
        }
        imuBuffer.rewind()

        // ── Input 1: temp_input — float32[1, 3] ──────────────────────────────
        val tempBuffer = ByteBuffer
            .allocateDirect(TEMP_FEATURES * 4)
            .order(ByteOrder.nativeOrder())
        tempBuffer.putFloat(tSkin.toFloat())
        tempBuffer.putFloat(outerC.toFloat())
        tempBuffer.putFloat(heatFluxCalPerSec.toFloat())
        tempBuffer.rewind()

        // ── Input 2: posture_input — float32[1, 250, 4] ──────────────────────
        val postureBuffer = ByteBuffer
            .allocateDirect(POSTURE_SAMPLES * POSTURE_CHANNELS * 4)
            .order(ByteOrder.nativeOrder())
        for (p in postureSeries.takeLast(POSTURE_SAMPLES)) {
            postureBuffer.putFloat(if (p.size > 0) p[0] else 0f)  // headAngle
            postureBuffer.putFloat(if (p.size > 1) p[1] else 0f)  // fwdFrac
            postureBuffer.putFloat(if (p.size > 2) p[2] else 0f)  // backFrac
            postureBuffer.putFloat(if (p.size > 3) p[3] else 0f)  // latFrac
        }
        postureBuffer.rewind()

        // ── Output: Identity — float32[1, 5] ─────────────────────────────────
        val outputBuffer = Array(1) { FloatArray(NUM_CLASSES) }
        val outputs = HashMap<Int, Any>().apply { put(0, outputBuffer) }

        interp.runForMultipleInputsOutputs(
            arrayOf(imuBuffer, tempBuffer, postureBuffer),
            outputs
        )

        val probs  = outputBuffer[0].map { it.toDouble() }
        val topIdx = probs.indices.maxByOrNull { probs[it] } ?: 0
        Log.d(TAG, "Inference → ${labels[topIdx]} ${"%.0f".format(probs[topIdx]*100)}% " +
                "win=${windowStartMs/1000}..${windowEndMs/1000}s " +
                "[${probs.mapIndexed { i, p -> "${labels[i][0]}=${"%.0f".format(p*100)}%"}.joinToString(" ")}]")

        // ── iOS parity: compute InferenceInputs averages for DebugScreen ──────
        val n = imuMatrix.size.toFloat().coerceAtLeast(1f)
        var axS=0f; var ayS=0f; var azS=0f; var gxS=0f; var gyS=0f; var gzS=0f
        for (row in imuMatrix.takeLast(IMU_SAMPLES)) {
            axS+=row[0]; ayS+=row[1]; azS+=row[2]; gxS+=row[4]; gyS+=row[5]; gzS+=row[6]
        }
        var haS=0f; var fwS=0f; var bkS=0f; var ltS=0f
        for (p in postureSeries.takeLast(POSTURE_SAMPLES)) {
            haS+=if(p.size>0) p[0] else 0f; fwS+=if(p.size>1) p[1] else 0f
            bkS+=if(p.size>2) p[2] else 0f; ltS+=if(p.size>3) p[3] else 0f
        }
        val inputs = InferenceInputs(
            accelXAvg=axS/n, accelYAvg=ayS/n, accelZAvg=azS/n,
            gyroXAvg=gxS/n,  gyroYAvg=gyS/n,  gyroZAvg=gzS/n,
            headAngleAvg=haS/n, fwdAvg=fwS/n, backAvg=bkS/n, latAvg=ltS/n,
            tSkin=tSkin, outerTemp=outerC, heatFlux=heatFluxCalPerSec
        )
        _lastInferenceInputs.value = inputs

        updateResults(probs, windowStartMs, windowEndMs)
    }

    // ── Long model (V1_1000): Car, Eating, Scooter ────────────────────────────
    private fun runLongInference(
        interp:            org.tensorflow.lite.Interpreter,
        imuMatrix:         Array<FloatArray>,
        tSkin:             Double,
        outerC:            Double,
        heatFluxCalPerSec: Double,
        postureSeries:     List<FloatArray>
    ) {
        val imuBuf = ByteBuffer.allocateDirect(LONG_IMU_SAMPLES * IMU_CHANNELS * 4)
            .order(ByteOrder.nativeOrder())
        for (row in imuMatrix.takeLast(LONG_IMU_SAMPLES)) {
            for (v in row) imuBuf.putFloat(v)
        }
        imuBuf.rewind()

        val tempBuf = ByteBuffer.allocateDirect(TEMP_FEATURES * 4).order(ByteOrder.nativeOrder())
        tempBuf.putFloat(tSkin.toFloat()); tempBuf.putFloat(outerC.toFloat())
        tempBuf.putFloat(heatFluxCalPerSec.toFloat()); tempBuf.rewind()

        val postureBuf = ByteBuffer.allocateDirect(LONG_POSTURE_SAMPLES * POSTURE_CHANNELS * 4)
            .order(ByteOrder.nativeOrder())
        for (p in postureSeries.takeLast(LONG_POSTURE_SAMPLES)) {
            postureBuf.putFloat(if(p.size>0) p[0] else 0f); postureBuf.putFloat(if(p.size>1) p[1] else 0f)
            postureBuf.putFloat(if(p.size>2) p[2] else 0f); postureBuf.putFloat(if(p.size>3) p[3] else 0f)
        }
        postureBuf.rewind()

        val out = Array(1) { FloatArray(LONG_NUM_CLASSES) }
        val longOutputs = HashMap<Int, Any>().apply { put(0, out) }
        interp.runForMultipleInputsOutputs(arrayOf(imuBuf, tempBuf, postureBuf), longOutputs)
        val probs  = out[0].map { it.toDouble() }
        val maxIdx = probs.indices.maxByOrNull { probs[it] } ?: 0
        _longCurrentActivity.value  = longlabels[maxIdx]
        _longConfidence.value       = probs[maxIdx]
        _longAllProbabilities.value = probs
        Log.d(TAG, "LongModel → ${longlabels[maxIdx]} ${"%.0f".format(probs[maxIdx]*100)}%")
    }

    // ── Results + MLPredictionStore + ActivityInferenceManager bridge ──────────

    private fun updateResults(probs: List<Double>, windowStartMs: Long, windowEndMs: Long) {
        if (probs.size < NUM_CLASSES) return
        val maxIdx   = probs.indices.maxByOrNull { probs[it] } ?: return
        val maxProb  = probs[maxIdx]
        val activity = labels[maxIdx]

        _currentActivity.value  = activity
        _confidence.value       = maxProb
        _allProbabilities.value = probs

        // ── Persist to MLPredictionStore (iOS parity) ─────────────────────────
        MLPredictionStore.getInstance(context).record(
            label            = activity,
            confidence       = maxProb,
            probabilities    = probs,
            windowStartMs    = windowStartMs,
            windowEndMs      = windowEndMs
        )

        // ── Bridge to ActivityInferenceManager (✓/✗ strip) ───────────────────
        val existing = ActivityInferenceManager.pending.value
        if (existing != null) {
            val pendingIdx         = labels.indexOf(existing.label)
            val pendingCurrentConf = if (pendingIdx >= 0) probs[pendingIdx] else 0.0
            val modelPrefersNew    = activity != existing.label && maxProb > existing.confidence
            val modelLostConf      = pendingCurrentConf < MIN_CONFIDENCE_TO_KEEP_PENDING
            val isStale            = (Date().time - existing.startedAt.time) / 1000.0 > STALE_PENDING_SECONDS
            if (modelPrefersNew || modelLostConf || isStale) {
                ActivityInferenceManager.dismissPrediction()
                lastPushedActivity = ""
            }
        }

        val cooledDown = System.currentTimeMillis() >= confirmCooldownUntil
        if (activity != lastPushedActivity &&
            ActivityInferenceManager.pending.value == null &&
            cooledDown) {
            lastPushedActivity = activity
            ActivityInferenceManager.setPrediction(activity, maxProb)
        }
    }

    // ── Dot colour (returns ARGB Int instead of Compose Color) ───────────────

    fun dotColorInt(activity: String): Int = when (activity) {
        "Running"  -> 0xFFE88C30.toInt()
        "Walking"  -> 0xFF1D9E75.toInt()
        "Sitting"  -> 0xFF43A5BB.toInt()
        "Standing" -> 0xFF2E7D32.toInt()
        "Stairs"   -> 0xFFF0A500.toInt()
        else       -> 0xFF9E9E9E.toInt()
    }
}
