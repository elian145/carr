import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_localizations.dart';
import '../shared/prefs/sell_draft_prefs.dart';
import '../shared/sell/sell_draft_archive.dart';

String _sellEntryTr(
  BuildContext context,
  String en, {
  String? ar,
  String? ku,
}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

/// Resolves whether to show the draft gate or start a fresh listing.
class SellEntryRouterPage extends StatefulWidget {
  const SellEntryRouterPage({super.key});

  @override
  State<SellEntryRouterPage> createState() => _SellEntryRouterPageState();
}

class _SellEntryRouterPageState extends State<SellEntryRouterPage> {
  Future<void> _resolve() async {
    try {
      final hasDraft = await SellDraftArchive.hasAnyVisibleDraft();
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/sell',
        arguments: hasDraft ? {'showDraftGate': true} : {'startFresh': true},
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/sell',
        arguments: {'startFresh': true},
      );
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_resolve());
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

/// Lets the user resume, discard, or start fresh when drafts exist.
class SellDraftGatePage extends StatefulWidget {
  const SellDraftGatePage({super.key});

  @override
  State<SellDraftGatePage> createState() => _SellDraftGatePageState();
}

class _SellDraftGatePageState extends State<SellDraftGatePage> {
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
    if (title.isEmpty && suffix.isEmpty) {
      return _sellEntryTr(context, 'Untitled draft', ar: 'مسودة بدون عنوان', ku: 'ڕەشنووسی بێ ناو');
    }
    if (title.isEmpty) return suffix;
    if (suffix.isEmpty) return title;
    return '$title • $suffix';
  }

  Future<void> _loadDrafts() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(SellDraftPrefs.snapshotKey);
      final archive = SellDraftArchive.decodeArchive(
        sp.getString(SellDraftPrefs.archiveKey),
      );

      final drafts = <Map<String, dynamic>>[];
      final seenIds = <String>{};
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        try {
          final decoded = json.decode(activeRaw);
          if (decoded is Map) {
            final active = SellDraftArchive.normalizeSnapshot(
              Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
            );
            if (SellDraftArchive.isVisibleDraft(active)) {
              drafts.add(<String, dynamic>{...active, 'isActive': true});
              seenIds.add(active['draftId'].toString());
            }
          }
        } catch (_) {}
      }
      for (final draft in archive) {
        if (!SellDraftArchive.isVisibleDraft(draft)) continue;
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
    } catch (_) {
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
      final activeRaw = sp.getString(SellDraftPrefs.snapshotKey);
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = SellDraftArchive.normalizeSnapshot(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          if (SellDraftArchive.isVisibleDraft(active)) {
            final archive = SellDraftArchive.decodeArchive(
              sp.getString(SellDraftPrefs.archiveKey),
            );
            archive.removeWhere((draft) => draft['draftId'] == active['draftId']);
            archive.insert(0, active);
            await sp.setString(
              SellDraftPrefs.archiveKey,
              SellDraftArchive.encodeArchive(archive),
            );
          }
        }
      }
      if (clearActive) {
        await SellDraftPrefs.clearActiveStorage();
      }
    } catch (_) {}
  }

  Future<void> _discardDraft(Map<String, dynamic> draft) async {
    final draftId = (draft['draftId'] ?? '').toString();
    final isActive = draft['isActive'] == true;
    try {
      final sp = await SharedPreferences.getInstance();
      if (isActive) {
        await SellDraftPrefs.clearActiveStorage();
      } else {
        final archive = SellDraftArchive.decodeArchive(
          sp.getString(SellDraftPrefs.archiveKey),
        );
        archive.removeWhere((item) => item['draftId'] == draftId);
        await sp.setString(
          SellDraftPrefs.archiveKey,
          SellDraftArchive.encodeArchive(archive),
        );
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
    } catch (_) {}
  }

  Future<void> _startFresh() async {
    SellDraftPrefs.suppressPersist = true;
    await _archiveActiveDraftIfAny(clearActive: true);
    await SellDraftPrefs.clearActiveStepStorage();
    if (!mounted) return;
    Navigator.pushReplacementNamed(
      context,
      '/sell',
      arguments: {'startFresh': true},
    );
  }

  Future<void> _continueDraft(Map<String, dynamic> draft) async {
    final normalized = SellDraftArchive.normalizeSnapshot(draft);
    final isActive = draft['isActive'] == true;
    if (!isActive) {
      await _archiveActiveDraftIfAny(clearActive: false);
      try {
        final sp = await SharedPreferences.getInstance();
        final archive = SellDraftArchive.decodeArchive(
          sp.getString(SellDraftPrefs.archiveKey),
        );
        archive.removeWhere((item) => item['draftId'] == normalized['draftId']);
        await sp.setString(
          SellDraftPrefs.archiveKey,
          SellDraftArchive.encodeArchive(archive),
        );
        await sp.setString(
          SellDraftPrefs.snapshotKey,
          json.encode(normalized),
        );
      } catch (_) {}
    }
    if (!mounted) return;
    try {
      final sp = await SharedPreferences.getInstance();
      final prefsStep = sp.getInt(SellDraftPrefs.currentStepKey);
      final fromNorm = SellDraftArchive.readStep(normalized['currentStep']);
      normalized['currentStep'] = SellDraftArchive.mergeStep(
        jsonStep: fromNorm,
        prefsStep: prefsStep,
      );
    } catch (_) {}
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
                  child: Text(
                    isActive
                        ? _sellEntryTr(
                            context,
                            'Draft in progress',
                            ar: 'مسودة قيد التقدم',
                            ku: 'ڕەشنووسی لە پێشکەوتن',
                          )
                        : _sellEntryTr(
                            context,
                            'Saved draft',
                            ar: 'مسودة محفوظة',
                            ku: 'ڕەشنووسی پارێزراو',
                          ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => unawaited(_continueDraft(draft)),
                    icon: const Icon(Icons.play_arrow),
                    label: Text(
                      _sellEntryTr(
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
                    onPressed: () => unawaited(_discardDraft(draft)),
                    icon: const Icon(Icons.delete_outline),
                    label: Text(
                      _sellEntryTr(
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
    final loc = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(loc?.addListingTitle ?? 'Add listing'),
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
                      _sellEntryTr(
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
                      child: Text(
                        _sellEntryTr(
                          context,
                          'Continue a draft, discard one, or start a new listing.',
                          ar: 'تابع مسودة أو احذف واحدة أو ابدأ إعلانا جديدا.',
                          ku: 'ڕەشنووسێک بەردەوام پێبدە یان بسڕەوە یان ڕیکلامێکی نوێ دەستپێبکە.',
                        ),
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ..._drafts.map(_buildDraftCard),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => unawaited(_startFresh()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          _sellEntryTr(
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
