part of 'edit_dealer_page.dart';

mixin _EditDealerPageSave on _EditDealerPageMedia {
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final phones = _phones
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (phones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Please enter at least one phone number.', ar: 'يرجى إدخال رقم هاتف واحد على الأقل.', ku: 'تکایە لانیکەم یەک ژمارەی تەلەفۆن بنووسە.'))),
      );
      return;
    }

    // Validate hours: if a day is enabled and not 24h, require both From and To.
    for (final d in _editDealerDays) {
      final day = _openingHours[d.key];
      if (day == null) continue;
      if (!day.enabled) continue;
      if (day.is24h) continue;
      final hasOpen = day.open != null;
      final hasClose = day.close != null;
      final legacy = (day.legacyText ?? '').trim();
      if ((!hasOpen || !hasClose) && legacy.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_tr('Please select both From and To for', ar: 'يرجى اختيار وقت من وإلى ليوم', ku: 'تکایە کاتی لە و بۆ هەڵبژێرە بۆ')} ${_dayLabel(d.key)}.'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    double? lat = _pickLat;
    double? lng = _pickLng;
    if (kIsWeb) {
      lat = double.tryParse(_coordLat.text.trim());
      lng = double.tryParse(_coordLng.text.trim());
    }
    if ((lat != null) != (lng != null)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_tr('Enter both latitude and longitude, or leave both empty.', ar: 'أدخل خط العرض وخط الطول معًا، أو اتركهما فارغين.', ku: 'هەردوو لاتیتوود و لۆنگیتوود بنووسە یان هەردووکیان بەتاڵ بهێڵە.')),
        ),
      );
      return;
    }
    if (lat != null && lng != null && !isValidDealerLatLng(lat, lng)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_tr('Coordinates are out of range.', ar: 'الإحداثيات خارج النطاق.', ku: 'کۆئۆردیناتەکان لە دەورە دەرچوون.'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final auth = context.read<AuthService>();
      final openingHours = <String, String>{};
      for (final d in _editDealerDays) {
        final day = _openingHours[d.key];
        if (day == null || !day.enabled) continue;
        if (day.is24h) {
          openingHours[d.key] = '24 hours';
          continue;
        }
        if (day.open != null && day.close != null) {
          openingHours[d.key] = _formatRange(day.open!, day.close!);
          continue;
        }
        final legacy = (day.legacyText ?? '').trim();
        if (legacy.isNotEmpty) {
          openingHours[d.key] = legacy;
        }
      }
      await auth.updateDealerProfile({
        'dealership_name': _name.text.trim(),
        'dealership_phone': phones.first,
        'dealership_phones': phones,
        'dealership_location': _location.text.trim(),
        'dealership_description': _description.text.trim(),
        'dealership_opening_hours': openingHours,
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
        SnackBar(
          content: Text(
            userErrorText(
              context,
              e,
              fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
