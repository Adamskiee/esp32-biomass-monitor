import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/alerts/alert_item.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';

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

  Future<List<AlertItem>> getAlerts() async {
    if (kIsWeb) return [];
    final rows = await (await _database.database).query('alerts');
    final alerts = rows
        .map(
          (row) => AlertItem(
            id: row['id']! as String,
            title: row['title']! as String,
            description: row['description']! as String,
            severity: row['severity']! as String,
            timestamp: DateTime.tryParse(row['time'] as String? ?? ''),
          ),
        )
        .toList();
    alerts.sort(
      (first, second) => (second.timestamp ?? DateTime(0)).compareTo(
        first.timestamp ?? DateTime(0),
      ),
    );
    return alerts;
  }
}
