import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../l10n/app_localizations.dart';
import '../app/listing_shell.dart' show buildFloatingBottomNav, navigateMainShellTab;
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/media/media_url.dart';
import '../theme_provider.dart';
import '../shared/debug/app_log.dart';

part 'dealers_directory_page_fields.dart';
part 'dealers_directory_page_load.dart';
part 'dealers_directory_page_widgets.dart';
part 'dealers_directory_page_core.dart';

/// Browse and search approved dealerships (public API).
class DealersDirectoryPage extends StatefulWidget {
  const DealersDirectoryPage({super.key});

  @override
  State<DealersDirectoryPage> createState() => _DealersDirectoryPageState();
}

class _DealersDirectoryPageState extends _DealersDirectoryPageFields
    with
        _DealersDirectoryPageLoad,
        _DealersDirectoryPageWidgets,
        _DealersDirectoryPageCore {}
