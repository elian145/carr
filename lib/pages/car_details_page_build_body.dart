part of 'car_details_page.dart';

mixin _CarDetailsPageBuildBody on _CarDetailsPageBuildHero {
  Widget _buildCarDetailsBodySliver(BuildContext context, bool isLightShell) {
    return                 SliverToBoxAdapter(
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isLightShell
                          ? AppThemes.lightAppBackground
                          : Colors.transparent,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(24),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    child: Theme(
                      data: isLightShell
                          ? Theme.of(context)
                          : AppThemes.darkTheme,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Quick Sell Banner
                          if (car!['is_quick_sell'] == true ||
                              car!['is_quick_sell'] == 'true')
                            Container(
                              width: double.infinity,
                              padding: EdgeInsets.symmetric(
                                vertical: 12,
                                horizontal: 16,
                              ),
                              margin: EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [Colors.orange, Colors.deepOrange],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.flash_on,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    AppLocalizations.of(context)!.quickSell,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          // Brand full width; price aligns with model line (same row as model)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _displayBrandName(context),
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: isLightShell
                                            ? AppThemes.darkHomeShellBackground
                                            : Colors.white,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (car!['price'] != null &&
                                      _displayModelName(context).isEmpty) ...[
                                    SizedBox(width: 12),
                                    Text(
                                      formatCurrency(
                                        context,
                                        car!['price'],
                                      ),
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFF6B00),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (_displayModelName(context).isNotEmpty) ...[
                                SizedBox(height: 4),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _displayModelName(context),
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: isLightShell
                                              ? Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant
                                              : Colors.white70,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (car!['price'] != null) ...[
                                      SizedBox(width: 12),
                                      Text(
                                        formatCurrency(
                                          context,
                                          car!['price'],
                                        ),
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFFFF6B00),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ],
                          ),
                          // City + listing age under model/price
                          Builder(
                            builder: (context) {
                              final cityDetail =
                                  (listingFirstNonEmpty(car!, [
                                            'city',
                                            'location',
                                          ]) ??
                                          '')
                                      .trim();
                              final cityLabelStyle = TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: isLightShell
                                    ? const Color(0xFF757575)
                                    : Colors.white70,
                              );
                              final uploadedDetail = listingUploadedAgo(
                                context,
                                car!,
                              );
                              if (cityDetail.isEmpty &&
                                  uploadedDetail.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const SizedBox(height: 10),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: cityDetail.isEmpty
                                            ? const SizedBox.shrink()
                                            : Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.location_city,
                                                    size: 14,
                                                    color: isLightShell
                                                        ? const Color(
                                                            0xFF757575,
                                                          )
                                                        : Colors.white70,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Flexible(
                                                    child: Text(
                                                      '${AppLocalizations.of(context)!.cityLabel}: '
                                                      '${translateListingValue(context, listingFirstNonEmpty(car!, ['city', 'location'])) ?? listingFirstNonEmpty(car!, ['city', 'location'])}',
                                                      style: cityLabelStyle,
                                                      // Allow long cities like "Sulaymaniyah" to show fully.
                                                      maxLines: 2,
                                                      overflow: TextOverflow.clip,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                      ),
                                      if (uploadedDetail.isNotEmpty) ...[
                                        if (cityDetail.isNotEmpty)
                                          const SizedBox(width: 8),
                                        Text(
                                          uploadedDetail,
                                          style: cityLabelStyle.copyWith(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 12,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ],
                              );
                            },
                          ),
                          const SizedBox(height: 16),

                          Divider(
                            height: 1,
                            thickness: 1,
                            color: isLightShell
                                ? const Color(0xFFE0E0E0)
                                : Colors.white24,
                          ),
                          SizedBox(height: 16),
                          Text(
                            AppLocalizations.of(context)!.specificationsLabel,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B00),
                            ),
                          ),
                          SizedBox(height: 20),
                          _buildSpecsGrid(),
                          SizedBox(height: 24),

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
                              snapController: _similarSnapController,
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
                            SizedBox(height: 28),
                          ],
                          if (relatedCars.isNotEmpty) ...[
                            Text(
                              AppLocalizations.of(context)!.relatedListings,
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
                              items: relatedCars,
                              listingColumnsPref: _listingColumnsPref,
                              snapController: _relatedSnapController,
                            ),
                          ] else if (loadingRelated) ...[
                            Text(
                              AppLocalizations.of(context)!.relatedListings,
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
