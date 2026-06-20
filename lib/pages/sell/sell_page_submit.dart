part of '../sell_page.dart';

// Extensions on [_SellPageState] call [setState] legitimately.
// ignore_for_file: invalid_use_of_protected_member

extension SellPageSubmit on _SellPageState {
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
        SnackBar(
          content: Text(
            AppLocalizations.of(context)?.loginRequired ?? 'Login required',
          ),
        ),
      );
      Navigator.pushNamed(context, '/login');
      return;
    }

    final editListingIdEarly = (_editListingId ?? '').trim();
    if (editListingIdEarly.isEmpty && !auth.isUserVerified) {
      final verified = await ensurePhoneVerifiedForAction(context);
      if (!verified || !mounted) return;
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            loc?.pleaseFixHighlightedFields ??
                'Please fix the highlighted fields',
          ),
        ),
      );
      return;
    }

    final int year = int.tryParse(_year.text.trim()) ?? 0;
    final int mileage = int.tryParse(_mileage.text.trim()) ?? 0;
    final double price = double.tryParse(_price.text.trim()) ?? 0;

    final editListingId = (_editListingId ?? '').trim();
    final isEditing = editListingId.isNotEmpty;

    setState(() {
      _submitting = true;
      _stage = isEditing
          ? 'Updating listing...'
          : (loc?.creatingListing ?? 'Creating listing...');
    });
    try {
      final body = <String, dynamic>{
        'brand': _selectedBrand!.trim(),
        'model': _selectedModel!.trim(),
        'trim': _selectedTrim!.trim(),
        'year': year,
        'mileage': mileage,
        'engine_type': _engineType,
        'fuel_type': _fuelType,
        'transmission': _transmission,
        'drive_type': _driveType,
        'condition': _condition,
        'body_type': _bodyType,
        'price': price,
        'currency': _currency,
        'location': _location.text.trim(),
        'description': _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
        'title_status': _titleStatus,
      };
      final vinText = _vin.text.trim();
      if (vinText.isNotEmpty) body['vin'] = vinText;
      final eng = OnlineSpecVariant.parseLeadingEngineLiters(
        _engineSizeCtl.text.trim(),
      );
      if (eng != null && eng > 0) body['engine_size'] = eng;
      final cyl = int.tryParse(_cylinderCtl.text.trim());
      if (cyl != null && cyl > 0) body['cylinder_count'] = cyl;
      final fe = _fuelEconomyCtl.text.trim();
      if (fe.isNotEmpty) body['fuel_economy'] = fe;
      final seat = int.tryParse(_seatingCtl.text.trim());
      if (seat != null && seat > 0) body['seating'] = seat;
      if (_titleStatus == 'damaged') {
        final dp = int.tryParse(_damagedParts.text.trim());
        if (dp != null && dp > 0) body['damaged_parts'] = dp;
      }

      final saved = isEditing
          ? await ApiService.updateCar(editListingId, body)
          : await ApiService.createCar(body);

      final car = (saved['car'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(saved['car'])
          : <String, dynamic>{};
      final carId = isEditing ? editListingId : listingPrimaryId(car);
      if (carId.isEmpty) {
        throw StateError('Car saved but missing id');
      }

      final draftOwner = _draftOwnerKey ?? _buildDraftOwnerKey();
      final refreshedPaths = await SellDraftMediaPersistence.persistPathList(
        _images,
        draftId: draftOwner,
        namePrefix: 'listing',
      );
      final refreshedDamage = await SellDraftMediaPersistence.persistPathList(
        _damageImages,
        draftId: draftOwner,
        namePrefix: 'damage',
      );
      final refreshedVideos = await SellDraftMediaPersistence.persistPathList(
        _videos,
        draftId: draftOwner,
        namePrefix: 'video',
      );
      if (mounted) {
        setState(() {
          _images
            ..clear()
            ..addAll(refreshedPaths.map((path) => XFile(path)));
          _damageImages
            ..clear()
            ..addAll(refreshedDamage.map((path) => XFile(path)));
          _videos
            ..clear()
            ..addAll(refreshedVideos.map((path) => XFile(path)));
        });
      }

      if (_images.isNotEmpty) {
        setState(() => _stage = loc?.uploadingPhotos ?? 'Uploading photos...');
        await _uploadCarImages(carId);
      }
      if (_damageImages.isNotEmpty) {
        setState(
          () => _stage =
              loc?.uploadingDamagePhotos ?? 'Uploading damage photos...',
        );
        await _uploadDamageImages(carId);
      }
      if (_videos.isNotEmpty) {
        setState(() => _stage = loc?.uploadingVideos ?? 'Uploading videos...');
        await ApiService.uploadCarVideos(carId, _videos);
      }

      if (!mounted) return;
      await SellDraftPrefs.clearListingDraft(
        _draftOwnerKey ?? _buildDraftOwnerKey(),
      );
      _skipDraftSaveOnDispose = true;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing
                ? 'Listing updated'
                : (loc?.listingCreated ?? 'Listing created'),
          ),
        ),
      );
      if (!mounted) return;
      if (isEditing) {
        Navigator.pop(context, {
          'car': car.isNotEmpty ? car : <String, dynamic>{...body, 'id': carId},
        });
        return;
      }
      Navigator.pushReplacementNamed(
        context,
        '/car_detail',
        arguments: {'carId': carId},
      );
    } catch (e) {
      if (!mounted) return;
      if (isPhoneVerificationRequired(e)) {
        showPhoneVerificationRequiredSnackBar(context);
      }
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.couldNotSubmitListing ??
              'Could not submit listing. Please try again.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
          _stage = null;
        });
      }
    }
  }

  /// Shown under trim: loading DB, error, "no match" explanation, or catalog card.
}
