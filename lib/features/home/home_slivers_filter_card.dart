part of 'home_flow.dart';

mixin _HomePageSliversFilterCard on _HomePageMoreFiltersDialog {
  Widget _buildHomeFilterCardSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8.0,
          vertical: 8.0,
        ),
        child: Card(
          elevation: 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          color: Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          ),
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.black54,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (context) {
                    final loc = AppLocalizations.of(context)!;
                    const allKey = '__all_cities__';
                    final isAll = (selectedCity == null ||
                        selectedCity!.trim().isEmpty ||
                        selectedCity == 'Any');
                    final display = isAll
                        ? loc.allCities
                        : (_translateValueGlobal(
                                context, selectedCity) ??
                            selectedCity!);

                    Widget cityIconLabel() {
                      return FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Row(
                          // Keep icon+text visually consistent in RTL/LTR.
                          textDirection: ui.TextDirection.ltr,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_city,
                              size: 16,
                              color: Color(0xFFFF6B00),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              display,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: GoogleFonts.orbitron(
                                fontSize: 14,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return LayoutBuilder(
                      builder: (context, c) {
                        final maxW = c.maxWidth;
                        final cityMaxW = (maxW * 0.46)
                            .clamp(140.0, 240.0);
                        return Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    _showSearchDialog(context),
                                child: Align(
                                  // RTL: pins to the right; LTR: pins to the left.
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Row(
                                    // Keep icon+text visually consistent in RTL/LTR.
                                    textDirection: ui.TextDirection.ltr,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.search,
                                        color: Color(0xFFFF6B00),
                                      ),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          loc.homeSearchHeading,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: GoogleFonts.orbitron(
                                            color: const Color(
                                              0xFFFF6B00,
                                            ),
                                            fontWeight:
                                                FontWeight.bold,
                                            fontSize: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: cityMaxW,
                              ),
                              child: SizedBox(
                                height: 34,
                                child: Align(
                                  alignment: AlignmentDirectional
                                      .centerEnd,
                                  child: PopupMenuButton<String>(
                                    tooltip: '',
                                    position:
                                        PopupMenuPosition.under,
                                    offset: const Offset(0, 6),
                                    color: Colors.grey[900]
                                        ?.withValues(alpha: 0.98),
                                    splashRadius: 18,
                                    onSelected: (value) {
                                      setState(() {
                                        selectedCity =
                                            value == allKey
                                                ? null
                                                : value;
                                      });
                                      onFilterChanged();
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem<String>(
                                        value: allKey,
                                        child: Text(
                                          loc.allCities,
                                          style: GoogleFonts
                                              .orbitron(
                                            fontSize: 14,
                                            color: Colors.white,
                                            fontWeight:
                                                FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      ...cities
                                          .where(
                                            (x) => x != 'Any',
                                          )
                                          .map(
                                            (c) =>
                                                PopupMenuItem<
                                                    String>(
                                              value: c,
                                              child: Text(
                                                (_translateValueGlobal(
                                                        context, c) ??
                                                    c),
                                                style: GoogleFonts
                                                    .orbitron(
                                                  fontSize: 14,
                                                  color:
                                                      Colors.white,
                                                  fontWeight:
                                                      FontWeight
                                                          .bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                    ],
                                    child: Padding(
                                      padding: const EdgeInsetsDirectional
                                          .only(
                                        start: 0,
                                        top: 6,
                                        bottom: 6,
                                        end: 8,
                                      ),
                                      child: cityIconLabel(),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
                SizedBox(height: 16),
                _buildHomeVehicleFilterRow(context),
                SizedBox(height: 8),
                // Active Filters Display
                if (_hasActiveFilters())
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.filter_list,
                                  color: Color(0xFFFF6B00),
                                  size: 16,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  AppLocalizations.of(
                                    context,
                                  )!.activeFilters,
                                  style: GoogleFonts.orbitron(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: _clearAllFilters,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.red
                                          .withValues(alpha: 0.2),
                                      borderRadius:
                                          BorderRadius.circular(
                                            12,
                                          ),
                                      border: Border.all(
                                        color: Colors.red,
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize:
                                          MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.clear,
                                          color: Colors.red,
                                          size: 12,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.clearFilters,
                                          style:
                                              GoogleFonts.orbitron(
                                                fontSize: 10,
                                                color: Colors.red,
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                GestureDetector(
                                  onTap: _saveCurrentSearch,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Color(
                                        0xFFFF6B00,
                                      ).withValues(alpha: 0.15),
                                      borderRadius:
                                          BorderRadius.circular(
                                            12,
                                          ),
                                      border: Border.all(
                                        color: Color(0xFFFF6B00),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize:
                                          MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons
                                              .bookmark_add_outlined,
                                          color: Color(
                                            0xFFFF6B00,
                                          ),
                                          size: 12,
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.save,
                                          style:
                                              GoogleFonts.orbitron(
                                                fontSize: 10,
                                                color: Color(
                                                  0xFFFF6B00,
                                                ),
                                                fontWeight:
                                                    FontWeight
                                                        .bold,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ..._buildActiveFilterChips(),
                          ],
                        ),
                      ],
                    ),
                  ),
                SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 36,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFF6B00),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 0,
                      ),
                      minimumSize: Size(0, 32),
                    ),
                    icon: Icon(Icons.tune, size: 18),
                    label: Text(
                      AppLocalizations.of(context)!.moreFilters,
                      style: GoogleFonts.orbitron(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () => _showMoreFiltersDialog(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
