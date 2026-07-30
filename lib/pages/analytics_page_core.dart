part of 'analytics_page.dart';

mixin _AnalyticsPageCore on _AnalyticsPageWidgets {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.analyticsTitle),
        backgroundColor: AppColors.brandOrange,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Container(
        decoration: AppThemes.shellBackgroundDecoration(
          Theme.of(context).brightness,
        ),
        child: _isLoading
            ? _analyticsSkeleton(context)
            : _error != null
            ? _buildErrorState(context)
            : _buildAnalyticsContent(context),
      ),
    );
  }

  Widget _analyticsSkeleton(BuildContext context) {
    Widget box({double? height, double? width, double radius = 12}) =>
        Container(
          height: height,
          width: width,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          box(height: 120, radius: 16),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: box(height: 84)),
              const SizedBox(width: 12),
              Expanded(child: box(height: 84)),
            ],
          ),
          const SizedBox(height: 16),
          box(height: 200, radius: 16),
        ],
      ),
    );
  }
}
