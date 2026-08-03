part of 'sell_flow.dart';

mixin _SellStep5Logic on _SellStep5Fields {
  /// Returns submit result on success so caller can navigate and show the right copy.
  Future<SellListingSubmitResult?> _submitListing(
    Map<String, dynamic> carData, {
    _SellCarPageState? parentState,
  }) async {
    // Require authentication before allowing submission
    final existingToken = ApiService.accessToken;
    if (existingToken == null || existingToken.isEmpty) {
      throw Exception('Authentication required');
    }

    final payload = buildSellCarCreatePayload(carData);
    final draftId = parentState?._currentDraftId.isNotEmpty == true
        ? parentState!._currentDraftId
        : 'default';

    try {
      final editId =
          context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._editListingId
              ?.trim() ??
          '';

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
        } on ApiException catch (e) {
          throw Exception(e.message);
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
          if (e.statusCode == 401) {
            _debugLog('Submission failed: Authentication failed');
            throw Exception('Authentication failed. Please log in again.');
          }
          _debugLog('Submission failed: ${e.statusCode} - ${e.message}');
          final body = e.body;
          String? msg = e.message;
          if (body != null) {
            final List<dynamic>? errs = (body['errors'] is List)
                ? List<dynamic>.from(body['errors']!)
                : null;
            if (errs != null && errs.isNotEmpty) {
              msg = errs.map((err) => err.toString()).join(', ');
            }
          }
          throw Exception(msg);
        } catch (e) {
          parentState?._abortSubmitDraftHandoff();
          rethrow;
        }
      }

      if (carId.isNotEmpty) {
        // Success - listing created or updated
        unawaited(AppHaptics.success());
        // Upload/attach images and wait for list refresh so the new listing has all image URLs before we show success
        try {
          // Hide the draft as soon as the server listing exists so a kill
          // during media prep/upload cannot show listing + draft.
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
          }

          final storedMedia =
              await SellDraftMediaPersistence.prepareCarDataForStorage(
                carData,
                draftId: draftId,
              );
          carData['images'] = storedMedia['images'];
          carData['damage_images'] = storedMedia['damage_images'];
          carData['videos'] = storedMedia['videos'];
          // Refresh pending paths after durable media copy.
          if (editId.isEmpty) {
            await SellPendingMediaPrefs.save(
              carId: carId,
              draftId: draftId,
              carData: carData,
              pendingReview: pendingReview,
            );
          } else if (parentState != null && parentState.mounted) {
            parentState.setState(() {
              parentState.carData['images'] = carData['images'];
              parentState.carData['damage_images'] = carData['damage_images'];
              parentState.carData['videos'] = carData['videos'];
            });
          }

          await SellListingMediaUpload.uploadForCar(
            carId: carId,
            carData: carData,
            multipartFileBuilder: _buildVideoMultipartFile,
          );

          // Precache all listing images so they appear instantly when user views the listing (no placeholder wait)
          if (mounted) {
            final svc = CarService();
            final createdCar = svc.cars
                .where((c) => c['id']?.toString() == carId)
                .toList();
            final Map<String, dynamic>? car = createdCar.isNotEmpty
                ? createdCar.first
                : null;
            if (car != null) {
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
                    ? (it['image_url'] ??
                              it['url'] ??
                              it['path'] ??
                              it['src'] ??
                              '')
                          .toString()
                    : it.toString();
                if (s.isNotEmpty) {
                  final full = _buildFullImageUrl(s);
                  if (!urls.contains(full)) urls.add(full);
                }
              }
              if (urls.isEmpty && imgs.isNotEmpty) {
                dynamic first;
                for (final dynamic e in imgs) {
                  if (e is Map &&
                      (e['kind'] ?? '').toString().toLowerCase() == 'damage') {
                    continue;
                  }
                  first = e;
                  break;
                }
                if (first != null) {
                  final String s = first is Map
                      ? (first['image_url'] ??
                                first['url'] ??
                                first['path'] ??
                                first['src'] ??
                                '')
                            .toString()
                      : first.toString();
                  if (s.isNotEmpty) urls.add(_buildFullImageUrl(s));
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
                  logNonFatal(e, st);
                }
              }
            }
          }
          await SellPendingMediaPrefs.clear();
        } catch (e, st) {
          logNonFatal(e, st, 'sell_step5.uploadMedia');
          // Keep pending media so a cold start can finish the upload.
          if (!mounted) {
            return SellListingSubmitResult(
              id: carId,
              pendingReview: pendingReview,
            );
          }
          try {
            final loc = AppLocalizations.of(context)!;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  loc.listingUploadPartialFail(
                    userErrorText(context, e, fallback: loc.errorTitle),
                  ),
                ),
              ),
            );
          } catch (snackErr, snackSt) {
            logNonFatal(snackErr, snackSt);
          }
        }
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
}
