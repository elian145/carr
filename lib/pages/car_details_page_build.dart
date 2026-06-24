part of 'car_details_page.dart';

mixin _CarDetailsPageBuild on _CarDetailsPageBuildBody {
  @override
  Widget build(BuildContext context) {
    final isLightShell = Theme.of(context).brightness == Brightness.light;
    final stickyButtons = (!loading && car != null && !_isListingSold && _hasDialableSellerPhone && _showStickyButtons);

    return Scaffold(
      backgroundColor: isLightShell ? Colors.white : null,
      body: Stack(
        children: [
          loading
          ? Center(child: CircularProgressIndicator())
          : car == null
          ? Center(child: Text(AppLocalizations.of(context)!.carNotFound))
          : CustomScrollView(
              controller: _scrollController,
              slivers: [
                _buildCarDetailsHeroSliver(context, isLightShell),
                _buildCarDetailsBodySliver(context, isLightShell),
              ],
            ),
          if (stickyButtons)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 12,
              child: _buildContactButtonsRow(),
            ),
        ],
      ),
    );
  }
}
