import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:car_listing_app/shared/ui/keyboard.dart';

void main() {
  group('keyboard focus helpers (A-05)', () {
    testWidgets('focusNextField moves to the next TextField', (tester) async {
      final first = FocusNode();
      final second = FocusNode();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(
                  focusNode: first,
                  autofocus: true,
                  onSubmitted: (_) {},
                ),
                TextField(focusNode: second),
                Builder(
                  builder: (context) {
                    return TextButton(
                      onPressed: () => focusNextField(context),
                      child: const Text('next'),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      expect(first.hasFocus, isTrue);

      await tester.tap(find.text('next'));
      await tester.pump();
      expect(second.hasFocus, isTrue);
    });

    testWidgets('requestFocusAfterFrame focuses the target node', (
      tester,
    ) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(focusNode: node),
          ),
        ),
      );
      expect(node.hasFocus, isFalse);

      requestFocusAfterFrame(node);
      await tester.pump();
      expect(node.hasFocus, isTrue);
    });

    testWidgets('dismissAnyKeyboard clears primary focus', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TextField(focusNode: node, autofocus: true),
          ),
        ),
      );
      await tester.pump();
      expect(node.hasFocus, isTrue);

      dismissAnyKeyboard();
      await tester.pump();
      expect(node.hasFocus, isFalse);
    });
  });
}
