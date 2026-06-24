part of 'comparison_page.dart';

extension _CarComparisonPageBodyFilledHeader on CarComparisonPage {
  Widget _buildComparisonFilledHeader(
    BuildContext context,
    CarComparisonStore comparisonStore,
    List<Map<String, dynamic>> cars,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withValues(alpha: 0.72);

    return Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : AppThemes.lightAppBackground,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : cs.outlineVariant,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.compare_arrows,
                          color: Color(0xFFFF6B00),
                          size: 28,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocalizations.of(
                                  context,
                                )!.specificationsLabel,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? Colors.white : lightInk,
                                ),
                              ),
                              Text(
                                '${AppLocalizations.of(context)!.sortBy}: ${cars.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.white70
                                      : lightInkMuted,
                                ),
                              ),
                              SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: Color(0xFFFF6B00),
                                      ),
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : lightInk,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      Navigator.pushReplacementNamed(
                                        context,
                                        '/',
                                      );
                                    },
                                    icon: Icon(
                                      Icons.add,
                                      color: Color(0xFFFF6B00),
                                      size: 18,
                                    ),
                                    label: Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.addMorePhotos,
                                    ),
                                  ),
                                  Semantics(
                                    button: true,
                                    label: AppLocalizations.of(context)!.clearAll,
                                    child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(
                                        color: isDark
                                            ? Colors.white24
                                            : cs.outlineVariant,
                                      ),
                                      foregroundColor: isDark
                                          ? Colors.white
                                          : lightInk,
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                    ),
                                    onPressed: () {
                                      Provider.of<CarComparisonStore>(
                                        context,
                                        listen: false,
                                      ).clearComparison();
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(context)!.comparisonCleared,
                                          ),
                                          backgroundColor: Color(0xFFFF6B00),
                                        ),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.delete_outline,
                                      color: isDark
                                          ? Colors.white70
                                          : lightInkMuted,
                                      size: 18,
                                    ),
                                    label: Text(AppLocalizations.of(context)!.clearAll),
                                  ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
  }
}
