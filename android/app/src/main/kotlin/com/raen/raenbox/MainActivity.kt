package com.raen.raenbox

import android.app.PictureInPictureParams
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.raen.raenbox/pip"
    private var methodChannel: MethodChannel? = null
    private var isAutoPiPEnabled = false
    private var pipAspectRatio = Rational(16, 9)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "enterPiP" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val num = call.argument<Int>("numerator") ?: 16
                            val den = call.argument<Int>("denominator") ?: 9
                            val clampedNum = num.coerceIn(1, 1000)
                            val clampedDen = den.coerceIn(1, 1000)
                            val ratio = clampedNum.toFloat() / clampedDen.toFloat()
                            pipAspectRatio = if (ratio in 0.42f..2.38f) {
                                Rational(clampedNum, clampedDen)
                            } else {
                                Rational(16, 9)
                            }
                            val builder = PictureInPictureParams.Builder()
                                .setAspectRatio(pipAspectRatio)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                builder.setAutoEnterEnabled(isAutoPiPEnabled)
                            }
                            val params = builder.build()
                            val entered = enterPictureInPictureMode(params)
                            result.success(entered)
                        } catch (e: Exception) {
                            result.error("PIP_ERROR", e.message, null)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "setAutoPiPEnabled" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: false
                    isAutoPiPEnabled = enabled
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            val builder = PictureInPictureParams.Builder()
                                .setAspectRatio(pipAspectRatio)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                builder.setAutoEnterEnabled(enabled)
                            }
                            setPictureInPictureParams(builder.build())
                        } catch (_: Exception) {}
                    }
                    result.success(true)
                }
                "isPiPSupported" -> {
                    val supported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        packageManager.hasSystemFeature(android.content.pm.PackageManager.FEATURE_PICTURE_IN_PICTURE)
                    result.success(supported)
                }
                "isInPiP" -> {
                    val inPip = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        isInPictureInPictureMode
                    } else {
                        false
                    }
                    result.success(inPip)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && isAutoPiPEnabled) {
            try {
                val builder = PictureInPictureParams.Builder()
                    .setAspectRatio(pipAspectRatio)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    builder.setAutoEnterEnabled(true)
                }
                enterPictureInPictureMode(builder.build())
            } catch (_: Exception) {}
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        methodChannel?.invokeMethod("onPiPChanged", isInPictureInPictureMode)
    }
}

