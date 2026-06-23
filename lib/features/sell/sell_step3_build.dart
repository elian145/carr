part of 'sell_flow.dart';

mixin _SellStep3Build on _SellStep3Body {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _dismissKeyboard,
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFFFF6B00).withValues(alpha: 0.1), Colors.white],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Color(0xFFFF6B00).withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.attach_money, size: 48, color: Color(0xFFFF6B00)),
                  SizedBox(height: 12),
                  Text(
                    AppLocalizations.of(context)!.pricingContactTitle,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    _trLegacyText(
                      context,
                      'Set your price and contact information',
                      ar: 'حدد السعر ومعلومات التواصل',
                      ku: 'نرخ و زانیاری پەیوەندی دابنێ',
                    ),
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),

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
                                    _SellStep3Body._pricePickerNoneOption,
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
                                          choice == _SellStep3Body._pricePickerNoneOption
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
                            String convertedPrice = _convertCurrency(
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

            // City (Modal)
            FormField<String>(
              validator: (_) =>
                  selectedCity == null
                      ? _trLegacyText(
                          context,
                          'Please select city',
                          ar: 'يرجى اختيار المدينة',
                          ku: 'تکایە شار هەڵبژێرە',
                        )
                      : null,
              builder: (state) => GestureDetector(
                onTap: () async {
                  _dismissKeyboard();
                  final choice = await _pickFromList(
                    AppLocalizations.of(context)!.cityLabel,
                    cities,
                  );
                  if (choice != null) {
                    setState(() => selectedCity = choice);
                    _syncStep3DraftToParent();
                  }
                },
                child: buildFancySelector(
                  context,
                  icon: Icons.location_city,
                  label: '${AppLocalizations.of(context)!.cityLabel} *',
                  value: _translateValueGlobal(context, selectedCity),
                ),
              ),
            ),
            SizedBox(height: 16),

            // Plate Type (Optional)
            GestureDetector(
              onTap: () async {
                _dismissKeyboard();
                final choice = await _pickFromList(
                  _trLegacyText(
                    context,
                    'Plate type',
                    ar: 'نوع اللوحة',
                    ku: 'جۆری پڵەیت',
                  ),
                  _plateTypeOptions.map(prettyTitleCase).toList(),
                );
                if (choice != null) {
                  setState(() {
                    selectedPlateType = choice.toLowerCase();
                  });
                  _syncStep3DraftToParent();
                }
              },
              child: buildFancySelector(
                context,
                icon: Icons.confirmation_number_outlined,
                label: _trLegacyText(
                  context,
                  'Plate type',
                  ar: 'نوع اللوحة',
                  ku: 'جۆری پڵەیت',
                ),
                value: selectedPlateType == null
                    ? null
                    : _translatePlateTypeLegacy(context, selectedPlateType!),
              ),
            ),
            SizedBox(height: 16),

            // Plate City (Optional)
            GestureDetector(
              onTap: () async {
                _dismissKeyboard();
                final choice = await _pickFromList(
                  _trLegacyText(
                    context,
                    'Plate city',
                    ar: 'مدينة اللوحة',
                    ku: 'شاری پڵەیت',
                  ),
                  _plateCities,
                );
                if (choice != null) {
                  setState(() => selectedPlateCity = choice);
                  _syncStep3DraftToParent();
                }
              },
              child: buildFancySelector(
                context,
                icon: Icons.location_on_outlined,
                label: _trLegacyText(
                  context,
                  'Plate city',
                  ar: 'مدينة اللوحة',
                  ku: 'شاری پڵەیت',
                ),
                value: selectedPlateCity == null
                    ? null
                    : (_translateValueGlobal(context, selectedPlateCity) ??
                        selectedPlateCity),
              ),
            ),
            SizedBox(height: 16),

            // Contact Phone
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
                prefixStyle: TextStyle(
                  color: Color(0xFFFF6B00),
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: Icon(Icons.phone, color: Color(0xFFFF6B00)),
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
            SizedBox(height: 24),

            // Listing Description (Optional)
            TextFormField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText:
                    AppLocalizations.of(context)?.descriptionOptionalLabel ??
                    'Description (optional)',
                hintText:
                    _trLegacyText(
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
                  color: Color(0xFFFF6B00),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                alignLabelWithHint: true,
              ),
              style: _sellFlowManualFieldTextStyle(context),
              onChanged: (_) => _syncStep3DraftToParent(),
            ),
            SizedBox(height: 24),

            // Quick Sell Option
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.flash_on, color: Colors.orange, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _quickSellTextGlobal(context),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.orange,
                          ),
                        ),
                        Text(
                          _trLegacyText(
                            context,
                            'Make your listing stand out with a special banner',
                            ar: 'اجعل إعلانك مميزا بشارة خاصة',
                            ku: 'ڕیکلامەکەت بە بانەری تایبەت دیار بکە',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: isQuickSell,
                    onChanged: (value) {
                      setState(() {
                        isQuickSell = value;
                      });
                      _syncStep3DraftToParent();
                    },
                    activeThumbColor: Colors.orange,
                  ),
                ],
              ),
            ),
            SizedBox(height: 32),

            // Navigation Buttons
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () {
                        final parentState = context
                            .findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          parentState._goToPreviousStep();
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: Color(0xFFFF6B00)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.previousButton,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFFF6B00),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () {
                        final List<String> missing = [];
                        if (selectedCity == null ||
                            (selectedCity ?? '').isEmpty) {
                          missing.add(AppLocalizations.of(context)!.cityLabel);
                        }
                        if (contactPhone == null ||
                            (contactPhone ?? '').trim().isEmpty) {
                          missing.add('Phone');
                        }
                        if (missing.isNotEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${_pleaseFillRequiredGlobal(context)}: ${missing.join(', ')}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }
                        final parentState = context
                            .findAncestorStateOfType<_SellCarPageState>();
                        if (parentState != null) {
                          _dismissKeyboard();
                          parentState.carData['price'] = selectedPrice;
                          parentState.carData['city'] = selectedCity;
                          parentState.carData['plate_type'] = selectedPlateType;
                          parentState.carData['plate_city'] = selectedPlateCity;
                          parentState.carData['contact_phone'] = contactPhone;
                          parentState.carData['description'] =
                              _descriptionController.text.trim();
                          parentState.carData['is_quick_sell'] = isQuickSell;
                          parentState._goToNextStep();
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Color(0xFFFF6B00),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                      child: Text(
                        AppLocalizations.of(context)!.nextStep,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
    );
  }
}
