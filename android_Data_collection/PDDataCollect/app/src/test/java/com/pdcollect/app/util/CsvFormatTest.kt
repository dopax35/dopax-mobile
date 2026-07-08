package com.pdcollect.app.util

import org.junit.Assert.*
import org.junit.Test

/**
 * Validates that CSV headers and data row formats are consistent across all data types.
 * Catches column count mismatches that could silently corrupt research data.
 */
class CsvFormatTest {

    @Test
    fun sensorsHeader_has10Columns() {
        val cols = Constants.SENSORS_HEADER.split(",")
        assertEquals(10, cols.size)
        assertEquals("timestamp_ns", cols[0])
    }

    @Test
    fun touchHeader_has5Columns() {
        val cols = Constants.TOUCH_HEADER.split(",")
        assertEquals(5, cols.size)
        assertEquals("timestamp_ms", cols[0])
    }

    @Test
    fun keysHeader_has4Columns() {
        val cols = Constants.KEYS_HEADER.split(",")
        assertEquals(4, cols.size)
        assertEquals("timestamp_ms", cols[0])
    }

    @Test
    fun appsHeader_has4Columns() {
        val cols = Constants.APPS_HEADER.split(",")
        assertEquals(4, cols.size)
        assertEquals("timestamp_ms", cols[0])
    }

    @Test
    fun tmtHeader_has9Columns() {
        val cols = Constants.TMT_HEADER.split(",")
        assertEquals(9, cols.size)
        assertEquals("start_time_ms", cols[0])
        assertEquals("wrong_target_errors", cols[4])
        assertEquals("lift_off_errors", cols[5])
    }

    @Test
    fun faceDistanceHeader_has11Columns() {
        val cols = Constants.FACE_DISTANCE_HEADER.split(",")
        assertEquals(11, cols.size)
        assertEquals("timestamp_ms", cols[0])
        assertEquals("context", cols[1])
        assertEquals("face_detected", cols[2])
        assertEquals("landmarks_detected", cols[3])
        assertEquals("eye_distance_px", cols[4])
        assertEquals("focal_length_px", cols[5])
        assertEquals("estimated_cm", cols[6])
        assertEquals("confidence", cols[7])
        assertEquals("head_euler_y", cols[8])
        assertEquals("head_euler_z", cols[9])
        assertEquals("method", cols[10])
    }

    @Test
    fun allHeaders_haveNoDuplicateColumns() {
        val headers = listOf(
            Constants.SENSORS_HEADER,
            Constants.TOUCH_HEADER,
            Constants.KEYS_HEADER,
            Constants.APPS_HEADER,
            Constants.TMT_HEADER,
            Constants.FACE_DISTANCE_HEADER
        )
        for (header in headers) {
            val cols = header.split(",")
            assertEquals(
                "Duplicate columns in header: $header",
                cols.size, cols.toSet().size
            )
        }
    }

    @Test
    fun allHeaders_haveNoEmptyColumnNames() {
        val headers = listOf(
            Constants.SENSORS_HEADER,
            Constants.TOUCH_HEADER,
            Constants.KEYS_HEADER,
            Constants.APPS_HEADER,
            Constants.TMT_HEADER,
            Constants.FACE_DISTANCE_HEADER
        )
        for (header in headers) {
            val cols = header.split(",")
            for (col in cols) {
                assertTrue("Empty column name in header: $header", col.isNotBlank())
            }
        }
    }

    @Test
    fun faceDistanceRow_faceDetected_matchesHeaderColumnCount() {
        val headerCols = Constants.FACE_DISTANCE_HEADER.split(",").size
        val row = "1234567890,tmt,true,true,61.5000,812.4000,45.3000,0.9100,5.5000,-2.3000,ipd_intrinsics"
        assertEquals(headerCols, row.split(",").size)
    }

    @Test
    fun faceDistanceRow_noFaceDetected_matchesHeaderColumnCount() {
        val headerCols = Constants.FACE_DISTANCE_HEADER.split(",").size
        val row = "1234567890,always_on,false,false,-1.0000,-1.0000,-1.0000,0.0000,0.0000,0.0000,no_face"
        assertEquals(headerCols, row.split(",").size)
    }

    @Test
    fun sensorRow_matchesHeaderColumnCount() {
        val headerCols = Constants.SENSORS_HEADER.split(",").size
        val row = "1000000000000,1.0,2.0,3.0,0.1,0.2,0.3,10.0,20.0,30.0"
        assertEquals(headerCols, row.split(",").size)
    }

    @Test
    fun touchRow_matchesHeaderColumnCount() {
        val headerCols = Constants.TOUCH_HEADER.split(",").size
        val row = "1234567890,TAP,500,800,com.example.app"
        assertEquals(headerCols, row.split(",").size)
    }

    @Test
    fun keysRow_matchesHeaderColumnCount() {
        val headerCols = Constants.KEYS_HEADER.split(",").size
        val row = "1234567890,a,false,com.example.app"
        assertEquals(headerCols, row.split(",").size)
    }

    @Test
    fun appsRow_matchesHeaderColumnCount() {
        val headerCols = Constants.APPS_HEADER.split(",").size
        val row = "1234567890,OPEN,com.example.app,com.example.app.MainActivity"
        assertEquals(headerCols, row.split(",").size)
    }
}
