import 'package:car_listing_app/shared/i18n/opening_hours_time_parse.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseHourTimeToken parses English meridiem markers', () {
    expect(parseHourTimeToken('9:00 AM'), const TimeOfDay(hour: 9, minute: 0));
    expect(parseHourTimeToken('8:30 PM'), const TimeOfDay(hour: 20, minute: 30));
    expect(parseHourTimeToken('12:00 am'), const TimeOfDay(hour: 0, minute: 0));
    expect(parseHourTimeToken('12:00 pm'), const TimeOfDay(hour: 12, minute: 0));
  });

  test('parseHourTimeToken parses Arabic meridiem markers', () {
    expect(parseHourTimeToken('9:00 م'), const TimeOfDay(hour: 21, minute: 0));
    expect(parseHourTimeToken('11:30 ص'), const TimeOfDay(hour: 11, minute: 30));
  });
}
