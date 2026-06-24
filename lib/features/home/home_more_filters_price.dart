part of 'home_flow.dart';

mixin _HomePageMoreFiltersPrice on _HomePageMoreFiltersVehicle {
  List<Widget> _moreFiltersPriceWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;
    final priceOptions = <int>[
      for (int p = 500; p <= 300000; p += 500) p,
      for (int p = 310000; p <= 2000000; p += 10000) p,
    ];

    return <Widget>[
      _moreFiltersRangeSectionHeader(
        title: loc.priceRange,
        style: style,
        toggle: _moreFiltersRangeModeToggle(
          style: style,
          isDropdown: isPriceDropdown,
          onPressed: () => setStateDialog(() {
            if (isPriceDropdown) {
              _minPriceController.text = selectedMinPrice ?? '';
              _maxPriceController.text = selectedMaxPrice ?? '';
            }
            isPriceDropdown = !isPriceDropdown;
          }),
        ),
      ),
      const SizedBox(height: 12),
      if (isPriceDropdown)
        _moreFiltersMinMaxRow(
          minField: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedMinPrice ?? '',
            decoration: _moreFiltersFilterFieldDecoration(style, loc.minPrice),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
              ),
              ...priceOptions
                  .where((p) {
                    if (selectedMaxPrice == null || selectedMaxPrice!.isEmpty) {
                      return true;
                    }
                    final max = int.tryParse(selectedMaxPrice!);
                    return max == null ? true : p <= max;
                  })
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.toString(),
                      child: Text(_formatCurrencyGlobal(context, p)),
                    ),
                  ),
            ],
            onChanged: (value) {
              setState(() {
                selectedMinPrice = value?.isEmpty == true ? null : value;
                final min = int.tryParse(selectedMinPrice ?? '');
                final max = int.tryParse(selectedMaxPrice ?? '');
                if (min != null && max != null && min > max) {
                  selectedMaxPrice = selectedMinPrice;
                }
              });
              setStateDialog(() {});
            },
          ),
          maxField: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: selectedMaxPrice ?? '',
            decoration: _moreFiltersFilterFieldDecoration(style, loc.maxPrice),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
              ),
              ...priceOptions
                  .where((p) {
                    if (selectedMinPrice == null || selectedMinPrice!.isEmpty) {
                      return true;
                    }
                    final min = int.tryParse(selectedMinPrice!);
                    return min == null ? true : p >= min;
                  })
                  .map(
                    (p) => DropdownMenuItem(
                      value: p.toString(),
                      child: Text(_formatCurrencyGlobal(context, p)),
                    ),
                  ),
            ],
            onChanged: (value) {
              setState(() {
                selectedMaxPrice = value?.isEmpty == true ? null : value;
                final min = int.tryParse(selectedMinPrice ?? '');
                final max = int.tryParse(selectedMaxPrice ?? '');
                if (min != null && max != null && max < min) {
                  selectedMinPrice = selectedMaxPrice;
                }
              });
              setStateDialog(() {});
            },
          ),
        )
      else
        _moreFiltersMinMaxRow(
          minField: TextFormField(
            controller: _minPriceController,
            decoration: _moreFiltersFilterFieldDecoration(style, loc.minPrice)
                .copyWith(
              hintText: loc.any,
              hintStyle: TextStyle(color: style.anyOrange),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                selectedMinPrice = value.isEmpty ? null : value;
                final min = int.tryParse(selectedMinPrice ?? '');
                final max = int.tryParse(selectedMaxPrice ?? '');
                if (min != null && max != null && min > max) {
                  selectedMaxPrice = selectedMinPrice;
                  _maxPriceController.text = selectedMaxPrice ?? '';
                }
              });
              setStateDialog(() {});
            },
          ),
          maxField: TextFormField(
            controller: _maxPriceController,
            decoration: _moreFiltersFilterFieldDecoration(style, loc.maxPrice)
                .copyWith(
              hintText: loc.any,
              hintStyle: TextStyle(color: style.anyOrange),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                selectedMaxPrice = value.isEmpty ? null : value;
                final min = int.tryParse(selectedMinPrice ?? '');
                final max = int.tryParse(selectedMaxPrice ?? '');
                if (min != null && max != null && max < min) {
                  selectedMinPrice = selectedMaxPrice;
                  _minPriceController.text = selectedMinPrice ?? '';
                }
              });
              setStateDialog(() {});
            },
          ),
        ),
      SizedBox(height: style.fieldGap),
    ];
  }
}
