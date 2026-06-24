import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/debug/app_log.dart';
import 'sell_draft_helpers.dart';

class SellEntryRouterPage extends StatefulWidget {
  const SellEntryRouterPage({super.key});

  @override
  State<SellEntryRouterPage> createState() => _SellEntryRouterPageState();
}

class _SellEntryRouterPageState extends State<SellEntryRouterPage> {
  static const String _draftSnapshotKey = 'legacy_sell_draft_snapshot_v1';

  Future<void> _resolve() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final activeRaw = sp.getString(_draftSnapshotKey);
      final archive = decodeSellDraftArchive(sp.getString(kSellDraftArchiveKey));
      bool hasAnyDraft = false;
      if (activeRaw != null && activeRaw.trim().isNotEmpty) {
        final decoded = json.decode(activeRaw);
        if (decoded is Map) {
          final active = normalizeSellDraftSnapshot(
            Map<String, dynamic>.from(decoded.cast<String, dynamic>()),
          );
          hasAnyDraft = isVisibleSellDraft(active);
        }
      }
      hasAnyDraft = hasAnyDraft || archive.any(isVisibleSellDraft);
      if (!mounted) return;
      Navigator.pushReplacementNamed(
        context,
        '/sell',
        arguments: hasAnyDraft ? {'showDraftGate': true} : {'startFresh': true},
      );
    } catch (e, st) { logNonFatal(e, st); 
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
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}
