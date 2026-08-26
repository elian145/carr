part of 'edit_dealer_page.dart';

mixin _EditDealerPageProfile on _EditDealerPageHours {
  @override
  void initState() {
    super.initState();
    _openingHours = {
      for (final d in _editDealerDays)
        d.key: _DayHours(enabled: false, is24h: false),
    };
    _openingHoursTileControllers = {
      for (final d in _editDealerDays) d.key: ExpansibleController(),
    };
    _openingHoursTileKeys = {
      for (final d in _editDealerDays) d.key: GlobalKey(),
    };
    unawaited(_hydrateProfile());
  }

  Future<void> _hydrateProfile() async {
    try {
      await context.read<AuthService>().refreshProfile();
    } catch (e, st) {
      logNonFatal(e, st, 'EditDealerPage.refreshProfile');
    }
    if (!mounted) return;
    _applyDealerUser(context.read<AuthService>().currentUser);
    setState(() => _hydratingProfile = false);
  }

  void _applyDealerUser(Map<String, dynamic>? me) {
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
    _verifiedPhones.clear();
    final rawVerifiedPhones = me?['dealership_verified_phones'];
    if (rawVerifiedPhones is List) {
      for (final value in rawVerifiedPhones) {
        final normalized = normalizeDealerPhoneForVerification(
          (value ?? '').toString(),
        );
        if (normalized.isNotEmpty) _verifiedPhones.add(normalized);
      }
    }
    if (me?['is_verified'] == true) {
      final accountPhone = normalizeDealerPhoneForVerification(
        (me?['phone_number'] ?? '').toString(),
      );
      if (accountPhone.isNotEmpty) _verifiedPhones.add(accountPhone);
    }
    final initialEmails = <String>[];
    final rawEmails = me?['dealership_emails'];
    if (rawEmails is List) {
      for (final x in rawEmails) {
        final s = (x ?? '').toString().trim();
        if (s.isNotEmpty) initialEmails.add(s);
      }
    }
    _emails
      ..clear()
      ..addAll(initialEmails.map((e) => TextEditingController(text: e)));
    _verifiedEmails.clear();
    final rawVerifiedEmails = me?['dealership_verified_emails'];
    if (rawVerifiedEmails is List) {
      for (final value in rawVerifiedEmails) {
        final normalized = normalizeDealerEmailForVerification(
          (value ?? '').toString(),
        );
        if (normalized.isNotEmpty) _verifiedEmails.add(normalized);
      }
    }
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
      } catch (e, st) {
        logNonFatal(e, st);
      }
    }
    if (hoursMap != null) {
      for (final d in _editDealerDays) {
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
    final socials = DealerSocials.fromDealerMap(me);
    _facebook.text = '';
    _instagram.text = '';
    _tiktok.text = '';
    for (final link in socials) {
      final handle = DealerSocials.editHandle(link.network, link.url);
      switch (link.network) {
        case DealerSocialNetwork.facebook:
          _facebook.text = handle;
        case DealerSocialNetwork.instagram:
          _instagram.text = handle;
        case DealerSocialNetwork.tiktok:
          _tiktok.text = handle;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    for (final c in _phones) {
      c.dispose();
    }
    for (final c in _emails) {
      c.dispose();
    }
    _location.dispose();
    _description.dispose();
    _coordLat.dispose();
    _coordLng.dispose();
    _facebook.dispose();
    _instagram.dispose();
    _tiktok.dispose();
    super.dispose();
  }
}
