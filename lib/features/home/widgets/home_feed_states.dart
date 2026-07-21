import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/ui/empty_state_panel.dart';

/// Empty listings message with optional one-time auto-fetch when a sort is active.
class HomeEmptyListMessage extends StatefulWidget {
  const HomeEmptyListMessage({
    super.key,
    required this.selectedSortBy,
    required this.onAutoFetch,
  });

  final String? selectedSortBy;
  final VoidCallback onAutoFetch;

  @override
  State<HomeEmptyListMessage> createState() => _HomeEmptyListMessageState();
}

class _HomeEmptyListMessageState extends State<HomeEmptyListMessage> {
  bool _didAutoFetch = false;

  @override
  void initState() {
    super.initState();
    if (widget.selectedSortBy != null && widget.selectedSortBy!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_didAutoFetch && mounted) {
          _didAutoFetch = true;
          widget.onAutoFetch();
        }
      });
    }
  }

  @override
  void didUpdateWidget(HomeEmptyListMessage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedSortBy != null &&
        widget.selectedSortBy != oldWidget.selectedSortBy &&
        !_didAutoFetch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_didAutoFetch && mounted) {
          _didAutoFetch = true;
          widget.onAutoFetch();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return EmptyStatePanel(
      icon: Icons.search_off_outlined,
      title: loc.noCarsFound,
      hint: loc.noCarsFoundHint,
    );
  }
}

/// Full-page home feed error with retry.
class HomeFeedErrorState extends StatelessWidget {
  const HomeFeedErrorState({
    super.key,
    required this.message,
    required this.onRetry,
    this.onClearFilters,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback? onClearFilters;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 48, color: muted),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: muted),
            ),
            const SizedBox(height: 20),
            FilledButton(onPressed: onRetry, child: Text(l10n.retryAction)),
            if (onClearFilters != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onClearFilters,
                child: Text(l10n.clearFilters),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
