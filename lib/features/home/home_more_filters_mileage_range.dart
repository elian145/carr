part of 'home_flow.dart';

mixin _HomePageMoreFiltersMileageRange on _HomePageMoreFiltersYear {
  List<Widget> _moreFiltersMileageRangeWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;
    final mileageOptions = <int>[
      for (int m = 0; m <= 100000; m += 1000) m,
      for (int m = 105000; m <= 300000; m += 5000) m,
    ];

    String formatMileage(int m) {
      return localizeDigits(
        context,
        m.toString().replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (mm) => '${mm[1]},',
        ),
      );
    }

    return <Widget>[
      _moreFiltersRangeSectionHeader(
        title: loc.mileageRangeLabel,
        style: style,
        toggle: _moreFiltersRangeModeToggle(
          style: style,
          isDropdown: isMileageDropdown,
          onPressed: () => setStateDialog(() {
            if (isMileageDropdown) {
              _minMileageController.text = selectedMinMileage ?? '';
              _maxMileageController.text = selectedMaxMileage ?? '';
            }
            isMileageDropdown = !isMileageDropdown;
          }),
        ),
      ),
      const SizedBox(height: 12),
      if (isMileageDropdown)
        _moreFiltersMinMaxRow(
          minField: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: (selectedMinMileage != null &&
                    selectedMinMileage!.isNotEmpty)
                ? selectedMinMileage
                : '',
            decoration: _moreFiltersFilterFieldDecoration(style, loc.minMileage),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
              ),
              ...mileageOptions
                  .where((m) {
                    if (selectedMaxMileage == null ||
                        selectedMaxMileage!.isEmpty) {
                      return true;
                    }
                    final max = int.tryParse(selectedMaxMileage!);
                    return max == null ? true : m <= max;
                  })
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.toString(),
                      child: Text(formatMileage(m)),
                    ),
                  ),
            ],
            onChanged: (value) {
              setState(() {
                selectedMinMileage =
                    (value == null || value.isEmpty) ? null : value;
                final min = int.tryParse(selectedMinMileage ?? '');
                final max = int.tryParse(selectedMaxMileage ?? '');
                if (min != null && max != null && min > max) {
                  selectedMaxMileage = selectedMinMileage;
                }
              });
              setStateDialog(() {});
            },
          ),
          maxField: DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: (selectedMaxMileage != null &&
                    selectedMaxMileage!.isNotEmpty)
                ? selectedMaxMileage
                : '',
            decoration: _moreFiltersFilterFieldDecoration(style, loc.maxMileage),
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
              ),
              ...mileageOptions
                  .where((m) {
                    if (selectedMinMileage == null ||
                        selectedMinMileage!.isEmpty) {
                      return true;
                    }
                    final min = int.tryParse(selectedMinMileage!);
                    return min == null ? true : m >= min;
                  })
                  .map(
                    (m) => DropdownMenuItem(
                      value: m.toString(),
                      child: Text(formatMileage(m)),
                    ),
                  ),
            ],
            onChanged: (value) {
              setState(() {
                selectedMaxMileage =
                    (value == null || value.isEmpty) ? null : value;
                final min = int.tryParse(selectedMinMileage ?? '');
                final max = int.tryParse(selectedMaxMileage ?? '');
                if (min != null && max != null && max < min) {
                  selectedMinMileage = selectedMaxMileage;
                }
              });
              setStateDialog(() {});
            },
          ),
        )
      else
        _moreFiltersMinMaxRow(
          minField: TextFormField(
            controller: _minMileageController,
            decoration: _moreFiltersFilterFieldDecoration(style, loc.minMileage)
                .copyWith(
              hintText: loc.any,
              hintStyle: TextStyle(color: style.anyOrange),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                selectedMinMileage = value.isEmpty ? null : value;
                final min = int.tryParse(selectedMinMileage ?? '');
                final max = int.tryParse(selectedMaxMileage ?? '');
                if (min != null && max != null && min > max) {
                  selectedMaxMileage = selectedMinMileage;
                  _maxMileageController.text = selectedMaxMileage ?? '';
                }
              });
              setStateDialog(() {});
            },
          ),
          maxField: TextFormField(
            controller: _maxMileageController,
            decoration: _moreFiltersFilterFieldDecoration(style, loc.maxMileage)
                .copyWith(
              hintText: loc.any,
              hintStyle: TextStyle(color: style.anyOrange),
            ),
            keyboardType: TextInputType.number,
            onChanged: (value) {
              setState(() {
                selectedMaxMileage = value.isEmpty ? null : value;
                final min = int.tryParse(selectedMinMileage ?? '');
                final max = int.tryParse(selectedMaxMileage ?? '');
                if (min != null && max != null && max < min) {
                  selectedMinMileage = selectedMaxMileage;
                  _minMileageController.text = selectedMinMileage ?? '';
                }
              });
              setStateDialog(() {});
            },
          ),
        ),
    ];
  }
}
