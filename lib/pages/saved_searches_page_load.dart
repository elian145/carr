part of 'saved_searches_page.dart';

mixin _SavedSearchesPageLoad on _SavedSearchesPageFields {
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final merged = await SavedSearchService.loadMerged();
      if (!mounted) return;
      setState(() {
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = userErrorText(
          context,
          e,
          fallback: AppLocalizations.of(context)!.error,
        );
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    await SavedSearchService.persistLocal(_items);
  }

  Future<void> _delete(int index) async {
    final loc = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          AppLocalizations.of(context)!.deleteSavedSearch,
        ),
        content: Text(
          AppLocalizations.of(context)!.thisWillPermanentlyRemoveThisSavedSearchThisCannotBeUndone,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc?.cancelAction ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              loc?.deleteAction ?? 'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (index < 0 || index >= _items.length) return;

    final id = (_items[index]['id'] ?? '').toString();
    setState(() {
      _items.removeAt(index);
    });
    await _save();
    unawaited(SavedSearchService.deleteOnServer(id));
  }

  void _toggleNotify(int index, bool value) async {
    setState(() {
      _items[index]['notify'] = value;
    });
    await _save();
    unawaited(SavedSearchService.pushItemToServer(_items[index]));
  }
}
