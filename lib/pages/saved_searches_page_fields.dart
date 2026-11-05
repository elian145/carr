part of 'saved_searches_page.dart';

abstract class _SavedSearchesPageFields extends State<SavedSearchesPage> {
  List<Map<String, dynamic>> _items = [];
  /// Account whose list _items belongs to (F-34). Writes go to this owner's
  /// storage only, even if the signed-in account changes while the page lives.
  String? _ownerId;
  /// Authentication session `_items` was loaded in. Anything this page
  /// pushes to the server is bound to it (never to a later account's).
  AuthSessionSnapshot? _session;
  /// Identifies the latest load; results of an older load are dropped.
  int _loadSeq = 0;
  bool _loading = true;
  String? _error;
}
