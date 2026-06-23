part of '../app/carzo_shared.dart';

// Car Comparison Page
class CarComparisonPage extends StatelessWidget {
  const CarComparisonPage({super.key});

  @override
  Widget build(BuildContext context) {
    final pageIsDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: pageIsDark ? null : AppThemes.lightAppBackground,
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.specificationsLabel),
        elevation: 0,
        actions: [
          Semantics(
            button: true,
            label: AppLocalizations.of(context)!.shareAction,
            child: IconButton(
              tooltip: AppLocalizations.of(context)!.shareAction,
              onPressed: () async {
              try {
                final store = Provider.of<CarComparisonStore>(
                  context,
                  listen: false,
                );
                final cars = store.comparisonCars;
                final text = cars
                    .map(
                      (c) =>
                          '${c['title'] ?? ''} â€¢ ${c['year'] ?? ''} â€¢ ${c['price'] ?? ''}',
                    )
                    .join('\n');
                if (text.trim().isNotEmpty) {
                  SharePlus.instance.share(ShareParams(text: text));
                }
              } catch (e, st) { logNonFatal(e, st); }
            },
            icon: Icon(Icons.share_outlined),
            ),
          ),
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, child) {
              if (comparisonStore.comparisonCount > 0) {
                return TextButton(
                  onPressed: () {
                    comparisonStore.clearComparison();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(context)!.clearFilters,
                        ),
                        backgroundColor: Color(0xFFFF6B00),
                      ),
                    );
                  },
                  child: Text(
                    AppLocalizations.of(context)!.clearFilters,
                    style: TextStyle(color: Colors.white),
                  ),
                );
              }
              return SizedBox.shrink();
            },
          ),
          const ThemeToggleWidget(),
          buildLanguageMenu(),
        ],
      ),
      body: Stack(
        children: [
          Container(
            decoration: pageIsDark
                ? AppThemes.shellBackgroundDecoration(Brightness.dark)
                : const BoxDecoration(color: AppThemes.lightAppBackground),
          ),
          Consumer<CarComparisonStore>(
            builder: (context, comparisonStore, child) {
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
                                    label: _clearAllTextGlobal(context),
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
                                            _comparisonClearedTextGlobal(
                                              context,
                                            ),
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
                                    label: Text(_clearAllTextGlobal(context)),
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
                                                      _formatCurrencyGlobal(
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
                                                      _formatCurrencyGlobal(
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
                                                              _localizedCarTitleForCard(
                                                                context,
                                                                car,
                                                              ),
                                                              _localizedTrimForCard(
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
                                                        _formatCurrencyGlobal(
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
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCarImage(Map<String, dynamic> car) {
    final imageUrl = car['image_url']?.toString();
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final built = _buildFullImageUrl(imageUrl);
      return _listingNetworkImage(built, fit: BoxFit.cover);
    }
    return Container(
      color: Colors.white10,
      child: Icon(Icons.directions_car, color: Colors.white24),
    );
  }

  List<Widget> _buildComparisonRows(
    BuildContext context,
    List<Map<String, dynamic>> cars,
    double columnWidth,
    double labelWidth,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final lightInk = AppThemes.darkHomeShellBackground;
    final lightInkMuted = lightInk.withValues(alpha: 0.72);
    final sections = [
      {
        'title': AppLocalizations.of(context)!.brandLabel,
        'icon': Icons.info_outline,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.brandLabel,
            'key': 'brand',
            'icon': Icons.directions_car,
          },
          {
            'label': AppLocalizations.of(context)!.modelLabel,
            'key': 'model',
            'icon': Icons.badge_outlined,
          },
          {
            'label': AppLocalizations.of(context)!.trimLabel,
            'key': 'trim',
            'icon': Icons.layers,
          },
          {
            'label': AppLocalizations.of(context)!.yearLabel,
            'key': 'year',
            'icon': Icons.calendar_today,
          },
          {
            'label': AppLocalizations.of(context)!.cityLabel,
            'key': 'city',
            'icon': Icons.location_city,
          },
          {
            'label': AppLocalizations.of(context)!.priceLabel,
            'key': 'price',
            'icon': Icons.attach_money,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.specificationsLabel,
        'icon': Icons.speed,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.mileageLabel,
            'key': 'mileage',
            'suffix': ' ${AppLocalizations.of(context)!.unit_km}',
            'icon': Icons.speed,
          },
          {
            'label': AppLocalizations.of(context)!.engineSizeL,
            'key': 'engine_size',
            'suffix': AppLocalizations.of(context)!.unit_liter_suffix,
            'icon': Icons.settings,
          },
          {
            'label': AppLocalizations.of(context)!.detail_cylinders,
            'key': 'cylinder_count',
            'suffix': '',
            'icon': Icons.precision_manufacturing,
          },
          {
            'label': AppLocalizations.of(context)!.seating,
            'key': 'seating',
            'suffix': '',
            'icon': Icons.event_seat,
          },
        ],
      },
      {
        'title': AppLocalizations.of(context)!.moreFilters,
        'icon': Icons.tune,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.detail_condition,
            'key': 'condition',
            'icon': Icons.verified,
          },
          {
            'label': AppLocalizations.of(context)!.transmissionLabel,
            'key': 'transmission',
            'icon': Icons.settings_suggest,
          },
          {
            'label': AppLocalizations.of(context)!.detail_fuel,
            'key': 'fuel_type',
            'icon': Icons.local_gas_station,
          },
          {
            'label': AppLocalizations.of(context)!.detail_body,
            'key': 'body_type',
            'icon': Icons.directions_car_filled,
          },
          {
            'label': AppLocalizations.of(context)!.driveType,
            'key': 'drive_type',
            'icon': Icons.all_inclusive,
          },
          {
            'label': AppLocalizations.of(context)!.regionSpecsLabel,
            'key': 'region_specs',
            'icon': Icons.public,
          },
          {
            'label': AppLocalizations.of(context)!.detail_color,
            'key': 'color',
            'icon': Icons.color_lens,
          },
        ],
      },
      {
        'title': _statusTitleGlobal(context),
        'icon': Icons.assignment_turned_in,
        'rows': [
          {
            'label': AppLocalizations.of(context)!.titleStatus,
            'key': 'title_status',
            'icon': Icons.assignment,
          },
          {
            'label': AppLocalizations.of(context)!.damagedParts,
            'key': 'damaged_parts',
            'suffix': '',
            'icon': Icons.build,
          },
          {
            'label': _quickSellTextGlobal(context),
            'key': 'is_quick_sell',
            'isBoolean': true,
            'icon': Icons.flash_on,
          },
        ],
      },
    ];

    final List<Widget> out = [];
    for (int s = 0; s < sections.length; s++) {
      final section = sections[s] as Map<String, dynamic>;
      out.add(
        Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          margin: EdgeInsets.only(top: s == 0 ? 0 : 16),
          decoration: BoxDecoration(
            // Keep the orange accent in light mode, but soften it.
            color: Color(0xFFFF6B00).withValues(alpha: isDark ? 0.12 : 0.10),
            borderRadius: BorderRadius.circular(12),
            border: isDark ? null : Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              if (section['icon'] is IconData)
                Icon(
                  section['icon'] as IconData,
                  color: Color(0xFFFF6B00),
                  size: 18,
                )
              else
                Icon(Icons.toc, color: Color(0xFFFF6B00), size: 18),
              SizedBox(width: 8),
              Text(
                section['title'].toString(),
                style: TextStyle(
                  color: isDark ? Colors.white : lightInk,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );

      final List rows = section['rows'] as List;
      for (int i = 0; i < rows.length; i++) {
        final property = Map<String, dynamic>.from(rows[i] as Map);
        final bool isOdd = i % 2 == 1;
        out.add(
          Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            decoration: BoxDecoration(
              color: isOdd
                  ? (isDark
                      ? Colors.white.withValues(alpha: 0.02)
                      : Colors.black.withValues(alpha: 0.02))
                  : Colors.transparent,
              border: Border(
                bottom: BorderSide(
                  color: isDark ? Colors.white12 : cs.outlineVariant,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: cars.length == 2
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                if (cars.length == 2) ...[
                  SizedBox(
                    width: columnWidth,
                    child: _buildCellValue(context, cars[0], property),
                  ),
                  SizedBox(
                    width: labelWidth,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final bool isDamagedParts =
                              (property['key']?.toString() ?? '') ==
                              'damaged_parts';
                          final double gap = isDamagedParts ? 2 : 4;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                (rows[i]['icon'] is IconData)
                                    ? (rows[i]['icon'] as IconData)
                                    : Icons.label_outline,
                                color: isDark ? Colors.white54 : lightInkMuted,
                                size: 16,
                              ),
                              SizedBox(width: gap),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (labelWidth - 16 - gap).clamp(
                                    48.0,
                                    labelWidth,
                                  ),
                                ),
                                child: AutoSizeText(
                                  property['label']!.toString(),
                                  textScaleFactor: 1.0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : lightInkMuted,
                                    height: 1.15,
                                  ),
                                  textAlign: isDamagedParts
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  maxLines: 2,
                                  minFontSize: 8,
                                  stepGranularity: 0.5,
                                  overflow: TextOverflow.clip,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(
                    width: columnWidth,
                    child: _buildCellValue(context, cars[1], property),
                  ),
                ] else ...[
                  SizedBox(
                    width: labelWidth,
                    child: Center(
                      child: Builder(
                        builder: (context) {
                          final bool isDamagedParts =
                              (property['key']?.toString() ?? '') ==
                              'damaged_parts';
                          final double gap = isDamagedParts ? 2 : 4;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                (rows[i]['icon'] is IconData)
                                    ? (rows[i]['icon'] as IconData)
                                    : Icons.label_outline,
                                color: isDark ? Colors.white54 : lightInkMuted,
                                size: 16,
                              ),
                              SizedBox(width: gap),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: (labelWidth - 16 - gap).clamp(
                                    48.0,
                                    labelWidth,
                                  ),
                                ),
                                child: AutoSizeText(
                                  property['label']!.toString(),
                                  textScaleFactor: 1.0,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white70
                                        : lightInkMuted,
                                    height: 1.15,
                                  ),
                                  textAlign: isDamagedParts
                                      ? TextAlign.start
                                      : TextAlign.center,
                                  maxLines: 2,
                                  minFontSize: 8,
                                  stepGranularity: 0.5,
                                  overflow: TextOverflow.clip,
                                  softWrap: true,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                  Expanded(
                    child: Row(
                      children: cars
                          .map(
                            (car) => SizedBox(
                              width: columnWidth,
                              child: _buildCellValue(context, car, property),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }
    }
    return out;
  }

  Widget _buildCellValue(
    BuildContext context,
    Map<String, dynamic> car,
    Map<String, dynamic> property,
  ) {
    final text = _formatPropertyValue(context, car, property);
    final isBool =
        property['isBoolean'] == true || property['isBoolean'] == 'true';
    if (isBool) {
      final boolVal = text.toLowerCase() == 'yes';
      return Align(
        alignment: Alignment.center,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: boolVal
                ? Colors.green.withValues(alpha: 0.18)
                : Colors.red.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: boolVal
                  ? Colors.greenAccent.withValues(alpha: 0.3)
                  : Colors.redAccent.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            boolVal ? _yesTextGlobal(context) : _noTextGlobal(context),
            style: TextStyle(
              color: boolVal ? Colors.greenAccent : Colors.redAccent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Text(
      text,
      style: TextStyle(
        color: isDark ? Colors.white : AppThemes.darkHomeShellBackground,
        fontWeight: FontWeight.w600,
      ),
      textAlign: TextAlign.center,
    );
  }

  String _formatPropertyValue(
    BuildContext context,
    Map<String, dynamic> car,
    Map<String, dynamic> property,
  ) {
    final key = property['key']!;
    final value = car[key];

    if (value == null) return '-';
    if (key == 'price') {
      return _formatCurrencyGlobal(context, value);
    }
    if (key == 'region_specs') {
      final c = value.toString().trim().toLowerCase();
      if (!isValidCarRegionSpecCode(c)) return '-';
      return carRegionSpecDisplayLabel(c);
    }

    if (property['isBoolean'] == true || property['isBoolean'] == 'true') {
      return value == true || value == 'true'
          ? _yesTextGlobal(context)
          : _noTextGlobal(context);
    }

    final suffix = property['suffix'] ?? '';
    final String raw = value.toString();
    // Translate known categorical fields
    const translatableKeys = {
      'condition',
      'transmission',
      'fuel_type',
      'body_type',
      'drive_type',
      'color',
      'city',
      'title_status',
    };
    if (translatableKeys.contains(key)) {
      final translated = _translateValueGlobal(context, raw) ?? raw;
      return translated + (suffix?.toString() ?? '');
    }
    // Localize digits for numeric-like strings
    return _localizeDigitsGlobal(context, raw + (suffix?.toString() ?? ''));
  }
}
