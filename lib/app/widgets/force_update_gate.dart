import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_version_gate.dart';

/// Blocks the app for hard force-update; shows a dismissible soft-update prompt.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  static const _kSoftDismissPrefix = 'soft_update_dismissed:';

  ForceUpdateDecision? _decision;
  bool _loading = true;
  bool _softDialogShown = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final decision = await AppVersionGate.evaluate();
    if (!mounted) return;
    setState(() {
      _decision = decision;
      _loading = false;
    });
    if (decision.softRecommended && !decision.required) {
      await _maybeShowSoftPrompt(decision);
    }
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
    _softDialogShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Update available'),
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
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () async {
                await _openStoreUrl(decision.storeUrl);
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openStoreUrl(String raw) async {
    final url = raw.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openStore() async {
    await _openStoreUrl(_decision?.storeUrl ?? '');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return widget.child;
    final decision = _decision;
    if (decision == null || !decision.required) return widget.child;

    final theme = Theme.of(context);
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
                'Update required',
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
              if (decision.storeUrl.trim().isNotEmpty)
                FilledButton(
                  onPressed: _openStore,
                  child: const Text('Update now'),
                ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () async {
                  setState(() => _loading = true);
                  await _check();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
