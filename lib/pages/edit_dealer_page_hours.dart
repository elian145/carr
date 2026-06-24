part of 'edit_dealer_page.dart';

mixin _EditDealerPageHours on _EditDealerPageStyle {
  String _daySummaryText(String dayKey) {
    final day = _openingHours[dayKey]!;
    if (!day.enabled) return _tr('Closed', ar: 'مغلق', ku: 'داخراوە');
    if (day.is24h) return _tr('24 hours', ar: '24 ساعة', ku: '24 کاتژمێر');
    if (day.open != null && day.close != null) {
      return _formatRange(day.open!, day.close!);
    }
    final legacy = (day.legacyText ?? '').trim();
    if (legacy.isNotEmpty) return legacy;
    if (day.open != null && day.close == null) {
      return '${_tr('From', ar: 'من', ku: 'لە')} ${_formatTime(day.open!)}';
    }
    if (day.open == null && day.close != null) {
      return '${_tr('To', ar: 'إلى', ku: 'بۆ')} ${_formatTime(day.close!)}';
    }
    return _tr('Select time', ar: 'اختر الوقت', ku: 'کات هەڵبژێرە');
  }

  void _openOpeningHoursDayEditor(String dayKey) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openingHoursTileControllers[dayKey]?.expand();
      final ctx = _openingHoursTileKeys[dayKey]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          alignment: 0.15,
        );
      }
    });
  }

  _DayHours _parseDayHours(String raw) {
    final s = raw.trim();
    if (s.isEmpty) {
      return _DayHours(enabled: false, is24h: false);
    }
    final lower = s.toLowerCase();
    if (lower.contains('24') && lower.contains('hour')) {
      return _DayHours(enabled: true, is24h: true);
    }
    if (lower == 'closed' || lower == 'close') {
      return _DayHours(enabled: false, is24h: false);
    }

    TimeOfDay? parseOne(String t) {
      final m = RegExp(
        r'^\s*(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*$',
        caseSensitive: false,
      ).firstMatch(t);
      if (m == null) return null;
      var h = int.tryParse(m.group(1) ?? '');
      final min = int.tryParse(m.group(2) ?? '0') ?? 0;
      final ap = (m.group(3) ?? '').toLowerCase();
      if (h == null) return null;
      if (min < 0 || min > 59) return null;
      if (ap.isNotEmpty) {
        if (h < 1 || h > 12) return null;
        if (ap == 'am') {
          h = h == 12 ? 0 : h;
        } else if (ap == 'pm') {
          h = h == 12 ? 12 : h + 12;
        }
      } else {
        if (h < 0 || h > 23) return null;
      }
      return TimeOfDay(hour: h, minute: min);
    }

    // Try to parse "start - end"
    final parts = s.split(RegExp(r'\s*-\s*'));
    if (parts.length >= 2) {
      final a = parseOne(parts[0]);
      final b = parseOne(parts[1]);
      if (a != null && b != null) {
        return _DayHours(enabled: true, is24h: false, open: a, close: b);
      }
    }

    // Fall back to legacy string (still saved as-is unless user edits).
    return _DayHours(enabled: true, is24h: false, legacyText: s);
  }

  String _formatTime(TimeOfDay t) => t.format(context);

  String _formatRange(TimeOfDay open, TimeOfDay close) =>
      '${_formatTime(open)} - ${_formatTime(close)}';

  List<TimeOfDay> _timeOptions() {
    final out = <TimeOfDay>[];
    for (var h = 0; h < 24; h++) {
      out.add(TimeOfDay(hour: h, minute: 0));
      out.add(TimeOfDay(hour: h, minute: 30));
    }
    return out;
  }

  Future<TimeOfDay?> _pickTimeWheel({
    required String title,
    TimeOfDay? initial,
  }) async {
    final options = _timeOptions();
    int indexOf(TimeOfDay t) {
      final i = options.indexWhere((x) => x.hour == t.hour && x.minute == t.minute);
      return i >= 0 ? i : 0;
    }

    final initialIdx = initial != null ? indexOf(initial) : 0;
    int selectedIndex = initialIdx;

    return await showModalBottomSheet<TimeOfDay>(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      builder: (ctx) {
        final controller = FixedExtentScrollController(initialItem: initialIdx);
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(ctx)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(_loc?.cancelAction ?? 'Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, options[selectedIndex]),
                        child: Text(_tr('Done', ar: 'تم', ku: 'تەواو')),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) => selectedIndex = i,
                    children: [
                      for (final t in options)
                        Center(
                          child: Text(
                            t.format(ctx),
                            style: Theme.of(ctx).textTheme.titleMedium,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
