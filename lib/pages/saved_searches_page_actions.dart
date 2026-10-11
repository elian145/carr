part of 'saved_searches_page.dart';

mixin _SavedSearchesPageActions on _SavedSearchesPageFilterDetails {
  void _applySearch(Map<String, dynamic> filters) async {
    final normalized = SavedSearchService.normalizeFilters(filters);
    // Persist as a cold-start / late-registration backup. The live Home
    // host (MainShell IndexedStack) must also be told via HomeTabActions —
    // prefs alone are only consumed in Home's first post-frame callback,
    // which never re-runs when Home is already mounted.
    await SavedSearchHomeBridge.persistFiltersForHome(normalized);

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final loc = AppLocalizations.of(context)!;
    final successText = loc.searchAppliedSuccessfully;
    final failText = loc.errorTitle;

    final parent = widget.parentState;
    if (parent != null && parent.mounted) {
      Navigator.pop(context);
      parent.setState(() {
        parent.applyFiltersFromSavedSearch(normalized);
      });
      parent.fetchCars(bypassCache: true);
      // Clear bridge so the live Home host (if also mounted) does not
      // double-apply from one-time prefs.
      await SavedSearchHomeBridge.consumeOneTimeFilters();
      await SavedSearchHomeBridge.consumePendingFetch();
      messenger.showSnackBar(
        SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    if (Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
    navigateMainShellTab(context, '/');

    final applied = await HomeTabActions.applySavedSearchFilters(normalized);
    if (!mounted) return;
    if (applied) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(successText),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(failText),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
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
                  Icon(Icons.filter_list, color: AppColors.brandOrange, size: 20),
                  SizedBox(width: 8),
                  Text(
                    AppLocalizations.of(context)!.appliedFilters,
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
              AppLocalizations.of(context)!.close,
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _applySearch(filters);
            },
            style: TextButton.styleFrom(
              backgroundColor: AppColors.brandOrange,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              AppLocalizations.of(context)!.applySearch,
            ),
          ),
        ],
      ),
    );
  }
}
