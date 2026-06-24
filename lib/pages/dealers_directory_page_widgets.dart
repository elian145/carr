part of 'dealers_directory_page.dart';

mixin _DealersDirectoryPageWidgets on _DealersDirectoryPageLoad {
  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final focused = _searchFocus.hasFocus;

    // One flat surface inside the border — avoid a second “grey panel” behind the text.
    final fill = isLight
        ? AppThemes.lightAppBackground
        : Color.alphaBlend(
            Colors.white.withValues(alpha: 0.07),
            AppThemes.darkHomeShellBackground,
          );

    final borderColor = focused
        ? _DealersDirectoryPageFields._brandOrange
        : scheme.outline.withValues(alpha: isLight ? 0.45 : 0.35);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: borderColor,
              width: focused ? 2 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isLight
                    ? _DealersDirectoryPageFields._brandOrange.withValues(alpha: focused ? 0.12 : 0.04)
                    : Colors.black.withValues(alpha: 0.45),
                blurRadius: focused ? 16 : 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(19),
            child: Row(
              children: [
                const SizedBox(width: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: _DealersDirectoryPageFields._brandOrange.withValues(alpha: isLight ? 0.1 : 0.18),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.search_rounded,
                      color: _DealersDirectoryPageFields._brandOrange,
                      size: 22,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: _query,
                    focusNode: _searchFocus,
                    textInputAction: TextInputAction.search,
                    cursorColor: _DealersDirectoryPageFields._brandOrange,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Colors.transparent,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      isDense: true,
                      hintText: _tr(
                        'Search by name or location',
                        ar: 'ابحث بالاسم أو الموقع',
                        ku: 'گەڕان بە ناو یان شوێن',
                      ),
                      hintStyle: GoogleFonts.orbitron(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: isLight
                            ? const Color(0xFF5C5C5C)
                            : scheme.onSurfaceVariant.withValues(alpha: 0.9),
                        letterSpacing: 0.2,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(context)
                                  .deleteButtonTooltip,
                              icon: Icon(
                                Icons.close_rounded,
                                color: scheme.onSurfaceVariant,
                                size: 22,
                              ),
                              onPressed: () {
                                _query.clear();
                                _searchFocus.requestFocus();
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
    );
  }

  Widget _dealerCard(BuildContext context, Map<String, dynamic> d) {
    final id = (d['id'] ?? '').toString().trim();
    final name = (d['dealership_name'] ?? '').toString().trim();
    final location = (d['dealership_location'] ?? '').toString().trim();
    final cover = _coverUrl(d);
    final logo = _logoUrl(d);
    final scheme = Theme.of(context).colorScheme;
    final isLight = Theme.of(context).brightness == Brightness.light;

    void openProfile() {
      if (id.isEmpty) return;
      Navigator.pushNamed(
        context,
        '/dealer/profile',
        arguments: {'dealerPublicId': id},
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: isLight
              ? Border.all(
                  color: scheme.outlineVariant,
                  width: 1,
                )
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          elevation: isLight ? 0 : 1,
          shadowColor: Colors.black26,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: openProfile,
            child: SizedBox(
              height: 200,
              width: double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: cover.isNotEmpty
                        ? Image.network(
                            cover,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorBuilder: (_, _, _) => ColoredBox(
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.storefront,
                                size: 56,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ColoredBox(
                            color: scheme.surfaceContainerHighest,
                            child: Center(
                              child: Icon(
                                Icons.storefront,
                                size: 56,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                  ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.45),
                            Colors.black.withValues(alpha: 0.78),
                          ],
                          stops: const [0.0, 0.35, 0.62, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Material(
                          elevation: 4,
                          shadowColor: Colors.black45,
                          shape: const CircleBorder(),
                          clipBehavior: Clip.antiAlias,
                          child: CircleAvatar(
                            radius: 30,
                            backgroundColor: scheme.surface,
                            child: CircleAvatar(
                              radius: 26,
                              backgroundColor: scheme.surfaceContainerHighest,
                              backgroundImage:
                                  logo.isNotEmpty ? NetworkImage(logo) : null,
                              child: logo.isEmpty
                                  ? Icon(
                                      Icons.business,
                                      color: scheme.onSurfaceVariant,
                                      size: 28,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                name.isNotEmpty ? name : id,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      shadows: const [
                                        Shadow(
                                          blurRadius: 8,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                              ),
                              if (location.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  location,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: 0.9,
                                        ),
                                        shadows: const [
                                          Shadow(
                                            blurRadius: 6,
                                            color: Colors.black54,
                                          ),
                                        ],
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
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
}
