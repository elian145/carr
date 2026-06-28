part of 'global_listing_card.dart';

/// Video count pill used on global listing cards (grid + list layout).
Widget _globalListingCardVideoCountBadge(Map car) {
  return Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.videocam, color: Colors.white, size: 16),
        const SizedBox(width: 4),
        Text(
          '${(car['videos'] as List).length}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    ),
  );
}

// Global image carousel for consistency
Widget _buildGlobalCardImageCarousel(
  BuildContext context,
  Map car, {
  int carouselResetSeed = 0,
  bool enableDetailTap = true,
  bool allowOwnerManagementOnOpen = false,
}) {
  final slots = ListingCardMedia.collectFromCar(
    car,
    resolveNetworkUrl: buildLegacyFullImageUrl,
  );

  if (slots.isEmpty) {
    return Container(
      color: Colors.grey[900],
      width: double.infinity,
      child: Icon(Icons.directions_car, size: 60, color: Colors.grey[400]),
    );
  }

  int currentIndex = 0;
  const int kMaxVisibleDots = 6;
  int dotWindowStart = 0;

  return StatefulBuilder(
    key: ValueKey(
      'global_card_carousel_${car['id'] ?? car['draftId'] ?? ''}_$carouselResetSeed',
    ),
    builder: (context, setState) {
      int computeDotStart(int index) {
        final int visible =
            slots.length < kMaxVisibleDots ? slots.length : kMaxVisibleDots;
        if (visible <= 0 || slots.length <= visible) return 0;
        final int maxStart = (slots.length - visible).clamp(0, slots.length);
        return (index - (visible - 1)).clamp(0, maxStart);
      }

      final pageView = PageView.builder(
        onPageChanged: (i) {
          setState(() {
            currentIndex = i;
            final nextStart = computeDotStart(i);
            if (nextStart != dotWindowStart) {
              dotWindowStart = nextStart;
            }
          });
        },
        itemCount: slots.length,
        itemBuilder: (context, i) {
          return ListingCardMedia.buildCarouselImage(
            slots[i],
            networkBuilder: listingNetworkImage,
            fit: BoxFit.cover,
          );
        },
      );

      final carId = (car['id'] ?? '').toString().trim();
      final Widget pager = enableDetailTap && carId.isNotEmpty
          ? GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/car_detail',
                  arguments: {
                    'carId': carId,
                    if (allowOwnerManagementOnOpen)
                      'allowOwnerManagement': true,
                  },
                );
              },
              child: pageView,
            )
          : pageView;

      return Stack(
        fit: StackFit.expand,
        children: [
          pager,
          if (slots.length > 1)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: () {
                  final int visible = slots.length < kMaxVisibleDots
                      ? slots.length
                      : kMaxVisibleDots;
                  if (visible <= 1) return const SizedBox.shrink();

                  Widget buildDotRow(int startIndex) {
                    return Row(
                      key: ValueKey<int>(startIndex),
                      mainAxisSize: MainAxisSize.min,
                      children: List.generate(visible, (j) {
                        final i = startIndex + j;
                        final active = i == currentIndex;
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: active ? 8 : 6,
                          height: active ? 8 : 6,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : Colors.white70,
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    );
                  }

                  final start = dotWindowStart.clamp(
                    0,
                    (slots.length - visible).clamp(0, slots.length),
                  );

                  return buildDotRow(start);
                }(),
              ),
            ),
        ],
      );
    },
  );
}
