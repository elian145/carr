part of 'sell_flow.dart';

mixin _SellStep3BuildDetails on _SellStep3BuildPrice {
  List<Widget> _sellStep3BuildDetailsSection() {
    final loc = AppLocalizations.of(context)!;

    return [
      FilterIconCardSection(
        title: loc.cityLabel,
        options: cities,
        selected: selectedCity,
        requiredField: true,
        scrollHorizontally: true,
        tileWidth: 100,
        textOnly: true,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() => selectedCity = value);
          _syncStep3DraftToParent();
        },
        onClear: selectedCity != null
            ? () {
                setState(() => selectedCity = null);
                _syncStep3DraftToParent();
              }
            : null,
      ),
      FilterIconCardSection(
        title: _trLegacyText(
          context,
          'Plate type',
          ar: 'نوع اللوحة',
          ku: 'جۆری پڵەیت',
        ),
        options: _plateTypeOptions,
        selected: selectedPlateType,
        scrollHorizontally: true,
        tileWidth: 120,
        tileImageWidth: 96,
        tileImageHeight: 24,
        iconForOption: filterPlateTypeIcon,
        imageAssetForOption: plateTypeImageAsset,
        labelForOption: (ctx, o) => _translatePlateTypeLegacy(ctx, o),
        onSelected: (value) {
          setState(() => selectedPlateType = value?.toLowerCase());
          _syncStep3DraftToParent();
        },
        onClear: selectedPlateType != null
            ? () {
                setState(() => selectedPlateType = null);
                _syncStep3DraftToParent();
              }
            : null,
      ),
      FilterIconCardSection(
        title: _trLegacyText(
          context,
          'Plate city',
          ar: 'مدينة اللوحة',
          ku: 'شاری پڵەیت',
        ),
        options: _plateCities,
        selected: selectedPlateCity,
        scrollHorizontally: true,
        tileWidth: 148,
        tileImageWidth: 132,
        tileImageHeight: 40,
        compactImageTile: true,
        iconForOption: filterPlateCityIcon,
        imageAssetForOption: plateCityImageAsset,
        labelForOption: (ctx, o) => _translateValueGlobal(ctx, o) ?? o,
        onSelected: (value) {
          setState(() => selectedPlateCity = value);
          _syncStep3DraftToParent();
        },
        onClear: selectedPlateCity != null
            ? () {
                setState(() => selectedPlateCity = null);
                _syncStep3DraftToParent();
              }
            : null,
      ),
      const SizedBox(height: 16),
      TextFormField(
        controller: _phoneController,
        decoration: InputDecoration(
          labelText: _trLegacyText(
            context,
            'WhatsApp/Phone Number *',
            ar: 'رقم واتساب/الهاتف *',
            ku: 'ژمارەی واتساپ/مۆبایل *',
          ),
          hintText: '7XX XXX XXXX',
          filled: true,
          fillColor: _sellFlowManualFieldFill(context),
          labelStyle: _sellFlowManualFieldLabelStyle(context),
          hintStyle: _sellFlowManualFieldHintStyle(context),
          prefixText: '+964 ',
          prefixStyle: const TextStyle(
            color: kFilterAccentColor,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          prefixIcon: const Icon(Icons.phone, color: kFilterAccentColor),
        ),
        style: _sellFlowManualFieldTextStyle(context),
        keyboardType: TextInputType.phone,
        inputFormatters: [
          services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
          services.LengthLimitingTextInputFormatter(10),
        ],
        onChanged: (value) {
          setState(() => contactPhone = '+964$value');
          _syncStep3DraftToParent();
        },
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return _trLegacyText(
              context,
              'Please enter phone number',
              ar: 'يرجى إدخال رقم الهاتف',
              ku: 'تکایە ژمارەی مۆبایل بنووسە',
            );
          }
          if (value.trim().length < 10) {
            return _trLegacyText(
              context,
              'Please enter a valid phone number',
              ar: 'يرجى إدخال رقم هاتف صحيح',
              ku: 'تکایە ژمارەی دروست بنووسە',
            );
          }
          return null;
        },
      ),
      const SizedBox(height: 24),
      TextFormField(
        controller: _descriptionController,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText:
              AppLocalizations.of(context)?.descriptionOptionalLabel ??
              'Description (optional)',
          hintText: _trLegacyText(
            context,
            'Add details about the car, condition, features, or notes',
            ar: 'أضف تفاصيل عن السيارة والحالة والمزايا أو ملاحظات',
            ku: 'وردەکاری دەربارەی ئۆتۆمبێلەکە، دۆخ، تایبەتمەندیەکان یان تێبینی زیاد بکە',
          ),
          filled: true,
          fillColor: _sellFlowManualFieldFill(context),
          labelStyle: _sellFlowManualFieldLabelStyle(context),
          hintStyle: _sellFlowManualFieldHintStyle(context),
          prefixIcon: const Icon(
            Icons.description_outlined,
            color: kFilterAccentColor,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          alignLabelWithHint: true,
        ),
        style: _sellFlowManualFieldTextStyle(context),
        onChanged: (_) => _syncStep3DraftToParent(),
      ),
      const SizedBox(height: 24),
    ];
  }
}
