part of 'saved_searches_page.dart';

mixin _SavedSearchesPageLoad on _SavedSearchesPageFields {
  @override
  void initState() {
    super.initState();
    AccountScope.addSessionChangedListener(_onSessionChanged);
    _load();
  }

  @override
  void dispose() {
    AccountScope.removeSessionChangedListener(_onSessionChanged);
    super.dispose();
  }

  /// The signed-in account changed (login, logout, switch): the list on
  /// screen belongs to the previous account, so drop it NOW (synchronously)
  /// and reload for the account that is signed in now. Any load still in
  /// flight for the old session is invalidated and its result discarded.
  void _onSessionChanged() {
    if (!mounted) return;
    _loadSeq++;
    setState(() {
      _items = [];
      _ownerId = null;
      _session = null;
      _error = null;
      _loading = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    setState(() {
      _loading = true;
      _error = null;
    });
    // The session (and account) this load belongs to is fixed BEFORE anything
    // is awaited; the result is only shown if it is still the signed-in one.
    final AuthSessionSnapshot session;
    try {
      session = await ApiService.beginSession();
    } on ApiSessionChangedException {
      // Another account signed in meanwhile; the session-changed listener
      // already scheduled the reload for it.
      return;
    }
    bool stale() =>
        !mounted ||
        seq != _loadSeq ||
        session.epoch != ApiService.sessionEpoch;
    if (stale()) return;
    try {
      final merged = await SavedSearchService.loadMerged(session: session);
      // Re-checked immediately before display: never show another session's
      // list, and never attribute a list to an account that did not load it.
      if (stale()) return;
      setState(() {
        _session = session;
        _ownerId = session.accountId;
        _items = merged;
        _loading = false;
      });
    } catch (e) {
      if (stale()) return;
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

  /// True while the session this list was loaded in is still the signed-in
  /// one (same account AND same authentication session).
  bool get _ownerStillSignedIn {
    final s = _session;
    return s != null &&
        s.epoch == ApiService.sessionEpoch &&
        _ownerId == SavedSearchService.currentOwnerId;
  }
  Future<void> _save() async {
    final owner = _ownerId;
    if (owner == null) return;
    await SavedSearchService.persistLocal(_items, ownerId: owner);
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
    if (_ownerStillSignedIn) {
      unawaited(SavedSearchService.deleteOnServer(id, session: _session));
    }
  }

  void _toggleNotify(int index, bool value) async {
    setState(() {
      _items[index]['notify'] = value;
    });
    await _save();
    // Never push this list's items into a different account (F-34).
    if (_ownerStillSignedIn) {
      unawaited(
        SavedSearchService.pushItemToServer(_items[index], session: _session),
      );
    }
  }
}
