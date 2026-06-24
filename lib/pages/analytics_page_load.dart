part of 'analytics_page.dart';

mixin _AnalyticsPageLoad on _AnalyticsPageFields {
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
}
