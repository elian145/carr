part of 'sell_flow.dart';

mixin _SellStep5Logic on _SellStep5Fields {
  /// Returns the created car id on success so caller can navigate to listing page; null otherwise.
  Future<String?> _submitListing(
    Map<String, dynamic> carData, {
    _SellCarPageState? parentState,
  }) async {
    // Require authentication before allowing submission
    final existingToken = ApiService.accessToken;
    if (existingToken == null || existingToken.isEmpty) {
      throw Exception('Authentication required');
    }

    final payload = buildSellCarCreatePayload(carData);

    try {
      final editId = context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._editListingId
              ?.trim() ??
          '';

      String carId = '';
      if (editId.isNotEmpty) {
        try {
          await ApiService.updateCar(editId, buildSellCarUpdatePayload(carData));
          carId = editId;
        } on ApiException catch (e) {
          throw Exception(e.message);
        }
      } else {
        try {
          final created = await ApiService.createCar(payload);
          final carObj = unwrapCarApiPayload(created);
          carId = listingPrimaryId(carObj);
        } on ApiException catch (e) {
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
        }
      }

      if (carId.isNotEmpty) {
        // Success - listing created or updated
        // Upload/attach images and wait for list refresh so the new listing has all image URLs before we show success
        try {
          final draftId = parentState?._currentDraftId.isNotEmpty == true
              ? parentState!._currentDraftId
              : 'default';
          final storedMedia =
              await SellDraftMediaPersistence.prepareCarDataForStorage(
            carData,
            draftId: draftId,
          );
          carData['images'] = storedMedia['images'];
          carData['damage_images'] = storedMedia['damage_images'];
          carData['videos'] = storedMedia['videos'];
          if (parentState != null && parentState.mounted) {
            parentState.setState(() {
              parentState.carData['images'] = carData['images'];
              parentState.carData['damage_images'] = carData['damage_images'];
              parentState.carData['videos'] = carData['videos'];
            });
          }

          final dynamic maybeImgs = carData['images'];
          final List<dynamic> imgs = (maybeImgs is List) ? maybeImgs : const [];
          final dynamic maybeVideos = carData['videos'];
          final List<dynamic> vids = (maybeVideos is List)
              ? maybeVideos
              : const [];
          final List<XFile> toUpload = <XFile>[];
          final List<String> toAttach = <String>[];
          final List<XFile> videosToUpload =
              SellDraftMediaPersistence.xFilesForUpload(vids);
          for (final dynamic img in imgs) {
            if (img is XFile) {
              if (File(img.path).existsSync()) {
                toUpload.add(img);
              }
            } else if (img is String) {
              final s = img.trim();
              // If it's a server-relative path (from "Blur Plates"), attach it; don't treat it as a local file.
              if (s.startsWith('uploads/') ||
                  s.startsWith('static/') ||
                  s.startsWith('/static/')) {
                toAttach.add(s);
              } else if (s.startsWith('http://') || s.startsWith('https://')) {
                // We don't attach absolute URLs; if you ever store them, keep them as-is in DB via other flow.
                // For now, ignore.
              } else if (File(s).existsSync()) {
                toUpload.add(XFile(s));
              }
            }
          }
          if (toAttach.isNotEmpty) {
            await CarService().attachCarImages(carId, toAttach);
          } else if (toUpload.isNotEmpty) {
            // No blur on submit; backend is called with skip_blur=1
            await CarService().uploadCarImages(carId, toUpload);
          }
          if (videosToUpload.isNotEmpty) {
            try {
              final payload = await ApiService.uploadCarVideos(
                carId,
                videosToUpload,
                multipartFileBuilder: _buildVideoMultipartFile,
              );
              final uploaded = payload['videos'];
              final uploadedCount = uploaded is List ? uploaded.length : 0;
              if (uploadedCount == 0) {
                _debugLog(
                  'Video upload returned success but 0 videos: $payload',
                );
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        (payload['message'] ?? 'No valid videos were uploaded.')
                            .toString(),
                      ),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            } on ApiException catch (e) {
              _debugLog('Video upload failed: ${e.statusCode} ${e.message}');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Video upload failed (${e.statusCode}). ${e.message.isNotEmpty ? e.message : ''}',
                    ),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            } catch (e, st) {
              logNonFatal(e, st);
            }
          }
          final dynamic maybeDmg = carData['damage_images'];
          final List<dynamic> dimgs =
              (maybeDmg is List) ? maybeDmg : const [];
          final List<XFile> damageToUpload = <XFile>[];
          final List<String> damageToAttach = <String>[];
          for (final dynamic img in dimgs) {
            if (img is XFile) {
              if (File(img.path).existsSync()) {
                damageToUpload.add(img);
              }
            } else if (img is String) {
              final s = img.trim();
              if (s.startsWith('uploads/') ||
                  s.startsWith('static/') ||
                  s.startsWith('/static/')) {
                damageToAttach.add(s);
              } else if (s.startsWith('http://') || s.startsWith('https://')) {
                // Skip absolute URLs for attach/upload here.
              } else if (File(s).existsSync()) {
                damageToUpload.add(XFile(s));
              }
            }
          }
          if (damageToAttach.isNotEmpty) {
            await CarService().attachCarImages(
              carId,
              damageToAttach,
              kind: 'damage',
            );
          }
          if (damageToUpload.isNotEmpty) {
            await CarService().uploadCarImages(
              carId,
              damageToUpload,
              imageKind: 'damage',
            );
          }
          // Refresh list so new listing has server-confirmed image_url/images before success/navigation
          try {
            await CarService().getCars(refresh: true);
          } catch (e, st) { logNonFatal(e, st); }
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
                  await precacheImage(NetworkImage(url), context);
                } catch (e, st) { logNonFatal(e, st); }
              }
            }
          }
        } catch (e) {
          if (!mounted) return carId;
          try {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  AppLocalizations.of(
                    context,
                  )!.listingUploadPartialFail(
                    AppLocalizations.of(context)!.errorTitle,
                  ),
                ),
              ),
            );
          } catch (e, st) { logNonFatal(e, st); }
        }
        _debugLog(
          editId.isNotEmpty
              ? 'Listing updated successfully'
              : 'Listing created successfully',
        );
        return carId;
      }

      throw Exception('Failed to create listing');
    } catch (e) {
      rethrow;
    }
  }

}
