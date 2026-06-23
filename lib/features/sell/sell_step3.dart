part of 'sell_flow.dart';
class SellStep3Page extends StatefulWidget {
  const SellStep3Page({super.key});

  @override
  State<SellStep3Page> createState() => _SellStep3PageState();
}

class _SellStep3PageState extends State<SellStep3Page>
    with _SellStep3Fields, _SellStep3Catalog, _SellStep3Pickers, _SellStep3BuildPrice, _SellStep3BuildDetails, _SellStep3Build {}
