import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';

Future<XFile?> pickCircularImage(
  BuildContext context, {
  required String title,
  String doneLabel = 'Done',
  String cancelLabel = 'Cancel',
}) async {
  final picked = await ImagePicker().pickImage(
    source: ImageSource.gallery,
    imageQuality: 95,
  );
  if (picked == null || !context.mounted) return null;

  final cropped = await ImageCropper().cropImage(
    sourcePath: picked.path,
    aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    maxWidth: 1024,
    maxHeight: 1024,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: title,
        toolbarColor: const Color(0xFF111111),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: AppColors.brandOrange,
        cropStyle: CropStyle.circle,
        initAspectRatio: CropAspectRatioPreset.square,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
        lockAspectRatio: true,
      ),
      IOSUiSettings(
        title: title,
        doneButtonTitle: doneLabel,
        cancelButtonTitle: cancelLabel,
        cropStyle: CropStyle.circle,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPresets: const [CropAspectRatioPreset.square],
      ),
      WebUiSettings(context: context),
    ],
  );

  return cropped == null ? null : XFile(cropped.path);
}
