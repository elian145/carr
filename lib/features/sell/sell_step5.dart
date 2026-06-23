part of 'sell_flow.dart';
class SellStep5Page extends StatefulWidget {
  const SellStep5Page({super.key});
  @override
  State<SellStep5Page> createState() => _SellStep5PageState();
}

class _SellStep5PageState extends State<SellStep5Page> {
  bool isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final carData = parentState?.carData ?? {};
    final isLight = Theme.of(context).brightness == Brightness.light;
    final shellBg = isLight
        ? Colors.white
        : Theme.of(context).scaffoldBackgroundColor;

    return ColoredBox(
      color: shellBg,
      child: Column(
        children: [
          Expanded(child: SellReviewCarDetailScrollView(carData: carData)),
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: shellBg,
            child: SafeArea(
              top: false,
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 50,
                        child: OutlinedButton(
                        onPressed: isSubmitting
                            ? null
                            : () {
                                final parentState = context
                                    .findAncestorStateOfType<
                                      _SellCarPageState
                                    >();
                                if (parentState != null) {
                                  parentState._goToPreviousStep();
                                }
                              },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Color(0xFFFF6B00)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.previousButton,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFFF6B00),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 50,
                      child: Semantics(
                        button: true,
                        label: parentState?._isEditMode == true
                            ? AppLocalizations.of(context)!.saveChangesButton
                            : AppLocalizations.of(context)!.submitListing,
                        child: ElevatedButton(
                          onPressed: isSubmitting
                              ? null
                              : () async {
                                setState(() {
                                  isSubmitting = true;
                                });

                                try {
                                  // Client-side validation before submit
                                  final parentState = context
                                      .findAncestorStateOfType<
                                        _SellCarPageState
                                      >();
                                  final isEdit =
                                      parentState?._isEditMode == true;
                                  if (!isEdit) {
                                    final auth = context.read<AuthService>();
                                    if (!auth.isUserVerified) {
                                      setState(() {
                                        isSubmitting = false;
                                      });
                                      await ensurePhoneVerifiedForAction(
                                        context,
                                      );
                                      return;
                                    }
                                  }
                                  final Map<String, dynamic> carData =
                                      Map<String, dynamic>.from(
                                        parentState?.carData ?? {},
                                      );
                                  final List<String> required = [
                                    'brand',
                                    'model',
                                    'trim',
                                    'year',
                                    'mileage',
                                    'condition',
                                    'transmission',
                                    'fuel_type',
                                    'color',
                                    'body_type',
                                    'seating',
                                    'drive_type',
                                    'region_specs',
                                    'title_status',
                                  ];
                                  final List<String> missing = [];
                                  for (final k in required) {
                                    final v = carData[k];
                                    final isEmpty =
                                        v == null ||
                                        (v is String && v.trim().isEmpty);
                                    if (isEmpty) missing.add(k);
                                  }
                                  if (missing.isNotEmpty) {
                                    int stepFor(String k) {
                                      const step1 = {
                                        'brand',
                                        'model',
                                        'trim',
                                        'year',
                                      };
                                      const step2 = {
                                        'mileage',
                                        'condition',
                                        'transmission',
                                        'fuel_type',
                                        'color',
                                        'body_type',
                                        'seating',
                                        'drive_type',
                                        'region_specs',
                                        'title_status',
                                      };
                                      if (step1.contains(k)) return 1;
                                      if (step2.contains(k)) return 2;
                                      return 3;
                                    }

                                    final first = missing.first;
                                    final targetStep = stepFor(first);
                                    // Navigate user to the step containing the first missing field
                                    if (parentState != null) {
                                      parentState._jumpSellWizardToIndex(
                                        targetStep - 1,
                                      );
                                    }
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Please complete: ${missing.join(', ')}',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    setState(() {
                                      isSubmitting = false;
                                    });
                                    return;
                                  }
                                  // Submit the listing
                                  final submittedId = await _submitListing(
                                    carData,
                                    parentState: parentState,
                                  );
                                  if (!mounted) return;

                                  if (parentState?._isEditMode == true) {
                                    Map<String, dynamic> updatedCar =
                                        Map<String, dynamic>.from(carData);
                                    if ((submittedId ?? '').isNotEmpty) {
                                      try {
                                        final fresh = await ApiService.getCar(
                                          submittedId!,
                                        );
                                        final inner = fresh['car'];
                                        if (inner is Map) {
                                          updatedCar =
                                              Map<String, dynamic>.from(
                                            inner.cast<String, dynamic>(),
                                          );
                                        }
                                      } catch (e, st) { logNonFatal(e, st); 
                                        updatedCar['id'] = submittedId;
                                        updatedCar['public_id'] = submittedId;
                                      }
                                    }
                                    if (!context.mounted) return;
                                    try {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)!
                                                .saveChangesButton,
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } catch (e, st) { logNonFatal(e, st); }
                                    Navigator.pop(
                                      context,
                                      {'car': updatedCar},
                                    );
                                    return;
                                  }

                                  if (parentState != null) {
                                    await parentState._clearSubmittedDraftOnly(
                                      draftId: parentState._currentDraftId,
                                    );
                                  } else {
                                    final sp = await SharedPreferences.getInstance();
                                    String draftId = '';
                                    final activeRaw =
                                        sp.getString('legacy_sell_draft_snapshot_v1');
                                    if (activeRaw != null && activeRaw.trim().isNotEmpty) {
                                      try {
                                        final decoded = json.decode(activeRaw);
                                        if (decoded is Map) {
                                          draftId =
                                              (decoded['draftId'] ?? '').toString().trim();
                                        }
                                      } catch (e, st) { logNonFatal(e, st); }
                                    }
                                    await sp.remove('legacy_sell_draft_current_step_v1');
                                    await sp.remove('legacy_sell_draft_snapshot_v1');
                                    await sp.remove('legacy_sell_draft_step1_v1');
                                    await sp.remove('legacy_sell_draft_step2_v1');
                                    await sp.remove('legacy_sell_draft_step3_v1');
                                    await sp.remove('legacy_sell_draft_step4_v1');
                                    if (draftId.isNotEmpty) {
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

                                  // Show success message
                                  if (!context.mounted) return;
                                  try {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _listingSubmittedSuccessTextGlobal(
                                            context,
                                          ),
                                        ),
                                        backgroundColor: Colors.green,
                                      ),
                                    );
                                  } catch (e, st) { logNonFatal(e, st); }

                                  // Navigate back to home
                                  try {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pushNamedAndRemoveUntil(
                                      '/',
                                      (route) => false,
                                    );
                                  } catch (e, st) { logNonFatal(e, st); 
                                    // Fallback
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/',
                                    );
                                  }
                                } catch (e) {
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        userErrorText(
                                          context,
                                          e,
                                          fallback: AppLocalizations.of(
                                            context,
                                          )!.couldNotSubmitListing,
                                        ),
                                      ),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } finally {
                                  setState(() {
                                    isSubmitting = false;
                                  });
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        child: isSubmitting
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : Text(
                                parentState?._isEditMode == true
                                    ? AppLocalizations.of(context)!
                                        .saveChangesButton
                                    : AppLocalizations.of(context)!
                                        .submitListing,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// PUT payload for editing an existing listing (matches backend updatable fields).
  Map<String, dynamic> _buildCarUpdatePayload(Map<String, dynamic> carData) {
    final brand = carData['brand']?.toString() ?? '';
    final model = carData['model']?.toString() ?? '';
    final trim = carData['trim']?.toString() ?? 'Base';
    final year =
        int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
    final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
    final condition =
        (carData['condition']?.toString() ?? 'used').toLowerCase();
    final transmission =
        (carData['transmission']?.toString() ?? 'automatic').toLowerCase();
    final fuelType =
        (carData['fuel_type']?.toString() ?? 'gasoline').toLowerCase();
    final color = (carData['color']?.toString() ?? 'black').toLowerCase();
    final bodyType = (carData['body_type']?.toString() ?? 'sedan').toLowerCase();
    final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
    final driveType = (carData['drive_type']?.toString() ?? 'fwd').toLowerCase();
    final regionSpecsRaw =
        carData['region_specs']?.toString().trim().toLowerCase() ?? '';
    final regionSpecs =
        isValidCarRegionSpecCode(regionSpecsRaw) ? regionSpecsRaw : null;
    final titleStatus =
        (carData['title_status']?.toString() ?? 'clean').toLowerCase();
    final damagedParts = titleStatus == 'damaged'
        ? int.tryParse(carData['damaged_parts']?.toString() ?? '')
        : null;
    final cylinderCount = int.tryParse(
      carData['cylinder_count']?.toString() ?? '',
    );
    final engineSizeRaw = (carData['engine_size']?.toString() ?? '').trim();
    final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(engineSizeRaw) ??
        double.tryParse(engineSizeRaw);
    final priceStr = (carData['price']?.toString() ?? '').replaceAll(
      RegExp(r'[^0-9\.-]'),
      '',
    );
    final dynamic priceValue = priceStr.isEmpty
        ? null
        : (int.tryParse(priceStr) ?? double.tryParse(priceStr));
    final location = (carData['location']?.toString().trim().isNotEmpty == true)
        ? carData['location'].toString().trim()
        : (carData['city']?.toString().trim() ?? '');
    final plateType =
        (carData['plate_type']?.toString() ?? '').trim().toLowerCase();
    final plateCity = (carData['plate_city']?.toString() ?? '').trim();
    final fuelEconomy = (carData['fuel_economy']?.toString() ?? '').trim();
    final description = (carData['description']?.toString() ?? '').trim();

    return {
      'title': '$brand $model $trim'.trim(),
      'brand': brand.toLowerCase().replaceAll(' ', '-'),
      'model': model,
      'trim': trim,
      'year': year,
      'price': priceValue,
      'mileage': mileage,
      'condition': condition,
      'transmission': transmission,
      'engine_type': fuelType,
      'fuel_type': fuelType,
      'color': color,
      'body_type': bodyType,
      'seating': seating,
      'drive_type': driveType,
      'region_specs': regionSpecs,
      'title_status': titleStatus,
      'damaged_parts': damagedParts,
      'cylinder_count': cylinderCount,
      'engine_size': engineSize,
      'location': location,
      'plate_type': plateType.isNotEmpty ? plateType : null,
      'plate_city': plateCity.isNotEmpty ? plateCity : null,
      if (fuelEconomy.isNotEmpty) 'fuel_economy': fuelEconomy,
      if (description.isNotEmpty) 'description': description,
      if ((carData['vin']?.toString() ?? '').trim().isNotEmpty)
        'vin': carData['vin'].toString().trim(),
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));
  }

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

    final brand = carData['brand']?.toString() ?? '';
    final model = carData['model']?.toString() ?? '';
    final trim = carData['trim']?.toString() ?? 'Base';
    final year =
        int.tryParse(carData['year']?.toString() ?? '') ?? DateTime.now().year;
    final mileage = int.tryParse(carData['mileage']?.toString() ?? '0') ?? 0;
    final condition = (carData['condition']?.toString() ?? 'Used')
        .toLowerCase();
    final transmission = (carData['transmission']?.toString() ?? 'Automatic')
        .toLowerCase();
    final fuelType = (carData['fuel_type']?.toString() ?? 'Gasoline')
        .toLowerCase();
    final color = (carData['color']?.toString() ?? 'Black').toLowerCase();
    final bodyType = (carData['body_type']?.toString() ?? 'Sedan')
        .toLowerCase();
    final seating = int.tryParse(carData['seating']?.toString() ?? '5') ?? 5;
    final driveType = (carData['drive_type']?.toString() ?? 'fwd')
        .toLowerCase();
    final regionSpecsRaw =
        carData['region_specs']?.toString().trim().toLowerCase() ?? '';
    final regionSpecs = isValidCarRegionSpecCode(regionSpecsRaw)
        ? regionSpecsRaw
        : null;
    final titleStatus = (carData['title_status']?.toString() ?? 'clean')
        .toLowerCase();
    final damagedParts = titleStatus == 'damaged'
        ? int.tryParse(carData['damaged_parts']?.toString() ?? '')
        : null;
    final cylinderCount = int.tryParse(
      carData['cylinder_count']?.toString() ?? '',
    );
    final String engineSizeRaw = (carData['engine_size']?.toString() ?? '').trim();
    final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(engineSizeRaw) ??
        double.tryParse(engineSizeRaw);
    final price = int.tryParse(carData['price']?.toString() ?? '');
    final city = (carData['city']?.toString() ?? 'Baghdad').toLowerCase();
    final plateType =
        (carData['plate_type']?.toString() ?? '').trim().toLowerCase();
    // Keep city casing as selected in UI; some backends validate against
    // a specific list and may reject lowercased values silently.
    final plateCity = (carData['plate_city']?.toString() ?? '').trim();
    final title = '$brand $model $trim'.trim();

    // Normalize payload to match backend expectations
    final String priceStr = (carData['price']?.toString() ?? '').replaceAll(
      RegExp(r'[^0-9\.-]'),
      '',
    );
    final dynamic priceValue = priceStr.isEmpty
        ? null
        : (int.tryParse(priceStr) ?? double.tryParse(priceStr) ?? price);
    // Keep `engine_type` and `fuel_type` independent. Some older backends treated
    // these as aliases, but overwriting `fuel_type` with `engine_type` can flip
    // the user's selection (e.g. Gasoline → Diesel).
    // In this sell flow, "engine type" uses the same vocabulary as fuel type.
    // Keep them in sync to avoid mismatches across backend variants / UI surfaces.
    final String engineType = fuelType;
    final String location = (carData['location']?.toString() ?? city)
        .toString();

    final payload = {
      'title': title,
      'brand': brand.toLowerCase().replaceAll(' ', '-'),
      'model': model,
      'trim': trim,
      'year': year,
      'price': priceValue,
      'mileage': mileage,
      'condition': condition,
      'transmission': transmission,
      // Send both keys so either backend variant accepts the fields.
      'engine_type': engineType.isNotEmpty ? engineType : null,
      'fuel_type': fuelType.isNotEmpty ? fuelType : null,
      'color': color,
      'body_type': bodyType,
      'seating': seating,
      'drive_type': driveType,
      'region_specs': regionSpecs,
      'title_status': titleStatus,
      'damaged_parts': damagedParts,
      'cylinder_count': cylinderCount,
      'engine_size': engineSize,
      'location': location,
      'city': city,
      'plate_type': plateType.isNotEmpty ? plateType : null,
      // Send both snake_case and camelCase so either backend schema accepts it.
      'plateType': plateType.isNotEmpty ? plateType : null,
      'plate_city': plateCity.isNotEmpty ? plateCity : null,
      'plateCity': plateCity.isNotEmpty ? plateCity : null,
      'contact_phone': (carData['contact_phone']?.toString() ?? '').trim(),
      'description': (carData['description']?.toString() ?? '').trim(),
      'is_quick_sell': carData['is_quick_sell'] ?? false,
      if ((carData['vin']?.toString() ?? '').trim().isNotEmpty)
        'vin': carData['vin'].toString().trim(),
    }..removeWhere((k, v) => v == null || (v is String && v.trim().isEmpty));

    try {
      final editId = context
              .findAncestorStateOfType<_SellCarPageState>()
              ?._editListingId
              ?.trim() ??
          '';

      String carId = '';
      if (editId.isNotEmpty) {
        try {
          await ApiService.updateCar(editId, _buildCarUpdatePayload(carData));
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

