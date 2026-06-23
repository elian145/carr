part of 'home_flow.dart';

mixin _HomePageMoreFiltersMid on _HomePageMoreFiltersBodyColor {
  List<Widget> _moreFiltersMidWidgets(
    BuildContext context,
    void Function(void Function()) setStateDialog,
    MoreFiltersDialogStyle style,
  ) => [
        ..._moreFiltersMileageWidgets(context, setStateDialog, style),
        ..._moreFiltersBodyColorWidgets(context, setStateDialog, style),
      ];
}
