// WCAG 2.x contrast guards for the remaining a11y gaps after F-24:
//  * SnackBars (shared theme + warning snackbars that used `Colors.orange`),
//  * dark-theme `onPrimary` on the bright brand orange (FilledButton etc.),
//  * muted grey text (old `0xFF8E8E93` was ~3.3:1 on white),
//  * strong orange text on the light-grey card / field fills (~4.4:1 before).
import 'dart:io';

import 'package:car_listing_app/theme/app_colors.dart';
import 'package:car_listing_app/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// [fg] at [alpha] painted over opaque [bg].
Color _over(Color fg, Color bg, double alpha) =>
    Color.alphaBlend(fg.withValues(alpha: alpha), bg);

void main() {
  const white = Colors.white;
  const lightGreys = <String, Color>{
    'listing card F4F4F4': Color(0xFFF4F4F4),
    'compact card F6F6F6': Color(0xFFF6F6F6),
    'field fill F3F3F3': Color(0xFFF3F3F3),
    'iOS grey F2F2F7': Color(0xFFF2F2F7),
  };
  const lightSurfaces = <String, Color>{
    'white shell': Colors.white,
    'specs card tint FFF7F0': Color(0xFFFFF7F0),
    ...lightGreys,
    'input fill E0E0E0': Color(0xFFE0E0E0),
  };
  const darkSurfaces = <String, Color>{
    'dark card 1E1E1E': Color(0xFF1E1E1E),
    'specs card tint 2A211C': Color(0xFF2A211C),
    'dark 121212': Color(0xFF121212),
    'shell 131722': Color(0xFF131722),
    'shell 0F1115': Color(0xFF0F1115),
  };

  group('SnackBars (item 1)', () {
    test(
      'documents the violation: Colors.orange fails with white and dark',
      () {
        expect(_contrast(Colors.orange, white), lessThan(3.0));
        expect(
          _contrast(Colors.orange, const Color(0xFF1A1A1A)),
          greaterThan(4.5),
        );
        // ...and the old pending-review banner colour with white / M3 text.
        expect(_contrast(const Color(0xFFF57C00), white), lessThan(3.0));
      },
    );

    test('warning snackbar: white text on the warning background >= 4.5:1', () {
      expect(
        _contrast(
          AppColors.onWarningSnackBar,
          AppColors.warningSnackBarBackground,
        ),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        AppColors.warningSnackBarTextStyle.color,
        AppColors.onWarningSnackBar,
      );
      // Still recognisably orange (red-dominant, no blue).
      final c = AppColors.warningSnackBarBackground;
      expect(c.r, greaterThan(c.g));
      expect(c.g, greaterThan(c.b));
    });

    test('status banner snackbar colours carry white text at >= 4.5:1', () {
      for (final bg in <Color>[
        AppColors.warningSnackBarBackground,
        Colors.green.shade800,
        Colors.red.shade700,
      ]) {
        expect(_contrast(white, bg), greaterThanOrEqualTo(4.5), reason: '$bg');
      }
    });

    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      test('$name SnackBarThemeData: text and action vs background', () {
        final theme = dark ? AppThemes.darkTheme : AppThemes.lightTheme;
        final sb = theme.snackBarTheme;
        final bg = sb.backgroundColor!;
        expect(bg.a, 1.0);
        expect(
          _contrast(sb.contentTextStyle!.color!, bg),
          greaterThanOrEqualTo(4.5),
        );
        expect(_contrast(sb.actionTextColor!, bg), greaterThanOrEqualTo(4.5));
        final disabled = _over(sb.disabledActionTextColor!, bg, 1.0);
        // Disabled action labels are exempt from WCAG, but keep them legible.
        expect(_contrast(disabled, bg), greaterThanOrEqualTo(3.0));
      });
    }

    testWidgets('warning snackbar text is white in both themes', (
      tester,
    ) async {
      for (final theme in [AppThemes.lightTheme, AppThemes.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Builder(
                builder: (ctx) => TextButton(
                  onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: WarningSnackBarText('warn-me'),
                      backgroundColor: AppColors.warningSnackBarBackground,
                    ),
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final text = tester.widget<Text>(find.text('warn-me'));
        expect(text.style!.color, AppColors.onWarningSnackBar);
        ScaffoldMessenger.of(tester.element(find.text('go'))).clearSnackBars();
        await tester.pump();
      }
    });

    test('source guard: no raw Colors.orange SnackBar backgrounds in lib/', () {
      final offenders = <String>[];
      final raw = RegExp(r'backgroundColor:\s*Colors\.orange\b');
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final p = f.path.replaceAll('\\', '/');
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (raw.hasMatch(lines[i])) offenders.add('$p:${i + 1}');
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'Use AppColors.warningSnackBarBackground + WarningSnackBarText '
            '(Colors.orange is ~2:1 with any text colour).',
      );
    });
  });

  group('onPrimary pairs (item 2)', () {
    test('documents the violation: white on the bright brand orange', () {
      expect(_contrast(white, AppColors.brandOrange), lessThan(3.0));
    });

    for (final dark in [false, true]) {
      final name = dark ? 'dark' : 'light';
      test('$name colorScheme onPrimary text on primary >= 4.5:1', () {
        final scheme =
            (dark ? AppThemes.darkTheme : AppThemes.lightTheme).colorScheme;
        expect(
          _contrast(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('$name ElevatedButton / AppBar foreground vs fill >= 4.5:1', () {
        final theme = dark ? AppThemes.darkTheme : AppThemes.lightTheme;
        final style = theme.elevatedButtonTheme.style!;
        final bg = style.backgroundColor!.resolve(<WidgetState>{})!;
        final fg = style.foregroundColor!.resolve(<WidgetState>{})!;
        expect(_contrast(fg, bg), greaterThanOrEqualTo(4.5));
        if (!dark) {
          final appBar = theme.appBarTheme;
          expect(
            _contrast(appBar.foregroundColor!, appBar.backgroundColor!),
            greaterThanOrEqualTo(4.5),
          );
        }
      });
    }

    test('dark theme keeps the bright brand orange as primary', () {
      expect(AppThemes.darkTheme.colorScheme.primary, AppColors.brandOrange);
      expect(
        _contrast(AppColors.onBrandOrange, AppColors.brandOrange),
        greaterThanOrEqualTo(4.5),
      );
    });

    testWidgets('dark FilledButton label is legible on its fill', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemes.darkTheme,
          home: Scaffold(
            body: Center(
              child: FilledButton(onPressed: () {}, child: const Text('Go')),
            ),
          ),
        ),
      );
      // Default FilledButton = primary fill + onPrimary label.
      final scheme = AppThemes.darkTheme.colorScheme;
      expect(
        _contrast(scheme.onPrimary, scheme.primary),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('light gradients behind white text stay >= 4.5:1 at every stop', () {
      for (final c in AppColors.brandGradientBehindWhiteText) {
        expect(_contrast(white, c), greaterThanOrEqualTo(4.5));
      }
    });
  });

  group('muted grey text (item 3)', () {
    test('documents the violation: 0xFF8E8E93 on white is < 4.5:1', () {
      expect(_contrast(const Color(0xFF8E8E93), white), lessThan(3.5));
      for (final e in lightSurfaces.entries) {
        expect(
          _contrast(const Color(0xFF8E8E93), e.value),
          lessThan(4.5),
          reason: e.key,
        );
      }
    });

    test('mutedText >= 4.5:1 on white and every light card / field fill', () {
      for (final e in lightSurfaces.entries) {
        expect(
          _contrast(AppColors.mutedText, e.value),
          greaterThanOrEqualTo(4.5),
          reason: e.key,
        );
      }
    });

    test('mutedTextOnDark >= 4.5:1 on every dark surface', () {
      for (final e in darkSurfaces.entries) {
        expect(
          _contrast(AppColors.mutedTextOnDark, e.value),
          greaterThanOrEqualTo(4.5),
          reason: e.key,
        );
      }
    });

    test('dark translucent-white muted variants used in the app >= 4.5:1', () {
      for (final alpha in <double>[0.54, 0.6, 0.7]) {
        for (final e in darkSurfaces.entries) {
          final fg = _over(Colors.white, e.value, alpha);
          expect(
            _contrast(fg, e.value),
            greaterThanOrEqualTo(4.5),
            reason: 'white@$alpha on ${e.key}',
          );
        }
      }
    });

    test('mutedTextFor picks the right variant per brightness', () {
      expect(AppColors.mutedTextFor(Brightness.light), AppColors.mutedText);
      expect(
        AppColors.mutedTextFor(Brightness.dark),
        AppColors.mutedTextOnDark,
      );
    });

    test('theme secondary ink (onSurfaceVariant) passes on both themes', () {
      final l = AppThemes.lightTheme.colorScheme;
      final d = AppThemes.darkTheme.colorScheme;
      for (final e in lightSurfaces.entries) {
        expect(
          _contrast(l.onSurfaceVariant, e.value),
          greaterThanOrEqualTo(4.5),
          reason: e.key,
        );
      }
      for (final e in darkSurfaces.entries) {
        expect(
          _contrast(d.onSurfaceVariant, e.value),
          greaterThanOrEqualTo(4.5),
          reason: e.key,
        );
      }
    });

    test('source guard: 0xFF8E8E93 only lives in the dark token', () {
      final offenders = <String>[];
      for (final f
          in Directory('lib')
              .listSync(recursive: true)
              .whereType<File>()
              .where((f) => f.path.endsWith('.dart'))) {
        final p = f.path.replaceAll('\\', '/');
        if (p.endsWith('theme/app_colors.dart')) continue; // dark token
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final l = lines[i];
          if (!l.contains('8E8E93')) continue;
          if (l.trimLeft().startsWith('//')) continue;
          offenders.add('$p:${i + 1}');
        }
      }
      expect(offenders, isEmpty);
    });
  });

  group('strong orange text on light greys (item 4)', () {
    test('documents the violation: old C24E00 was < 4.5:1 on F4F4F4', () {
      expect(
        _contrast(const Color(0xFFC24E00), const Color(0xFFF4F4F4)),
        lessThan(4.5),
      );
    });

    test('brandOrangeStrong >= 4.5:1 on white and every light grey', () {
      expect(
        _contrast(AppColors.brandOrangeStrong, white),
        greaterThanOrEqualTo(4.5),
      );
      for (final e in lightGreys.entries) {
        expect(
          _contrast(AppColors.brandOrangeStrong, e.value),
          greaterThanOrEqualTo(4.5),
          reason: e.key,
        );
      }
    });

    test('white on brandOrangeStrong keeps >= 4.5:1 (fills / buttons)', () {
      expect(
        _contrast(white, AppColors.brandOrangeStrong),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('accent text on orange tints still uses the deeper shade', () {
      final tint = _over(AppColors.brandOrange, white, 0.12);
      expect(
        _contrast(AppColors.brandOrangeDeep, tint),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        _contrast(AppColors.brandOrangeDeep, const Color(0xFFF4F4F4)),
        greaterThanOrEqualTo(4.5),
      );
    });

    test('strong orange stays recognisably orange and ordered by depth', () {
      final s = AppColors.brandOrangeStrong;
      expect(s.r, greaterThan(0.7));
      expect(s.g, inInclusiveRange(0.25, 0.35));
      expect(s.b, lessThan(0.05));
      expect(
        AppColors.brandOrangeDeep.computeLuminance(),
        lessThan(s.computeLuminance()),
      );
      expect(
        s.computeLuminance(),
        lessThan(AppColors.brandOrangeIcon.computeLuminance()),
      );
    });

    test(
      'dark theme: accent text (bright orange) on dark surfaces >= 4.5:1',
      () {
        for (final e in darkSurfaces.entries) {
          expect(
            _contrast(AppColors.brandOrange, e.value),
            greaterThanOrEqualTo(4.5),
            reason: e.key,
          );
        }
      },
    );
  });
}
