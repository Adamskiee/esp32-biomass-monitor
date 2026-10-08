import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/experiments/attempt.dart';
import 'package:biomass_iot_app/features/experiments/attempt_comparison_service.dart';
import 'package:biomass_iot_app/features/experiments/attempt_controller.dart';
import 'package:biomass_iot_app/features/experiments/attempt_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/telemetry_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeTelemetry extends ChangeNotifier implements TelemetrySource {
  @override
  bool isHardwareConnected = false;
  @override
  int telemetryRevision = 0;
  @override
  SensorData currentData = SensorData(timestamp: DateTime.now());
  void emit({bool connected = true}) {
    isHardwareConnected = connected;
    telemetryRevision++;
    notifyListeners();
  }
}

void main() {
  late Directory directory;
  late AppDatabase database;
  late FakeTelemetry source;
  late AttemptController controller;
  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('attempt-controller-');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/db.sqlite',
    );
    source = FakeTelemetry();
    controller = AttemptController(
      source,
      AttemptStore(database),
      const AttemptComparisonService(),
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await database.close();
    await directory.delete(recursive: true);
  });
  test(
    'rejects offline start and records each connected telemetry revision once',
    () async {
      await controller.start(AttemptScenario.withoutFiltration);
      expect(controller.activeAttempt, isNull);
      source.isHardwareConnected = true;
      await controller.start(AttemptScenario.withoutFiltration);
      expect(controller.activeAttempt, isNotNull);
      source.currentData = SensorData(mq2V: 1, timestamp: DateTime.now());
      source.emit();
      await Future<void>.delayed(Duration.zero);
      source.notifyListeners();
      await Future<void>.delayed(Duration.zero);
      expect(
        (await AttemptStore(
          database,
        ).listReadings(controller.activeAttempt!.id)),
        hasLength(1),
      );
      await controller.stop();
      expect(
        (await AttemptStore(database).listAttempts()).single.status,
        AttemptStatus.completed,
      );
    },
  );
  test('interrupts an active attempt when the source disconnects', () async {
    source.isHardwareConnected = true;
    await controller.start(AttemptScenario.withFiltration);
    source.emit(connected: false);
    await Future<void>.delayed(Duration.zero);
    expect(
      (await AttemptStore(database).listAttempts()).single.status,
      AttemptStatus.interrupted,
    );
  });
}
