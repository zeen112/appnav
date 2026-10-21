package com.mototouring.nav

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.annotation.NonNull
import com.mototouring.nav.media.GlobalMediaManager
import com.mototouring.nav.service.MotoTouringForegroundService
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val MEDIA_METHOD_CHANNEL = "com.mototouring.nav/media_controller"
    private val MEDIA_EVENT_CHANNEL = "com.mototouring.nav/media_events"
    private val SERVICE_METHOD_CHANNEL = "com.mototouring.nav/foreground_service"
    private val SPATIALFLOW_CHANNEL = "com.mototouring.nav/spatialflow"

    private lateinit var mediaManager: GlobalMediaManager

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        mediaManager = GlobalMediaManager(this)

        // 1. Universal Media Controller Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_METHOD_CHANNEL)
            .setMethodCallHandler(mediaManager)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, MEDIA_EVENT_CHANNEL)
            .setStreamHandler(mediaManager)

        // 2. Foreground Service & Battery Optimization Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SERVICE_METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startTouringService" -> {
                        val intent = Intent(this, MotoTouringForegroundService::class.java).apply {
                            action = MotoTouringForegroundService.ACTION_START_RIDE
                        }
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success(true)
                    }
                    "stopTouringService" -> {
                        val intent = Intent(this, MotoTouringForegroundService::class.java).apply {
                            action = MotoTouringForegroundService.ACTION_STOP_RIDE
                        }
                        startService(intent)
                        result.success(true)
                    }
                    "isBatteryOptimizationIgnored" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimization" -> {
                        val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                            data = Uri.parse("package:$packageName")
                        }
                        startActivity(intent)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        // 3. Spatialflow Deep-Linking & Intent Channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SPATIALFLOW_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openSpatialflow" -> {
                        val customData = call.argument<String>("data") ?: ""
                        val pm = packageManager
                        
                        // First attempt: Launch via custom URI scheme
                        val deepLinkIntent = Intent(Intent.ACTION_VIEW, Uri.parse("spatialflow://touring?payload=$customData"))
                        if (deepLinkIntent.resolveActivity(pm) != null) {
                            startActivity(deepLinkIntent)
                            result.success("LAUNCHED_DEEPLINK")
                        } else {
                            // Second attempt: Launch via package name if installed
                            val launchIntent = pm.getLaunchIntentForPackage("com.spatialflow.app")
                            if (launchIntent != null) {
                                startActivity(launchIntent)
                                result.success("LAUNCHED_PACKAGE")
                            } else {
                                // Fallback: Open GitHub repo / releases page in browser
                                val browserIntent = Intent(
                                    Intent.ACTION_VIEW,
                                    Uri.parse("https://github.com/spatialflow")
                                )
                                startActivity(browserIntent)
                                result.success("OPENED_FALLBACK_URL")
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
