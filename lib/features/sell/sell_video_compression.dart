/// Sell-video oversized/high-bitrate compression.
///
/// ============================================================================
/// AUDIT (read before touching this file)
/// ============================================================================
/// Real-device evidence: a 6-second `.mov` at 112,329,351 bytes was rejected
/// by the backend with `status=400 message="File too large. Maximum size:
/// 100MB" mime=video/quicktime`. The backend hard limit is
/// `kk/routes/media.py::upload_car_videos` -> `validate_file_upload(f,
/// max_size_mb=100, ...)` -- see [kSellVideoBackendMaxBytes] below, which
/// mirrors that EXACT number and must never be used to raise/relax what the
/// server accepts.
///
/// Existing Sell video pipeline audited before writing this file (see
/// `lib/features/sell/sell_step4_logic.dart:_pickVideos`,
/// `lib/shared/prefs/sell_draft_media_persistence.dart`,
/// `lib/features/sell/pending_sell_submission_service.dart`,
/// `lib/features/sell/sell_listing_media_upload.dart`):
///   1. `_pickVideos()` calls `image_picker.pickMultiVideo(maxDuration: 5
///      minutes)` -- so Sell ALREADY has a 5-minute client-side duration cap
///      (pre-existing product rule; NOT changed or invented by this file).
///   2. Every accepted picked video is added to `_selectedVideos`, then
///      `_syncMediaDraftToParent()` (awaited, synchronous with the pick) calls
///      `SellDraftMediaPersistence.persistDynamicMediaList(...,
///      namePrefix: 'video')`, which copies the file into
///      `getApplicationDocumentsDirectory()/sell_draft_media/<draftId>/` --
///      the durable, app-private, crash/restart-safe location. This already
///      happens BEFORE the user ever presses Submit.
///   3. `PendingSellSubmissionService.submit()` calls
///      `SellDraftMediaPersistence.prepareCarDataForStorage()` (idempotent
///      no-op for anything already under `sell_draft_media`) before writing
///      the `SellSubmissionRecord`, then `SellListingMediaUpload.uploadForCar`
///      uploads it via `POST /api/cars/<id>/videos`.
///   4. Repo-wide search found NO existing video compression/transcoding of
///      any kind: no `video_compress`, no `MediaCodec`/Media3 `Transformer`
///      use, no `AVAssetExportSession`, no FFmpeg, no native compression
///      code. The video pipeline picks, previews (`video_thumbnail`/
///      `video_player`/`chewie`), durably copies, and uploads the ORIGINAL
///      bytes verbatim -- there was nothing to reuse; adding a mechanism is
///      the correct call, not "adding a package blindly".
///
/// This file plugs compression into step 2 above -- BEFORE the durable copy
/// -- so a video is compressed at most once, at pick time, and the EXISTING
/// (already-tested) durable-copy/resume/crash-durability pipeline in
/// `SellDraftMediaPersistence` / `PendingSellSubmissionService` handles the
/// compressed file exactly like it already handles any other locally-picked
/// video. Nothing downstream needed to change for durability/resume/crash
/// safety -- it already only ever reads whatever `XFile` ends up in
/// `_selectedVideos`, and by the time that setState runs, it already IS the
/// compressed file (see `sell_step4_logic.dart:_pickVideos`).
///
/// ============================================================================
/// IMPLEMENTATION CHOICE: `light_compressor_v2` (native encoders, no FFmpeg)
/// ============================================================================
/// Candidates evaluated (see chat/task audit for the full comparison):
///   - `video_compress` (getx.site): most-downloaded, but unmaintained since
///     Feb 2025 (208 open issues) -- exactly the "old ffmpeg-less video
///     compress lib" the task said not to reach for blindly.
///   - `flutter_compress` / `video_compressor_plus`: newer, well-designed,
///     but very young (weeks old, "unverified uploader" on pub.dev) --
///     too risky to depend on for a real production upload path.
///   - `light_compressor_v2` (gurf.dev, verified publisher): a maintained
///     continuation of the long-established `light_compressor` design.
///     Android encodes via `MediaCodec`/`MediaMuxer`, iOS/macOS via
///     `AVFoundation` (`AVAssetReader`/`AVAssetWriter`) -- exactly the native
///     encoder APIs the task asked to prefer over FFmpeg. MIT, zero
///     third-party deps, ships unit + device integration tests, CI on every
///     push. Chosen for this file.
///
/// The actual native compress/probe calls are behind [SellVideoCompressor] /
/// [SellVideoProber] typedefs (both overridable via
/// `debugCompressorOverride` / `debugProberOverride`) so
/// `SellVideoCompression.prepare()` -- the only entry point the Sell UI
/// calls -- is fully unit-testable under `flutter test` without a device or
/// real codec (native plugin calls cannot run under the `flutter test` VM).
///
/// ============================================================================
/// FOLLOW-UP AUDIT: real-device Dolby Vision / dual-track failure
/// ============================================================================
/// Second real-device report (Samsung SM-A175F, Android 16): the EXACT
/// 112,329,351-byte / 6.995s `.mov` above, ALSO 2160x3840 portrait with a
/// Dolby Vision track, failed with `Failed to initialize video/dolby-vision
/// error 0xfffffffe (NAME_NOT_FOUND)`.
///
/// Root cause (confirmed by reading the plugin's Android source -- see
/// `packages/light_compressor_v2_local/FORK_NOTES.md` for the full
/// analysis): upstream `light_compressor_v2` 1.9.1's track selection always
/// picked the FIRST `video/*` track with no regard for whether it was
/// actually decodable, and this source's `MediaExtractor` enumerates
/// `video/dolby-vision` before the (Dolby-Vision-mandated,
/// standalone-decodable) `video/hevc` base layer. There was no
/// `Configuration` hook to influence this. Fixed by vendoring a **local
/// fork** of the plugin (not editing pub cache) that prefers a decodable
/// base-layer track (AVC, then HEVC) over anything else, and additionally
/// retags HDR (ST2084/HLG) color metadata as SDR on the H.264 output (see
/// the fork notes for why -- otherwise-correct colors can render
/// washed-out/dark/green on players that respect that metadata).
///
/// [outputContractViolation] adds a second, independent safety net:
/// `prepare()` re-probes its OWN output after compression and falls back to
/// [SellVideoPrepareStatus.failed] if the actual file doesn't satisfy the
/// contract (long edge, frame rate, orientation, aspect ratio) -- never
/// trusting only the parameters that were requested from the encoder.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart' as lc;

import '../../shared/debug/app_log.dart';

/// Mirrors the EXACT backend hard limit for `POST /api/cars/<id>/videos`
/// (`kk/routes/media.py::upload_car_videos` ->
/// `validate_file_upload(f, max_size_mb=100, ...)`). This task explicitly
/// forbids raising the backend limit -- this constant exists ONLY so the
/// client can pre-empt that exact rejection by compressing, never to change
/// what the server accepts. If the backend limit ever changes, update BOTH
/// `kk/routes/media.py` and this constant together.
const int kSellVideoBackendMaxBytes = 100 * 1024 * 1024;

/// Output target: cap the long edge at 1080p (1920px), preserving aspect
/// ratio/orientation (both dimensions are scaled by the same factor, and
/// which of width/height is larger is never swapped).
const int kSellVideoMaxLongEdge = 1920;

/// Output target: never encode above 30 fps. `Video.videoFps` on the
/// underlying plugin only ever downsamples -- a source already at or below
/// this rate is left unchanged (frames are never duplicated/upsampled).
const int kSellVideoMaxFrameRate = 30;

/// Output target video bitrate, in the middle of the requested 8-12 Mbps
/// band -- reasonable quality for a car-listing clip at <=1080p/30fps.
const int kSellVideoTargetBitrateMbps = 10;

/// Output target audio bitrate (AAC) when the source has an audio track.
const int kSellVideoAudioBitrateBps = 128000;

/// A source whose long edge exceeds [kSellVideoMaxLongEdge], or whose
/// bitrate exceeds this, is "obviously excessive" for a 1080p/8-12Mbps
/// listing clip and is compressed proactively even when it is already
/// under the backend byte limit (task section 3: "Prefer also compressing
/// obviously excessive 4K/high-bitrate videos even if they barely fit").
/// 16 Mbps is comfortably above the 8-12 Mbps target band, so a video below
/// this is never "excessive" purely on bitrate.
const int kSellVideoExcessiveBitrateBps = 16 * 1000 * 1000;

/// Minimal probe of a source video, used ONLY to decide whether/how to
/// compress. Never persisted, never sent to the server. Every field besides
/// [sizeBytes] is nullable because probing can fail/be partial (e.g. a
/// container the probe can't fully read) -- callers must tolerate nulls.
@immutable
class SellVideoProbe {
  const SellVideoProbe({
    required this.sizeBytes,
    this.width,
    this.height,
    this.bitrateBps,
    this.durationMs,
    this.frameRateFps,
    this.mimeType,
  });

  /// Source file size in bytes. `0` when it could not be determined either.
  final int sizeBytes;

  /// Display width/height in pixels (rotation-aware -- i.e. already
  /// swapped for a 90/270-degree-rotated source), or `null` if unknown.
  final int? width;
  final int? height;

  /// Overall bitrate in bits per second, or `null` if unknown.
  final int? bitrateBps;

  /// Duration in milliseconds, or `null` if unknown.
  final int? durationMs;

  /// Frame rate in frames per second, or `null` if unknown. Used by
  /// [SellVideoCompression.prepare]'s post-compression contract check
  /// (section 3 of the Dolby Vision/HDR follow-up task: never trust only
  /// the requested encoder parameters -- probe the actual output).
  final double? frameRateFps;

  /// The container/track MIME type (e.g. `video/mp4`), or `null` if
  /// unknown. Diagnostic-only; not currently used to gate any decision.
  final String? mimeType;
}

/// Probes [path] for [SellVideoProbe] metadata. Production uses the native
/// plugin (`_defaultProbe`); tests inject a deterministic fake via
/// [SellVideoCompression.debugProberOverride].
typedef SellVideoProber = Future<SellVideoProbe> Function(String path);

/// Everything [SellVideoCompression.prepare] decided the compressor should
/// target, computed from the source [SellVideoProbe] plus the fixed output
/// targets above.
@immutable
class SellVideoCompressRequest {
  const SellVideoCompressRequest({
    required this.sourcePath,
    required this.maxFrameRate,
    required this.videoBitrateMbps,
    required this.audioBitrateBps,
    this.targetWidth,
    this.targetHeight,
  });

  final String sourcePath;

  /// Explicit output dimensions, already scaled to preserve the source's
  /// aspect ratio/orientation and capped at [kSellVideoMaxLongEdge] on the
  /// long edge. Both null when the source is already within bounds (or its
  /// resolution could not be probed), in which case the compressor should
  /// keep the source resolution and only re-target bitrate/fps/codec.
  final int? targetWidth;
  final int? targetHeight;

  final int maxFrameRate;
  final int videoBitrateMbps;
  final int audioBitrateBps;
}

/// Where the compressor wrote its output. The path may be inside the
/// plugin's own app-specific/temp storage -- [SellVideoCompression.prepare]
/// itself never assumes it is durable; the EXISTING
/// `SellDraftMediaPersistence` pipeline (already run right after this by
/// `sell_step4_logic.dart:_pickVideos`) is what makes it durable.
@immutable
class SellVideoCompressOutput {
  const SellVideoCompressOutput(this.outputPath);
  final String outputPath;
}

/// Thrown internally when the native compressor fails, is cancelled, or
/// reports success with no readable output. Always caught by
/// [SellVideoCompression.prepare] and turned into
/// [SellVideoPrepareStatus.failed] -- never leaks past this file.
class SellVideoCompressorFailure implements Exception {
  SellVideoCompressorFailure(this.message);
  final String message;

  @override
  String toString() => 'SellVideoCompressorFailure: $message';
}

/// Runs the actual compression for [request], returning the output
/// location or throwing [SellVideoCompressorFailure]. Production uses the
/// native plugin (`_defaultCompress`); tests inject a deterministic fake
/// via [SellVideoCompression.debugCompressorOverride] (native codecs
/// cannot run under `flutter test`).
typedef SellVideoCompressor = Future<SellVideoCompressOutput> Function(
  SellVideoCompressRequest request,
);

/// Outcome of [SellVideoCompression.prepare].
enum SellVideoPrepareStatus {
  /// Source was already reasonable (under the backend limit and not
  /// "obviously excessive") -- returned completely untouched.
  unchanged,

  /// Source was compressed and the result is under the backend limit.
  compressed,

  /// Compression was attempted but failed (native error, cancelled, or
  /// produced no readable/non-empty output). The ORIGINAL source file is
  /// always left untouched in this case.
  failed,

  /// Compression succeeded but the output is STILL above
  /// [kSellVideoBackendMaxBytes]. The oversized output is deleted
  /// (best-effort); the original source is left untouched.
  stillTooLarge,
}

/// Result of [SellVideoCompression.prepare]. [file] is non-null when
/// [status] is [SellVideoPrepareStatus.unchanged] or
/// [SellVideoPrepareStatus.compressed] (i.e. [ok] is true, and [file] is
/// what the caller should use in place of the original picked file).
@immutable
class SellVideoPrepareResult {
  const SellVideoPrepareResult({
    required this.status,
    this.file,
    this.originalBytes,
    this.outputBytes,
    this.didAttemptCompression = false,
  });

  final SellVideoPrepareStatus status;
  final XFile? file;
  final int? originalBytes;
  final int? outputBytes;

  /// True once the native compressor was actually invoked (distinguishes
  /// "skipped, already fine" from "we tried and it didn't work" in logs/
  /// tests without string-matching [status]).
  final bool didAttemptCompression;

  bool get ok =>
      status == SellVideoPrepareStatus.unchanged ||
      status == SellVideoPrepareStatus.compressed;
}

/// Decides whether a Sell listing video needs compressing and, if so, runs
/// it -- see the file-level doc comment above for the full audit trail.
class SellVideoCompression {
  SellVideoCompression._();

  /// Test-only override for the probe step (native plugin calls cannot run
  /// under `flutter test`). Must be reset to `null` in `tearDown()`.
  @visibleForTesting
  static SellVideoProber? debugProberOverride;

  /// Test-only override for the compress step. Must be reset to `null` in
  /// `tearDown()`.
  @visibleForTesting
  static SellVideoCompressor? debugCompressorOverride;

  static int? _longEdge(int? w, int? h) {
    if (w == null || h == null) return null;
    return w > h ? w : h;
  }

  /// Rounds down to an even pixel count -- most hardware encoders
  /// (Android `MediaCodec`, iOS `AVAssetWriter`) require even dimensions.
  static int _evenize(int v) => v.isOdd ? v - 1 : v;

  /// True when [probe] looks "obviously excessive" for a 1080p/8-12Mbps
  /// listing clip -- i.e. worth compressing even if it is already under
  /// the backend byte limit. Exposed for tests; not part of the public
  /// pick-time contract (callers should use [prepare]).
  @visibleForTesting
  static bool isObviouslyExcessive(SellVideoProbe probe) {
    final longEdge = _longEdge(probe.width, probe.height);
    if (longEdge != null && longEdge > kSellVideoMaxLongEdge) return true;
    if (probe.bitrateBps != null &&
        probe.bitrateBps! > kSellVideoExcessiveBitrateBps) {
      return true;
    }
    return false;
  }

  static Future<bool> _fileHasContent(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      return await f.length() > 0;
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression._fileHasContent');
      return false;
    }
  }

  static Future<int> _fileLengthOrZero(String path) async {
    try {
      return await File(path).length();
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression._fileLengthOrZero');
      return 0;
    }
  }

  /// Probes [source] for [SellVideoProbe] metadata -- the exact same
  /// probe [prepare] itself uses (including [debugProberOverride] and its
  /// size-only fallback on failure). Exposed publicly so callers can make
  /// probe-only decisions -- e.g. `sell_step4_logic.dart:_pickVideos`'s
  /// 30-second duration cap -- without duplicating this fallback logic or
  /// running compression. Never throws.
  static Future<SellVideoProbe> probe(XFile source) async {
    var originalBytes = 0;
    try {
      originalBytes = await source.length();
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression.probe.sourceLength');
    }
    try {
      return await (debugProberOverride ?? _defaultProbe)(source.path);
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression.probe');
      return SellVideoProbe(sizeBytes: originalBytes);
    }
  }

  /// Prepares [source] for durable Sell-draft persistence / upload.
  ///
  /// Returns [SellVideoPrepareResult.file] to use in place of [source] when
  /// [SellVideoPrepareResult.ok] is true (status `unchanged` or
  /// `compressed`); the caller (`sell_step4_logic.dart:_pickVideos`) is
  /// responsible for showing an error and DROPPING the video (never
  /// falling back to the untouched oversized original) when it is false.
  ///
  /// Never deletes, moves, or otherwise touches [source] itself -- on
  /// every path (including failure), the original picked file is left
  /// exactly as picked.
  ///
  /// [onStatus] is invoked with a short phase tag (`'probing'` then, only
  /// when compression is actually needed, `'compressing'`) purely so the
  /// caller can drive a "Preparing video…" UI state; it carries no
  /// correctness meaning.
  static Future<SellVideoPrepareResult> prepare(
    XFile source, {
    void Function(String phase)? onStatus,
  }) async {
    onStatus?.call('probing');

    var originalBytes = 0;
    try {
      originalBytes = await source.length();
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression.prepare.sourceLength');
    }

    // Probe failure alone must never block the pick -- `probe()` already
    // falls back to a size-only probe (still enough to catch the exact
    // 112MB/100MB real-device scenario this file exists for).
    final probe = await SellVideoCompression.probe(source);
    final sizeBytes = probe.sizeBytes > 0 ? probe.sizeBytes : originalBytes;

    final overLimit = sizeBytes > kSellVideoBackendMaxBytes;
    final excessive = isObviouslyExcessive(probe);
    if (!overLimit && !excessive) {
      return SellVideoPrepareResult(
        status: SellVideoPrepareStatus.unchanged,
        file: source,
        originalBytes: sizeBytes,
        outputBytes: sizeBytes,
      );
    }

    onStatus?.call('compressing');

    int? targetWidth;
    int? targetHeight;
    final longEdge = _longEdge(probe.width, probe.height);
    if (probe.width != null &&
        probe.height != null &&
        longEdge != null &&
        longEdge > kSellVideoMaxLongEdge) {
      final scale = kSellVideoMaxLongEdge / longEdge;
      targetWidth = _evenize((probe.width! * scale).round());
      targetHeight = _evenize((probe.height! * scale).round());
      if (targetWidth < 2) targetWidth = 2;
      if (targetHeight < 2) targetHeight = 2;
    }

    final request = SellVideoCompressRequest(
      sourcePath: source.path,
      targetWidth: targetWidth,
      targetHeight: targetHeight,
      maxFrameRate: kSellVideoMaxFrameRate,
      videoBitrateMbps: kSellVideoTargetBitrateMbps,
      audioBitrateBps: kSellVideoAudioBitrateBps,
    );

    SellVideoCompressOutput output;
    try {
      output = await (debugCompressorOverride ?? _defaultCompress)(request);
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression.prepare.compress');
      return SellVideoPrepareResult(
        status: SellVideoPrepareStatus.failed,
        originalBytes: sizeBytes,
        didAttemptCompression: true,
      );
    }

    if (!await _fileHasContent(output.outputPath)) {
      return SellVideoPrepareResult(
        status: SellVideoPrepareStatus.failed,
        originalBytes: sizeBytes,
        didAttemptCompression: true,
      );
    }

    final outBytes = await _fileLengthOrZero(output.outputPath);
    if (outBytes > kSellVideoBackendMaxBytes) {
      try {
        await File(output.outputPath).delete();
      } catch (e, st) {
        logNonFatal(e, st, 'SellVideoCompression.prepare.deleteTooLarge');
      }
      return SellVideoPrepareResult(
        status: SellVideoPrepareStatus.stillTooLarge,
        originalBytes: sizeBytes,
        outputBytes: outBytes,
        didAttemptCompression: true,
      );
    }

    // Dolby Vision / dual-track follow-up, section 3: never trust only the
    // requested encoder parameters (a real-device log showed the ENCODER
    // was configured with the requested params, before those get finalized
    // -- misleading, but not proof of what was actually written). Probe the
    // ACTUAL output file and reject it (falling back to `failed`, exactly
    // like any other compression failure -- original left untouched,
    // localized error shown, nothing durable/pending ever references the
    // bad file) if it does not satisfy the output contract.
    final outputProbe = await _probeOutputSafely(output.outputPath);
    final violation = outputContractViolation(probe, outputProbe);
    if (violation != null) {
      logNonFatal(
        SellVideoCompressorFailure(violation),
        StackTrace.current,
        'SellVideoCompression.prepare.outputContractViolated',
      );
      try {
        await File(output.outputPath).delete();
      } catch (e, st) {
        logNonFatal(
          e,
          st,
          'SellVideoCompression.prepare.deleteContractViolated',
        );
      }
      return SellVideoPrepareResult(
        status: SellVideoPrepareStatus.failed,
        originalBytes: sizeBytes,
        didAttemptCompression: true,
      );
    }

    return SellVideoPrepareResult(
      status: SellVideoPrepareStatus.compressed,
      file: XFile(output.outputPath),
      originalBytes: sizeBytes,
      outputBytes: outBytes,
      didAttemptCompression: true,
    );
  }

  static Future<SellVideoProbe> _probeOutputSafely(String path) async {
    try {
      return await (debugProberOverride ?? _defaultProbe)(path);
    } catch (e, st) {
      logNonFatal(e, st, 'SellVideoCompression.prepare.probeOutput');
      // Unable to verify -- treated as "no known violation" below (an
      // unmeasurable output is not proof it broke the contract, and
      // rejecting on measurement failure alone would make an otherwise-
      // working compression unusable whenever the probe itself is flaky).
      return const SellVideoProbe(sizeBytes: 0);
    }
  }

  static double? _aspectRatio(int? w, int? h) {
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    final lo = w < h ? w : h;
    final hi = w < h ? h : w;
    return hi / lo;
  }

  static bool? _isPortrait(int? w, int? h) {
    if (w == null || h == null || w == h) return null;
    return h > w;
  }

  /// Compares the compressed [output] probe against [source] and the fixed
  /// output targets (long edge, frame rate) and returns a human-readable
  /// violation reason, or `null` when the output satisfies the contract
  /// (or there isn't enough information to prove otherwise -- an
  /// unmeasurable field is never treated as a violation).
  ///
  /// Checked, in order: output long edge <= [kSellVideoMaxLongEdge] (+2px
  /// rounding slack), output frame rate <= [kSellVideoMaxFrameRate] (+0.5fps
  /// slack), orientation preserved (portrait source stays portrait), aspect
  /// ratio preserved within 5% (catches a stretch/crop bug; not exact-pixel
  /// equality because of the +-1px evenize rounding in [prepare]).
  @visibleForTesting
  static String? outputContractViolation(
    SellVideoProbe source,
    SellVideoProbe output,
  ) {
    final outLongEdge = _longEdge(output.width, output.height);
    if (outLongEdge != null && outLongEdge > kSellVideoMaxLongEdge + 2) {
      return 'output long edge $outLongEdge exceeds the '
          '$kSellVideoMaxLongEdge cap';
    }

    if (output.frameRateFps != null &&
        output.frameRateFps! > kSellVideoMaxFrameRate + 0.5) {
      return 'output frame rate ${output.frameRateFps} exceeds the '
          '$kSellVideoMaxFrameRate fps cap';
    }

    final sourcePortrait = _isPortrait(source.width, source.height);
    final outputPortrait = _isPortrait(output.width, output.height);
    if (sourcePortrait != null &&
        outputPortrait != null &&
        sourcePortrait != outputPortrait) {
      return 'output orientation (portrait=$outputPortrait) does not match '
          'the source (portrait=$sourcePortrait)';
    }

    final sourceRatio = _aspectRatio(source.width, source.height);
    final outputRatio = _aspectRatio(output.width, output.height);
    if (sourceRatio != null && outputRatio != null && sourceRatio > 0) {
      final relativeDelta = (outputRatio - sourceRatio).abs() / sourceRatio;
      if (relativeDelta > 0.05) {
        return 'output aspect ratio $outputRatio deviates from the source '
            '$sourceRatio by more than 5% (stretch/crop?)';
      }
    }

    return null;
  }

  static Future<SellVideoProbe> _defaultProbe(String path) async {
    final info = await lc.LightCompressor().getMediaInfo(path);
    var sizeBytes = info.fileSize ?? 0;
    if (sizeBytes <= 0) sizeBytes = await _fileLengthOrZero(path);
    return SellVideoProbe(
      sizeBytes: sizeBytes,
      width: info.displayWidth,
      height: info.displayHeight,
      bitrateBps: info.bitrate,
      durationMs: info.duration?.inMilliseconds,
      frameRateFps: info.frameRate,
      mimeType: info.mimeType,
    );
  }

  static Future<SellVideoCompressOutput> _defaultCompress(
    SellVideoCompressRequest req,
  ) async {
    final outName = 'sell_video_${DateTime.now().microsecondsSinceEpoch}.mp4';
    final hasExplicitSize = req.targetWidth != null && req.targetHeight != null;
    final video = lc.Video(
      videoName: outName,
      // Explicit width/height (scaled to preserve aspect/orientation, see
      // `prepare()`) when the source needs downscaling; otherwise keep the
      // source resolution exactly and only re-target bitrate/fps/codec --
      // never upscale, crop, or stretch.
      keepOriginalResolution: !hasExplicitSize,
      videoWidth: hasExplicitSize ? req.targetWidth : null,
      videoHeight: hasExplicitSize ? req.targetHeight : null,
      videoBitrateInMbps: req.videoBitrateMbps,
      videoFps: req.maxFrameRate,
    );

    lc.Result result;
    try {
      result = await lc.LightCompressor().compressVideo(
        path: req.sourcePath,
        videoQuality: lc.VideoQuality.medium,
        // App-private storage, not the shared gallery/MediaStore -- this
        // is an intermediate encode output, not user-facing media, and
        // the EXISTING `SellDraftMediaPersistence` pipeline durably copies
        // it into `sell_draft_media/<draftId>/` right after this returns.
        android: lc.AndroidConfig(isSharedStorage: false),
        ios: lc.IOSConfig(saveInGallery: false),
        video: video,
        // Explicit H.264 (never the h265-with-fallback default) -- the
        // task asks for H.264 specifically for maximum listing-viewer
        // compatibility.
        videoFormat: lc.VideoFormat.h264,
        // Re-encode audio as AAC when the source has an audio track;
        // silently ignored by the plugin when there is none.
        audio: lc.AudioConfig(bitrate: req.audioBitrateBps),
        // `prepare()` above already decided compression is needed (over
        // the backend limit, or obviously excessive resolution/bitrate) --
        // the plugin's own "skip if source bitrate < 2Mbps" heuristic must
        // never silently override that decision and hand back the
        // original oversized bytes.
        isMinBitrateCheckEnabled: false,
      );
    } on lc.UnsupportedVideoException catch (e) {
      throw SellVideoCompressorFailure(e.message);
    } on lc.LightCompressorException catch (e) {
      throw SellVideoCompressorFailure(e.message);
    }

    if (result is lc.OnSuccess) {
      return SellVideoCompressOutput(result.destinationPath);
    }
    if (result is lc.OnCancelled) {
      throw SellVideoCompressorFailure('Video compression was cancelled.');
    }
    final failure = result as lc.OnFailure;
    throw SellVideoCompressorFailure(failure.message);
  }
}
