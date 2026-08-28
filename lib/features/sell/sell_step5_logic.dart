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

  /// Returns submit result on success so caller can navigate and show the right copy.
  Future<SellListingSubmitResult?> _submitListing(
    Map<String, dynamic> carData, {
    _SellCarPageState? parentState,
  }) async {
    // Require authentication before allowing submission
    final existingToken = ApiService.accessToken;
    if (existingToken == null || existingToken.isEmpty) {
      throw ApiException(statusCode: 401, message: 'Authentication required');
    }

    final payload = buildSellCarCreatePayload(carData);
    final draftId = parentState?._currentDraftId.isNotEmpty == true
        ? parentState!._currentDraftId
        : 'default';
    final loc = AppLocalizations.of(context)!;

    try {
      final editId =
          context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._editListingId
              ?.trim() ??
          '';

      _setSubmitStatus(
        editId.isNotEmpty ? loc.submitting : loc.creatingListing,
      );

      // Finish background photo upload started when leaving the photos step.
      if (_listingPhotoCount(carData) > 0 ||
          (parentState?.carData['images'] is List &&
              (parentState!.carData['images'] as List).isNotEmpty)) {
        _setSubmitStatus(loc.uploadingPhotos);
        await parentState?.awaitBackgroundPhotoPrestage();
        if (!mounted) return null;
        if (parentState != null) {
          _adoptPreparedMedia(carData, parentState.carData);
        }
      }

      // Copy remaining local picker files to durable paths. Android
      // cache/content URIs can vanish; never replace live photos with empty.
      final storedMedia =
          await SellDraftMediaPersistence.prepareCarDataForStorage(
            carData,
            draftId: draftId,
          );
      _adoptPreparedMedia(carData, storedMedia);

      // Stage whatever is still local (no-op when background prestage finished).
      if (_listingPhotoCount(carData) > 0) {
        _setSubmitStatus(loc.uploadingPhotos);
        await SellPhotoPrestage.stageCarData(carData);
        if (!mounted) return null;
        _setSubmitStatus(
          editId.isNotEmpty ? loc.submitting : loc.creatingListing,
        );
      }

      String carId = '';
      var pendingReview = false;
      if (editId.isNotEmpty) {
        try {
          await ApiService.updateCar(
            editId,
            buildSellCarUpdatePayload(carData),
          );
          carId = editId;
          try {
            final fresh = await ApiService.getCar(editId);
            final inner = fresh['car'];
            if (inner is Map) {
              pendingReview = isListingPendingReview(
                Map<String, dynamic>.from(inner.cast<String, dynamic>()),
              );
            }
          } catch (e, st) {
            logNonFatal(e, st);
          }
        } on ApiException {
          // Keep the ApiException so status code and error code survive for the
          // user-facing message (validation details, phone verification, 401).
          rethrow;
        }
      } else {
        // Block dispose/async draft saves for the create→upload window so a
        // killed submit cannot leave both a listing and a draft.
        parentState?._beginSubmitDraftHandoff();
        try {
          final created = await ApiService.createCar(
            payload,
            idempotencyKey: SellPendingMediaPrefs.createIdempotencyKey(draftId),
          );
          final carObj = unwrapCarApiPayload(created);
          carId = listingPrimaryId(carObj);
          pendingReview = isListingPendingReview(carObj);
        } on ApiException catch (e) {
          parentState?._abortSubmitDraftHandoff();
          _debugLog('Submission failed: ${e.statusCode} - ${e.message}');
          final body = e.body;
          String msg = e.message;
          if (body != null) {
            final List<dynamic>? errs = (body['errors'] is List)
                ? List<dynamic>.from(body['errors']!)
                : null;
            if (errs != null && errs.isNotEmpty) {
              msg = errs.map((err) => err.toString()).join(', ');
            }
          }
          // Re-throw as ApiException so the status code and error code still
          // drive the user-facing message (401 relogin, phone verification).
          throw ApiException(
            statusCode: e.statusCode,
            message: msg,
            body: e.body,
          );
        } catch (e) {
          parentState?._abortSubmitDraftHandoff();
          rethrow;
        }
      }

      if (carId.isNotEmpty) {
        // Upload media before treating submit as done. Haptics wait until photos land.
        try {
          if (editId.isEmpty) {
            await SellPendingMediaPrefs.save(
              carId: carId,
              draftId: draftId,
              carData: carData,
              pendingReview: pendingReview,
            );
            if (parentState != null) {
              await parentState._clearSubmittedDraftOnly(draftId: draftId);
            } else {
              LegacySellDraftPrefs.invalidatePersist();
              final sp = await SharedPreferences.getInstance();
              await LegacySellDraftPrefs.clearActiveStorage();
              final archive = _decodeSellDraftArchive(
                sp.getString(_sellDraftArchiveKey),
              );
              archive.removeWhere(
                (item) => item['draftId']?.toString() == draftId,
              );
              await sp.setString(
                _sellDraftArchiveKey,
                _encodeSellDraftArchive(archive),
              );
            }
          } else if (parentState != null && parentState.mounted) {
            parentState.setState(() {
              parentState.carData['images'] = carData['images'];
              parentState.carData['damage_images'] = carData['damage_images'];
              parentState.carData['videos'] = carData['videos'];
            });
          }

          final listingMediaConfirmed =
              await SellListingMediaUpload.uploadForCar(
            carId: carId,
            carData: carData,
            multipartFileBuilder: _buildVideoMultipartFile,
            onPhase: (phase) {
              if (!mounted) return;
              final phaseLoc = AppLocalizations.of(context)!;
              switch (phase) {
                case SellMediaUploadPhase.photos:
                  _setSubmitStatus(phaseLoc.uploadingPhotos);
                case SellMediaUploadPhase.videos:
                  _setSubmitStatus(phaseLoc.uploadingVideos);
                case SellMediaUploadPhase.damagePhotos:
                  _setSubmitStatus(phaseLoc.uploadingDamagePhotos);
              }
            },
          );

          if (_listingPhotoCount(carData) > 0 && !listingMediaConfirmed) {
            _setSubmitStatus(loc.uploadingPhotos);
            var hasMedia =
                await SellListingMediaUpload.listingAlreadyHasMedia(carId);
            for (var attempt = 0; !hasMedia && attempt < 4; attempt++) {
              await Future<void>.delayed(
                Duration(milliseconds: 300 * (attempt + 1)),
              );
              hasMedia =
                  await SellListingMediaUpload.listingAlreadyHasMedia(carId);
            }
            if (!hasMedia) {
              throw StateError(
                'Listing photos did not finish uploading. Please try again.',
              );
            }
          }

          // Precache off the submit path so success navigation is not blocked.
          if (mounted) {
            final svc = CarService();
            final createdCar = svc.cars
                .where((c) => c['id']?.toString() == carId)
                .toList();
            final Map<String, dynamic>? car = createdCar.isNotEmpty
                ? createdCar.first
                : null;
            if (car != null) {
              unawaited(_precacheSubmittedListingImages(car));
            }
          }
          await SellPendingMediaPrefs.clear();
        } catch (e, st) {
          logNonFatal(e, st, 'sell_step5.uploadMedia');
          unawaited(
            Future<void>.delayed(const Duration(seconds: 4), () {
              SellPendingMediaResume.tryResume();
            }),
          );
          Error.throwWithStackTrace(e, st);
        }
        unawaited(AppHaptics.success());
        _debugLog(
          editId.isNotEmpty
              ? 'Listing updated successfully'
              : 'Listing created successfully',
        );
        return SellListingSubmitResult(
          id: carId,
          pendingReview: pendingReview,
        );
      }

      throw Exception('Failed to create listing');
    } catch (e) {
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
