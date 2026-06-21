part of 'carzo_pages.dart';

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
          IconButton(
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
                          '${c['title'] ?? ''} • ${c['year'] ?? ''} • ${c['price'] ?? ''}',
                    )
                    .join('\n');
                if (text.trim().isNotEmpty) {
                  SharePlus.instance.share(ShareParams(text: text));
                }
              } catch (e, st) { logNonFatal(e, st); }
            },
            icon: Icon(Icons.share_outlined),
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
                                  OutlinedButton.icon(
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

/* Legacy AddListingPage implementation removed - begin (commented out)
  final _formKey = GlobalKey<FormState>();
  String? selectedBrand;
  String? selectedModel;
  String? selectedYear;
  String? selectedMinYear;
  String? selectedMaxYear;
  String? selectedPrice;
  String? selectedMinPrice;
  String? selectedMaxPrice;
  String? selectedMileage;
  String? selectedMinMileage;
  String? selectedMaxMileage;
  String? selectedCondition;
  String? selectedTransmission;
  String? selectedFuelType;
  String? selectedBodyType;
  String? selectedColor;
  String? selectedTrim;
  String? selectedDriveType;
  String? selectedCylinderCount;
  String? selectedSeating;
  String? selectedEngineSize;
  String? selectedCity;
  String? selectedTitleStatus;
  String? selectedDamagedParts;
  String? contactPhone;
  bool isQuickSell = false;

  // For image picker
  final ImagePicker _imagePicker = ImagePicker();
  List<XFile> _selectedImages = [];
  Future<void> _pickImages() async {
    try {
      // Upload full-resolution images to improve YOLO/OCR accuracy
      final files = await _imagePicker.pickMultiImage();
      if (files.isNotEmpty) {
        setState(() {
          _selectedImages = files;
        });
      }
    } catch (e, st) { logNonFatal(e, st); }
  }

  // For video picker
  List<XFile> _selectedVideos = [];
  Future<void> _pickVideos() async {
    try {
      final file = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: Duration(minutes: 5),
      );
      if (file != null) {
        setState(() {
          _selectedVideos.add(file);
        });
      }
    } catch (e, st) { logNonFatal(e, st); }
  }
  
  // Toggle states for unified filters
  bool isPriceDropdown = true;
  bool isYearDropdown = true;
  bool isMileageDropdown = true;

  // Use the same options as HomePage
  final List<String> addBrands = [
    'Toyota', 'Volkswagen', 'Ford', 'Honda', 'Hyundai', 'Nissan', 'Chevrolet', 'Kia', 'Mercedes-Benz', 'BMW', 'Audi', 'Lexus', 'Mazda', 'Subaru', 'Volvo', 'Jeep', 'RAM', 'GMC', 'Buick', 'Cadillac', 'Lincoln', 'Mitsubishi', 'Acura', 'Infiniti', 'Tesla', 'Mini', 'Porsche', 'Land Rover', 'Jaguar', 'Fiat', 'Renault', 'Peugeot', 'CitroÃ«n', 'Å koda', 'SEAT', 'Dacia', 'Chery', 'BYD', 'Great Wall', 'FAW', 'Roewe', 'Proton', 'Perodua', 'Tata', 'Mahindra', 'Lada', 'ZAZ', 'Daewoo', 'SsangYong', 'Changan', 'Haval', 'Wuling', 'Baojun', 'Nio', 'XPeng', 'Li Auto', 'VinFast', 'Ferrari', 'Lamborghini', 'Bentley', 'Rolls-Royce', 'Aston Martin', 'McLaren', 'Maserati', 'Bugatti', 'Pagani', 'Koenigsegg', 'Polestar', 'Rivian', 'Lucid', 'Alfa Romeo', 'Lancia', 'Abarth', 'Opel', 'DS', 'MAN', 'Iran Khodro', 'Genesis', 'Isuzu', 'Datsun', 'JAC Motors', 'JAC Trucks', 'KTM', 'Alpina', 'Brabus', 'Mansory', 'Bestune', 'Hongqi', 'Dongfeng', 'FAW Jiefang', 'Foton', 'Leapmotor', 'GAC', 'SAIC', 'MG', 'Vauxhall', 'Smart'
  ];
  final Map<String, List<String>> models = {
    'BMW': ['X3', 'X5', 'X7', '3 Series', '5 Series', '7 Series', 'M3', 'M5', 'X1', 'X6'],
    'Mercedes-Benz': ['C-Class', 'E-Class', 'S-Class', 'GLC', 'GLE', 'GLS', 'A-Class', 'CLA', 'GLA', 'AMG GT'],
    'Audi': ['A3', 'A4', 'A6', 'A8', 'Q3', 'Q5', 'Q7', 'Q8', 'RS6', 'TT'],
    'Toyota': ['Camry', 'Corolla', 'RAV4', 'Highlander', 'Tacoma', 'Tundra', 'Prius', 'Avalon', '4Runner', 'Sequoia'],
    'Honda': ['Civic', 'Accord', 'CR-V', 'Pilot', 'Ridgeline', 'Odyssey', 'HR-V', 'Passport', 'Insight', 'Clarity'],
    'Nissan': ['Altima', 'Maxima', 'Rogue', 'Murano', 'Pathfinder', 'Frontier', 'Titan', 'Leaf', 'Sentra', 'Versa'],
    'Ford': ['F-150', 'Mustang', 'Explorer', 'Escape', 'Edge', 'Ranger', 'Bronco', 'Mach-E', 'Focus', 'Fusion'],
    'Chevrolet': ['Silverado', 'Camaro', 'Equinox', 'Tahoe', 'Suburban', 'Colorado', 'Corvette', 'Malibu', 'Cruze', 'Traverse'],
    'Hyundai': ['Elantra', 'Sonata', 'Tucson', 'Santa Fe', 'Palisade', 'Kona', 'Venue', 'Accent', 'Veloster', 'Ioniq'],
    'Kia': ['Forte', 'K5', 'Sportage', 'Telluride', 'Sorento', 'Soul', 'Rio', 'Stinger', 'EV6', 'Niro']
  };
// Legacy AddListingPage implementation removed - end
*/
// @override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: Text(AppLocalizations.of(context)!.addListingTitle),
      automaticallyImplyLeading: false,
      actions: [const ThemeToggleWidget(), buildLanguageMenu()],
    ),
    /* Legacy AddListingPage UI removed
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              GestureDetector(
                onTap: _pickBrand,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: AppLocalizations.of(context)!.brandLabel,
                    border: OutlineInputBorder(),
                  ),
                  child: Row(
                    children: [
                      if (selectedBrand != null)
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: CachedNetworkImage(
                                imageUrl: getApiBase() + '/static/images/brands/' + (brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')) + '.png',
                                placeholder: (context, url) => SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
                                errorWidget: (context, url, error) => Icon(Icons.directions_car, size: 22, color: Color(0xFFFF6B00)),
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text(
                              CarNameTranslations.getLocalizedBrand(context, selectedBrand).isNotEmpty
                                  ? CarNameTranslations.getLocalizedBrand(context, selectedBrand)
                                  : selectedBrand!,
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        )
                      else
                        Text(AppLocalizations.of(context)!.tapToSelectBrand, style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              FormField<String>(
                validator: (_) => (selectedModel == null || selectedModel!.isEmpty) ? AppLocalizations.of(context)!.modelLabel : null,
                builder: (state) => GestureDetector(
                  onTap: _pickModel,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.modelLabel,
                      border: OutlineInputBorder(),
                      errorText: state.errorText,
                    ),
                    child: Text(
                      selectedModel != null
                          ? (CarNameTranslations.getLocalizedModel(context, selectedBrand, selectedModel).isNotEmpty
                              ? CarNameTranslations.getLocalizedModel(context, selectedBrand, selectedModel)
                              : selectedModel!)
                          : AppLocalizations.of(context)!.tapToSelectBrand,
                      style: TextStyle(color: selectedModel == null ? Colors.grey : Colors.white),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Trim Dropdown (dependent on brand + model) placed under Model
              FormField<String>(
                validator: (_) => (selectedTrim == null || selectedTrim!.isEmpty) ? AppLocalizations.of(context)!.trimLabel : null,
                builder: (state) => GestureDetector(
                  onTap: _pickTrimOption,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: AppLocalizations.of(context)!.trimLabel,
                      border: OutlineInputBorder(),
                      errorText: state.errorText,
                    ),
                    child: Text(
                      selectedTrim ?? AppLocalizations.of(context)!.anyOption,
                      style: TextStyle(color: selectedTrim == null ? Colors.grey : Colors.white),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 12),
              Row(
                  children: [
                    Expanded(
                      child: isYearDropdown
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              value: (selectedMinYear != null && selectedMinYear!.isNotEmpty && years.contains(selectedMinYear)) ? selectedMinYear : null,
                              items: years.map((y) => DropdownMenuItem(value: y, child: Text(_localizeDigitsGlobal(context, y)))).toList(),
                              onChanged: (v) { setState(() { selectedMinYear = v; selectedMaxYear = v; }); _persistFilters(); },
                            )
                          : TextFormField(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) { setState(() { selectedMinYear = v; selectedMaxYear = v; }); _persistFilters(); },
                            ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => isYearDropdown = !isYearDropdown),
                      icon: Icon(isYearDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
              ),
              SizedBox(height: 12),
              SizedBox(height: 12),
              Row(
                  children: [
                    Expanded(
                      child: isPriceDropdown
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              value: (selectedMinPrice != null && selectedMinPrice!.isNotEmpty) ? selectedMinPrice : null,
                              items: [
                                ...List.generate(600, (i) => (500 + i * 500).toString()).map((p) => DropdownMenuItem(value: p, child: Text(_formatCurrencyGlobal(context, p)))).toList(),
                                ...List.generate(171, (i) => (300000 + (i + 1) * 10000).toString()).map((p) => DropdownMenuItem(value: p, child: Text(_formatCurrencyGlobal(context, p)))).toList(),
                              ],
                              onChanged: (v) => setState(() { selectedMinPrice = v; selectedMaxPrice = v; }),
                            )
                          : TextFormField(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => setState(() { selectedMinPrice = v; selectedMaxPrice = v; }),
                            ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => isPriceDropdown = !isPriceDropdown),
                      icon: Icon(isPriceDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
              ),
              SizedBox(height: 12),
              SizedBox(height: 12),
              Row(
                  children: [
                    Expanded(
                      child: isMileageDropdown
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              value: (selectedMaxMileage != null && selectedMaxMileage!.isNotEmpty) ? selectedMaxMileage : null,
                              items: [
                                ...[
                                  for (int m = 0; m <= 100000; m += 1000) m,
                                  for (int m = 105000; m <= 300000; m += 5000) m,
                                ]
                                    .map((m) => DropdownMenuItem(
                                          value: m.toString(),
                                          child: Text(_localizeDigitsGlobal(context, m.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (mm) => '${mm[1]},'))),
                                        ))
                                    .toList(),
                              ],
                              onChanged: (v) => setState(() { selectedMaxMileage = v; }),
                              validator: (v) => (v == null || v.isEmpty) ? AppLocalizations.of(context)!.mileageLabel : null,
                            )
                          : TextFormField(
                              decoration: InputDecoration(
                                hintText: AppLocalizations.of(context)!.any,
                                border: OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (v) => setState(() { selectedMaxMileage = v; }),
                            ),
                    ),
                    SizedBox(width: 8),
                    IconButton(
                      onPressed: () => setState(() => isMileageDropdown = !isMileageDropdown),
                      icon: Icon(isMileageDropdown ? Icons.edit : Icons.list, color: Color(0xFFFF6B00)),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.grey.withValues(alpha: 0.2),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.conditionLabel),
                value: selectedCondition != null && conditions.contains(selectedCondition) ? selectedCondition : null,
                items: conditions.map((c) => DropdownMenuItem(value: c, child: Text(_translateValueGlobal(context, c) ?? c))).toList(),
                onChanged: (v) {
                  setState(() => selectedCondition = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.conditionLabel : null,
              ),
              SizedBox(height: 12),
              // Title Status
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.titleStatus),
                value: selectedTitleStatus,
                items: [
                  DropdownMenuItem(value: 'clean', child: Text(AppLocalizations.of(context)!.value_title_clean)),
                  DropdownMenuItem(value: 'damaged', child: Text(AppLocalizations.of(context)!.value_title_damaged)),
                ],
                onChanged: (v) {
                  setState(() {
                    selectedTitleStatus = v;
                    if (selectedTitleStatus != 'damaged') {
                      selectedDamagedParts = null;
                    }
                  });
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.titleStatus : null,
              ),
              if (selectedTitleStatus == 'damaged') ...[
                SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: AppLocalizations.of(context)!.damagedParts),
                  value: selectedDamagedParts,
                  items: [
                    ...List.generate(15, (i) => (i + 1).toString()).map((p) => DropdownMenuItem(value: p, child: Text(_localizeDigitsGlobal(context, p))))
                  ],
                  onChanged: (v) => setState(() => selectedDamagedParts = v),
                  validator: (v) => (selectedTitleStatus == 'damaged' && (v == null || v.isEmpty)) ? AppLocalizations.of(context)!.damagedParts : null,
                ),
              ],
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.transmissionLabel),
                value: selectedTransmission != null && transmissions.contains(selectedTransmission) ? selectedTransmission : null,
                items: transmissions.map((t) => DropdownMenuItem(value: t, child: Text(_translateValueGlobal(context, t) ?? t))).toList(),
                onChanged: (v) {
                  setState(() => selectedTransmission = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.transmissionLabel : null,
              ),
              SizedBox(height: 12),
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.fuelTypeLabel),
                value: selectedFuelType != null && fuelTypes.contains(selectedFuelType) ? selectedFuelType : null,
                items: fuelTypes.map((f) => DropdownMenuItem(value: f, child: Text(_translateValueGlobal(context, f) ?? f))).toList(),
                onChanged: (v) {
                  setState(() => selectedFuelType = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.fuelTypeLabel : null,
              ),
              SizedBox(height: 12),
              // Body Type Selection Button
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final bodyType = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return Dialog(
                          backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Container(
                            width: 400,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(AppLocalizations.of(context)!.selectBodyType, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                    IconButton(
                                      icon: Icon(Icons.close, color: Colors.white),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10),
                                SizedBox(
                                  height: 300,
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics: BouncingScrollPhysics(),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 1.2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: bodyTypes.length,
                                    itemBuilder: (context, index) {
                                      final bodyTypeName = bodyTypes[index];
                                      final asset = _getBodyTypeAsset(bodyTypeName);
                                      
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          Navigator.pop(context, bodyTypeName);
                                          final parent = context.findAncestorStateOfType<_SellCarPageState>();
                                          if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          padding: EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 56,
                                                height: 56,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.white24, width: 1),
                                                ),
                                                child: Padding(
                                                  padding: EdgeInsets.all(8),
                                                  child: FittedBox(
                                                    fit: BoxFit.contain,
                                                    child: _buildBodyTypeImage(asset),
                                                  ),
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                _translateValueGlobal(context, bodyTypeName) ?? bodyTypeName,
                                                style: GoogleFonts.orbitron(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    if (bodyType != null) {
                      setState(() {
                        selectedBodyType = bodyType == 'Any' ? null : bodyType;
                      });
                      final parent = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (selectedBodyType != null) ...[
                              Container(
                                width: 24,
                                height: 24,
                                margin: EdgeInsets.only(right: 8),
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: _buildBodyTypeImage(_getBodyTypeAsset(selectedBodyType!)),
                                ),
                              ),
                          ],
                          Text(
                            selectedBodyType != null ? _translateValueGlobal(context, selectedBodyType!) ?? selectedBodyType! : AppLocalizations.of(context)!.anyOption,
                            style: TextStyle(
                              color: selectedBodyType != null ? Color(0xFFFF6B00) : Colors.white,
                              fontSize: 16,
                              fontWeight: selectedBodyType != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Color Selection Button
              Container(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final color = await showDialog<String>(
                      context: context,
                      builder: (context) {
                        return Dialog(
                          backgroundColor: Colors.grey[900]?.withValues(alpha: 0.98),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Container(
                            width: 400,
                            padding: EdgeInsets.all(20),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(AppLocalizations.of(context)!.selectColor, style: GoogleFonts.orbitron(color: Color(0xFFFF6B00), fontWeight: FontWeight.bold, fontSize: 20)),
                                    IconButton(
                                      icon: Icon(Icons.close, color: Colors.white),
                                      onPressed: () => Navigator.pop(context),
                                    ),
                                  ],
                                ),
                                SizedBox(height: 10),
                                SizedBox(
                                  height: 300,
                                  child: GridView.builder(
                                    shrinkWrap: true,
                                    physics: BouncingScrollPhysics(),
                                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 3,
                                      childAspectRatio: 1.2,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                    ),
                                    itemCount: getAddCarAvailableColors().length,
                                    itemBuilder: (context, index) {
                                      final colorName = getAddCarAvailableColors()[index];
                                      Color colorValue = Colors.grey;
                                      
                                      // Map color names to actual colors
                                      switch (colorName.toLowerCase()) {
                                        case 'black':
                                          colorValue = Colors.black;
                                          break;
                                        case 'white':
                                          colorValue = Colors.white;
                                          break;
                                        case 'silver':
                                          colorValue = Colors.grey[300]!;
                                          break;
                                        case 'gray':
                                          colorValue = Colors.grey[600]!;
                                          break;
                                        case 'red':
                                          colorValue = Colors.red;
                                          break;
                                        case 'blue':
                                          colorValue = Colors.blue;
                                          break;
                                        case 'green':
                                          colorValue = Colors.green;
                                          break;
                                        case 'yellow':
                                          colorValue = Colors.yellow;
                                          break;
                                        case 'orange':
                                          colorValue = Colors.orange;
                                          break;
                                        case 'purple':
                                          colorValue = Colors.purple;
                                          break;
                                        case 'brown':
                                          colorValue = Colors.brown;
                                          break;
                                        case 'beige':
                                          colorValue = Color(0xFFF5F5DC);
                                          break;
                                        case 'gold':
                                          colorValue = Color(0xFFFFD700);
                                          break;
                                        default:
                                          colorValue = Colors.grey;
                                      }
                                      
                                      return InkWell(
                                        borderRadius: BorderRadius.circular(12),
                                        onTap: () {
                                          Navigator.pop(context, colorName);
                                          final parent = context.findAncestorStateOfType<_SellCarPageState>();
                                          if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                                        },
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(color: Colors.white24),
                                          ),
                                          padding: EdgeInsets.all(8),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 40,
                                                decoration: BoxDecoration(
                                                  color: colorValue,
                                                  borderRadius: BorderRadius.circular(8),
                                                  border: Border.all(color: Colors.white24, width: 2),
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Text(
                                                _translateValueGlobal(context, colorName) ?? colorName,
                                                style: GoogleFonts.orbitron(fontSize: 12, color: Colors.white, fontWeight: FontWeight.bold),
                                                textAlign: TextAlign.center,
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                    if (color != null) {
                      setState(() {
                        selectedColor = color == 'Any' ? null : color;
                      });
                      final parent = context.findAncestorStateOfType<_SellCarPageState>();
                      if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          if (selectedColor != null) ...[
                            Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: _getColorValue(selectedColor!),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white24, width: 1),
                              ),
                            ),
                            SizedBox(width: 8),
                          ],
                          Text(
                            selectedColor != null ? _translateValueGlobal(context, selectedColor!) ?? selectedColor! : AppLocalizations.of(context)!.anyOption,
                            style: TextStyle(
                              color: selectedColor != null ? Color(0xFFFF6B00) : Colors.white,
                              fontSize: 16,
                              fontWeight: selectedColor != null ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.arrow_drop_down, color: Colors.white),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 12),
              // Drive Type Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.driveType),
                value: selectedDriveType != null && getAddCarAvailableDriveTypes().contains(selectedDriveType) ? selectedDriveType : null,
                items: getAddCarAvailableDriveTypes().map((d) => DropdownMenuItem(value: d, child: Text(_translateValueGlobal(context, d) ?? d))).toList(),
                onChanged: (v) {
                  setState(() => selectedDriveType = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectDriveType : null,
              ),
              SizedBox(height: 12),
              // Cylinder Count Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cylinderCount),
                value: selectedCylinderCount != null && getAddCarAvailableCylinderCounts().contains(selectedCylinderCount) ? selectedCylinderCount : null,
                items: getAddCarAvailableCylinderCounts().map((c) => DropdownMenuItem(value: c, child: Text(_localizeDigitsGlobal(context, c)))).toList(),
                onChanged: (v) {
                  setState(() => selectedCylinderCount = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectCylinderCount : null,
              ),
              SizedBox(height: 12),
              // Seating Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.seating),
                value: selectedSeating != null && getAddCarAvailableSeatings().contains(selectedSeating) ? selectedSeating : null,
                items: getAddCarAvailableSeatings().map((s) => DropdownMenuItem(value: s, child: Text(_localizeDigitsGlobal(context, s)))).toList(),
                onChanged: (v) {
                  setState(() => selectedSeating = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectSeating : null,
              ),
              SizedBox(height: 12),
              // Engine Size Dropdown / Manual input
              Row(
                children: [
                  Expanded(
                    child: isInlineEngineSizeDropdown
                        ? DropdownButtonFormField<String>(
                            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.engineSizeL),
                            value: selectedEngineSize != null && getAddCarAvailableEngineSizes().contains(selectedEngineSize) ? selectedEngineSize : null,
                            items: getAddCarAvailableEngineSizes()
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      '${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              setState(() => selectedEngineSize = v);
                              final parent = context.findAncestorStateOfType<_SellCarPageState>();
                              if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                            },
                            validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectEngineSize : null,
                          )
                        : TextFormField(
                            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.engineSizeL),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => setState(() => selectedEngineSize = v.isEmpty ? null : v),
                            validator: (v) {
                              if (v == null || v.isEmpty) {
                                return AppLocalizations.of(context)!.selectEngineSize;
                              }
                              final parsed = double.tryParse(v);
                              if (parsed == null || parsed <= 0) {
                                return AppLocalizations.of(context)!.invalidField;
                              }
                              return null;
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => setState(() {
                      isInlineEngineSizeDropdown = !isInlineEngineSizeDropdown;
                    }),
                    icon: Icon(
                      isInlineEngineSizeDropdown ? Icons.edit : Icons.list,
                      color: const Color(0xFFFF6B00),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.grey.withValues(alpha: 0.2),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              // City Dropdown
              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: AppLocalizations.of(context)!.cityLabel),
                value: selectedCity != null && cities.contains(selectedCity) ? selectedCity : null,
                items: cities.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) {
                  setState(() => selectedCity = v);
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) => v == null || v.isEmpty ? AppLocalizations.of(context)!.selectCity : null,
              ),
              SizedBox(height: 12),
              TextFormField(
                decoration: InputDecoration(
                  labelText: AppLocalizations.of(context)!.whatsappLabel, 
                  hintText: '7XX XXX XXXX',
                  prefixText: '+964 ',
                  prefixStyle: TextStyle(
                    color: Color(0xFFFF6B00),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  services.LengthLimitingTextInputFormatter(10),
                ],
                onChanged: (v) {
                  setState(() => contactPhone = '+964' + v.trim());
                  final parent = context.findAncestorStateOfType<_SellCarPageState>();
                  if (parent != null) unawaited(parent._saveSellDraftSnapshot());
                },
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return AppLocalizations.of(context)!.enterWhatsAppNumber;
                  if (v.trim().length < 10) {
                    return _trLegacyText(
                      context,
                      'Please enter a valid phone number',
                      ar: 'يرجى إدخال رقم هاتف صحيح',
                      ku: 'تکایە ژمارەی دروست بنووسە',
                    );
                  }
                  return null;
                },
                onSaved: (_) {},
              ),
              SizedBox(height: 16),
              Text(_photosRequiredTitleGlobal(context), style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              if (_selectedImages.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._selectedImages.map((x) => Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.file(File(x.path), fit: BoxFit.cover),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedImages.remove(x);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ))
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _pickImages,
                  icon: Icon(Icons.photo_library),
                  label: Text(_selectedImages.isEmpty ? AppLocalizations.of(context)!.addPhotos : AppLocalizations.of(context)!.addMorePhotos),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 16),
              Text(_videosOptionalTitleGlobal(context), style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              if (_selectedVideos.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ..._selectedVideos.map((x) => Stack(
                      alignment: Alignment.topRight,
                      children: [
                        Container(
                          width: 90,
                          height: 90,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white24),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: FutureBuilder<String?>(
                            future: generateVideoThumbnail(x.path),
                            builder: (context, snapshot) {
                              if (snapshot.hasData && snapshot.data != null) {
                                return Stack(
                                  children: [
                                    Image.file(
                                      File(snapshot.data!),
                                      width: 90,
                                      height: 90,
                                      fit: BoxFit.cover,
                                    ),
                                    Center(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                return Stack(
                                  children: [
                                    Container(
                                      color: Colors.grey[800],
                                      child: Center(
                                        child: Icon(Icons.videocam, color: Colors.white, size: 32),
                                      ),
                                    ),
                                    Center(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: EdgeInsets.all(8),
                                        child: Icon(Icons.play_arrow, color: Colors.white, size: 24),
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _selectedVideos.remove(x);
                              });
                            },
                            child: Container(
                              decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        )
                      ],
                    ))
                  ],
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: ElevatedButton.icon(
                  onPressed: _pickVideos,
                  icon: Icon(Icons.videocam),
                  label: Text(
                    _selectedVideos.isEmpty
                        ? _trLegacyText(
                            context,
                            'Add Videos',
                            ar: 'إضافة فيديوهات',
                            ku: 'ڤیدیۆ زیاد بکە',
                          )
                        : _trLegacyText(
                            context,
                            'Add More Videos',
                            ar: 'إضافة المزيد من الفيديوهات',
                            ku: 'ڤیدیۆی زیاتر زیاد بکە',
                          ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              SizedBox(height: 24),
              // Quick Sell Option
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.flash_on, color: Colors.orange, size: 24),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _quickSellTextGlobal(context),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          Text(
                            _trLegacyText(
                              context,
                              'Enable this to make your listing stand out with a special banner',
                              ar: 'فعّل هذا الخيار ليظهر إعلانك بشارة خاصة',
                              ku:
                                  'ئەمە چالاک بکە بۆ ئەوەی ڕیکلامەکەت بە بانەری تایبەت دیار بێت',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: isQuickSell,
                      onChanged: (value) {
                        setState(() {
                          isQuickSell = value;
                        });
                      },
                      activeColor: Colors.orange,
                    ),
                  ],
                ),
              ),
              SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(Icons.add),
                label: Text(AppLocalizations.of(context)!.submitListing),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 16),
                  textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                onPressed: () async {
                  // Require authentication before allowing submission
                  final existingToken = ApiService.accessToken;
                  if (existingToken == null || existingToken.isEmpty) {
                    await showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(AppLocalizations.of(context)!.loginRequired),
                        content: Text(AppLocalizations.of(context)!.authenticationRequired),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              Navigator.pushNamed(context, '/login');
                            },
                            child: Text(AppLocalizations.of(context)!.navLogin),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(_cancelTextGlobal(context)),
                          ),
                        ],
                      ),
                    );
                    return;
                  }

                  if (!_formKey.currentState!.validate()) return;
                  
                  // Validate that at least one photo is selected
                  if (_selectedImages.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(_pleaseSelectPhotoTextGlobal(context)),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                  final brand = selectedBrand?.toString() ?? '';
                  final model = selectedModel?.toString() ?? '';
                  final trim = selectedTrim?.toString() ?? 'Base';
                  final year = int.tryParse(selectedMinYear ?? selectedYear ?? '') ?? DateTime.now().year;
                  final mileage = int.tryParse(selectedMaxMileage ?? '0') ?? 0;
                  final condition = (selectedCondition ?? 'Used').toLowerCase();
                  final transmission = (selectedTransmission ?? 'Automatic').toLowerCase();
                  final fuelType = (selectedFuelType ?? 'Gasoline').toLowerCase();
                  final color = (selectedColor ?? 'Black').toLowerCase();
                  final bodyType = (selectedBodyType ?? 'Sedan').toLowerCase();
                  final seating = int.tryParse(selectedSeating ?? '5') ?? 5;
                  final driveType = (selectedDriveType ?? 'fwd').toLowerCase();
                  final titleStatus = (selectedTitleStatus ?? 'clean').toLowerCase();
                  final damagedParts = titleStatus == 'damaged' ? int.tryParse(selectedDamagedParts ?? '') : null;
                  final cylinderCount = int.tryParse(selectedCylinderCount ?? '');
                  final engineSize = OnlineSpecVariant.parseLeadingEngineLiters(
                        selectedEngineSize ?? '',
                      ) ??
                      double.tryParse(selectedEngineSize ?? '');
                  final price = int.tryParse(selectedMinPrice ?? '');
                  final city = (selectedCity ?? 'Baghdad').toLowerCase();
                  final title = '$brand $model $trim'.trim();

                  final payload = {
                    'title': title,
                    'brand': brand.toLowerCase().replaceAll(' ', '-'),
                    'model': model,
                    'trim': trim,
                    'year': year,
                    'price': price,
                    'mileage': mileage,
                    'condition': condition,
                    'transmission': transmission,
                    'fuel_type': fuelType,
                    'color': color,
                    'body_type': bodyType,
                    'seating': seating,
                    'drive_type': driveType,
                    'title_status': titleStatus,
                    'damaged_parts': damagedParts,
                    'cylinder_count': cylinderCount,
                    'engine_size': engineSize,
                    'city': city,
                    'contact_phone': (contactPhone ?? '').trim(),
                    'is_quick_sell': isQuickSell,
                  };

                  try {
                    final result = await ApiService.createCar(payload);
                    final carMap = unwrapCarApiPayload(result);
                    final carId = listingPrimaryId(carMap);
                    if (_selectedImages.isNotEmpty) {
                      try {
                        final respJson = await ApiService.uploadCarImages(
                          carId,
                          _selectedImages,
                        );
                        final newPrimary = respJson['image_url']?.toString() ?? '';
                        if (newPrimary.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(_photosUploadedTextGlobal(context))),
                          );
                        }
                      } on ApiException catch (e) {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(AppLocalizations.of(context)!.error),
                            content: Text(
                              AppLocalizations.of(context)!.listingUploadPartialFail(e.statusCode) +
                                  (e.message.isNotEmpty ? '\n${e.message}' : ''),
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                            ],
                          ),
                        );
                      }
                    }

                    if (_selectedVideos.isNotEmpty) {
                      try {
                        await ApiService.uploadCarVideos(
                          carId,
                          _selectedVideos,
                          multipartFileBuilder: _buildVideoMultipartFile,
                        );
                      } on ApiException catch (e) {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(AppLocalizations.of(context)!.error),
                            content: Text('${AppLocalizations.of(context)!.error}: ${_localizeDigitsGlobal(context, e.statusCode.toString())}'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                            ],
                          ),
                        );
                      }
                    }

                    Navigator.pushReplacementNamed(context, '/');
                  } on ApiException catch (e) {
                    if (e.statusCode == 401 || e.statusCode == 403) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(AppLocalizations.of(context)!.authenticationRequired),
                          content: Text(AppLocalizations.of(context)!.loginRequired),
                          actions: [
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                Navigator.pushNamed(context, '/login');
                              },
                              child: Text(AppLocalizations.of(context)!.navLogin),
                            ),
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(_cancelTextGlobal(context))),
                          ],
                        ),
                      );
                    } else {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(AppLocalizations.of(context)!.error),
                          content: Text(AppLocalizations.of(context)!.failedToSubmitListing(e.message)),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                          ],
                        ),
                      );
                    }
                  } catch (e) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(AppLocalizations.of(context)!.error),
                        content: Text(AppLocalizations.of(context)!.couldNotSubmitListing),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text(AppLocalizations.of(context)!.ok)),
                        ],
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
      */
    extendBody: true,
    bottomNavigationBar: buildFloatingBottomNav(
      context,
      currentIndex: 0,
      onTap: (idx) {
        switch (idx) {
          case 0:
            _switchMainTabNoAnimation(context, '/');
            break;
          case 1:
            _switchMainTabNoAnimation(context, '/favorites');
            break;
          case 2:
            _switchMainTabNoAnimation(context, '/dealers');
            break;
          case 3:
            if (ApiService.accessToken == null ||
                ApiService.accessToken!.isEmpty) {
              Navigator.pushReplacementNamed(context, '/login');
            } else {
              _switchMainTabNoAnimation(context, '/profile');
            }
            break;
        }
      },
    ),
  );
}

// Removed stray closing brace that caused a syntax error

