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
        title: AppLocalizations.of(context)!.labelPlateType,
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
        title: AppLocalizations.of(context)!.labelPlateCity,
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
      Text(
        AppLocalizations.of(context)!.listingContactPhonesTitle,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        AppLocalizations.of(context)!.listingContactPhonesHint,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
      const SizedBox(height: 12),
      ...List<Widget>.generate(_phoneControllers.length, (index) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: index == _phoneControllers.length - 1 ? 0 : 12,
          ),
          child: _buildContactPhoneRow(context, index),
        );
      }),
      if (_phoneControllers.length < _SellStep3Fields.maxContactPhones) ...[
        const SizedBox(height: 8),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _phoneControllers.add(TextEditingController());
              });
            },
            icon: const Icon(Icons.add),
            label: Text(AppLocalizations.of(context)!.addPhoneNumber),
          ),
        ),
      ],
      const SizedBox(height: 24),
      TextFormField(
        controller: _descriptionController,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
          labelText:
              AppLocalizations.of(context)?.descriptionOptionalLabel ??
              'Description (optional)',
          hintText: AppLocalizations.of(context)!.addDetailsAboutTheCarConditionFeaturesOrNotes,
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

  Widget _buildContactPhoneRow(BuildContext context, int index) {
    final loc = AppLocalizations.of(context)!;
    final auth = context.read<AuthService>();
    final parentState = context.findAncestorStateOfType<_SellCarPageState>();
    final digits = _phoneControllers[index].text.trim();
    final fullPhone = digits.isEmpty ? '' : '+964$digits';
    final verified = fullPhone.isNotEmpty &&
        isListingContactPhoneVerified(
          contactPhone: fullPhone,
          auth: auth,
          verifiedPhonesCache: parentState?._verifiedListingPhones,
        );
    final label = index == 0
        ? loc.whatsappPhoneNumber2
        : loc.listingContactPhoneN(index + 1);
    final canRemove = _phoneControllers.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _phoneControllers[index],
          // Keep +964 and digits in LTR order even on Arabic/Kurdish screens.
          textDirection: ui.TextDirection.ltr,
          textAlign: TextAlign.left,
          decoration: InputDecoration(
            labelText: label,
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
            suffixIcon: canRemove
                ? IconButton(
                    tooltip: loc.removeAction,
                    onPressed: () {
                      setState(() {
                        _phoneControllers.removeAt(index).dispose();
                        contactPhones = _collectContactPhonesFromControllers();
                        contactPhone =
                            contactPhones.isEmpty ? null : contactPhones.first;
                      });
                      _syncStep3DraftToParent();
                    },
                    icon: const Icon(Icons.close),
                  )
                : null,
          ),
          style: _sellFlowManualFieldTextStyle(context),
          keyboardType: TextInputType.phone,
          inputFormatters: [
            services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
            services.LengthLimitingTextInputFormatter(10),
          ],
          onChanged: (_) {
            setState(() {
              contactPhones = _collectContactPhonesFromControllers();
              contactPhone =
                  contactPhones.isEmpty ? null : contactPhones.first;
            });
            _formKey.currentState?.validate();
            _syncStep3DraftToParent();
          },
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) {
              // Empty row is fine when another number is present (e.g. user
              // removed/cleared the default account phone after verifying another).
              if (_hasContactPhoneDigitsBesides(index)) return null;
              return index == 0 ? loc.pleaseEnterPhoneNumber : null;
            }
            if (trimmed.length < 10) {
              return loc.pleaseEnterAValidPhoneNumber;
            }
            if (_isDuplicateContactPhoneDigits(trimmed, index)) {
              return loc.duplicateContactPhoneError;
            }
            return null;
          },
        ),
        Row(
          children: [
            TextButton.icon(
              onPressed: verified ||
                      digits.length < 10 ||
                      _isDuplicateContactPhoneDigits(digits, index)
                  ? null
                  : () async {
                      final ok = await ensureListingContactPhoneVerified(
                        context,
                        contactPhone: '+964$digits',
                        verifiedPhonesCache:
                            parentState?._verifiedListingPhones,
                      );
                      if (!mounted) return;
                      if (ok) setState(() {});
                    },
              style: TextButton.styleFrom(
                foregroundColor: kFilterAccentColor,
                disabledForegroundColor: Colors.green,
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                verified ? Icons.verified_rounded : Icons.sms_outlined,
                size: 18,
              ),
              label: Text(
                verified ? loc.phoneVerifiedBadge : loc.verifyPhoneAction,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
