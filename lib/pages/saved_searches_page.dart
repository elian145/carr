import 'dart:async';

import 'package:flutter/material.dart';

import '../app/listing_shell.dart' show navigateMainShellTab;
import '../data/car_name_translations.dart';
import '../features/saved_searches/saved_search_home_bridge.dart';
import '../l10n/app_localizations.dart';
import '../services/saved_search_service.dart';
import '../shared/errors/user_error_text.dart';
import '../shared/i18n/legacy_inline_text.dart';
import '../shared/i18n/listing_field_labels.dart';
import '../shared/i18n/listing_value_labels.dart';
import '../shared/i18n/region_spec_labels.dart';
part 'saved_searches_page_fields.dart';
part 'saved_searches_page_load.dart';
part 'saved_searches_page_helpers.dart';
part 'saved_searches_page_actions.dart';
part 'saved_searches_page_filter_details.dart';
part 'saved_searches_page_core.dart';

class SavedSearchesPage extends StatefulWidget {
  final dynamic parentState;

  const SavedSearchesPage({super.key, this.parentState});

  @override
  State<SavedSearchesPage> createState() => _SavedSearchesPageState();
}

class _SavedSearchesPageState extends _SavedSearchesPageFields
    with
        _SavedSearchesPageLoad,
        _SavedSearchesPageHelpers,
        _SavedSearchesPageFilterDetails,
        _SavedSearchesPageActions,
        _SavedSearchesPageCore {}
