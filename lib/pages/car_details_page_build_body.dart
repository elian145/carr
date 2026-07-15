part of 'car_details_page.dart';

mixin _CarDetailsPageBuildBody on _CarDetailsPageBuildHero {
  Widget _buildCarDetailsBodySliver(BuildContext context, bool isLightShell) {
                return                 SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    color: isLightShell
                        ? AppThemes.lightAppBackground
                        : AppThemes.darkHomeShellBackground,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    child: Theme(
                      data: isLightShell
                          ? Theme.of(context)
                          : AppThemes.darkTheme,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Specifications label lives in the title sheet above.
                          const SizedBox(height: 12),
                          _buildSpecsGrid(),
                          const SizedBox(height: 24),

                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!_isListingSold && _hasDialableSellerPhone) ...[
                                Container(
                                  key: _contactButtonsKey,
                                  child: _buildContactButtonsRow(),
                                ),
                                SizedBox(height: 6),
                              ],
                              ComparisonButton(car: car!),
                              if (!_isListingSold) ...[
                              SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                height: 46,
                                child: OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Color(0xFFFF6B00),
                                    side: BorderSide(color: Color(0xFFFF6B00)),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    minimumSize: Size(0, 46),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(17),
                                    ),
                                  ),
                                  onPressed: _openCarzoChat,
                                  icon: Icon(Icons.forum_outlined, size: 19),
                                  label: Text(
                                    AppLocalizations.of(context)!.chatOnCarzo,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                              ],
                              CarDetailsSellerSection(car: car!),
                            ],
                          ),
                          SizedBox(height: 28),
                          if (similarCars.isNotEmpty) ...[
                            Text(
                              AppLocalizations.of(context)!.similarListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            CarDetailsHorizontalList(
                              items: similarCars,
                              listingColumnsPref: _listingColumnsPref,
                            ),
                            SizedBox(height: 28),
                          ] else if (loadingSimilar) ...[
                            Text(
                              AppLocalizations.of(context)!.similarListings,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isLightShell
                                    ? AppThemes.darkHomeShellBackground
                                    : Colors.white,
                              ),
                            ),
                            SizedBox(height: 12),
                            SizedBox(
                              height: 120,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
  }

  Widget _buildSpecsGrid() => buildCarListingSpecsGrid(context, car!);
}
