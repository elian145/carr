import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// F-23: overlays/bubbles must use start/end so Arabic and Sorani mirror.
String _src(String rel) => File(rel).readAsStringSync();

void main() {
  group('source guards (no one-sided physical offsets in fixed spots)', () {
    test('tiktok card back button is pinned to the start edge', () {
      final s = _src('lib/pages/tiktok_scroll_listing_card.dart');
      final i = s.indexOf('// Back button');
      expect(i, greaterThan(-1));
      final block = s.substring(i, i + 400);
      expect(block, contains('PositionedDirectional('));
      expect(block, contains('start: 8'));
      expect(block, isNot(contains('left: 8')));
    });

    test('chat bubble alignment and edited-label padding are directional', () {
      final s = _src(
        'lib/features/chat/chat_conversation_page_build_body_messages.dart',
      );
      expect(s, contains('AlignmentDirectional.centerEnd'));
      expect(s, contains('AlignmentDirectional.centerStart'));
      expect(s, isNot(contains('Alignment.centerRight')));
      expect(s, isNot(contains('Alignment.centerLeft')));
      expect(RegExp(r'EdgeInsets\.only\(\s*right:').hasMatch(s), isFalse);
    });

    test('count badges and video tag use PositionedDirectional', () {
      for (final rel in [
        'lib/app/widgets/global_listing_card_build.dart',
        'lib/app/widgets/global_listing_card_carousel.dart',
        'lib/widgets/in_app_video_screen.dart',
      ]) {
        final s = _src(rel);
        expect(
          RegExp(r'Positioned\(\s*(top|bottom): \d+,\s*right: \d+,')
              .hasMatch(s),
          isFalse,
          reason: rel,
        );
        expect(s, contains('PositionedDirectional('), reason: rel);
      }
    });
  });

  testWidgets('PositionedDirectional(start) mirrors in RTL, not in LTR',
      (t) async {
    Future<double> leftOf(TextDirection d) async {
      await t.pumpWidget(
        Directionality(
          textDirection: d,
          child: const Stack(
            children: [
              PositionedDirectional(
                top: 0,
                start: 8,
                child: SizedBox(key: ValueKey('b'), width: 20, height: 20),
              ),
            ],
          ),
        ),
      );
      return t.getTopLeft(find.byKey(const ValueKey('b'))).dx;
    }

    // Stack fills the 800x600 test surface.
    expect(await leftOf(TextDirection.ltr), 8);
    expect(await leftOf(TextDirection.rtl), 800 - 8 - 20);
  });

  group('round 2: remaining physical left/right replaced by start/end', () {
    const converted = [
      'lib/app/widgets/global_listing_card_build.dart',
      'lib/features/chat/widgets/chat_media_viewer.dart',
      'lib/features/chat/widgets/chat_composer_widgets.dart',
      'lib/pages/comparison_page_helpers.dart',
      'lib/pages/production_favorites_page.dart',
      'lib/pages/recently_viewed_page.dart',
      'lib/pages/listing_image_gallery_grid_page.dart',
      'lib/pages/listing_preview_media_grid_page.dart',
      'lib/pages/dealer_profile_page_helpers.dart',
      'lib/pages/edit_profile_page_widgets.dart',
      'lib/pages/my_listings_page.dart',
      'lib/pages/tiktok_scroll_listing_card.dart',
    ];
    // A Positioned that pins to ONE physical side (left or right) only;
    // full-width `left: 0, right: 0` stretches are symmetric and fine.
    final oneSided = RegExp(
      r'\bPositioned\(\s*(?:(?:top|bottom): [^,\n]+,\s*)?(?:left|right): [^,\n]+,\s*(?:(?:top|bottom): [^,\n]+,\s*)?child:',
    );

    test('overlays pinned to one side use PositionedDirectional', () {
      for (final rel in converted) {
        final s = _src(rel);
        expect(oneSided.hasMatch(s), isFalse, reason: rel);
        expect(s, contains('PositionedDirectional('), reason: rel);
      }
    });

    test('reply quote bar uses BorderDirectional(start)', () {
      final s = _src('lib/features/chat/widgets/chat_composer_widgets.dart');
      expect(s, contains('BorderDirectional(start:'));
      expect(s, isNot(contains('Border(left:')));
    });

    test('shared alignments and trailing text align are directional', () {
      final responsive = _src('lib/shared/ui/responsive.dart');
      expect(responsive, isNot(contains('Alignment.centerRight')));
      expect(responsive, isNot(contains('Alignment.centerLeft')));
      final profile = _src('lib/pages/production_profile_body_account.dart');
      expect(profile, isNot(contains('Alignment.bottomLeft')));
      expect(profile, isNot(contains('Alignment.centerLeft')));
      final typing = _src(
        'lib/features/chat/chat_conversation_page_build_body_composer.dart',
      );
      expect(typing, isNot(contains('Alignment.centerLeft')));
      for (final rel in [
        'lib/features/chat/chat_list_page.dart',
        'lib/features/listing/car_listing_specs_grid_widgets.dart',
        'lib/widgets/in_app_video_screen.dart',
      ]) {
        expect(_src(rel), isNot(contains('TextAlign.right')), reason: rel);
      }
    });

    test('sell progress segments space with end margin', () {
      final s = _src('lib/features/sell/sell_draft_gate.dart');
      expect(s, contains('EdgeInsetsDirectional.only('));
      expect(RegExp(r'EdgeInsets\.only\(\s*right:').hasMatch(s), isFalse);
    });
  });

  test('phone numbers render LTR so +964 digits do not reorder in RTL', () {
    final contact = _src('lib/pages/car_details_page_contact.dart');
    expect(contact, contains('Text(phone, textDirection: TextDirection.ltr)'));
    final dealer = _src('lib/pages/dealer_profile_page_helpers.dart');
    expect(
      RegExp(r'Text\(\s*phones\[i\],[\s\S]{0,160}?textDirection: TextDirection\.ltr')
          .hasMatch(dealer),
      isTrue,
    );  });
  test('BorderDirectional(start) draws the quote bar on the leading edge', () {
    const border = BorderDirectional(
      start: BorderSide(color: Colors.red, width: 3),
    );
    expect(border.dimensions.resolve(TextDirection.ltr).left, 3);
    expect(border.dimensions.resolve(TextDirection.rtl).left, 0);
    expect(border.dimensions.resolve(TextDirection.rtl).right, 3);
  });
}
