part of 'sell_flow.dart';
class SellStep4Page extends StatefulWidget {
  const SellStep4Page({super.key});

  @override
  State<SellStep4Page> createState() => _SellStep4PageState();
}

class _SellStep4PageState extends State<SellStep4Page>
    with _SellStep4Fields, _SellStep4Logic, _SellStep4BuildIntro, _SellStep4BuildPhotos, _SellStep4BuildDamage, _SellStep4BuildVideos, _SellStep4Build {}
