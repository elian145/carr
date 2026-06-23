part of 'sell_flow.dart';

mixin _SellStep5Build on _SellStep5Logic {
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
}
