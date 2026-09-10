import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base local del modo repartidor (`reparto.db`). Es 100% de la app (no la
/// pisa ninguna sync de catálogo): `hoja_ruta` / `parada` / `parada_renglon`
/// se reemplazan enteras en cada `fetchHojas`, y `entrega_outbox` sobrevive
/// como cola de idempotencia (mismo criterio que `movil_sync.db`).
class RepartoDatabaseHelper {
  RepartoDatabaseHelper._();
  static final RepartoDatabaseHelper instance = RepartoDatabaseHelper._();

  static const _dbName = 'reparto.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get db async => _db ??= await _open();

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    return openDatabase(
      p.join(dir.path, _dbName),
      version: _dbVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE hoja_ruta (
            id INTEGER PRIMARY KEY,
            fecha TEXT,
            estado TEXT,
            deposito TEXT,
            distancia_m INTEGER,
            duracion_s INTEGER,
            notas TEXT,
            recorrido_json TEXT,
            updated_at TEXT
          )''');
        await db.execute('''
          CREATE TABLE parada (
            id INTEGER PRIMARY KEY,
            hoja_id INTEGER NOT NULL,
            orden INTEGER,
            estado TEXT,
            remito_id INTEGER,
            cliente TEXT,
            telefono TEXT,
            direccion TEXT,
            lat REAL,
            lng REAL,
            ventana_desde TEXT,
            ventana_hasta TEXT,
            instrucciones TEXT
          )''');
        await db.execute('''
          CREATE TABLE parada_renglon (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            parada_id INTEGER NOT NULL,
            stock_movement_id INTEGER,
            articulo TEXT,
            sku TEXT,
            cantidad REAL,
            entregado REAL
          )''');
        await db.execute('''
          CREATE TABLE entrega_outbox (
            uuid TEXT PRIMARY KEY,
            parada_id INTEGER NOT NULL,
            payload_json TEXT NOT NULL,
            estado TEXT NOT NULL DEFAULT 'pendiente',
            error TEXT,
            prueba_id INTEGER,
            created_at TEXT NOT NULL
          )''');
      },
    );
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// UUID v4 — mismo criterio que ApiSyncProvider (sin dependencia externa).
  static String uuidV4() {
    final rnd = Random.secure();
    final b = List<int>.generate(16, (_) => rnd.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    String hex(int s, int e) =>
        [for (var i = s; i < e; i++) b[i].toRadixString(16).padLeft(2, '0')].join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
