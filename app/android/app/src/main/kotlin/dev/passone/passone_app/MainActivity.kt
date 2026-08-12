package dev.passone.passone_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Block screenshots, screen recordings and the app-switcher preview
        // for the whole app (same behaviour as Bitwarden and other password
        // managers).
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
}
