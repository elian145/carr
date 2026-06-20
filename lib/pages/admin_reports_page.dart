import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';

/// Admin moderation queue for user and listing reports.
class AdminReportsPage extends StatefulWidget {
  const AdminReportsPage({super.key});

  @override
  State<AdminReportsPage> createState() => _AdminReportsPageState();
}

class _AdminReportsPageState extends State<AdminReportsPage> {
  bool _loading = true;
  String? _error;
  String _status = 'pending';
  String _type = 'all';
  List<Map<String, dynamic>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.adminListReports(
        status: _status,
        type: _type,
      );
      final raw = res['reports'];
      _rows = raw is List
          ? raw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
              .toList()
          : [];
    } catch (e) {
      if (!mounted) return;
      _error = userErrorText(
        context,
        e,
        fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
      );
      _rows = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _updateReport(Map<String, dynamic> row, String status) async {
    final id = row['id'];
    final type = (row['type'] ?? '').toString();
    if (id == null) return;
    try {
      if (type == 'listing') {
        await ApiService.adminUpdateListingReport(id as int, status: status);
      } else {
        await ApiService.adminUpdateUserReport(id as int, status: status);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('Report updated', ar: 'تم تحديث البلاغ', ku: 'ڕاپۆرت نوێکرایەوە')),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showDetail(Map<String, dynamic> row) {
    final type = (row['type'] ?? '').toString();
    final reason = (row['reason'] ?? '').toString();
    final details = (row['details'] ?? '').toString();
    final status = (row['status'] ?? '').toString();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          MediaQuery.of(ctx).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              type == 'listing'
                  ? _tr('Listing report', ar: 'بلاغ إعلان', ku: 'ڕاپۆرتی ڕیکلام')
                  : _tr('User report', ar: 'بلاغ مستخدم', ku: 'ڕاپۆرتی بەکارهێنەر'),
              style: Theme.of(ctx).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text('${_tr("Status")}: $status'),
            const SizedBox(height: 8),
            Text('${_tr("Reason")}: $reason'),
            if (details.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(details),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _updateReport(row, 'dismissed');
                    },
                    child: Text(_tr('Dismiss')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _updateReport(row, 'resolved');
                    },
                    child: Text(_tr('Resolve')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _subtitle(Map<String, dynamic> row) {
    final type = (row['type'] ?? '').toString();
    if (type == 'listing') {
      final listing = row['listing'];
      if (listing is Map) {
        final title = (listing['title'] ?? '').toString();
        final id = (listing['id'] ?? '').toString();
        return title.isNotEmpty ? title : id;
      }
    }
    final reported = row['reported_user'];
    if (reported is Map) {
      return (reported['username'] ?? reported['id'] ?? '').toString();
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Reports queue', ar: 'قائمة البلاغات', ku: 'ڕیزبەندی ڕاپۆرتەکان')),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _status,
                    decoration: InputDecoration(
                      labelText: _tr('Status'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(value: 'pending', child: Text(_tr('Pending'))),
                      DropdownMenuItem(value: 'all', child: Text(_tr('All'))),
                      DropdownMenuItem(value: 'resolved', child: Text(_tr('Resolved'))),
                      DropdownMenuItem(value: 'dismissed', child: Text(_tr('Dismissed'))),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _status = v);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _type,
                    decoration: InputDecoration(
                      labelText: _tr('Type'),
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      DropdownMenuItem(value: 'all', child: Text(_tr('All'))),
                      DropdownMenuItem(value: 'user', child: Text(_tr('User'))),
                      DropdownMenuItem(value: 'listing', child: Text(_tr('Listing'))),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _type = v);
                      _load();
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, textAlign: TextAlign.center))
                    : _rows.isEmpty
                        ? Center(child: Text(_tr('No reports')))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: _rows.length,
                              itemBuilder: (context, index) {
                                final row = _rows[index];
                                final type = (row['type'] ?? '').toString();
                                final reason = (row['reason'] ?? '').toString();
                                return Card(
                                  child: ListTile(
                                    leading: Icon(
                                      type == 'listing'
                                          ? Icons.directions_car_outlined
                                          : Icons.person_outline,
                                    ),
                                    title: Text(reason),
                                    subtitle: Text(_subtitle(row)),
                                    trailing: const Icon(Icons.chevron_right),
                                    onTap: () => _showDetail(row),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
