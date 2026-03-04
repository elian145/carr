import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';

class SellPage extends StatefulWidget {
  const SellPage({super.key});

  @override
  State<SellPage> createState() => _SellPageState();
}

class _SellPageState extends State<SellPage> {
  final _formKey = GlobalKey<FormState>();

  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _mileage = TextEditingController();
  final _price = TextEditingController();
  final _location = TextEditingController();
  final _description = TextEditingController();

  String _engineType = 'gasoline';
  String _transmission = 'automatic';
  String _driveType = 'fwd';
  String _condition = 'used';
  String _bodyType = 'sedan';
  String _currency = 'USD';

  final List<XFile> _images = <XFile>[];
  final List<XFile> _videos = <XFile>[];
  bool _submitting = false;
  String? _error;
  String? _stage;

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _mileage.dispose();
    _price.dispose();
    _location.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1920,
        maxHeight: 1920,
      );
      if (picked.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _images.addAll(picked);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _videos.add(picked);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final loc = AppLocalizations.of(context);
    setState(() {
      _error = null;
      _stage = null;
    });

    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isAuthenticated) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)?.loginRequired ?? 'Login required')),
      );
      Navigator.pushNamed(context, '/login');
      return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.pleaseFixHighlightedFields ?? 'Please fix the highlighted fields',
          ),
        ),
      );
      return;
    }

    final int year = int.tryParse(_year.text.trim()) ?? 0;
    final int mileage = int.tryParse(_mileage.text.trim()) ?? 0;
    final double price = double.tryParse(_price.text.trim()) ?? 0;

    setState(() {
      _submitting = true;
      _stage = loc?.creatingListing ?? 'Creating listing...';
    });
    try {
      final created = await ApiService.createCar({
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        'year': year,
        'mileage': mileage,
        'engine_type': _engineType,
        'transmission': _transmission,
        'drive_type': _driveType,
        'condition': _condition,
        'body_type': _bodyType,
        'price': price,
        'currency': _currency,
        'location': _location.text.trim(),
        'description': _description.text.trim().isEmpty ? null : _description.text.trim(),
      });

      final car = (created['car'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(created['car'])
          : <String, dynamic>{};
      final carId = (car['id'] ?? car['public_id'] ?? '').toString().trim();
      if (carId.isEmpty) {
        throw StateError('Car created but missing id');
      }

      if (_images.isNotEmpty) {
        setState(() => _stage = loc?.uploadingPhotos ?? 'Uploading photos...');
        await ApiService.uploadCarImages(carId, _images);
      }
      if (_videos.isNotEmpty) {
        setState(() => _stage = loc?.uploadingVideos ?? 'Uploading videos...');
        await ApiService.uploadCarVideos(carId, _videos);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc?.listingCreated ?? 'Listing created')),
      );
      Navigator.pushReplacementNamed(
        context,
        '/car_detail',
        arguments: {'carId': carId},
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _stage = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.sellTitle ?? 'Sell'),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_submitting && (_stage ?? '').isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_stage!)),
                    ],
                  ),
                ),
              ],
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.withOpacity(0.25)),
                  ),
                  child: Text(_error!),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _brand,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: loc?.brandLabel ?? 'Brand'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _model,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: loc?.modelLabel ?? 'Model'),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: loc?.yearLabel ?? 'Year'),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null) return loc?.requiredField ?? 'Required';
                        if (n < 1980 || n > DateTime.now().year + 1) {
                          return loc?.invalidField ?? 'Invalid';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _mileage,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(
                        labelText: loc?.mileageLabel ?? 'Mileage',
                      ),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        if (n == null) return loc?.requiredField ?? 'Required';
                        if (n < 0) return loc?.invalidField ?? 'Invalid';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: loc?.priceLabel ?? 'Price'),
                      validator: (v) {
                        final n = double.tryParse((v ?? '').trim());
                        if (n == null) return loc?.requiredField ?? 'Required';
                        if (n <= 0) return loc?.invalidField ?? 'Invalid';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _currency,
                      decoration: InputDecoration(
                        labelText: loc?.currencyLabel ?? 'Currency',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'IQD', child: Text('IQD')),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _currency = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _location,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: loc?.locationLabel ?? 'Location',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? (loc?.requiredField ?? 'Required') : null,
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _engineType,
                decoration: InputDecoration(
                  labelText: loc?.engineTypeLabel ?? 'Engine type',
                ),
                items: const [
                  DropdownMenuItem(value: 'gasoline', child: Text('Gasoline')),
                  DropdownMenuItem(value: 'diesel', child: Text('Diesel')),
                  DropdownMenuItem(value: 'hybrid', child: Text('Hybrid')),
                  DropdownMenuItem(value: 'electric', child: Text('Electric')),
                ],
                onChanged: (v) => setState(() => _engineType = v ?? _engineType),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _transmission,
                decoration: const InputDecoration(labelText: 'Transmission'),
                items: const [
                  DropdownMenuItem(value: 'automatic', child: Text('Automatic')),
                  DropdownMenuItem(value: 'manual', child: Text('Manual')),
                  DropdownMenuItem(value: 'cvt', child: Text('CVT')),
                ],
                onChanged: (v) => setState(() => _transmission = v ?? _transmission),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _driveType,
                decoration: const InputDecoration(labelText: 'Drive type'),
                items: const [
                  DropdownMenuItem(value: 'fwd', child: Text('FWD')),
                  DropdownMenuItem(value: 'rwd', child: Text('RWD')),
                  DropdownMenuItem(value: 'awd', child: Text('AWD')),
                  DropdownMenuItem(value: '4wd', child: Text('4WD')),
                ],
                onChanged: (v) => setState(() => _driveType = v ?? _driveType),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _condition,
                decoration: const InputDecoration(labelText: 'Condition'),
                items: const [
                  DropdownMenuItem(value: 'new', child: Text('New')),
                  DropdownMenuItem(value: 'used', child: Text('Used')),
                  DropdownMenuItem(value: 'certified', child: Text('Certified')),
                ],
                onChanged: (v) => setState(() => _condition = v ?? _condition),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _bodyType,
                decoration: const InputDecoration(labelText: 'Body type'),
                items: const [
                  DropdownMenuItem(value: 'sedan', child: Text('Sedan')),
                  DropdownMenuItem(value: 'suv', child: Text('SUV')),
                  DropdownMenuItem(value: 'hatchback', child: Text('Hatchback')),
                  DropdownMenuItem(value: 'coupe', child: Text('Coupe')),
                  DropdownMenuItem(value: 'pickup', child: Text('Pickup')),
                  DropdownMenuItem(value: 'van', child: Text('Van')),
                ],
                onChanged: (v) => setState(() => _bodyType = v ?? _bodyType),
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _description,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(
                  labelText: loc?.descriptionOptionalLabel ?? 'Description (optional)',
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickImages,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(
                        loc?.addPhotosCount(_images.length) ??
                            'Add photos (${_images.length})',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _submitting ? null : _pickVideo,
                      icon: const Icon(Icons.videocam_outlined),
                      label: Text(
                        loc?.addVideoCount(_videos.length) ??
                            'Add video (${_videos.length})',
                      ),
                    ),
                  ),
                ],
              ),
              if (_images.isNotEmpty) ...[
                const SizedBox(height: 10),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _images.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final img = _images[index];
                      return Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.file(
                              File(img.path),
                              width: 92,
                              height: 92,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) =>
                                  Container(
                                width: 92,
                                height: 92,
                                color: Colors.black12,
                                child: const Icon(Icons.image_not_supported),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 2,
                            child: InkWell(
                              onTap: _submitting
                                  ? null
                                  : () {
                                      setState(() => _images.removeAt(index));
                                    },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: Text(
                  _submitting
                      ? (loc?.creatingListing ?? 'Creating listing...')
                      : (loc?.createListingButton ?? 'Create listing'),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                loc?.plateBlurNote ?? 'Note: Plate blurring is enabled by default for privacy.',
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

