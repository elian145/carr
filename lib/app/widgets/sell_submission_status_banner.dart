import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/sell/pending_sell_submission_service.dart';
import '../../l10n/app_localizations.dart';
import '../carzo_shared.dart' show productionNavigatorKey;

/// F-41: determinate fraction for the banner spinner, or null (indeterminate)
/// while the total is unknown.
double? sellSubmissionProgressFraction(SellSubmissionUiStatus status) {
  if (status.totalMediaCount <= 0) return null;
  return (status.completedMediaCount / status.totalMediaCount)
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Test hook / stable finder for the banner's cancel button.
const Key kSellSubmissionBannerCancelKey = ValueKey<String>(
  'sell-submission-banner-cancel',
);

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


  static String? _progressValueText(SellSubmissionUiStatus status) {
    final f = sellSubmissionProgressFraction(status);
    return f == null ? null : '${(f * 100).round()}%';
  }

  /// F-41: ask before cancelling (accidental taps must not lose an upload).
  Future<void> _confirmCancel(String draftId) async {
    final ctx = productionNavigatorKey.currentContext;
    if (ctx == null) return;
    final loc = AppLocalizations.of(ctx);
    if (loc == null) return;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (dctx) => AlertDialog(
        content: Text(loc.a11yCancelUploadConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(false),
            child: Text(loc.a11yKeepUploading),
          ),
          TextButton(
            onPressed: () => Navigator.of(dctx).pop(true),
            child: Text(loc.a11yCancelUpload),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final outcome =
        await PendingSellSubmissionService.instance.cancelSubmission(draftId);
    if (outcome == SellCancelOutcome.draftKept && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(loc.a11yUploadCancelledDraftKept)),
      );
    }
  }
  String _phaseLabel(
    AppLocalizations? loc,
    SellSubmissionUiStatus status,
  ) {
    // Phase 3B: the server-transcode fallback's three sub-phases get their
    // own short, already-localized labels (added alongside the rest of
    // this feature's strings) instead of the generic count-based message
    // below -- never exposes HTTP status, task ids, R2 keys, or any
    // upload internals, exactly like every other label this banner
    // already shows. Every other phase (including the coarse
    // `uploadingVideos` used by the normal <=100MB video path) keeps its
    // EXACT pre-existing behavior below, unchanged.
    switch (status.phase) {
      case SellSubmissionPhase.uploadingVideoSource:
        return loc?.sellVideoUploadingSource ?? 'Uploading video…';
      case SellSubmissionPhase.processingVideoOnServer:
        return loc?.sellVideoProcessingOnServer ?? 'Processing video…';
      case SellSubmissionPhase.finishingVideoUpload:
        return loc?.sellVideoFinishing ?? 'Finishing video…';
      case SellSubmissionPhase.creating:
      case SellSubmissionPhase.uploadingPhotos:
      case SellSubmissionPhase.uploadingVideos:
      case SellSubmissionPhase.uploadingDamagePhotos:
      case SellSubmissionPhase.done:
        break;
    }
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

        // `verticalDirection: up` + the bar as the LAST child keeps the bar
        // visually on top while painting it AFTER the app content. The
        // Navigator's route barrier uses BlockSemantics, which drops the
        // semantics of anything painted before it; with the bar first, its
        // live-region progress and cancel button were invisible to TalkBack /
        // VoiceOver (F-41).
        return Column(
          verticalDirection: VerticalDirection.up,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: child),
            Material(
              color: bg,
              elevation: 1,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(
                    start: 16,
                    end: 4,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        // F-41: one announced node -- label + percentage value
                        // (live region, so progress changes are spoken).
                        child: Semantics(
                          liveRegion: true,
                          label: _phaseLabel(loc, status),
                          value: _progressValueText(status),
                          excludeSemantics: true,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: fg,
                                    value: sellSubmissionProgressFraction(status),
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
                      if (!status.isEdit && loc != null)
                        // No `tooltip:` on purpose: this banner is mounted in
                        // `MaterialApp.builder`, ABOVE the Navigator, so there is
                        // no Overlay ancestor and a Tooltip would assert while a
                        // submission is active. The accessible name comes from
                        // Semantics instead; the 48dp target is kept.
                        // MergeSemantics => ONE labelled button node (not a
                        // label node plus an unlabelled button child).
                        MergeSemantics(
                          child: Semantics(
                            label: loc.a11yCancelUpload,
                            child: IconButton(
                              key: kSellSubmissionBannerCancelKey,
                              constraints: const BoxConstraints(
                                minWidth: 48,
                                minHeight: 48,
                              ),
                              icon: Icon(Icons.close, color: fg),
                              onPressed: () => _confirmCancel(status.draftId),
                            ),
                          ),
                        )
                      else
                        const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
