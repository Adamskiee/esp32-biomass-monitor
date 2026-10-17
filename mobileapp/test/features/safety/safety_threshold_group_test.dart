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
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, update) => SafetyThresholdGroup(
            title: title,
            fields: fields,
            editor: editor,
            controllers: controllers,
            reading: data ?? reading,
            activeTriggers: triggers,
            locked: locked,
            onChanged: (field, value) =>
                update(() => editor.edit(field, value)),
          ),
        ),
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

  testWidgets('humidity pairing errors appear only beside humidity inputs', (
    tester,
  ) async {
    editor.edit(humidityMin, '75');
    await tester.pumpWidget(subject(title: 'Gas', fields: [mq2]));
    expect(
      find.text('Maximum humidity must exceed minimum humidity.'),
      findsNothing,
    );
    await tester.pumpWidget(
      subject(title: 'Humidity', fields: [humidityMin, humidityMax]),
    );
    expect(
      find.text('Maximum humidity must exceed minimum humidity.'),
      findsNWidgets(2),
    );
  });

  Finder sliderFor(String field) => find.byKey(ValueKey('${field}_slider'));
  String inputText(WidgetTester tester, String field) => tester
      .widget<TextFormField>(find.byKey(ValueKey(field)))
      .controller!
      .text;

  testWidgets('each upper limit offers a slider that writes a valid draft', (
    tester,
  ) async {
    for (final entry in <String, (double, String)>{
      chamber: (85.26, '85.5'),
      ambient: (-10.26, '-10.5'),
      mq2: (1.26, '1.3'),
      mq135: (2.84, '2.8'),
      pm1: (80.4, '80'),
      pm25: (90.6, '91'),
      pm10: (110.1, '110'),
    }.entries) {
      await tester.pumpWidget(subject(title: 'Threshold', fields: [entry.key]));
      final slider = tester.widget<Slider>(sliderFor(entry.key));
      slider.onChanged!(entry.value.$1);
      await tester.pump();
      expect(inputText(tester, entry.key), entry.value.$2);
      expect(
        editor.changedValues(),
        containsPair(entry.key, double.parse(entry.value.$2)),
      );
    }
  });

  testWidgets('exact typing moves the slider without rounding the input', (
    tester,
  ) async {
    await tester.pumpWidget(subject(title: 'Temperature', fields: [ambient]));
    await tester.enterText(find.byKey(const ValueKey(ambient)), '-10.25');
    await tester.pump();
    expect(tester.widget<Slider>(sliderFor(ambient)).value, -10.25);
    expect(inputText(tester, ambient), '-10.25');
    expect(editor.changedValues(), {ambient: -10.25});
    expect(
      tester.widget<Slider>(sliderFor(ambient)).semanticFormatterCallback!(
        -10.25,
      ),
      '-10.25 °C',
    );
  });

  testWidgets(
    'PM range expands for exact entry and stays stable while dragging down',
    (tester) async {
      await tester.pumpWidget(
        subject(title: 'Particulate Matter', fields: [pm25]),
      );
      expect(tester.widget<Slider>(sliderFor(pm25)).max, 500);
      await tester.enterText(find.byKey(const ValueKey(pm25)), '1200.25');
      await tester.pump();
      final expanded = tester.widget<Slider>(sliderFor(pm25));
      expect(expanded.max, greaterThanOrEqualTo(1200.25));
      expect(expanded.value, 1200.25);
      expanded.onChanged!(100);
      await tester.pump();
      expect(tester.widget<Slider>(sliderFor(pm25)).max, expanded.max);
      expect(inputText(tester, pm25), '100');
      await tester.enterText(find.byKey(const ValueKey(pm25)), '65535');
      await tester.pump();
      expect(tester.widget<Slider>(sliderFor(pm25)).max, 65535);
      expect(editor.changedValues(), {pm25: 65535});
    },
  );

  testWidgets('saved PM settings beyond the initial range stay visible', (
    tester,
  ) async {
    editor.refresh(SafetyThresholds.fromJson({pm1: 900}));
    controllers[pm1]!.text = '900';
    await tester.pumpWidget(
      subject(title: 'Particulate Matter', fields: [pm1]),
    );
    final slider = tester.widget<Slider>(sliderFor(pm1));
    expect(slider.max, greaterThanOrEqualTo(900));
    expect(slider.value, 900);
    expect(editor.isDirty, isFalse);
  });

  testWidgets('unset limits remain unset until a slider is used', (
    tester,
  ) async {
    editor.refresh(SafetyThresholds.fromJson({ambient: null}));
    controllers[ambient]!.clear();
    await tester.pumpWidget(subject(title: 'Temperature', fields: [ambient]));
    expect(inputText(tester, ambient), isEmpty);
    expect(editor.isDirty, isFalse);
    expect(editor.changedValues(), isEmpty);
    tester.widget<Slider>(sliderFor(ambient)).onChanged!(-5);
    await tester.pump();
    expect(inputText(tester, ambient), '-5');
    expect(editor.changedValues(), {ambient: -5});
    expect(find.text('Saved limit: Not configured'), findsOneWidget);
  });

  testWidgets('legacy MQ-2 setting stays intact until the slider is edited', (
    tester,
  ) async {
    editor.refresh(SafetyThresholds.fromJson({mq2: 5}));
    controllers[mq2]!.text = '5';
    await tester.pumpWidget(subject(title: 'Gas', fields: [mq2]));
    final slider = tester.widget<Slider>(sliderFor(mq2));
    expect(slider.max, 4.8);
    expect(slider.value, 4.8);
    expect(inputText(tester, mq2), '5');
    expect(editor.isDirty, isFalse);
    slider.onChanged!(4.8);
    await tester.pump();
    expect(editor.changedValues(), {mq2: 4.8});
  });

  testWidgets(
    'invalid text is retained while slider positions remain bounded',
    (tester) async {
      await tester.pumpWidget(
        subject(title: 'Particulate Matter', fields: [pm25]),
      );
      for (final text in ['65536', '-1', 'NaN', 'Infinity', 'bad', '']) {
        await tester.enterText(find.byKey(const ValueKey(pm25)), text);
        await tester.pump();
        final slider = tester.widget<Slider>(sliderFor(pm25));
        expect(slider.value, inInclusiveRange(slider.min, slider.max));
        expect(inputText(tester, pm25), text);
        expect(editor.changedValues(), isEmpty);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets(
    'one humidity range slider synchronizes both bounds and keeps exact typing',
    (tester) async {
      await tester.pumpWidget(
        subject(title: 'Humidity', fields: [humidityMin, humidityMax]),
      );
      expect(find.byType(Slider), findsNothing);
      final range = find.byType(RangeSlider);
      expect(range, findsOneWidget);
      tester.widget<RangeSlider>(range).onChanged!(const RangeValues(30, 81.7));
      await tester.pump();
      expect(inputText(tester, humidityMin), '30');
      expect(inputText(tester, humidityMax), '82');
      expect(editor.changedValues(), {humidityMax: 82});
      await tester.enterText(find.byKey(const ValueKey(humidityMin)), '35.25');
      await tester.pump();
      expect(tester.widget<RangeSlider>(range).values.start, 35.25);
      tester.widget<RangeSlider>(range).onChanged!(
        const RangeValues(35.25, 90.4),
      );
      await tester.pump();
      expect(inputText(tester, humidityMin), '35.25');
      expect(inputText(tester, humidityMax), '90');
    },
  );

  testWidgets(
    'unset humidity pair is configured together only on interaction',
    (tester) async {
      editor.refresh(
        SafetyThresholds.fromJson({humidityMin: null, humidityMax: null}),
      );
      controllers[humidityMin]!.clear();
      controllers[humidityMax]!.clear();
      await tester.pumpWidget(
        subject(title: 'Humidity', fields: [humidityMin, humidityMax]),
      );
      expect(editor.changedValues(), isEmpty);
      expect(inputText(tester, humidityMin), isEmpty);
      expect(inputText(tester, humidityMax), isEmpty);
      tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged!(
        const RangeValues(20.4, 79.6),
      );
      await tester.pump();
      expect(editor.changedValues(), {humidityMin: 20, humidityMax: 80});
      expect(editor.validate(), isEmpty);
    },
  );

  testWidgets(
    'reversed humidity typing stays visible with validation and a renderable slider',
    (tester) async {
      await tester.pumpWidget(
        subject(title: 'Humidity', fields: [humidityMin, humidityMax]),
      );
      await tester.enterText(find.byKey(const ValueKey(humidityMin)), '80');
      await tester.pump();
      final slider = tester.widget<RangeSlider>(find.byType(RangeSlider));
      expect(slider.values.start, lessThanOrEqualTo(slider.values.end));
      expect(slider.labels!.start, '70 %');
      expect(slider.labels!.end, '80 %');
      expect(inputText(tester, humidityMin), '80');
      expect(inputText(tester, humidityMax), '70');
      expect(editor.validate(), contains('humidity'));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'offline and unsupported controls disable sliders as well as typing',
    (tester) async {
      await tester.pumpWidget(
        subject(title: 'Gas', fields: [mq2], locked: true),
      );
      expect(tester.widget<Slider>(sliderFor(mq2)).onChanged, isNull);
      await tester.pumpWidget(
        subject(
          title: 'Humidity',
          fields: [humidityMin, humidityMax],
          locked: true,
        ),
      );
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged,
        isNull,
      );
      editor.refresh(SafetyThresholds.fromJson({humidityMin: 30}));
      await tester.pumpWidget(
        subject(title: 'Humidity', fields: [humidityMin, humidityMax]),
      );
      expect(
        tester.widget<RangeSlider>(find.byType(RangeSlider)).onChanged,
        isNull,
      );
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey(humidityMin)))
            .enabled,
        isTrue,
      );
      await tester.pumpWidget(subject(title: 'Gas', fields: [mq2]));
      expect(tester.widget<Slider>(sliderFor(mq2)).onChanged, isNull);
    },
  );
}
