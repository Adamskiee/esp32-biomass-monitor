import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/safety/safety_threshold_editor.dart';
import 'package:biomass_iot_app/features/safety/safety_thresholds.dart';
import 'package:biomass_iot_app/features/safety/widgets/safety_threshold_group.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const chamber = 'threshold_chamber_temp_c';
const ambient = 'threshold_temperature_c';
const mq2 = 'threshold_mq2_v';
const mq135 = 'threshold_mq135_v';
const pm1 = 'threshold_pm1_0_ug_m3';
const pm25 = 'threshold_pm2_5_ug_m3';
const pm10 = 'threshold_pm10_ug_m3';
const humidityMin = 'threshold_humidity_min_percent';
const humidityMax = 'threshold_humidity_max_percent';

void main() {
  late SafetyThresholdEditor editor;
  late Map<String, TextEditingController> controllers;
  final reading = SensorData(
    chamberTempC: 65,
    temperatureC: -2,
    mq2V: 1.2,
    mq135V: 0.8,
    pm1_0UgM3: 5,
    pm2_5UgM3: 10,
    pm10UgM3: 15,
    humidityPercent: 55,
    timestamp: DateTime.utc(2026),
  );

  setUp(() {
    editor = SafetyThresholdEditor()
      ..refresh(
        SafetyThresholds.fromJson({
          chamber: 70,
          ambient: 35,
          mq2: 2.5,
          mq135: 2,
          pm1: 50,
          pm25: 60,
          pm10: 70,
          humidityMin: 30,
          humidityMax: 70,
        }),
      );
    controllers = {
      for (final field in [
        chamber,
        ambient,
        mq2,
        mq135,
        pm1,
        pm25,
        pm10,
        humidityMin,
        humidityMax,
      ])
        field: TextEditingController(text: editor.textFor(field)),
    };
  });

  tearDown(() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
  });

  Widget subject({
    required String title,
    required List<String> fields,
    SensorData? data,
    Set<String> triggers = const {},
    bool locked = false,
  }) => MaterialApp(
    home: Scaffold(
      body: SafetyThresholdGroup(
        title: title,
        fields: fields,
        editor: editor,
        controllers: controllers,
        reading: data ?? reading,
        activeTriggers: triggers,
        locked: locked,
        onChanged: editor.edit,
      ),
    ),
  );

  testWidgets('renders all canonical inputs across four groups', (
    tester,
  ) async {
    for (final entry in <String, List<String>>{
      'Temperature': [chamber, ambient],
      'Gas': [mq2, mq135],
      'Particulate Matter': [pm1, pm25, pm10],
      'Humidity': [humidityMin, humidityMax],
    }.entries) {
      await tester.pumpWidget(subject(title: entry.key, fields: entry.value));
      for (final field in entry.value) {
        expect(find.byKey(ValueKey(field)), findsOneWidget);
      }
    }
  });

  testWidgets('shows saved limits, readings, actions, and alert state', (
    tester,
  ) async {
    await tester.pumpWidget(
      subject(
        title: 'Temperature',
        fields: [chamber, ambient],
        triggers: {'high_chamber_temp'},
      ),
    );

    expect(find.text('Current: 65 °C'), findsOneWidget);
    expect(find.text('Current: -2 °C'), findsOneWidget);
    expect(find.text('Saved limit: 70 °C'), findsOneWidget);
    expect(find.text('Alerts + automatic sprinkler'), findsOneWidget);
    expect(find.text('Alerts only'), findsOneWidget);
    expect(find.text('Alert'), findsOneWidget);
  });

  testWidgets('prioritizes sensor fault and warm-up status', (tester) async {
    await tester.pumpWidget(
      subject(
        title: 'Gas',
        fields: [mq2, mq135],
        data: SensorData(
          mq2V: null,
          mq135V: null,
          mqWarmingUp: true,
          mqWarmupRemainingSeconds: 300,
          timestamp: DateTime.utc(2026),
        ),
      ),
    );
    expect(find.text('Warming up: 300 s'), findsNWidgets(2));
    expect(find.text('Sensor fault'), findsNothing);

    await tester.pumpWidget(
      subject(
        title: 'Humidity',
        fields: [humidityMin, humidityMax],
        data: SensorData(timestamp: DateTime.utc(2026)),
      ),
    );
    expect(find.text('Sensor fault'), findsNWidgets(2));
  });

  testWidgets('shows unsupported fields as disabled firmware requirements', (
    tester,
  ) async {
    editor.refresh(SafetyThresholds.fromJson({chamber: 70}));
    await tester.pumpWidget(subject(title: 'Gas', fields: [mq2]));

    expect(find.text('Firmware update required'), findsWidgets);
    expect(
      tester.widget<TextFormField>(find.byKey(const ValueKey(mq2))).enabled,
      isFalse,
    );
  });

  testWidgets('uses signed decimal input for ambient temperature', (
    tester,
  ) async {
    await tester.pumpWidget(subject(title: 'Temperature', fields: [ambient]));

    final editable = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const ValueKey(ambient)),
        matching: find.byType(EditableText),
      ),
    );
    expect(editable.keyboardType.signed, isTrue);
    expect(editable.keyboardType.decimal, isTrue);
  });
}
