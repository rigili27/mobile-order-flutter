import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../app_mode.dart';

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

  /// Nombre del archivo de la base activa según el modo (WiFi: `moviles.db`,
  /// API: `moviles_api.db`). Las dos conviven en el mismo directorio.
  String get _baseName => AppMode.dbBaseName;

  Future<String> get dbPath async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, _baseName);
  }

  /// Cierra la base actual y la reabre según el modo vigente. Se llama al
  /// cambiar de modo (configurar / borrar el servidor API).
  Future<DbInitResult> switchMode() async {
    await close();
    return init();
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
    final dir = (await getApplicationDocumentsDirectory()).path;
    // Solo los archivos del modo vigente — la base del otro modo no se toca.
    final names = AppMode.isApi
        ? ['moviles_api.db', 'backup_moviles_api.db', 'temp_moviles_api.db', 'export_moviles_api.db']
        : ['moviles.db', 'backup_moviles.db', 'temp.db', 'export.db'];
    for (final name in names) {
      final f = File(join(dir, name));
      if (await f.exists()) await f.delete();
    }
  }
}
