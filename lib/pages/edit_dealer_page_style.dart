part of 'edit_dealer_page.dart';

mixin _EditDealerPageStyle on _EditDealerPageFields {
  String _tr(String en, {String? ar, String? ku}) {
    final code = Localizations.localeOf(context).languageCode;
    if (code == 'ar') return ar ?? en;
    if (code == 'ku' || code == 'ckb') return ku ?? en;
    return en;
  }

  String _dayLabel(String key) {
    switch (key) {
      case 'sun':
        return _tr('Sunday', ar: 'الأحد', ku: 'یەکشەممە');
      case 'mon':
        return _tr('Monday', ar: 'الاثنين', ku: 'دووشەممە');
      case 'tue':
        return _tr('Tuesday', ar: 'الثلاثاء', ku: 'سێشەممە');
      case 'wed':
        return _tr('Wednesday', ar: 'الأربعاء', ku: 'چوارشەممە');
      case 'thu':
        return _tr('Thursday', ar: 'الخميس', ku: 'پێنجشەممە');
      case 'fri':
        return _tr('Friday', ar: 'الجمعة', ku: 'هەینی');
      case 'sat':
        return _tr('Saturday', ar: 'السبت', ku: 'شەممە');
      default:
        return key;
    }
  }

  TextStyle _fieldTextStyle(bool isLightShell) {
    return TextStyle(
      color: isLightShell ? Colors.black87 : Colors.white,
      fontWeight: FontWeight.w600,
    );
  }

  InputDecoration _fieldDecoration(
    bool isLightShell, {
    required String label,
    String? hint,
    IconData? icon,
  }) {
    final fill = isLightShell
        ? Theme.of(context).colorScheme.surfaceContainerHighest
        : Colors.black.withValues(alpha: 0.18);
    final enabledBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(
        color: isLightShell ? Colors.grey.shade300 : Colors.white12,
        width: 1.2,
      ),
    );
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: _editDealerAccent,
        fontWeight: FontWeight.w800,
      ),
      floatingLabelStyle: const TextStyle(
        color: _editDealerAccent,
        fontWeight: FontWeight.w900,
      ),
      filled: true,
      fillColor: fill,
      prefixIcon: icon == null
          ? null
          : Icon(
              icon,
              color: isLightShell ? Colors.grey.shade700 : Colors.white70,
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: enabledBorder,
      border: enabledBorder,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _editDealerAccent, width: 2),
      ),
    );
  }

  ButtonStyle _outlineAccentStyle() {
    return OutlinedButton.styleFrom(
      foregroundColor: _editDealerAccent,
      side: const BorderSide(color: _editDealerAccent, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Widget _brandingMediaButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
    bool selected = false,
  }) {
    final enabled = onPressed != null;
    final borderColor = selected
        ? _editDealerAccent
        : _editDealerAccent.withValues(alpha: enabled ? 0.42 : 0.22);
    // Keep short two-word labels on one line (e.g. "Change logo").
    final displayLabel = label.contains(' ')
        ? label.replaceFirst(' ', '\u00A0')
        : label;

    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(8),
          splashColor: _editDealerAccent.withValues(alpha: 0.12),
          highlightColor: _editDealerAccent.withValues(alpha: 0.06),
          child: Ink(
            height: 44,
            decoration: BoxDecoration(
              color: selected
                  ? _editDealerAccent.withValues(alpha: 0.1)
                  : _editDealerAccent.withValues(alpha: 0.035),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.max,
                children: [
                  Icon(icon, size: 18, color: _editDealerAccent),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        displayLabel,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _editDealerAccent,
                          height: 1.1,
                          letterSpacing: 0.05,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandingCoverPreview(String coverUrl) {
    if (_cover != null) {
      return Image.file(
        File(_cover!.path),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            Container(color: Colors.black12),
      );
    }
    if (coverUrl.isNotEmpty) {
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (context, error, stackTrace) =>
            Container(color: Colors.black12),
      );
    }
    return Container(
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.55),
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  RoundedRectangleBorder _pageCardShape(Brightness brightness) {
    final isLightShell = brightness == Brightness.light;
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: BorderSide(
        color: isLightShell
            ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.35)
            : Colors.white12,
      ),
    );
  }

  Widget _sectionTitle({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: _editDealerAccent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: _editDealerAccent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing,
        ],
      ],
    );
  }
}
