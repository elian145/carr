part of 'edit_dealer_page.dart';

mixin _EditDealerPageBuildBody on _EditDealerPageBuildBodyLower {
  Widget _buildEditDealerBody(BuildContext context) {
      return Stack(
        children: [
          Container(
            decoration: AppThemes.shellBackgroundDecoration(
              Theme.of(context).brightness,
            ),
          ),
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 110),
              children: [
                ..._editDealerUpperFormCards(context),
                ..._editDealerLowerFormCards(context),
              ],
            ),
          ),
        ],
      );
  }
}
