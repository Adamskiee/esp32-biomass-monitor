import 'package:biomass_iot_app/core/storage/app_database.dart';
import 'package:biomass_iot_app/features/safety/audit_log.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AuditLogStore {
  AuditLogStore(this._database);

  final AppDatabase _database;

  Future<int> insertAuditLog(AuditLog log) async {
    if (kIsWeb) return 0;
    return (await _database.database).insert('audit_logs', {
      'action': log.action,
      'user': log.user,
      'timestamp': log.timestamp,
    });
  }

  Future<List<AuditLog>> getAuditLogs() async {
    if (kIsWeb) return [];
    final rows = await (await _database.database).query(
      'audit_logs',
      orderBy: 'id DESC',
    );
    return rows
        .map(
          (row) => AuditLog(
            row['action']! as String,
            row['user']! as String,
            row['timestamp']! as String,
          ),
        )
        .toList();
  }
}
