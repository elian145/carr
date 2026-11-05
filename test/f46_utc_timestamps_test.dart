// F-46 -- API timestamps are UTC; every client parse site must honour that.
//
// The backend (F-07) now sends `...Z`, but older servers/rows/caches still
// produce offset-less strings (`2026-03-04T05:06:07.123456`). Dart's
// `DateTime.parse` reads those as DEVICE-LOCAL time, which on a UTC+3 phone
// (Iraq) made saved searches, analytics and chat 3 hours off.
//
// These tests are deterministic on any machine time zone: they compare
// absolute instants (`toUtc()`), or assert that the legacy / `Z` / `+03:00`
// spellings of the same instant behave identically. On a UTC machine the
// baseline bug is invisible by construction (local == UTC), on any other zone
// the legacy-path assertions fail against the old `DateTime.parse` code.
import 'package:car_listing_app/features/home/home_feed_client_sort.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/models/analytics_model.dart';
import 'package:car_listing_app/models/chat_message.dart';
import 'package:car_listing_app/pages/saved_searches_page.dart'
    show formatSavedSearchDate;
import 'package:car_listing_app/services/websocket_service.dart'
    show parseApiDateTime, tryParseApiDateTime;
import 'package:car_listing_app/shared/listings/listing_uploaded_ago.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// The same instant, spelled the three ways the client can receive it.
class _Spellings {
  _Spellings(DateTime instantUtc)
    : instant = instantUtc,
      legacy = _stripZone(instantUtc),
      z = instantUtc.toIso8601String(),
      plus03 = _asOffset(instantUtc, const Duration(hours: 3), '+03:00');

  final DateTime instant;
  final String legacy; // what pre-F-07 servers sent (no designator)
  final String z; // what F-07 servers send
  final String plus03; // an explicit offset

  List<String> get all => [legacy, z, plus03];

  static String _stripZone(DateTime utc) {
    final s = utc.toIso8601String();
    return s.endsWith('Z') ? s.substring(0, s.length - 1) : s;
  }

  static String _asOffset(DateTime utc, Duration offset, String suffix) {
    final shifted = utc.add(offset).toIso8601String(); // ends with Z
    return '${shifted.substring(0, shifted.length - 1)}$suffix';
  }
}

Widget _app(Widget Function(BuildContext) builder) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Builder(builder: builder),
);

Map<String, dynamic> _analyticsJson(Map<String, dynamic> extra) => {
  'listing_id': 'car-1',
  'title': 't',
  'brand': 'toyota',
  'model': 'camry',
  'year': 2020,
  'price': 1000,
  'views': 1,
  'messages': 0,
  'calls': 0,
  'shares': 0,
  'favorites': 0,
  ...extra,
};

void main() {
  final instant = DateTime.utc(2026, 3, 4, 5, 6, 7, 123, 456);
  final spellings = _Spellings(instant);

  group('parseApiDateTime / tryParseApiDateTime', () {
    test('legacy, Z and +03:00 spellings are the same absolute instant', () {
      for (final s in spellings.all) {
        expect(parseApiDateTime(s).toUtc(), instant, reason: s);
        expect(tryParseApiDateTime(s)!.toUtc(), instant, reason: s);
      }
    });

    test('legacy offset-less is UTC wall-clock, never device-local', () {
      expect(
        parseApiDateTime('2026-03-04T05:06:07').toUtc(),
        DateTime.utc(2026, 3, 4, 5, 6, 7),
      );
    });

    test('tryParseApiDateTime is null for absent/garbage input', () {
      expect(tryParseApiDateTime(null), isNull);
      expect(tryParseApiDateTime(''), isNull);
      expect(tryParseApiDateTime('   '), isNull);
      expect(tryParseApiDateTime('not-a-date'), isNull);
    });

    test('tryParseApiDateTime agrees with parseApiDateTime when parseable', () {
      for (final s in spellings.all) {
        expect(tryParseApiDateTime(s), parseApiDateTime(s));
      }
    });
  });

  group('ChatMessage (lib/models/chat_message.dart)', () {
    Map<String, dynamic> msg(String createdAt, {String key = 'created_at'}) => {
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 's1',
      'body': 'hi',
      key: createdAt,
    };

    test('created_at parses to the right instant for every spelling', () {
      for (final s in spellings.all) {
        expect(ChatMessage.fromJson(msg(s)).createdAt!.toUtc(), instant);
        expect(
          ChatMessage.fromJson(msg(s, key: 'timestamp')).createdAt!.toUtc(),
          instant,
        );
      }
    });

    test('a message N minutes old is N minutes old (not shifted by TZ)', () {
      final sentAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 30),
      );
      for (final s in _Spellings(sentAt).all) {
        final age = DateTime.now().difference(
          ChatMessage.fromJson(msg(s)).createdAt!,
        );
        expect(age.inMinutes, inInclusiveRange(29, 31), reason: s);
      }
    });

    test('missing or unparseable created_at stays null', () {
      expect(ChatMessage.fromJson(msg('')).createdAt, isNull);
      expect(ChatMessage.fromJson(msg('garbage')).createdAt, isNull);
      expect(
        ChatMessage.fromJson({'id': 'x', 'body': 'b'}).createdAt,
        isNull,
      );
    });

    test('toJson -> fromJson round trip keeps the instant', () {
      final original = ChatMessage.fromJson(msg(spellings.legacy));
      final back = ChatMessage.fromJson(original.toJson());
      expect(back.createdAt!.toUtc(), instant);
      expect(original.toJson()['created_at'], endsWith('Z'));
    });
  });

  group('ListingAnalytics (lib/models/analytics_model.dart)', () {
    test('created_at / last_updated parse to the right instant', () {
      for (final s in spellings.all) {
        final a = ListingAnalytics.fromJson(
          _analyticsJson({'created_at': s, 'last_updated': s}),
        );
        expect(a.createdAt.toUtc(), instant, reason: s);
        expect(a.lastUpdated.toUtc(), instant, reason: s);
      }
    });

    test('a listing N minutes old is N minutes old', () {
      final created = DateTime.now().toUtc().subtract(
        const Duration(minutes: 45),
      );
      for (final s in _Spellings(created).all) {
        final a = ListingAnalytics.fromJson(
          _analyticsJson({'created_at': s, 'last_updated': s}),
        );
        expect(
          DateTime.now().difference(a.createdAt).inMinutes,
          inInclusiveRange(44, 46),
          reason: s,
        );
      }
    });

    test('absent timestamps fall back to "now" instead of throwing', () {
      final a = ListingAnalytics.fromJson(_analyticsJson({}));
      expect(DateTime.now().difference(a.createdAt).inSeconds.abs(), lessThan(5));
    });

    test('toJson -> fromJson round trip keeps the instant', () {
      final a = ListingAnalytics.fromJson(
        _analyticsJson({
          'created_at': spellings.legacy,
          'last_updated': spellings.z,
        }),
      );
      final back = ListingAnalytics.fromJson(a.toJson());
      expect(back.createdAt.toUtc(), instant);
      expect(back.lastUpdated.toUtc(), instant);
    });
  });

  group('saved searches date label (formatSavedSearchDate)', () {
    testWidgets('legacy, Z and +03:00 render the same local time', (
      tester,
    ) async {
      final created = DateTime.utc(2026, 3, 4, 11, 30);
      final now = created.add(const Duration(minutes: 30));
      final labels = <String>[];
      await tester.pumpWidget(
        _app((context) {
          for (final s in _Spellings(created).all) {
            labels.add(formatSavedSearchDate(context, s, now: now));
          }
          return const SizedBox.shrink();
        }),
      );
      final local = created.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      expect(labels, ['Today $hh:$mm', 'Today $hh:$mm', 'Today $hh:$mm']);
    });

    testWidgets('relative buckets are computed from absolute instants', (
      tester,
    ) async {
      final created = DateTime.utc(2026, 3, 4, 11, 30);
      final out = <String>[];
      await tester.pumpWidget(
        _app((context) {
          for (final s in _Spellings(created).all) {
            out.add(
              formatSavedSearchDate(
                context,
                s,
                now: created.add(const Duration(hours: 30)),
              ),
            );
            out.add(
              formatSavedSearchDate(
                context,
                s,
                now: created.add(const Duration(days: 3, hours: 1)),
              ),
            );
          }
          return const SizedBox.shrink();
        }),
      );
      final local = created.toLocal();
      final hh = local.hour.toString().padLeft(2, '0');
      final mm = local.minute.toString().padLeft(2, '0');
      expect(out, [
        for (var i = 0; i < 3; i++) ...['Yesterday $hh:$mm', '3 days ago'],
      ]);
    });

    testWidgets('unparseable input is returned unchanged', (tester) async {
      String? got;
      await tester.pumpWidget(
        _app((context) {
          got = formatSavedSearchDate(context, 'garbage');
          return const SizedBox.shrink();
        }),
      );
      expect(got, 'garbage');
    });
  });

  group('listing card "uploaded ago" (listingUploadedAgo)', () {
    testWidgets('a listing 30 minutes old reads "30 minutes ago" in every form', (
      tester,
    ) async {
      final created = DateTime.now().toUtc().subtract(
        const Duration(minutes: 30),
      );
      final out = <String>[];
      late AppLocalizations l;
      await tester.pumpWidget(
        _app((context) {
          l = AppLocalizations.of(context)!;
          for (final s in _Spellings(created).all) {
            out.add(listingUploadedAgo(context, {'created_at': s}));
          }
          return const SizedBox.shrink();
        }),
      );
      expect(out, List.filled(3, l.timeMinutesAgo(30)));
    });

    testWidgets('a listing 3 hours old reads "3 hours ago" in every form', (
      tester,
    ) async {
      final created = DateTime.now().toUtc().subtract(
        const Duration(hours: 3, minutes: 1),
      );
      final out = <String>[];
      late AppLocalizations l;
      await tester.pumpWidget(
        _app((context) {
          l = AppLocalizations.of(context)!;
          for (final s in _Spellings(created).all) {
            out.add(listingUploadedAgo(context, {'created_at': s}));
          }
          return const SizedBox.shrink();
        }),
      );
      expect(out, List.filled(3, l.timeHoursAgo(3)));
    });
  });

  group('home feed client sort (newest)', () {
    test('mixed legacy and Z created_at order by absolute instant', () {
      final older = {'id': 'older', 'created_at': '2026-03-04T11:00:00Z'};
      // 12:00 UTC in the legacy spelling: newer than 11:00Z on every machine.
      final newer = {'id': 'newer', 'created_at': '2026-03-04T12:00:00'};
      final sorted = homeFeedClientSortedListings([older, newer], 'newest');
      expect(sorted.map((e) => e['id']).toList(), ['newer', 'older']);
    });
  });
}
