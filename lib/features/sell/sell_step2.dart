part of 'sell_flow.dart';

class SellStep2Page extends StatefulWidget {
  const SellStep2Page({super.key, this.specsHydrateToken = ''});

  /// When catalog/online/AI specs timestamps change, state re-reads [carData] (covers off-screen step 2).
  final String specsHydrateToken;

  @override
  State<SellStep2Page> createState() => _SellStep2PageState();
}

class _SellStep2PageState extends _SellStep2Fields
    with _SellStep2Logic, _SellStep2Build {
  @override
  void initState() {
    super.initState();
    _mileageController = TextEditingController();
    _engineSizeController = TextEditingController();
    _vinController = TextEditingController();
    _resetStep2();
    _hydrateFromParentCarData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _hydrateFromParentCarData(force: true);
    });
    CarSpecIndex.load().then((idx) {
      if (!mounted) return;
      setState(() {
        _specIdx = idx;
        _refreshCatalogOptsFromParent();
      });
    });
  }

  @override
  void didUpdateWidget(covariant SellStep2Page oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.specsHydrateToken != oldWidget.specsHydrateToken) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _hydrateFromParentCarData(force: true);
      });
    }
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _mileageFocusNode.dispose();
    _engineSizeFocusNode.dispose();
    _mileageController.dispose();
    _engineSizeController.dispose();
    _vinController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _hydrateFromParentCarData();
  }

}
