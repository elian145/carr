import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import '../../theme/app_colors.dart';

Future<XFile?> pickCoverImage(
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
    aspectRatio: const CropAspectRatio(ratioX: 16, ratioY: 9),
    compressFormat: ImageCompressFormat.jpg,
    compressQuality: 90,
    maxWidth: 1600,
    maxHeight: 900,
    uiSettings: [
      AndroidUiSettings(
        toolbarTitle: title,
        toolbarColor: const Color(0xFF111111),
        toolbarWidgetColor: Colors.white,
        activeControlsWidgetColor: AppColors.brandOrange,
        cropStyle: CropStyle.rectangle,
        initAspectRatio: CropAspectRatioPreset.ratio16x9,
        aspectRatioPresets: const [CropAspectRatioPreset.ratio16x9],
        lockAspectRatio: true,
      ),
      IOSUiSettings(
        title: title,
        doneButtonTitle: doneLabel,
        cancelButtonTitle: cancelLabel,
        cropStyle: CropStyle.rectangle,
        aspectRatioLockEnabled: true,
        resetAspectRatioEnabled: false,
        aspectRatioPresets: const [CropAspectRatioPreset.ratio16x9],
      ),
      WebUiSettings(context: context),
    ],
  );

  return cropped == null ? null : XFile(cropped.path);
}
