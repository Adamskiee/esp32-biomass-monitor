import 'package:sqflite/sqflite.dart';

import '../../core/storage/database_provider.dart';
import '../monitoring/sensor_data.dart';
import 'attempt.dart';
import 'attempt_reading.dart';

class AttemptStore {
  AttemptStore(this._provider);
  final DatabaseProvider _provider;

  Future<Attempt> startAttempt(
    AttemptScenario scenario,
    DateTime startedAt,
  ) async {
    final database = await _provider.database;
    try {
      return await database.transaction((transaction) async {
        final result = await transaction.rawQuery(
          'SELECT COALESCE(MAX(sequence_number), 0) + 1 AS next FROM attempts WHERE scenario = ?',
          [scenario.storageValue],
        );
        final sequence = result.single['next'] as int;
        final id = await transaction.insert('attempts', {
          'scenario': scenario.storageValue,
          'sequence_number': sequence,
          'started_at': startedAt.toIso8601String(),
          'status': AttemptStatus.active.storageValue,
        });
        return Attempt(
          id: id,
          scenario: scenario,
          sequenceNumber: sequence,
          startedAt: startedAt,
          endedAt: null,
          status: AttemptStatus.active,
          sampleCount: 0,
        );
      });
    } on DatabaseException catch (error) {
      if (error.isUniqueConstraintError()) {
        throw StateError('An attempt is already active');
      }
      rethrow;
    }
  }

  Future<void> addReading(
    int attemptId,
    SensorData data,
    Duration elapsed,
  ) async {
    final database = await _provider.database;
    await database.insert('attempt_readings', {
      'attempt_id': attemptId,
      'recorded_at': data.timestamp.toIso8601String(),
      'elapsed_ms': elapsed.inMilliseconds,
      'temperature_c': data.temperatureC,
      'humidity_percent': data.humidityPercent,
      'mq135_v': data.mq135V,
      'mq2_v': data.mq2V,
      'pm1_ug_m3': data.pm1UgM3,
      'pm25_ug_m3': data.pm25UgM3,
      'pm10_ug_m3': data.pm10UgM3,
    });
  }

  Future<void> finishAttempt(
    int attemptId,
    DateTime endedAt,
    AttemptStatus status,
  ) async {
    await (await _provider.database).update(
      'attempts',
      {'ended_at': endedAt.toIso8601String(), 'status': status.storageValue},
      where: 'id = ?',
      whereArgs: [attemptId],
    );
  }

  Future<List<Attempt>> listAttempts() async {
    final database = await _provider.database;
    final rows = await database.rawQuery(
      'SELECT attempts.*, COUNT(attempt_readings.id) AS sample_count FROM attempts LEFT JOIN attempt_readings ON attempt_readings.attempt_id = attempts.id GROUP BY attempts.id ORDER BY started_at DESC',
    );
    return rows.map(_attempt).toList();
  }

  Future<List<AttemptReading>> listReadings(int attemptId) async {
    final rows = await (await _provider.database).query(
      'attempt_readings',
      where: 'attempt_id = ?',
      whereArgs: [attemptId],
      orderBy: 'elapsed_ms ASC',
    );
    return rows
        .map(
          (row) => AttemptReading(
            attemptId: attemptId,
            recordedAt: DateTime.parse(row['recorded_at']! as String),
            elapsed: Duration(milliseconds: row['elapsed_ms']! as int),
            data: SensorData(
              temperatureC: (row['temperature_c'] as num?)?.toDouble(),
              humidityPercent: (row['humidity_percent'] as num?)?.toDouble(),
              mq135V: (row['mq135_v'] as num?)?.toDouble(),
              mq2V: (row['mq2_v'] as num?)?.toDouble(),
              pm1UgM3: (row['pm1_ug_m3'] as num?)?.toDouble(),
              pm25UgM3: (row['pm25_ug_m3'] as num?)?.toDouble(),
              pm10UgM3: (row['pm10_ug_m3'] as num?)?.toDouble(),
              timestamp: DateTime.parse(row['recorded_at']! as String),
            ),
          ),
        )
        .toList();
  }

  Future<void> recoverActiveAttempt() async {
    final database = await _provider.database;
    final active = await database.query(
      'attempts',
      where: 'status = ?',
      whereArgs: [AttemptStatus.active.storageValue],
    );
    for (final row in active) {
      final id = row['id']! as int;
      final readings = await database.query(
        'attempt_readings',
        where: 'attempt_id = ?',
        whereArgs: [id],
        orderBy: 'recorded_at DESC',
        limit: 1,
      );
      final endedAt = readings.isEmpty
          ? row['started_at']! as String
          : readings.single['recorded_at']! as String;
      await database.update(
        'attempts',
        {'ended_at': endedAt, 'status': AttemptStatus.interrupted.storageValue},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> deleteAttempt(int attemptId) async {
    final database = await _provider.database;
    final rows = await database.query(
      'attempts',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [attemptId],
    );
    if (rows.isNotEmpty &&
        rows.single['status'] == AttemptStatus.active.storageValue) {
      throw StateError('Cannot delete an active attempt');
    }
    await database.delete('attempts', where: 'id = ?', whereArgs: [attemptId]);
  }

  Attempt _attempt(Map<String, Object?> row) => Attempt(
    id: row['id']! as int,
    scenario: AttemptScenarioStorage.parse(row['scenario']! as String),
    sequenceNumber: row['sequence_number']! as int,
    startedAt: DateTime.parse(row['started_at']! as String),
    endedAt: row['ended_at'] == null
        ? null
        : DateTime.parse(row['ended_at']! as String),
    status: AttemptStatusStorage.parse(row['status']! as String),
    sampleCount: row['sample_count']! as int,
  );
}
