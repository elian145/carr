part of 'sell_flow.dart';

mixin _SellStepBlurChoiceFields on State<SellStepBlurChoicePage> {
  bool? _useBlurredPlates;
}

mixin _SellStepBlurChoiceLogic on _SellStepBlurChoiceFields {
  bool _didLoadChoice = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadChoice) return;
    _didLoadChoice = true;
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    final raw = parent?.carData['use_blurred_plates'];
    if (raw is bool) {
      _useBlurredPlates = raw;
    }
    // Keep background blur going if photos were added earlier but blur never finished.
    if (parent != null &&
        !parent.hasBlurredPlatesReady &&
        !parent.isBlurringPlates) {
      final originals =
          parent.carData['original_images'] ?? parent.carData['images'];
      final damage = parent.carData['original_damage_images'] ??
          parent.carData['damage_images'];
      final hasMain = originals is List && originals.isNotEmpty;
      final hasDamage = damage is List && damage.isNotEmpty;
      if (hasMain || hasDamage) {
        unawaited(parent.startBackgroundPlateBlur());
      }
    }
  }

  List<dynamic> _originalImages(Map<String, dynamic> carData) {
    final originals = carData['original_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final images = carData['images'];
    if (images is List) return List<dynamic>.from(images);
    return const [];
  }

  List<dynamic> _blurredImages(Map<String, dynamic> carData) {
    final blurred = carData['blurred_images'];
    if (blurred is List && blurred.isNotEmpty) {
      return List<dynamic>.from(blurred);
    }
    return const [];
  }

  List<dynamic> _damageOriginalImages(Map<String, dynamic> carData) {
    final originals = carData['original_damage_images'];
    if (originals is List && originals.isNotEmpty) {
      return List<dynamic>.from(originals);
    }
    final damage = carData['damage_images'];
    if (damage is List) return List<dynamic>.from(damage);
    return const [];
  }

  List<dynamic> _damageBlurredImages(Map<String, dynamic> carData) {
    final blurred = carData['blurred_damage_images'];
    if (blurred is List && blurred.isNotEmpty) {
      return List<dynamic>.from(blurred);
    }
    return const [];
  }

  void _selectChoice(bool useBlurred) {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    setState(() => _useBlurredPlates = useBlurred);
    applySellPlateBlurChoice(parent.carData, useBlurred);
    parent.setState(() {});
    unawaited(parent._saveSellDraftSnapshot());
  }

  Future<void> _retryBackgroundBlur() async {
    final parent = context.findAncestorStateOfType<_SellCarPageState>();
    if (parent == null) return;
    await parent.startBackgroundPlateBlur(
      interactive: true,
      uiContext: context,
    );
  }
}
