import 'package:flutter/widgets.dart';

import '../../shared/i18n/legacy_inline_text.dart';

/// Internal home-feed error keys (not shown directly to users).
abstract final class HomeFeedErrors {
  static const String network = 'feed:network';

  static String server(int statusCode) => 'feed:server:$statusCode';
}

/// Maps [HomeFeedErrors] keys to localized user-facing copy.
String formatHomeFeedErrorMessage(BuildContext context, String? key) {
  if (key == null || key.isEmpty) {
    return couldNotLoadListingsText(context);
  }
  if (key == HomeFeedErrors.network) {
    return homeFeedNetworkErrorText(context);
  }
  if (key.startsWith('feed:server:')) {
    final code = key.substring('feed:server:'.length);
    return homeFeedServerErrorText(context, code);
  }
  return couldNotLoadListingsText(context);
}
