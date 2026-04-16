import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../shared/media/media_url.dart';

class EditDealerPage extends StatefulWidget {
  const EditDealerPage({super.key});

  @override
  State<EditDealerPage> createState() => _EditDealerPageState();
}

class _EditDealerPageState extends State<EditDealerPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _location = TextEditingController();
  XFile? _logo;
  XFile? _cover;
  bool _saving = false;
  String? _currentLogo;
  String? _currentCover;

  @override
  void initState() {
    super.initState();
    final me = context.read<AuthService>().currentUser;
    _name.text = (me?['dealership_name'] ?? '').toString();
    _phone.text = (me?['dealership_phone'] ?? '').toString();
    _location.text = (me?['dealership_location'] ?? '').toString();
    _currentLogo = (me?['profile_picture'] ?? '').toString().trim();
    _currentCover = (me?['dealership_cover_picture'] ?? '').toString().trim();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _logo = picked);
  }

  Future<void> _pickCover() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      maxHeight: 900,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _cover = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthService>();
      await auth.updateDealerProfile({
        'dealership_name': _name.text.trim(),
        'dealership_phone': _phone.text.trim(),
        'dealership_location': _location.text.trim(),
      });
      if (_logo != null) {
        await auth.uploadProfilePicture(_logo!);
      }
      if (_cover != null) {
        await auth.uploadDealerCoverPicture(_cover!);
      }
      await auth.initialize();
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoUrl = buildMediaUrl((_currentLogo ?? '').trim());
    final coverUrl = buildMediaUrl((_currentCover ?? '').trim());
    return Scaffold(
      appBar: AppBar(title: const Text('Edit dealer page')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundImage: _logo != null
                      ? null
                      : (logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null),
                  child: _logo == null && logoUrl.isEmpty
                      ? const Icon(Icons.storefront_outlined, size: 30)
                      : null,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _saving ? null : _pickLogo,
                  icon: const Icon(Icons.image_outlined),
                  label: Text(_logo == null ? 'Change logo' : 'Logo selected'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Dealership cover image (shown at top of dealer page)',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 140,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _cover != null
                    ? Image.file(
                        File(_cover!.path),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            Container(color: Colors.black12),
                      )
                    : (coverUrl.isNotEmpty
                        ? Image.network(
                            coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                Container(color: Colors.black12),
                          )
                        : Container(color: Colors.black12)),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _saving ? null : _pickCover,
                icon: const Icon(Icons.photo_outlined),
                label: Text(
                  _cover == null ? 'Choose cover image' : 'Cover selected',
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Dealership name',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Dealership name is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _phone,
              decoration: const InputDecoration(
                labelText: 'Dealership phone',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Dealership phone is required'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Dealership location',
                border: OutlineInputBorder(),
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Dealership location is required'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving...' : 'Save dealer page'),
            ),
          ],
        ),
      ),
    );
  }
}

