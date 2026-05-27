import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class OrdenPreparacionDatabaseHelper {
  OrdenPreparacionDatabaseHelper._();
  static final OrdenPreparacionDatabaseHelper instance =
      OrdenPreparacionDatabaseHelper._();

  Database? _db;

  Database get db {
    if (_db == null) throw StateError('OrdenPreparacionDatabaseHelper no inicializado.');
    return _db!;
  }

  bool get isOpen => _db != null && _db!.isOpen;

  Future<String> get dbPath async {
    final dir = await getApplicationDocumentsDirectory();
    return join(dir.path, 'moviles_orden_preparacion.db');
  }

  Future<DbInitResult> init() async {
    final path = await dbPath;
    try {
      _db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS PedCMovil (
              ID INTEGER PRIMARY KEY AUTOINCREMENT,
              CODCLIENTE INTEGER NOT NULL,
              CODVENDEDOR INTEGER NOT NULL,
              FECHA TEXT NOT NULL,
              COMENTARIOS TEXT DEFAULT '',
              NROPEDIDO INTEGER,
              QUIENRECIBIO TEXT DEFAULT '',
              FIRMA BLOB
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS PedDMovil (
              ID INTEGER PRIMARY KEY AUTOINCREMENT,
              IDPEDIDO INTEGER NOT NULL,
              CODARTICULO INTEGER NOT NULL,
              CANTIDAD REAL DEFAULT 0,
              PRECIO REAL DEFAULT 0,
              IMPORTE REAL DEFAULT 0,
              UNIDAD INTEGER,
              PORDTO REAL DEFAULT 0,
              COMENTARIO TEXT DEFAULT '',
              DEPOSITO INTEGER
            )
          ''');
        },
      );
      await _db!.rawQuery('SELECT 1 FROM PedCMovil LIMIT 1');
      return DbInitResult.ok;
    } catch (e) {
      await _db?.close();
      _db = null;
      return DbInitResult.error(e.toString());
    }
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  Future<void> reopen() async {
    final path = await dbPath;
    _db = await openDatabase(path, readOnly: false);
  }
}
