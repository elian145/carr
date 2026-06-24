import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../shared/debug/app_log.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../widgets/theme_toggle_widget.dart';

part 'forgot_password_page_fields.dart';
part 'forgot_password_page_labels.dart';
part 'forgot_password_page_actions.dart';
part 'forgot_password_page_core.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends _ForgotPasswordPageFields
    with
        _ForgotPasswordPageLabels,
        _ForgotPasswordPageActions,
        _ForgotPasswordPageCore {}
