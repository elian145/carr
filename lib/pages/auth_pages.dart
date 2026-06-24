import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:developer' as developer;
import '../services/auth_service.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../shared/errors/user_error_text.dart';
import '../widgets/theme_toggle_widget.dart';

// Lightweight i18n helpers for auth pages

part 'auth_pages_i18n.dart';
part 'auth_login_page.dart';
part 'auth_register_page.dart';
part 'auth_forgot_password_page.dart';
