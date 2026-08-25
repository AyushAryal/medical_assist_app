package com.medapp.medical_app

import android.content.pm.ApplicationInfo
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    /**
     * Blocks screenshots, screen recording and thumbnail capture — in release
     * builds only.
     *
     * FLAG_SECURE also blanks the window in the recent-apps switcher, which is
     * the part that matters day to day: without it, the last patient chart
     * viewed stays visible to anyone who picks up the device and taps the
     * overview button.
     *
     * It is skipped when the package is debuggable, because it also blocks
     * `adb screencap`, which makes UI work effectively blind. The exemption is
     * keyed off FLAG_DEBUGGABLE rather than a constant of our own, so a release
     * build physically cannot take this branch: that flag is set by the
     * manifest merger from the build type, not by app code.
     */
    override fun onCreate(savedInstanceState: Bundle?) {
        val isDebuggable =
            (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0

        if (!isDebuggable) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        }

        super.onCreate(savedInstanceState)
    }
}
