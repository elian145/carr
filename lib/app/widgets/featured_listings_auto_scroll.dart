import 'dart:async';

import 'package:flutter/material.dart';

import 'featured_listing_card.dart';

/// Horizontal featured carousel that advances one full listing at a time
/// and loops continuously in both directions.
class FeaturedListingsAutoScroll extends StatefulWidget {
  const FeaturedListingsAutoScroll({
    super.key,
    required this.cars,
    required this.height,
    required this.cardWidth,
    this.horizontalPadding = 12,
    this.verticalPadding = 10,
    this.separatorWidth = 12,
    this.pageInterval = const Duration(seconds: 4),
    this.pageAnimation = const Duration(milliseconds: 450),
  });

  final List<Map<String, dynamic>> cars;
  final double height;
  final double cardWidth;
  final double horizontalPadding;
  final double verticalPadding;
  final double separatorWidth;
  final Duration pageInterval;
  final Duration pageAnimation;

  @override
  State<FeaturedListingsAutoScroll> createState() =>
      _FeaturedListingsAutoScrollState();
}

class _FeaturedListingsAutoScrollState extends State<FeaturedListingsAutoScroll> {
  /// Large virtual page space so swipe / auto-advance never hits an edge.
  static const int _kVirtualCount = 100000;

  PageController? _pageController;
  Timer? _timer;
  bool _userInteracting = false;
  bool _animating = false;
  int _page = 0;

  int get _realCount => widget.cars.length;

  int _realIndex(int page) {
    if (_realCount == 0) return 0;
    return page % _realCount;
  }

  int _initialPage() {
    if (_realCount == 0) return 0;
    // Start near the middle, aligned to a real index of 0.
    final mid = _kVirtualCount ~/ 2;
    return mid - (mid % _realCount);
  }

  @override
  void initState() {
    super.initState();
    _initController();
    _startAutoScroll();
  }

  void _initController() {
    _page = _initialPage();
    _pageController = PageController(initialPage: _page);
  }

  @override
  void didUpdateWidget(covariant FeaturedListingsAutoScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cars.length != widget.cars.length) {
      _timer?.cancel();
      _pageController?.dispose();
      _initController();
      _startAutoScroll();
      setState(() {});
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController?.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    _timer?.cancel();
    if (_realCount < 2) return;
    _timer = Timer.periodic(widget.pageInterval, (_) => _goNext());
  }

  Future<void> _goNext() async {
    final controller = _pageController;
    if (!mounted || controller == null) return;
    if (_userInteracting || _animating) return;
    if (!controller.hasClients) return;
    if (_realCount < 2) return;

    final next = _page + 1;
    _animating = true;
    try {
      await controller.animateToPage(
        next,
        duration: widget.pageAnimation,
        curve: Curves.easeInOut,
      );
      if (mounted) _page = next;
    } finally {
      _animating = false;
    }
  }

  void _pauseForUser() {
    _userInteracting = true;
  }

  void _scheduleResume() {
    Future<void>.delayed(const Duration(milliseconds: 2500), () {
      if (!mounted) return;
      _userInteracting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = _pageController;
    if (controller == null || _realCount == 0) {
      return SizedBox(height: widget.height + widget.verticalPadding * 2);
    }

    final totalH = widget.height + widget.verticalPadding * 2;
    final itemCount = _realCount < 2 ? _realCount : _kVirtualCount;

    return SizedBox(
      height: totalH,
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n is ScrollStartNotification && n.dragDetails != null) {
            _pauseForUser();
          } else if (n is ScrollEndNotification) {
            _scheduleResume();
          }
          return false;
        },
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: widget.verticalPadding),
          child: PageView.builder(
            controller: controller,
            clipBehavior: Clip.none,
            itemCount: itemCount,
            onPageChanged: (i) => _page = i,
            itemBuilder: (context, index) {
              final car = widget.cars[_realIndex(index)];
              return Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: widget.horizontalPadding,
                ),
                child: SizedBox(
                  width: widget.cardWidth,
                  height: widget.height,
                  child: FeaturedListingCard(car: car),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
