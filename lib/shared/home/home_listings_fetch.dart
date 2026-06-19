import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

import '../../services/config.dart';
import 'home_filter_query.dart';

class HomeListingsPageResult {
  const HomeListingsPageResult({
    required this.cars,
    required this.hasNext,
  });

  final List<Map<String, dynamic>> cars;
  final bool hasNext;
}

/// Fetches a page of home listings using persisted filter prefs.
Future<HomeListingsPageResult> fetchHomeListingsPage({
  required int page,
  required int perPage,
  BuildContext? context,
  Map<String, String>? extraFilters,
}) async {
  final filters = await HomeFilterQuery.fromSharedPreferences(context: context);
  if (extraFilters != null) {
    filters.addAll(extraFilters);
  }
  filters['page'] = page.toString();
  filters['per_page'] = perPage.toString();

  final query = Uri(queryParameters: filters).query;
  final url = Uri.parse(
    '${effectiveApiBase()}/api/cars${query.isNotEmpty ? '?$query' : ''}',
  );

  final timeout = filters.containsKey('sort_by')
      ? const Duration(seconds: 30)
      : const Duration(seconds: 15);

  final response = await http
      .get(
        url,
        headers: const {
          'Connection': 'keep-alive',
          'Accept': 'application/json',
          'User-Agent': 'CarNet-Mobile/1.0',
          'Cache-Control': 'no-cache',
          'Pragma': 'no-cache',
        },
      )
      .timeout(timeout);

  if (response.statusCode != 200) {
    throw HomeListingsFetchException(
      'Listings request failed (${response.statusCode})',
    );
  }

  final decoded = json.decode(response.body);
  List<dynamic> listSource;
  var hasNext = false;

  if (decoded is List) {
    listSource = decoded;
    hasNext = listSource.length >= perPage;
  } else if (decoded is Map && decoded['cars'] is List) {
    listSource = decoded['cars'] as List;
    final pg = decoded['pagination'];
    if (pg is Map && pg['has_next'] is bool) {
      hasNext = pg['has_next'] as bool;
    } else {
      hasNext = listSource.length >= perPage;
    }
  } else {
    listSource = const [];
  }

  final parsed = listSource
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e.cast<String, dynamic>()))
      .toList();

  return HomeListingsPageResult(
    cars: HomeFilterQuery.applyDamagedPartsExactFilter(parsed, filters),
    hasNext: hasNext,
  );
}

class HomeListingsFetchException implements Exception {
  HomeListingsFetchException(this.message);
  final String message;
  @override
  String toString() => message;
}
