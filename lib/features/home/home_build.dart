part of 'home_flow.dart';

mixin _HomePageBuild on _HomePageMoreFiltersDialog {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppLocalizations.of(context)!.appTitle,
          style: TextStyle(fontSize: 18),
        ),
        titleSpacing: NavigationToolbar.kMiddleSpacing,
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(
              end: NavigationToolbar.kMiddleSpacing,
            ),
            child: OutlinedButton.icon(
              onPressed: () {
                // Same as leaving Home via bottom nav: keep scroll offset for return.
                _persistCurrentHomeOffsetNow();
                // Match former bottom-nav Sell: shell swap + SellEntryRouterPage
                // (draft gate / resume / start fresh), not a raw SellCarPage push.
                _switchMainTabNoAnimation(context, '/sell');
              },
              icon: Icon(Icons.add, color: Colors.white),
              label: Text(
                AppLocalizations.of(context)!.sellButton,
                style: TextStyle(color: Colors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Colors.white70),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: EdgeInsets.symmetric(horizontal: 12),
              ),
            ),
          ),
        ],
      ),
      // Pull-to-refresh is already provided inside the main content via internal scrollables
      extendBody: true,
      bottomNavigationBar: buildFloatingBottomNav(
        context,
        currentIndex: 0,
        onTap: (idx) {
          if (idx != 0) {
            // Persist exact offset before route replacement to avoid stale restores.
            _persistCurrentHomeOffsetNow();
          }
          switch (idx) {
            case 0:
              _scrollHomeToTopAndResetCardImages();
              break;
            case 1:
              _switchMainTabNoAnimation(context, '/favorites');
              break;
            case 2:
              _switchMainTabNoAnimation(context, '/dealers');
              break;
            case 3:
              _switchMainTabNoAnimation(context, '/profile');
              break;
          }
        },
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            Container(
              decoration: AppThemes.shellBackgroundDecoration(
                Theme.of(context).brightness,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 0.0),
              child: CustomScrollView(
                controller: _homeScrollController,
                slivers: [
                  SliverToBoxAdapter(
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
                              Builder(
                                builder: (filterRowContext) {
                                  final isLightShell =
                                      Theme.of(filterRowContext).brightness ==
                                      Brightness.light;
                                  final dropdownMenuInk = isLightShell
                                      ? AppThemes.darkHomeShellBackground
                                      : Colors.white;
                                  const dropdownFieldInk = Colors.white;
                                  final dropdownMenuBg = isLightShell
                                      ? Colors.white
                                      : AppThemes.darkHomeShellBackground;
                                  return Row(
                                children: [
                                  // Brand selector styled like a form field for symmetry
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final brand = await showDialog<String>(
                                          context: context,
                                          builder: (context) {
                                            return Dialog(
                                              backgroundColor: Colors.grey[900]
                                                  ?.withValues(alpha: 0.98),
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              child: Container(
                                                width: 400,
                                                padding: EdgeInsets.all(20),
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .spaceBetween,
                                                      children: [
                                                        Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.selectBrand,
                                                          style:
                                                              GoogleFonts.orbitron(
                                                                color: Color(
                                                                  0xFFFF6B00,
                                                                ),
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                                fontSize: 20,
                                                              ),
                                                        ),
                                                        IconButton(
                                                          icon: Icon(
                                                            Icons.close,
                                                            color: Colors.white,
                                                          ),
                                                          onPressed: () =>
                                                              Navigator.pop(
                                                                context,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                    SizedBox(height: 10),
                                                    SizedBox(
                                                      height: 380,
                                                      child: GridView.builder(
                                                        shrinkWrap: true,
                                                        physics:
                                                            BouncingScrollPhysics(),
                                                        gridDelegate:
                                                            SliverGridDelegateWithFixedCrossAxisCount(
                                                              crossAxisCount: 4,
                                                              childAspectRatio:
                                                                  0.85,
                                                              crossAxisSpacing:
                                                                  10,
                                                              mainAxisSpacing:
                                                                  10,
                                                            ),
                                                        itemCount:
                                                            homeBrands.length,
                                                        itemBuilder: (context, index) {
                                                          final brand =
                                                              homeBrands[index];
                                                          final logoFile =
                                                              brandLogoFilenames[brand] ??
                                                              brand
                                                                  .toLowerCase()
                                                                  .replaceAll(
                                                                    ' ',
                                                                    '-',
                                                                  )
                                                                  .replaceAll(
                                                                    'Ã©',
                                                                    'e',
                                                                  )
                                                                  .replaceAll(
                                                                    'Ã¶',
                                                                    'o',
                                                                  );
                                                          final logoUrl =
                                                              '${getApiBase()}/static/images/brands/$logoFile.png';
                                                          return InkWell(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                            onTap: () =>
                                                                Navigator.pop(
                                                                  context,
                                                                  brand,
                                                                ),
                                                            child: Container(
                                                              decoration: BoxDecoration(
                                                                color: Colors
                                                                    .black
                                                                    .withValues(alpha: 
                                                                      0.15,
                                                                    ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                                border: Border.all(
                                                                  color: Colors
                                                                      .white24,
                                                                ),
                                                              ),
                                                              padding:
                                                                  EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              child: Column(
                                                                mainAxisAlignment:
                                                                    MainAxisAlignment
                                                                        .center,
                                                                children: [
                                                                  Container(
                                                                    width: 32,
                                                                    height: 32,
                                                                    padding:
                                                                        EdgeInsets.all(
                                                                          4,
                                                                        ),
                                                                    decoration: BoxDecoration(
                                                                      color: Colors
                                                                          .white,
                                                                      borderRadius:
                                                                          BorderRadius.circular(
                                                                            8,
                                                                          ),
                                                                    ),
                                                                    child: CachedNetworkImage(
                                                                      imageUrl:
                                                                          logoUrl,
                                                                      placeholder:
                                                                          (
                                                                            context,
                                                                            url,
                                                                          ) => SizedBox(
                                                                            width:
                                                                                24,
                                                                            height:
                                                                                24,
                                                                            child: CircularProgressIndicator(
                                                                              strokeWidth: 2,
                                                                            ),
                                                                          ),
                                                                      errorWidget:
                                                                          (
                                                                            context,
                                                                            url,
                                                                            error,
                                                                          ) => Icon(
                                                                            Icons.directions_car,
                                                                            size:
                                                                                22,
                                                                            color: Color(
                                                                              0xFFFF6B00,
                                                                            ),
                                                                          ),
                                                                      fit: BoxFit
                                                                          .contain,
                                                                    ),
                                                                  ),
                                                                  SizedBox(
                                                                    height: 4,
                                                                  ),
                                                                  Text(
                                                                    CarNameTranslations.getLocalizedBrand(
                                                                          context,
                                                                          brand,
                                                                        ).isNotEmpty
                                                                        ? CarNameTranslations.getLocalizedBrand(
                                                                            context,
                                                                            brand,
                                                                          )
                                                                        : brand,
                                                                    style: GoogleFonts.orbitron(
                                                                      fontSize:
                                                                          10,
                                                                      color: Colors
                                                                          .white,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .bold,
                                                                    ),
                                                                    textAlign:
                                                                        TextAlign
                                                                            .center,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
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
                                        if (brand != null) {
                                          setState(() {
                                            selectedBrand = brand;
                                            selectedModel = null;
                                            selectedTrim = null;
                                            clearFiltersOnVehicleChange();
                                          });
                                          onFilterChanged();
                                        }
                                      },
                                      child: InputDecorator(
                                        decoration: InputDecoration(
                                          labelText: AppLocalizations.of(
                                            context,
                                          )!.brandLabel,
                                          labelStyle: GoogleFonts.orbitron(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          filled: true,
                                          fillColor: Colors.black.withValues(alpha: 
                                            0.15,
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 12,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            if (selectedBrand != null &&
                                                selectedBrand!.isNotEmpty)
                                              Container(
                                                width: 24,
                                                height: 24,
                                                decoration: BoxDecoration(
                                                  color: Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(6),
                                                ),
                                                padding: EdgeInsets.all(2),
                                                child: CachedNetworkImage(
                                                  imageUrl:
                                                      '${getApiBase()}/static/images/brands/${brandLogoFilenames[selectedBrand] ?? selectedBrand!.toLowerCase().replaceAll(' ', '-')}.png',
                                                  placeholder: (context, url) =>
                                                      SizedBox(
                                                        width: 16,
                                                        height: 16,
                                                        child:
                                                            CircularProgressIndicator(
                                                              strokeWidth: 2,
                                                            ),
                                                      ),
                                                  errorWidget:
                                                      (
                                                        context,
                                                        url,
                                                        error,
                                                      ) => Icon(
                                                        Icons.directions_car,
                                                        size: 16,
                                                        color: Color(
                                                          0xFFFF6B00,
                                                        ),
                                                      ),
                                                  fit: BoxFit.contain,
                                                ),
                                              )
                                            else
                                              Icon(
                                                Icons.directions_car,
                                                size: 20,
                                                color: Color(0xFFFF6B00),
                                              ),
                                            SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                selectedBrand == null ||
                                                        selectedBrand!.isEmpty
                                                    ? AppLocalizations.of(
                                                        context,
                                                      )!.any
                                                    : (CarNameTranslations.getLocalizedBrand(
                                                            context,
                                                            selectedBrand,
                                                          ).isNotEmpty
                                                          ? CarNameTranslations.getLocalizedBrand(
                                                              context,
                                                              selectedBrand,
                                                            )
                                                          : selectedBrand!),
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 14,
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                maxLines: 1,
                                                softWrap: false,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  // Model Dropdown
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isDense: true,
                                      isExpanded: true,
                                      dropdownColor: dropdownMenuBg,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 14,
                                        color: dropdownMenuInk,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      selectedItemBuilder: (context) => [
                                        Text(
                                          AppLocalizations.of(context)!.any,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.orbitron(
                                            fontSize: 14,
                                            color: dropdownFieldInk,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (selectedBrand != null &&
                                            models[selectedBrand!] != null)
                                          ...models[selectedBrand!]!.map(
                                            (m) => Text(
                                              CarNameTranslations.getLocalizedModel(
                                                    context,
                                                    selectedBrand,
                                                    m,
                                                  ).isNotEmpty
                                                  ? CarNameTranslations.getLocalizedModel(
                                                      context,
                                                      selectedBrand,
                                                      m,
                                                    )
                                                  : m,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.orbitron(
                                                fontSize: 14,
                                                color: dropdownFieldInk,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                      ],
                                      initialValue:
                                          selectedModel != null &&
                                              (selectedModel!.isEmpty ||
                                                  (selectedBrand != null &&
                                                      models[selectedBrand] !=
                                                          null &&
                                                      models[selectedBrand]!
                                                          .contains(
                                                            selectedModel,
                                                          )))
                                          ? selectedModel
                                          : null,
                                      decoration: InputDecoration(
                                        labelText: AppLocalizations.of(
                                          context,
                                        )!.modelLabel,
                                        labelStyle: GoogleFonts.orbitron(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        filled: true,
                                        fillColor: Colors.black.withValues(alpha: 
                                          0.15,
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                        ),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 6,
                                        ),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: '',
                                          child: Text(
                                            AppLocalizations.of(context)!.any,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.orbitron(
                                              color: isLightShell
                                                  ? const Color(0xFF757575)
                                                  : Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (selectedBrand != null &&
                                            models[selectedBrand!] != null)
                                          ...models[selectedBrand!]!.map(
                                            (m) => DropdownMenuItem(
                                              value: m,
                                              child: Text(
                                                CarNameTranslations.getLocalizedModel(
                                                      context,
                                                      selectedBrand,
                                                      m,
                                                    ).isNotEmpty
                                                    ? CarNameTranslations.getLocalizedModel(
                                                        context,
                                                        selectedBrand,
                                                        m,
                                                      )
                                                    : m,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: GoogleFonts.orbitron(
                                                  fontSize: 14,
                                                  color: dropdownMenuInk,
                                                ),
                                              ),
                                            ),
                                          ),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          selectedModel = value == ''
                                              ? null
                                              : value;
                                          selectedTrim = null;
                                          clearFiltersOnVehicleChange();
                                        });
                                        onFilterChanged();
                                      },
                                    ),
                                  ),
                                  SizedBox(width: 6),
                                  // Trim Dropdown
                                  Expanded(
                                    child: DropdownButtonFormField<String>(
                                      isDense: true,
                                      isExpanded: true,
                                      dropdownColor: dropdownMenuBg,
                                      style: GoogleFonts.orbitron(
                                        fontSize: 14,
                                        color: dropdownMenuInk,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      selectedItemBuilder: (context) => [
                                        Text(
                                          AppLocalizations.of(context)!.any,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.orbitron(
                                            fontSize: 14,
                                            color: dropdownFieldInk,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (selectedBrand != null &&
                                            selectedModel != null &&
                                            trimsByBrandModel[selectedBrand] != null &&
                                            trimsByBrandModel[selectedBrand]![selectedModel] !=
                                                null)
                                          ...trimsByBrandModel[selectedBrand]![selectedModel]!
                                              .map(
                                                (t) => Text(
                                                  t,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: GoogleFonts.orbitron(
                                                    fontSize: 14,
                                                    color: dropdownFieldInk,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                      ],
                                      initialValue:
                                          selectedTrim != null &&
                                              (selectedTrim!.isEmpty ||
                                                  (selectedBrand != null &&
                                                      selectedModel != null &&
                                                      trimsByBrandModel[selectedBrand] !=
                                                          null &&
                                                      trimsByBrandModel[selectedBrand]![selectedModel] !=
                                                          null &&
                                                      trimsByBrandModel[selectedBrand]![selectedModel]!
                                                          .contains(selectedTrim)))
                                          ? selectedTrim
                                          : null,
                                      decoration: InputDecoration(
                                        labelText:
                                            AppLocalizations.of(context)!.trimLabel,
                                        labelStyle: GoogleFonts.orbitron(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        filled: true,
                                        fillColor: Colors.black.withValues(alpha: 0.15),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        contentPadding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 6,
                                        ),
                                      ),
                                      items: [
                                        DropdownMenuItem(
                                          value: '',
                                          child: Text(
                                            AppLocalizations.of(context)!.any,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: GoogleFonts.orbitron(
                                              color: isLightShell
                                                  ? const Color(0xFF757575)
                                                  : Colors.grey,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        if (selectedBrand != null &&
                                            selectedModel != null &&
                                            trimsByBrandModel[selectedBrand] != null &&
                                            trimsByBrandModel[selectedBrand]![selectedModel] !=
                                                null)
                                          ...trimsByBrandModel[selectedBrand]![selectedModel]!
                                              .map(
                                                (t) => DropdownMenuItem(
                                                  value: t,
                                                  child: Text(
                                                    t,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: GoogleFonts.orbitron(
                                                      fontSize: 14,
                                                      color: dropdownMenuInk,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ],
                                      onChanged: (value) {
                                        setState(() {
                                          selectedTrim = value == '' ? null : value;
                                          clearFiltersOnVehicleChange();
                                        });
                                        onFilterChanged();
                                      },
                                    ),
                                  ),
                                ],
                              );
                                },
                              ),
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
                  ), // SliverToBoxAdapter
                  if (isLoading)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Color(0xFFFF6B00),
                              ),
                            ),
                            SizedBox(height: 16),
                            Text(
                              selectedSortBy != null
                                  ? homeFeedSortingListingsText(context)
                                  : homeFeedLoadingListingsText(context),
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (loadErrorMessage != null && cars.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: HomeFeedErrorState(
                        message: formatHomeFeedErrorMessage(
                          context,
                          loadErrorMessage,
                        ),
                        onRetry: () {
                          _fetchRetryCount = 0;
                          fetchCars(bypassCache: true);
                        },
                        onClearFilters: () => onFilterChanged(),
                      ),
                    )
                  else if (cars.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: HomeEmptyListMessage(
                        selectedSortBy: selectedSortBy,
                        onAutoFetch: () {
                          if (!_autoFetchedForEmptyWithSort &&
                              selectedSortBy != null &&
                              selectedSortBy!.isNotEmpty) {
                            _autoFetchedForEmptyWithSort = true;
                            onFilterChanged();
                          }
                        },
                      ),
                    )
                  else ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PopupMenuButton<String>(
                              tooltip: AppLocalizations.of(context)!.sortBy,
                              icon: Icon(Icons.sort, size: 20),
                              onSelected: (value) {
                                setState(
                                  () => selectedSortBy = value == ''
                                      ? null
                                      : value,
                                );
                                _persistFilters();
                                onSortChanged();
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: '',
                                  child: Text(
                                    AppLocalizations.of(context)!.defaultSort,
                                  ),
                                ),
                                ...getLocalizedSortOptions(context)
                                    .skip(1)
                                    .map(
                                      (s) => PopupMenuItem(
                                        value: s,
                                        child: Text(s),
                                      ),
                                    ),
                              ],
                            ),
                            ToggleButtons(
                              isSelected: [
                                listingColumns == 1,
                                listingColumns == 2,
                                listingColumns == 3,
                              ],
                              onPressed: (index) {
                                setState(() {
                                  listingColumns = index == 0 ? 1 : (index == 1 ? 2 : 3);
                                });
                                ListingLayoutPrefs.setColumns(listingColumns);
                              },
                              children: const [
                                Icon(Icons.view_agenda),
                                Icon(Icons.grid_view),
                                Icon(Icons.swipe_vertical),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (loadErrorMessage != null && cars.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Container(
                          width: double.infinity,
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          margin: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.orange.withValues(alpha: 0.3),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.offline_bolt,
                                color: Colors.orange,
                                size: 16,
                              ),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Showing cached results',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: fetchCars,
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  minimumSize: Size(0, 0),
                                ),
                                child: Text(
                                  'Refresh',
                                  style: TextStyle(
                                    color: Colors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        listingColumns == 1 ? 4 : 8,
                        8,
                        listingColumns == 1 ? 4 : 8,
                        8 + MediaQuery.of(context).padding.bottom + 92,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: listingColumns == 1 ? 1 : 2,
                          // Slightly taller cells than 0.65 so listing cards (image + content) don’t overflow
                          // One column: horizontal row — wider vs tall to match strip layout.
                          // One column: horizontal card. Larger ratio => shorter cell height
                          // so the text column is not left with a tall empty band under the last row.
                          childAspectRatio: listingColumns == 1
                              ? 2.78
                              : (Platform.isIOS ? 0.66 : 0.61),
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          if (index >= cars.length) {
                            return Center(
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            );
                          }
                          final car = cars[index];
                          if (listingColumns == 3) {
                            return GestureDetector(
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  '/tiktok_scroll',
                                  arguments: {
                                    'cars': cars,
                                    'initialIndex': index,
                                  },
                                );
                              },
                              child: AbsorbPointer(
                                child: buildGlobalCarCard(
                                  context,
                                  car,
                                  listLayout: false,
                                  carouselResetSeed: _homeCarouselResetSeed,
                                ),
                              ),
                            );
                          }
                          return buildGlobalCarCard(
                            context,
                            car,
                            listLayout: listingColumns == 1,
                            carouselResetSeed: _homeCarouselResetSeed,
                          );
                        }, childCount: cars.length + (_hasNext ? 1 : 0)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // Intentionally avoid full-screen obscuring overlay while scroll restores.
          ],
        ),
      ),
      floatingActionButton: null,
    );
  }
}
