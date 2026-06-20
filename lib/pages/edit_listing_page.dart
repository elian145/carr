import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/listings/listing_identity.dart';
import '../shared/listings/listing_management.dart';

class EditListingPage extends StatefulWidget {
  final Map<String, dynamic> car;

  const EditListingPage({super.key, required this.car});

  @override
  State<EditListingPage> createState() => _EditListingPageState();
}

class _EditListingPageState extends State<EditListingPage> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _brand;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _mileage;
  late final TextEditingController _price;
  late final TextEditingController _location;
  late final TextEditingController _description;
  late final TextEditingController _color;
  late final TextEditingController _vin;

  late String _condition;
  bool _saving = false;

  String _text(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  @override
  void initState() {
    super.initState();
    final car = widget.car;
    _brand = TextEditingController(text: (car['brand'] ?? '').toString());
    _model = TextEditingController(text: (car['model'] ?? '').toString());
    _year = TextEditingController(text: (car['year'] ?? '').toString());
    _mileage = TextEditingController(text: (car['mileage'] ?? '').toString());
    _price = TextEditingController(text: (car['price'] ?? '').toString());
    _location = TextEditingController(text: (car['location'] ?? '').toString());
    _description =
        TextEditingController(text: (car['description'] ?? '').toString());
    _color = TextEditingController(text: (car['color'] ?? '').toString());
    _vin = TextEditingController(text: (car['vin'] ?? '').toString());
    final cond = (car['condition'] ?? 'used').toString().trim().toLowerCase();
    _condition = cond == 'new' ? 'new' : 'used';
  }

  @override
  void dispose() {
    _brand.dispose();
    _model.dispose();
    _year.dispose();
    _mileage.dispose();
    _price.dispose();
    _location.dispose();
    _description.dispose();
    _color.dispose();
    _vin.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final carId = listingPrimaryId(widget.car);
    if (carId.isEmpty) return;

    final year = int.tryParse(_year.text.trim());
    final mileage = int.tryParse(_mileage.text.trim());
    final price = double.tryParse(_price.text.trim());

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'brand': _brand.text.trim(),
        'model': _model.text.trim(),
        if (year != null) 'year': year,
        if (mileage != null) 'mileage': mileage,
        if (price != null) 'price': price,
        'location': _location.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'color': _color.text.trim().isEmpty ? null : _color.text.trim(),
        'condition': _condition,
        if (_vin.text.trim().isNotEmpty) 'vin': _vin.text.trim(),
      };

      final res = await ApiService.updateCar(carId, payload);
      final updated = (res['car'] is Map)
          ? Map<String, dynamic>.from(
              (res['car'] as Map).cast<String, dynamic>(),
            )
          : {...widget.car, ...payload};

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _text(
              'Listing updated',
              ar: 'تم تحديث الإعلان',
              ku: 'ڕێکلام نوێکرایەوە',
            ),
          ),
        ),
      );
      Navigator.pop(context, updated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback:
                  AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final title = listingTitleLabel(widget.car);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title.isEmpty
              ? (loc?.editListingTitle ?? 'Edit listing')
              : title,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            TextFormField(
              controller: _brand,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: loc?.brandLabel ?? 'Brand',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? _text('Brand is required', ar: 'الماركة مطلوبة', ku: 'براند پێویستە')
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _model,
              textCapitalization: TextCapitalization.words,
              decoration: InputDecoration(
                labelText: loc?.modelLabel ?? 'Model',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? _text('Model is required', ar: 'الموديل مطلوب', ku: 'مۆدێل پێویستە')
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: loc?.yearLabel ?? 'Year',
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 1900) {
                        return _text(
                          'Enter a valid year',
                          ar: 'أدخل سنة صالحة',
                          ku: 'ساڵێکی دروست بنووسە',
                        );
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _mileage,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: loc?.mileageLabel ?? 'Mileage',
                    ),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      if (n == null || n < 0) {
                        return _text(
                          'Enter mileage',
                          ar: 'أدخل المسافة المقطوعة',
                          ku: 'میلەج بنووسە',
                        );
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: loc?.priceLabel ?? 'Price',
              ),
              validator: (v) {
                final n = double.tryParse((v ?? '').trim());
                if (n == null || n <= 0) {
                  return _text(
                    'Enter a valid price',
                    ar: 'أدخل سعرًا صالحًا',
                    ku: 'نرخێکی دروست بنووسە',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _location,
              decoration: InputDecoration(
                labelText: loc?.locationLabel ?? 'Location',
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? _text(
                      'Location is required',
                      ar: 'الموقع مطلوب',
                      ku: 'شوێن پێویستە',
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _color,
              decoration: InputDecoration(
                labelText: loc?.colorLabel ?? 'Color',
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _vin,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: _text(
                  'VIN (optional)',
                  ar: 'رقم الهيكل (اختياري)',
                  ku: 'ژمارەی شاسی (ئارەزوومەندانە)',
                ),
                hintText: 'e.g. 1HGBH41JXMN109186',
              ),
              validator: (v) {
                final trimmed = (v ?? '').trim();
                if (trimmed.isEmpty) return null;
                if (trimmed.length != 17) {
                  return _text(
                    'VIN must be 17 characters',
                    ar: 'رقم الهيكل يجب أن يكون 17 حرفاً',
                    ku: 'ژمارەی شاسی دەبێت ١٧ پیت بێت',
                  );
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _condition,
              decoration: InputDecoration(
                labelText: loc?.conditionLabel ?? 'Condition',
              ),
              items: [
                DropdownMenuItem(
                  value: 'used',
                  child: Text(_text('Used', ar: 'مستعمل', ku: 'بەکارهاتوو')),
                ),
                DropdownMenuItem(
                  value: 'new',
                  child: Text(_text('New', ar: 'جديد', ku: 'نوێ')),
                ),
              ],
              onChanged: _saving
                  ? null
                  : (v) {
                      if (v == null) return;
                      setState(() => _condition = v);
                    },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              minLines: 3,
              maxLines: 8,
              decoration: InputDecoration(
                labelText: loc?.descriptionTitle ?? 'Description',
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(loc?.saveChangesButton ?? 'Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}
