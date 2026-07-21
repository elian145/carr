import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../services/connectivity_service.dart';

/// Persistent top banner when the device has no network interface.
///
/// Mounted once in [MaterialApp.builder] so every route shows offline state
/// instead of only cryptic API failures.
class ConnectivityBanner extends StatefulWidget {
  const ConnectivityBanner({super.key, required this.child});

  final Widget child;

  @override
  State<ConnectivityBanner> createState() => _ConnectivityBannerState();
}

class _ConnectivityBannerState extends State<ConnectivityBanner> {
  @override
  void initState() {
    super.initState();
    unawaited(ConnectivityService.instance.start());
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.instance.isOnline,
      builder: (context, online, _) {
        final child = widget.child;
        if (online) return child;

        final loc = AppLocalizations.of(context);
        final message = loc?.offlineBannerMessage ?? "You're offline";
        final theme = Theme.of(context);
        final bg = theme.colorScheme.errorContainer;
        final fg = theme.colorScheme.onErrorContainer;

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
                  label: message,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.cloud_off, size: 18, color: fg),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            message,
                            style: theme.textTheme.bodyMedium?.copyWith(
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
