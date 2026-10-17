import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';

class AlertPage {
  const AlertPage({required this.alerts, required this.nextCursor});

  final List<AlertItem> alerts;
  final int? nextCursor;
}

class AlertsStore {
  AlertsStore(this._database);

  final AppDatabase _database;

  Future<int> insertAlert(AlertItem alert) async {
    if (kIsWeb) return 0;
    return (await _database.database).insert('alerts', {
      'id': alert.id,
      'title': alert.title,
      'description': alert.description,
      'severity': alert.severity,
      'time': alert.timestamp?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<bool> recordActivation(String key, AlertItem alert) async {
    if (kIsWeb) return true;
    final database = await _database.database;
    return database.transaction((transaction) async {
      final states = await transaction.query(
        'alert_states',
        where: 'key = ? AND active = ?',
        whereArgs: [key, 1],
        limit: 1,
      );
      if (states.isNotEmpty) return false;
      await transaction.insert('alerts', {
        'id': alert.id,
        'title': alert.title,
        'description': alert.description,
        'severity': alert.severity,
        'time': alert.timestamp?.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.insert('alert_states', {
        'key': key,
        'active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      return true;
    });
  }

  Future<void> migrateLegacyGasHazard() async {
    if (kIsWeb) return;
    final database = await _database.database;
    await database.transaction((transaction) async {
      final legacy = await transaction.query(
        'alert_states',
        where: 'key = ? AND active = ?',
        whereArgs: ['gas_hazard', 1],
        limit: 1,
      );
      if (legacy.isEmpty) return;
      await transaction.insert('alert_states', {
        'key': 'trigger:high_mq2_gas',
        'active': 1,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await transaction.insert('alert_states', {
        'key': 'gas_hazard',
        'active': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> recordRecovery(String key, AlertItem alert) async {
    if (kIsWeb) return;
    final database = await _database.database;
    await database.transaction((transaction) async {
      await transaction.insert('alerts', {
        'id': alert.id,
        'title': alert.title,
        'description': alert.description,
        'severity': alert.severity,
        'time': alert.timestamp?.toIso8601String(),
      });
      await transaction.insert('alert_states', {
        'key': key,
        'active': 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<AlertItem>> getAlerts({
    int limit = 20,
    int offset = 0,
    String? severity,
    int? throughRowId,
  }) async {
    if (kIsWeb) return [];
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (severity != null) {
      clauses.add('severity = ?');
      arguments.add(severity);
    }
    if (throughRowId != null) {
      clauses.add('rowid <= ?');
      arguments.add(throughRowId);
    }
    final rows = await (await _database.database).query(
      'alerts',
      where: clauses.isEmpty ? null : clauses.join(' AND '),
      whereArgs: arguments.isEmpty ? null : arguments,
      orderBy: 'rowid DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(_alertFromRow).toList();
  }

  Future<int> getLatestAlertRowId() async {
    if (kIsWeb) return 0;
    final rows = await (await _database.database).rawQuery(
      'SELECT COALESCE(MAX(rowid), 0) AS latest_row_id FROM alerts',
    );
    return (rows.single['latest_row_id'] as num).toInt();
  }

  Future<AlertPage> getAlertPage({
    required int throughRowId,
    int? beforeRowId,
    String? severity,
    int limit = 20,
  }) async {
    if (kIsWeb) return const AlertPage(alerts: [], nextCursor: null);
    final clauses = <String>['rowid <= ?'];
    final arguments = <Object?>[throughRowId];
    if (beforeRowId != null) {
      clauses.add('rowid < ?');
      arguments.add(beforeRowId);
    }
    if (severity != null) {
      clauses.add('severity = ?');
      arguments.add(severity);
    }
    arguments.add(limit);
    final rows = await (await _database.database).rawQuery(
      'SELECT rowid AS row_id, id, title, description, severity, time '
      'FROM alerts WHERE ${clauses.join(' AND ')} '
      'ORDER BY rowid DESC LIMIT ?',
      arguments,
    );
    return AlertPage(
      alerts: rows.map(_alertFromRow).toList(),
      nextCursor: rows.isEmpty ? null : (rows.last['row_id'] as num).toInt(),
    );
  }

  Future<int> getAlertCount({String? severity, int? throughRowId}) async {
    if (kIsWeb) return 0;
    final clauses = <String>[];
    final arguments = <Object?>[];
    if (severity != null) {
      clauses.add('severity = ?');
      arguments.add(severity);
    }
    if (throughRowId != null) {
      clauses.add('rowid <= ?');
      arguments.add(throughRowId);
    }
    final rows = await (await _database.database).rawQuery(
      'SELECT COUNT(*) AS alert_count FROM alerts${clauses.isEmpty ? '' : ' WHERE ${clauses.join(' AND ')}'}',
      arguments.isEmpty ? null : arguments,
    );
    return (rows.single['alert_count'] as num).toInt();
  }

  Future<void> deleteAlert(String id) async {
    if (kIsWeb) return;
    await (await _database.database).delete(
      'alerts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearAlerts() async {
    if (kIsWeb) return;
    final database = await _database.database;
    await database.delete('alerts');
    await database.delete('alert_states');
  }

  Future<Set<String>> getActiveAlertStates() async {
    if (kIsWeb) return {};
    final rows = await (await _database.database).query(
      'alert_states',
      where: 'active = ?',
      whereArgs: [1],
    );
    return rows.map((row) => row['key']! as String).toSet();
  }

  Future<void> setAlertState(String key, bool active) async {
    if (kIsWeb) return;
    await (await _database.database).insert('alert_states', {
      'key': key,
      'active': active ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  AlertItem _alertFromRow(Map<String, Object?> row) => AlertItem(
    id: row['id']! as String,
    title: row['title']! as String,
    description: row['description']! as String,
    severity: row['severity']! as String,
    timestamp: DateTime.tryParse(row['time'] as String? ?? ''),
  );
}
