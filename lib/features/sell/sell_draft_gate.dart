import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/prefs/legacy_sell_draft_prefs.dart';
import '../../shared/prefs/sell_draft_step.dart';
import '../../theme_provider.dart';
import 'sell_draft_helpers.dart';

class SellDraftGatePage extends StatefulWidget {
  const SellDraftGatePage({super.key});

  @override
  State<SellDraftGatePage> createState() => _SellDraftGatePageState();
}

class _SellDraftGatePageState extends State<SellDraftGatePage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  static const Color _accent = Color(0xFFFF6B00);

  bool _loading = true;
  List<Map<String, dynamic>> _drafts = <Map<String, dynamic>>[];

  bool get _isLight => Theme.of(context).brightness == Brightness.light;

  Color get _cardFill => _isLight
      ? Colors.white
      : Color.alphaBlend(
          Colors.white.withValues(alpha: 0.085),
          AppThemes.darkHomeShellBackground,
        );

  Color get _cardBorder =>
      _isLight ? const Color(0xFFE0E0E0) : Colors.white.withValues(alpha: 0.12);

  Color get _primaryInk =>
      _isLight ? const Color(0xFF1A1A1A) : const Color(0xFFECECEC);

  Color get _secondaryInk =>
      _isLight ? Colors.grey.shade600 : Colors.white70;

  BoxDecoration get _cardDecoration => BoxDecoration(
        color: _cardFill,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isLight ? 0.05 : 0.35),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      );

  void _goBack() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.pushReplacementNamed(context, '/');
    }
  }

  String _draftTitle(Map<String, dynamic> data) {
    final brand = (data['brand'] ?? '').toString().trim();
    final model = (data['model'] ?? '').toString().trim();
    final trim = (data['trim'] ?? '').toString().trim();
    final year = (data['year'] ?? '').toString().trim();
    final title = [brand, model].where((v) => v.isNotEmpty).join(' ');
    final suffix = [trim, year].where((v) => v.isNotEmpty).join(' • ');
    if (title.isEmpty && suffix.isEmpty) return 'Untitled draft';
    if (title.isEmpty) return suffix;
    if (suffix.isEmpty) return title;
    return '$title • $suffix';
  }

  Future<void> _loadDrafts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(_draftSnapshotKey);
      final archive = decodeSellDraftArchive(sp.getString(kSellDraftArchiveKey));

      final drafts = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(activeRaw);
          if (decoded is Map) {
            final active = normalizeSellDraftSnapshot(
              Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
            );
            if (isVisibleSellDraft(active)) {
              drafts.add(<String, dynamic>{...active, 'isActive': true});
              seenIds.add(active['draftId'].toString());
            }
          }
        } catch (e, st) { logNonFatal(e, st); }
      }
      for (final draft in archive) {
        if (!isVisibleSellDraft(draft)) continue;
        final id = draft['draftId'].toString();
        if (seenIds.contains(id)) continue;
        drafts.add(<String, dynamic>{...draft, 'isActive': false});
        seenIds.add(id);
      }

      if (!mounted) return;
      setState(() {
        _drafts = drafts;
        _loading = false;
      });
      if (_drafts.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_startFresh());
        });
      }
    } catch (e, st) { logNonFatal(e, st); 
      if (!mounted) return;
      setState(() {
        _drafts = <Map<String, dynamic>>[];
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_startFresh());
      });
    }
  }

  Future<void> _archiveActiveDraftIfAny({bool clearActive = true}) async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(_draftSnapshotKey);
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = normalizeSellDraftSnapshot(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          if (isVisibleSellDraft(active)) {
            final archive =
                decodeSellDraftArchive(sp.getString(kSellDraftArchiveKey));
            archive.removeWhere((draft) => draft['draftId'] == active['draftId']);
            archive.insert(0, active);
            await sp.setString(
              kSellDraftArchiveKey,
              encodeSellDraftArchive(archive),
            );
          }
        }
      }
      if (clearActive) {
        await sp.remove(_draftSnapshotKey);
        await sp.remove('legacy_sell_draft_current_step_v1');
        await sp.remove('legacy_sell_draft_step1_v1');
        await sp.remove('legacy_sell_draft_step2_v1');
        await sp.remove('legacy_sell_draft_step3_v1');
        await sp.remove('legacy_sell_draft_step4_v1');
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.discardDraft,
        ),
        content: Text(
          AppLocalizations.of(context)!.thisWillPermanentlyDeleteThisDraftListingThisCannotBeUndone,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              AppLocalizations.of(context)!.discard,
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final draftId = (draft['draftId'] ?? '').toString();
    final isActive = draft['isActive'] == true;
    try {
      final sp = await SharedPreferences.getInstance();
      if (isActive) {
        await sp.remove(_draftSnapshotKey);
        await sp.remove('legacy_sell_draft_current_step_v1');
        await sp.remove('legacy_sell_draft_step1_v1');
        await sp.remove('legacy_sell_draft_step2_v1');
        await sp.remove('legacy_sell_draft_step3_v1');
        await sp.remove('legacy_sell_draft_step4_v1');
      } else {
        final archive =
            decodeSellDraftArchive(sp.getString(kSellDraftArchiveKey));
        archive.removeWhere((item) => item['draftId'] == draftId);
        await sp.setString(kSellDraftArchiveKey, encodeSellDraftArchive(archive));
      }
      if (!mounted) return;
      setState(() {
        _drafts.removeWhere((item) => item['draftId'] == draftId);
      });
      if (_drafts.isEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_startFresh());
        });
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  Future<void> _startFresh() async {
    LegacySellDraftPrefs.suppressPersist = true;
    await _archiveActiveDraftIfAny(clearActive: true);
    await LegacySellDraftPrefs.clearActiveStepStorage();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/sell',
      arguments: {'startFresh': true},
    );
  }

  Future<void> _startFreshWithArchive() async => _startFresh();

  Future<void> _continueDraft(Map<String, dynamic> draft) async {
    final normalized = normalizeSellDraftSnapshot(draft);
    final isActive = draft['isActive'] == true;
    if (!isActive) {
      await _archiveActiveDraftIfAny(clearActive: false);
      try {
        final sp = await SharedPreferences.getInstance();
        final archive =
            decodeSellDraftArchive(sp.getString(kSellDraftArchiveKey));
        archive.removeWhere((item) => item['draftId'] == normalized['draftId']);
        await sp.setString(kSellDraftArchiveKey, encodeSellDraftArchive(archive));
        await sp.setString(_draftSnapshotKey, json.encode(normalized));
      } catch (e, st) { logNonFatal(e, st); }
    }
    if (!mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final prefsStep = sp.getInt(_draftCurrentStepKey);
      final fromNorm = readSellDraftStepDynamic(normalized['currentStep']);
      final merged = mergeSellDraftStep(jsonStep: fromNorm, prefsStep: prefsStep);
      normalized['currentStep'] = merged;
    } catch (e, st) { logNonFatal(e, st); }
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/sell',
      arguments: {'draftSnapshot': normalized},
    );
  }

  Widget _buildStepProgress(int currentStep) {
    final step = currentStep.clamp(0, 5);
    return Row(
      children: List.generate(6, (index) {
        final filled = index <= step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: index < 5 ? 4 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: filled
                  ? _accent
                  : (_isLight ? const Color(0xFFE8E8ED) : Colors.white24),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStatusBadge({required bool isActive}) {
    final label = isActive
        ? AppLocalizations.of(context)!.inProgress
        : AppLocalizations.of(context)!.saved;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: isActive ? 0.14 : 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: _accent,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _isLight
              ? [
                  _accent.withValues(alpha: 0.12),
                  _accent.withValues(alpha: 0.03),
                ]
              : [
                  _accent.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.04),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.edit_note_rounded, color: _accent, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)!.draftsInProgress,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _primaryInk,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  AppLocalizations.of(context)!.continueAnyDraftDiscardOneOrStartANewListingWhileKeepingTheOthers,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: _secondaryInk,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftCard(Map<String, dynamic> draft) {
    final carData = draft['carData'] is Map
        ? Map<String, dynamic>.from((draft['carData'] as Map).cast<String, dynamic>())
        : <String, dynamic>{};
    final currentStep = readSellDraftStepDynamic(draft['currentStep']);
    final stepIndex = currentStep.clamp(0, 5).toInt();
    final labels = <String>[
      AppLocalizations.of(context)!.sellStep1Photos,
      AppLocalizations.of(context)!.sellStep2BasicInfo,
      AppLocalizations.of(context)!.sellStep3Details,
      AppLocalizations.of(context)!.sellStep4Pricing,
      AppLocalizations.of(context)!.sellStep5Plates,
      AppLocalizations.of(context)!.sellStep6Review,
    ];
    final label = labels[stepIndex];
    final title = _draftTitle(carData);
    final isActive = draft['isActive'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: _cardDecoration,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.directions_car_outlined, color: _accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _primaryInk,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _secondaryInk,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(isActive: isActive),
              ],
            ),
            const SizedBox(height: 14),
            _buildStepProgress(stepIndex),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.stepXOf5(stepIndex + 1),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _accent,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: () => unawaited(_continueDraft(draft)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 22),
                      label: Text(
                        AppLocalizations.of(context)!.continueAction,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: () => unawaited(_discardDraft(draft)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _secondaryInk,
                      side: BorderSide(color: _cardBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline_rounded, size: 18, color: _secondaryInk),
                        const SizedBox(width: 6),
                        Text(
                          AppLocalizations.of(context)!.discard,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: _secondaryInk,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartNewButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton.icon(
        onPressed: () => unawaited(_startFreshWithArchive()),
        style: ElevatedButton.styleFrom(
          backgroundColor: _accent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          AppLocalizations.of(context)!.startNewListing,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.directions_car_outlined,
                size: 56,
                color: _accent,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              AppLocalizations.of(context)!.startANewListing,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _primaryInk,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AppLocalizations.of(context)!.noDraftsYetCreateYourFirstCarListingToGetStarted,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: _secondaryInk,
              ),
            ),
            const SizedBox(height: 28),
            _buildStartNewButton(),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadDrafts());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.addListingTitle),
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: Container(
        decoration: AppThemes.shellBackgroundDecoration(
          Theme.of(context).brightness,
        ),
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _accent),
              )
            : (_drafts.isEmpty)
                ? _buildEmptyState()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 18),
                      ..._drafts.map(_buildDraftCard),
                      const SizedBox(height: 6),
                      _buildStartNewButton(),
                    ],
                  ),
      ),
    );
  }
}
