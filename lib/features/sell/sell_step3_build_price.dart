part of 'sell_flow.dart';

mixin _SellStep3BuildPrice on _SellStep3Pickers {
  List<Widget> _sellStep3BuildPriceSection() {
    return [
            // Price (Modal or Manual Input)
            Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: isPriceManualInput
                          ? TextFormField(
                              focusNode: _priceFocusNode,
                              controller: _priceController,
                              decoration: InputDecoration(
                                labelText: _trLegacyText(
                                  context,
                                  'Price (optional)',
                                  ar: 'السعر (اختياري)',
                                  ku: 'نرخ (ئیختیاری)',
                                ),
                                hintText: _trLegacyText(
                                  context,
                                  'Enter price',
                                  ar: 'أدخل السعر',
                                  ku: 'نرخ بنووسە',
                                ),
                                prefixText: selectedCurrency == 'IQD'
                                    ? 'IQD '
                                    : '\$',
                                prefixStyle: TextStyle(
                                  color: Color(0xFFFF6B00),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                filled: true,
                                fillColor: _sellFlowManualFieldFill(context),
                                labelStyle: _sellFlowManualFieldLabelStyle(
                                  context,
                                ),
                                hintStyle: _sellFlowManualFieldHintStyle(
                                  context,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                errorBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(color: Colors.red),
                                ),
                              ),
                              style: _sellFlowManualFieldTextStyle(context),
                              keyboardType: TextInputType.number,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _dismissKeyboard(),
                              onTapOutside: (_) => _dismissKeyboard(),
                              inputFormatters: [
                                services.FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (value) {
                                setState(() {
                                  // Store the full price with currency prefix
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
                          : FormField<String>(
                              validator: (_) => null,
                              builder: (state) => GestureDetector(
                                onTap: () async {
                                  final List<String> numericOptions =
                                      selectedCurrency == 'IQD'
                                      ? [
                                          ...List.generate(
                                            200,
                                            (i) => (500000 + i * 500000)
                                                .toString(),
                                          ),
                                          ...List.generate(
                                            100,
                                            (i) =>
                                                (100000000 + (i + 1) * 1000000)
                                                    .toString(),
                                          ),
                                        ].map((p) => 'IQD $p').toList()
                                      : [
                                          ...List.generate(
                                            600,
                                            (i) => (500 + i * 500).toString(),
                                          ),
                                          ...List.generate(
                                            171,
                                            (i) => (300000 + (i + 1) * 10000)
                                                .toString(),
                                          ),
                                        ].map((p) => '\$$p').toList();
                                  final priceOptions = <String>[
                                    _SellStep3Fields._pricePickerNoneOption,
                                    ...numericOptions,
                                  ];
                                  final choice = await _pickFromList(
                                    _trLegacyText(
                                      context,
                                      'Price ($selectedCurrency) (optional)',
                                      ar: 'السعر ($selectedCurrency) (اختياري)',
                                      ku:
                                          'نرخ ($selectedCurrency) (ئیختیاری)',
                                    ),
                                    priceOptions,
                                  );
                                  if (choice != null) {
                                    setState(() {
                                      selectedPrice =
                                          choice == _SellStep3Fields._pricePickerNoneOption
                                          ? null
                                          : choice;
                                    });
                                    _syncStep3DraftToParent();
                                  }
                                },
                                child: buildFancySelector(
                                  context,
                                  currency: selectedCurrency,
                                  label: _trLegacyText(
                                    context,
                                    'Price ($selectedCurrency) (optional)',
                                    ar: 'السعر ($selectedCurrency) (اختياري)',
                                    ku:
                                        'نرخ ($selectedCurrency) (ئیختیاری)',
                                  ),
                                  value: selectedPrice != null
                                      ? _formatCurrencyGlobal(
                                          context,
                                          selectedPrice,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                    ),
                    SizedBox(width: 8),
                    // Currency Selector button (styled like pencil button)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          // Convert price when switching currency
                          if (selectedPrice != null &&
                              selectedPrice!.isNotEmpty) {
                            String convertedPrice = convertSellListingPrice(
                              selectedPrice!,
                              selectedCurrency,
                              selectedCurrency == 'USD' ? 'IQD' : 'USD',
                            );
                            selectedPrice = convertedPrice;
                            // Update controller with numeric value only
                            String numericValue = convertedPrice.replaceAll(
                              RegExp(r'[^\d.]'),
                              '',
                            );
                            _priceController.text = numericValue;
                          }
                          selectedCurrency = selectedCurrency == 'USD'
                              ? 'IQD'
                              : 'USD';
                          // Update global currency symbol
                          globalSymbol = selectedCurrency == 'IQD'
                              ? 'IQD '
                              : r'$';
                        });
                        _syncStep3DraftToParent();
                      },
                      icon: Text(
                        selectedCurrency,
                        style: TextStyle(
                          color: Color(0xFFFF6B00),
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
                      tooltip:
                          _trLegacyText(
                            context,
                            'Switch to ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                            ar:
                                'التبديل إلى ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                            ku:
                                'گۆڕین بۆ ${selectedCurrency == 'USD' ? 'IQD' : 'USD'}',
                          ),
                    ),
                    SizedBox(width: 8),
                    // Pencil/Checkmark button
                    IconButton(
                      onPressed: () {
                        if (isPriceManualInput) {
                          // If in manual input mode, confirm the price and dismiss keyboard
                          _priceFocusNode.unfocus();
                          FocusScope.of(context).unfocus();
                          setState(() {
                            isPriceManualInput = false;
                            // Ensure the selectedPrice is properly formatted
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
                          // If in dropdown mode, switch to manual input
                          setState(() {
                            isPriceManualInput = true;
                            // Clear the controller to start fresh
                            _priceController.clear();
                            selectedPrice = null;
                          });
                          _syncStep3DraftToParent();
                        }
                      },
                      icon: Icon(
                        isPriceManualInput ? Icons.check : Icons.edit,
                        color: Color(0xFFFF6B00),
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
            SizedBox(height: 16),
    ];
  }
}
