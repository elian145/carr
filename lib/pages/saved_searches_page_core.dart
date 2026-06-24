part of 'saved_searches_page.dart';

mixin _SavedSearchesPageCore on _SavedSearchesPageActions {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.savedSearchesTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(_error!),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _load,
                    child: Text(AppLocalizations.of(context)!.retryAction),
                  ),
                ],
              ),
            )
          : _items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search_off, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    AppLocalizations.of(context)!.noSavedSearchesYet,
                    style: TextStyle(fontSize: 18, color: Colors.grey),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppLocalizations.of(context)!.savedSearchesHint,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (context, index) => Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _items[index];
                final filters = item['filters'] as Map<String, dynamic>? ?? {};

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    onTap: () => _showFilterDetails(
                      _localizedSearchTitle(context, item),
                      filters,
                    ),
                    leading: Icon(Icons.bookmark, color: Color(0xFFFF6B00)),
                    title: Text(
                      _localizedSearchTitle(context, item),
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        _buildFilterChips(context, filters),
                        SizedBox(height: 4),
                        Text(
                          _formatDate(
                            context,
                            item['created_at']?.toString() ?? '',
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                            (item['notify'] == true)
                                ? Icons.notifications_active
                                : Icons.notifications_none,
                            color: const Color(0xFFFF6B00),
                          ),
                          onPressed: () => _toggleNotify(
                            index,
                            item['notify'] != true,
                          ),
                          tooltip: trLegacyText(
                            context,
                            'Alerts',
                            ar: 'التنبيهات',
                            ku: 'ئاگادارکردنەوە',
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.search, color: Colors.green),
                          onPressed: () => _applySearch(filters),
                          tooltip: AppLocalizations.of(context)!.applySearch,
                        ),
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _rename(index),
                          tooltip: AppLocalizations.of(context)!.renameTooltip,
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _delete(index),
                          tooltip: AppLocalizations.of(context)!.deleteTooltip,
                        ),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
    );
  }
}
