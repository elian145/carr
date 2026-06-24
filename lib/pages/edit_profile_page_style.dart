part of 'edit_profile_page.dart';

mixin _EditProfilePageStyle on _EditProfilePageFields {
  bool _shellLight(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  Color _cardFill(BuildContext context) {
    if (_shellLight(context)) return Colors.white;
    return Color.alphaBlend(
      Colors.white.withValues(alpha: 0.085),
      AppThemes.darkHomeShellBackground,
    );
  }

  Color _cardBorderColor(BuildContext context) {
    if (_shellLight(context)) return const Color(0xFFE0E0E0);
    return Colors.white.withValues(alpha: 0.12);
  }

  Color _primaryInk(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[800]!;
    return const Color(0xFFECECEC);
  }

  Color _secondaryInk(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[600]!;
    return Colors.white70;
  }

  Color _fieldFill(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[50]!;
    return Colors.white.withValues(alpha: 0.06);
  }

  Color _fieldBorder(BuildContext context) {
    if (_shellLight(context)) return Colors.grey[300]!;
    return Colors.white.withValues(alpha: 0.14);
  }

  BoxDecoration _cardDecoration(BuildContext context, {double radius = 16}) {
    final light = _shellLight(context);
    return BoxDecoration(
      color: _cardFill(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _cardBorderColor(context), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: light ? 0.05 : 0.45),
          blurRadius: light ? 10 : 18,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
