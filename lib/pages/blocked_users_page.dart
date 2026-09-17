import 'package:flutter/material.dart';

import '../app/widgets/listing_network_image.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/media/media_url.dart';
import '../shared/ui/empty_state_panel.dart';
import '../theme/app_colors.dart';

/// MI-01: lets the current user view and manage the accounts they've
/// blocked.
///
/// Reuses the existing `GET /api/users/blocked` endpoint's additive
/// `blocked_user_details` field (via [ApiService.getBlockedUserDetails]) and
/// the existing [ApiService.unblockUser] — no new backend endpoint.
class BlockedUsersPage extends StatefulWidget {
  const BlockedUsersPage({super.key});

  @override
  State<BlockedUsersPage> createState() => _BlockedUsersPageState();
}

class _BlockedUsersPageState extends State<BlockedUsersPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];

  /// Ids currently mid-unblock, to disable that row's button and prevent a
  /// duplicate tap from firing a second request while one is in flight.
  final Set<String> _unblockingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final users = await ApiService.getBlockedUserDetails();
      if (!mounted) return;
      setState(() {
        _users = users;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)?.blockedUsersLoadError,
        );
      });
    }
  }

  Future<void> _confirmUnblock(Map<String, dynamic> user) async {
    final id = (user['id'] ?? '').toString();
    if (id.isEmpty || _unblockingIds.contains(id)) return;

    final loc = AppLocalizations.of(context)!;
    final name = (user['name'] ?? '').toString().trim();
    final displayName = name.isEmpty ? id : name;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.unblockUserTitle),
        content: Text(loc.unblockUserConfirmation(displayName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.cancelAction),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.unblockAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _unblockingIds.add(id));
    try {
      await ApiService.unblockUser(id);
      if (!mounted) return;
      setState(() {
        // Only remove locally after the API call actually succeeded.
        _users = _users.where((u) => (u['id'] ?? '').toString() != id).toList();
        _unblockingIds.remove(id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.userUnblocked)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _unblockingIds.remove(id));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(context, e, fallback: loc.failedToUnblockUser),
          ),
        ),
      );
    }
  }

  Widget _buildAvatar(Map<String, dynamic> user) {
    final raw = (user['profile_picture'] ?? '').toString().trim();
    final url = raw.isEmpty ? '' : buildLegacyFullImageUrl(raw);
    return CircleAvatar(
      radius: 22,
      backgroundColor: const Color(0x26FF6B00),
      backgroundImage: url.isEmpty
          ? null
          : listingCachedNetworkImageProvider(url),
      child: url.isEmpty
          ? const Icon(Icons.person, color: AppColors.brandOrange, size: 24)
          : null,
    );
  }

  Widget _buildBody(AppLocalizations loc) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: Text(loc.retryAction)),
            ],
          ),
        ),
      );
    }
    if (_users.isEmpty) {
      return EmptyStatePanel(icon: Icons.block, title: loc.noBlockedUsers);
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: _users.length,
        separatorBuilder: (_, _) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final user = _users[index];
          final id = (user['id'] ?? '').toString();
          final name = (user['name'] ?? '').toString().trim();
          final busy = _unblockingIds.contains(id);
          return ListTile(
            leading: _buildAvatar(user),
            title: Text(
              name.isEmpty ? id : name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              onPressed: busy ? null : () => _confirmUnblock(user),
              child: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(loc.unblockAction),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.blockedUsersTitle)),
      body: _buildBody(loc),
    );
  }
}
