part of 'saved_searches_page.dart';

mixin _SavedSearchesPageCore on _SavedSearchesPageActions {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.savedSearchesTitle),
      ),
      body: _loading
          ? _savedSearchesSkeleton(context)
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
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _items.length,
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
                    leading: Icon(Icons.bookmark, color: AppColors.brandOrange),
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
                            color: AppColors.brandOrange,
                          ),
                          onPressed: () => _toggleNotify(
                            index,
                            item['notify'] != true,
                          ),
                          tooltip: AppLocalizations.of(context)!.alerts,
                        ),
                        IconButton(
                          icon: Icon(Icons.search, color: Colors.green),
                          onPressed: () => _applySearch(filters),
                          tooltip: AppLocalizations.of(context)!.applySearch,
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

  Widget _savedSearchesSkeleton(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        itemCount: 6,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemBuilder: (context, _) => Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(height: 14, width: 160, color: Colors.white),
                      const SizedBox(height: 8),
                      Container(
                        height: 12,
                        width: double.infinity,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 6),
                      Container(height: 12, width: 100, color: Colors.white),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
