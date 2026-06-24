part of 'production_account_pages.dart';

mixin _ProfilePageStyle on _ProfilePageFields {
  BoxDecoration _shellDecoration(BuildContext context) =>
      AppThemes.shellBackgroundDecoration(Theme.of(context).brightness);

  bool _profileLightShell(BuildContext context) =>
      Theme.of(context).brightness == Brightness.light;

  Color _profileCardFill(BuildContext context) {
    if (_profileLightShell(context)) return Colors.white;
    return Color.alphaBlend(
      Colors.white.withValues(alpha: 0.085),
      AppThemes.darkHomeShellBackground,
    );
  }

  Color _profileBorderColor(BuildContext context) {
    if (_profileLightShell(context)) return const Color(0xFFE0E0E0);
    return Colors.white.withValues(alpha: 0.12);
  }

  Color _profilePrimaryInk(BuildContext context) {
    if (_profileLightShell(context)) return Colors.grey[800]!;
    return const Color(0xFFECECEC);
  }

  Color _profileSecondaryInk(BuildContext context) {
    if (_profileLightShell(context)) return Colors.grey[600]!;
    return Colors.white70;
  }

  BoxDecoration _profileCardDecoration(
    BuildContext context, {
    double radius = 16,
    double blur = 12,
    double shadowOpacity = 0.06,
  }) {
    final light = _profileLightShell(context);
    return BoxDecoration(
      color: _profileCardFill(context),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: _profileBorderColor(context), width: 1),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: light ? shadowOpacity : 0.45),
          blurRadius: light ? blur : 20,
          offset: const Offset(0, 6),
        ),
      ],
    );
  }
}
