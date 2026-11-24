package com.ybsolutions.suturavault

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // SEC-08 : Anti-capture, anti-enregistrement vidéo & masquage dans les apps récentes
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}