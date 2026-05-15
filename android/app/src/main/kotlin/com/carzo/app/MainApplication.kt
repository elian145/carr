package com.carzo.app

import android.app.Application
import co.ab180.airbridge.flutter.AirbridgeFlutter

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        val name = BuildConfig.AIRBRIDGE_APP_NAME.trim()
        val token = BuildConfig.AIRBRIDGE_APP_TOKEN.trim()
        if (name.isNotEmpty() && token.isNotEmpty()) {
            AirbridgeFlutter.initializeSDK(this, name, token)
        }
    }
}
