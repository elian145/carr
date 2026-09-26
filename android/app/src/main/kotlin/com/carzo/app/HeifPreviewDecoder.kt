package com.carzo.app

/*
 * HEIC/HEIF Sell-photo preview fix.
 *
 * Real-device evidence proved that BOTH Flutter's own Skia decoders
 * (`Image.file`/`Image.memory`) AND `flutter_image_compress` (which on
 * Android decodes via `android.graphics.BitmapFactory`, the OS's own
 * decoder) fail to decode a specific Samsung HEIF file:
 *
 *   [HEIC PREVIEW] conversion failed error=CompressError:
 *   Attempt to invoke virtual method
 *   'void android.graphics.Bitmap.recycle()' on a null object reference
 *
 * (BitmapFactory returned null; the plugin then tried to recycle that
 * null Bitmap.) A package audit found no maintained Flutter plugin that
 * decodes HEIC/HEIF on Android without ultimately delegating to
 * BitmapFactory/`android.graphics.ImageDecoder`.
 *
 * This file decodes HEIC/HEIF via `io.github.awxkee:avif-coder:2.2.1`
 * instead, which bundles its OWN native `libheif` + `libde265` and never
 * touches BitmapFactory/ImageDecoder for the decode step -- see
 * `HeifCoder.decodeSampled` below.
 *
 * License note (preserved as-is; NOT a legal conclusion -- just recording
 * both so a future reader/auditor has them):
 *   - The avif-coder GitHub repository's own LICENSE file, and the header
 *     comment in every one of its Kotlin source files (including
 *     HeifCoder.kt), declare: MIT License, Copyright (c) 2023 Radzivon
 *     Bartoshyk.
 *   - The Maven Central POM metadata published for
 *     io.github.awxkee:avif-coder:2.2.1 instead declares dual licensing:
 *     "The Apache License, Version 2.0" AND "The 3-Clause BSD License".
 *   These two sources disagree; this comment exists so both notices are
 *   retained rather than only one being silently kept.
 */

import android.graphics.Bitmap
import android.util.Log
import com.radzivon.bartoshyk.avif.coder.HeifCoder
import com.radzivon.bartoshyk.avif.coder.PreferredColorConfig
import com.radzivon.bartoshyk.avif.coder.ScaleMode
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

private const val HEIF_PREVIEW_TAG = "HeifPreviewDecoder"

/**
 * Decodes HEIC/HEIF [bytes] via [HeifCoder] (avif-coder's bundled
 * libheif/libde265) and re-encodes the result as JPEG, replying to
 * [result] with the JPEG bytes on success or a `FlutterError` on failure.
 *
 * [maxDimension] bounds the decoded bitmap's longer side (aspect ratio
 * preserved via [ScaleMode.FIT]) so a large original can't spike memory --
 * this is a PREVIEW only, never the upload source; the original HEIC/HEIF
 * file on the Dart side is never touched by this function.
 *
 * Orientation: HEIF stores rotation/mirroring via its own `irot`/`imir`
 * container properties, not EXIF (per the MIAF spec, renderers should
 * ignore EXIF Orientation for HEIF-family files). avif-coder decodes via
 * real libheif, which is MIAF-compliant and applies `irot`/`imir` during
 * decode, so the returned [Bitmap] is already upright -- no separate
 * rotation pass is added here. (Verified from the library's own
 * documentation/spec compliance claims, not from a device test of every
 * possible orientation; if a real rotated photo is ever seen upside-down
 * or sideways in the preview, that assumption needs re-checking.)
 */
internal fun decodeHeifToJpeg(
    bytes: ByteArray,
    maxDimension: Int,
    quality: Int,
    result: MethodChannel.Result,
) {
    if (BuildConfig.DEBUG) {
        Log.d(HEIF_PREVIEW_TAG, "[HEIF NATIVE] inputBytes=${bytes.size}")
    }
    var bitmap: Bitmap? = null
    try {
        // Deliberately NOT BitmapFactory.decodeByteArray / ImageDecoder --
        // those are exactly what already fails on-device for this format.
        bitmap = HeifCoder().decodeSampled(
            bytes,
            maxDimension,
            maxDimension,
            preferredColorConfig = PreferredColorConfig.RGBA_8888,
            scaleMode = ScaleMode.FIT,
        )
        val decoded = bitmap
        if (BuildConfig.DEBUG) {
            Log.d(
                HEIF_PREVIEW_TAG,
                "[HEIF NATIVE] decode success width=${decoded.width} height=${decoded.height}",
            )
        }
        val out = ByteArrayOutputStream()
        val compressed = decoded.compress(Bitmap.CompressFormat.JPEG, quality, out)
        if (!compressed) {
            result.error("heif_preview_compress_failed", "Bitmap.compress returned false", null)
            return
        }
        val jpegBytes = out.toByteArray()
        if (BuildConfig.DEBUG) {
            Log.d(HEIF_PREVIEW_TAG, "[HEIF NATIVE] jpegBytes=${jpegBytes.size}")
        }
        result.success(jpegBytes)
    } catch (e: Throwable) {
        if (BuildConfig.DEBUG) {
            Log.w(HEIF_PREVIEW_TAG, "[HEIF NATIVE] failed ${e.javaClass.simpleName}: ${e.message}")
        }
        result.error("heif_preview_decode_failed", e.message, e.javaClass.simpleName)
    } finally {
        // Recycle ONLY a successfully-decoded, still-valid bitmap -- never
        // a null reference. That exact "recycle() on a null object" crash
        // is the bug this native decoder replaces (see file header).
        val toRecycle = bitmap
        if (toRecycle != null && !toRecycle.isRecycled) {
            toRecycle.recycle()
        }
    }
}
