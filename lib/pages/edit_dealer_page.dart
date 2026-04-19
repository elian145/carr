import 'dart:io';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../services/auth_service.dart';
import '../shared/maps/dealer_map_coords.dart';
import '../shared/maps/open_google_maps.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../widgets/dealer_location_map_preview.dart';
import 'dealer_location_picker_page.dart';

class EditDealerPage extends StatefulWidget {
  const EditDealerPage({super.key});

  @override
  State<EditDealerPage> createState() => _EditDealerPageState();
}

class _DayHours {
  bool enabled;
  bool is24h;
  TimeOfDay? open;
  TimeOfDay? close;
  String? legacyText;

  _DayHours({
    required this.enabled,
    required this.is24h,
    this.open,
    this.close,
    this.legacyText,
  });
}

class _EditDealerPageState extends State<EditDealerPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final List<TextEditingController> _phones = [];
  final _location = TextEditingController();
  final _description = TextEditingController();
  final _coordLat = TextEditingController();
  final _coordLng = TextEditingController();
  final GlobalKey _mapPreviewKey = GlobalKey();
  XFile? _logo;
  XFile? _cover;
  bool _saving = false;
  String? _currentLogo;
  String? _currentCover;
  double? _pickLat;
  double? _pickLng;
  late final Map<String, _DayHours> _openingHours;
  late final Map<String, ExpansionTileController> _openingHoursTileControllers;
  late final Map<String, GlobalKey> _openingHoursTileKeys;
  static const int _maxPhones = 5;

  static const List<({String key, String label})> _days = [
    (key: 'sun', label: 'Sunday'),
    (key: 'mon', label: 'Monday'),
    (key: 'tue', label: 'Tuesday'),
    (key: 'wed', label: 'Wednesday'),
    (key: 'thu', label: 'Thursday'),
    (key: 'fri', label: 'Friday'),
    (key: 'sat', label: 'Saturday'),
  ];

  RoundedRectangleBorder _pageCardShape(Brightness brightness) {
    final isLightShell = brightness == Brightness.light;
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: isLightShell
          ? BorderSide(
              color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.45),
            )
          : BorderSide.none,
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }

  String _daySummaryText(String dayKey) {
    final day = _openingHours[dayKey]!;
    if (!day.enabled) return 'Closed';
    if (day.is24h) return '24 hours';
    if (day.open != null && day.close != null) {
      return _formatRange(day.open!, day.close!);
    }
    final legacy = (day.legacyText ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    if (day.open != null && day.close == null) {
      return 'From ${_formatTime(day.open!)}';
    }
    if (day.open == null && day.close != null) {
      return 'To ${_formatTime(day.close!)}';
    }
    return 'Select time';
  }

  void _openOpeningHoursDayEditor(String dayKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingHoursTileControllers[dayKey]?.expand();
      final ctx = _openingHoursTileKeys[dayKey]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      }
    });
  }

  _DayHours _parseDayHours(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return _DayHours(enabled: false, is24h: false);
    }
    final lower = s.toLowerCase();
    if (lower.contains('24') && lower.contains('hour')) {
      return _DayHours(enabled: true, is24h: true);
    }
    if (lower == 'closed' || lower == 'close') {
      return _DayHours(enabled: false, is24h: false);
    }

    TimeOfDay? parseOne(String t) {
      final m = RegExp(
        r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$',
        caseSensitive: false,
      ).firstMatch(t);
      if (m == null) return null;
      var h = int.tryParse(m.group(1) ?? '');
      final min = int.tryParse(m.group(2) ?? '0') ?? 0;
      final ap = (m.group(3) ?? '').toLowerCase();
      if (h == null) return null;
      if (min < 0 || min > 59) return null;
      if (ap.isNotEmpty) {
        if (h < 1 || h > 12) return null;
        if (ap == 'am') {
          h = h == 12 ? 0 : h;
        } else if (ap == 'pm') {
          h = h == 12 ? 12 : h + 12;
        }
      } else {
        if (h < 0 || h > 23) return null;
      }
      return TimeOfDay(hour: h, minute: min);
    }

    // Try to parse "start - end"
    final parts = s.split(RegExp(r'\s*-\s*'));
    if (parts.length >= 2) {
      final a = parseOne(parts[0]);
      final b = parseOne(parts[1]);
      if (a != null && b != null) {
        return _DayHours(enabled: true, is24h: false, open: a, close: b);
      }
    }

    // Fall back to legacy string (still saved as-is unless user edits).
    return _DayHours(enabled: true, is24h: false, legacyText: s);
  }

  String _formatTime(TimeOfDay t) => t.format(context);

  String _formatRange(TimeOfDay open, TimeOfDay close) =>
      '${_formatTime(open)} - ${_formatTime(close)}';

  List<TimeOfDay> _timeOptions() {
    final out = <TimeOfDay>[];
    for (var h = 0; h < 24; h++) {
      out.add(TimeOfDay(hour: h, minute: 0));
      out.add(TimeOfDay(hour: h, minute: 30));
    }
    return out;
  }

  Future<TimeOfDay?> _pickTimeWheel({
    required String title,
    TimeOfDay? initial,
  }) async {
    final options = _timeOptions();
    int indexOf(TimeOfDay t) {
      final i = options.indexWhere((x) => x.hour == t.hour && x.minute == t.minute);
      return i >= 0 ? i : 0;
    }

    final initialIdx = initial != null ? indexOf(initial) : 0;
    int selectedIndex = initialIdx;

    return await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      builder: (ctx) {
        final controller = FixedExtentScrollController(initialItem: initialIdx);
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(ctx)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, options[selectedIndex]),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) => selectedIndex = i,
                    children: [
                      for (final t in options)
                        Center(
                          child: Text(
                            t.format(ctx),
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _openingHours = {
      for (final d in _days) d.key: _DayHours(enabled: false, is24h: false),
    };
    _openingHoursTileControllers = {
      for (final d in _days) d.key: ExpansionTileController(),
    };
    _openingHoursTileKeys = {
      for (final d in _days) d.key: GlobalKey(),
    };
    final me = context.read<AuthService>().currentUser;
    _name.text = (me?['dealership_name'] ?? '').toString();
    final initialPhones = <String>[];
    final rawPhones = me?['dealership_phones'];
    if (rawPhones is List) {
      for (final x in rawPhones) {
        final s = (x ?? '').toString().trim();
        if (s.isNotEmpty) initialPhones.add(s);
      }
    }
    final legacySingle = (me?['dealership_phone'] ?? '').toString().trim();
    if (initialPhones.isEmpty && legacySingle.isNotEmpty) {
      initialPhones.add(legacySingle);
    }
    if (initialPhones.isEmpty) initialPhones.add('');
    _phones
      ..clear()
      ..addAll(initialPhones.map((p) => TextEditingController(text: p)));
    _location.text = (me?['dealership_location'] ?? '').toString();
    _description.text = (me?['dealership_description'] ?? '').toString();
    final rawHours = me?['dealership_opening_hours'];
    Map<String, dynamic>? hoursMap;
    if (rawHours is Map) {
      hoursMap = Map<String, dynamic>.from(rawHours.cast<String, dynamic>());
    } else if (rawHours is String) {
      try {
        final decoded = jsonDecode(rawHours);
        if (decoded is Map) {
          hoursMap = Map<String, dynamic>.from(decoded.cast<String, dynamic>());
        }
      } catch (_) {}
    }
    if (hoursMap != null) {
      for (final d in _days) {
        final v = (hoursMap[d.key] ?? '').toString();
        if (v.trim().isEmpty) continue;
        _openingHours[d.key] = _parseDayHours(v);
      }
    }
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
    for (final c in _phones) {
      c.dispose();
    }
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _mapPreviewKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      }
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

  ({double lat, double lng})? _effectivePinForPreview() {
    if (kIsWeb) {
      final lat = double.tryParse(_coordLat.text.trim());
      final lng = double.tryParse(_coordLng.text.trim());
      if (lat == null || lng == null) return null;
      if (!isValidDealerLatLng(lat, lng)) return null;
      return (lat: lat, lng: lng);
    }
    final lat = _pickLat;
    final lng = _pickLng;
    if (lat == null || lng == null) return null;
    if (!isValidDealerLatLng(lat, lng)) return null;
    return (lat: lat, lng: lng);
  }

  Future<void> _openPinInGoogleMaps(double lat, double lng) async {
    final ok = await openGoogleMapsAt(lat, lng).catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps')),
      );
    }
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

    final phones = _phones
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (phones.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one phone number.')),
      );
      return;
    }

    // Validate hours: if a day is enabled and not 24h, require both From and To.
    for (final d in _days) {
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
            content: Text('Please select both From and To for ${d.label}.'),
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
      final openingHours = <String, String>{};
      for (final d in _days) {
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
    final brightness = Theme.of(context).brightness;
    final cardShape = _pageCardShape(brightness);
    final isLightShell = brightness == Brightness.light;

    return Scaffold(
      appBar: AppBar(title: const Text('Edit dealer page')),
      backgroundColor: isLightShell ? AppThemes.lightAppBackground : null,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save changes'),
          ),
        ),
      ),
      body: Stack(
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                Card(
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.photo_outlined,
                          title: 'Branding',
                          subtitle: 'Logo and cover image shown on your dealer page.',
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          height: 150,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
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
                                        errorBuilder:
                                            (context, error, stackTrace) =>
                                                Container(color: Colors.black12),
                                      )
                                    : Container(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .surfaceContainerHighest
                                            .withValues(alpha: 0.55),
                                        child: Center(
                                          child: Icon(
                                            Icons.image_outlined,
                                            color: Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                      )),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              backgroundImage: _logo != null
                                  ? null
                                  : (logoUrl.isNotEmpty ? NetworkImage(logoUrl) : null),
                              child: _logo == null && logoUrl.isEmpty
                                  ? const Icon(Icons.storefront_outlined)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _saving ? null : _pickLogo,
                                      icon: const Icon(Icons.image_outlined),
                                      label: Text(
                                        _logo == null ? 'Change logo' : 'Logo selected',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: _saving ? null : _pickCover,
                                      icon: const Icon(Icons.photo_outlined),
                                      label: Text(
                                        _cover == null
                                            ? 'Change cover'
                                            : 'Cover selected',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.storefront_outlined,
                          title: 'Dealership details',
                          subtitle: 'What buyers see on your dealer page.',
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(
                            labelText: 'Dealership name',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Dealership name is required'
                              : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _location,
                          decoration: const InputDecoration(
                            labelText: 'Dealership location',
                            prefixIcon: Icon(Icons.location_on_outlined),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Dealership location is required'
                              : null,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _description,
                          minLines: 3,
                          maxLines: 6,
                          maxLength: 1000,
                          decoration: const InputDecoration(
                            labelText: 'Description',
                            hintText: 'Tell buyers about your dealership',
                            prefixIcon: Icon(Icons.notes_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.phone_outlined,
                          title: 'Contact numbers',
                          subtitle: 'Add up to $_maxPhones phone numbers.',
                          trailing: OutlinedButton.icon(
                            onPressed: (_saving || _phones.length >= _maxPhones)
                                ? null
                                : () => setState(
                                      () => _phones.add(TextEditingController()),
                                    ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add'),
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (var i = 0; i < _phones.length; i++) ...[
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _phones[i],
                                  keyboardType: TextInputType.phone,
                                  decoration: InputDecoration(
                                    labelText: i == 0
                                        ? 'Primary phone'
                                        : 'Phone ${i + 1}',
                                    prefixIcon: const Icon(Icons.phone_outlined),
                                  ),
                                  validator: i == 0
                                      ? (v) => (v == null || v.trim().isEmpty)
                                          ? 'At least one phone is required'
                                          : null
                                      : null,
                                ),
                              ),
                              if (i > 0) ...[
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: IconButton(
                                    tooltip: 'Remove',
                                    onPressed: _saving
                                        ? null
                                        : () {
                                            final c = _phones.removeAt(i);
                                            c.dispose();
                                            setState(() {});
                                          },
                                    icon: const Icon(Icons.close),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (i != _phones.length - 1) const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: _sectionTitle(
                          icon: Icons.schedule_outlined,
                          title: 'Opening hours',
                          subtitle: 'Start week is Sunday. Tap a day to edit.',
                        ),
                      ),
                      const Divider(height: 1),
                      for (var i = 0; i < _days.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        Builder(
                          builder: (context) {
                            final d = _days[i];
                            final day = _openingHours[d.key]!;
                            return Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                key: _openingHoursTileKeys[d.key],
                                controller: _openingHoursTileControllers[d.key],
                                tilePadding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                childrenPadding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                title: Text(
                                  d.label,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                subtitle: Text(_daySummaryText(d.key)),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Switch(
                                      value: day.enabled,
                                      onChanged: _saving
                                          ? null
                                          : (v) {
                                              setState(() {
                                                day.enabled = v;
                                                if (!v) {
                                                  day.is24h = false;
                                                  day.open = null;
                                                  day.close = null;
                                                  day.legacyText = null;
                                                  _openingHoursTileControllers[d.key]
                                                      ?.collapse();
                                                }
                                              });
                                              if (v) {
                                                _openOpeningHoursDayEditor(d.key);
                                              }
                                            },
                                    ),
                                    const SizedBox(width: 4),
                                    PopupMenuButton<String>(
                                      enabled: !_saving,
                                      onSelected: (value) {
                                        if (value == '24h') {
                                          setState(() {
                                            day.enabled = true;
                                            day.is24h = true;
                                            day.open = null;
                                            day.close = null;
                                            day.legacyText = null;
                                          });
                                        } else if (value == 'clear') {
                                          setState(() {
                                            day.enabled = false;
                                            day.is24h = false;
                                            day.open = null;
                                            day.close = null;
                                            day.legacyText = null;
                                          });
                                        }
                                      },
                                      itemBuilder: (context) => const [
                                        PopupMenuItem(
                                          value: '24h',
                                          child: Text('Set 24 hours'),
                                        ),
                                        PopupMenuItem(
                                          value: 'clear',
                                          child: Text('Set closed'),
                                        ),
                                      ],
                                      child: const Padding(
                                        padding:
                                            EdgeInsets.symmetric(horizontal: 2),
                                        child: Icon(Icons.more_vert),
                                      ),
                                    ),
                                  ],
                                ),
                                children: [
                                  if (!day.enabled)
                                    Text(
                                      'This day is set to closed.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    )
                                  else if (day.is24h)
                                    Text(
                                      'Open 24 hours.',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    )
                                  else
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () async {
                                                    setState(() {
                                                      day.is24h = false;
                                                      day.legacyText = null;
                                                    });
                                                    final picked =
                                                        await _pickTimeWheel(
                                                      title:
                                                          '${d.label} opens at',
                                                      initial: day.open ??
                                                          const TimeOfDay(
                                                            hour: 9,
                                                            minute: 0,
                                                          ),
                                                    );
                                                    if (!mounted ||
                                                        picked == null) {
                                                      return;
                                                    }
                                                    setState(
                                                      () => day.open = picked,
                                                    );
                                                  },
                                            child: Text(
                                              day.open == null
                                                  ? 'From'
                                                  : _formatTime(day.open!),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: _saving
                                                ? null
                                                : () async {
                                                    setState(() {
                                                      day.is24h = false;
                                                      day.legacyText = null;
                                                    });
                                                    final picked =
                                                        await _pickTimeWheel(
                                                      title:
                                                          '${d.label} closes at',
                                                      initial: day.close ??
                                                          const TimeOfDay(
                                                            hour: 18,
                                                            minute: 0,
                                                          ),
                                                    );
                                                    if (!mounted ||
                                                        picked == null) {
                                                      return;
                                                    }
                                                    setState(
                                                      () => day.close = picked,
                                                    );
                                                  },
                                            child: Text(
                                              day.close == null
                                                  ? 'To'
                                                  : _formatTime(day.close!),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  shape: cardShape,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle(
                          icon: Icons.map_outlined,
                          title: 'Map location',
                          subtitle: kIsWeb
                              ? 'Optional: paste coordinates from Google Maps.'
                              : 'Optional: drop a pin so buyers can open this spot in Google Maps.',
                        ),
                        const SizedBox(height: 12),
                        if (!kIsWeb) ...[
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _saving ? null : _openMapPicker,
                                  icon: const Icon(Icons.map_outlined),
                                  label: Text(
                                    _pickLat != null
                                        ? 'Update map pin'
                                        : 'Set map pin',
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
                          Builder(
                            builder: (context) {
                              final pin = _effectivePinForPreview();
                              if (pin == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${pin.lat.toStringAsFixed(6)}, ${pin.lng.toStringAsFixed(6)}',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                    const SizedBox(height: 10),
                                    KeyedSubtree(
                                      key: _mapPreviewKey,
                                      child: DealerLocationMapPreview(
                                        latitude: pin.lat,
                                        longitude: pin.lng,
                                        height: 170,
                                        onOpenInGoogleMaps: () =>
                                            _openPinInGoogleMaps(
                                          pin.lat,
                                          pin.lng,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ] else ...[
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: _coordLat,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Latitude',
                                    prefixIcon: Icon(Icons.my_location_outlined),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextFormField(
                                  controller: _coordLng,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                                  decoration: const InputDecoration(
                                    labelText: 'Longitude',
                                    prefixIcon:
                                        Icon(Icons.my_location_outlined),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          Builder(
                            builder: (context) {
                              final pin = _effectivePinForPreview();
                              if (pin == null) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: KeyedSubtree(
                                  key: _mapPreviewKey,
                                  child: DealerLocationMapPreview(
                                    latitude: pin.lat,
                                    longitude: pin.lng,
                                    height: 170,
                                    onOpenInGoogleMaps: () => _openPinInGoogleMaps(
                                      pin.lat,
                                      pin.lng,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

