part of 'car_details_page.dart';

mixin _CarDetailsPageLifecycle on _CarDetailsPageMedia {
  void _onScroll() {
    final keyContext = _contactButtonsKey.currentContext;
    if (keyContext == null) return;
    final box = keyContext.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final pos = box.localToGlobal(Offset.zero);
    final screenH = MediaQuery.of(context).size.height;
    final visible = pos.dy < screenH;
    if (visible == !_showStickyButtons) return;
    setState(() => _showStickyButtons = !visible);
  }

  /// Start loading all listing images into cache so they appear immediately when the user views the carousel.
  void _precacheListingImages() {
    if (!mounted || car == null) return;
    final urls = _imageUrls;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in urls) {
        if (url.isEmpty) continue;
        precacheImage(NetworkImage(url), context);
      }
    });
  }

  void _clampHeroMediaIndex() {
    final n = _heroMediaCount;
    if (n <= 0) {
      if (_currentImageIndex != 0) {
        if (mounted) setState(() => _currentImageIndex = 0);
      }
      return;
    }
    if (_currentImageIndex >= n) {
      final newIndex = n - 1;
      if (mounted) setState(() => _currentImageIndex = newIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_imagePageController.hasClients) {
          _imagePageController.jumpToPage(newIndex);
        }
      });
    }
  }
}
