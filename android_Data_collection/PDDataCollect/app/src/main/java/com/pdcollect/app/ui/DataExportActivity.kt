package com.pdcollect.app.ui

import android.app.AlertDialog
import android.app.ProgressDialog
import android.content.Intent
import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.core.content.FileProvider
import androidx.recyclerview.widget.LinearLayoutManager
import androidx.recyclerview.widget.RecyclerView
import com.pdcollect.app.R
import com.pdcollect.app.data.DataManager
import com.pdcollect.app.data.UserProfile
import com.pdcollect.app.util.UploadState

class DataExportActivity : AppCompatActivity() {

    private lateinit var dataManager: DataManager
    private lateinit var profile: UserProfile
    private lateinit var adapter: DateAdapter
    private lateinit var recyclerView: androidx.recyclerview.widget.RecyclerView
    private lateinit var tvEmpty: android.widget.TextView
    private val dateEntries = mutableListOf<DataManager.DateEntry>()
    private val deletingDates = mutableSetOf<String>()
    private val handler = android.os.Handler(android.os.Looper.getMainLooper())
    private val refreshRunnable = object : Runnable {
        override fun run() {
            if (deletingDates.isEmpty()) {
                refreshList()
            }
            handler.postDelayed(this, 2000)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_data_export)

        /*
        val toolbar = findViewById<androidx.appcompat.widget.Toolbar>(R.id.toolbar)
        setSupportActionBar(toolbar)
        supportActionBar?.setDisplayHomeAsUpEnabled(true)
        toolbar.setNavigationOnClickListener { finish() }
        */

        profile = UserProfile(this)
        dataManager = DataManager(this, profile)

        recyclerView = findViewById(R.id.recyclerDates)
        tvEmpty = findViewById(R.id.tvEmpty)

        adapter = DateAdapter()
        recyclerView.layoutManager = LinearLayoutManager(this)
        recyclerView.adapter = adapter

        findViewById<android.widget.Button>(R.id.btnBack).setOnClickListener {
            finish()
        }
    }

    override fun onResume() {
        super.onResume()
        handler.post(refreshRunnable)
    }

    override fun onDestroy() {
        super.onDestroy()
        // DataManager starts a background HandlerThread in its constructor
        // that only stops via closeAll(); this screen is reachable repeatedly
        // from the nav drawer ("Data & Privacy"), so each visit was leaking
        // one more idle thread for the rest of the app process's life.
        dataManager.closeAll()
    }

    override fun onPause() {
        super.onPause()
        handler.removeCallbacks(refreshRunnable)
    }

    private fun refreshList() {
        dateEntries.clear()
        dateEntries.addAll(dataManager.listAvailableDates())
        adapter.notifyDataSetChanged()

        if (dateEntries.isEmpty()) {
            recyclerView.visibility = View.GONE
            tvEmpty.visibility = View.VISIBLE
        } else {
            recyclerView.visibility = View.VISIBLE
            tvEmpty.visibility = View.GONE
        }
    }

    private fun formatSize(bytes: Long): String {
        return when {
            bytes >= 1024 * 1024 * 1024 -> "%.1f GB".format(bytes / (1024.0 * 1024.0 * 1024.0))
            bytes >= 1024 * 1024 -> "%.1f MB".format(bytes / (1024.0 * 1024.0))
            bytes >= 1024 -> "%.1f KB".format(bytes / 1024.0)
            else -> "$bytes B"
        }
    }

    @Suppress("DEPRECATION")
    private fun exportDate(dateStr: String) {
        val dateDir = java.io.File(dataManager.getStoragePath(), dateStr)
        if (UploadState.isUploaded(dateDir)) {
            Toast.makeText(this, "$dateStr is already uploaded", Toast.LENGTH_SHORT).show()
            return
        }
        if (!dataManager.dateHasRecordedData(dateStr)) {
            Toast.makeText(this, "No recorded data rows for $dateStr", Toast.LENGTH_LONG).show()
            return
        }
        if (!UploadState.tryClaimUpload(dateDir)) {
            Toast.makeText(this, "Upload already in progress for $dateStr", Toast.LENGTH_SHORT).show()
            return
        }

        val progress = ProgressDialog(this).apply {
            setMessage("Zipping data for $dateStr...")
            setCancelable(false)
            show()
        }

        Thread {
            var zipFile: java.io.File? = null
            var uploadSucceeded = false
            try {
                zipFile = dataManager.zipDateData(dateStr)
                runOnUiThread {
                    val createdZip = zipFile
                    if (createdZip == null || !createdZip.exists() || createdZip.length() <= 0L) {
                        progress.dismiss()
                        Toast.makeText(this, "Failed to create non-empty zip", Toast.LENGTH_SHORT).show()
                        return@runOnUiThread
                    }
                    progress.setMessage("Uploading to Secure Cloud (Drive)...")
                }
                
                val zip = zipFile
                if (zip == null || !zip.exists() || zip.length() <= 0L) return@Thread
                
                uploadSucceeded = com.pdcollect.app.util.CloudUploader.uploadZipFileSync(zip, profile.userId, dateStr)
                if (uploadSucceeded) {
                    try {
                        UploadState.markUploaded(
                            dateDir,
                            UploadState.cloudFilename(profile.userId, dateStr),
                            zip.length()
                        )
                    } catch (e: Exception) {
                        android.util.Log.e("DataExport", "Failed to create upload marker", e)
                    }
                }
                
                runOnUiThread {
                    progress.dismiss()
                    if (uploadSucceeded) {
                        Toast.makeText(this, "Successfully uploaded $dateStr to Cloud", Toast.LENGTH_LONG).show()
                        refreshList()
                    } else {
                        Toast.makeText(this, "Failed to upload to Cloud. Check internet connection or Web App setup.", Toast.LENGTH_LONG).show()
                    }
                }
            } finally {
                zipFile?.delete()
                if (!uploadSucceeded) {
                    UploadState.clearUploadClaim(dateDir)
                }
            }
        }.start()
    }

    private fun confirmDelete(dateStr: String) {
        // Defence in depth: the "Delete" button is already disabled for today in
        // onBindViewHolder, but guard here too since active foreground services
        // (PDCollectService, FaceDistanceService, etc.) hold open writers to today's
        // directory in this same process — deleting it out from under them would
        // unlink the directory while writes keep silently succeeding into thin air,
        // losing the rest of that day's data with no error surfaced anywhere.
        if (dateStr == com.pdcollect.app.util.TimeUtils.todayDateString()) {
            Toast.makeText(this, "Today's data can't be deleted while it's still being collected", Toast.LENGTH_SHORT).show()
            return
        }
        AlertDialog.Builder(this)
            .setTitle("Delete Data")
            .setMessage("This will permanently delete all data for $dateStr. This action cannot be undone.")
            .setPositiveButton("Delete") { _, _ ->
                deleteDateInBackground(dateStr)
            }
            .setNegativeButton("Cancel", null)
            .show()
    }

    @Suppress("DEPRECATION")
    private fun deleteDateInBackground(dateStr: String) {
        if (!deletingDates.add(dateStr)) return
        adapter.notifyDataSetChanged()

        val progress = ProgressDialog(this).apply {
            setMessage("Deleting data for $dateStr...")
            setCancelable(false)
            show()
        }

        Thread({
            val success = try {
                dataManager.deleteDateData(dateStr)
            } catch (e: Exception) {
                android.util.Log.e("DataExport", "Failed to delete data for $dateStr", e)
                false
            }

            runOnUiThread {
                deletingDates.remove(dateStr)
                progress.dismiss()
                if (success) {
                    Toast.makeText(this, "Deleted data for $dateStr", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "Failed to delete data for $dateStr", Toast.LENGTH_SHORT).show()
                }
                refreshList()
            }
        }, "DeleteData-$dateStr").start()
    }

    private inner class DateAdapter : RecyclerView.Adapter<DateAdapter.DateViewHolder>() {

        inner class DateViewHolder(view: View) : RecyclerView.ViewHolder(view) {
            val tvDate: TextView = view.findViewById(R.id.tvDate)
            val tvSize: TextView = view.findViewById(R.id.tvSize)
            val tvFileCount: TextView = view.findViewById(R.id.tvFileCount)
            val btnExport: Button = view.findViewById(R.id.btnExport)
            val btnDelete: Button = view.findViewById(R.id.btnDelete)
            val ivUploaded: android.widget.ImageView = view.findViewById(R.id.ivUploaded)
        }

        override fun onCreateViewHolder(parent: ViewGroup, viewType: Int): DateViewHolder {
            val view = LayoutInflater.from(parent.context)
                .inflate(R.layout.item_date_entry, parent, false)
            return DateViewHolder(view)
        }

        override fun onBindViewHolder(holder: DateViewHolder, position: Int) {
            val entry = dateEntries[position]
            val dateStr = entry.date
            holder.tvDate.text = dateStr
            holder.tvSize.text = formatSize(entry.sizeBytes)
            holder.tvFileCount.text = "${entry.fileCount} file${if (entry.fileCount != 1) "s" else ""}"
            holder.btnExport.setOnClickListener { exportDate(dateStr) }
            holder.btnDelete.setOnClickListener { confirmDelete(dateStr) }
            
            // Show upload checkmark for past dates with a marker file.
            // Never show it for today — data is still being collected.
            val today = com.pdcollect.app.util.TimeUtils.todayDateString()
            val isToday = dateStr == today
            val isUploaded = !isToday && entry.isUploaded
            val isDeleting = dateStr in deletingDates
            holder.ivUploaded.visibility = if (isUploaded) View.VISIBLE else View.GONE
            holder.btnExport.isEnabled = !isUploaded && !isDeleting
            holder.btnExport.text = if (isUploaded) "Uploaded" else "Export"
            // Today's directory is actively being written to by foreground services in
            // this process — deleting it mid-collection would unlink it out from under
            // their open file writers. See confirmDelete() for the full explanation.
            holder.btnDelete.isEnabled = !isDeleting && !isToday
            holder.btnDelete.text = if (isDeleting) "Deleting" else "Delete"
        }

        override fun getItemCount() = dateEntries.size
    }
}
