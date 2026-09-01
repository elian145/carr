package com.carzo.app

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.util.DisplayMetrics
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var lockingResources = false

    override fun attachBaseContext(newBase: Context) {
        super.attachBaseContext(newBase.withLockedSystemDisplay())
    }

    override fun applyOverrideConfiguration(overrideConfiguration: Configuration?) {
        if (overrideConfiguration != null) {
            lockSystemDisplay(overrideConfiguration)
        }
        super.applyOverrideConfiguration(overrideConfiguration)
    }

    override fun getResources(): Resources {
        val res = super.getResources()
        if (!lockingResources) {
            lockingResources = true
            try {
                res.lockToDesignedDisplay()
            } finally {
                lockingResources = false
            }
        }
        return res
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        lockSystemDisplay(newConfig, resources.displayMetrics)
        super.onConfigurationChanged(newConfig)
        resources.lockToDesignedDisplay()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "carzo/display_lock",
        ).setMethodCallHandler { call, result ->
            if (call.method == "getStableDensityDpi") {
                val dpi =
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                        DisplayMetrics.DENSITY_DEVICE_STABLE
                    } else {
                        resources.displayMetrics.densityDpi
                    }
                result.success(dpi)
            } else {
                result.notImplemented()
            }
        }
    }
}
