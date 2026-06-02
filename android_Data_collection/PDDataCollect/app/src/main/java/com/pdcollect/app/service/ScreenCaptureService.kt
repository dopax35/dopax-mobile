package com.pdcollect.app.service

import android.app.Activity
import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import android.widget.Toast
import androidx.core.app.NotificationCompat
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.ui.MainActivity
import com.pdcollect.app.util.Constants
import java.io.File
import java.io.FileOutputStream

class ScreenCaptureService : Service() {

    private var mediaProjection: MediaProjection? = null
    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null
    private lateinit var dataManager: DataManager
    private val handler = Handler(Looper.getMainLooper())
    private var previousBitmap: Bitmap? = null
    private var screenWidth = 720
    private var screenHeight = 1280
    private var screenDensity = DisplayMetrics.DENSITY_DEFAULT

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            val timestamp = System.currentTimeMillis()
            dataManager.writeScreenCaptureLog("$timestamp,SERVICE_HEARTBEAT,0,0.0,true")
            handler.postDelayed(this, 1000 * 60) // Once a minute
        }
    }

    override fun onCreate() {
        super.onCreate()
        val profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getMetrics(metrics)
        // Align to multiple of 16 for hardware scaler compatibility
        screenWidth = (metrics.widthPixels / 16) * 16
        screenHeight = (metrics.heightPixels / 16) * 16
        screenDensity = metrics.densityDpi
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val resultCode = intent?.getIntExtra("resultCode", Activity.RESULT_CANCELED) ?: Activity.RESULT_CANCELED
        val data = intent?.getParcelableExtra<Intent>("data")

        if (resultCode != Activity.RESULT_OK || data == null) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                Constants.NOTIFICATION_ID_SCREEN,
                buildNotification(),
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
            )
        } else {
            startForeground(Constants.NOTIFICATION_ID_SCREEN, buildNotification())
        }

        val projectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        mediaProjection = projectionManager.getMediaProjection(resultCode, data)
        // Must register callback before createVirtualDisplay on Android 14+
        mediaProjection?.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                virtualDisplay?.release()
                imageReader?.close()
                handler.removeCallbacks(heartbeatRunnable)
            }
        }, handler)
        handler.removeCallbacks(heartbeatRunnable)
        setupVirtualDisplay()
        handler.post(heartbeatRunnable)

        // Log service start and storage path for transparency
        val timestamp = System.currentTimeMillis()
        val path = dataManager.screenshotsDir().absolutePath
        dataManager.writeScreenCaptureLog("$timestamp,SERVICE_STARTED,0,0.0,true,PATH:$path")
        
        return START_NOT_STICKY
    }

    private fun setupVirtualDisplay() {
        imageReader?.close()
        // Capture at 50% scale, aligned to multiple of 16
        val captureWidth = (screenWidth / 32) * 16 
        val captureHeight = (screenHeight / 32) * 16

        imageReader = ImageReader.newInstance(
            captureWidth, captureHeight,
            PixelFormat.RGBA_8888, 2
        )
        
        imageReader?.setOnImageAvailableListener({ reader ->
            captureScreenFromReader(reader)
        }, handler)

        virtualDisplay = mediaProjection?.createVirtualDisplay(
            "PDScreenCapture",
            captureWidth, captureHeight, screenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            imageReader!!.surface, null, handler
        )
    }

    private fun captureScreenFromReader(reader: ImageReader) {
        val latestImage = reader.acquireLatestImage() ?: return
        processImage(latestImage)
    }

    private var nullImgCount = 0

    private fun processImage(image: android.media.Image) {
        nullImgCount = 0

        try {
            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * image.width

            buffer.position(0)
            val bitmap = Bitmap.createBitmap(
                image.width + rowPadding / pixelStride,
                image.height,
                Bitmap.Config.ARGB_8888
            )
            buffer.position(0)
            bitmap.copyPixelsFromBuffer(buffer)

            val cropped = Bitmap.createBitmap(bitmap, 0, 0, image.width, image.height)
            if (bitmap != cropped) bitmap.recycle()

            val timestamp = System.currentTimeMillis()
            val pkg = getForegroundPackageName()
            val (diffCount, diffPercent) = calculateDiff(cropped)
            // Guarantee image saves even on tiny ui updates
            val isSignificant = diffPercent > 0.0001f 
            
            // Record analytics even if we don't save the image
            val logRow = "$timestamp,$pkg,$diffCount,${"%.4f".format(diffPercent)},$isSignificant"
            dataManager.writeScreenCaptureLog(logRow)

            if (isSignificant || previousBitmap == null) {
                saveBitmap(cropped, timestamp)
                previousBitmap?.recycle()
                previousBitmap = cropped
            } else {
                cropped.recycle()
            }
        } catch (e: Exception) {
            android.util.Log.e("ScreenCapture", "Failed capture math", e)
        } finally {
            image.close()
        }
    }

    private fun getForegroundPackageName(): String {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as android.app.usage.UsageStatsManager
        val time = System.currentTimeMillis()
        val stats = usm.queryUsageStats(android.app.usage.UsageStatsManager.INTERVAL_DAILY, time - 1000 * 60, time)
        if (!stats.isNullOrEmpty()) {
            return stats.maxByOrNull { it.lastTimeUsed }?.packageName ?: "unknown"
        }
        return "unknown"
    }

    private fun calculateDiff(current: Bitmap): Pair<Int, Float> {
        val prev = previousBitmap ?: return Pair(0, 1.0f)
        if (prev.width != current.width || prev.height != current.height) return Pair(0, 1.0f)

        val sampleSize = 100
        var diffCount = 0
        val totalPixels = current.width * current.height
        val step = maxOf(1, totalPixels / sampleSize)
        
        var i = 0
        while (i < totalPixels) {
            val x = i % current.width
            val y = i / current.width
            if (current.getPixel(x, y) != prev.getPixel(x, y)) diffCount++
            i += step
        }

        val percent = diffCount.toFloat() / sampleSize
        // Estimate total changed pixels based on sample
        val estimatedTotalDiff = (percent * totalPixels).toInt()
        
        return Pair(estimatedTotalDiff, percent)
    }

    private var firstSaveToastShown = false

    private fun saveBitmap(bitmap: Bitmap, timestamp: Long) {
        val dir = dataManager.screenshotsDir()
        val file = File(dir, "screen_$timestamp.jpg")
        FileOutputStream(file).use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, Constants.SCREENSHOT_QUALITY, out)
        }
        if (!firstSaveToastShown) {
            handler.post {
                Toast.makeText(this, "Screen Capture Active! Saved first image.", Toast.LENGTH_SHORT).show()
            }
            firstSaveToastShown = true
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        handler.removeCallbacks(heartbeatRunnable)
        virtualDisplay?.release()
        imageReader?.close()
        mediaProjection?.stop()
        previousBitmap?.recycle()
        dataManager.closeAll()
        super.onDestroy()
    }

    private fun buildNotification(): Notification {
        val intent = Intent(this, MainActivity::class.java)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, intent, PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, Constants.CHANNEL_SCREEN)
            .setContentTitle("PD Data Collection")
            .setContentText("Screen capture active")
            .setSmallIcon(R.drawable.ic_notification)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    companion object {
        fun start(context: Context, resultCode: Int, data: Intent) {
            val intent = Intent(context, ScreenCaptureService::class.java).apply {
                putExtra("resultCode", resultCode)
                putExtra("data", data)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ScreenCaptureService::class.java))
        }
    }
}
