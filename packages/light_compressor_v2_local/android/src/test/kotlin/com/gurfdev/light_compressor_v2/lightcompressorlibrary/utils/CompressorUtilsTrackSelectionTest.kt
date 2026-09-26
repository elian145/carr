package com.gurfdev.light_compressor_v2.lightcompressorlibrary.utils

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Plain-JVM unit tests for [CompressorUtils.selectVideoTrackIndex] -- the
 * pure decision logic behind the real-device fix documented in
 * `packages/light_compressor_v2_local/FORK_NOTES.md`.
 *
 * Real-device evidence (Samsung SM-A175F, Android 16): a 6.995s `.mov`
 * (112,329,351 bytes, 2160x3840 portrait) whose `MediaExtractor` enumerated
 * `video/dolby-vision` at track 0 and `video/hevc` at track 1 failed with
 * `Failed to initialize video/dolby-vision error 0xfffffffe
 * (NAME_NOT_FOUND)` because upstream `light_compressor_v2` 1.9.1 always
 * picked track 0.
 *
 * `MediaExtractor`/`MediaCodecList` cannot be constructed or meaningfully
 * mocked in a plain JVM test (no Robolectric/instrumentation runner is
 * wired up for this vendored plugin), and a real Dolby Vision binary
 * fixture is impractical to ship in this repository -- so, per the task's
 * own fallback ("isolate and test track-selection/probe logic
 * separately"), these tests exercise [CompressorUtils.selectVideoTrackIndex]
 * directly: plain (index, mime) pairs in, an `isDecodable` lambda standing
 * in for `MediaCodecList.findDecoderForFormat`.
 */
class CompressorUtilsTrackSelectionTest {

    @Test
    fun `dual-track Dolby Vision plus HEVC base layer -- HEVC is preferred, exactly the real-device fixture`() {
        // track[0] = video/dolby-vision, track[1] = video/hevc -- the EXACT
        // enumeration order from the real-device NuMediaExtractor log.
        val tracks = listOf(0 to "video/dolby-vision", 1 to "video/hevc")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(
            "must prefer the HEVC base layer (track 1) over Dolby Vision " +
                "(track 0), regardless of enumeration order",
            1,
            chosen,
        )
    }

    @Test
    fun `dual-track Dolby Vision plus HEVC -- HEVC NOT decodable, Dolby Vision decodable -- chooses Dolby Vision`() {
        val tracks = listOf(0 to "video/dolby-vision", 1 to "video/hevc")

        // Only track 0 (Dolby Vision) is decodable on this device; the
        // preferred-mime HEVC track exists but is NOT decodable, so it must
        // be skipped in favor of the track that actually works -- proves
        // decodability, not mere mime membership, gates the preferred-codec
        // branch.
        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { index -> index == 0 }

        assertEquals(
            "HEVC is present but undecodable on this device, so the " +
                "(decodable) Dolby Vision track must be used instead",
            0,
            chosen,
        )
    }

    @Test
    fun `AVC present but NOT decodable, HEVC decodable -- chooses HEVC, not the merely-preferred-by-mime AVC track`() {
        val tracks = listOf(0 to "video/avc", 1 to "video/hevc")

        // This is the exact bug being fixed: an earlier draft picked a
        // preferred-mime track (AVC) without ever checking isDecodable,
        // which defeats the point of decoder-aware selection.
        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { index -> index == 1 }

        assertEquals(
            "AVC is present but this device cannot decode that exact " +
                "MediaFormat, so the decodable HEVC track must be chosen " +
                "instead -- mime preference must never override decodability",
            1,
            chosen,
        )
    }

    @Test
    fun `all tracks reported undecodable -- falls back to the first video track as an explicit failure fallback`() {
        val tracks = listOf(0 to "video/dolby-vision", 1 to "video/hevc")

        // Nothing is decodable on this device at all -- proves the
        // preference list alone doesn't bypass the decodability check when
        // a HEVC track exists but isn't usable, and that the function still
        // returns a definite index (not -5) so the existing "Failed to
        // initialize <mime>" error path stays accurate.
        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { false }

        assertEquals(
            "with nothing decodable, must fall back to the FIRST video " +
                "track (preserves the original error-reporting behavior) " +
                "rather than silently returning -5/skipping the video",
            0,
            chosen,
        )
    }

    @Test
    fun `ordinary single-track HEVC source is selected normally`() {
        val tracks = listOf(0 to "video/hevc")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(0, chosen)
    }

    @Test
    fun `ordinary single-track H264 source is selected normally`() {
        val tracks = listOf(0 to "video/avc")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(0, chosen)
    }

    @Test
    fun `AVC is preferred over HEVC when a source somehow carries both`() {
        val tracks = listOf(0 to "video/hevc", 1 to "video/avc")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(1, chosen)
    }

    @Test
    fun `Dolby Vision only, no base layer at all, but this device CAN decode dolby-vision directly -- uses it rather than failing`() {
        val tracks = listOf(0 to "video/dolby-vision")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(
            "no AVC/HEVC track exists, so the (decodable-on-this-device) " +
                "Dolby Vision track itself must still be used",
            0,
            chosen,
        )
    }

    @Test
    fun `AV1 track alongside an HEVC base layer -- HEVC is still preferred`() {
        val tracks = listOf(0 to "video/av01", 1 to "video/hevc")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(1, chosen)
    }

    @Test
    fun `AV1 decodable, AVC-HEVC absent -- chooses AV1 via the non-preferred-but-decodable fallback`() {
        val tracks = listOf(0 to "video/av01")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { true }

        assertEquals(
            "no AVC/HEVC track exists at all, so the first (and only, " +
                "decodable) track of any other mime must be chosen",
            0,
            chosen,
        )
    }

    @Test
    fun `no video tracks at all returns the not-found sentinel`() {
        val chosen = CompressorUtils.selectVideoTrackIndex(emptyList()) { true }

        assertEquals(-5, chosen)
    }

    @Test
    fun `real-device regression -- Samsung SM-A175F mt6789, 3840x2160 DV+HEVC where NEITHER decoder supports 4K -- falls back to track 0, not a crash`() {
        // Real-device evidence (Samsung SM-A175F / MediaTek mt6789):
        // c2.mtk.hevc.decoder, OMX.MTK.VIDEO.DECODER.HEVC,
        // c2.android.hevc.decoder, and OMX.google.hevc.decoder all
        // advertise VideoCapabilities maxing out at <=2560x2560 (hardware)
        // / <=1920x1920 (software) -- none support this source's actual
        // 3840x2160 frame size, and there is no Dolby Vision decoder at
        // all. This is a genuine device decoder-capability ceiling, not a
        // track-selection bug: selectVideoTrackIndex must still return a
        // definite index (its step-4 explicit-failure fallback), so
        // `Compressor.start()` can detect "the chosen track isn't
        // decodable either" and fail with an accurate message instead of
        // selectVideoTrackIndex itself throwing or returning -5.
        val tracks = listOf(0 to "video/dolby-vision", 1 to "video/hevc")

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { false }

        assertEquals(
            "neither track is decodable at its native 3840x2160 resolution " +
                "on this device -- must still return a definite fallback " +
                "index (not -5) so the caller can build an accurate failure",
            0,
            chosen,
        )
    }

    @Test
    fun `buildNoDecoderFailureMessage reports the real mime and resolution, not a mime-specific NAME_NOT_FOUND`() {
        val message = CompressorUtils.buildNoDecoderFailureMessage("video/dolby-vision", 3840, 2160)

        assertEquals(
            "This device has no video decoder that supports the source video " +
                "(mime=video/dolby-vision, 3840x2160). None of its registered " +
                "decoders can handle this resolution/codec, so it cannot be " +
                "compressed on this device.",
            message,
        )
    }

    @Test
    fun `buildNoDecoderFailureMessage handles a null mime without crashing`() {
        val message = CompressorUtils.buildNoDecoderFailureMessage(null, 0, 0)

        assertEquals(
            "This device has no video decoder that supports the source video " +
                "(mime=unknown, 0x0). None of its registered decoders can handle " +
                "this resolution/codec, so it cannot be compressed on this device.",
            message,
        )
    }

    @Test
    fun `isDecodable IS consulted for a preferred base-layer track -- this is the whole point of the fix`() {
        // FORK FIX regression guard: an earlier draft of
        // selectVideoTrackIndex picked a preferred-mime track (AVC/HEVC)
        // WITHOUT ever calling isDecodable, which defeated the point of
        // decoder-aware selection entirely (see
        // `AVC present but NOT decodable, HEVC decodable` above for the
        // concrete failure that would cause). This test just proves the
        // decodability check is genuinely reached for preferred mimes, not
        // short-circuited away.
        val tracks = listOf(0 to "video/dolby-vision", 1 to "video/hevc")
        var consultedForHevcTrack = false

        val chosen = CompressorUtils.selectVideoTrackIndex(tracks) { index ->
            if (index == 1) consultedForHevcTrack = true
            true
        }

        assertEquals(1, chosen)
        assertEquals(
            "isDecodable must be called for the preferred HEVC track " +
                "before it can be chosen -- mime match alone is not enough",
            true,
            consultedForHevcTrack,
        )
    }
}
