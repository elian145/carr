package com.carzo.app

import android.content.Context
import android.content.res.Configuration
import android.content.res.Resources
import android.os.Build
import android.util.DisplayMetrics

/**
 * Ignore the user Display size (density) setting so layouts stay designed.
 *
 * The user Font size ([Configuration.fontScale]) is deliberately NOT touched
 * (F-10): accessibility font scaling must reach Flutter. Dart bounds it to
 * 1.0..2.0 in SystemDisplayLock.
 */
internal fun Context.withLockedSystemDisplay(): Context {
    val config = Configuration(resources.configuration)
    lockSystemDisplay(config, resources.displayMetrics)
    return createConfigurationContext(config)
}

internal fun lockSystemDisplay(
    config: Configuration,
    metrics: DisplayMetrics? = null,
) {
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
 * FlutterView reads [DisplayMetrics.density] from [Activity.getResources],
 * not from a wrapped attachBaseContext. Patch it on every read so emulator
 * Display size cannot leak in. The font scale is preserved as the user set it.
 */
internal fun Resources.lockToDesignedDisplay() {
    val stableDpi = stableDensityDpi(displayMetrics)
    if (stableDpi <= 0) return
    val density = stableDpi / 160f
    val metrics = displayMetrics
    metrics.densityDpi = stableDpi
    metrics.density = density
    val fontScale = configuration.fontScale
    metrics.scaledDensity = density * fontScale
    val config = configuration
    if (config.densityDpi != stableDpi) {
        val locked = Configuration(config)
        lockSystemDisplay(locked, metrics)
        @Suppress("DEPRECATION")
        updateConfiguration(locked, metrics)
        metrics.densityDpi = stableDpi
        metrics.density = density
        metrics.scaledDensity = density * fontScale
    }
}
