import 'package:flutter/material.dart';

import '../services/api_service.dart';

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
      _error = e is ApiException ? e.message : e.toString();
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
        const SnackBar(content: Text('Dealer approved'), backgroundColor: Colors.green),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : e.toString()),
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
        title: const Text('Reject dealer application?'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Reason (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ApiService.adminRejectDealer(publicId, reason: controller.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Application rejected')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e is ApiException ? e.message : e.toString()),
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
        title: const Text('Dealer approvals'),
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
                      const Text(
                        'You must be logged in as an admin (is_admin on the server). '
                        'If you see 403, set is_admin=true for your user in the database.',
                      ),
                    ],
                  )
                : _rows.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(24),
                        children: const [
                          Text('No pending dealer applications.'),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(12),
                        itemCount: _rows.length,
                        separatorBuilder: (context, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final u = _rows[i];
                          final id = (u['id'] ?? '').toString();
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
                                  if (dn.isNotEmpty) Text('Dealership: $dn'),
                                  if (dp.isNotEmpty) Text('Phone: $dp'),
                                  if (loc.isNotEmpty) Text('Location: $loc'),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      FilledButton(
                                        onPressed: id.isEmpty ? null : () => _approve(id),
                                        child: const Text('Approve'),
                                      ),
                                      const SizedBox(width: 8),
                                      OutlinedButton(
                                        onPressed: id.isEmpty ? null : () => _reject(id),
                                        child: const Text('Reject'),
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
