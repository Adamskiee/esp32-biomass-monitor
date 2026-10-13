import 'package:biomass_iot_app/features/alerts/alerts_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reserves space above the mobile navigation bar', () {
    expect(alertListBottomInset(width: 450, safeAreaBottom: 24), 160);
  });

  test('uses a normal inset beside desktop navigation', () {
    expect(alertListBottomInset(width: 900, safeAreaBottom: 24), 32);
  });
}
