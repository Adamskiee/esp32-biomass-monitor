import 'dart:async';
import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_history_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_log_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FailingSensorHistoryReader implements SensorHistoryReader {
  @override
  Future<int> getLatestSensorDataId() async => throw StateError('unavailable');

  @override
  Future<int> getSensorDataCount({int? throughId}) async =>
      throw StateError('unavailable');

  @override
  Future<List<SensorData>> getSensorData({
    int limit = 100,
    int offset = 0,
    int? throughId,
  }) async => throw StateError('unavailable');
}

class _ControllableSensorHistoryReader implements SensorHistoryReader {
  _ControllableSensorHistoryReader(this.records);

  final List<SensorData> records;
  Completer<int>? pendingLatestId;
  Completer<int>? pendingCount;
  Completer<void>? countStarted;
  Completer<List<SensorData>>? pendingPage;

  @override
  Future<int> getLatestSensorDataId() {
    final pending = pendingLatestId;
    pendingLatestId = null;
    return pending?.future ?? Future.value(records.length);
  }

  @override
  Future<int> getSensorDataCount({int? throughId}) {
    countStarted?.complete();
    countStarted = null;
    final pending = pendingCount;
    pendingCount = null;
    if (pending != null) return pending.future;
    final cutoff = throughId ?? records.length;
    return Future.value(cutoff < records.length ? cutoff : records.length);
  }

  @override
  Future<List<SensorData>> getSensorData({
    int limit = 100,
    int offset = 0,
    int? throughId,
  }) {
    final pending = pendingPage;
    pendingPage = null;
    if (pending != null) return pending.future;
    final cutoff = throughId ?? records.length;
    return Future.value(
      records.take(cutoff).toList().reversed.skip(offset).take(limit).toList(),
    );
  }
}

void main() {
  late Directory temporaryDirectory;
  late AppDatabase database;
  late SensorHistoryStore history;
  late SensorLogController controller;
  final start = DateTime.utc(2026, 10, 7, 12);

  setUpAll(sqfliteFfiInit);

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('sensor-log-');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${temporaryDirectory.path}/biomass_iot.db',
    );
    history = SensorHistoryStore(database);
    for (var index = 0; index < 25; index++) {
      await history.insertSensorData(
        SensorData(
          temperatureC: index.toDouble(),
          timestamp: start.add(Duration(minutes: index)),
        ),
      );
    }
    controller = SensorLogController(history);
  });

  tearDown(() async {
    controller.dispose();
    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });

  test('loads ten records and navigates through the snapshot', () async {
    await controller.loadInitialPage();

    expect(controller.currentPage, 1);
    expect(controller.pageCount, 3);
    expect(controller.records, hasLength(10));
    expect(controller.records.first.temperatureC, 24);

    await controller.nextPage();

    expect(controller.currentPage, 2);
    expect(controller.records, hasLength(10));
    expect(controller.records.first.temperatureC, 14);
    expect(controller.records.last.temperatureC, 5);

    await controller.previousPage();

    expect(controller.currentPage, 1);
    expect(controller.records.first.temperatureC, 24);
  });

  test('keeps updates out of the log until a manual refresh', () async {
    await controller.loadInitialPage();
    await history.insertSensorData(
      SensorData(
        temperatureC: 99,
        timestamp: start.add(const Duration(days: 1)),
      ),
    );

    await controller.onTelemetryRevision();

    expect(controller.liveUpdates, isFalse);
    expect(controller.records.first.temperatureC, 24);

    await controller.refresh();

    expect(controller.records.first.temperatureC, 99);
  });

  test('updates page one live without disrupting an older page', () async {
    await controller.loadInitialPage();
    await controller.setLiveUpdates(true);
    await history.insertSensorData(
      SensorData(
        temperatureC: 99,
        timestamp: start.add(const Duration(days: 1)),
      ),
    );

    await controller.onTelemetryRevision();

    expect(controller.records.first.temperatureC, 99);
    await controller.nextPage();
    expect(controller.records.first.temperatureC, 15);

    await history.insertSensorData(
      SensorData(
        temperatureC: 100,
        timestamp: start.add(const Duration(days: 2)),
      ),
    );
    await controller.onTelemetryRevision();

    expect(controller.currentPage, 2);
    expect(controller.records.first.temperatureC, 15);
    expect(controller.hasNewRecords, isTrue);

    await controller.showNewRecords();

    expect(controller.currentPage, 1);
    expect(controller.records.first.temperatureC, 100);
    expect(controller.hasNewRecords, isFalse);
  });

  test('exposes sensor history load failures for retry', () async {
    final failingController = SensorLogController(
      _FailingSensorHistoryReader(),
    );
    addTearDown(failingController.dispose);

    await failingController.loadInitialPage();

    expect(failingController.isLoading, isFalse);
    expect(
      failingController.errorMessage,
      'Unable to load sensor data. Try again.',
    );
    expect(failingController.records, isEmpty);
  });

  test('coalesces a live update that arrives during a page refresh', () async {
    final reader = _ControllableSensorHistoryReader([
      SensorData(temperatureC: 1, timestamp: start),
    ]);
    final liveController = SensorLogController(reader);
    addTearDown(liveController.dispose);
    await liveController.loadInitialPage();
    await liveController.setLiveUpdates(true);
    final pendingLatestId = Completer<int>();
    reader.pendingLatestId = pendingLatestId;

    final activeRefresh = liveController.onTelemetryRevision();
    reader.records.add(
      SensorData(
        temperatureC: 2,
        timestamp: start.add(const Duration(minutes: 1)),
      ),
    );
    final queuedRefresh = liveController.onTelemetryRevision();
    pendingLatestId.complete(1);
    await Future.wait([activeRefresh, queuedRefresh]);

    expect(liveController.records.first.temperatureC, 2);
  });

  test('does not change pages while another page is loading', () async {
    final reader = _ControllableSensorHistoryReader(
      List.generate(
        30,
        (index) => SensorData(
          temperatureC: index.toDouble(),
          timestamp: start.add(Duration(minutes: index)),
        ),
      ),
    );
    final busyController = SensorLogController(reader);
    addTearDown(busyController.dispose);
    await busyController.loadInitialPage();
    await busyController.setLiveUpdates(true);
    await busyController.nextPage();
    await busyController.nextPage();
    reader.records.add(
      SensorData(
        temperatureC: 30,
        timestamp: start.add(const Duration(minutes: 30)),
      ),
    );
    await busyController.onTelemetryRevision();
    final pendingPage = Completer<List<SensorData>>();
    reader.pendingPage = pendingPage;

    final navigation = busyController.previousPage();
    await busyController.showNewRecords();
    pendingPage.complete(reader.records.reversed.skip(10).take(10).toList());
    await navigation;

    expect(busyController.currentPage, 2);
    expect(busyController.records.first.temperatureC, 20);
    expect(busyController.hasNewRecords, isTrue);
  });

  test('does not publish a pending load after disposal', () async {
    final reader = _ControllableSensorHistoryReader([]);
    final pendingLatestId = Completer<int>();
    reader.pendingLatestId = pendingLatestId;
    final disposableController = SensorLogController(reader);

    final load = disposableController.loadInitialPage();
    disposableController.dispose();
    pendingLatestId.complete(0);

    await expectLater(load, completes);
  });

  test(
    'keeps a new-record notice raised during an older-page refresh',
    () async {
      final reader = _ControllableSensorHistoryReader(
        List.generate(
          25,
          (index) => SensorData(
            temperatureC: index.toDouble(),
            timestamp: start.add(Duration(minutes: index)),
          ),
        ),
      );
      final refreshingController = SensorLogController(reader);
      addTearDown(refreshingController.dispose);
      await refreshingController.loadInitialPage();
      await refreshingController.setLiveUpdates(true);
      await refreshingController.nextPage();
      final countStarted = Completer<void>();
      final pendingCount = Completer<int>();
      reader.countStarted = countStarted;
      reader.pendingCount = pendingCount;

      final refresh = refreshingController.refresh();
      await countStarted.future;
      reader.records.add(
        SensorData(
          temperatureC: 25,
          timestamp: start.add(const Duration(minutes: 25)),
        ),
      );
      await refreshingController.onTelemetryRevision();
      pendingCount.complete(25);
      await refresh;

      expect(refreshingController.hasNewRecords, isTrue);
    },
  );
}
