part of 'home_flow.dart';

mixin _HomePageFilterBarBrand on _HomePageFilterLogic {
  Future<String?> _showHomeBrandPickerDialog(BuildContext context) {
    return showDialog<String>(
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
  }

  Future<void> _pickHomeBrand(BuildContext context) async {
    final brand = await _showHomeBrandPickerDialog(context);
    if (brand != null) {
      setState(() {
        selectedBrand = brand;
        selectedModel = null;
        selectedTrim = null;
        clearFiltersOnVehicleChange();
      });
      onFilterChanged();
    }
  }
}
