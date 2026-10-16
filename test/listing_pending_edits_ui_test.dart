import 'package:car_listing_app/features/sell/sell_listing_payload.dart';
import 'package:car_listing_app/l10n/app_localizations.dart';
import 'package:car_listing_app/shared/listings/listing_pending_badge.dart';
import 'package:car_listing_app/shared/listings/listing_status.dart';
import 'package:car_listing_app/shared/listings/listing_to_sell_draft.dart';
import 'package:car_listing_app/shared/listings/pending_edits_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _active({
  String? revisionStatus,
  String? reason,
  Map<String, dynamic>? working,
}) => {
  'id': 'car_1',
  'public_id': 'car_1',
  'status': 'active',
  'title': 'Approved title',
  'price': 10000,
  'images': [
    {'id': 1, 'image_url': 'uploads/car_photos/approved.jpg', 'kind': 'listing'},
  ],
  'image_url': 'uploads/car_photos/approved.jpg',
  if (revisionStatus != null)
    'pending_revision': {
      'status': revisionStatus,
      'rejection_reason': reason,
      'changed_fields': ['price', 'images'],
      'car': working ??
          {
            'id': 'car_1',
            'title': 'Pending title',
            'price': 12000,
            'images': [
              {
                'id': 77,
                'image_url': 'uploads/car_photos/pending.jpg',
                'kind': 'listing',
              },
            ],
            'image_url': 'uploads/car_photos/pending.jpg',
          },
    },
};

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('pending revision state helpers', () {
    test('a plain Active listing has no pending revision', () {
      final l = _active();
      expect(listingHasPendingRevision(l), isFalse);
      expect(listingHasPendingEditsUnderReview(l), isFalse);
      expect(listingForOwnerEditing(l), same(l));
    });

    test('pending / rejected / editing are told apart', () {
      expect(
        listingHasPendingEditsUnderReview(_active(revisionStatus: 'pending')),
        isTrue,
      );
      final rejected = _active(revisionStatus: 'rejected', reason: 'Blurry');
      expect(listingHasRejectedEdits(rejected), isTrue);
      expect(listingRevisionRejectionReason(rejected), 'Blurry');
      expect(
        listingHasUnsubmittedEdits(_active(revisionStatus: 'editing')),
        isTrue,
      );
    });

    test('an Under Review listing never reports pending edits', () {
      final l = {..._active(revisionStatus: 'pending'), 'status': 'pending'};
      expect(listingHasPendingRevision(l), isFalse);
      expect(listingForOwnerEditing(l)['title'], 'Approved title');
    });

    test(
      'listingForOwnerEditing edits the pending version but keeps the '
      "approved listing's identity and status",
      () {
        final merged = listingForOwnerEditing(
          _active(revisionStatus: 'pending'),
        );
        expect(merged['title'], 'Pending title');
        expect(merged['price'], 12000);
        expect(merged['id'], 'car_1');
        expect(merged['public_id'], 'car_1');
        expect(merged['status'], 'active');
      },
    );

    test('the edit wizard snapshot is built from the pending photos', () {
      final snapshot = listingToSellDraftSnapshot(
        listingForOwnerEditing(_active(revisionStatus: 'pending')),
      );
      final data = snapshot['carData'] as Map<String, dynamic>;
      expect(data['_editListingId'], 'car_1');
      final images = data['images'] as List;
      expect(images, hasLength(1));
      expect(images.single.toString(), contains('pending.jpg'));
    });
  });

  group('update payload', () {
    const base = <String, dynamic>{
      'brand': 'Toyota',
      'model': 'Camry',
      'trim': 'LE',
      'year': '2020',
      'price': '12500',
      'mileage': '1000',
      'description': '',
      'vin': '',
    };

    test('blank optional fields are omitted by default (partial edits)', () {
      final payload = buildSellCarUpdatePayload(base);
      expect(payload.containsKey('description'), isFalse);
      expect(payload.containsKey('vin'), isFalse);
    });

    test('with clearEmptyOptionalFields blanks are sent as explicit null', () {
      final payload = buildSellCarUpdatePayload(
        base,
        clearEmptyOptionalFields: true,
      );
      expect(payload.containsKey('description'), isTrue);
      expect(payload['description'], isNull);
      expect(payload.containsKey('vin'), isTrue);
      expect(payload['vin'], isNull);
      // Required fields are never nulled.
      expect(payload['price'], 12500);
    });
  });

  group('owner UI', () {
    testWidgets('card badge says "Active — Edits Under Review"', (t) async {
      late BuildContext ctx;
      await t.pumpWidget(
        _host(
          Builder(
            builder: (c) {
              ctx = c;
              return buildListingStatusBadge(
                    c,
                    _active(revisionStatus: 'pending'),
                  ) ??
                  const Text('none');
            },
          ),
        ),
      );
      expect(find.text('Active \u2014 Edits Under Review'), findsOneWidget);
      expect(
        buildListingStatusBadge(ctx, _active()),
        isNull,
        reason: 'a plain Active listing shows no badge',
      );
    });

    testWidgets('rejected edits show the admin reason and the actions', (
      t,
    ) async {
      var discarded = 0;
      var edited = 0;
      await t.pumpWidget(
        _host(
          PendingEditsBanner(
            listing: _active(
              revisionStatus: 'rejected',
              reason: 'Photos are blurry',
            ),
            onEdit: () => edited++,
            onDiscard: () => discarded++,
            onPreview: () {},
          ),
        ),
      );
      expect(find.text('Active \u2014 Edits Not Approved'), findsOneWidget);
      expect(
        find.text('Your changes were not approved: Photos are blurry'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const ValueKey('pending_edits_edit')));
      await t.tap(find.byKey(const ValueKey('pending_edits_discard')));
      expect(edited, 1);
      expect(discarded, 1);
    });

    testWidgets('banner is empty without a pending revision', (t) async {
      await t.pumpWidget(_host(PendingEditsBanner(listing: _active())));
      expect(find.byKey(const ValueKey('pending_edits_banner')), findsNothing);
    });

    testWidgets('under-review banner explains buyers still see approved', (
      t,
    ) async {
      await t.pumpWidget(
        _host(PendingEditsBanner(listing: _active(revisionStatus: 'pending'))),
      );
      expect(
        find.textContaining('Buyers still see the approved version'),
        findsOneWidget,
      );
    });
  });
}
