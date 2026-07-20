part of 'sell_flow.dart';

mixin _SellStep3BuildPrice on _SellStep3Pickers {
  List<Widget> _sellStep3BuildPriceSection() {
    final style = filterDialogStyle(context);
    final priceLabel = _trLegacyText(
      context,
      'Price ($selectedCurrency) (optional)',
      ar: 'السعر ($selectedCurrency) (اختياري)',
      ku: 'نرخ ($selectedCurrency) (ئیختیاری)',
    );
    final enterPriceHint = _trLegacyText(
      context,
      'Enter price',
      ar: 'أدخل السعر',
      ku: 'نرخ بنووسە',
    );

    return [
      FilterCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FilterSectionHeader(
              title: priceLabel,
              valueSummary: selectedPrice == null ||
                      selectedPrice!.trim().isEmpty
                  ? enterPriceHint
                  : _formatCurrencyGlobal(context, selectedPrice),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    focusNode: _priceFocusNode,
                    controller: _priceController,
                    decoration: filterFieldDecoration(
                      style,
                      enterPriceHint,
                    ).copyWith(
                      prefixText: selectedCurrency == 'IQD' ? 'IQD ' : '\$',
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
                    inputFormatters: const [
                      ThousandsSeparatorInputFormatter(),
                    ],
                    onChanged: (value) {
                      final digits =
                          ThousandsSeparatorInputFormatter.digitsOnly(value);
                      setState(() {
                        selectedPrice = digits.isEmpty
                            ? null
                            : (selectedCurrency == 'IQD'
                                  ? 'IQD $digits'
                                  : '\$$digits');
                      });
                      _syncStep3DraftToParent();
                    },
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return null;
                      }
                      final price = int.tryParse(
                        ThousandsSeparatorInputFormatter.digitsOnly(
                          value.trim(),
                        ),
                      );
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
                        _priceController.text =
                            ThousandsSeparatorInputFormatter.format(
                              numericValue,
                            );
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
              ],
            ),
          ],
        ),
      ),
    ];
  }
}
