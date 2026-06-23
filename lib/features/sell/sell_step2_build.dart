part of 'sell_flow.dart';

mixin _SellStep2Build on _SellStep2BuildMechanical {
  List<Widget> _sellStep2BuildNavSection() {
    return [

    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ..._sellStep2BuildCoreSection(),
            ..._sellStep2BuildAppearanceSection(),
            ..._sellStep2BuildMechanicalSection(),
            ..._sellStep2BuildNavSection(),
          ],
        ),
      ),
    );
  }
}
