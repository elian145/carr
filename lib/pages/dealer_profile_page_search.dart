part of 'dealer_profile_page.dart';

extension _DealerProfilePageSearch on _DealerProfilePageState {
  Widget _buildDealerSearchAppBarAction(bool isLight) {
    final searchPillBg = isLight
        ? AppColors.brandOrange.withValues(alpha: 0.10)
        : Colors.white.withValues(alpha: 0.18);
    final searchPillBorder = isLight
        ? AppColors.brandOrange.withValues(alpha: 0.45)
        : Colors.white.withValues(alpha: 0.35);
    final searchPillFg = isLight ? AppColors.brandOrange : Colors.white;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: searchPillBg,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          key: const Key('dealerInventorySearchAction'),
          onTap: _openDealerListingSearch,
          borderRadius: BorderRadius.circular(20),
          splashColor: searchPillFg.withValues(alpha: 0.2),
          highlightColor: searchPillFg.withValues(alpha: 0.12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: searchPillBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_rounded, color: searchPillFg, size: 18),
                const SizedBox(width: 6),
                Text(
                  AppLocalizations.of(context)!.homeSearchHeading,
                  style: TextStyle(
                    color: searchPillFg,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDealerInventorySearchBar(bool isLight) {
    final loc = AppLocalizations.of(context)!;
    final barBg = isLight
        ? Colors.white
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.06),
            AppThemes.darkHomeShellBackground,
          );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Card(
          key: const Key('dealerInventorySearchBar'),
          elevation: isLight ? 6 : 12,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: isLight
                ? const BorderSide(color: Color(0xFFCACACA), width: 1)
                : BorderSide.none,
          ),
          color: barBg,
          surfaceTintColor: Colors.transparent,
          shadowColor: isLight ? Colors.black38 : Colors.black54,
          child: InkWell(
            onTap: _openDealerListingSearch,
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.search, color: AppColors.brandOrange, size: 22),
                  const SizedBox(width: 7),
                  Text(
                    loc.homeSearchHeading,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.visible,
                    style: GoogleFonts.orbitron(
                      color: AppColors.brandOrange,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDealerListingsToolbar() {
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          ListingSortButton(
            key: const Key('dealerInventorySortButton'),
            tooltip: loc.sortBy,
            active: _selectedSortBy != null && _selectedSortBy!.isNotEmpty,
            onSelected: _setDealerSortBy,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: '',
                child: Text(loc.defaultSort),
              ),
              ...localizedListingSortOptions(context).skip(1).map(
                    (s) => PopupMenuItem(value: s, child: Text(s)),
                  ),
            ],
          ),
          ValueListenableBuilder<int>(
            valueListenable: ListingLayoutPrefs.columns,
            builder: (context, cols, _) {
              return ListingLayoutToggle(
                columns: cols == 1 ? 1 : 2,
                onChanged: ListingLayoutPrefs.setColumns,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDealerActiveFiltersBar() {
    final chipFilters = _searchFilters.copyWith(
      sortByUi: _selectedSortBy,
      clearSortByUi: _selectedSortBy == null || _selectedSortBy!.trim().isEmpty,
    );
    if (!chipFilters.hasActiveFilters) {
      return const SizedBox.shrink();
    }
    final chips = buildLocalizedHomeFilterChips(
      context,
      filters: chipFilters,
      onClear: _clearDealerSearchFilter,
    );
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: SizedBox(
        height: 28,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: chips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 6),
          itemBuilder: (context, index) => chips[index],
        ),
      ),
    );
  }
}
