part of 'car_details_page.dart';

mixin _CarDetailsPageBuild on _CarDetailsPageBuildBody {
  /// Localized message for a non-"not found" load failure, reusing the
  /// existing home-feed network/server copy and auth copy rather than
  /// introducing new strings (F-01).
  String _loadErrorMessage(BuildContext context, _CarDetailLoadError error) {
    final loc = AppLocalizations.of(context)!;
    switch (error.kind) {
      case _CarDetailLoadErrorKind.authRequired:
        return loc.authenticationRequired;
      case _CarDetailLoadErrorKind.server:
        final code = error.statusCode;
        return code != null
            ? loc.homeFeedServerError(code.toString())
            : loc.homeFeedNetworkError;
      case _CarDetailLoadErrorKind.network:
      case _CarDetailLoadErrorKind.notFound:
        return loc.homeFeedNetworkError;
    }
  }

  void _retryLoadCar() {
    setState(() {
      loading = true;
      loadError = null;
    });
    _loadCar();
  }

  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final stickyButtons = (!loading && car != null && !_isListingSold && _hasDialableSellerPhone && _showStickyButtons);

    final Widget content;
    if (loading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (car != null) {
      content = CustomScrollView(
        clipBehavior: Clip.none,
        controller: _scrollController,
        slivers: [
          _buildCarDetailsHeroSliver(context, isLightShell),
          _buildCarDetailsBodySliver(context, isLightShell),
        ],
      );
    } else if (loadError != null &&
        loadError!.kind != _CarDetailLoadErrorKind.notFound) {
      // Transient/server/network/auth failure with no usable cache: show a
      // retry-able error state instead of implying the listing was deleted.
      content = HomeFeedErrorState(
        message: _loadErrorMessage(context, loadError!),
        onRetry: _retryLoadCar,
      );
    } else {
      // Confirmed 404 (or the initial, error-less null state).
      content = Center(child: Text(AppLocalizations.of(context)!.carNotFound));
    }

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      body: Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          if (stickyButtons)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.viewPaddingOf(context).bottom + 12,
              child: _buildContactButtonsRow(),
            ),
        ],
      ),
    );
  }
}
