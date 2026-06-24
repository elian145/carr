part of 'saved_searches_page.dart';

mixin _SavedSearchesPageActions on _SavedSearchesPageFilterDetails {
  void _applySearch(Map<String, dynamic> filters) async {
    final normalized = SavedSearchService.normalizeFilters(filters);
    await SavedSearchHomeBridge.persistFiltersForHome(normalized);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final successText = trLegacyText(
      context,
      'Search applied successfully!',
      ar: 'تم تطبيق البحث بنجاح!',
      ku: 'گەڕان بە سەرکەوتوویی جێبەجێ کرا!',
    );

    final parent = widget.parentState;
    if (parent != null && parent.mounted) {
      Navigator.pop(context);
      parent.setState(() {
        parent.applyFiltersFromSavedSearch(normalized);
      });
      parent.fetchCars(bypassCache: true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    Navigator.pop(context);
    await SavedSearchHomeBridge.markPendingFetch();
    if (!mounted) return;
    navigateMainShellTab(context, '/');
    messenger.showSnackBar(
      SnackBar(
        content: Text(successText),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showFilterDetails(String searchName, Map<String, dynamic> filters) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Color(0xFF1E1E1E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(
          searchName,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.filter_list, color: Color(0xFFFF6B00), size: 20),
                  SizedBox(width: 8),
                  Text(
                    trLegacyText(
                      context,
                      'Applied Filters:',
                      ar: 'الفلاتر المطبقة:',
                      ku: 'فلتەرە جێبەجێکراوەکان:',
                    ),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 12),
              _buildDetailedFilterList(filters),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[400]),
            child: Text(
              trLegacyText(
                context,
                'Close',
                ar: 'إغلاق',
                ku: 'داخستن',
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applySearch(filters);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Color(0xFFFF6B00),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              trLegacyText(
                context,
                'Apply Search',
                ar: 'تطبيق البحث',
                ku: 'جێبەجێکردنی گەڕان',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
