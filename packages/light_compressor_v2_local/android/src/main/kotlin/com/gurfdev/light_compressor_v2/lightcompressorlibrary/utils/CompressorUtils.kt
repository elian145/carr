package com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils

import android.media.MediaCodecInfo
import android.media.MediaCodecList
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMetadataRetriever
import android.os.Build
import android.util.Log
import com.gurfdev.light_compressor_v2.lightcompressorlibrary.VideoQuality
import kotlin.math.roundToInt

object CompressorUtils {

    private const val MIN_HEIGHT = 640.0
    private const val MIN_WIDTH = 368.0

    // 1 second between I-frames
    private const val I_FRAME_INTERVAL = 1

    fun prepareVideoWidth(
        mediaMetadataRetriever: MediaMetadataRetriever,
    ): Double {
        val widthData =
            mediaMetadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH)
        return if (widthData.isNullOrEmpty()) {
            MIN_WIDTH
        } else {
            widthData.toDouble()
        }
    }

    fun prepareVideoHeight(
        mediaMetadataRetriever: MediaMetadataRetriever,
    ): Double {
        val heightData =
            mediaMetadataRetriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT)
        return if (heightData.isNullOrEmpty()) {
            MIN_HEIGHT
        } else {
            heightData.toDouble()
        }
    }

    /**
     * Set output parameters like bitrate and frame rate.
     *
     * CARNET FORK: [effectiveFrameRate], when non-null, is used INSTEAD of
     * the source's frame rate for both the `KEY_FRAME_RATE` value actually
     * set on [outputFormat] AND this function's own diagnostic log line
     * below -- see the call site in `Compressor.start()` for why (frame-rate
     * diagnostic-order fix: the caller resolves the downsampled target rate
     * first and passes it in, so this is the single place that both sets
     * AND logs the true effective value, instead of logging the
     * pre-downsample source rate here and separately overwriting
     * `KEY_FRAME_RATE` after this function returns).
     */
    fun setOutputFileParameters(
        inputFormat: MediaFormat,
        outputFormat: MediaFormat,
        newBitrate: Int,
        effectiveFrameRate: Int? = null,
    ) {
        val newFrameRate = effectiveFrameRate ?: getFrameRate(inputFormat)
        val iFrameInterval = getIFrameIntervalRate(inputFormat)
        outputFormat.apply {

            // according to https://developer.android.com/media/optimize/sharing#b-frames_and_encoding_profiles
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val type = outputFormat.getString(MediaFormat.KEY_MIME)
                // IMPORTANT: a profile must be paired with a compatible level, otherwise
                // many hardware encoders (notably Qualcomm) reject configure() with
                // error -38 and we silently fall back to Baseline. Pick a profile+level
                // pair that the encoder actually advertises.
                val profileLevel = getSupportedProfileLevel(type)
                if (profileLevel != null) {
                    Log.i(
                        "Output file parameters",
                        "Selected profile=${profileLevel.profile} level=${profileLevel.level}"
                    )
                    setInteger(MediaFormat.KEY_PROFILE, profileLevel.profile)
                    setInteger(MediaFormat.KEY_LEVEL, profileLevel.level)
                }
                // If no supported pair is found we deliberately leave profile/level unset
                // and let the encoder choose its own defaults.
            } else if (outputFormat.getString(MediaFormat.KEY_MIME) != "video/hevc") {
                setInteger(MediaFormat.KEY_PROFILE, MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline)
            }

            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface
            )

            setInteger(MediaFormat.KEY_FRAME_RATE, newFrameRate)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, iFrameInterval)
            // expected bps
            setInteger(MediaFormat.KEY_BIT_RATE, newBitrate)
            setInteger(
                MediaFormat.KEY_BITRATE_MODE,
                MediaCodecInfo.EncoderCapabilities.BITRATE_MODE_CBR
            )



            // CARNET FORK (see ../../../../../../../../FORK_NOTES.md): HDR
            // (Dolby Vision / HDR10 / HLG) color-metadata handling.
            //
            // This pipeline's decoder always renders into a plain Surface
            // (OutputSurface/TextureRenderer do a GL blit + optional
            // brightness/contrast/saturation adjust -- no explicit HDR EOTF/
            // tone-mapping shader). The encoder's input Surface is likewise
            // never configured for any particular HDR transfer. On real
            // devices this means the GPU/hardware-composer performs an
            // IMPLICIT HDR->SDR tone-map during that blit whenever the
            // decoded source was HDR -- this is the platform-supported path
            // that actually changes the pixel values; nothing in this file
            // does it explicitly, and nothing here can reliably improve on
            // it without a real tone-mapping shader.
            //
            // The bug this fixes: the ORIGINAL code always copied the
            // SOURCE track's COLOR_TRANSFER/COLOR_STANDARD onto the OUTPUT
            // format verbatim. `SellVideoCompression` only ever requests
            // H.264 output, so an HDR source (ST2084/HLG transfer, usually
            // BT2020 standard -- exactly what a Dolby Vision base layer or
            // plain HDR10/HLG HEVC track reports) would produce an H.264
            // bitstream whose pixels were already tone-mapped down to SDR
            // by the implicit blit above, but whose container metadata
            // still claimed HDR. A spec-compliant player then applies the
            // HDR EOTF a SECOND time to already-SDR pixel data --
            // exactly the washed-out/too-dark/green/clipped symptom this
            // task asked to avoid. Retag as SDR instead of blindly copying
            // (and never simply stripping to "unspecified", which is
            // ambiguous) so the metadata matches what the pixels actually
            // are.
            val sourceTransfer = getColorTransfer(inputFormat)
            val sourceWasHdr = sourceTransfer == MediaFormat.COLOR_TRANSFER_ST2084 ||
                sourceTransfer == MediaFormat.COLOR_TRANSFER_HLG

            getColorStandard(inputFormat)?.let {
                val outStandard =
                    if (sourceWasHdr && it == MediaFormat.COLOR_STANDARD_BT2020) {
                        // BT.2020 primaries + an SDR transfer is an
                        // inconsistent combination most SDR-expecting
                        // players don't handle well; the implicit tone-map
                        // typically narrows the gamut toward BT.709 anyway.
                        MediaFormat.COLOR_STANDARD_BT709
                    } else {
                        it
                    }
                setInteger(MediaFormat.KEY_COLOR_STANDARD, outStandard)
            }

            sourceTransfer?.let {
                val outTransfer =
                    if (sourceWasHdr) MediaFormat.COLOR_TRANSFER_SDR_VIDEO else it
                setInteger(MediaFormat.KEY_COLOR_TRANSFER, outTransfer)
            }

            getColorRange(inputFormat)?.let {
                setInteger(MediaFormat.KEY_COLOR_RANGE, it)
            }


            Log.i(
                "Output file parameters",
                "videoFormat: $this"
            )
        }
    }

    private fun getFrameRate(format: MediaFormat): Int {
        return if (format.containsKey(MediaFormat.KEY_FRAME_RATE)) format.getInteger(MediaFormat.KEY_FRAME_RATE)
        else 30
    }

    private fun getIFrameIntervalRate(format: MediaFormat): Int {
        return if (format.containsKey(MediaFormat.KEY_I_FRAME_INTERVAL)) format.getInteger(
            MediaFormat.KEY_I_FRAME_INTERVAL
        )
        else I_FRAME_INTERVAL
    }

    private fun getColorStandard(format: MediaFormat): Int? {
        return if (format.containsKey(MediaFormat.KEY_COLOR_STANDARD)) format.getInteger(
            MediaFormat.KEY_COLOR_STANDARD
        )
        else null
    }

    private fun getColorTransfer(format: MediaFormat): Int? {
        return if (format.containsKey(MediaFormat.KEY_COLOR_TRANSFER)) format.getInteger(
            MediaFormat.KEY_COLOR_TRANSFER
        )
        else null
    }

    private fun getColorRange(format: MediaFormat): Int? {
        return if (format.containsKey(MediaFormat.KEY_COLOR_RANGE)) format.getInteger(
            MediaFormat.KEY_COLOR_RANGE
        )
        else null
    }

    // CARNET FORK (see ../../../../../../../../FORK_NOTES.md): base-layer
    // track preference order for [findTrack]'s video branch. A source can
    // carry more than one video/* track (e.g. a Dolby Vision file always
    // also carries a standalone-decodable base layer for backward
    // compatibility) — prefer AVC, then HEVC, over anything else (Dolby
    // Vision, AV1, etc.) before ever falling back to "first video track".
    // Literal strings (not MediaFormat.MIMETYPE_VIDEO_*) to match this file's
    // existing style and avoid any doubt about constant availability.
    private val PREFERRED_VIDEO_BASE_LAYER_MIMES = listOf(
        "video/avc",
        "video/hevc",
    )

    /**
     * Counts the number of tracks (video, audio) found in the file source provided
     * @param extractor what is used to extract the encoded data
     * @param isVideo to determine whether we are processing video or audio at time of call
     * @return index of the requested track
     */
    fun findTrack(
        extractor: MediaExtractor,
        isVideo: Boolean,
    ): Int {
        val numTracks = extractor.trackCount
        if (!isVideo) {
            for (i in 0 until numTracks) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
                if (mime?.startsWith("audio/") == true) return i
            }
            return -5
        }

        // CARNET FORK: collect every video/* track instead of stopping at the
        // first one — a source may expose several (real-device evidence: a
        // Dolby Vision .mov enumerates `video/dolby-vision` at track 0 and a
        // `video/hevc` base layer at track 1; the original upstream code
        // always picked track 0, which some devices cannot even
        // `createDecoderByType` for, throwing NAME_NOT_FOUND before any
        // decoding starts).
        val videoTracks = (0 until numTracks).mapNotNull { i ->
            val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME)
            if (mime != null && mime.startsWith("video/")) i to mime else null
        }
        return selectVideoTrackIndex(videoTracks) { index ->
            isTrackFormatDecodable(extractor.getTrackFormat(index))
        }
    }

    // CARNET FORK (real-device evidence: Samsung SM-A175F / MediaTek
    // mt6789's registered HEVC decoders -- c2.mtk.hevc.decoder,
    // OMX.MTK.VIDEO.DECODER.HEVC, c2.android.hevc.decoder,
    // OMX.google.hevc.decoder -- all advertise `VideoCapabilities` maxing
    // out at <=2560x2560 (hardware) / <=1920x1920 (software); a 3840x2160
    // Dolby-Vision-plus-HEVC-base-layer source is therefore undecodable by
    // ANY registered codec on that device, not just Dolby Vision itself):
    // exposed standalone (not just as the private lambda inside [findTrack])
    // so a caller that already has the FINAL chosen track's [MediaFormat]
    // (e.g. `Compressor.start()`, right before `prepareDecoder`) can ask
    // "is this exact format decodable here at all", to fail early with an
    // accurate message instead of letting `MediaCodec.createDecoderByType`
    // throw its low-level, mime-specific `NAME_NOT_FOUND` deep in the
    // decode pipeline when the real problem is that NOTHING on this device
    // can decode this source's video track(s), regardless of which one was
    // preferred.
    fun isTrackFormatDecodable(format: MediaFormat): Boolean {
        val codecList = runCatching { MediaCodecList(MediaCodecList.REGULAR_CODECS) }.getOrNull()
            ?: return false
        return runCatching { codecList.findDecoderForFormat(format) != null }.getOrDefault(false)
    }

    /**
     * The accurate, actionable failure message for the case above --
     * extracted as a pure function (no `MediaFormat`/Android dependency) so
     * it can be covered by a plain JVM unit test, unlike [isTrackFormatDecodable]
     * itself which genuinely needs `MediaCodecList`.
     */
    fun buildNoDecoderFailureMessage(mime: String?, width: Int, height: Int): String =
        "This device has no video decoder that supports the source video " +
            "(mime=${mime ?: "unknown"}, ${width}x$height). None of its registered " +
            "decoders can handle this resolution/codec, so it cannot be compressed " +
            "on this device."

    /**
     * The pure decision logic behind [findTrack]'s video branch, extracted
     * with no `MediaExtractor`/`MediaCodecList` dependency so it can run in
     * a plain JVM unit test (see `android/src/test/kotlin/.../
     * CompressorUtilsTrackSelectionTest.kt`) -- those Android framework
     * classes cannot be constructed or meaningfully mocked outside
     * Robolectric/instrumentation, and a real Dolby Vision binary fixture
     * is impractical to ship in this repository.
     *
     * @param tracks (index, mime) for every video track (mime prefix
     *   `video/`), in the source's original enumeration order.
     * @param isDecodable reports whether this device can actually decode
     *   the track at a given index (backed in production by
     *   `MediaCodecList.findDecoderForFormat`).
     * @return the chosen track index, or `-5` when [tracks] is empty
     *   (matches [findTrack]'s existing "not found" sentinel).
     *
     * Selection order (fixed from an earlier draft that checked mime only,
     * not decodability, for the two preferred codecs -- which defeated the
     * point of decoder-aware selection: a preferred-mime track this device
     * cannot actually decode must never be chosen over a codec further down
     * the list, or any other track, that CAN be decoded):
     *   1. the first DECODABLE `video/avc` track
     *   2. otherwise the first DECODABLE `video/hevc` track
     *   3. otherwise the first OTHER video track (any mime, including
     *      Dolby Vision or AV1) for which [isDecodable] is true
     *   4. otherwise the first video track at all, as an explicit-failure
     *      fallback (see below)
     *   5. no video tracks at all -> `-5` (`TRACK_NOT_FOUND`)
     */
    fun selectVideoTrackIndex(
        tracks: List<Pair<Int, String>>,
        isDecodable: (Int) -> Boolean,
    ): Int {
        if (tracks.isEmpty()) return -5

        // 1 + 2) Prefer a known-good base-layer codec (AVC, then HEVC) over
        // anything else (Dolby Vision, AV1, ...), regardless of enumeration
        // order -- but ONLY when this device can actually decode that exact
        // track. Dolby Vision must never be selected over a decodable HEVC
        // base layer, and AVC/HEVC must never be selected merely by mime if
        // this device cannot decode that exact MediaFormat.
        for (preferredMime in PREFERRED_VIDEO_BASE_LAYER_MIMES) {
            tracks.firstOrNull { it.second == preferredMime && isDecodable(it.first) }
                ?.let { return it.first }
        }

        // 3) Neither preferred codec is decodable (or present): fall back to
        // the first track of ANY mime this device actually has a registered
        // decoder for (e.g. a Dolby-Vision-only source with no base layer,
        // but the device happens to support DV decode; or a plain AV1
        // source with no AVC/HEVC track at all).
        for ((index, _) in tracks) {
            if (isDecodable(index)) return index
        }

        // 4) Nothing reported decodable on this device: return the first
        // video track anyway, as an explicit failure fallback. This
        // preserves the original (pre-fork) behavior for any format
        // `findDecoderForFormat` cannot evaluate (e.g. missing required
        // keys) and keeps the existing "Failed to initialize <mime>" error
        // path accurate rather than silently skipping the whole video.
        return tracks.first().first
    }

    fun printException(exception: Exception) {
        var message = "An error has occurred!"
        exception.localizedMessage?.let {
            message = it
        }
        Log.e("Compressor", message, exception)
    }

    /**
     * Get fixed bitrate value based on the file's current bitrate
     * @param bitrate file's current bitrate
     * @return new smaller bitrate value
     */
    fun getBitrate(
        bitrate: Int,
        quality: VideoQuality,
    ): Int {
        return when (quality) {
            VideoQuality.VERY_LOW -> (bitrate * 0.1).roundToInt()
            VideoQuality.LOW -> (bitrate * 0.2).roundToInt()
            VideoQuality.MEDIUM -> (bitrate * 0.3).roundToInt()
            VideoQuality.HIGH -> (bitrate * 0.4).roundToInt()
            VideoQuality.VERY_HIGH -> (bitrate * 0.6).roundToInt()
        }
    }

    /**
     * Generate new width and height for source file
     * @param width file's original width
     * @param height file's original height
     * @return the scale factor to apply to the video's resolution
     */
    fun autoResizePercentage(width: Double, height: Double): Double {
        return when {
            width >= 1920 || height >= 1920 -> 0.5
            width >= 1280 || height >= 1280 -> 0.75
            width >= 960 || height >= 960 -> 0.95
            else -> 0.9
        }
    }

    /**
     * True when the device advertises a **hardware** HEVC (H.265) encoder.
     *
     * AOSP software HEVC encoders (`c2.android.*` / `OMX.google.*`) are excluded
     * because they are far too slow to be practical for video compression; when
     * only those are present the caller falls back to H.264. Vendor Codec2
     * encoders (e.g. `c2.qti.*`, `c2.exynos.*`, `c2.mtk.*`) are hardware and pass
     * this check.
     */
    fun isHevcHardwareEncoderAvailable(): Boolean =
        runCatching {
            MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { codec ->
                codec.isEncoder &&
                    "video/hevc" in codec.supportedTypes &&
                    !codec.name.contains("google", ignoreCase = true) &&
                    !codec.name.contains("c2.android", ignoreCase = true)
            }
        }.getOrDefault(false)

    /**
     * Finds a profile+level pair that an available encoder for [type] actually
     * supports. Preference order is High > Main > Baseline, and within a profile
     * the highest advertised level is chosen.
     *
     * Returns `null` when no encoder/capabilities are found, in which case the
     * caller should leave the profile/level unset (the encoder picks defaults).
     *
     * Pairing a profile with a compatible level is required: setting
     * [MediaFormat.KEY_PROFILE] without [MediaFormat.KEY_LEVEL] makes many
     * hardware encoders fail `configure()` with error -38.
     */
    private fun getSupportedProfileLevel(type: String?): MediaCodecInfo.CodecProfileLevel? {
        if (type == null) return null

        val capabilities = MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos
            .filter { codec -> codec.isEncoder && type in codec.supportedTypes }
            .mapNotNull { codec -> runCatching { codec.getCapabilitiesForType(type) }.getOrNull() }

        val preferenceOrder = if (type == "video/hevc") {
            // HEVC Main covers 8-bit 4:2:0 video, which is what this surface
            // pipeline produces.
            listOf(MediaCodecInfo.CodecProfileLevel.HEVCProfileMain)
        } else {
            listOf(
                MediaCodecInfo.CodecProfileLevel.AVCProfileHigh,
                MediaCodecInfo.CodecProfileLevel.AVCProfileMain,
                MediaCodecInfo.CodecProfileLevel.AVCProfileBaseline,
            )
        }

        for (profile in preferenceOrder) {
            var best: MediaCodecInfo.CodecProfileLevel? = null
            capabilities.forEach { capabilitiesForType ->
                capabilitiesForType.profileLevels.forEach { profileLevel ->
                    if (profileLevel.profile == profile &&
                        (best == null || profileLevel.level > best!!.level)
                    ) {
                        best = profileLevel
                    }
                }
            }
            if (best != null) return best
        }

        return null
    }
}
