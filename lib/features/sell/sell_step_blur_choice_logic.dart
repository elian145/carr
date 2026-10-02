part of 'sell_flow.dart';

mixin _SellStepBlurChoiceFields on State<SellStepBlurChoicePage> {
  bool? _useBlurredPlates;
}

mixin _SellStepBlurChoiceLogic on _SellStepBlurChoiceFields {
  bool _didLoadChoice = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadChoice) return;
    _didLoadChoice = true;
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final raw = parent?.carData['use_blurred_plates'];
    if (raw is bool) {
      _useBlurredPlates = raw;
    }
    // Keep background blur going if photos were added earlier but blur never finished.
    if (parent != null &&
        !parent.hasBlurredPlatesReady &&
        !parent.isBlurringPlates) {
      final originals =
          parent.carData['original_images'] ?? parent.carData['images'];
      final damage = parent.carData['original_damage_images'] ??
          parent.carData['damage_images'];
      final hasMain = originals is List && originals.isNotEmpty;
      final hasDamage = damage is List && damage.isNotEmpty;
      if (hasMain || hasDamage) {
        // Widget-lifecycle fix: `startBackgroundPlateBlur()` calls
        // `setState()` on ITS OWN first synchronous line (before its
        // first `await`) -- calling it directly from here would run
        // that `setState()` synchronously from `didChangeDependencies`
        // during this page's very first build (`StatefulElement.
        // _firstBuild` -> `didChangeDependencies`), which throws
        // ("setState() or markNeedsBuild() called during build")
        // whenever a user resumes/reopens directly at this step with a
        // background blur that never finished. Deferring to the next
        // frame (well after this build completes) is the standard,
        // behavior-preserving fix for exactly this class of bug -- the
        // resumed blur still starts immediately, just one frame later.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(parent.startBackgroundPlateBlur());
        });
      }
    }
  }

  List<dynamic> _originalImages(Map<String, dynamic> carData) {
    final originals = carData['original_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final images = carData['images'];
    if (images is List) return List<dynamic>.from(images);
    return const [];
  }

  List<dynamic> _blurredImages(Map<String, dynamic> carData) {
    final blurred = carData['blurred_images'];
    if (blurred is List && blurred.isNotEmpty) {
      return _filterToCurrentSelection(
        List<dynamic>.from(blurred),
        _originalImages(carData),
      );
    }
    return const [];
  }

  List<dynamic> _damageOriginalImages(Map<String, dynamic> carData) {
    final originals = carData['original_damage_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final damage = carData['damage_images'];
    if (damage is List) return List<dynamic>.from(damage);
    return const [];
  }

  List<dynamic> _damageBlurredImages(Map<String, dynamic> carData) {
    final blurred = carData['blurred_damage_images'];
    if (blurred is List && blurred.isNotEmpty) {
      return _filterToCurrentSelection(
        List<dynamic>.from(blurred),
        _damageOriginalImages(carData),
      );
    }
    return const [];
  }

  /// Stale-media-after-delete fix (spec item 4, "defend Step 5"): even
  /// with `_removePhotoAt`/`_removeDamagePhotoAt` correctly pruning
  /// everything at delete time (see `sell_step4_logic.dart`), Step 5 must
  /// NOT trust `carData['blurred_images']`/`['blurred_damage_images']` as
  /// automatically authoritative -- it's written by a background job that
  /// can, in principle, still be racing a delete (or carry over from a
  /// stale draft). This is the belt-and-suspenders final check: drop any
  /// [blurred] entry that doesn't correspond to a CURRENTLY selected
  /// photo in [currentOriginals], matching by `_ui_media_id` when both
  /// sides carry one, else falling back to `source` path -- same
  /// identity-then-path strategy as `_pruneBlurredToCurrentSelection`
  /// (`sell_step4_logic.dart`), kept as a separate, small copy here since
  /// this file has no access to that Step4-only mixin.
  ///
  /// Path-fallback caveat (regression this fixes): a RESOLVED blurred
  /// entry's `source` is the brand-new server URL
  /// (`mergeBlurResultsIntoOriginals` -- `sell_plate_blur_merge.dart`),
  /// never equal to any original's LOCAL path -- path-matching only ever
  /// works for a still-PENDING entry (whose `source` is still a copy of
  /// its original). For data that predates `_ui_media_id` tagging
  /// entirely (pre-existing drafts/edit-mode listings), path-matching
  /// alone would therefore wrongly drop every genuinely-resolved result.
  /// [blurred] and [currentOriginals] are POSITION-aligned 1:1 by
  /// construction whenever nothing has been deleted (`pendingBlurSkeleton`
  /// / `mergeBlurResultsIntoOriginals` always return the SAME length,
  /// same order, as the originals they were built from) -- so when the
  /// lengths still match, fall back to POSITION as the untagged item's
  /// identity instead of its (post-resolution, deliberately different)
  /// `source`. Only an actual length mismatch (the real "something was
  /// deleted" signal for untagged data, which has no `_ui_media_id` to
  /// prune by) falls through to path-matching, which fails closed
  /// (drops the entry) for any already-resolved item at that point --
  /// an acceptable, conservative trade-off given there is no reliable
  /// identity available for that case at all.
  List<dynamic> _filterToCurrentSelection(
    List<dynamic> blurred,
    List<dynamic> currentOriginals,
  ) {
    if (blurred.isEmpty) return blurred;
    if (currentOriginals.isEmpty) return const [];
    final currentIds = currentOriginals
        .map(ListingImageMedia.uiMediaId)
        .whereType<String>()
        .toSet();
    final currentPaths = currentOriginals.map(ListingImageMedia.source).toSet();
    final sameLength = blurred.length == currentOriginals.length;
    final result = <dynamic>[];
    for (var i = 0; i < blurred.length; i++) {
      final item = blurred[i];
      final id = ListingImageMedia.uiMediaId(item);
      if (id != null) {
        if (currentIds.contains(id)) result.add(item);
        continue;
      }
      if (currentPaths.contains(ListingImageMedia.source(item))) {
        result.add(item);
        continue;
      }
      if (sameLength) result.add(item);
    }
    return result;
  }

  void _selectChoice(bool useBlurred) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    setState(() => _useBlurredPlates = useBlurred);
    applySellPlateBlurChoice(parent.carData, useBlurred);
    parent.setState(() {});
    unawaited(parent._saveSellDraftSnapshot());
  }

  Future<void> _retryBackgroundBlur() async {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    await parent.startBackgroundPlateBlur(
      interactive: true,
      uiContext: context,
    );
  }
}
