import 'package:biomass_iot_app/features/safety/safety_threshold_editor.dart';
import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const humidityMin = 'threshold_humidity_min_percent';
  const humidityMax = 'threshold_humidity_max_percent';

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

  test('refresh preserves a draft and updates its saved humidity partner', () {
    final editor = SafetyThresholdEditor()
      ..refresh(SafetyThresholds.fromJson({humidityMin: 30, humidityMax: 70}))
      ..edit(humidityMin, '35')
      ..refresh(SafetyThresholds.fromJson({humidityMin: 30, humidityMax: 34}));

    expect(editor.textFor(humidityMin), '35');
    expect(editor.saved.value(humidityMax), 34);
    expect(editor.validate(), contains('humidity'));
  });

  test('confirmation replaces visible values and clears drafts', () {
    final editor = SafetyThresholdEditor()
      ..refresh(SafetyThresholds.fromJson({humidityMin: 30, humidityMax: 70}))
      ..edit(humidityMin, '35')
      ..confirm(SafetyThresholds.fromJson({humidityMin: 35, humidityMax: 75}));

    expect(editor.hasDraft(humidityMin), isFalse);
    expect(editor.hasDraft(humidityMax), isFalse);
    expect(editor.textFor(humidityMin), '35');
    expect(editor.textFor(humidityMax), '75');
  });

  test(
    'normalizes equivalent numeric drafts and omits untouched null values',
    () {
      final editor = SafetyThresholdEditor()
        ..refresh(
          SafetyThresholds.fromJson({
            'threshold_temperature_c': 35,
            'threshold_pm2_5_ug_m3': null,
          }),
        )
        ..edit('threshold_temperature_c', '35.0');

      expect(editor.changedValues(), isEmpty);
      expect(editor.isDirty, isFalse);
    },
  );

  test('rejects clearing a configured limit', () {
    final editor = SafetyThresholdEditor()
      ..refresh(SafetyThresholds.fromJson({'threshold_temperature_c': 35}))
      ..edit('threshold_temperature_c', '');

    expect(editor.validate()['threshold_temperature_c'], isNotNull);
    expect(editor.changedValues(), isEmpty);
  });

  test('requires a complete and ordered humidity pair', () {
    final firstHalf = SafetyThresholdEditor()
      ..refresh(
        SafetyThresholds.fromJson({humidityMin: null, humidityMax: null}),
      )
      ..edit(humidityMin, '30');
    final reversed = SafetyThresholdEditor()
      ..refresh(SafetyThresholds.fromJson({humidityMin: 30, humidityMax: 70}))
      ..edit(humidityMin, '70');

    expect(firstHalf.validate(), contains('humidity'));
    expect(reversed.validate(), contains('humidity'));
  });

  test('accepts finite range endpoints', () {
    final editor = SafetyThresholdEditor()
      ..refresh(
        SafetyThresholds.fromJson({
          'threshold_chamber_temp_c': 20,
          'threshold_mq2_v': 0.1,
          'threshold_mq135_v': 5,
          'threshold_temperature_c': -40,
          'threshold_pm1_0_ug_m3': 65535,
          humidityMin: 0,
          humidityMax: 100,
        }),
      )
      ..edit('threshold_chamber_temp_c', '150')
      ..edit('threshold_temperature_c', '80');

    expect(editor.validate(), isEmpty);
  });

  test('allows an unrelated edit with a legacy MQ-2 saved value', () {
    final editor = SafetyThresholdEditor()
      ..refresh(
        SafetyThresholds.fromJson({
          'threshold_mq2_v': 5.0,
          'threshold_temperature_c': 35,
        }),
      )
      ..edit('threshold_temperature_c', '40');

    expect(editor.validate(), isEmpty);
    expect(editor.changedValues(), {'threshold_temperature_c': 40.0});
  });
  test(
    'an equivalent legacy MQ-2 draft does not invalidate an ambient edit',
    () {
      final editor = SafetyThresholdEditor()
        ..refresh(
          SafetyThresholds.fromJson({
            'threshold_mq2_v': 5,
            'threshold_temperature_c': 30,
          }),
        )
        ..edit('threshold_mq2_v', '5.0')
        ..edit('threshold_temperature_c', '40');
      expect(editor.validate(), isEmpty);
      expect(editor.changedValues(), {'threshold_temperature_c': 40});
    },
  );

  test('never includes unsupported field drafts in a payload', () {
    final editor = SafetyThresholdEditor()
      ..refresh(SafetyThresholds.fromJson({'threshold_temperature_c': 35}))
      ..edit('threshold_not_in_firmware', '12');

    expect(editor.changedValues(), isEmpty);
  });

  for (final entry in <String, List<String>>{
    'threshold_chamber_temp_c': ['19', '151', 'NaN', 'Infinity', ''],
    'threshold_mq2_v': ['0', '4.9'],
    'threshold_mq135_v': ['0', '5.1'],
    'threshold_temperature_c': ['-41', '81'],
    'threshold_pm1_0_ug_m3': ['0', '65536'],
    'threshold_pm2_5_ug_m3': ['-1', '65536'],
    'threshold_pm10_ug_m3': ['0', '65536'],
    humidityMin: ['-1', '101', '70', '71'],
    humidityMax: ['-1', '101', '30', '29'],
  }.entries) {
    for (final value in entry.value) {
      test('rejects ${entry.key} value $value before payload generation', () {
        final editor = SafetyThresholdEditor()
          ..refresh(
            SafetyThresholds.fromJson({
              entry.key: null,
              humidityMin: 30,
              humidityMax: 70,
            }),
          )
          ..edit(entry.key, value);
        expect(editor.validate(), isNotEmpty);
        expect(editor.changedValues(), isEmpty);
      });
    }
  }
}
