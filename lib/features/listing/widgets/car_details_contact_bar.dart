import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../shared/i18n/legacy_inline_text.dart';

/// WhatsApp + call actions on the listing detail page.
class CarDetailsContactBar extends StatelessWidget {
  const CarDetailsContactBar({
    super.key,
    required this.onWhatsApp,
    required this.onCall,
  });

  final VoidCallback onWhatsApp;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 46,
            child: Semantics(
              button: true,
              label: AppLocalizations.of(context)!.chatOnWhatsApp,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF25D366),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: Colors.black26,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 46),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.chat, size: 19),
                label: Text(
                  AppLocalizations.of(context)!.chatOnWhatsApp,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: onWhatsApp,
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: SizedBox(
            height: 46,
            child: Semantics(
              button: true,
              label: trLegacyText(
                context,
                'Call Seller',
                ar: 'اتصل بالبائع',
                ku: 'پەیوەندی بە فرۆشیار',
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF007AFF),
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shadowColor: Colors.black26,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  minimumSize: const Size(0, 46),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(17),
                  ),
                ),
                icon: const Icon(Icons.phone, size: 19),
                label: Text(
                  trLegacyText(
                    context,
                    'Call Seller',
                    ar: 'اتصل بالبائع',
                    ku: 'پەیوەندی بە فرۆشیار',
                  ),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onPressed: onCall,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
