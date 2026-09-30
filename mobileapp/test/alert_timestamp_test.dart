import 'package:biomass_iot_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 9, 30, 12);

  test('formats recent alerts in minutes', () {
    expect(
      formatAlertTimestamp(now.subtract(const Duration(minutes: 5)), now: now),
      '5 minutes ago',
    );
  });

  test('formats same-day alerts in hours', () {
    expect(
      formatAlertTimestamp(now.subtract(const Duration(hours: 3)), now: now),
      '3 hours ago',
    );
  });

  test('formats alerts under seven days in days', () {
    expect(
      formatAlertTimestamp(now.subtract(const Duration(days: 6)), now: now),
      '6 days ago',
    );
  });

  test('formats alerts seven days or older as dates', () {
    expect(
      formatAlertTimestamp(now.subtract(const Duration(days: 7)), now: now),
      'Sep 23, 2026',
    );
  });
}
