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
      case SellSubmissionPhase.uploadingVideoSource:
        return loc.sellVideoUploadingSource;
      case SellSubmissionPhase.processingVideoOnServer:
        return loc.sellVideoProcessingOnServer;
      case SellSubmissionPhase.finishingVideoUpload:
        return loc.sellVideoFinishing;
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
  ///
  /// Fast optimistic submission: calls [PendingSellSubmissionService.
  /// submitFast] (NOT [PendingSellSubmissionService.submit]) so this
  /// method — and therefore the Submit button's success navigation —
  /// returns as soon as the backend listing itself exists, without
  /// waiting for image/video upload or a `requiresServerTranscode`
  /// video's 60-120s server-side transcode. That media work keeps running
  /// in the background via the SAME durable [PendingSellSubmissionService]
  /// worker regardless of this page navigating away; see
  /// `owner_pending_media_merge.dart` for how My Listings / the listing
  /// detail page show the seller their locally-selected photos/videos in
  /// the meantime, and `submitFast`'s own doc comment for the full
  /// contract.
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

    // Media-readiness contract fix (new-listing submission must not wait
    // on image processing before `create_car()`): this pre-create
    // "prestage" upload+poll-to-completion step is EDIT-MODE ONLY now.
    // For a new listing, `submitFast()`'s own Phase A (raw bytes
    // durably server-owned + async job accepted, NOT full processing --
    // see `SellListingMediaUpload.runPhaseAOnly`) is what makes
    // `create_car()` + media transfer fast without ever blocking on
    // resize/blur completion; awaiting this pre-create prestage job here
    // would defeat that entirely by making the seller wait on the exact
    // same (or, worse, redundant/duplicate) processing work before
    // `submitFast()` even gets a chance to run. Edit-mode submissions are
    // explicitly out of scope for this fix (left byte-for-byte unchanged,
    // including this wait) -- see `PendingSellSubmissionService`'s own
    // Phase-A gate, which is create-mode only for the same reason.
    if (isEdit &&
        (_listingPhotoCount(carData) > 0 ||
            (parentState?.carData['images'] is List &&
                (parentState!.carData['images'] as List).isNotEmpty))) {
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
      final result = await PendingSellSubmissionService.instance.submitFast(
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
