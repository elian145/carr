part of 'sell_flow.dart';

mixin _SellStep5Build on _SellStep5Logic {
  @override
  Widget build(BuildContext context) {
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final carData = parentState?.carData ?? {};
    final isLight = Theme.of(context).brightness == Brightness.light;
    // Match [CarDetailsPage] shell so the review preview blends with listing detail.
    final shellBg = isLight
        ? Colors.white
        : AppThemes.darkHomeShellBackground;

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
                          side: BorderSide(color: AppColors.brandOrange),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          AppLocalizations.of(context)!.previousButton,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brandOrange,
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
                                  final Map<String, dynamic> carData =
                                      Map<String, dynamic>.from(
                                        parentState?.carData ?? {},
                                      );
                                  final contactPhones =
                                      sellContactPhonesFromCarData(carData);
                                  if (contactPhones.isNotEmpty) {
                                    final verified =
                                        await ensureAllListingContactPhonesVerified(
                                      context,
                                      contactPhones: contactPhones,
                                      verifiedPhonesCache:
                                          parentState?._verifiedListingPhones,
                                    );
                                    if (!verified) {
                                      setState(() {
                                        isSubmitting = false;
                                      });
                                      return;
                                    }
                                  }
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
                                  // Media + contact live outside the simple
                                  // string map; validate explicitly so a
                                  // restored draft or edit cannot submit blank.
                                  final imagesVal = carData['images'];
                                  final hasImages =
                                      imagesVal is List && imagesVal.isNotEmpty;
                                  if (!hasImages) missing.add('images');
                                  if ((carData['city'] ?? '')
                                      .toString()
                                      .trim()
                                      .isEmpty) {
                                    missing.add('city');
                                  }
                                  if (contactPhones.isEmpty) {
                                    missing.add('contact_phone');
                                  }
                                  if (missing.isNotEmpty) {
                                    int stepFor(String k) {
                                      const basic = {
                                        'brand',
                                        'model',
                                        'trim',
                                        'year',
                                      };
                                      const details = {
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
                                      // Wizard indices: 0 photos, 1 basic, 2 details, 3 pricing/contact
                                      if (k == 'images') return 0;
                                      if (basic.contains(k)) return 1;
                                      if (details.contains(k)) return 2;
                                      return 3;
                                    }

                                    final first = missing.first;
                                    final targetStep = stepFor(first);
                                    // Navigate user to the step containing the first missing field
                                    if (parentState != null) {
                                      parentState._jumpSellWizardToIndex(
                                        targetStep,
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
                                  final submitResult = await _submitListing(
                                    carData,
                                    parentState: parentState,
                                  );
                                  if (!mounted) return;
                                  final submittedId = submitResult?.id;

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

                                  // Show success message (live vs under review — UX-05)
                                  if (!context.mounted) return;
                                  final pending =
                                      submitResult?.pendingReview ?? false;
                                  try {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          _listingSubmittedSuccessTextGlobal(
                                            context,
                                            pendingReview: pending,
                                          ),
                                        ),
                                        backgroundColor:
                                            pending ? const Color(0xFFF57C00) : Colors.green,
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  } catch (e, st) { logNonFatal(e, st); }

                                  // Send sellers to My Listings (Pending tab when under review).
                                  // Keep the home route so Back returns to the main shell.
                                  try {
                                    Navigator.of(
                                      context,
                                      rootNavigator: true,
                                    ).pushNamedAndRemoveUntil(
                                      '/my_listings',
                                      ModalRoute.withName('/'),
                                      arguments: <String, dynamic>{
                                        if (pending) 'filter': 'pending',
                                      },
                                    );
                                  } catch (e, st) { logNonFatal(e, st); 
                                    // Fallback
                                    Navigator.pushReplacementNamed(
                                      context,
                                      '/my_listings',
                                      arguments: <String, dynamic>{
                                        if (pending) 'filter': 'pending',
                                      },
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
                          backgroundColor: AppColors.brandOrange,
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
}
