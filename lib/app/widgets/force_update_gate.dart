import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_version_gate.dart';

/// Blocks the app when the server requires a newer client build.
class ForceUpdateGate extends StatefulWidget {
  const ForceUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate> {
  ForceUpdateDecision? _decision;
  bool _loading = true;

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
  }

  Future<void> _openStore() async {
    final url = (_decision?.storeUrl ?? '').trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
