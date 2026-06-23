import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/i18n/legacy_inline_text.dart';
import '../../../shared/media/media_url.dart';
import '../../../theme_provider.dart';
import '../car_details_listing_fields.dart';

/// Seller / dealership card on the listing detail page.
class CarDetailsSellerSection extends StatelessWidget {
  const CarDetailsSellerSection({
    super.key,
    required this.car,
  });

  final Map<String, dynamic> car;

  @override
  Widget build(BuildContext context) {
    final Map<String, dynamic> seller = sellerMapFromListing(car) ?? {};
    final bool isLight = Theme.of(context).brightness == Brightness.light;

    final String firstName = (seller['first_name'] ?? '').toString().trim();
    final String lastName = (seller['last_name'] ?? '').toString().trim();
    final String fullName = '$firstName $lastName'.trim();
    final String name =
        (listingFirstNonEmpty(seller, ['name', 'display_name']) ??
                listingFirstNonEmpty(car, [
                  'seller_name',
                  'owner_name',
                  'posted_by',
                ]) ??
                '')
            .trim();
    final String phone =
        (listingFirstNonEmpty(seller, ['phone_number', 'phone', 'mobile']) ??
                sellerPhoneRawForContact(car) ??
                '')
            .trim();
    final String email =
        ((listingFirstNonEmpty(seller, ['email']) ??
                    listingFirstNonEmpty(car, ['seller_email'])) ??
                '')
            .trim();
    final String city =
        ((listingFirstNonEmpty(seller, ['city', 'location']) ??
                    listingFirstNonEmpty(car, ['city', 'location'])) ??
                '')
            .trim();
    final String avatarRaw =
        ((listingFirstNonEmpty(seller, [
                      'profile_picture',
                      'avatar',
                      'avatar_url',
                      'image_url',
                      'photo_url',
                    ]) ??
                    listingFirstNonEmpty(car, ['seller_profile_picture'])) ??
                '')
            .trim();
    final String avatarUrl =
        avatarRaw.isEmpty ? '' : buildLegacyFullImageUrl(avatarRaw);

    final bool isVerified =
        seller['is_verified'] == true || seller['verified'] == true;
    final String accountType = (seller['account_type'] ?? '').toString().trim();
    final String dealerStatus = (seller['dealer_status'] ?? '').toString().trim();
    final String dealershipName =
        (seller['dealership_name'] ?? '').toString().trim();
    final String dealershipLocation =
        (seller['dealership_location'] ?? '').toString().trim();
    final String dealershipDescription =
        (seller['dealership_description'] ?? seller['dealer_description'] ?? '')
            .toString()
            .trim();
    final bool isApprovedDealer =
        accountType == 'dealer' && dealerStatus == 'approved';
    final bool isDealerSeller = accountType == 'dealer';
    final String sellerTypeLabel = isDealerSeller
        ? trLegacyText(context, 'Dealership', ar: 'معرض', ku: 'نمایشگا')
        : trLegacyText(
            context,
            'Private seller',
            ar: 'بائع فردي',
            ku: 'فرۆشیاری تاک',
          );
    final String dealerPublicId =
        (seller['id'] ?? seller['user_id'] ?? '').toString().trim();
    final bool canOpenDealerPage =
        isApprovedDealer && dealerPublicId.isNotEmpty;

    final String displayName = isDealerSeller
        ? ((isApprovedDealer && dealershipName.isNotEmpty)
              ? dealershipName
              : (name.isNotEmpty
                    ? name
                    : (fullName.isNotEmpty
                          ? fullName
                          : trLegacyText(
                              context,
                              'Dealer',
                              ar: 'وكيل',
                              ku: 'وەکیل',
                            ))))
        : sellerTypeLabel;

    final String locationShown =
        (isApprovedDealer && dealershipLocation.isNotEmpty)
            ? dealershipLocation
            : city;

    String initials = 'S';
    if (displayName.isNotEmpty) {
      final List<String> parts = displayName
          .split(RegExp(r'\s+'))
          .where((s) => s.trim().isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        initials = '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      } else {
        initials = parts.first[0].toUpperCase();
      }
    }

    Widget detailRow(IconData icon, String label, String value) {
      if (value.trim().isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: const Color(0xFFFF6B00)),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: isLight
                        ? AppThemes.darkHomeShellBackground
                        : Colors.white70,
                  ),
                  children: [
                    TextSpan(
                      text: '$label: ',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    TextSpan(text: value),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: canOpenDealerPage
            ? () => Navigator.pushNamed(
                  context,
                  '/dealer/profile',
                  arguments: {'dealerPublicId': dealerPublicId},
                )
            : null,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(top: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isLight ? Colors.white : const Color(0xFF1A120E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isLight ? const Color(0x1A000000) : const Color(0x33FF6B00),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: const Color(0x26FF6B00),
                    backgroundImage: isDealerSeller && avatarUrl.isNotEmpty
                        ? NetworkImage(avatarUrl)
                        : null,
                    child: !isDealerSeller
                        ? const Icon(
                            Icons.person,
                            color: Color(0xFFFF6B00),
                            size: 26,
                          )
                        : avatarUrl.isEmpty
                        ? Text(
                            initials,
                            style: const TextStyle(
                              color: Color(0xFFFF6B00),
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isDealerSeller) ...[
                          Text(
                            sellerTypeLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isLight ? Colors.black54 : Colors.white60,
                            ),
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isLight
                                ? AppThemes.darkHomeShellBackground
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isDealerSeller && isVerified)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x1A4CAF50),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF4CAF50),
                            size: 13,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            trLegacyText(
                              context,
                              'Verified',
                              ar: 'موثّق',
                              ku: 'پشتڕاستکراوە',
                            ),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4CAF50),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              if (isDealerSeller) ...[
                detailRow(
                  Icons.phone_outlined,
                  trLegacyText(context, 'Phone', ar: 'الهاتف', ku: 'تەلەفۆن'),
                  phone,
                ),
                detailRow(
                  Icons.email_outlined,
                  trLegacyText(
                    context,
                    'Email',
                    ar: 'البريد الإلكتروني',
                    ku: 'ئیمەیل',
                  ),
                  email,
                ),
              ],
              if (isDealerSeller)
                detailRow(
                  Icons.location_on_outlined,
                  trLegacyText(context, 'Location', ar: 'الموقع', ku: 'شوێن'),
                  locationShown,
                ),
              if (isDealerSeller)
                detailRow(
                  Icons.notes_outlined,
                  AppLocalizations.of(context)?.descriptionTitle ?? 'Description',
                  dealershipDescription,
                ),
              if (canOpenDealerPage)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    trLegacyText(
                      context,
                      'Tap to open dealership page',
                      ar: 'اضغط لفتح صفحة المعرض',
                      ku: 'کرتە بکە بۆ کردنەوەی پەڕەی نمایشگا',
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: isLight ? Colors.black54 : Colors.white60,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
