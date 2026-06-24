part of 'analytics_page.dart';

mixin _AnalyticsPageCore on _AnalyticsPageWidgets {
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
