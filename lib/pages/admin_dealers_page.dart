import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';

/// Admin-only: review and approve or reject pending dealer signups.
///
/// Requires a JWT for a user with `is_admin: true` on the backend.
class AdminDealersPage extends StatefulWidget {
  const AdminDealersPage({super.key});

  @override
  State<AdminDealersPage> createState() => _AdminDealersPageState();
}

class _AdminDealersPageState extends State<AdminDealersPage> {
  bool _loading = true;
  String? _error;
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
      final res = await ApiService.adminDealersPending();
      final raw = res['dealers'];
      final list = raw is List ? raw : const <dynamic>[];
      _rows = list
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m.cast<String, dynamic>()))
          .toList();
    } catch (e) {
      _error = userErrorText(
        context,
        e,
        fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
      );
      _rows = [];
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _approve(String publicId) async {
    try {
      await ApiService.adminApproveDealer(publicId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Dealer approved', ar: 'تمت الموافقة على الوكيل', ku: 'وەکیل پەسەند کرا')), backgroundColor: Colors.green),
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

  Future<void> _reject(String publicId) async {
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_tr('Reject dealer application?', ar: 'رفض طلب الوكيل؟', ku: 'داواکاری وەکیل ڕەتبکرێتەوە؟')),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: _tr('Reason (optional)', ar: 'السبب (اختياري)', ku: 'هۆکار (ئارەزوومەندانە)'),
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)?.cancelAction ?? 'Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_tr('Reject', ar: 'رفض', ku: 'ڕەتکردنەوە'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.adminRejectDealer(publicId, reason: controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Application rejected', ar: 'تم رفض الطلب', ku: 'داواکارییەکە ڕەتکرایەوە'))),
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
    } finally {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('Dealer approvals', ar: 'موافقات الوكلاء', ku: 'پەسەندکردنی وەکیلەکان')),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(24),
                    children: [
                      Text(_error!, style: const TextStyle(color: Colors.red)),
                      const SizedBox(height: 16),
                      Text(
                        _tr(
                          'You must be logged in as an admin (is_admin on the server). If you see 403, set is_admin=true for your user in the database.',
                          ar: 'يجب تسجيل الدخول كمدير (is_admin على الخادم). إذا ظهر 403 فقم بتعيين is_admin=true للمستخدم في قاعدة البيانات.',
                          ku: 'پێویستە وەک بەڕێوەبەر بچیتە ژوورەوە (is_admin لە سێرڤەر). ئەگەر 403 ببینیت، is_admin=true بۆ بەکارهێنەرەکەت لە داتابەیس دابنێ.',
                        ),
                      ),
                    ],
                  )
                : _rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: [
                          Text(_tr('No pending dealer applications.', ar: 'لا توجد طلبات وكلاء معلقة.', ku: 'هیچ داواکاری وەکیلی چاوەڕوان نییە.')),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (context, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final u = _rows[i];
                          final id = (u['public_id'] ?? u['id'] ?? '')
                              .toString()
                              .trim();
                          final username = (u['username'] ?? '').toString();
                          final name = '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
                          final dn = (u['dealership_name'] ?? '').toString();
                          final dp = (u['dealership_phone'] ?? '').toString();
                          final loc = (u['dealership_location'] ?? '').toString();
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    username.isNotEmpty ? '@$username' : id,
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                  if (name.isNotEmpty) Text(name),
                                  if (dn.isNotEmpty) Text('${_tr('Dealership', ar: 'المعرض', ku: 'نمایشگا')}: $dn'),
                                  if (dp.isNotEmpty) Text('${_tr('Phone', ar: 'الهاتف', ku: 'تەلەفۆن')}: $dp'),
                                  if (loc.isNotEmpty) Text('${_tr('Location', ar: 'الموقع', ku: 'شوێن')}: $loc'),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      FilledButton(
                                        onPressed: id.isEmpty ? null : () => _approve(id),
                                        child: Text(_tr('Approve', ar: 'موافقة', ku: 'پەسەندکردن')),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: id.isEmpty ? null : () => _reject(id),
                                        child: Text(_tr('Reject', ar: 'رفض', ku: 'ڕەتکردنەوە')),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
