part of 'sell_flow.dart';

mixin _SellStep5Logic on _SellStep5Fields {
  void _setSubmitStatus(String message) {
    if (!mounted) return;
    setState(() => submitStatusMessage = message);
  }

  void _adoptPreparedMedia(
    Map<String, dynamic> live,
    Map<String, dynamic> stored,
  ) {
    for (final key in ['images', 'damage_images', 'videos']) {
      final persisted = stored[key];
      if (persisted is List && persisted.isNotEmpty) {
        live[key] = persisted;
        continue;
      }
      // Keep the live picker / content-URI files when the disk copy dropped
      // them, so an empty persist result never wipes the user's photos.
      final current = live[key];
      final liveHas = current is List && current.isNotEmpty;
      if (!liveHas && persisted != null) live[key] = persisted;
    }
  }

  int _listingPhotoCount(Map<String, dynamic> carData) {
    final imgs = carData['images'];
    if (imgs is! List) return 0;
    var n = 0;
    for (final item in imgs) {
      if (ListingImageMedia.source(item).isNotEmpty) n++;
    }
    return n;
  }

  String _submitPhaseLocalizedMessage(
    BuildContext context,
    SellSubmissionPhase phase, {
    required bool isEdit,
  }) {
    final loc = AppLocalizations.of(context)!;
    switch (phase) {
      case SellSubmissionPhase.creating:
        return isEdit ? loc.submitting : loc.creatingListing;
      case SellSubmissionPhase.uploadingPhotos:
        return loc.uploadingPhotos;
      case SellSubmissionPhase.uploadingVideos:
        return loc.uploadingVideos;
      case SellSubmissionPhase.uploadingDamagePhotos:
        return loc.uploadingDamagePhotos;
      case SellSubmissionPhase.done:
        return isEdit ? loc.submitting : loc.creatingListing;
    }
  }

  /// Returns submit result on success so caller can navigate and show the
  /// right copy.
  ///
  /// The actual create-listing / upload-media work happens inside
  /// [PendingSellSubmissionService] — a process-wide coordinator that is
  /// NOT owned by this widget's `State`. Pressing Submit durably records
  /// the submission and starts (or joins) that coordinator; this method
  /// only does the same-session bookkeeping that still makes sense while
  /// this page happens to be mounted (draft-handoff flags, localized
  /// status text, precache) and otherwise just awaits the result. If this
  /// widget is disposed (user navigates away) while the `await` below is
  /// pending, the service keeps running unaffected — nothing in this
  /// method or in the service ever checks this widget's `mounted` to
  /// decide whether to *continue* the submission, only whether it is still
  /// safe to touch this widget's own state.
  Future<SellListingSubmitResult?> _submitListing(
    Map<String, dynamic> carData, {
    _SellCarPageState? parentState,
  }) async {
    // Require authentication before allowing submission.
    final existingToken = ApiService.accessToken;
    if (existingToken == null || existingToken.isEmpty) {
      throw ApiException(statusCode: 401, message: 'Authentication required');
    }

    final draftId = parentState?._currentDraftId.isNotEmpty == true
        ? parentState!._currentDraftId
        : 'default';
    final loc = AppLocalizations.of(context)!;
    final editId =
        context
            .findAncestorStateOfType<_SellCarPageState>()
            ?._editListingId
            ?.trim() ??
        '';
    final isEdit = editId.isNotEmpty;

    _setSubmitStatus(isEdit ? loc.submitting : loc.creatingListing);

    // Finish background photo upload started when leaving the photos step,
    // and adopt whatever it staged. This is a same-session optimization
    // only available while this widget is mounted; a headless resume (app
    // restart, no SellStep5 in the tree) simply skips it — the service's
    // own staging inside `PendingSellSubmissionService.submit` covers that
    // case idempotently.
    if (_listingPhotoCount(carData) > 0 ||
        (parentState?.carData['images'] is List &&
            (parentState!.carData['images'] as List).isNotEmpty)) {
      _setSubmitStatus(loc.uploadingPhotos);
      await parentState?.awaitBackgroundPhotoPrestage();
      if (mounted && parentState != null) {
        _adoptPreparedMedia(carData, parentState.carData);
      }
    }

    // Block dispose/async draft saves for the create→upload window so a
    // killed submit cannot leave both a listing and a draft. This only
    // affects this widget *instance* (harmless / a no-op once it is
    // disposed); the durable record created by the service below is what
    // actually survives navigation, backgrounding, or a process kill.
    if (!isEdit) {
      parentState?._beginSubmitDraftHandoff();
    }

    try {
      final result = await PendingSellSubmissionService.instance.submit(
        draftId: draftId,
        carData: carData,
        editListingId: isEdit ? editId : null,
        onPhase: (phase) {
          if (!mounted) return;
          _setSubmitStatus(
            _submitPhaseLocalizedMessage(context, phase, isEdit: isEdit),
          );
        },
      );

      if (result == null) {
        // The service could not start (e.g. signed out between validation
        // and this call) — surface the same 401 the pre-existing guard at
        // the top of this method would have.
        throw ApiException(
          statusCode: 401,
          message: 'Authentication required',
        );
      }

      if (isEdit && parentState != null && parentState.mounted) {
        parentState.setState(() {
          parentState.carData['images'] = carData['images'];
          parentState.carData['damage_images'] = carData['damage_images'];
          parentState.carData['videos'] = carData['videos'];
        });
      }

      // Precache off the submit path so success navigation is not blocked.
      if (mounted) {
        final svc = CarService();
        final createdCar = svc.cars
            .where((c) => c['id']?.toString() == result.id)
            .toList();
        final Map<String, dynamic>? car = createdCar.isNotEmpty
            ? createdCar.first
            : null;
        if (car != null) {
          unawaited(_precacheSubmittedListingImages(car));
        }
      }

      _debugLog(
        isEdit ? 'Listing updated successfully' : 'Listing created successfully',
      );
      return result;
    } catch (e) {
      // Only release this widget's draft-handoff flag when no listing was
      // created yet — once a listing exists, the "draft" is this
      // in-progress submission (tracked by the service), and resuming
      // normal draft editing on it would risk confusing UX (not
      // duplicate listings — the idempotency key still prevents that).
      if (!isEdit) {
        final hasListing =
            await PendingSellSubmissionService.instance.hasCreatedListing(
          draftId,
        );
        if (!hasListing) {
          parentState?._abortSubmitDraftHandoff();
        }
      }
      rethrow;
    }
  }

  Future<void> _precacheSubmittedListingImages(Map<String, dynamic> car) async {
    final List<String> urls = <String>[];
    final String primary = (car['image_url'] ?? '').toString();
    final List<dynamic> imgs = (car['images'] is List)
        ? (car['images'] as List)
        : const [];
    if (primary.isNotEmpty) urls.add(_buildFullImageUrl(primary));
    for (final dynamic it in imgs) {
      if (it is Map &&
          (it['kind'] ?? '').toString().toLowerCase() == 'damage') {
        continue;
      }
      final String s = it is Map
          ? (it['image_url'] ?? it['url'] ?? it['path'] ?? it['src'] ?? '')
                .toString()
          : it.toString();
      if (s.isNotEmpty) {
        final full = _buildFullImageUrl(s);
        if (!urls.contains(full)) urls.add(full);
      }
    }
    for (final url in urls) {
      if (url.isEmpty || !mounted) continue;
      try {
        await precacheImage(
          listingCachedNetworkImageProvider(url),
          context,
        );
      } catch (e, st) {
        if (!isExpectedClientNoise(e)) logNonFatal(e, st);
      }
    }
  }
}
