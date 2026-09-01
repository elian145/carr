package com.carzo.app

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.util.DisplayMetrics

/** Ignore the user Font size and Display size settings so layouts stay designed. */
internal fun Context.withLockedSystemDisplay(): Context {
    val config = Configuration(resources.configuration)
    lockSystemDisplay(config, resources.displayMetrics)
    return createConfigurationContext(config)
}

internal fun lockSystemDisplay(
    config: Configuration,
    metrics: DisplayMetrics? = null,
) {
    config.fontScale = 1.0f
    val stableDpi = stableDensityDpi(metrics)
    if (stableDpi > 0) {
        config.densityDpi = stableDpi
    }
}

internal fun stableDensityDpi(metrics: DisplayMetrics? = null): Int {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
        DisplayMetrics.DENSITY_DEVICE_STABLE
    } else {
        metrics?.densityDpi ?: 0
    }
}

/**
 * FlutterView reads [DisplayMetrics.density] and [Configuration.fontScale]
 * from [Activity.getResources], not from a wrapped attachBaseContext. Patch
 * both on every read so emulator Display size / Font size cannot leak in.
 */
internal fun Resources.lockToDesignedDisplay() {
    val stableDpi = stableDensityDpi(displayMetrics)
    if (stableDpi <= 0) return
    val density = stableDpi / 160f
    val metrics = displayMetrics
    metrics.densityDpi = stableDpi
    metrics.density = density
    metrics.scaledDensity = density
    val config = configuration
    if (config.fontScale != 1.0f || config.densityDpi != stableDpi) {
        val locked = Configuration(config)
        lockSystemDisplay(locked, metrics)
        @Suppress("DEPRECATION")
        updateConfiguration(locked, metrics)
        metrics.densityDpi = stableDpi
        metrics.density = density
        metrics.scaledDensity = density
    }
}
