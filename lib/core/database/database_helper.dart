import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

enum DbInitState { ok, noFile, error }

class DbInitResult {
  final DbInitState state;
  final String? error;
  const DbInitResult._(this.state, [this.error]);
  static const ok = DbInitResult._(DbInitState.ok);
  static const noFile = DbInitResult._(DbInitState.noFile);
  factory DbInitResult.error(String e) => DbInitResult._(DbInitState.error, e);
}

class DatabaseHelper {
  DatabaseHelper._();
  static final DatabaseHelper instance = DatabaseHelper._();

  Database? _db;

  Database get db {
    if (_db == null) throw StateError('DatabaseHelper no inicializado.');
    return _db!;
  }

  bool get isOpen => _db != null && _db!.isOpen;

  Future<String> get dbPath async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, 'moviles.db');
  }

  Future<DbInitResult> init() async {
    final path = await dbPath;
    if (!await File(path).exists()) {
      return DbInitResult.noFile;
    }
    try {
      _db = await openDatabase(path, readOnly: false);
      // Quick sanity check
      await _db!.rawQuery('SELECT 1 FROM VendMovil LIMIT 1');
      return DbInitResult.ok;
    } catch (e) {
      await _db?.close();
      _db = null;
      return DbInitResult.error(e.toString());
    }
  }

  /// Copia la DB inicial desde assets (solo para reset/primera instalación debug).
  Future<void> copyFromAssets() async {
    final path = await dbPath;
    final bytes = await rootBundle.load('assets/db/moviles.db');
    await File(path).writeAsBytes(bytes.buffer.asUint8List(), flush: true);
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> reopen() async {
    final path = await dbPath;
    _db = await openDatabase(path, readOnly: false);
  }

  Future<bool> validateDatabase(String path) async {
    Database? testDb;
    try {
      testDb = await openDatabase(path, readOnly: true);
      await testDb.rawQuery('SELECT 1 FROM VendMovil LIMIT 1');
      return true;
    } catch (_) {
      return false;
    } finally {
      await testDb?.close();
    }
  }

  Future<void> deleteDatabase() async {
    await close();
    final path = await dbPath;
    final dir = (await getApplicationDocumentsDirectory()).path;
    for (final name in ['moviles.db', 'backup_moviles.db', 'temp.db', 'export.db']) {
      final f = File(join(dir, name));
      if (await f.exists()) await f.delete();
    }
  }
}
