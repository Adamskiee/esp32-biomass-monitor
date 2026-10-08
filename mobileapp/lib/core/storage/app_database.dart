import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_provider.dart';
import 'database_schema.dart';

class AppDatabase implements DatabaseProvider {
  AppDatabase({DatabaseFactory? databaseFactory, String? databasePath})
    : _databaseFactory = databaseFactory ?? _defaultDatabaseFactory,
      _databasePath = databasePath;

  static final DatabaseFactory _defaultDatabaseFactory = databaseFactory;
  final DatabaseFactory _databaseFactory;
  final String? _databasePath;
  Database? _database;

  @override
  Future<Database> get database async {
    if (_database != null) return _database!;
    if (kIsWeb) throw UnsupportedError('SQLite is not supported on the Web');
    _database = await _databaseFactory.openDatabase(
      _databasePath ?? await _defaultPath(),
      options: OpenDatabaseOptions(
        version: DatabaseSchema.version,
        onConfigure: DatabaseSchema.configure,
        onCreate: DatabaseSchema.create,
        onUpgrade: DatabaseSchema.upgrade,
      ),
    );
    return _database!;
  }

  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<String> _defaultPath() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'biomass_iot.db');
  }
}
