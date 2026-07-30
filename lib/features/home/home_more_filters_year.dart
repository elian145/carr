part of 'home_flow.dart';

mixin _HomePageMoreFiltersYear on _HomePageMoreFiltersPrice {
  List<Widget> _moreFiltersYearWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) {
    final loc = AppLocalizations.of(context)!;
    final yearOptions = List<String>.generate(
      127,
      (i) => (1900 + i).toString(),
    ).reversed.toList();

    return <Widget>[
      _moreFiltersRangeSectionHeader(
        title: loc.yearRange,
        style: style,
        toggle: _moreFiltersRangeModeToggle(
          context: context,
          style: style,
          isDropdown: isYearDropdown,
          onPressed: () => setStateDialog(() {
            if (isYearDropdown) {
              _minYearController.text = selectedMinYear ?? '';
              _maxYearController.text = selectedMaxYear ?? '';
            }
            isYearDropdown = !isYearDropdown;
          }),
        ),
      ),
      const SizedBox(height: 12),
      if (isYearDropdown)
        _moreFiltersMinMaxRow(
          minField: _moreFiltersDropdownField(
            context: context,
            style: style,
            label: loc.minYear,
            value: selectedMinYear ?? '',
            narrowMenu: true,
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
              ),
              ...yearOptions
                  .where((y) {
                    if (selectedMaxYear == null || selectedMaxYear!.isEmpty) {
                      return true;
                    }
                    final max = int.tryParse(selectedMaxYear!);
                    final val = int.tryParse(y);
                    return max == null || val == null ? true : val <= max;
                  })
                  .map(
                    (y) => DropdownMenuItem(
                      value: y,
                      child: Text(
                        localizeDigits(context, y),
                        style: TextStyle(color: style.onSurface),
                      ),
                    ),
                  ),
            ],
            onChanged: (value) {
              setState(() {
                selectedMinYear =
                    (value == null || value.isEmpty) ? null : value;
                final min = int.tryParse(selectedMinYear ?? '');
                final max = int.tryParse(selectedMaxYear ?? '');
                if (min != null && max != null && min > max) {
                  selectedMaxYear = selectedMinYear;
                }
                _afterHomeYearBoundsChanged();
              });
              setStateDialog(() {});
            },
          ),
          maxField: _moreFiltersDropdownField(
            context: context,
            style: style,
            label: loc.maxYear,
            value: selectedMaxYear ?? '',
            narrowMenu: true,
            items: [
              DropdownMenuItem(
                value: '',
                child: Text(loc.any, style: TextStyle(color: style.anyOrange)),
              ),
              ...yearOptions
                  .where((y) {
                    if (selectedMinYear == null || selectedMinYear!.isEmpty) {
                      return true;
                    }
                    final min = int.tryParse(selectedMinYear!);
                    final val = int.tryParse(y);
                    return min == null || val == null ? true : val >= min;
                  })
                  .map(
                    (y) => DropdownMenuItem(
                      value: y,
                      child: Text(
                        localizeDigits(context, y),
                        style: TextStyle(color: style.onSurface),
                      ),
                    ),
                  ),
            ],
            onChanged: (value) {
              setState(() {
                selectedMaxYear =
                    (value == null || value.isEmpty) ? null : value;
                final min = int.tryParse(selectedMinYear ?? '');
                final max = int.tryParse(selectedMaxYear ?? '');
                if (min != null && max != null && max < min) {
                  selectedMinYear = selectedMaxYear;
                }
                _afterHomeYearBoundsChanged();
              });
              setStateDialog(() {});
            },
          ),
        )
      else
        _moreFiltersMinMaxRow(
          minField: TextFormField(
            controller: _minYearController,
            decoration: _moreFiltersColorMatchedFieldDecoration(
              style,
              loc.minYear,
            ).copyWith(
              hintText: loc.any,
              hintStyle: TextStyle(color: style.anyOrange),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
            ],
            onChanged: (value) {
              setState(() {
                selectedMinYear = value.isEmpty ? null : value;
                final min = int.tryParse(selectedMinYear ?? '');
                final max = int.tryParse(selectedMaxYear ?? '');
                if (min != null && max != null && min > max) {
                  selectedMaxYear = selectedMinYear;
                  _maxYearController.text = selectedMaxYear ?? '';
                }
                _afterHomeYearBoundsChanged();
              });
              setStateDialog(() {});
            },
          ),
          maxField: TextFormField(
            controller: _maxYearController,
            decoration: _moreFiltersColorMatchedFieldDecoration(
              style,
              loc.maxYear,
            ).copyWith(
              hintText: loc.any,
              hintStyle: TextStyle(color: style.anyOrange),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              services.FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
            ],
            onChanged: (value) {
              setState(() {
                selectedMaxYear = value.isEmpty ? null : value;
                final min = int.tryParse(selectedMinYear ?? '');
                final max = int.tryParse(selectedMaxYear ?? '');
                if (min != null && max != null && max < min) {
                  selectedMinYear = selectedMaxYear;
                  _minYearController.text = selectedMinYear ?? '';
                }
                _afterHomeYearBoundsChanged();
              });
              setStateDialog(() {});
            },
          ),
        ),
      SizedBox(height: style.fieldGap),
    ];
  }
}
