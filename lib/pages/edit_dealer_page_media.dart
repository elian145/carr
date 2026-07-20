part of 'edit_dealer_page.dart';

mixin _EditDealerPageMedia on _EditDealerPageLocation {
  Future<void> _pickLogo() async {
    final picked = await pickCircularImage(
      context,
      title: _tr(
        'Position your logo',
        ar: 'حدّد موضع شعارك',
        ku: 'شوێنی لۆگۆکەت دیاری بکە',
      ),
      doneLabel: _tr('Done', ar: 'تم', ku: 'تەواو'),
      cancelLabel: _tr('Cancel', ar: 'إلغاء', ku: 'هەڵوەشاندنەوە'),
    );
    if (picked == null || !mounted) return;
    setState(() => _logo = picked);
  }

  Future<void> _pickCover() async {
    final picked = await pickCoverImage(
      context,
      title: _tr(
        'Position your cover photo',
        ar: 'حدّد موضع صورة الغلاف',
        ku: 'شوێنی وێنەی کاڤەر دیاری بکە',
      ),
      doneLabel: _tr('Done', ar: 'تم', ku: 'تەواو'),
      cancelLabel: _tr('Cancel', ar: 'إلغاء', ku: 'هەڵوەشاندنەوە'),
    );
    if (picked == null || !mounted) return;
    setState(() => _cover = picked);
  }
}
