part of 'home_flow.dart';

mixin _HomePageMoreFiltersVehicle on _HomePageFilterLogic {
  InputDecoration _moreFiltersColorMatchedFieldDecoration(
    MoreFiltersDialogStyle style,
    String label, {
    bool compactLabel = false,
  }) =>
      filterDropdownFieldDecoration(
        style,
        label,
        compactLabel: compactLabel,
      );

  Widget _moreFiltersRangeModeToggle({
    required BuildContext context,
    required MoreFiltersDialogStyle style,
    required bool isDropdown,
    required VoidCallback onPressed,
  }) {
    final loc = AppLocalizations.of(context)!;
    return IconButton(
      tooltip: isDropdown ? loc.typeManually : loc.selectFromList,
      onPressed: onPressed,
      icon: Icon(
        isDropdown ? Icons.edit : Icons.list,
        color: AppColors.brandOrange,
        size: 24,
      ),
      style: IconButton.styleFrom(
        backgroundColor: style.fieldFill,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        visualDensity: VisualDensity.standard,
        padding: const EdgeInsets.all(8),
        minimumSize: const Size(40, 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  Widget _moreFiltersRangeSectionHeader({
    required String title,
    required MoreFiltersDialogStyle style,
    Widget? toggle,
  }) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: style.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ),
        if (toggle != null) toggle,
      ],
    );
  }

  Widget _moreFiltersMinMaxRow({
    required Widget minField,
    required Widget maxField,
    double gap = 8,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: minField),
        SizedBox(width: gap),
        Expanded(child: maxField),
      ],
    );
  }

  Widget _moreFiltersDropdownField({
    required BuildContext context,
    required MoreFiltersDialogStyle style,
    required String label,
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
    bool narrowMenu = false,
  }) {
    return FilterDropdownField(
      style: style,
      label: label,
      value: value,
      items: items,
      onChanged: onChanged,
      narrowMenu: narrowMenu,
    );
  }

}
