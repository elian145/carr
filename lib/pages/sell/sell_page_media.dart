part of '../sell_page.dart';

// Extensions on [_SellPageState] call [setState] legitimately.
// ignore_for_file: invalid_use_of_protected_member

extension SellPageMedia on _SellPageState {
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
      _scheduleDraftSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
        );
      });
    }
  }

  Future<void> _pickVideo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _videos.add(picked);
      });
      _scheduleDraftSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
        );
      });
    }
  }

  Future<void> _pickDamageImages() async {
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
        _damageImages.addAll(picked);
      });
      _scheduleDraftSave();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)?.errorTitle ?? 'Error',
        );
      });
    }
  }

  Future<void> _uploadCarImages(String carId) async {
    final files = SellDraftMediaPersistence.xFilesForUpload(_images);
    if (files.isEmpty) return;
    try {
      final publicUrls = <String>[];
      for (final file in files) {
        final sign = await ApiService.signR2ImageUpload(
          filename: file.name,
          contentType: file.mimeType,
        );
        final uploadUrl = sign['upload_url'] as String?;
        final publicUrl = sign['public_url'] as String?;
        if (uploadUrl == null ||
            uploadUrl.isEmpty ||
            publicUrl == null ||
            publicUrl.isEmpty) {
          await ApiService.uploadCarImages(carId, files);
          return;
        }
        await ApiService.uploadToSignedUpload(uploadUrl, file);
        publicUrls.add(publicUrl);
      }
      await ApiService.attachCarImageUrls(carId, publicUrls);
    } on ApiException catch (e) {
      if (e.statusCode == 503) {
        await ApiService.uploadCarImages(carId, files);
      } else {
        rethrow;
      }
    } catch (_) {
      await ApiService.uploadCarImages(carId, files);
    }
  }

  Future<void> _uploadDamageImages(String carId) async {
    final files = SellDraftMediaPersistence.xFilesForUpload(_damageImages);
    if (files.isEmpty) return;
    try {
      final publicUrls = <String>[];
      for (final file in files) {
        final sign = await ApiService.signR2ImageUpload(
          filename: file.name,
          contentType: file.mimeType,
        );
        final uploadUrl = sign['upload_url'] as String?;
        final publicUrl = sign['public_url'] as String?;
        if (uploadUrl == null ||
            uploadUrl.isEmpty ||
            publicUrl == null ||
            publicUrl.isEmpty) {
          await ApiService.uploadCarImages(
            carId,
            files,
            imageKind: 'damage',
          );
          return;
        }
        await ApiService.uploadToSignedUpload(uploadUrl, file);
        publicUrls.add(publicUrl);
      }
      await ApiService.attachCarImageUrls(carId, publicUrls, kind: 'damage');
    } on ApiException catch (e) {
      if (e.statusCode == 503) {
        await ApiService.uploadCarImages(
          carId,
          files,
          imageKind: 'damage',
        );
      } else {
        rethrow;
      }
    } catch (_) {
      await ApiService.uploadCarImages(
        carId,
        files,
        imageKind: 'damage',
      );
    }
  }

}
