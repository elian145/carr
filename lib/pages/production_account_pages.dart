import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/widgets/main_shell_navigation.dart'
    show buildFloatingBottomNav, navigateMainShellTab;
import '../l10n/app_localizations.dart';
import '../pages/saved_searches_page.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../services/push_notification_service.dart';
import '../services/websocket_service.dart';
import '../shared/account/delete_account_dialog.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/media/media_url.dart';
import '../state/locale_controller.dart';
import '../theme_provider.dart';
part 'production_profile_fields.dart';
part 'production_profile_style.dart';
part 'production_profile_load.dart';
part 'production_profile_widgets.dart';
part 'production_profile_body_guest.dart';
part 'production_profile_body_account.dart';
part 'production_profile_body_actions.dart';
part 'production_profile_body.dart';
part 'production_profile_core.dart';
part 'production_profile_page.dart';
part 'production_settings_page.dart';
