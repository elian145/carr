import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/media/media_url.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _loading = false;
  String? _error;

  Future<void> _refresh() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Refresh the profile info from server.
      await ApiService.getProfile();
      // Keep AuthService consistent by calling initialize (loads profile + sockets).
      // This is best-effort and safe even if already initialized.
      await auth.initialize();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final auth = context.watch<AuthService>();

    final user = auth.currentUser;
    final username = (user?['username'] ?? '').toString();
    final email = (user?['email'] ?? '').toString();
    final phone = (user?['phone_number'] ?? '').toString();
    final firstName = (user?['first_name'] ?? '').toString();
    final lastName = (user?['last_name'] ?? '').toString();
    final fullName = ('$firstName $lastName').trim();
    final pic = (user?['profile_picture'] ?? '').toString();
    final picUrl = buildMediaUrl(pic);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.profileTitle ?? 'Profile'),
        actions: [
          IconButton(
            tooltip: loc?.settingsTitle ?? 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: !auth.isAuthenticated
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(loc?.loginRequired ?? 'Login required'),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () => Navigator.pushNamed(context, '/login'),
                      child: Text(loc?.loginAction ?? 'Login'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.3)),
                      ),
                      child: Text(_error!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 32,
                            backgroundColor: Colors.black12,
                            backgroundImage: picUrl.isNotEmpty
                                ? NetworkImage(picUrl)
                                : null,
                            child: picUrl.isEmpty
                                ? const Icon(Icons.person, size: 32)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  fullName.isEmpty ? username : fullName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                if (username.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text('@$username'),
                                ],
                                if (email.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(email),
                                ],
                                if (phone.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(phone),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.edit_outlined),
                          title: Text(loc?.editProfileAction ?? 'Edit profile'),
                          onTap: () async {
                            final result = await Navigator.pushNamed(
                              context,
                              '/edit-profile',
                            );
                            if (!mounted) return;
                            if (result == true) {
                              await _refresh();
                            }
                          },
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.favorite_border),
                          title: Text(loc?.favoritesTitle ?? 'Favorites'),
                          onTap: () => Navigator.pushNamed(context, '/favorites'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.list_alt_outlined),
                          title: Text(loc?.myListingsTitle ?? 'My listings'),
                          onTap: () => Navigator.pushNamed(context, '/my_listings'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _loading
                        ? null
                        : () async {
                            await AuthService().logout();
                            if (!context.mounted) return;
                            Navigator.pushReplacementNamed(context, '/login');
                          },
                    icon: const Icon(Icons.logout),
                    label: Text(loc?.logout ?? 'Logout'),
                  ),
                ],
              ),
            ),
    );
  }
}

