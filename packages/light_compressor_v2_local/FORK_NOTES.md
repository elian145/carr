# Local fork of `light_compressor_v2` 1.9.1

This is a **local, repo-owned fork** of the upstream
[`light_compressor_v2`](https://pub.dev/packages/light_compressor_v2) 1.9.1
package (MIT licensed — see `LICENSE`, unchanged). It exists ONLY to fix a
real-device Android track-selection bug that upstream cannot be patched for
in place (we do not edit files inside the pub cache). Everything else in the
package — the GL-based frame pipeline, encoder fallback chain, two-pass
target-size solver, HDR color-metadata passthrough, audio re-encode, iOS/
macOS `AVFoundation` implementation — is **unchanged** from upstream 1.9.1.

## Why this fork exists

Real-device report (Samsung SM-A175F, Android 16): a 6.995s `.mov`
(112,329,351 bytes, 2160x3840 portrait, containing BOTH a `video/dolby-vision`
track and a `video/hevc` base-layer track — confirmed via `NuMediaExtractor`
log: `track of type 'video/dolby-vision'` then `track of type 'video/hevc'`)
failed to compress with:

```
selectTrack, track[0]: video/dolby-vision
...
Failed to initialize video/dolby-vision
error 0xfffffffe (NAME_NOT_FOUND)
```

### Root cause

`lightcompressorlibrary/utils/CompressorUtils.kt`'s `findTrack()` (used by
both `Compressor.kt`'s transcode path and `LightCompressorPlugin.kt`'s
`getMediaInfo`/`readTrackDurationAndBitrate`) picked the **first** track
whose MIME starts with `"video/"`, with **no discrimination** between a
normal decodable video track and a Dolby Vision track:

```kotlin
fun findTrack(extractor: MediaExtractor, isVideo: Boolean): Int {
    val numTracks = extractor.trackCount
    for (i in 0 until numTracks) {
        val format = extractor.getTrackFormat(i)
        val mime = format.getString(MediaFormat.KEY_MIME)
        if (isVideo) {
            if (mime?.startsWith("video/")!!) return i   // <-- always track 0
        } else { ... }
    }
    return -5
}
```

The source file's `MediaExtractor` enumerates `video/dolby-vision` as
track 0 and the (Dolby-Vision-mandated, backward-compatible) `video/hevc`
base layer as track 1. `findTrack` always returns track 0. Later,
`prepareDecoder()` calls
`MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME)!!)`
— i.e. `createDecoderByType("video/dolby-vision")` — which this particular
device (MediaTek SoC, `c2.mtk.hevc.decoder` present) does not resolve to any
registered component, throwing `NAME_NOT_FOUND`. `Configuration` (the
package's only public tuning surface) has **no track-selection hook at
all** — there is no supported way to fix this from the Dart side or via any
existing configuration option.

### The fix (this fork)

`CompressorUtils.findTrack()` now enumerates every `video/*` track and
**prefers a known-decodable base-layer track** (`video/avc`, then
`video/hevc`) over anything else (Dolby Vision, AV1, or any other exotic
video mime), falling back to the first track this device's
`MediaCodecList` can actually provide a decoder for (verified via
`findDecoderForFormat`), and only falling back to the naive "first video
track" behavior if literally nothing on the device can decode any of them
(so the original, accurate "Failed to initialize <mime>" error still surfaces
instead of silently no-op-ing). This is exactly Dolby Vision's own
backward-compatibility design: every Dolby Vision stream carries a
standalone-decodable HEVC (or, for some profiles, AVC) base layer for
non-DV-aware players — preferring it is correct, not a workaround.

The identical fix is applied to `LightCompressorPlugin.readTrackDurationAndBitrate`
(used by `getMediaInfo`) so probing a Dolby-Vision-tagged source doesn't
report the wrong track's duration/bitrate either, and `handleGetMediaInfo`
now also falls back to the selected video track's `MediaFormat.KEY_FRAME_RATE`
when `MediaMetadataRetriever`'s `CAPTURE_FRAMERATE` metadata is absent (true
on most devices — it is a slow-motion-specific key, not a general "container
frame rate" key), so `MediaInfo.frameRate` is populated reliably enough for
`SellVideoCompression`'s post-transcode frame-rate verification.

No other behavior changed. iOS/macOS (`AVFoundation`) are untouched — the
reported failure and root cause are Android-`MediaExtractor`-specific.

## Files actually modified vs. upstream 1.9.1

- `android/src/main/kotlin/.../utils/CompressorUtils.kt` — `findTrack()`
- `android/src/main/kotlin/.../LightCompressorPlugin.kt` —
  `readTrackDurationAndBitrate()`, `handleGetMediaInfo()` (frame-rate
  fallback only)

Everything else is byte-for-byte upstream 1.9.1.

## Updating this fork later

If upstream fixes this (or a newer version is adopted), re-vendor from pub
cache and re-apply exactly the diffs described above — do not hand-merge
unrelated upstream changes without re-reading them first.
