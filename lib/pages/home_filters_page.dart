import 'package:flutter/material.dart';

import '../legacy/main_legacy.dart' show LegacyHomeFiltersPage;

/// Production home filter screen (`/home_filters`).
///
/// Filter UI still lives in legacy home for now; this page is the modern route
/// entry so we can replace the panel incrementally without changing callers.
class HomeFiltersPage extends StatelessWidget {
  const HomeFiltersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LegacyHomeFiltersPage();
  }
}
