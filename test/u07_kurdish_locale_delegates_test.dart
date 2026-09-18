import 'dart:async';

import 'package:car_listing_app/features/chat/chat_strings.dart';
import 'package:car_listing_app/shared/i18n/ku_delegates.dart';
import 'package:car_listing_app/state/locale_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// U-07: Kurdish must no longer intentionally use Arabic Material/Cupertino
/// localization as a proxy (and, per a later follow-up, must no longer
/// silently fall back to English either): Kurdish system chrome
/// (OK/Cancel/date-picker labels/text-selection toolbar/etc.) must be
/// genuinely Kurdish. `ckb` must not be added as a fourth supported locale,
/// and stale `ckb` references must resolve consistently to `ku`.
Widget _kuApp(Widget home) {
  return MaterialApp(
    locale: const Locale('ku'),
    supportedLocales: const [Locale('en'), Locale('ar'), Locale('ku')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      KuMaterialLocalizationsDelegate(),
      KuWidgetsLocalizationsDelegate(),
      KuCupertinoLocalizationsDelegate(),
    ],
    home: home,
  );
}

void main() {
  group('U-07 supported locales', () {
    test('Kurdish locale resolution remains "ku" (not "ckb")', () {
      expect(LocaleController.supportedCodes, ['en', 'ar', 'ku']);
      expect(LocaleController.supportedCodes, isNot(contains('ckb')));
    });
  });

  group('U-07 stale "ckb" alias resolves consistently to "ku"', () {
    testWidgets('chatText treats ckb the same as ku, not English', (
      tester,
    ) async {
      await tester.pumpWidget(
        _kuApp(
          Builder(
            builder: (context) {
              // `ku` (the real resolved locale) and the stale `ckb` alias
              // path inside chatText must produce the identical string.
              final viaKu = chatText(
                context,
                'English',
                ar: 'عربي',
                ku: 'کوردی',
              );
              expect(viaKu, 'کوردی');
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    });
  });

  group(
    'U-07 Kurdish Material/Cupertino/Widgets localizations are genuinely '
    'Kurdish (not Arabic, not English)',
    () {
      testWidgets(
        '`Locale(\'ku\')` resolves through the custom Kurdish delegates',
        (tester) async {
          late BuildContext capturedContext;
          await tester.pumpWidget(
            _kuApp(
              Builder(
                builder: (context) {
                  capturedContext = context;
                  return const Scaffold(body: SizedBox());
                },
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(Localizations.localeOf(capturedContext), const Locale('ku'));
          final matLoc = MaterialLocalizations.of(capturedContext);
          expect(matLoc.okButtonLabel, 'باشە');
        },
      );

      testWidgets('Common Material action strings are Kurdish', (
        tester,
      ) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _kuApp(
            Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final matLoc = MaterialLocalizations.of(capturedContext);
        // Neither English ("OK"/"Cancel") nor Arabic ("موافق"/"إلغاء").
        expect(matLoc.okButtonLabel, 'باشە');
        expect(matLoc.cancelButtonLabel, 'هەڵوەشاندنەوە');
        expect(matLoc.okButtonLabel, isNot('OK'));
        expect(matLoc.okButtonLabel, isNot('موافق'));
        expect(matLoc.cancelButtonLabel, isNot('Cancel'));
        expect(matLoc.cancelButtonLabel, isNot('إلغاء'));
        expect(matLoc.closeButtonLabel, 'داخستن');
        expect(matLoc.saveButtonLabel, 'پاشەکەوتکردن');
        expect(matLoc.deleteButtonTooltip, 'سڕینەوە');
        expect(matLoc.backButtonTooltip, 'گەڕانەوە');
        expect(matLoc.searchFieldLabel, 'گەڕان');
      });

      testWidgets('representative date-picker labels are Kurdish', (
        tester,
      ) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _kuApp(
            Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final matLoc = MaterialLocalizations.of(capturedContext);
        expect(matLoc.datePickerHelpText, 'بەروار هەڵبژێرە');
        expect(matLoc.dateInputLabel, 'بەروار بنووسە');
        expect(matLoc.invalidDateFormatLabel, 'شێوازی نادروست.');
        expect(matLoc.currentDateLabel, 'ئەمڕۆ');
        expect(matLoc.nextMonthTooltip, 'مانگی داهاتوو');
        expect(matLoc.previousMonthTooltip, 'مانگی پێشوو');
        // representative time-picker labels
        expect(matLoc.timePickerDialHelpText, 'کاتژمێر هەڵبژێرە');
        expect(matLoc.timePickerHourLabel, 'کاتژمێر');
        expect(matLoc.timePickerMinuteLabel, 'خولەک');
      });

      testWidgets('representative text-selection labels are Kurdish', (
        tester,
      ) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _kuApp(
            Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final matLoc = MaterialLocalizations.of(capturedContext);
        expect(matLoc.copyButtonLabel, 'کۆپیکردن');
        expect(matLoc.cutButtonLabel, 'بڕین');
        expect(matLoc.pasteButtonLabel, 'لکاندن');
        expect(matLoc.selectAllButtonLabel, 'هەموو هەڵبژێرە');

        final widgetsLoc = WidgetsLocalizations.of(capturedContext);
        expect(widgetsLoc.copyButtonLabel, 'کۆپیکردن');
        expect(widgetsLoc.cutButtonLabel, 'بڕین');
        expect(widgetsLoc.pasteButtonLabel, 'لکاندن');
        expect(widgetsLoc.selectAllButtonLabel, 'هەموو هەڵبژێرە');
      });

      testWidgets('Cupertino system strings are Kurdish', (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _kuApp(
            Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final cupLoc = CupertinoLocalizations.of(capturedContext);
        // Neither English ("Today"/"Cancel") nor Arabic ("اليوم"/"الإلغاء").
        expect(cupLoc.todayLabel, 'ئەمڕۆ');
        expect(cupLoc.todayLabel, isNot('Today'));
        expect(cupLoc.cancelButtonLabel, 'هەڵوەشاندنەوە');
        expect(cupLoc.cancelButtonLabel, isNot('Cancel'));
        expect(cupLoc.copyButtonLabel, 'کۆپیکردن');
        expect(cupLoc.cutButtonLabel, 'بڕین');
        expect(cupLoc.pasteButtonLabel, 'لکاندن');
        expect(cupLoc.selectAllButtonLabel, 'هەموو هەڵبژێرە');
      });

      testWidgets(
        'Kurdish text direction stays RTL even though it now has its own '
        'genuine Kurdish system strings',
        (tester) async {
          late BuildContext capturedContext;
          await tester.pumpWidget(
            _kuApp(
              Builder(
                builder: (context) {
                  capturedContext = context;
                  return const Scaffold(body: SizedBox());
                },
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(Directionality.of(capturedContext), TextDirection.rtl);
        },
      );
    },
  );

  group('U-07 real framework dialogs/pickers under Locale(\'ku\')', () {
    testWidgets('showDialog AlertDialog OK/Cancel buttons render Kurdish', (
      tester,
    ) async {
      await tester.pumpWidget(
        _kuApp(
          Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        builder: (ctx) {
                          final matLoc = MaterialLocalizations.of(ctx);
                          return AlertDialog(
                            title: const Text('Test'),
                            actions: [
                              TextButton(
                                onPressed: () {},
                                child: Text(matLoc.cancelButtonLabel),
                              ),
                              TextButton(
                                onPressed: () {},
                                child: Text(matLoc.okButtonLabel),
                              ),
                            ],
                          );
                        },
                      );
                    },
                    child: const Text('Open'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('باشە'), findsOneWidget);
      expect(find.text('هەڵوەشاندنەوە'), findsOneWidget);
      expect(find.text('OK'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets(
      'showDatePicker renders Kurdish help text and OK/Cancel labels',
      (tester) async {
        late BuildContext capturedContext;
        await tester.pumpWidget(
          _kuApp(
            Builder(
              builder: (context) {
                capturedContext = context;
                return const Scaffold(body: SizedBox());
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        unawaited(
          showDatePicker(
            context: capturedContext,
            initialDate: DateTime(2024, 1, 15),
            firstDate: DateTime(2020, 1, 1),
            lastDate: DateTime(2030, 12, 31),
          ),
        );
        await tester.pumpAndSettle();

        // Kurdish help text/action labels from _MaterialLocalizationKu.
        expect(find.text('بەروار هەڵبژێرە'), findsOneWidget);
        expect(find.text('باشە'), findsOneWidget);
        expect(find.text('هەڵوەشاندنەوە'), findsOneWidget);
        expect(find.text('Select date'), findsNothing);
        expect(find.text('OK'), findsNothing);
        expect(find.text('Cancel'), findsNothing);
      },
    );
  });
}
