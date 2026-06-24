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

  void _rename(int index) async {
    final controller = TextEditingController(
      text: _items[index]['name']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Rename'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(AppLocalizations.of(context)!.ok),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _items[index]['name'] = controller.text.trim().isEmpty
            ? _items[index]['name']
            : controller.text.trim();
      });
      await _save();
      unawaited(SavedSearchService.pushItemToServer(_items[index]));
    }
  }

  void _delete(int index) async {
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
