part of 'comparison_page.dart';

extension _CarComparisonPageBodyEmpty on CarComparisonPage {
  Widget _buildComparisonEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withValues(alpha: 0.72);

                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.compare_arrows,
                        size: 84,
                        color: isDark
                            ? Colors.white24
                            : cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                      SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.noCarsFound,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white70 : lightInk,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        AppLocalizations.of(context)!.tapToSelectBrand,
                        style: TextStyle(
                          fontSize: 16,
                          color: isDark ? Colors.white54 : lightInkMuted,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: () =>
                            Navigator.pushReplacementNamed(context, '/'),
                        icon: Icon(Icons.search),
                        label: Text(AppLocalizations.of(context)!.navHome),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFFFF6B00),
                          foregroundColor: Colors.white,
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
  }
}
