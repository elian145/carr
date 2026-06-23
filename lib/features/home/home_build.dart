part of 'home_flow.dart';

mixin _HomePageBuild on _HomePageFilterLogic {
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
                                  onPressed: () async {
                                    // Sync manual-entry controllers to current selections
                                    // (do this once when opening the dialog, not during typing).
                                    _minPriceController.text =
                                        selectedMinPrice ?? '';
                                    _maxPriceController.text =
                                        selectedMaxPrice ?? '';
                                    _minYearController.text =
                                        selectedMinYear ?? '';
                                    _maxYearController.text =
                                        selectedMaxYear ?? '';
                                    _minMileageController.text =
                                        selectedMinMileage ?? '';
                                    _maxMileageController.text =
                                        selectedMaxMileage ?? '';
                                    _engineSizeController.text =
                                        selectedEngineSize ?? '';
                                    final moreFiltersSnapshot =
                                        _moreFiltersDialogSnapshot();
                                    await showDialog(
                                      context: context,
                                      builder: (context) {
                                        return StatefulBuilder(
                                          builder: (context, setStateDialog) {
                                            final isLightMoreFilters =
                                                Theme.of(context).brightness ==
                                                Brightness.light;
                                            final moreFiltersBg =
                                                isLightMoreFilters
                                                ? Colors.white
                                                : (Colors.grey[900]
                                                          ?.withValues(alpha: 0.98) ??
                                                      Colors.grey.shade900);
                                            final moreFiltersOnSurface =
                                                isLightMoreFilters
                                                ? const Color(0xFF1A1A1A)
                                                : Colors.white;
                                            final moreFiltersMuted =
                                                isLightMoreFilters
                                                ? const Color(0xFF757575)
                                                : Colors.white70;
                                            final moreFiltersAnyOrange =
                                                const Color(0xFFFF6B00);
                                            final moreFiltersFieldFill =
                                                isLightMoreFilters
                                                ? Colors.grey.shade200
                                                : Colors.black.withValues(alpha: 0.2);
                                            const double moreFiltersFieldGap =
                                                18;
                                            return AlertDialog(
                                              backgroundColor: moreFiltersBg,
                                              surfaceTintColor:
                                                  Colors.transparent,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(20),
                                              ),
                                              title: Text(
                                                AppLocalizations.of(
                                                  context,
                                                )!.moreFilters,
                                                style: GoogleFonts.orbitron(
                                                  color: Color(0xFFFF6B00),
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              content: SingleChildScrollView(
                                                child: KeyedSubtree(
                                                  key: ValueKey<int>(
                                                    _moreFiltersDialogFieldGeneration,
                                                  ),
                                                  child: Column(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      // Price Filter
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.priceRange,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isPriceDropdown
                                                                ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  isExpanded: true,
                                                                                  initialValue:
                                                                                      selectedMinPrice ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int p = 500;
                                                                                            p <=
                                                                                                300000;
                                                                                            p += 500
                                                                                          )
                                                                                            p,
                                                                                          for (
                                                                                            int p = 310000;
                                                                                            p <=
                                                                                                2000000;
                                                                                            p += 10000
                                                                                          )
                                                                                            p,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            p,
                                                                                          ) {
                                                                                            if (selectedMaxPrice ==
                                                                                                    null ||
                                                                                                selectedMaxPrice!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxPrice!,
                                                                                            );
                                                                                            return max ==
                                                                                                    null
                                                                                                ? true
                                                                                                : p <=
                                                                                                      max;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            p,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: p.toString(),
                                                                                            child: Text(
                                                                                              _formatCurrencyGlobal(
                                                                                                context,
                                                                                                p,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMinPrice =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                min >
                                                                                                    max) {
                                                                                              selectedMaxPrice = selectedMinPrice;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  isExpanded: true,
                                                                                  initialValue:
                                                                                      selectedMaxPrice ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int p = 500;
                                                                                            p <=
                                                                                                300000;
                                                                                            p += 500
                                                                                          )
                                                                                            p,
                                                                                          for (
                                                                                            int p = 310000;
                                                                                            p <=
                                                                                                2000000;
                                                                                            p += 10000
                                                                                          )
                                                                                            p,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            p,
                                                                                          ) {
                                                                                            if (selectedMinPrice ==
                                                                                                    null ||
                                                                                                selectedMinPrice!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final min = int.tryParse(
                                                                                              selectedMinPrice!,
                                                                                            );
                                                                                            return min ==
                                                                                                    null
                                                                                                ? true
                                                                                                : p >=
                                                                                                      min;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            p,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: p.toString(),
                                                                                            child: Text(
                                                                                              _formatCurrencyGlobal(
                                                                                                context,
                                                                                                p,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMaxPrice =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxPrice ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                max <
                                                                                                    min) {
                                                                                              selectedMinPrice = selectedMaxPrice;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _minPriceController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMinPrice = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinPrice ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxPrice ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            min >
                                                                                                max) {
                                                                                          selectedMaxPrice = selectedMinPrice;
                                                                                          _maxPriceController.text =
                                                                                              selectedMaxPrice ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _maxPriceController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMaxPrice = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinPrice ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxPrice ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            max <
                                                                                                min) {
                                                                                          selectedMinPrice = selectedMaxPrice;
                                                                                          _minPriceController.text =
                                                                                              selectedMinPrice ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isPriceDropdown) {
                                                                _minPriceController
                                                                        .text =
                                                                    selectedMinPrice ??
                                                                    '';
                                                                _maxPriceController
                                                                        .text =
                                                                    selectedMaxPrice ??
                                                                    '';
                                                              }
                                                              isPriceDropdown =
                                                                  !isPriceDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isPriceDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      // Year Filter
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.yearRange,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isYearDropdown
                                                                ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      selectedMinYear ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...List.generate(
                                                                                          127,
                                                                                          (
                                                                                            i,
                                                                                          ) =>
                                                                                              (1900 +
                                                                                                      i)
                                                                                                  .toString(),
                                                                                        ).reversed
                                                                                        .where(
                                                                                          (
                                                                                            y,
                                                                                          ) {
                                                                                            if (selectedMaxYear ==
                                                                                                    null ||
                                                                                                selectedMaxYear!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxYear!,
                                                                                            );
                                                                                            final val = int.tryParse(
                                                                                              y,
                                                                                            );
                                                                                            return max ==
                                                                                                        null ||
                                                                                                    val ==
                                                                                                        null
                                                                                                ? true
                                                                                                : val <=
                                                                                                      max;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            y,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: y,
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                y,
                                                                                              ),
                                                                                              style: TextStyle(
                                                                                                color: moreFiltersOnSurface,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMinYear =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinYear ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxYear ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                min >
                                                                                                    max) {
                                                                                              selectedMaxYear = selectedMinYear;
                                                                                            }
                                                                                            _afterHomeYearBoundsChanged();
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      selectedMaxYear ??
                                                                                      '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.any,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...List.generate(
                                                                                          127,
                                                                                          (
                                                                                            i,
                                                                                          ) =>
                                                                                              (1900 +
                                                                                                      i)
                                                                                                  .toString(),
                                                                                        ).reversed
                                                                                        .where(
                                                                                          (
                                                                                            y,
                                                                                          ) {
                                                                                            if (selectedMinYear ==
                                                                                                    null ||
                                                                                                selectedMinYear!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final min = int.tryParse(
                                                                                              selectedMinYear!,
                                                                                            );
                                                                                            final val = int.tryParse(
                                                                                              y,
                                                                                            );
                                                                                            return min ==
                                                                                                        null ||
                                                                                                    val ==
                                                                                                        null
                                                                                                ? true
                                                                                                : val >=
                                                                                                      min;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            y,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: y,
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                y,
                                                                                              ),
                                                                                              style: TextStyle(
                                                                                                color: moreFiltersOnSurface,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMaxYear =
                                                                                                value?.isEmpty ==
                                                                                                    true
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinYear ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxYear ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                max <
                                                                                                    min) {
                                                                                              selectedMinYear = selectedMaxYear;
                                                                                            }
                                                                                            _afterHomeYearBoundsChanged();
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _minYearController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMinYear = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinYear ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxYear ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            min >
                                                                                                max) {
                                                                                          selectedMaxYear = selectedMinYear;
                                                                                          _maxYearController.text =
                                                                                              selectedMaxYear ??
                                                                                              '';
                                                                                        }
                                                                                        _afterHomeYearBoundsChanged();
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _maxYearController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMaxYear = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinYear ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxYear ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            max <
                                                                                                min) {
                                                                                          selectedMinYear = selectedMaxYear;
                                                                                          _minYearController.text =
                                                                                              selectedMinYear ??
                                                                                              '';
                                                                                        }
                                                                                        _afterHomeYearBoundsChanged();
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isYearDropdown) {
                                                                _minYearController
                                                                        .text =
                                                                    selectedMinYear ??
                                                                    '';
                                                                _maxYearController
                                                                        .text =
                                                                    selectedMaxYear ??
                                                                    '';
                                                              }
                                                              isYearDropdown =
                                                                  !isYearDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isYearDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      // Mileage Filter
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.mileageRangeLabel,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontWeight:
                                                                FontWeight.bold,
                                                            fontSize: 18,
                                                          ),
                                                        ),
                                                      ),
                                                      SizedBox(height: 12),
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isMileageDropdown
                                                                ? Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      (selectedMinMileage !=
                                                                                              null &&
                                                                                          selectedMinMileage!.isNotEmpty)
                                                                                      ? selectedMinMileage
                                                                                      : '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.minMileage,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int m = 0;
                                                                                            m <=
                                                                                                100000;
                                                                                            m += 1000
                                                                                          )
                                                                                            m,
                                                                                          for (
                                                                                            int m = 105000;
                                                                                            m <=
                                                                                                300000;
                                                                                            m += 5000
                                                                                          )
                                                                                            m,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            m,
                                                                                          ) {
                                                                                            if (selectedMaxMileage ==
                                                                                                    null ||
                                                                                                selectedMaxMileage!.isEmpty) {
                                                                                              return true;
                                                                                            }
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxMileage!,
                                                                                            );
                                                                                            return max ==
                                                                                                    null
                                                                                                ? true
                                                                                                : m <=
                                                                                                      max;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            m,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: m.toString(),
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                m.toString().replaceAllMapped(
                                                                                                  RegExp(
                                                                                                    r'(\d{1,3})(?=(\d{3})+(?!\d))',
                                                                                                  ),
                                                                                                  (
                                                                                                    mm,
                                                                                                  ) => '${mm[1]},',
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMinMileage =
                                                                                                (value ==
                                                                                                        null ||
                                                                                                    value.isEmpty)
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                min >
                                                                                                    max) {
                                                                                              selectedMaxMileage = selectedMinMileage;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child:
                                                                                DropdownButtonFormField<
                                                                                  String
                                                                                >(
                                                                                  initialValue:
                                                                                      (selectedMaxMileage !=
                                                                                              null &&
                                                                                          selectedMaxMileage!.isNotEmpty)
                                                                                      ? selectedMaxMileage
                                                                                      : '',
                                                                                  decoration: InputDecoration(
                                                                                    hintText: AppLocalizations.of(
                                                                                      context,
                                                                                    )!.maxMileage,
                                                                                    filled: true,
                                                                                    fillColor: moreFiltersFieldFill,
                                                                                    hintStyle: TextStyle(
                                                                                      color: moreFiltersAnyOrange,
                                                                                    ),
                                                                                    border: OutlineInputBorder(
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                    ),
                                                                                  ),
                                                                                  items: [
                                                                                    DropdownMenuItem(
                                                                                      value: '',
                                                                                      child: Text(
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any,
                                                                                        style: TextStyle(
                                                                                          color: moreFiltersAnyOrange,
                                                                                        ),
                                                                                      ),
                                                                                    ),
                                                                                    ...[
                                                                                          for (
                                                                                            int m = 0;
                                                                                            m <=
                                                                                                100000;
                                                                                            m += 1000
                                                                                          )
                                                                                            m,
                                                                                          for (
                                                                                            int m = 105000;
                                                                                            m <=
                                                                                                300000;
                                                                                            m += 5000
                                                                                          )
                                                                                            m,
                                                                                        ]
                                                                                        .where(
                                                                                          (
                                                                                            m,
                                                                                          ) {
                                                                                            if (selectedMinMileage ==
                                                                                                    null ||
                                                                                                selectedMinMileage!.isNotEmpty ==
                                                                                                    false) {
                                                                                              return true;
                                                                                            }
                                                                                            final min = int.tryParse(
                                                                                              selectedMinMileage!,
                                                                                            );
                                                                                            return min ==
                                                                                                    null
                                                                                                ? true
                                                                                                : m >=
                                                                                                      min;
                                                                                          },
                                                                                        )
                                                                                        .map(
                                                                                          (
                                                                                            m,
                                                                                          ) => DropdownMenuItem(
                                                                                            value: m.toString(),
                                                                                            child: Text(
                                                                                              _localizeDigitsGlobal(
                                                                                                context,
                                                                                                m.toString().replaceAllMapped(
                                                                                                  RegExp(
                                                                                                    r'(\d{1,3})(?=(\d{3})+(?!\d))',
                                                                                                  ),
                                                                                                  (
                                                                                                    mm,
                                                                                                  ) => '${mm[1]},',
                                                                                                ),
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                  ],
                                                                                  onChanged:
                                                                                      (
                                                                                        value,
                                                                                      ) {
                                                                                        setState(
                                                                                          () {
                                                                                            selectedMaxMileage =
                                                                                                (value ==
                                                                                                        null ||
                                                                                                    value.isEmpty)
                                                                                                ? null
                                                                                                : value;
                                                                                            final min = int.tryParse(
                                                                                              selectedMinMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            final max = int.tryParse(
                                                                                              selectedMaxMileage ??
                                                                                                  '',
                                                                                            );
                                                                                            if (min !=
                                                                                                    null &&
                                                                                                max !=
                                                                                                    null &&
                                                                                                max <
                                                                                                    min) {
                                                                                              selectedMinMileage = selectedMaxMileage;
                                                                                            }
                                                                                          },
                                                                                        );
                                                                                        setStateDialog(
                                                                                          () {},
                                                                                        );
                                                                                      },
                                                                                ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  )
                                                                : Column(
                                                                    children: [
                                                                      Row(
                                                                        children: [
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _minMileageController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMinMileage = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinMileage ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxMileage ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            min >
                                                                                                max) {
                                                                                          selectedMaxMileage = selectedMinMileage;
                                                                                          _maxMileageController.text =
                                                                                              selectedMaxMileage ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                          SizedBox(
                                                                            width:
                                                                                8,
                                                                          ),
                                                                          Expanded(
                                                                            child: TextFormField(
                                                                              controller: _maxMileageController,
                                                                              decoration: InputDecoration(
                                                                                hintText: AppLocalizations.of(
                                                                                  context,
                                                                                )!.any,
                                                                                filled: true,
                                                                                fillColor: moreFiltersFieldFill,
                                                                                hintStyle: TextStyle(
                                                                                  color: moreFiltersAnyOrange,
                                                                                ),
                                                                                border: OutlineInputBorder(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                ),
                                                                              ),
                                                                              keyboardType: TextInputType.number,
                                                                              onChanged:
                                                                                  (
                                                                                    value,
                                                                                  ) {
                                                                                    setState(
                                                                                      () {
                                                                                        selectedMaxMileage = value.isEmpty
                                                                                            ? null
                                                                                            : value;
                                                                                        final min = int.tryParse(
                                                                                          selectedMinMileage ??
                                                                                              '',
                                                                                        );
                                                                                        final max = int.tryParse(
                                                                                          selectedMaxMileage ??
                                                                                              '',
                                                                                        );
                                                                                        if (min !=
                                                                                                null &&
                                                                                            max !=
                                                                                                null &&
                                                                                            max <
                                                                                                min) {
                                                                                          selectedMinMileage = selectedMaxMileage;
                                                                                          _minMileageController.text =
                                                                                              selectedMinMileage ??
                                                                                              '';
                                                                                        }
                                                                                      },
                                                                                    );
                                                                                    setStateDialog(
                                                                                      () {},
                                                                                    );
                                                                                  },
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                    ],
                                                                  ),
                                                          ),
                                                          SizedBox(width: 8),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isMileageDropdown) {
                                                                _minMileageController
                                                                        .text =
                                                                    selectedMinMileage ??
                                                                    '';
                                                                _maxMileageController
                                                                        .text =
                                                                    selectedMaxMileage ??
                                                                    '';
                                                              }
                                                              isMileageDropdown =
                                                                  !isMileageDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isMileageDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color: Color(
                                                                0xFFFF6B00,
                                                              ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(context)!.titleStatus,
                                                          style: TextStyle(
                                                            color: moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            for (final entry in <String, String>{
                                                              '': AppLocalizations.of(context)!.any,
                                                              'clean': AppLocalizations.of(context)!.value_title_clean,
                                                              'damaged': AppLocalizations.of(context)!.value_title_damaged,
                                                            }.entries)
                                                              ChoiceChip(
                                                                label: Text(entry.value),
                                                                selected: (selectedTitleStatus ?? '') == entry.key,
                                                                selectedColor: entry.key == ''
                                                                    ? moreFiltersAnyOrange
                                                                    : Theme.of(context).colorScheme.primary,
                                                                backgroundColor: moreFiltersFieldFill,
                                                                labelStyle: TextStyle(
                                                                  color: (selectedTitleStatus ?? '') == entry.key
                                                                      ? Colors.white
                                                                      : moreFiltersOnSurface,
                                                                  fontWeight: (selectedTitleStatus ?? '') == entry.key
                                                                      ? FontWeight.bold
                                                                      : FontWeight.normal,
                                                                ),
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  side: BorderSide(
                                                                    color: (selectedTitleStatus ?? '') == entry.key
                                                                        ? Colors.transparent
                                                                        : moreFiltersOnSurface.withValues(alpha: 0.2),
                                                                  ),
                                                                ),
                                                                onSelected: (_) {
                                                                  setState(() {
                                                                    selectedTitleStatus = entry.key == '' ? null : entry.key;
                                                                    if (selectedTitleStatus != 'damaged') {
                                                                      selectedDamagedParts = null;
                                                                    }
                                                                  });
                                                                  setStateDialog(() {});
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      if (selectedTitleStatus ==
                                                          'damaged')
                                                        ...[
                                                          SizedBox(
                                                            height:
                                                                moreFiltersFieldGap,
                                                          ),
                                                          DropdownButtonFormField<
                                                            String
                                                          >(
                                                            initialValue:
                                                                selectedDamagedParts ??
                                                                '',
                                                            decoration: InputDecoration(
                                                              labelText:
                                                                  AppLocalizations.of(
                                                                    context,
                                                                  )!.damagedParts,
                                                              filled: true,
                                                              fillColor:
                                                                  moreFiltersFieldFill,
                                                              labelStyle: TextStyle(
                                                                color:
                                                                    moreFiltersOnSurface,
                                                                fontSize: 18,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                              border: OutlineInputBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      12,
                                                                    ),
                                                              ),
                                                            ),
                                                            items: [
                                                              DropdownMenuItem(
                                                                value: '',
                                                                child: Text(
                                                                  AppLocalizations.of(
                                                                    context,
                                                                  )!.any,
                                                                  style: TextStyle(
                                                                    color:
                                                                        moreFiltersAnyOrange,
                                                                  ),
                                                                ),
                                                              ),
                                                              ...List.generate(
                                                                15,
                                                                (i) => (i + 1)
                                                                    .toString(),
                                                              ).map(
                                                                (
                                                                  p,
                                                                ) => DropdownMenuItem(
                                                                  value: p,
                                                                  child: Text(
                                                                    '${_localizeDigitsGlobal(context, p)} ${AppLocalizations.of(context)!.damagedParts}',
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                            onChanged: (value) {
                                                              setState(
                                                                () =>
                                                                    selectedDamagedParts =
                                                                        value ==
                                                                            ''
                                                                        ? null
                                                                        : value,
                                                              );
                                                              setStateDialog(
                                                                () {},
                                                              );
                                                            },
                                                          ),
                                                        ],
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(context)!.conditionLabel,
                                                          style: TextStyle(
                                                            color: moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: conditions.map((c) {
                                                            final isSelected = (selectedCondition ?? 'Any') == c;
                                                            return ChoiceChip(
                                                              label: Text(
                                                                _translateValueGlobal(context, c) ?? c,
                                                              ),
                                                              selected: isSelected,
                                                              selectedColor: c == 'Any'
                                                                  ? moreFiltersAnyOrange
                                                                  : Theme.of(context).colorScheme.primary,
                                                              backgroundColor: moreFiltersFieldFill,
                                                              labelStyle: TextStyle(
                                                                color: isSelected
                                                                    ? Colors.white
                                                                    : moreFiltersOnSurface,
                                                                fontWeight: isSelected
                                                                    ? FontWeight.bold
                                                                    : FontWeight.normal,
                                                              ),
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius: BorderRadius.circular(12),
                                                                side: BorderSide(
                                                                  color: isSelected
                                                                      ? Colors.transparent
                                                                      : moreFiltersOnSurface.withValues(alpha: 0.2),
                                                                ),
                                                              ),
                                                              onSelected: (_) {
                                                                setState(() {
                                                                  selectedCondition = c == 'Any' ? 'Any' : c;
                                                                });
                                                                setStateDialog(() {});
                                                              },
                                                            );
                                                          }).toList(),
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Text(
                                                          AppLocalizations.of(context)!.transmissionLabel,
                                                          style: TextStyle(
                                                            color: moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      Align(
                                                        alignment: AlignmentDirectional.centerStart,
                                                        child: Wrap(
                                                          spacing: 8,
                                                          runSpacing: 8,
                                                          children: [
                                                            for (final t in ['Any', ...getAvailableTransmissions().where((t) => t != 'Any')])
                                                              ChoiceChip(
                                                                label: Text(
                                                                  t == 'Any'
                                                                      ? AppLocalizations.of(context)!.any
                                                                      : _translateValueGlobal(context, t) ?? t,
                                                                ),
                                                                selected: (selectedTransmission ?? 'Any') == t,
                                                                selectedColor: t == 'Any'
                                                                    ? moreFiltersAnyOrange
                                                                    : Theme.of(context).colorScheme.primary,
                                                                backgroundColor: moreFiltersFieldFill,
                                                                labelStyle: TextStyle(
                                                                  color: (selectedTransmission ?? 'Any') == t
                                                                      ? Colors.white
                                                                      : moreFiltersOnSurface,
                                                                  fontWeight: (selectedTransmission ?? 'Any') == t
                                                                      ? FontWeight.bold
                                                                      : FontWeight.normal,
                                                                ),
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius: BorderRadius.circular(12),
                                                                  side: BorderSide(
                                                                    color: (selectedTransmission ?? 'Any') == t
                                                                        ? Colors.transparent
                                                                        : moreFiltersOnSurface.withValues(alpha: 0.2),
                                                                  ),
                                                                ),
                                                                onSelected: (_) {
                                                                  setState(() {
                                                                    selectedTransmission = t == 'Any' ? 'Any' : t;
                                                                  });
                                                                  setStateDialog(() {});
                                                                },
                                                              ),
                                                          ],
                                                        ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            _getValidFuelTypeValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.fuelTypeLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableFuelTypes()
                                                              .where(
                                                                (f) =>
                                                                    f != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  f,
                                                                ) => DropdownMenuItem(
                                                                  value: f,
                                                                  child: Text(
                                                                    _translateValueGlobal(
                                                                          context,
                                                                          f,
                                                                        ) ??
                                                                        f,
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) =>
                                                            setState(
                                                              () =>
                                                                  selectedFuelType =
                                                                      value ==
                                                                          ''
                                                                      ? 'Any'
                                                                      : value,
                                                            ),
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      TextFormField(
                                                        key: ValueKey(
                                                          'bodyType_${selectedBodyType ?? 'any'}',
                                                        ),
                                                        readOnly: true,
                                                        style: TextStyle(
                                                          color:
                                                              (selectedBodyType !=
                                                                      null &&
                                                                  selectedBodyType!
                                                                      .isNotEmpty)
                                                              ? moreFiltersOnSurface
                                                              : moreFiltersAnyOrange,
                                                        ),
                                                        initialValue:
                                                            (selectedBodyType ??
                                                            AppLocalizations.of(
                                                              context,
                                                            )!.any),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.bodyTypeLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          suffixIcon: Container(
                                                            margin:
                                                                EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            width: 44,
                                                            height: 44,
                                                            decoration: BoxDecoration(
                                                              shape: BoxShape
                                                                  .circle,
                                                              color:
                                                                  Colors.white,
                                                              border: Border.all(
                                                                color: Color(
                                                                  0xFFFF6B00,
                                                                ),
                                                                width: 2,
                                                              ),
                                                            ),
                                                            child: Padding(
                                                              padding:
                                                                  EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              child: ClipOval(
                                                                child: FittedBox(
                                                                  fit: BoxFit
                                                                      .contain,
                                                                  child:
                                                                      (selectedBodyType !=
                                                                              null &&
                                                                          selectedBodyType!
                                                                              .isNotEmpty)
                                                                      ? _buildBodyTypeImage(
                                                                          _getBodyTypeAsset(
                                                                            selectedBodyType!,
                                                                          ),
                                                                        )
                                                                      : Icon(
                                                                          _getBodyTypeIcon(
                                                                            'car',
                                                                          ),
                                                                          color:
                                                                              Colors.black,
                                                                        ),
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        onTap: () async {
                                                          final bodyType = await showDialog<String>(
                                                            context: context,
                                                            builder: (dlgContext) {
                                                              final isLightPicker =
                                                                  Theme.of(
                                                                    dlgContext,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .light;
                                                              final pickerBg =
                                                                  isLightPicker
                                                                  ? Colors.white
                                                                  : (Colors.grey[900]
                                                                            ?.withValues(alpha: 
                                                                              0.98,
                                                                            ) ??
                                                                        Colors
                                                                            .grey
                                                                            .shade900);
                                                              final onPicker =
                                                                  isLightPicker
                                                                  ? const Color(
                                                                      0xFF1A1A1A,
                                                                    )
                                                                  : Colors
                                                                        .white;
                                                              final onPickerMuted =
                                                                  isLightPicker
                                                                  ? const Color(
                                                                      0xFF616161,
                                                                    )
                                                                  : Colors
                                                                        .white70;
                                                              final borderSubtle =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .black26
                                                                  : Colors
                                                                        .white24;
                                                              final shadowIdle =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .black12
                                                                  : Colors
                                                                        .black54;
                                                              return Dialog(
                                                                backgroundColor:
                                                                    pickerBg,
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                                child: Container(
                                                                  width: 400,
                                                                  padding:
                                                                      EdgeInsets.all(
                                                                        20,
                                                                      ),
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.spaceBetween,
                                                                        children: [
                                                                          Text(
                                                                            AppLocalizations.of(
                                                                              context,
                                                                            )!.selectBodyType,
                                                                            style: GoogleFonts.orbitron(
                                                                              color: Color(
                                                                                0xFFFF6B00,
                                                                              ),
                                                                              fontWeight: FontWeight.bold,
                                                                              fontSize: 20,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: Icon(
                                                                              Icons.close,
                                                                              color: onPicker,
                                                                            ),
                                                                            onPressed: () => Navigator.pop(
                                                                              dlgContext,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            10,
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            300,
                                                                        child: GridView.builder(
                                                                          shrinkWrap:
                                                                              true,
                                                                          physics:
                                                                              BouncingScrollPhysics(),
                                                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                            crossAxisCount:
                                                                                3,
                                                                            childAspectRatio:
                                                                                0.82,
                                                                            crossAxisSpacing:
                                                                                12,
                                                                            mainAxisSpacing:
                                                                                12,
                                                                          ),
                                                                          itemCount:
                                                                              getAvailableBodyTypes().length,
                                                                          itemBuilder:
                                                                              (
                                                                                context,
                                                                                index,
                                                                              ) {
                                                                                final bodyTypeName = getAvailableBodyTypes()[index];
                                                                                final asset = _getBodyTypeAsset(
                                                                                  bodyTypeName,
                                                                                );
                                                                                final bool
                                                                                isSelected =
                                                                                    (selectedBodyType ??
                                                                                        AppLocalizations.of(
                                                                                          context,
                                                                                        )!.any) ==
                                                                                    bodyTypeName;
                                                                                return InkWell(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                  onTap: () => Navigator.pop(
                                                                                    dlgContext,
                                                                                    bodyTypeName,
                                                                                  ),
                                                                                  child: Container(
                                                                                    decoration: BoxDecoration(
                                                                                      color: Colors.transparent,
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                      border: Border.all(
                                                                                        color: isSelected
                                                                                            ? const Color(
                                                                                                0xFFFF6B00,
                                                                                              )
                                                                                            : borderSubtle,
                                                                                        width: isSelected
                                                                                            ? 2
                                                                                            : 1,
                                                                                      ),
                                                                                      boxShadow: isSelected
                                                                                          ? [
                                                                                              BoxShadow(
                                                                                                color:
                                                                                                    const Color(
                                                                                                      0xFFFF6B00,
                                                                                                    ).withValues(alpha: 
                                                                                                      0.35,
                                                                                                    ),
                                                                                                blurRadius: 14,
                                                                                                spreadRadius: 1,
                                                                                                offset: const Offset(
                                                                                                  0,
                                                                                                  4,
                                                                                                ),
                                                                                              ),
                                                                                            ]
                                                                                          : [
                                                                                              BoxShadow(
                                                                                                color: shadowIdle,
                                                                                                blurRadius: 10,
                                                                                                spreadRadius: 0,
                                                                                                offset: const Offset(
                                                                                                  0,
                                                                                                  3,
                                                                                                ),
                                                                                              ),
                                                                                            ],
                                                                                    ),
                                                                                    padding: EdgeInsets.all(
                                                                                      8,
                                                                                    ),
                                                                                    child: Column(
                                                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                                                      children: [
                                                                                        Container(
                                                                                          width: 56,
                                                                                          height: 56,
                                                                                          decoration: BoxDecoration(
                                                                                            shape: BoxShape.circle,
                                                                                            color: Colors.white,
                                                                                            border: Border.all(
                                                                                              color: isSelected
                                                                                                  ? const Color(
                                                                                                      0xFFFF6B00,
                                                                                                    )
                                                                                                  : borderSubtle,
                                                                                              width: isSelected
                                                                                                  ? 2
                                                                                                  : 1,
                                                                                            ),
                                                                                          ),
                                                                                          child: Padding(
                                                                                            padding: const EdgeInsets.all(
                                                                                              8,
                                                                                            ),
                                                                                            child: FittedBox(
                                                                                              fit: BoxFit.contain,
                                                                                              child: _buildBodyTypeImage(
                                                                                                asset,
                                                                                              ),
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                        const SizedBox(
                                                                                          height: 8,
                                                                                        ),
                                                                                        Text(
                                                                                          bodyTypeName ==
                                                                                                  'Any'
                                                                                              ? AppLocalizations.of(
                                                                                                  context,
                                                                                                )!.anyOption
                                                                                              : (_translateValueGlobal(
                                                                                                      context,
                                                                                                      bodyTypeName,
                                                                                                    ) ??
                                                                                                    bodyTypeName),
                                                                                          style: GoogleFonts.orbitron(
                                                                                            fontSize: 12,
                                                                                            color: isSelected
                                                                                                ? const Color(
                                                                                                    0xFFFF6B00,
                                                                                                  )
                                                                                                : onPickerMuted,
                                                                                            fontWeight: FontWeight.bold,
                                                                                          ),
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
                                                          if (bodyType !=
                                                              null) {
                                                            setState(() {
                                                              selectedBodyType =
                                                                  bodyType ==
                                                                      'Any'
                                                                  ? null
                                                                  : bodyType;
                                                            });
                                                            setStateDialog(
                                                              () {},
                                                            );
                                                          }
                                                        },
                                                      ),
                                                      SizedBox(
                                                        height:
                                                            moreFiltersFieldGap,
                                                      ),
                                                      TextFormField(
                                                        key: ValueKey(
                                                          'color_${selectedColor ?? 'any'}',
                                                        ),
                                                        readOnly: true,
                                                        style: TextStyle(
                                                          color:
                                                              (selectedColor !=
                                                                      null &&
                                                                  selectedColor!
                                                                      .isNotEmpty)
                                                              ? moreFiltersOnSurface
                                                              : moreFiltersAnyOrange,
                                                        ),
                                                        initialValue:
                                                            (_translateValueGlobal(
                                                              context,
                                                              selectedColor,
                                                            ) ??
                                                            selectedColor ??
                                                            AppLocalizations.of(
                                                              context,
                                                            )!.any),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.colorLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                          suffixIcon: Container(
                                                            width: 24,
                                                            height: 24,
                                                            margin:
                                                                EdgeInsets.all(
                                                                  8,
                                                                ),
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  selectedColor !=
                                                                      null
                                                                  ? _getColorValue(
                                                                      selectedColor!,
                                                                    )
                                                                  : Colors.grey,
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    6,
                                                                  ),
                                                              border: Border.all(
                                                                color: Colors
                                                                    .white24,
                                                                width: 2,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        onTap: () async {
                                                          final color = await showDialog<String>(
                                                            context: context,
                                                            builder: (dlgContext) {
                                                              final isLightPicker =
                                                                  Theme.of(
                                                                    dlgContext,
                                                                  ).brightness ==
                                                                  Brightness
                                                                      .light;
                                                              final pickerBg =
                                                                  isLightPicker
                                                                  ? Colors.white
                                                                  : (Colors.grey[900]
                                                                            ?.withValues(alpha: 
                                                                              0.98,
                                                                            ) ??
                                                                        Colors
                                                                            .grey
                                                                            .shade900);
                                                              final onPicker =
                                                                  isLightPicker
                                                                  ? const Color(
                                                                      0xFF1A1A1A,
                                                                    )
                                                                  : Colors
                                                                        .white;
                                                              final borderSubtle =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .black26
                                                                  : Colors
                                                                        .white24;
                                                              final cellFill =
                                                                  isLightPicker
                                                                  ? Colors
                                                                        .grey
                                                                        .shade200
                                                                  : Colors.black
                                                                        .withValues(alpha: 
                                                                          0.15,
                                                                        );
                                                              return Dialog(
                                                                backgroundColor:
                                                                    pickerBg,
                                                                shape: RoundedRectangleBorder(
                                                                  borderRadius:
                                                                      BorderRadius.circular(
                                                                        20,
                                                                      ),
                                                                ),
                                                                child: Container(
                                                                  width: 400,
                                                                  padding:
                                                                      EdgeInsets.all(
                                                                        20,
                                                                      ),
                                                                  child: Column(
                                                                    crossAxisAlignment:
                                                                        CrossAxisAlignment
                                                                            .start,
                                                                    mainAxisSize:
                                                                        MainAxisSize
                                                                            .min,
                                                                    children: [
                                                                      Row(
                                                                        mainAxisAlignment:
                                                                            MainAxisAlignment.spaceBetween,
                                                                        children: [
                                                                          Text(
                                                                            AppLocalizations.of(
                                                                              context,
                                                                            )!.selectColor,
                                                                            style: GoogleFonts.orbitron(
                                                                              color: Color(
                                                                                0xFFFF6B00,
                                                                              ),
                                                                              fontWeight: FontWeight.bold,
                                                                              fontSize: 20,
                                                                            ),
                                                                          ),
                                                                          IconButton(
                                                                            icon: Icon(
                                                                              Icons.close,
                                                                              color: onPicker,
                                                                            ),
                                                                            onPressed: () => Navigator.pop(
                                                                              dlgContext,
                                                                            ),
                                                                          ),
                                                                        ],
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            10,
                                                                      ),
                                                                      SizedBox(
                                                                        height:
                                                                            300,
                                                                        child: GridView.builder(
                                                                          shrinkWrap:
                                                                              true,
                                                                          physics:
                                                                              BouncingScrollPhysics(),
                                                                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                                                            crossAxisCount:
                                                                                3,
                                                                            childAspectRatio:
                                                                                1.2,
                                                                            crossAxisSpacing:
                                                                                10,
                                                                            mainAxisSpacing:
                                                                                10,
                                                                          ),
                                                                          itemCount:
                                                                              getAvailableColors().length,
                                                                          itemBuilder:
                                                                              (
                                                                                context,
                                                                                index,
                                                                              ) {
                                                                                final colorName = getAvailableColors()[index];
                                                                                Color
                                                                                colorValue = Colors.grey;
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
                                                                                    colorValue = Color(
                                                                                      0xFFF5F5DC,
                                                                                    );
                                                                                    break;
                                                                                  case 'gold':
                                                                                    colorValue = Color(
                                                                                      0xFFFFD700,
                                                                                    );
                                                                                    break;
                                                                                  default:
                                                                                    colorValue = Colors.grey;
                                                                                }
                                                                                return InkWell(
                                                                                  borderRadius: BorderRadius.circular(
                                                                                    12,
                                                                                  ),
                                                                                  onTap: () => Navigator.pop(
                                                                                    dlgContext,
                                                                                    colorName,
                                                                                  ),
                                                                                  child: Container(
                                                                                    decoration: BoxDecoration(
                                                                                      color: cellFill,
                                                                                      borderRadius: BorderRadius.circular(
                                                                                        12,
                                                                                      ),
                                                                                      border: Border.all(
                                                                                        color: borderSubtle,
                                                                                      ),
                                                                                    ),
                                                                                    padding: EdgeInsets.all(
                                                                                      8,
                                                                                    ),
                                                                                    child: Column(
                                                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                                                      children: [
                                                                                        Container(
                                                                                          width: 40,
                                                                                          height: 40,
                                                                                          decoration: BoxDecoration(
                                                                                            color: colorValue,
                                                                                            borderRadius: BorderRadius.circular(
                                                                                              8,
                                                                                            ),
                                                                                            border: Border.all(
                                                                                              color: borderSubtle,
                                                                                              width: 2,
                                                                                            ),
                                                                                          ),
                                                                                        ),
                                                                                        SizedBox(
                                                                                          height: 8,
                                                                                        ),
                                                                                        Text(
                                                                                          _translateValueGlobal(
                                                                                                context,
                                                                                                colorName,
                                                                                              ) ??
                                                                                              colorName,
                                                                                          style: GoogleFonts.orbitron(
                                                                                            fontSize: 12,
                                                                                            color: onPicker,
                                                                                            fontWeight: FontWeight.bold,
                                                                                          ),
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
                                                              selectedColor =
                                                                  color == 'Any'
                                                                  ? null
                                                                  : color;
                                                            });
                                                            setStateDialog(
                                                              () {},
                                                            );
                                                          }
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Drive Type Dropdown
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            _getValidDriveTypeValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.driveType,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableDriveTypes()
                                                              .where(
                                                                (d) =>
                                                                    d != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  d,
                                                                ) => DropdownMenuItem(
                                                                  value: d,
                                                                  child: Text(
                                                                    _translateValueGlobal(
                                                                          context,
                                                                          d,
                                                                        ) ??
                                                                        d,
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(
                                                            () =>
                                                                selectedDriveType =
                                                                    value == ''
                                                                    ? null
                                                                    : value,
                                                          );
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        key: ValueKey(
                                                          'home_more_region_specs_$_moreFiltersDialogFieldGeneration',
                                                        ),
                                                        initialValue:
                                                            _getValidRegionSpecsValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.regionSpecsLabel,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...kCarRegionSpecCodes.map(
                                                            (
                                                              code,
                                                            ) => DropdownMenuItem(
                                                              value: code,
                                                              child: Text(
                                                                carRegionSpecDisplayLabelLocalized(
                                                                  context,
                                                                  code,
                                                                ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(
                                                            () => selectedRegionSpecs =
                                                                value == null ||
                                                                    value
                                                                        .isEmpty
                                                                ? null
                                                                : value,
                                                          );
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Cylinder Count Dropdown
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            _getValidCylinderCountValue(),
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.cylinderCount,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableCylinderCounts()
                                                              .where(
                                                                (c) =>
                                                                    c != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  c,
                                                                ) => DropdownMenuItem(
                                                                  value: c,
                                                                  child: Text(
                                                                    _localizeDigitsGlobal(
                                                                      context,
                                                                      c,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedCylinderCount =
                                                                value == ''
                                                                ? null
                                                                : value;
                                                            _applyMoreFiltersEngineSyncFromCylinder(
                                                              selectedCylinderCount,
                                                            );
                                                          });
                                                          setStateDialog(() {});
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Seating Dropdown
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            selectedSeating ??
                                                            '',
                                                        decoration: InputDecoration(
                                                          labelText:
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.seating,
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...getAvailableSeatings()
                                                              .where(
                                                                (s) =>
                                                                    s != 'Any',
                                                              )
                                                              .map(
                                                                (
                                                                  s,
                                                                ) => DropdownMenuItem(
                                                                  value: s,
                                                                  child: Text(
                                                                    _localizeDigitsGlobal(
                                                                      context,
                                                                      s,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(
                                                            () =>
                                                                selectedSeating =
                                                                    value == ''
                                                                    ? null
                                                                    : value,
                                                          );
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      SizedBox(height: 12),
                                                      // Engine Size Dropdown / Manual input
                                                      Row(
                                                        children: [
                                                          Expanded(
                                                            child:
                                                                isEngineSizeDropdown
                                                                ? DropdownButtonFormField<
                                                                    String
                                                                  >(
                                                                    initialValue:
                                                                        _getValidEngineSizeValue(),
                                                                    decoration: InputDecoration(
                                                                      labelText: AppLocalizations.of(
                                                                        context,
                                                                      )!.engineSizeL,
                                                                      filled:
                                                                          true,
                                                                      fillColor:
                                                                          moreFiltersFieldFill,
                                                                      labelStyle:
                                                                          TextStyle(
                                                                            color:
                                                                                moreFiltersOnSurface,
                                                                            fontSize: 18,
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                      border: OutlineInputBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    items: [
                                                                      DropdownMenuItem(
                                                                        value:
                                                                            '',
                                                                        child: Text(
                                                                          AppLocalizations.of(
                                                                            context,
                                                                          )!.any,
                                                                          style: TextStyle(
                                                                            color:
                                                                                moreFiltersAnyOrange,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                      ...getAvailableEngineSizes()
                                                                          .where(
                                                                            (
                                                                              e,
                                                                            ) =>
                                                                                e !=
                                                                                'Any',
                                                                          )
                                                                          .map(
                                                                            (
                                                                              e,
                                                                            ) => DropdownMenuItem(
                                                                              value: e,
                                                                              child: Text(
                                                                                '${_localizeDigitsGlobal(context, e)}${AppLocalizations.of(context)!.unit_liter_suffix}',
                                                                              ),
                                                                            ),
                                                                          ),
                                                                    ],
                                                                    onChanged: (value) {
                                                                      setState(() {
                                                                        selectedEngineSize =
                                                                            value ==
                                                                                ''
                                                                            ? null
                                                                            : value;
                                                                        _applyMoreFiltersCylinderSyncFromEngine(
                                                                          selectedEngineSize,
                                                                        );
                                                                      });
                                                                      setStateDialog(
                                                                        () {},
                                                                      );
                                                                      _persistFilters();
                                                                    },
                                                                  )
                                                                : TextFormField(
                                                                    controller:
                                                                        _engineSizeController,
                                                                    decoration: InputDecoration(
                                                                      labelText: AppLocalizations.of(
                                                                        context,
                                                                      )!.engineSizeL,
                                                                      filled:
                                                                          true,
                                                                      fillColor:
                                                                          moreFiltersFieldFill,
                                                                      labelStyle:
                                                                          TextStyle(
                                                                            color:
                                                                                moreFiltersOnSurface,
                                                                            fontSize: 18,
                                                                            fontWeight: FontWeight.bold,
                                                                          ),
                                                                      border: OutlineInputBorder(
                                                                        borderRadius:
                                                                            BorderRadius.circular(
                                                                              12,
                                                                            ),
                                                                      ),
                                                                    ),
                                                                    keyboardType:
                                                                        const TextInputType.numberWithOptions(
                                                                          decimal:
                                                                              true,
                                                                        ),
                                                                    inputFormatters: [
                                                                      services
                                                                          .FilteringTextInputFormatter.allow(
                                                                        RegExp(
                                                                          r'[0-9.]',
                                                                        ),
                                                                      ),
                                                                    ],
                                                                    onChanged: (value) {
                                                                      setState(() {
                                                                        selectedEngineSize =
                                                                            value.isEmpty
                                                                            ? null
                                                                            : value;
                                                                        _applyMoreFiltersCylinderSyncFromEngine(
                                                                          selectedEngineSize,
                                                                        );
                                                                      });
                                                                      setStateDialog(
                                                                        () {},
                                                                      );
                                                                      _persistFilters();
                                                                    },
                                                                  ),
                                                          ),
                                                          const SizedBox(
                                                            width: 8,
                                                          ),
                                                          IconButton(
                                                            onPressed: () => setStateDialog(() {
                                                              if (isEngineSizeDropdown) {
                                                                _engineSizeController
                                                                        .text =
                                                                    selectedEngineSize ??
                                                                    '';
                                                              }
                                                              isEngineSizeDropdown =
                                                                  !isEngineSizeDropdown;
                                                            }),
                                                            icon: Icon(
                                                              isEngineSizeDropdown
                                                                  ? Icons.edit
                                                                  : Icons.list,
                                                              color:
                                                                  const Color(
                                                                    0xFFFF6B00,
                                                                  ),
                                                            ),
                                                            style: IconButton.styleFrom(
                                                              backgroundColor:
                                                                  moreFiltersFieldFill,
                                                              shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                      SizedBox(height: 12),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            selectedPlateType ??
                                                            '',
                                                        decoration: InputDecoration(
                                                          labelText: _trLegacyText(context, 'Plate type', ar: 'نوع اللوحة', ku: 'جۆری پڵەیت'),
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'private',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'private',
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'temporary',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'temporary',
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'commercial',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'commercial',
                                                              ),
                                                            ),
                                                          ),
                                                          DropdownMenuItem(
                                                            value: 'taxi',
                                                            child: Text(
                                                              _translatePlateTypeLegacy(
                                                                context,
                                                                'taxi',
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedPlateType =
                                                                (value == null ||
                                                                        value
                                                                            .isEmpty)
                                                                ? null
                                                                : value;
                                                          });
                                                          _persistFilters();
                                                        },
                                                      ),
                                                      const SizedBox(height: 12),
                                                      DropdownButtonFormField<
                                                        String
                                                      >(
                                                        initialValue:
                                                            selectedPlateCity ??
                                                            '',
                                                        decoration: InputDecoration(
                                                          labelText: _trLegacyText(context, 'Plate city', ar: 'مدينة اللوحة', ku: 'شاری پڵەیت'),
                                                          filled: true,
                                                          fillColor:
                                                              moreFiltersFieldFill,
                                                          labelStyle: TextStyle(
                                                            color:
                                                                moreFiltersOnSurface,
                                                            fontSize: 18,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                          border: OutlineInputBorder(
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  12,
                                                                ),
                                                          ),
                                                        ),
                                                        items: [
                                                          DropdownMenuItem(
                                                            value: '',
                                                            child: Text(
                                                              AppLocalizations.of(
                                                                context,
                                                              )!.any,
                                                              style: TextStyle(
                                                                color:
                                                                    moreFiltersAnyOrange,
                                                              ),
                                                            ),
                                                          ),
                                                          ...cities
                                                              .where(
                                                                (c) =>
                                                                    c.toLowerCase() !=
                                                                    'any',
                                                              )
                                                              .map(
                                                                (c) =>
                                                                    DropdownMenuItem(
                                                                  value: c,
                                                                  child: Text(
                                                                    _translateValueGlobal(
                                                                          context,
                                                                          c,
                                                                        ) ??
                                                                        c,
                                                                  ),
                                                                ),
                                                              ),
                                                        ],
                                                        onChanged: (value) {
                                                          setState(() {
                                                            selectedPlateCity =
                                                                (value == null ||
                                                                        value
                                                                            .isEmpty)
                                                                ? null
                                                                : value;
                                                          });
                                                          _persistFilters();
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              actions: [
                                                SizedBox(
                                                  width: double.infinity,
                                                  child: Row(
                                                    textDirection:
                                                        ui.TextDirection.ltr,
                                                    children: [
                                                      TextButton(
                                                        onPressed: () async {
                                                          await _resetFiltersFromMoreFiltersDialog(
                                                            () =>
                                                                setStateDialog(
                                                                  () {},
                                                                ),
                                                          );
                                                        },
                                                        child: Text(
                                                          AppLocalizations.of(
                                                            context,
                                                          )!.resetButton,
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersMuted,
                                                          ),
                                                        ),
                                                      ),
                                                      TextButton(
                                                        onPressed: () {
                                                          _restoreMoreFiltersDialogSnapshot(
                                                            moreFiltersSnapshot,
                                                          );
                                                          unawaited(
                                                            _persistFilters(),
                                                          );
                                                          Navigator.pop(
                                                            context,
                                                          );
                                                        },
                                                        child: Text(
                                                          _cancelTextGlobal(
                                                            context,
                                                          ),
                                                          style: TextStyle(
                                                            color:
                                                                moreFiltersMuted,
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: ElevatedButton(
                                                          style: ElevatedButton.styleFrom(
                                                            backgroundColor:
                                                                Color(
                                                                  0xFFFF6B00,
                                                                ),
                                                            foregroundColor:
                                                                Colors.white,
                                                          ),
                                                          onPressed: () {
                                                            unawaited(
                                                              _persistFilters(),
                                                            );
                                                            onFilterChanged();
                                                            Navigator.pop(
                                                              context,
                                                            );
                                                          },
                                                          child: Text(
                                                            AppLocalizations.of(
                                                              context,
                                                            )!.applyFilters,
                                                            maxLines: 1,
                                                            overflow:
                                                                TextOverflow
                                                                    .ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
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
