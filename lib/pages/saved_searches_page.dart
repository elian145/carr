import 'dart:async';

import 'package:flutter/material.dart';

import '../app/listing_shell.dart' show navigateMainShellTab;
import '../data/car_name_translations.dart';
import '../features/saved_searches/saved_search_home_bridge.dart';
import '../l10n/app_localizations.dart';
import '../services/saved_search_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/listing_field_labels.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/region_spec_labels.dart';

part 'saved_searches_page_helpers.dart';

class SavedSearchesPage extends StatefulWidget {
  final dynamic parentState;

  const SavedSearchesPage({super.key, this.parentState});

  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends State<SavedSearchesPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final merged = await SavedSearchService.loadMerged();
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)!.error,
        );
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await SavedSearchService.persistLocal(_items);
  }

  void _rename(int index) async {
    final controller = TextEditingController(
      text: _items[index]['name']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.save),
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

  void _delete(int index) async {
    final id = (_items[index]['id'] ?? '').toString();
    setState(() {
      _items.removeAt(index);
    });
    await _save();
    unawaited(SavedSearchService.deleteOnServer(id));
  }

  void _toggleNotify(int index, bool value) async {
    setState(() {
      _items[index]['notify'] = value;
    });
    await _save();
    unawaited(SavedSearchService.pushItemToServer(_items[index]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.savedSearchesTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: Text(AppLocalizations.of(context)!.retryAction),
                  ),
                ],
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noSavedSearchesYet,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.savedSearchesHint,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (context, index) => Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                final filters = item['filters'] as Map<String, dynamic>? ?? {};

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    onTap: () => _showFilterDetails(
                      _localizedSearchTitle(context, item),
                      filters,
                    ),
                    leading: Icon(Icons.bookmark, color: Color(0xFFFF6B00)),
                    title: Text(
                      _localizedSearchTitle(context, item),
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        _buildFilterChips(context, filters),
                        SizedBox(height: 4),
                        Text(
                          _formatDate(
                            context,
                            item['created_at']?.toString() ?? '',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
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
                          tooltip: trLegacyText(
                            context,
                            'Alerts',
                            ar: 'التنبيهات',
                            ku: 'ئاگادارکردنەوە',
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.search, color: Colors.green),
                          onPressed: () => _applySearch(filters),
                          tooltip: AppLocalizations.of(context)!.applySearch,
                        ),
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _rename(index),
                          tooltip: AppLocalizations.of(context)!.renameTooltip,
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _delete(index),
                          tooltip: AppLocalizations.of(context)!.deleteTooltip,
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
