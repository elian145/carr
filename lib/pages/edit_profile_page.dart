import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../l10n/app_localizations.dart';
import '../services/auth_service.dart';
import '../services/config.dart';
import '../shared/errors/user_error_text.dart';
import '../theme_provider.dart';
import 'package:provider/provider.dart';

part 'edit_profile_page_fields.dart';
part 'edit_profile_page_style.dart';
part 'edit_profile_page_load.dart';
part 'edit_profile_page_widgets.dart';
part 'edit_profile_page_core.dart';

String getApiBase() {
  return apiBase();
}

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends _EditProfilePageFields
    with
        _EditProfilePageStyle,
        _EditProfilePageLoad,
        _EditProfilePageWidgets,
        _EditProfilePageCore {}
