package dev.passone.passone_app

import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channel = "passone/secure_window"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSecure" -> {
                        val secure = call.argument<Boolean>("secure") ?: false
                        val flag = WindowManager.LayoutParams.FLAG_SECURE
                        val lp = window.attributes
                        if (secure) {
                            lp.flags = lp.flags or flag
                        } else {
                            lp.flags = lp.flags and flag.inv()
                        }
                        window.attributes = lp
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
