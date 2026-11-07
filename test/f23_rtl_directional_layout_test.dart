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
}
