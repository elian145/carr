part of 'sell_flow.dart';

/// Runs plate blur on the sell wizard shell so work continues across steps.
mixin _SellCarPagePlateBlur on _SellCarPageDraftPersist {
  bool _isBlurringPlates = false;
  int _plateBlurJobId = 0;

  bool get isBlurringPlates => _isBlurringPlates;

  bool get hasBlurredPlatesReady {
    final mainOrig = _plateBlurOriginals();
    final damageOrig = _damageBlurOriginals();
    if (mainOrig.isEmpty && damageOrig.isEmpty) return false;

    final mainBlurred = carData['blurred_images'];
    final damageBlurred = carData['blurred_damage_images'];
    final mainOk = mainOrig.isEmpty ||
        (mainBlurred is List && mainBlurred.isNotEmpty);
    final damageOk = damageOrig.isEmpty ||
        (damageBlurred is List && damageBlurred.isNotEmpty);
    return mainOk && damageOk;
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

  Future<List<dynamic>> _blurMediaList({
    required List<dynamic> originals,
    required String namePrefix,
    required int jobId,
  }) async {
    if (originals.isEmpty) return const [];

    final local = originals
        .map(ListingImageMedia.localFile)
        .whereType<XFile>()
        .toList();
    if (local.isEmpty) {
      return List<dynamic>.from(originals);
    }

    final payload = await AiService.processCarImagesToServerPayload(local);
    if (jobId != _plateBlurJobId) return const [];

    final paths = payload?['paths'] ?? const <String>[];
    final b64 = payload?['base64'] ?? const <String>[];
    if (paths.isEmpty) return const [];

    final draftId = _currentDraftId.isNotEmpty ? _currentDraftId : 'default';
    final blurredLocal = <dynamic>[];
    for (var i = 0; i < paths.length; i++) {
      if (jobId != _plateBlurJobId) return const [];
      final dataUri = (i < b64.length) ? b64[i].toString() : null;
      final previous = i < originals.length ? originals[i] : paths[i].toString();
      if (dataUri != null &&
          dataUri.startsWith('data:') &&
          dataUri.contains('base64,')) {
        final idx = dataUri.indexOf('base64,');
        final raw = base64Decode(dataUri.substring(idx + 7));
        final stored = await SellDraftMediaPersistence.persistBytesToDraft(
          raw,
          draftId: draftId,
          namePrefix: namePrefix,
        );
        if (stored != null && stored.isNotEmpty) {
          blurredLocal.add(
            ListingImageMedia.map(
              previous,
              source: stored,
              focusY: ListingImageMedia.focusY(previous),
              width: ListingImageMedia.width(previous),
              height: ListingImageMedia.height(previous),
            ),
          );
          continue;
        }
      }
      if (i < originals.length) {
        blurredLocal.add(originals[i]);
      }
    }
    return blurredLocal.isNotEmpty
        ? blurredLocal
        : List<dynamic>.from(originals);
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
            );
      if (jobId != _plateBlurJobId) return;

      final blurredDamage = damageOriginals.isEmpty
          ? <dynamic>[]
          : await _blurMediaList(
              originals: damageOriginals,
              namePrefix: 'damage_blur',
              jobId: jobId,
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
