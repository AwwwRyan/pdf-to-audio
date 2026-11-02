package com.awwwryan.pdf_listener

import android.Manifest
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity shares its FlutterEngine with the background audio service.
class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pdf_listener/system")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openTtsSettings" -> {
                        try {
                            startActivity(Intent("com.android.settings.TTS_SETTINGS")
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        } catch (e: ActivityNotFoundException) {
                            // Some OEMs don't export the TTS screen; fall back to Settings.
                            startActivity(Intent(Settings.ACTION_SETTINGS)
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                        result.success(null)
                    }
                    "requestNotificationPermission" -> {
                        // Android remembers a "don't ask again" answer, so repeat calls are quiet.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                                PackageManager.PERMISSION_GRANTED
                        ) {
                            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
                        }
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
