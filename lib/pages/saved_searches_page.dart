import 'dart:async';

import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/saved_search_service.dart';
import '../shared/home/saved_search_apply.dart';
import '../shared/home/saved_search_filter_chips.dart';
import '../shared/shell/main_shell_navigation.dart';
import '../theme_provider.dart';

class SavedSearchesPage extends StatefulWidget {
  const SavedSearchesPage({super.key});

  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends State<SavedSearchesPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final merged = await SavedSearchService.loadMerged();
    if (!mounted) return;
    setState(() {
      _items = merged;
      _loading = false;
    });
  }

  Future<void> _save() async {
    await SavedSearchService.persistLocal(_items);
  }

  Future<void> _rename(int index) async {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(
      text: _items[index]['name']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.renameTooltip),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _items[index]['name'] = controller.text.trim().isEmpty
            ? _items[index]['name']
            : controller.text.trim();
      });
      await _save();
      unawaited(SavedSearchService.pushItemToServer(_items[index]));
    }
  }

  Future<void> _delete(int index) async {
    final id = (_items[index]['id'] ?? '').toString();
    setState(() => _items.removeAt(index));
    await _save();
    unawaited(SavedSearchService.deleteOnServer(id));
  }

  Future<void> _toggleNotify(int index, bool value) async {
    setState(() => _items[index]['notify'] = value);
    await _save();
    unawaited(SavedSearchService.pushItemToServer(_items[index]));
  }

  String _formatDate(BuildContext context, String dateString) {
    try {
      final date = DateTime.parse(dateString);
      final now = DateTime.now();
      final difference = now.difference(date);
      final l = AppLocalizations.of(context)!;
      final timeStr =
          '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

      if (difference.inDays == 0) {
        return '${l.today} $timeStr';
      } else if (difference.inDays == 1) {
        return '${l.yesterday} $timeStr';
      } else if (difference.inDays < 7) {
        return l.daysAgo(difference.inDays);
      }
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateString;
    }
  }

  Future<void> _applySearch(Map<String, dynamic> filters) async {
    final normalized = SavedSearchService.normalizeFilters(filters);
    await SavedSearchApply.persistForHome(normalized);

    if (!mounted) return;
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    Navigator.pop(context);
    navigateMainShellTab(context, '/');

    messenger.showSnackBar(
      SnackBar(
        content: Text(loc.applySearch),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFilterDetails(String searchName, Map<String, dynamic> filters) {
    final loc = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(searchName),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.moreFilters,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              SavedSearchFilterChips(filters: filters),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.cancelAction),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_applySearch(filters));
            },
            child: Text(loc.applySearch),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final muted = Theme.of(context).brightness == Brightness.dark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurfaceVariant;

    return Scaffold(
      appBar: AppBar(title: Text(loc.savedSearchesTitle)),
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B00)),
              ),
            )
          else if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off, size: 64, color: muted),
                    const SizedBox(height: 16),
                    Text(
                      loc.noSavedSearchesYet,
                      style: TextStyle(fontSize: 18, color: muted),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      loc.savedSearchesHint,
                      style: TextStyle(color: muted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: _load,
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final filters = item['filters'] is Map
                      ? Map<String, dynamic>.from(
                          (item['filters'] as Map).cast<String, dynamic>(),
                        )
                      : <String, dynamic>{};
                  final title = savedSearchDisplayTitle(context, item);

                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ListTile(
                      onTap: () => _showFilterDetails(title, filters),
                      leading: const Icon(Icons.bookmark, color: Color(0xFFFF6B00)),
                      title: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          SavedSearchFilterChips(filters: filters),
                          const SizedBox(height: 4),
                          Text(
                            _formatDate(
                              context,
                              item['created_at']?.toString() ?? '',
                            ),
                            style: TextStyle(fontSize: 12, color: muted),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              (item['notify'] == true)
                                  ? Icons.notifications_active
                                  : Icons.notifications_none,
                              color: const Color(0xFFFF6B00),
                            ),
                            onPressed: () => _toggleNotify(
                              index,
                              item['notify'] != true,
                            ),
                            tooltip: loc.settingsEnablePush,
                          ),
                          IconButton(
                            icon: const Icon(Icons.search, color: Colors.green),
                            onPressed: () => unawaited(_applySearch(filters)),
                            tooltip: loc.applySearch,
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _rename(index),
                            tooltip: loc.renameTooltip,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _delete(index),
                            tooltip: loc.deleteTooltip,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
