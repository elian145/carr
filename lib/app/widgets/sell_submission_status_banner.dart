import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/sell/pending_sell_submission_service.dart';
import '../../l10n/app_localizations.dart';
import '../carzo_shared.dart' show productionNavigatorKey;

/// Global, page-independent UI for `PendingSellSubmissionService` (req.
/// #10): a persistent slim progress banner while a submission is actively
/// uploading, plus one-shot success / needs-attention / retrying
/// notifications — all regardless of whether `SellStep5Page` (or even
/// `SellCarPage`) is anywhere in the widget tree, since the coordinator
/// this listens to is not owned by those pages.
///
/// Mounted once in [MaterialApp.builder] (see `production_app.dart`),
/// alongside `ConnectivityBanner`.
class SellSubmissionStatusBanner extends StatefulWidget {
  const SellSubmissionStatusBanner({super.key, required this.child});

  final Widget child;

  @override
  State<SellSubmissionStatusBanner> createState() =>
      _SellSubmissionStatusBannerState();
}

class _SellSubmissionStatusBannerState
    extends State<SellSubmissionStatusBanner> {
  StreamSubscription<SellSubmissionEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = PendingSellSubmissionService.instance.events.listen(_onEvent);
  }

  void _onEvent(SellSubmissionEvent event) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final loc = AppLocalizations.of(context);

    String message;
    Color? background;
    if (event.success) {
      message = event.pendingReview
          ? (loc?.listingSubmittedPending ??
              'Your listing was submitted and is pending review.')
          : (loc?.listingSubmittedSuccess ??
              'Your listing was submitted successfully.');
      background = event.pendingReview ? const Color(0xFFF57C00) : Colors.green;
    } else if (event.needsAttention) {
      // Permanent failure (req. #11): never auto-retried. The backend
      // listing may already exist (its id survives on the failed record
      // even though the local Sell draft was discarded right after
      // creation) — in that case the original draft is gone, so "open the
      // draft" would be a dead end. Point the user at My Listings instead,
      // where the existing Edit/Delete actions operate directly on the
      // listing id and can fix or remove it (no new listing is ever
      // created from that flow — edits always PATCH the existing id).
      final hasListing = (event.carId ?? '').trim().isNotEmpty;
      message = hasListing
          ? (loc?.sellSubmissionNeedsAttention ??
              "Your listing was created, but we couldn't finish uploading it. "
                  'Open My Listings to fix it.')
          : (loc?.sellSubmissionNeedsAttentionNoListing ??
              "We couldn't finish creating your listing. Open My Listings to "
                  'find and fix the draft.');
      background = Colors.red;
    } else {
      // Transient failure — a background retry is already scheduled
      // automatically (connectivity restore / app resume / next
      // bootstrap); this is purely informational.
      message = loc?.sellSubmissionRetrying ?? 'Finishing your listing upload…';
      background = null;
    }

    try {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: background,
          duration: Duration(seconds: event.needsAttention ? 8 : 4),
          action: event.needsAttention
              ? SnackBarAction(
                  label: loc?.sellSubmissionOpenMyListingsAction ??
                      'My Listings',
                  textColor: Colors.white,
                  onPressed: () {
                    // Use the app-wide navigator key (not this widget's own
                    // `context`, which sits above the routed `Navigator` in
                    // `MaterialApp.builder`) -- same pattern already used by
                    // `FirstRunOnboardingGate`.
                    productionNavigatorKey.currentState
                        ?.pushNamed('/my_listings');
                  },
                )
              : null,
        ),
      );
    } catch (_) {
      // Best-effort only; never let a notification failure break the app.
    }
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  String _phaseLabel(
    AppLocalizations? loc,
    SellSubmissionUiStatus status,
  ) {
    if (status.totalMediaCount > 0) {
      return loc?.sellSubmissionUploadingProgress(
            status.completedMediaCount.clamp(0, status.totalMediaCount),
            status.totalMediaCount,
          ) ??
          'Uploading listing… ${status.completedMediaCount} of '
              '${status.totalMediaCount} media uploaded';
    }
    return loc?.sellSubmissionUploadingGeneric ?? 'Uploading listing…';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<SellSubmissionUiStatus?>(
      valueListenable: PendingSellSubmissionService.instance.statusNotifier,
      builder: (context, status, _) {
        final child = widget.child;
        if (status == null || status.phase == SellSubmissionPhase.done) {
          return child;
        }
        final loc = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final bg = theme.colorScheme.primaryContainer;
        final fg = theme.colorScheme.onPrimaryContainer;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: bg,
              elevation: 1,
              child: SafeArea(
                bottom: false,
                child: Semantics(
                  liveRegion: true,
                  label: _phaseLabel(loc, status),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fg,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _phaseLabel(loc, status),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}
