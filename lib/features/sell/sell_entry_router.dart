import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../shared/debug/app_log.dart';
import 'pending_sell_submission_service.dart';
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
      // Resume-after-reopen fix (see `SellDraftGatePage._loadDrafts` for the
      // full explanation): kick off resume so a fast one clears a stale
      // draft snapshot before it's read below, and never count a draftId
      // that has an active `PendingSellSubmissionRecord` as an ordinary,
      // routable "has a draft" signal -- that submission is already being
      // auto-resumed in the background and surfaced via the global
      // `SellSubmissionStatusBanner`, not this ordinary-draft flow.
      appLog('[SELL RESUME] entry router: resolving, triggering resume check');
      unawaited(PendingSellSubmissionService.instance.resumeAll());

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
          final activeId = active['draftId'].toString();
          final pending =
              await PendingSellSubmissionService.instance.peek(activeId);
          if (pending != null) {
            appLog(
              '[SELL RESUME] entry router: active draft id=$activeId has a '
              'pending submission (status=${pending.status.name}); not '
              'counting it as an ordinary draft',
            );
          } else if (isVisibleSellDraft(active)) {
            hasAnyDraft = true;
          } else {
            await sp.remove(_draftSnapshotKey);
            await sp.remove('legacy_sell_draft_current_step_v1');
          }
        }
      }
      final visibleArchive =
          archive.where(isVisibleSellDraft).toList(growable: false);
      if (visibleArchive.length != archive.length) {
        if (visibleArchive.isEmpty) {
          await sp.remove(kSellDraftArchiveKey);
        } else {
          await sp.setString(
            kSellDraftArchiveKey,
            encodeSellDraftArchive(visibleArchive),
          );
        }
      }
      var routableArchiveCount = 0;
      for (final draft in visibleArchive) {
        final id = draft['draftId'].toString();
        final pending = await PendingSellSubmissionService.instance.peek(id);
        if (pending != null) {
          appLog(
            '[SELL RESUME] entry router: archived draft id=$id has a '
            'pending submission (status=${pending.status.name}); not '
            'counting it as an ordinary draft',
          );
          continue;
        }
        routableArchiveCount++;
      }
      hasAnyDraft = hasAnyDraft || routableArchiveCount > 0;
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
