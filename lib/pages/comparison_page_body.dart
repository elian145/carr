part of 'comparison_page.dart';

extension _CarComparisonPageBody on CarComparisonPage {
  Widget _buildComparisonBody(
    BuildContext context,
    CarComparisonStore comparisonStore,
  ) {
              final cars = comparisonStore.comparisonCars;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final cs = Theme.of(context).colorScheme;
              final lightInk = AppThemes.darkHomeShellBackground;
              final lightInkMuted = lightInk.withValues(alpha: 0.72);

              if (cars.isEmpty) {
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

              return ListView(
                padding: EdgeInsets.all(16),
                children: [
                  // Header
                  Container(
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
                  ),
                  SizedBox(height: 20),

                  // Comparison Table
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final double labelWidth = 120.0;
                      final double horizontalPadding =
                          32.0; // padding inside row containers
                      final bool isTwoCars = cars.length == 2;
                      final double availableWidth = constraints.maxWidth;
                      final double effectiveRowWidth =
                          availableWidth - horizontalPadding;
                      final int numColumns = cars.isEmpty ? 1 : cars.length;
                      final double baseColumnWidth =
                          (effectiveRowWidth - labelWidth) / numColumns;
                      final double columnWidth = isTwoCars
                          ? (baseColumnWidth < 96.0 ? 96.0 : baseColumnWidth)
                          : baseColumnWidth.clamp(120.0, 260.0).toDouble();
                      final double requiredWidth =
                          labelWidth +
                          (numColumns * columnWidth) +
                          horizontalPadding;
                      final double tableWidth = requiredWidth > availableWidth
                          ? requiredWidth
                          : availableWidth;
                      final double imageSize = isTwoCars
                          ? ((columnWidth - 16).clamp(88.0, 120.0)).toDouble()
                          : 120.0;
                      final double headerTitleHeight = 52.0;
                      final double headerPriceHeight = 22.0;

                      final table = Container(
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : AppThemes.lightAppBackground,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 16,
                              offset: Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Car Headers
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                // Keep the orange accent in light mode, but soften it.
                                color: Color(0xFFFF6B00).withValues(alpha: 
                                  isDark ? 0.12 : 0.10,
                                ),
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: isTwoCars
                                    ? MainAxisAlignment.center
                                    : MainAxisAlignment.start,
                                children: isTwoCars
                                    ? [
                                        // Left car
                                        SizedBox(
                                          width: columnWidth,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Column(
                                              children: [
                                                Container(
                                                  height: imageSize,
                                                  width: imageSize,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white10,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: _buildCarImage(
                                                      cars[0],
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                SizedBox(
                                                  height: headerTitleHeight,
                                                  child: Center(
                                                    child: AutoSizeText(
                                                      (cars[0]['title'] ?? '')
                                                          .toString(),
                                                      textScaleFactor: 1.0,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: isDark
                                                            ? Colors.white
                                                            : lightInk,
                                                        height: 1.15,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      minFontSize: 9,
                                                      stepGranularity: 0.5,
                                                      overflow:
                                                          TextOverflow.clip,
                                                      softWrap: true,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                SizedBox(
                                                  height: headerPriceHeight,
                                                  child: Center(
                                                    child: Text(
                                                      formatCurrency(
                                                        context,
                                                        cars[0]['price']
                                                                ?.toString() ??
                                                            '0',
                                                      ),
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                IconButton(
                                                  onPressed: () {
                                                    comparisonStore
                                                        .removeCarFromComparison(
                                                          cars[0]['id'],
                                                        );
                                                  },
                                                  icon: Icon(
                                                    Icons.close,
                                                    color: Colors.red,
                                                    size: 24,
                                                  ),
                                                  constraints: BoxConstraints(),
                                                  padding: EdgeInsets.zero,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        // Middle spacer for labels
                                        SizedBox(width: labelWidth),
                                        // Right car
                                        SizedBox(
                                          width: columnWidth,
                                          child: Padding(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8,
                                            ),
                                            child: Column(
                                              children: [
                                                Container(
                                                  height: imageSize,
                                                  width: imageSize,
                                                  decoration: BoxDecoration(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    border: Border.all(
                                                      color: Colors.white10,
                                                    ),
                                                  ),
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    child: _buildCarImage(
                                                      cars[1],
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                SizedBox(
                                                  height: headerTitleHeight,
                                                  child: Center(
                                                    child: AutoSizeText(
                                                      (cars[1]['title'] ?? '')
                                                          .toString(),
                                                      textScaleFactor: 1.0,
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 14,
                                                        color: isDark
                                                            ? Colors.white
                                                            : lightInk,
                                                        height: 1.15,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      minFontSize: 9,
                                                      stepGranularity: 0.5,
                                                      overflow:
                                                          TextOverflow.clip,
                                                      softWrap: true,
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 4),
                                                SizedBox(
                                                  height: headerPriceHeight,
                                                  child: Center(
                                                    child: Text(
                                                      formatCurrency(
                                                        context,
                                                        cars[1]['price']
                                                                ?.toString() ??
                                                            '0',
                                                      ),
                                                      style: TextStyle(
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 16,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                SizedBox(height: 8),
                                                IconButton(
                                                  onPressed: () {
                                                    comparisonStore
                                                        .removeCarFromComparison(
                                                          cars[1]['id'],
                                                        );
                                                  },
                                                  icon: Icon(
                                                    Icons.close,
                                                    color: Colors.red,
                                                    size: 24,
                                                  ),
                                                  constraints: BoxConstraints(),
                                                  padding: EdgeInsets.zero,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ]
                                    : [
                                        SizedBox(
                                          width: labelWidth,
                                        ), // Space for property names
                                        ...cars.map(
                                          (car) => SizedBox(
                                            width: columnWidth,
                                            child: Padding(
                                              padding: EdgeInsets.symmetric(
                                                horizontal: 8,
                                              ),
                                              child: Column(
                                                children: [
                                                  Container(
                                                    height: 110,
                                                    width: 110,
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      border: Border.all(
                                                        color: Colors.white10,
                                                      ),
                                                    ),
                                                    child: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                      child: _buildCarImage(
                                                        car,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 8),
                                                  SizedBox(
                                                    height: headerTitleHeight,
                                                    child: Center(
                                                      child: AutoSizeText(
                                                        [
                                                              localizedCarTitleForCard(
                                                                context,
                                                                car,
                                                              ),
                                                              localizedTrimForCard(
                                                                context,
                                                                car,
                                                              ),
                                                            ]
                                                            .where(
                                                              (s) =>
                                                                  s.isNotEmpty,
                                                            )
                                                            .join(' '),
                                                        textScaleFactor: 1.0,
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 14,
                                                          color: isDark
                                                              ? Colors.white
                                                              : lightInk,
                                                          height: 1.15,
                                                        ),
                                                        textAlign:
                                                            TextAlign.center,
                                                        maxLines: 2,
                                                        minFontSize: 9,
                                                        stepGranularity: 0.5,
                                                        overflow:
                                                            TextOverflow.clip,
                                                        softWrap: true,
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 4),
                                                  SizedBox(
                                                    height: headerPriceHeight,
                                                    child: Center(
                                                      child: Text(
                                                        formatCurrency(
                                                          context,
                                                          car['price']
                                                                  ?.toString() ??
                                                              '0',
                                                        ),
                                                        style: TextStyle(
                                                          color: Color(
                                                            0xFFFF6B00,
                                                          ),
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          fontSize: 16,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  SizedBox(height: 8),
                                                  IconButton(
                                                    onPressed: () {
                                                      comparisonStore
                                                          .removeCarFromComparison(
                                                            car['id'],
                                                          );
                                                    },
                                                    icon: Icon(
                                                      Icons.close,
                                                      color: Colors.red,
                                                      size: 24,
                                                    ),
                                                    constraints:
                                                        BoxConstraints(),
                                                    padding: EdgeInsets.zero,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                              ),
                            ),
                            SizedBox(height: 12),

                            // Comparison Rows
                            ..._buildComparisonRows(
                              context,
                              cars,
                              columnWidth,
                              labelWidth,
                            ),
                          ],
                        ),
                      );

                      if (isTwoCars) {
                        return SizedBox(width: availableWidth, child: table);
                      }
                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: BouncingScrollPhysics(),
                        child: SizedBox(width: tableWidth, child: table),
                      );
                    },
                  ),
                ],
              );
  }
}
