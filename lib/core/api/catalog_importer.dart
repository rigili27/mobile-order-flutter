import 'dart:io';

import 'package:sqflite/sqflite.dart';

import '../database/database_helper.dart';

/// Escribe el snapshot JSON de `/catalogo` en las tablas `*Movil` del SQLite
/// local (`moviles_api.db`). Reemplaza el contenido tabla por tabla
/// (DELETE + INSERT) dentro de una transacción — equivalente al swap del
/// archivo completo del modo WiFi, pero sin tocar los datos propios del
/// vendedor (PedCMovil / PedDMovil / PedMCCte no se tocan nunca).
///
/// La base API es propia de la app (no la maneja ningún sistema externo),
/// así que sí se le ajusta el esquema: el `moviles.db` de assets es viejo y
/// le faltan columnas (`ParaMovil.CONFIGURACION`, `PedCMovil.TIPOVENTA`) y la
/// tabla `PedMCCte`. `_ensureApiSchema()` las agrega de forma idempotente.
class CatalogImporter {
  final _helper = DatabaseHelper.instance;

  Future<void> import(Map<String, dynamic> catalogo) async {
    await _ensureDatabase();
    final db = _helper.db;
    await _ensureApiSchema(db);

    await db.transaction((txn) async {
      await _replace(txn, 'VendMovil', _rows(catalogo['vendedores'], _vendedor));
      await _replace(txn, 'CliMovil', _rows(catalogo['clientes'], _cliente));
      await _replace(txn, 'ArtMovil', _rows(catalogo['articulos'], _articulo));
      await _replace(txn, 'DepoMovil', _rows(catalogo['depositos'], _deposito));
      await _replace(txn, 'ProvMovil', _rows(catalogo['proveedores'], _proveedor));
      await _replace(txn, 'ListaPrecioMovil', _rows(catalogo['listas'], _lista));
      await _replacePrecios(txn, catalogo['articulos']);

      final parametros = catalogo['parametros'];
      if (parametros is Map<String, dynamic>) {
        await _replace(txn, 'ParaMovil', [_parametros(parametros)]);
      }
    });
  }

  /// Refresca artículos, listas de precio y stock por depósito desde el
  /// endpoint dedicado `GET /articulos` (`{listas, articulos}`). No toca
  /// pedidos ni cuentas corrientes. Molde: [import].
  Future<void> importArticulos(Map<String, dynamic> data) async {
    await _ensureDatabase();
    final db = _helper.db;
    await _ensureApiSchema(db);

    final articulos = data['articulos'];

    await db.transaction((txn) async {
      await _replace(txn, 'ListaPrecioMovil', _rows(data['listas'], _lista));
      await _replacePrecios(txn, articulos);

      if (articulos is List) {
        // Upsert de cada artículo (conserva STOCKACTUAL/PREVTAPUB del
        // catálogo base si el endpoint no los trae).
        final artCols = await _columns(txn, 'ArtMovil');
        for (final a in articulos.whereType<Map<String, dynamic>>()) {
          final precios = (a['precios'] as List?)
                  ?.whereType<Map>()
                  .map((p) => _toDouble(p['precio']))
                  .toList() ??
              const <double>[];
          final stock = (a['stockPorDeposito'] as List?)
                  ?.whereType<Map>()
                  .fold<double>(0, (s, d) => s + _toDouble(d['stock'])) ??
              0.0;
          final row = <String, Object?>{
            'CODIGO': a['codigo'],
            'DESCRIPCION': a['descripcion'] ?? '',
            'UNIDAD': a['unidad'],
            'STOCKACTUAL': stock,
            'PREVTAPUB1': precios.isNotEmpty ? precios[0] : 0.0,
            'PREVTAPUB2': precios.length > 1 ? precios[1] : 0.0,
            'PREVTAPUB3': precios.length > 2 ? precios[2] : 0.0,
            'ALICUTA': _toDouble(a['alicuota']),
            'MONEDA': a['moneda'],
            'CODIGOBARRA': a['codigoBarra'] ?? '',
            'SKU': a['sku'] ?? '',
            'PENDIENTE': a['pendiente'] == true ? 1 : 0,
          }..removeWhere((k, _) => !artCols.contains(k.toUpperCase()));
          await txn.insert('ArtMovil', row,
              conflictAlgorithm: ConflictAlgorithm.replace);
        }

        // Rebuild de DepoMovil desde stockPorDeposito.
        final depoCols = await _columns(txn, 'DepoMovil');
        if (depoCols.isNotEmpty) {
          await txn.delete('DepoMovil');
          for (final a in articulos.whereType<Map<String, dynamic>>()) {
            for (final d in (a['stockPorDeposito'] as List? ?? const [])
                .whereType<Map>()) {
              final row = <String, Object?>{
                'CODIGO': d['codDeposito'],
                'CODARTICULO': a['codigo'],
                'DESCRIPCION': d['descripcion'] ?? '',
                'DESCARTICULO': a['descripcion'] ?? '',
                'STOCK': _toDouble(d['stock']),
              }..removeWhere((k, _) => !depoCols.contains(k.toUpperCase()));
              await txn.insert('DepoMovil', row,
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
          }
        }
      }
    });
  }

  /// Vuelca `articulos[].precios` (todas las listas) en `ArtMovilPrecio`.
  Future<void> _replacePrecios(DatabaseExecutor txn, Object? articulos) async {
    await txn.delete('ArtMovilPrecio');
    if (articulos is! List) return;
    for (final a in articulos.whereType<Map<String, dynamic>>()) {
      final codArticulo = a['codigo'];
      final precios = a['precios'];
      if (codArticulo == null || precios is! List) continue;
      for (final p in precios.whereType<Map<String, dynamic>>()) {
        await txn.insert(
          'ArtMovilPrecio',
          {
            'COD_ARTICULO': codArticulo,
            'COD_LISTA': p['codLista'],
            'PRECIO': _toDouble(p['precio']),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }

  Future<void> _ensureDatabase() async {
    final path = await _helper.dbPath;
    if (!await File(path).exists()) {
      await _helper.copyFromAssets();
    }
    if (!_helper.isOpen) {
      final result = await _helper.init();
      if (result.state != DbInitState.ok) {
        throw StateError('No se pudo abrir la base local: ${result.error}');
      }
    }
  }

  /// Ajusta el esquema de la base API a lo que necesita la app hoy
  /// (el `moviles.db` de assets quedó viejo). Idempotente.
  Future<void> _ensureApiSchema(Database db) async {
    Future<bool> hasColumn(String table, String column) async {
      final info = await db.rawQuery('PRAGMA table_info($table)');
      return info.any((c) => (c['name'] as String? ?? '').toUpperCase() == column);
    }

    if (!await hasColumn('ParaMovil', 'CONFIGURACION')) {
      await db.execute('ALTER TABLE ParaMovil ADD COLUMN CONFIGURACION TEXT');
    }
    if (!await hasColumn('ParaMovil', 'PRECIOS_INCLUYEN_IVA')) {
      await db.execute('ALTER TABLE ParaMovil ADD COLUMN PRECIOS_INCLUYEN_IVA INTEGER DEFAULT 0');
    }
    if (!await hasColumn('PedCMovil', 'TIPOVENTA')) {
      await db.execute('ALTER TABLE PedCMovil ADD COLUMN TIPOVENTA TEXT');
    }
    if (!await hasColumn('ArtMovil', 'PENDIENTE')) {
      await db.execute('ALTER TABLE ArtMovil ADD COLUMN PENDIENTE INTEGER DEFAULT 0');
    }
    if (!await hasColumn('CliMovil', 'PENDIENTE')) {
      await db.execute('ALTER TABLE CliMovil ADD COLUMN PENDIENTE INTEGER DEFAULT 0');
    }
    if (!await hasColumn('CliMovil', 'COD_LISTA')) {
      await db.execute('ALTER TABLE CliMovil ADD COLUMN COD_LISTA INTEGER');
    }
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ListaPrecioMovil (
        CODIGO INTEGER PRIMARY KEY,
        NOMBRE TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ArtMovilPrecio (
        COD_ARTICULO INTEGER NOT NULL,
        COD_LISTA INTEGER NOT NULL,
        PRECIO REAL DEFAULT 0,
        PRIMARY KEY (COD_ARTICULO, COD_LISTA)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS CtaCteMovil (
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        COD_CLIENTE INTEGER NOT NULL,
        FECHA TEXT,
        TIPO TEXT,
        DETALLE TEXT,
        DEBE REAL DEFAULT 0,
        HABER REAL DEFAULT 0,
        SALDO REAL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS PedMCCte (
        ID INTEGER PRIMARY KEY AUTOINCREMENT,
        IDPEDMOVIL INTEGER,
        CODCLIENTE INTEGER NOT NULL,
        TIPOVENTA TEXT,
        IMPORTE REAL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ProvMovil (
        CODIGO INTEGER PRIMARY KEY,
        NOMBRE TEXT
      )
    ''');
  }

  Future<void> _replace(
      DatabaseExecutor txn, String table, List<Map<String, Object?>> rows) async {
    final existing = await _columns(txn, table);
    await txn.delete(table);
    for (final row in rows) {
      final filtered = <String, Object?>{
        for (final e in row.entries)
          if (existing.contains(e.key.toUpperCase())) e.key: e.value,
      };
      if (filtered.isNotEmpty) {
        await txn.insert(table, filtered,
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    }
  }

  Future<Set<String>> _columns(DatabaseExecutor txn, String table) async {
    final info = await txn.rawQuery('PRAGMA table_info($table)');
    return info
        .map((c) => (c['name'] as String? ?? '').toUpperCase())
        .toSet();
  }

  List<Map<String, Object?>> _rows(
      Object? list, Map<String, Object?> Function(Map<String, dynamic>) map) {
    if (list is! List) return const [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(map)
        .toList(growable: false);
  }

  Map<String, Object?> _vendedor(Map<String, dynamic> v) => {
        'CODIGO': v['codigo'],
        'NOMBRE': v['nombre'] ?? '',
        'CLAVE': v['clave'] ?? '',
      };

  Map<String, Object?> _cliente(Map<String, dynamic> c) => {
        'CODIGO': c['codigo'],
        'NOMBRE': c['nombre'] ?? '',
        'DOMICILIO': c['domicilio'] ?? '',
        'LOCALIDAD': c['localidad'] ?? '',
        'TELEFONO': c['telefono'] ?? '',
        'NROCUIT': c['nroCuit'] ?? '',
        'CODCATIVA': c['codCatIva'],
        'NROLPRECIOS': c['nrolPrecios'] ?? 1,
        'SALDO': _toDouble(c['saldo']),
        'PENDIENTE': c['pendiente'] == true ? 1 : 0,
        'COD_LISTA': c['codLista'],
      };

  Map<String, Object?> _lista(Map<String, dynamic> l) => {
        'CODIGO': l['codigo'],
        'NOMBRE': l['nombre'] ?? '',
      };

  Map<String, Object?> _articulo(Map<String, dynamic> a) => {
        'CODIGO': a['codigo'],
        'DESCRIPCION': a['descripcion'] ?? '',
        'UNIDAD': a['unidad'],
        'STOCKACTUAL': _toDouble(a['stockActual']),
        'PREVTAPUB1': _toDouble(a['prevtaPub1']),
        'PREVTAPUB2': _toDouble(a['prevtaPub2']),
        'PREVTAPUB3': _toDouble(a['prevtaPub3']),
        'ALICUTA': _toDouble(a['alicuota']), // columna mal escrita en la DB
        'MONEDA': a['moneda'],
        'CODIGOBARRA': a['codigoBarra'] ?? '',
        'SKU': a['sku'] ?? '',
        'PENDIENTE': a['pendiente'] == true ? 1 : 0,
      };

  Map<String, Object?> _deposito(Map<String, dynamic> d) => {
        'ID': d['id'],
        'CODIGO': d['codigo'],
        'CODARTICULO': d['codArticulo'],
        'DESCRIPCION': d['descripcion'] ?? '',
        'DESCARTICULO': d['descArticulo'] ?? '',
        'STOCK': _toDouble(d['stock']),
      };

  Map<String, Object?> _proveedor(Map<String, dynamic> p) => {
        'CODIGO': p['codigo'],
        'NOMBRE': p['nombre'] ?? '',
      };

  Map<String, Object?> _parametros(Map<String, dynamic> p) => {
        'RAZONSOCIAL': p['razonSocial'] ?? '',
        'DOMICILIO': p['domicilio'] ?? '',
        'NROCUIT': p['nroCuit'] ?? '',
        'COTIZACION': _toDouble(p['cotizacion'], fallback: 1),
        'FTP': p['ftp'] ?? '',
        'CONFIGURACION': p['configuracion'] ?? '',
        'PRECIOS_INCLUYEN_IVA': p['preciosIncluyenIva'] == true ? 1 : 0,
      };

  double _toDouble(Object? v, {double fallback = 0}) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? fallback;
    return fallback;
  }
}
