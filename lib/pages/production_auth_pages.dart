import 'dart:async';
import 'dart:convert';

import 'dart:io';

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
import '../navigation/app_page_route.dart';
import '../pages/legal_document_page.dart';
import '../services/analytics_service.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/prefs/listing_layout_prefs.dart';
import '../theme_provider.dart';

part 'production_favorites_page.dart';
part 'production_chat_list_page.dart';
part 'production_login_page.dart';
part 'production_signup_page_fields.dart';
part 'production_signup_page_actions.dart';
part 'production_signup_page_build.dart';
part 'production_signup_page.dart';
