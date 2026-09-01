package com.carzo.app

import android.app.Application
import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import co.ab180.airbridge.flutter.AirbridgeFlutter

class MainApplication : Application() {
    private var lockingResources = false

    override fun attachBaseContext(base: Context) {
        super.attachBaseContext(base.withLockedSystemDisplay())
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

    override fun onCreate() {
        super.onCreate()
        val name = BuildConfig.AIRBRIDGE_APP_NAME.trim()
        val token = BuildConfig.AIRBRIDGE_APP_TOKEN.trim()
        if (name.isNotEmpty() && token.isNotEmpty()) {
            AirbridgeFlutter.initializeSDK(this, name, token)
        }
    }
}
