import 'package:flutter/material.dart';

import '../../services/deep_link_service.dart';

/// Wraps [MaterialApp] and initializes [DeepLinkService] after the first frame.
class AppWithDeepLinks extends StatefulWidget {
  const AppWithDeepLinks({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppWithDeepLinks> createState() => _AppWithDeepLinksState();
}

class _AppWithDeepLinksState extends State<AppWithDeepLinks> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinkService.instance.init(widget.navigatorKey);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
