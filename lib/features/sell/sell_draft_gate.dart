import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../l10n/app_localizations.dart';
import '../../shared/debug/app_log.dart';
import '../../shared/i18n/legacy_inline_text.dart';
import '../../shared/prefs/legacy_sell_draft_prefs.dart';
import '../../shared/prefs/sell_draft_step.dart';
import 'sell_draft_helpers.dart';

class SellDraftGatePage extends StatefulWidget {
  const SellDraftGatePage({super.key});

  @override
  State<SellDraftGatePage> createState() => _SellDraftGatePageState();
}

class _SellDraftGatePageState extends State<SellDraftGatePage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';
  static const String _draftCurrentStepKey = 'legacy_sell_draft_current_step_v1';
  bool _loading = true;
  List<Map<String, dynamic>> _drafts = <Map<String, dynamic>>[];

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

  Widget _buildDraftCard(Map<String, dynamic> draft) {
    final carData = draft['carData'] is Map
        ? Map<String, dynamic>.from((draft['carData'] as Map).cast<String, dynamic>())
        : <String, dynamic>{};
    final currentStep = readSellDraftStepDynamic(draft['currentStep']);
    final labels = <String>[
      trLegacyText(context, 'Step 1: Basic info', ar: 'الخطوة 1: المعلومات الأساسية', ku: 'هەنگاو 1: زانیاری سەرەکی'),
      trLegacyText(context, 'Step 2: Details', ar: 'الخطوة 2: التفاصيل', ku: 'هەنگاو 2: وردەکاری'),
      trLegacyText(context, 'Step 3: Pricing', ar: 'الخطوة 3: السعر', ku: 'هەنگاو 3: نرخ'),
      trLegacyText(context, 'Step 4: Photos', ar: 'الخطوة 4: الصور', ku: 'هەنگاو 4: وێنەکان'),
      trLegacyText(context, 'Step 5: Review', ar: 'الخطوة 5: المراجعة', ku: 'هەنگاو 5: پێداچوونەوە'),
    ];
    final label = labels[currentStep.clamp(0, 4).toInt()];
    final title = _draftTitle(carData);
    final isActive = draft['isActive'] == true;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.24)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6B00).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.drafts_outlined, color: Color(0xFFFF6B00)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isActive
                            ? trLegacyText(
                                context,
                                'Draft in progress',
                                ar: 'مسودة قيد التقدم',
                                ku: 'ڕەشنووسی لە پێشکەوتن',
                              )
                            : trLegacyText(
                                context,
                                'Saved draft',
                                ar: 'مسودة محفوظة',
                                ku: 'ڕەشنووسی پارێزراو',
                              ),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              trLegacyText(
                context,
                'Continue, discard, or start a new listing without deleting this draft.',
                ar: 'أكمل أو احذف أو ابدأ إعلانا جديدا بدون حذف هذه المسودة.',
                ku: 'بەردەوام بە یان بسڕەوە یان ڕیکلامێکی نوێ دەستپێبکە بێ سڕینەوەی ئەم ڕەشنووسە.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _continueDraft(draft),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      trLegacyText(
                        context,
                        'Continue',
                        ar: 'متابعة',
                        ku: 'بەردەوام بە',
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _discardDraft(draft),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      trLegacyText(
                        context,
                        'Discard',
                        ar: 'حذف',
                        ku: 'بسڕەوە',
                      ),
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
        backgroundColor: const Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goBack,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_drafts.isEmpty)
              ? Center(
                  child: ElevatedButton(
                    onPressed: () => unawaited(_startFresh()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      trLegacyText(
                        context,
                        'Start new listing',
                        ar: 'ابدأ إعلانا جديدا',
                        ku: 'ڕیکلامێکی نوێ دەستپێبکە',
                      ),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.orange.withValues(alpha: 0.24)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            trLegacyText(
                              context,
                              'Drafts in progress',
                              ar: 'مسودات قيد التقدم',
                              ku: 'ڕەشنووسەکان لە پێشکەوتندان',
                            ),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            trLegacyText(
                              context,
                              'Continue any draft, discard one, or start a new listing while keeping the others.',
                              ar: 'تابع أي مسودة أو احذف واحدة أو ابدأ إعلانا جديدا مع الاحتفاظ بالباقي.',
                              ku: 'هەر ڕەشنووسێک بەردەوام پێبدە یان یەکێک بسڕەوە یان ڕیکلامێکی نوێ دەستپێبکە لەگەڵ پاراستنی ئەوانی تر.',
                            ),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._drafts.map(_buildDraftCard),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => unawaited(_startFreshWithArchive()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          trLegacyText(
                            context,
                            'Start new listing',
                            ar: 'ابدأ إعلانا جديدا',
                            ku: 'ڕیکلامێکی نوێ دەستپێبکە',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
