import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../services/app_version_gate.dart';
import '../../shared/debug/app_log.dart';

/// Opens a validated store URL (overridable in tests).
typedef StoreUrlLauncher = Future<bool> Function(Uri uri);

Future<bool> _defaultLaunch(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Blocks the app for hard force-update; shows a dismissible soft-update prompt.
///
/// The gate lives in `MaterialApp.builder`, i.e. ABOVE the app's [Navigator].
/// Pass [navigatorKey] (the app's root navigator key) so the soft-update
/// dialog is shown through the Navigator instead of this widget's own
/// context (which has no Navigator ancestor there).
///
/// Re-checks the server config when the app returns to the foreground
/// ([AppVersionGate.shouldRecheckOnResume]) and on "Try again" (which really
/// refetches), so lowering the server floor releases blocked users.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({
    super.key,
    required this.child,
    this.navigatorKey,
    this.urlLauncher,
  });

  final Widget child;
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Test hook; defaults to `launchUrl(..., externalApplication)`.
  final StoreUrlLauncher? urlLauncher;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate>
    with WidgetsBindingObserver {
  static const _kSoftDismissPrefix = 'soft_update_dismissed:';

  ForceUpdateDecision? _decision;
  bool _loading = true;
  bool _retrying = false;
  bool _softDialogShown = false;
  int _checkSeq = 0;

  bool get _isBlocked => _decision?.required == true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!AppVersionGate.shouldRecheckOnResume(blocked: _isBlocked)) return;
    _check(forceRefresh: true);
  }

  Future<void> _check({bool forceRefresh = false}) async {
    final seq = ++_checkSeq;
    ForceUpdateDecision decision;
    try {
      decision = await AppVersionGate.evaluate(forceRefresh: forceRefresh);
    } catch (e, st) {
      // evaluate() never throws by contract; if it ever does, fail open.
      logNonFatal(e, st, 'ForceUpdateGate._check');
      decision = const ForceUpdateDecision(required: false);
    }
    // A newer check (e.g. "Try again" during a resume check) supersedes us.
    if (!mounted || seq != _checkSeq) return;
    setState(() {
      _decision = decision;
      _loading = false;
      _retrying = false;
    });
    if (decision.softRecommended && !decision.required) {
      await _maybeShowSoftPrompt(decision);
    }
  }

  /// Context that actually has a [Navigator] ancestor (or is the Navigator).
  BuildContext? _dialogContext() {
    final key = widget.navigatorKey;
    if (key != null) return key.currentContext;
    if (Navigator.maybeOf(context) != null) return context;
    return null;
  }

  Future<void> _maybeShowSoftPrompt(ForceUpdateDecision decision) async {
    if (_softDialogShown || !mounted) return;
    final key = decision.softPromptKey.trim();
    if (key.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('$_kSoftDismissPrefix$key') == true) return;
    } catch (_) {
      // Still show the prompt if prefs fail.
    }
    if (!mounted) return;
    var dialogContext = _dialogContext();
    if (dialogContext == null && widget.navigatorKey != null) {
      // First frame: the Navigator is not built yet. Wait one frame.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      dialogContext = _dialogContext();
    }
    if (dialogContext == null || !dialogContext.mounted) {
      appLog('ForceUpdateGate: no Navigator available for the soft prompt');
      return;
    }
    _softDialogShown = true;
    try {
      await showDialog<void>(
        context: dialogContext,
        barrierDismissible: true,
        builder: (ctx) {
          final l10n = AppLocalizations.of(ctx)!;
          return AlertDialog(
            title: Text(l10n.updateAvailableTitle),
            content: Text(decision.message),
            actions: [
              TextButton(
                onPressed: () async {
                  try {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('$_kSoftDismissPrefix$key', true);
                  } catch (_) {}
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Text(l10n.notNowButton),
              ),
              FilledButton(
                onPressed: () async {
                  await _openStoreUrl(decision.storeUrl);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                },
                child: Text(l10n.updateButton),
              ),
            ],
          );
        },
      );
    } catch (e, st) {
      // A soft prompt must never take the app down.
      logNonFatal(e, st, 'ForceUpdateGate.softPrompt');
    }
  }

  /// Opens the store page; a missing/malformed URL or a launch failure is a
  /// silent no-op (never throws into the UI).
  Future<void> _openStoreUrl(String raw) async {
    final url = AppVersionGate.sanitizeStoreUrl(raw);
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      await (widget.urlLauncher ?? _defaultLaunch)(uri);
    } catch (e, st) {
      logNonFatal(e, st, 'ForceUpdateGate.openStore');
    }
  }

  Future<void> _openStore() async {
    await _openStoreUrl(_decision?.storeUrl ?? '');
  }

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    // Bypass the cache: a real refetch, so a lowered floor releases the user.
    await _check(forceRefresh: true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.child;
    final decision = _decision;
    if (decision == null || !decision.required) return widget.child;

    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final canOpenStore =
        AppVersionGate.sanitizeStoreUrl(decision.storeUrl).isNotEmpty;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.system_update,
                size: 64,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                l10n.updateRequiredTitle,
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                decision.message,
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (canOpenStore)
                FilledButton(
                  onPressed: _openStore,
                  child: Text(l10n.updateNowButton),
                ),
              const SizedBox(height: 12),
              if (_retrying)
                const SizedBox(
                  height: 48,
                  child: Center(
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                TextButton(
                  onPressed: _retry,
                  child: Text(l10n.tryAgainButton),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
