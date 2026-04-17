import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/media/media_url.dart';
import 'dealer_location_picker_page.dart';

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
  final _description = TextEditingController();
  final _coordLat = TextEditingController();
  final _coordLng = TextEditingController();
  XFile? _logo;
  XFile? _cover;
  bool _saving = false;
  String? _currentLogo;
  String? _currentCover;
  double? _pickLat;
  double? _pickLng;

  @override
  void initState() {
    super.initState();
    final me = context.read<AuthService>().currentUser;
    _name.text = (me?['dealership_name'] ?? '').toString();
    _phone.text = (me?['dealership_phone'] ?? '').toString();
    _location.text = (me?['dealership_location'] ?? '').toString();
    _description.text = (me?['dealership_description'] ?? '').toString();
    _currentLogo = (me?['profile_picture'] ?? '').toString().trim();
    _currentCover = (me?['dealership_cover_picture'] ?? '').toString().trim();
    final lat0 = parseDealerCoord(me?['dealership_latitude']);
    final lng0 = parseDealerCoord(me?['dealership_longitude']);
    _pickLat = lat0;
    _pickLng = lng0;
    _coordLat.text = lat0 != null ? lat0.toString() : '';
    _coordLng.text = lng0 != null ? lng0.toString() : '';
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _location.dispose();
    _description.dispose();
    _coordLat.dispose();
    _coordLng.dispose();
    super.dispose();
  }

  Future<void> _openMapPicker() async {
    if (kIsWeb) return;
    final res = await Navigator.push<Map<String, double>>(
      context,
      MaterialPageRoute(
        builder: (_) => DealerLocationPickerPage(
          initialLatitude: _pickLat,
          initialLongitude: _pickLng,
        ),
      ),
    );
    if (!mounted || res == null) return;
    final lat = res['lat'];
    final lng = res['lng'];
    if (lat == null || lng == null) return;
    setState(() {
      _pickLat = lat;
      _pickLng = lng;
      _coordLat.text = lat.toString();
      _coordLng.text = lng.toString();
    });
  }

  void _clearMapPin() {
    setState(() {
      _pickLat = null;
      _pickLng = null;
      _coordLat.clear();
      _coordLng.clear();
    });
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

    double? lat = _pickLat;
    double? lng = _pickLng;
    if (kIsWeb) {
      lat = double.tryParse(_coordLat.text.trim());
      lng = double.tryParse(_coordLng.text.trim());
    }
    if ((lat != null) != (lng != null)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter both latitude and longitude, or leave both empty.'),
        ),
      );
      return;
    }
    if (lat != null && lng != null && !isValidDealerLatLng(lat, lng)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Coordinates are out of range.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthService>();
      await auth.updateDealerProfile({
        'dealership_name': _name.text.trim(),
        'dealership_phone': _phone.text.trim(),
        'dealership_location': _location.text.trim(),
        'dealership_description': _description.text.trim(),
        'dealership_latitude': lat,
        'dealership_longitude': lng,
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
            const SizedBox(height: 12),
            Text(
              'Exact location on map',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              kIsWeb
                  ? 'Optional: paste latitude and longitude from Google Maps (Share → coordinates).'
                  : 'Optional: drop a pin so buyers can open this spot in Google Maps.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (!kIsWeb) ...[
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving ? null : _openMapPicker,
                      icon: const Icon(Icons.map_outlined),
                      label: Text(
                        _pickLat != null ? 'Update map pin' : 'Set map pin',
                      ),
                    ),
                  ),
                  if (_pickLat != null && _pickLng != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _saving ? null : _clearMapPin,
                      child: const Text('Clear'),
                    ),
                  ],
                ],
              ),
              if (_pickLat != null && _pickLng != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '${_pickLat!.toStringAsFixed(6)}, ${_pickLng!.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _coordLat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Latitude',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _coordLng,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Longitude',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: 'Dealership description',
                hintText: 'Tell buyers about your dealership',
                border: OutlineInputBorder(),
              ),
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

