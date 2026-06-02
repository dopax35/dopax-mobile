package com.pdcollect.app.ui

import android.widget.TextView

internal fun TextView.setTestButtonState(enabled: Boolean, label: CharSequence? = null) {
    isEnabled = enabled
    isClickable = enabled
    alpha = if (enabled) 1f else 0.45f
    if (label != null) {
        text = label
    }
}
