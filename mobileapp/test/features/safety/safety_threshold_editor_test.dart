import 'package:biomass_iot_app/features/safety/safety_threshold_editor.dart';
import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the saved humidity maximum when validating an edited minimum', () {
    final editor = SafetyThresholdEditor()
      ..refresh(
        SafetyThresholds.fromJson({
          'threshold_humidity_min_percent': 30.0,
          'threshold_humidity_max_percent': 70.0,
        }),
      )
      ..edit('threshold_humidity_min_percent', '35');

    expect(editor.validate(), isEmpty);
    expect(editor.changedValues(), {'threshold_humidity_min_percent': 35.0});
  });

  test(
    'rejects a newly entered MQ-2 threshold above the valid sensor range',
    () {
      final editor = SafetyThresholdEditor()
        ..refresh(SafetyThresholds.fromJson({'threshold_mq2_v': 5.0}))
        ..edit('threshold_mq2_v', '4.9');

      expect(editor.validate()['threshold_mq2_v'], isNotNull);
    },
  );
}
