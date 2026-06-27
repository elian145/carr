part of 'home_flow.dart';

mixin _HomePageSliversSearchBar on _HomePageSearchFiltersPageUi {
  Widget _buildHomeSearchCityBarSliver(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Builder(
              builder: (context) {
                final loc = AppLocalizations.of(context)!;
                const allKey = '__all_cities__';
                final isAll = selectedCity == null ||
                    selectedCity!.trim().isEmpty ||
                    selectedCity == 'Any';
                final display = isAll
                    ? loc.allCities
                    : (_translateValueGlobal(context, selectedCity) ??
                        selectedCity!);

                Widget cityIconLabel() {
                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerEnd,
                    child: Row(
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
                  builder: (context, constraints) {
                    final cityMaxW =
                        (constraints.maxWidth * 0.46).clamp(140.0, 240.0);
                    return Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _openHomeSearchFiltersPage(context),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Row(
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
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.orbitron(
                                        color: const Color(0xFFFF6B00),
                                        fontWeight: FontWeight.bold,
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
                          constraints: BoxConstraints(maxWidth: cityMaxW),
                          child: SizedBox(
                            height: 34,
                            child: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: PopupMenuButton<String>(
                                tooltip: '',
                                position: PopupMenuPosition.under,
                                offset: const Offset(0, 6),
                                color:
                                    Colors.grey[900]?.withValues(alpha: 0.98),
                                splashRadius: 18,
                                onSelected: (value) {
                                  setState(() {
                                    selectedCity =
                                        value == allKey ? null : value;
                                  });
                                  onFilterChanged();
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem<String>(
                                    value: allKey,
                                    child: Text(
                                      loc.allCities,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 14,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  ...cities
                                      .where((x) => x != 'Any')
                                      .map(
                                        (city) => PopupMenuItem<String>(
                                          value: city,
                                          child: Text(
                                            _translateValueGlobal(
                                                  context,
                                                  city,
                                                ) ??
                                                city,
                                            style: GoogleFonts.orbitron(
                                              fontSize: 14,
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                ],
                                child: Padding(
                                  padding: const EdgeInsetsDirectional.only(
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
          ),
        ),
      ),
    );
  }

  Widget _buildHomeActiveFiltersSliver(BuildContext context) {
    if (!_hasActiveFilters()) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    final chips = _buildActiveFilterChips();
    if (chips.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: SizedBox(
          height: 30,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: chips.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (context, index) => chips[index],
          ),
        ),
      ),
    );
  }
}
