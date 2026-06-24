import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../services/config.dart';
import '../models/analytics_model.dart';
import '../services/analytics_service.dart';
import '../shared/errors/user_error_text.dart';
import '../app/listing_shell.dart' show buildGlobalCarCard;
import '../shared/prefs/listing_layout_prefs.dart';
import '../theme_provider.dart';
import '../shared/text/pretty_title_case.dart';
part 'analytics_page_fields.dart';
part 'analytics_page_load.dart';
part 'analytics_page_listing_selection.dart';
part 'analytics_page_listing_card.dart';
part 'analytics_page_widgets.dart';
part 'analytics_page_core.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends _AnalyticsPageFields
    with
        _AnalyticsPageLoad,
        _AnalyticsPageListingCard,
        _AnalyticsPageListingSelection,
        _AnalyticsPageWidgets,
        _AnalyticsPageCore {}
