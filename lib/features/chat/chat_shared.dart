part of 'chat_pages.dart';

const Color _kComposerOutlineOrange = Color(0xFFFF7A00);

/// Brand orange (matches home [buildGlobalCarCard]); explicit color avoids
/// [Theme.primaryColor] matching surfaces inside chat bubbles in dark mode.
const Color _kChatListingCardAccentOrange = Color(0xFFFF6B00);

/// Peer bubble / preview fill: same look as dark mode (frosted on dark shell; solid blend on light shell).
Color _homeListingCardBackgroundFill(BuildContext context) {
  if (Theme.of(context).brightness == Brightness.dark) {
    return Colors.white.withValues(alpha: 0.10);
  }
  return AppThemes.listingCardFillGridOnLightShell();
}

String _digitsLocalized(BuildContext context, String input) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar' || code == 'ku' || code == 'ckb') {
    const western = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const eastern = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    var out = input;
    for (int i = 0; i < western.length; i++) {
      out = out.replaceAll(western[i], eastern[i]);
    }
    return out;
  }
  return input;
}

Widget buildChatListingAvatar(
  BuildContext context, {
  String? imageUrl,
  double radius = 24,
}) {
  final cs = Theme.of(context).colorScheme;
  final resolved = (imageUrl ?? '').trim();
  final size = radius * 2;
  final fallback = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withAlpha(30),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.directions_car,
      color: cs.primary,
      size: radius * 0.85,
    ),
  );
  if (resolved.isEmpty) return fallback;
  return SizedBox(
    width: size,
    height: size,
    child: ClipOval(
      child: Image.network(
        resolved,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            width: size,
            height: size,
            color: cs.primary.withAlpha(30),
            alignment: Alignment.center,
            child: SizedBox(
              width: radius,
              height: radius,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: cs.primary,
              ),
            ),
          );
        },
      ),
    ),
  );
}

String _relativeTime(BuildContext context, DateTime dateTime) {
  final now = DateTime.now();
  final diff = now.difference(dateTime.toLocal());
  final loc = AppLocalizations.of(context)!;
  String formatNum(int n) => _digitsLocalized(context, n.toString());
  if (diff.isNegative) {
    return loc.justNow;
  }
  if (diff.inDays > 0) {
    return loc.timeDaysAgo(formatNum(diff.inDays));
  } else if (diff.inHours > 0) {
    return loc.timeHoursAgo(formatNum(diff.inHours));
  } else if (diff.inMinutes > 0) {
    return loc.timeMinutesAgo(formatNum(diff.inMinutes));
  }
  return loc.justNow;
}

/// Best-effort timestamp string from API (snake_case / camelCase / conversation fallbacks).
String _rawChatListTimestamp(
  Map<String, dynamic> last,
  Map<String, dynamic> conversation,
) {
  String pick(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty && s != 'null') return s;
    }
    return '';
  }

  var s = pick(last, [
    'created_at',
    'createdAt',
    'updated_at',
    'updatedAt',
    'timestamp',
    'time',
    'sent_at',
    'sentAt',
  ]);
  if (s.isNotEmpty) return s;
  s = pick(conversation, [
    'updated_at',
    'updatedAt',
    'last_activity_at',
    'lastActivityAt',
  ]);
  return s;
}

String _noMessagesText(BuildContext context) {
  return AppLocalizations.of(context)!.noMessagesYet;
}

String _chatText(BuildContext context, String en, {String? ar, String? ku}) {
  final code = Localizations.localeOf(context).languageCode;
  if (code == 'ar') return ar ?? en;
  if (code == 'ku' || code == 'ckb') return ku ?? en;
  return en;
}

String _chatEditedLabel(BuildContext context) =>
    _chatText(context, 'Edited', ar: 'معدّل', ku: 'دەستکاری کراو');

String _chatMessageDeletedText(BuildContext context) => _chatText(
      context,
      'This message was deleted',
      ar: 'تم حذف هذه الرسالة',
      ku: 'ئەم پەیامە سڕایەوە',
    );

String _chatDisplayContent(BuildContext context, ChatMessage message) {
  if (message.isDeleted) return _chatMessageDeletedText(context);
  return message.content;
}

/// Listing title in the active app language (brand/model translated; trim kept in English).
String localizedListingTitle(BuildContext context, Map<String, dynamic> car) {
  final brand = (car['brand'] ?? '').toString().trim();
  final model = (car['model'] ?? '').toString().trim();
  if (brand.isNotEmpty && model.isNotEmpty) {
    final base = CarNameTranslations.getLocalizedCarTitleNoYear(context, car);
    final trim = (car['trim'] ?? '').toString().trim();
    final year = (car['year'] ?? '').toString().trim();
    final parts = <String>[
      if (base.isNotEmpty) base,
      if (trim.isNotEmpty && trim.toLowerCase() != 'base') prettyTitleCase(trim),
      if (year.isNotEmpty) year,
    ];
    final built = parts.join(' ').trim();
    if (built.isNotEmpty) {
      // Avoid Latin title-casing on Arabic/Kurdish text.
      return built;
    }
  }

  final localized =
      CarNameTranslations.getLocalizedCarTitle(context, car).trim();
  if (localized.isNotEmpty) {
    return RegExp(r'[A-Za-z]').hasMatch(localized)
        ? prettyTitleCase(localized)
        : localized;
  }
  final fallback = (car['title'] ?? '').toString().trim();
  if (fallback.isNotEmpty) return prettyTitleCase(fallback);
  return '';
}

/// Build car map for [localizedListingTitle] from a chat list row or route args.
Map<String, dynamic> listingMetaFromChatRow(Map<String, dynamic> source) {
  final brand =
      (source['car_brand'] ?? source['brand'] ?? '').toString().trim();
  final model =
      (source['car_model'] ?? source['model'] ?? '').toString().trim();
  final hasIdentity = brand.isNotEmpty && model.isNotEmpty;

  return {
    if (brand.isNotEmpty) 'brand': brand,
    if (model.isNotEmpty) 'model': model,
    if ((source['car_trim'] ?? source['trim'] ?? '').toString().trim().isNotEmpty)
      'trim': (source['car_trim'] ?? source['trim']).toString(),
    if ((source['car_year'] ?? source['year'] ?? '').toString().trim().isNotEmpty)
      'year': (source['car_year'] ?? source['year']).toString(),
    if (!hasIdentity &&
        (source['car_title'] ?? source['title'] ?? '').toString().trim().isNotEmpty)
      'title': (source['car_title'] ?? source['title']).toString(),
  };
}

String _chatLastMessagePreview(
  BuildContext context,
  Map<String, dynamic> last,
) {
  final content = (last['content'] ?? '').toString().trim();
  final type = (last['message_type'] ?? '').toString().toLowerCase();

  if (type == 'audio' ||
      content.toLowerCase() == '[voice message]') {
    return _chatText(
      context,
      'Voice message',
      ar: 'رسالة صوتية',
      ku: 'پەیامی دەنگی',
    );
  }
  if (type == 'image' || content.toLowerCase() == '[image]') {
    return _chatText(context, 'Photo', ar: 'صورة', ku: 'وێنە');
  }
  if (type == 'video' || content.toLowerCase() == '[video]') {
    return _chatText(context, 'Video', ar: 'فيديو', ku: 'ڤیدیۆ');
  }
  if (type == 'media_group' ||
      RegExp(r'^\[\d+\s+attachments?\]$', caseSensitive: false)
          .hasMatch(content)) {
    return _chatText(context, 'Media', ar: 'وسائط', ku: 'میدیا');
  }
  if (content.isEmpty) return '...';
  return content;
}

String _formatVoiceDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

const double _kOutgoingMetaMinGap = 14;
const double _kBubbleHorizontalPadding = 32;

bool _isAudioMessage(ChatMessage message) {
  if (message.messageType.toLowerCase() == 'audio') return true;
  if (message.attachments.length == 1 &&
      message.attachments.first.type.toLowerCase() == 'audio') {
    return true;
  }
  return false;
}

