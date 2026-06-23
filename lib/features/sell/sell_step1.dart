part of 'sell_flow.dart';

class SellStep1Page extends StatefulWidget {
  const SellStep1Page({super.key, this.resumeDraftToken = 0});

  final int resumeDraftToken;

  @override
  State<SellStep1Page> createState() => _SellStep1PageState();
}

class _SellStep1PageState extends _SellStep1Fields
    with _SellStep1Catalog, _SellStep1Pickers, _SellStep1Build {
  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController();
    _yearController.addListener(_onYearTextForCatalog);
    _resetSellFilters();
    _hydrateFromParentCarData();
    CarSpecIndex.loadWithResult().then((r) {
      if (!mounted) return;
      setState(() {
        _specIdx = r.index;
        _specLoadErr = r.errorMessage;
        _specDbReady = true;
        _pruneYearOutsideCatalog();
      });
      _schedDsRefresh();
    });
  }

  @override
  void didUpdateWidget(covariant SellStep1Page oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.resumeDraftToken != oldWidget.resumeDraftToken ||
        widget.resumeDraftToken > 0) {
      _hydrateFromParentCarData();
    }
  }

  @override
  void dispose() {
    if (!LegacySellDraftPrefs.suppressPersist) {
      unawaited(_saveDraft());
    }
    _yearFocusNode.dispose();
    _yearController.removeListener(_onYearTextForCatalog);
    _yearController.dispose();
    super.dispose();
  }
}
