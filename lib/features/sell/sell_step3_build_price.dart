part of 'sell_flow.dart';

mixin _SellStep3BuildPrice on _SellStep3Pickers {
  List<String> _sellPriceDropdownOptions() {
    if (selectedCurrency == 'IQD') {
      return [
        ...List.generate(200, (i) => (500000 + i * 500000).toString()),
        ...List.generate(
          100,
          (i) => (100000000 + (i + 1) * 1000000).toString(),
        ),
      ].map((p) => 'IQD $p').toList();
    }
    return [
      ...List.generate(600, (i) => (500 + i * 500).toString()),
      ...List.generate(
        171,
        (i) => (300000 + (i + 1) * 10000).toString(),
      ),
    ].map((p) => '\$$p').toList();
  }

  List<Widget> _sellStep3BuildPriceSection() {
    final style = filterDialogStyle(context);
    final priceLabel = _trLegacyText(
      context,
      'Price ($selectedCurrency) (optional)',
      ar: 'السعر ($selectedCurrency) (اختياري)',
      ku: 'نرخ ($selectedCurrency) (ئیختیاری)',
    );
    final priceOptions = _sellPriceDropdownOptions();

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: priceLabel,
              valueSummary: selectedPrice == null
                  ? AppLocalizations.of(context)!.tapToSelect
                  : _formatCurrencyGlobal(context, selectedPrice),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: isPriceManualInput
                      ? TextFormField(
                          focusNode: _priceFocusNode,
                          controller: _priceController,
                          decoration: filterFieldDecoration(
                            style,
                            priceLabel,
                          ).copyWith(
                            prefixText: selectedCurrency == 'IQD'
                                ? 'IQD '
                                : '\$',
                            prefixStyle: const TextStyle(
                              color: kFilterAccentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          style: TextStyle(color: style.onSurface),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _dismissKeyboard(),
                          onTapOutside: (_) => _dismissKeyboard(),
                          inputFormatters: [
                            services.FilteringTextInputFormatter.digitsOnly,
                          ],
                          onChanged: (value) {
                            setState(() {
                              selectedPrice = value.isEmpty
                                  ? null
                                  : (selectedCurrency == 'IQD'
                                        ? 'IQD $value'
                                        : '\$$value');
                            });
                            _syncStep3DraftToParent();
                          },
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return null;
                            }
                            final price = int.tryParse(value.trim());
                            if (price == null) {
                              return _trLegacyText(
                                context,
                                'Invalid price',
                                ar: 'سعر غير صالح',
                                ku: 'نرخی نادروست',
                              );
                            }
                            if (price < 0) {
                              return _trLegacyText(
                                context,
                                'Price cannot be negative',
                                ar: 'لا يمكن أن يكون السعر سالبا',
                                ku: 'نرخ ناتوانێت سالب بێت',
                              );
                            }
                            return null;
                          },
                        )
                      : DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: selectedPrice != null &&
                                  priceOptions.contains(selectedPrice)
                              ? selectedPrice
                              : null,
                          decoration: filterFieldDecoration(style, priceLabel),
                          items: [
                            DropdownMenuItem<String>(
                              value: null,
                              child: Text(
                                AppLocalizations.of(context)!.tapToSelect,
                                style: TextStyle(
                                  color: style.anyOrange,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            ...priceOptions.map(
                              (price) => DropdownMenuItem<String>(
                                value: price,
                                child: Text(
                                  _formatCurrencyGlobal(context, price),
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setState(() => selectedPrice = value);
                            _syncStep3DraftToParent();
                          },
                        ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    setState(() {
                      if (selectedPrice != null && selectedPrice!.isNotEmpty) {
                        final convertedPrice = convertSellListingPrice(
                          selectedPrice!,
                          selectedCurrency,
                          selectedCurrency == 'USD' ? 'IQD' : 'USD',
                        );
                        selectedPrice = convertedPrice;
                        final numericValue = convertedPrice.replaceAll(
                          RegExp(r'[^\d.]'),
                          '',
                        );
                        _priceController.text = numericValue;
                      }
                      selectedCurrency =
                          selectedCurrency == 'USD' ? 'IQD' : 'USD';
                      globalSymbol =
                          selectedCurrency == 'IQD' ? 'IQD ' : r'$';
                    });
                    _syncStep3DraftToParent();
                  },
                  icon: Text(
                    selectedCurrency,
                    style: const TextStyle(
                      color: kFilterAccentColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: _trLegacyText(
                    context,
                    'Switch to ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                    ar: 'التبديل إلى ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                    ku: 'گۆڕین بۆ ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () {
                    if (isPriceManualInput) {
                      _priceFocusNode.unfocus();
                      FocusScope.of(context).unfocus();
                      setState(() {
                        isPriceManualInput = false;
                        if (_priceController.text.isNotEmpty) {
                          final numericValue = _priceController.text;
                          selectedPrice = selectedCurrency == 'IQD'
                              ? 'IQD $numericValue'
                              : '\$$numericValue';
                        } else {
                          selectedPrice = null;
                        }
                      });
                      _syncStep3DraftToParent();
                    } else {
                      setState(() {
                        isPriceManualInput = true;
                        _priceController.clear();
                        selectedPrice = null;
                      });
                      _syncStep3DraftToParent();
                    }
                  },
                  icon: Icon(
                    isPriceManualInput ? Icons.check : Icons.edit,
                    color: kFilterAccentColor,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.grey.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  tooltip: isPriceManualInput
                      ? AppLocalizations.of(context)!.confirmYear
                      : AppLocalizations.of(context)!.typeManually,
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }
}
