part of 'sell_flow.dart';

/// Runs plate blur on the sell wizard shell so work continues across steps.
mixin _SellCarPagePlateBlur on _SellCarPageDraftPersist {
  bool _isBlurringPlates = false;
  int _plateBlurJobId = 0;

  bool get isBlurringPlates => _isBlurringPlates;

  /// True only once EVERY local photo's blur job has reached a terminal,
  /// non-pending outcome (success -- blurred or truthfully "not applied"
  /// -- or a genuine, truthfully-tagged failure). See `blur_pending`/
  /// `blur_failed` (`sell_plate_blur_merge.dart`) -- this deliberately does
  /// NOT just check "list is non-empty" any more: `_blurMediaList` now
  /// publishes a non-empty PENDING skeleton the instant it starts (so the
  /// choice screen can render per-tile "Generating blurred preview…"
  /// states live), and that skeleton must not be mistaken for "ready" just
  /// because the list itself is already populated.
  bool get hasBlurredPlatesReady {
    final mainOrig = _plateBlurOriginals();
    final damageOrig = _damageBlurOriginals();
    if (mainOrig.isEmpty && damageOrig.isEmpty) return false;

    bool listReady(List<dynamic> orig, dynamic blurredRaw) {
      if (orig.isEmpty) return true;
      if (blurredRaw is! List || blurredRaw.length != orig.length) {
        return false;
      }
      return !blurredRaw.any(
        (e) =>
            e is Map && (e['blur_pending'] == true || e['blur_failed'] == true),
      );
    }

    return listReady(mainOrig, carData['blurred_images']) &&
        listReady(damageOrig, carData['blurred_damage_images']);
  }

  List<dynamic> _plateBlurOriginals() {
    final originals = carData['original_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final images = carData['images'];
    if (images is List && images.isNotEmpty) {
      return List<dynamic>.from(images);
    }
    return const [];
  }

  List<dynamic> _damageBlurOriginals() {
    final originals = carData['original_damage_images'];
    if (originals is List) {
      return List<dynamic>.from(originals);
    }
    final damage = carData['damage_images'];
    if (damage is List && damage.isNotEmpty) {
      return List<dynamic>.from(damage);
    }
    return const [];
  }

  /// Invalidates any in-flight blur job and clears blurred outputs.
  void invalidatePlateBlurJob({bool clearBlurred = true}) {
    _plateBlurJobId++;
    _isBlurringPlates = false;
    if (clearBlurred) {
      carData['blurred_images'] = <dynamic>[];
      carData['blurred_damage_images'] = <dynamic>[];
      carData['images_processed'] = false;
      carData.remove('processed_image_paths');
    }
  }

  /// OOM-fix follow-up (real-device evidence): this used to call
  /// `AiService.processCarImagesToServerPayload()` -- the fully synchronous
  /// `POST /api/process-car-images` (no `async=1`), plus `inline_base64=1`
  /// -- which ran the entire PIL decode / OpenCV plate-detection / Roboflow
  /// / blur / re-encode pipeline directly inside the `carr` web process's
  /// request handler, AND base64-encoded the full-size output for the JSON
  /// response on top of that. Unlike `SellPhotoPrestage` (the Submit-time
  /// prestage path, already fixed to use the async Celery job), THIS call
  /// fires on every single photo pick -- see the `unawaited(parentState?.
  /// startBackgroundPlateBlur())` calls in `sell_step4_logic.dart` -- so
  /// simply attaching one photo, before ever pressing Submit, was already
  /// enough to run that heavy pipeline synchronously in `carr` and OOM a
  /// 512MB instance. Moved onto the SAME async Celery job path
  /// (`AiService.enqueueCarImagesAsync` + `SellImageJobPolling`) that
  /// `SellPhotoPrestage` already uses and this repo already has passing
  /// tests for, so the actual decode/blur work now runs on
  /// `carr-worker-fra`, never in the web process. The returned `rel_path`
  /// is a server reference (URL, or a Flask-relative path resolved
  /// client-side by `buildLegacyFullImageUrl`/`_buildFullImageUrl`) --
  /// stored directly as the blurred entry's `source`, exactly like
  /// `SellPhotoPrestage` already does for staged photos; no local
  /// base64-decode/file-write step is needed any more. This requires no UI
  /// change: `_blurPreviewGrid` (`sell_step_blur_choice_build.dart`)
  /// already renders any non-local `source` via `_listingNetworkImage`.
  ///
  /// Blur-choice preview-lifecycle fix (real-device evidence: "the Blurred
  /// section ALSO visually shows originals, even after selecting Blurred,
  /// even though the backend confirms plate_blur_applied=True for some
  /// photos"): this used to await EVERY job in the batch before writing
  /// anything back to `carData` at all -- the choice screen had no way to
  /// know a job had finished until the WHOLE batch did, and (see
  /// `sell_plate_blur_merge.dart`) a successful merge left a stale local
  /// `preview_source` in place, so even a fully "ready" blurred entry for
  /// a HEIC/HEIF original kept rendering the pre-blur local file forever.
  /// [onProgress], when supplied, is invoked with an updated, same-length
  /// copy of [originals] IMMEDIATELY (a `blur_pending: true` skeleton,
  /// before any job id even comes back from the enqueue call) and again
  /// after EACH individual job resolves -- letting the choice screen
  /// render each tile's own state live instead of one all-or-nothing
  /// banner for the whole batch.
  Future<List<dynamic>> _blurMediaList({
    required List<dynamic> originals,
    required String namePrefix,
    required int jobId,
    void Function(List<dynamic> partial)? onProgress,
  }) async {
    if (originals.isEmpty) return const [];

    // Index-alignment fix: `local` must only ever contain the LOCAL-file
    // subset of `originals` (already-remote items -- e.g. pre-existing
    // edit-mode photos -- can't be re-blurred by re-uploading them, so
    // they're never sent to the blur job). `localIndices[i]` records WHERE
    // in `originals` each `local[i]`/`jobIds[i]` actually came from, so the
    // result can be written back to the correct position below instead of
    // assuming `originals` and `local` share the same order/length (see
    // `mergeBlurResultsIntoOriginals` for why that assumption was wrong).
    final localIndices = <int>[];
    final local = <XFile>[];
    for (var idx = 0; idx < originals.length; idx++) {
      final file = ListingImageMedia.localFile(originals[idx]);
      if (file != null) {
        localIndices.add(idx);
        local.add(file);
      }
    }
    if (local.isEmpty) {
      return List<dynamic>.from(originals);
    }

    List<String>? jobIds;
    try {
      jobIds = await AiService.enqueueCarImagesAsync(local, skipBlur: false);
    } catch (e, st) {
      logNonFatal(e, st, 'SellCarPage.blurMediaList.$namePrefix');
    }
    if (jobId != _plateBlurJobId) return const [];
    // Publish the PENDING skeleton right after the jobs are enqueued --
    // before polling any of them -- so the choice screen can show
    // "Generating blurred preview…" on every local tile for the whole
    // (typically much longer) polling phase, rather than a blank/not-ready
    // state until the entire batch finishes. Deliberately NOT published
    // before the `await` above: `AiService.enqueueCarImagesAsync` reads
    // each local file off disk (`http.MultipartFile.fromPath`), genuine
    // I/O this method's own callers may run inside a constrained/real
    // async context (see e.g. `sell_blur_choice_ui_and_race_test.dart`'s
    // `tester.runAsync()` usage) -- triggering a synchronous `setState()`
    // (via `onProgress`) immediately beforehand is unnecessary and only
    // adds risk for no UX benefit (the gap is one network round trip).
    if (jobIds != null && jobIds.length == local.length) {
      onProgress?.call(
        pendingBlurSkeleton(originals: originals, localIndices: localIndices),
      );
    }
    // A short/absent result means the enqueue itself failed for at least
    // one file -- the same "abandon the whole batch rather than guess
    // positional correspondence" safety choice `SellPhotoPrestage` already
    // makes for the identical ambiguity (see its `urls.length != files.length`
    // check). Publish a truthful FAILED state for every pending tile (not
    // left stuck on "Generating blurred preview…" forever) before
    // returning -- the UI already offers the "Blur plates now" retry
    // action for this case.
    if (jobIds == null || jobIds.length != local.length) {
      onProgress?.call(
        mergeBlurResultsIntoOriginals(
          originals: originals,
          localIndices: localIndices,
          relPaths: List<String?>.filled(local.length, null),
          plateBlurApplied: List<bool>.filled(local.length, false),
        ),
      );
      return const [];
    }

    final relPaths = <String?>[];
    final plateBlurApplied = <bool>[];
    for (var i = 0; i < jobIds.length; i++) {
      final polled = await SellImageJobPolling.awaitImageJobResult(
        jobIds[i],
        logTag: 'SellCarPage.blurMediaList.$namePrefix',
      );
      if (jobId != _plateBlurJobId) return const [];
      relPaths.add(polled.relPath);
      plateBlurApplied.add(polled.plateBlurApplied);
      // Progressive reveal: merge and publish JUST what's known so far --
      // every job resolved up to and including `i` gets its real outcome,
      // every job still pending after `i` keeps its `blur_pending` tile
      // (relPaths[j]/plateBlurApplied[j] for j > i simply haven't been
      // appended yet, so `mergeBlurResultsIntoOriginals`'s shorter-array
      // handling leaves those positions as the pending skeleton produced
      // moments ago -- overwritten in-place on `originals` copy below).
      if (onProgress != null) {
        final partial = pendingBlurSkeleton(
          originals: originals,
          localIndices: localIndices,
        );
        onProgress(
          mergeBlurResultsIntoOriginals(
            originals: partial,
            localIndices: localIndices.sublist(0, relPaths.length),
            relPaths: relPaths,
            plateBlurApplied: plateBlurApplied,
          ),
        );
      }
    }
    return mergeBlurResultsIntoOriginals(
      originals: originals,
      localIndices: localIndices,
      relPaths: relPaths,
      plateBlurApplied: plateBlurApplied,
    );
  }

  /// Writes [partial] into `carData['blurred_images']` (or
  /// `blurred_damage_images`) and triggers a rebuild -- shared by every
  /// `onProgress` callback passed to `_blurMediaList` below so each
  /// individual job's completion is reflected on screen the moment it
  /// resolves, not just once the entire batch finishes.
  void _publishBlurProgress(String key, List<dynamic> partial) {
    void apply() => carData[key] = partial;
    if (mounted) {
      setState(apply);
    } else {
      apply();
    }
  }

  /// Starts (or restarts) plate blur for listing + damage photos.
  /// Safe to call after navigating away from the photos step.
  Future<void> startBackgroundPlateBlur({
    bool interactive = false,
    BuildContext? uiContext,
  }) async {
    final originals = _plateBlurOriginals();
    final damageOriginals = _damageBlurOriginals();
    if (originals.isEmpty && damageOriginals.isEmpty) return;

    final jobId = ++_plateBlurJobId;
    if (mounted) {
      setState(() {
        _isBlurringPlates = true;
        carData['images_processed'] = false;
      });
    } else {
      _isBlurringPlates = true;
      carData['images_processed'] = false;
    }

    final ctx = uiContext;
    try {
      if (interactive && ctx != null && ctx.mounted) {
        if (!await ensurePhoneVerifiedForAction(ctx)) {
          if (jobId == _plateBlurJobId && mounted) {
            setState(() => _isBlurringPlates = false);
          }
          return;
        }
      }

      if (jobId != _plateBlurJobId) return;

      _debugLog(
        'AI UI: Background plate blur '
        '(main=${originals.length}, damage=${damageOriginals.length}, job $jobId)',
      );

      final blurredMain = originals.isEmpty
          ? <dynamic>[]
          : await _blurMediaList(
              originals: originals,
              namePrefix: 'listing_blur',
              jobId: jobId,
              onProgress: (partial) {
                if (jobId != _plateBlurJobId) return;
                _publishBlurProgress('blurred_images', partial);
              },
            );
      if (jobId != _plateBlurJobId) return;

      final blurredDamage = damageOriginals.isEmpty
          ? <dynamic>[]
          : await _blurMediaList(
              originals: damageOriginals,
              namePrefix: 'damage_blur',
              jobId: jobId,
              onProgress: (partial) {
                if (jobId != _plateBlurJobId) return;
                _publishBlurProgress('blurred_damage_images', partial);
              },
            );
      if (jobId != _plateBlurJobId) return;

      final mainFailed = originals.isNotEmpty && blurredMain.isEmpty;
      final damageFailed =
          damageOriginals.isNotEmpty && blurredDamage.isEmpty;
      if (mainFailed || damageFailed) {
        if (interactive && ctx != null && ctx.mounted) {
          ScaffoldMessenger.of(ctx).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(ctx)!.failedToBlurPlatesPleaseTryAgain,
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        if (mounted) {
          setState(() => _isBlurringPlates = false);
        } else {
          _isBlurringPlates = false;
        }
        return;
      }

      if (originals.isNotEmpty) {
        carData['original_images'] = List<dynamic>.from(originals);
        carData['blurred_images'] = List<dynamic>.from(blurredMain);
        carData['processed_image_paths'] = blurredMain
            .map(ListingImageMedia.source)
            .where((s) => s.trim().isNotEmpty)
            .toList();
      }
      if (damageOriginals.isNotEmpty) {
        carData['original_damage_images'] =
            List<dynamic>.from(damageOriginals);
        carData['blurred_damage_images'] =
            List<dynamic>.from(blurredDamage);
      } else {
        carData['blurred_damage_images'] = <dynamic>[];
      }

      carData['images_processed'] = true;
      carData['sell_wizard_v2'] = true;
      if (carData['use_blurred_plates'] is bool) {
        applySellPlateBlurChoice(
          carData,
          carData['use_blurred_plates'] == true,
        );
      }

      if (mounted) {
        setState(() => _isBlurringPlates = false);
      } else {
        _isBlurringPlates = false;
      }
      unawaited(_saveSellDraftSnapshot());

      if (interactive && ctx != null && ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(ctx)!.platesBlurredSuccessfully,
            ),
          ),
        );
      }
    } catch (e, st) {
      logNonFatal(e, st);
      _debugLog('AI UI: Background plate blur failed: $e');
      if (jobId != _plateBlurJobId) return;
      if (mounted) {
        setState(() => _isBlurringPlates = false);
      } else {
        _isBlurringPlates = false;
      }
      if (interactive && ctx != null && ctx.mounted) {
        if (isPhoneVerificationRequired(e)) {
          await ensurePhoneVerifiedForAction(ctx);
        }
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text(
              userErrorText(
                ctx,
                e,
                fallback: AppLocalizations.of(ctx)!.failedToBlurPlatesPleaseTryAgain,
              ),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
