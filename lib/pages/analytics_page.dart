import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'package:intl/intl.dart';
import '../services/config.dart';
import '../models/analytics_model.dart';
import '../services/analytics_service.dart';
import '../shared/errors/user_error_text.dart';
import '../app/listing_shell.dart' show buildGlobalCarCard;
import '../theme_provider.dart';
import '../shared/text/pretty_title_case.dart';

part 'analytics_page_widgets.dart';

class AnalyticsPage extends StatefulWidget {
  const AnalyticsPage({super.key});

  @override
  State<AnalyticsPage> createState() => _AnalyticsPageState();
}

class _AnalyticsPageState extends State<AnalyticsPage> {
  List<ListingAnalytics> _listings = [];
  ListingAnalytics? _selectedListing;
  bool _isLoading = true;
  String? _error;
  AnalyticsSummary? _summary;

  // Brand logo filenames map (copied from main.dart)
  final Map<String, String> brandLogoFilenames = {
    'toyota': 'toyota',
    'nissan': 'nissan',
    'mercedes-benz': 'mercedes-benz',
    'bmw': 'bmw',
    'audi': 'audi',
    'volkswagen': 'volkswagen',
    'kia': 'kia',
    'hyundai': 'hyundai',
    'honda': 'honda',
    'mazda': 'mazda',
    'ford': 'ford',
    'chevrolet': 'chevrolet',
    'lexus': 'lexus',
    'infiniti': 'infiniti',
    'mitsubishi': 'mitsubishi',
    'subaru': 'subaru',
    'suzuki': 'suzuki',
    'acura': 'acura',
    'buick': 'buick',
    'cadillac': 'cadillac',
    'chrysler': 'chrysler',
    'dodge': 'dodge',
    'genesis': 'genesis',
    'gmc': 'gmc',
    'jaguar': 'jaguar',
    'jeep': 'jeep',
    'lincoln': 'lincoln',
    'maserati': 'maserati',
    'mini': 'mini',
    'porsche': 'porsche',
    'ram': 'ram',
    'smart': 'smart',
    'tesla': 'tesla',
    'volvo': 'volvo',
    'dacia': 'dacia',
    'fiat': 'fiat',
    'lancia': 'lancia',
    'land-rover': 'land-rover',
    'skoda': 'skoda',
    'seat': 'seat',
    'peugeot': 'peugeot',
    'citroën': 'citroen',
    'citroen': 'citroen',
    'renault': 'renault',
    'opel': 'opel',
    'alfa-romeo': 'alfa-romeo',
    'ferrari': 'ferrari',
    'lamborghini': 'lamborghini',
    'bentley': 'bentley',
    'rolls-royce': 'rolls-royce',
    'aston-martin': 'aston-martin',
    'mclaren': 'mclaren',
    'lotus': 'lotus',
    'saab': 'saab',
    'scion': 'scion',
    'isuzu': 'isuzu',
    'daihatsu': 'daihatsu',
    'geo': 'geo',
    'hummer': 'hummer',
    'mercury': 'mercury',
    'oldsmobile': 'oldsmobile',
    'plymouth': 'plymouth',
    'pontiac': 'pontiac',
    'saturn': 'saturn',
    'daewoo': 'daewoo',
    'ssangyong': 'ssangyong',
    'great-wall': 'great-wall',
    'chery': 'chery',
    'byd': 'byd',
    'geely': 'geely',
    'mg': 'mg',
    'tata': 'tata',
    'mahindra': 'mahindra',
    'maruti-suzuki': 'maruti-suzuki',
    'proton': 'proton',
    'perodua': 'perodua',
    'lada': 'lada',
    'uaz': 'uaz',
    'gaz': 'gaz',
    'zaz': 'zaz',
    'bogdan': 'bogdan',
    'changan': 'changan',
    'dongfeng': 'dongfeng',
    'faw': 'faw',
    'jac': 'jac',
    'jianghuai': 'jianghuai',
    'lifan': 'lifan',
    'zotye': 'zotye',
    'haval': 'haval',
    'wey': 'wey',
    'lynk-co': 'lynk-co',
    'polestar': 'polestar',
    'ds': 'ds',
    'alpine': 'alpine',
    'cupra': 'cupra',
    'maybach': 'maybach',
    'amg': 'amg',
    'brabus': 'brabus',
    'alpina': 'alpina',
    'ac-cars': 'ac-cars',
    'ariel': 'ariel',
    'caterham': 'caterham',
    'morgan': 'morgan',
    'tvr': 'tvr',
    'westfield': 'westfield',
  };

  // Helper functions (copied from main.dart)
  String getApiBase() {
    return apiBase();
  }

  NumberFormat _decimalFormatterGlobal(BuildContext context) {
    final locale = Localizations.localeOf(context);
    if (locale.languageCode == 'ar' ||
        locale.languageCode == 'ku' ||
        locale.languageCode == 'ckb') {
      return NumberFormat.decimalPattern('en_US');
    }
    return NumberFormat.decimalPattern(locale.toLanguageTag());
  }

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final listings = await AnalyticsService.getUserListingsAnalytics();
      if (!mounted) return;
      setState(() {
        _listings = listings;
        _summary = AnalyticsSummary.fromListings(listings);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback:
              AppLocalizations.of(context)?.failedToLoadListings ??
              'Failed to load your listings',
        );
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.analyticsTitle),
        backgroundColor: Color(0xFFFF6B00),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: AppThemes.shellBackgroundDecoration(
          Theme.of(context).brightness,
        ),
        child: _isLoading
            ? Center(child: CircularProgressIndicator())
            : _error != null
            ? _buildErrorState(context)
            : _buildAnalyticsContent(context),
      ),
    );
  }
}
