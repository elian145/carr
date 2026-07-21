import 'dart:async';
import 'dart:convert';
import '../theme/app_colors.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' as services;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/widgets/global_listing_card.dart'
    show buildGlobalCarCard, mapListingToGlobalCarCardData;
import '../app/widgets/main_shell_navigation.dart'
    show buildFloatingBottomNav, navigateMainShellTab;
import '../features/chat/chat_pages.dart' as carzo_chat;
import '../features/listing/listing_mappers.dart';
import '../l10n/app_localizations.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/ui/app_haptics.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../shared/ui/listing_feed_skeleton.dart';
import '../shared/ui/empty_state_panel.dart';
import '../shared/ui/responsive.dart';
import '../shared/ui/keyboard.dart';
import '../theme_provider.dart';

part 'production_favorites_page.dart';
part 'production_chat_list_page.dart';
part 'production_login_page.dart';
