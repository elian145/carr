part of 'saved_searches_page.dart';

abstract class _SavedSearchesPageFields extends State<SavedSearchesPage> {
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;
  String? _error;
}
