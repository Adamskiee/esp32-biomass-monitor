import 'dart:io';

import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/experiments/attempt.dart';
import 'package:biomass_iot_app/features/experiments/attempt_store.dart';
import 'package:biomass_iot_app/features/monitoring/sensor_data.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory directory;
  late AppDatabase database;
  late AttemptStore store;
  final startedAt = DateTime.utc(2026, 10, 7, 12);
  final sample = SensorData(temperatureC: 25, mq2V: 1, timestamp: startedAt);

  setUpAll(sqfliteFfiInit);
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('attempt-store-');
    database = AppDatabase(
      databaseFactory: databaseFactoryFfi,
      databasePath: '${directory.path}/app.db',
    );
    store = AttemptStore(database);
  });
  tearDown(() async {
    await database.close();
    await directory.delete(recursive: true);
  });

  test('stores readings and allocates scenario sequence labels', () async {
    final first = await store.startAttempt(
      AttemptScenario.withoutFiltration,
      startedAt,
    );
    await store.addReading(
      first.id,
      sample,
      const Duration(milliseconds: 1500),
    );
    await store.finishAttempt(
      first.id,
      startedAt.add(const Duration(seconds: 2)),
      AttemptStatus.completed,
    );
    final second = await store.startAttempt(
      AttemptScenario.withoutFiltration,
      startedAt.add(const Duration(hours: 1)),
    );
    await store.finishAttempt(
      second.id,
      startedAt.add(const Duration(hours: 1, seconds: 1)),
      AttemptStatus.completed,
    );
    final filtered = await store.startAttempt(
      AttemptScenario.withFiltration,
      startedAt.add(const Duration(hours: 2)),
    );
    await store.finishAttempt(
      filtered.id,
      startedAt.add(const Duration(hours: 2, seconds: 1)),
      AttemptStatus.completed,
    );

    expect(first.label, 'Without filtration #1');
    expect(second.label, 'Without filtration #2');
    expect(filtered.label, 'With filtration #1');
    expect(
      (await store.listReadings(first.id)).single.elapsed,
      const Duration(milliseconds: 1500),
    );
    expect((await store.listAttempts()).map((attempt) => attempt.id), [
      filtered.id,
      second.id,
      first.id,
    ]);
  });

  test(
    'serializes active creation, cascades deletion, and recovers active attempts',
    () async {
      final results = await Future.wait([
        store
            .startAttempt(AttemptScenario.withoutFiltration, startedAt)
            .then<Object>(
              (value) => value.id,
              onError: (Object error) => error,
            ),
        store
            .startAttempt(AttemptScenario.withFiltration, startedAt)
            .then<Object>(
              (value) => value.id,
              onError: (Object error) => error,
            ),
      ]);
      expect(results.whereType<int>(), hasLength(1));
      expect(results.whereType<StateError>(), hasLength(1));
      final activeId = results.whereType<int>().single;
      expect(() => store.deleteAttempt(activeId), throwsStateError);
      await store.addReading(
        activeId,
        SensorData(
          temperatureC: 25,
          mq2V: 1,
          timestamp: startedAt.add(const Duration(seconds: 3)),
        ),
        const Duration(seconds: 3),
      );
      await store.recoverActiveAttempt();
      final recovered = (await store.listAttempts()).single;
      expect(recovered.status, AttemptStatus.interrupted);
      expect(recovered.endedAt, startedAt.add(const Duration(seconds: 3)));
      await store.deleteAttempt(activeId);
      expect(await store.listReadings(activeId), isEmpty);
    },
  );
}
