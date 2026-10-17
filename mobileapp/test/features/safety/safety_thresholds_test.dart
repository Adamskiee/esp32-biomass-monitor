import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('distinguishes supported null limits from absent firmware fields', () {
    final thresholds = SafetyThresholds.fromJson({
      'threshold_temperature_c': null,
    });

    expect(thresholds.supports('threshold_temperature_c'), isTrue);
    expect(thresholds.value('threshold_temperature_c'), isNull);
    expect(thresholds.supports('threshold_pm2_5_ug_m3'), isFalse);
    expect(thresholds.value('threshold_pm2_5_ug_m3'), isNull);
  });
  test('non-finite saved settings remain unavailable', () {
    final thresholds = SafetyThresholds.fromJson({
      'threshold_mq2_v': double.infinity,
    });
    expect(thresholds.supports('threshold_mq2_v'), isTrue);
    expect(thresholds.value('threshold_mq2_v'), isNull);
  });
}
