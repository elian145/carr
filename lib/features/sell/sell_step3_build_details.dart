part of 'sell_flow.dart';

mixin _SellStep3BuildDetails on _SellStep3BuildPrice {
  List<Widget> _sellStep3BuildDetailsSection() {
    return [
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
    ];
  }
}
