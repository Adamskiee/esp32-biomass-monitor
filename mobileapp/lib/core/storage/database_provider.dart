import 'package:sqflite/sqflite.dart';

abstract interface class DatabaseProvider {
  Future<Database> get database;
}
