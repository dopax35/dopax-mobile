package com.pdcollect.app.service

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.util.Size
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2CameraInfo
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import androidx.camera.core.resolutionselector.ResolutionSelector
import androidx.camera.core.resolutionselector.ResolutionStrategy
import com.pdcollect.app.util.Constants
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.sqrt

/**
 * Shared face-distance recorder used by both the always-on service and TMT-only capture.
 *
 * Distance is estimated from the horizontal distance between eye landmarks using:
 *
 *   distance_cm = focal_px * assumed_ipd_cm * cos(yaw) / observed_eye_distance_px
 *
 * Where focal_px comes from camera intrinsics when available, otherwise from
 * focal length + sensor size metadata. We prefer the inter-eye method over a
 * face-box heuristic because it is less sensitive to hairstyle, cheeks, and
 * detector box padding.
 */
class FaceDistanceRecorder(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner,
    private val captureContext: String,
    private val sampleIntervalMs: Long = Constants.FACE_CAPTURE_INTERVAL_MS,
    private val onSample: (DistanceSample) -> Unit,
    private val onBlink: ((BlinkSample) -> Unit)? = null,
    private val onGaze: ((GazeSample) -> Unit)? = null,
    private val onError: (Throwable) -> Unit = {}
) {

    /** Emitted per frame for eye/pupil gaze tracking across timestamps. */
    data class GazeSample(
        val timestampMs: Long,
        val leftGazeX: Float,
        val leftGazeY: Float,
        val rightGazeX: Float,
        val rightGazeY: Float,
        val leftBlink: Float,
        val rightBlink: Float,
        val lookAtX: Float,
        val lookAtY: Float,
        val lookAtZ: Float,
        val method: String
    ) {
        fun toCsvRow(): String {
            return listOf(
                timestampMs.toString(),
                formatFloat(leftGazeX),
                formatFloat(leftGazeY),
                formatFloat(rightGazeX),
                formatFloat(rightGazeY),
                formatFloat(leftBlink),
                formatFloat(rightBlink),
                formatFloat(lookAtX),
                formatFloat(lookAtY),
                formatFloat(lookAtZ),
                method
            ).joinToString(",")
        }

        private fun formatFloat(value: Float): String = if (value.isFinite()) {
            String.format(Locale.US, "%.4f", value)
        } else {
            "0.0000"
        }
    }

    /** Emitted once per completed blink (eyes-closed → eyes-open transition). */
    data class BlinkSample(
        val timestampMs: Long,
        val captureContext: String,
        val leftTroughProb: Float,
        val rightTroughProb: Float,
        val blinkRatePerMin: Float
    ) {
        fun toCsvRow(): String = "$timestampMs,$captureContext," +
            "${String.format(Locale.US, "%.4f", leftTroughProb)}," +
            "${String.format(Locale.US, "%.4f", rightTroughProb)}," +
            String.format(Locale.US, "%.2f", blinkRatePerMin)
    }

    data class DistanceSample(
        val timestampMs: Long,
        val context: String,
        val faceDetected: Boolean,
        val landmarksDetected: Boolean,
        val eyeDistancePx: Float,
        val focalLengthPx: Double,
        val estimatedCm: Double,
        val confidence: Float,
        val headEulerY: Float,
        val headEulerZ: Float,
        val method: String
    ) {
        fun toCsvRow(): String {
            return listOf(
                timestampMs.toString(),
                context,
                faceDetected.toString(),
                landmarksDetected.toString(),
                formatFloat(eyeDistancePx),
                formatDouble(focalLengthPx),
                formatDouble(estimatedCm),
                formatFloat(confidence),
                formatFloat(headEulerY),
                formatFloat(headEulerZ),
                method
            ).joinToString(",")
        }

        private fun formatDouble(value: Double): String = if (value.isFinite()) {
            String.format(Locale.US, "%.4f", value)
        } else {
            "-1.0000"
        }

        private fun formatFloat(value: Float): String = if (value.isFinite()) {
            String.format(Locale.US, "%.4f", value)
        } else {
            "-1.0000"
        }
    }

    private data class CameraCalibration(
        val fxPx: Double?,
        val fyPx: Double?,
        val sensorWidthMm: Double?,
        val sensorHeightMm: Double?,
        val focalLengthMm: Double?
    )

    private val detector: FaceDetector by lazy {
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .build()
        FaceDetection.getClient(options)
    }

    private val analysisExecutor = Executors.newSingleThreadExecutor()
    private var cameraProvider: ProcessCameraProvider? = null
    private var calibration: CameraCalibration? = null
    private var lastCaptureTimeMs = 0L
    private var inFlight = false
    private var running = false
    private val recentDistanceEstimatesCm = ArrayDeque<Double>()

    // Blink detection state — all accessed from the ML Kit success callback (main thread)
    private val blinkDetector = BlinkDetector()

    fun start() {
        if (running) return
        running = true
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            try {
                bind(providerFuture.get())
            } catch (t: Throwable) {
                running = false
                onError(t)
            }
        }, ContextCompat.getMainExecutor(context))
    }

    fun stop() {
        running = false
        inFlight = false
        cameraProvider?.unbindAll()
        runCatching { detector.close() }
        analysisExecutor.shutdown()
    }

    private fun bind(provider: ProcessCameraProvider) {
        cameraProvider = provider

        val resolutionSelector = ResolutionSelector.Builder()
            .setResolutionStrategy(
                ResolutionStrategy(
                    Size(320, 240),
                    ResolutionStrategy.FALLBACK_RULE_CLOSEST_HIGHER_THEN_LOWER
                )
            )
            .build()

        val imageAnalysis = ImageAnalysis.Builder()
            .setResolutionSelector(resolutionSelector)
            .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
            .build()

        imageAnalysis.setAnalyzer(analysisExecutor) { imageProxy ->
            analyze(imageProxy)
        }

        provider.unbindAll()
        val camera = provider.bindToLifecycle(
            lifecycleOwner,
            CameraSelector.DEFAULT_FRONT_CAMERA,
            imageAnalysis
        )

        calibration = resolveCalibration(camera.cameraInfo)
    }

    @OptIn(ExperimentalGetImage::class)
    private fun analyze(imageProxy: ImageProxy) {
        val now = System.currentTimeMillis()
        if (!running || inFlight || now - lastCaptureTimeMs < sampleIntervalMs) {
            imageProxy.close()
            return
        }

        val mediaImage = imageProxy.image
        if (mediaImage == null) {
            imageProxy.close()
            return
        }

        inFlight = true
        lastCaptureTimeMs = now

        val frameWidth = imageProxy.width
        val frameHeight = imageProxy.height
        val rotation = imageProxy.imageInfo.rotationDegrees
        val inputImage = InputImage.fromMediaImage(mediaImage, rotation)

        detector.process(inputImage)
            .addOnSuccessListener { faces ->
                val timestamp = System.currentTimeMillis()
                val face = faces.firstOrNull()
                val sample = buildSample(
                    timestampMs = timestamp,
                    face = face,
                    frameWidthPx = frameWidth,
                    frameHeightPx = frameHeight,
                    rotationDegrees = rotation
                )
                onSample(sample)
                if (face != null) {
                    if (onBlink != null) {
                        processBlink(face, timestamp)
                    }
                    onGaze?.invoke(buildGazeSample(timestamp, face, frameWidth, frameHeight))
                }
            }
            .addOnFailureListener(onError)
            .addOnCompleteListener {
                inFlight = false
                imageProxy.close()
            }
    }

    private fun buildSample(
        timestampMs: Long,
        face: Face?,
        frameWidthPx: Int,
        frameHeightPx: Int,
        rotationDegrees: Int
    ): DistanceSample {
        if (face == null) {
            return DistanceSample(
                timestampMs = timestampMs,
                context = captureContext,
                faceDetected = false,
                landmarksDetected = false,
                eyeDistancePx = -1f,
                focalLengthPx = -1.0,
                estimatedCm = -1.0,
                confidence = 0f,
                headEulerY = 0f,
                headEulerZ = 0f,
                method = "no_face"
            )
        }

        val leftEye = face.getLandmark(FaceLandmark.LEFT_EYE)?.position
        val rightEye = face.getLandmark(FaceLandmark.RIGHT_EYE)?.position
        if (leftEye == null || rightEye == null) {
            return DistanceSample(
                timestampMs = timestampMs,
                context = captureContext,
                faceDetected = true,
                landmarksDetected = false,
                eyeDistancePx = -1f,
                focalLengthPx = -1.0,
                estimatedCm = -1.0,
                confidence = 0.1f,
                headEulerY = face.headEulerAngleY,
                headEulerZ = face.headEulerAngleZ,
                method = "missing_landmarks"
            )
        }

        val observedEyeDistancePx = sqrt(
            ((leftEye.x - rightEye.x) * (leftEye.x - rightEye.x) +
                (leftEye.y - rightEye.y) * (leftEye.y - rightEye.y)).toDouble()
        ).toFloat()

        val focalLengthPx = resolveFocalLengthPx(frameWidthPx, frameHeightPx, rotationDegrees)
        if (!focalLengthPx.isFinite() || focalLengthPx <= 0.0f || observedEyeDistancePx <= 0f) {
            return DistanceSample(
                timestampMs = timestampMs,
                context = captureContext,
                faceDetected = true,
                landmarksDetected = true,
                eyeDistancePx = observedEyeDistancePx,
                focalLengthPx = -1.0,
                estimatedCm = -1.0,
                confidence = 0.2f,
                headEulerY = face.headEulerAngleY,
                headEulerZ = face.headEulerAngleZ,
                method = "camera_metadata_unavailable"
            )
        }

        val yawRadians = Math.toRadians(face.headEulerAngleY.toDouble())
        val yawCorrection = cos(yawRadians).coerceAtLeast(0.5)
        val assumedIpdCm = 6.3
        val estimatedCm = (focalLengthPx * assumedIpdCm * yawCorrection) / observedEyeDistancePx
        val confidence = computeConfidence(face, observedEyeDistancePx, estimatedCm)
        val smoothedEstimatedCm = smoothDistanceEstimate(estimatedCm, confidence)
        val methodBase = if (calibration?.fxPx != null || calibration?.fyPx != null) {
            "ipd_intrinsics"
        } else {
            "ipd_fallback"
        }
        val method = if (recentDistanceEstimatesCm.size >= 3) {
            "${methodBase}_median5"
        } else {
            methodBase
        }

        return DistanceSample(
            timestampMs = timestampMs,
            context = captureContext,
            faceDetected = true,
            landmarksDetected = true,
            eyeDistancePx = observedEyeDistancePx,
            focalLengthPx = focalLengthPx.toDouble(),
            estimatedCm = smoothedEstimatedCm,
            confidence = confidence,
            headEulerY = face.headEulerAngleY,
            headEulerZ = face.headEulerAngleZ,
            method = method
        )
    }

    private fun computeConfidence(face: Face, eyeDistancePx: Float, estimatedCm: Double): Float {
        val yawScore = (1f - (abs(face.headEulerAngleY) / 30f)).coerceIn(0f, 1f)
        val rollScore = (1f - (abs(face.headEulerAngleZ) / 20f)).coerceIn(0f, 1f)
        val sizeScore = ((eyeDistancePx - 18f) / 90f).coerceIn(0f, 1f)
        val distanceScore = if (estimatedCm in 15.0..90.0) 1f else 0.25f
        val focalScore = if (calibration?.fxPx != null || calibration?.fyPx != null) 1f else 0.7f
        return (yawScore * 0.3f + rollScore * 0.2f + sizeScore * 0.3f + distanceScore * 0.1f + focalScore * 0.1f)
            .coerceIn(0f, 1f)
    }

    private fun smoothDistanceEstimate(rawDistanceCm: Double, confidence: Float): Double {
        if (rawDistanceCm.isFinite() && confidence >= MIN_SMOOTHING_CONFIDENCE) {
            recentDistanceEstimatesCm.addLast(rawDistanceCm)
            while (recentDistanceEstimatesCm.size > MAX_SMOOTHING_SAMPLES) {
                recentDistanceEstimatesCm.removeFirst()
            }
        }

        if (recentDistanceEstimatesCm.size < 3) {
            return rawDistanceCm
        }

        val sorted = recentDistanceEstimatesCm.sorted()
        return sorted[sorted.size / 2]
    }

    private fun resolveFocalLengthPx(
        frameWidthPx: Int,
        frameHeightPx: Int,
        rotationDegrees: Int
    ): Float {
        val localCalibration = calibration ?: return Float.NaN
        val rotated = rotationDegrees == 90 || rotationDegrees == 270

        val intrinsic = if (rotated) localCalibration.fyPx else localCalibration.fxPx
        if (intrinsic != null && intrinsic > 0.0) return intrinsic.toFloat()

        val sensorMm = if (rotated) localCalibration.sensorHeightMm else localCalibration.sensorWidthMm
        val framePx = if (rotated) frameHeightPx else frameWidthPx
        val focalMm = localCalibration.focalLengthMm
        if (sensorMm == null || sensorMm <= 0.0 || focalMm == null || focalMm <= 0.0) {
            return Float.NaN
        }

        return (framePx.toDouble() * focalMm / sensorMm).toFloat()
    }

    @OptIn(ExperimentalCamera2Interop::class)
    private fun resolveCalibration(cameraInfo: androidx.camera.core.CameraInfo): CameraCalibration {
        return try {
            val camera2Info = Camera2CameraInfo.from(cameraInfo)
            val intrinsics = camera2Info.getCameraCharacteristic(CameraCharacteristics.LENS_INTRINSIC_CALIBRATION)
            val sensorSize = camera2Info.getCameraCharacteristic(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)
            val focalLengths = camera2Info.getCameraCharacteristic(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)

            CameraCalibration(
                fxPx = intrinsics?.getOrNull(0)?.toDouble(),
                fyPx = intrinsics?.getOrNull(1)?.toDouble(),
                sensorWidthMm = sensorSize?.width?.toDouble(),
                sensorHeightMm = sensorSize?.height?.toDouble(),
                focalLengthMm = focalLengths?.firstOrNull()?.toDouble()
            )
        } catch (_: Throwable) {
            CameraCalibration(
                fxPx = null,
                fyPx = null,
                sensorWidthMm = null,
                sensorHeightMm = null,
                focalLengthMm = null
            )
        }
    }

    /**
     * State machine for blink detection.
     * Called on the ML Kit success-listener thread (main thread) once per frame.
     *
     * Algorithm:
     *   OPEN  → CLOSED : avgProb drops below BLINK_CLOSE_THRESHOLD
     *   CLOSED → OPEN  : avgProb rises above BLINK_OPEN_THRESHOLD  (hysteresis gap avoids noise)
     *   On the CLOSED→OPEN transition a BlinkSample is emitted.
     */
    private fun processBlink(face: Face, timestampMs: Long) {
        val leftProb  = face.leftEyeOpenProbability  ?: return
        val rightProb = face.rightEyeOpenProbability ?: return
        val event = blinkDetector.onProbabilities(timestampMs, leftProb, rightProb) ?: return
        onBlink?.invoke(
            BlinkSample(
                timestampMs = event.timestampMs,
                captureContext = captureContext,
                leftTroughProb = event.leftTroughProb,
                rightTroughProb = event.rightTroughProb,
                blinkRatePerMin = event.blinkRatePerMin
            )
        )
    }

    private fun buildGazeSample(
        timestampMs: Long,
        face: Face,
        frameWidthPx: Int,
        frameHeightPx: Int
    ): GazeSample {
        val leftEye = face.getLandmark(FaceLandmark.LEFT_EYE)?.position
        val rightEye = face.getLandmark(FaceLandmark.RIGHT_EYE)?.position

        val boundingBox = face.boundingBox
        val boxWidth = boundingBox.width().toFloat().coerceAtLeast(1.0f)
        val boxHeight = boundingBox.height().toFloat().coerceAtLeast(1.0f)
        val boxCenterX = boundingBox.centerX().toFloat()
        val boxCenterY = boundingBox.centerY().toFloat()

        // Normalize pupil/eye position relative to face bounding box
        val leftGazeX = leftEye?.let { (it.x - boxCenterX) / boxWidth } ?: 0f
        val leftGazeY = leftEye?.let { (it.y - boxCenterY) / boxHeight } ?: 0f
        val rightGazeX = rightEye?.let { (it.x - boxCenterX) / boxWidth } ?: 0f
        val rightGazeY = rightEye?.let { (it.y - boxCenterY) / boxHeight } ?: 0f

        val leftBlink = face.leftEyeOpenProbability ?: 1.0f
        val rightBlink = face.rightEyeOpenProbability ?: 1.0f

        return GazeSample(
            timestampMs = timestampMs,
            leftGazeX = leftGazeX,
            leftGazeY = leftGazeY,
            rightGazeX = rightGazeX,
            rightGazeY = rightGazeY,
            leftBlink = leftBlink,
            rightBlink = rightBlink,
            lookAtX = face.headEulerAngleY, // head yaw proxy
            lookAtY = face.headEulerAngleZ, // head roll proxy
            lookAtZ = face.headEulerAngleX, // head pitch proxy
            method = "mlkit_face_landmarks"
        )
    }

    companion object {
        private const val MAX_SMOOTHING_SAMPLES = 5
        private const val MIN_SMOOTHING_CONFIDENCE = 0.35f
    }
}
