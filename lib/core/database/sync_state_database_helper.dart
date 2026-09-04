import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Base local propia de la app (no la `moviles.db` del ERP) para el estado de
/// sincronización con la API. Mismo patrón que
/// `OrdenPreparacionDatabaseHelper`: archivo aparte, esquema creado por la
/// app. Guarda el "outbox" de pedidos y cobranzas pendientes de subir.
enum OutboxEstado { pendiente, sincronizado, error }

class OutboxEntry {
  final int idPedidoLocal;
  final String uuid;
  final OutboxEstado estado;
  final int? salesDocumentId;
  final int intentos;
  final String? ultimoError;

  OutboxEntry({
    required this.idPedidoLocal,
    required this.uuid,
    required this.estado,
    this.salesDocumentId,
    this.intentos = 0,
    this.ultimoError,
  });

  factory OutboxEntry.fromMap(Map<String, dynamic> m) => OutboxEntry(
        idPedidoLocal: m['id_pedido_local'] as int,
        uuid: m['uuid'] as String,
        estado: OutboxEstado.values.byName(m['estado'] as String),
        salesDocumentId: m['sales_document_id'] as int?,
        intentos: (m['intentos'] as int?) ?? 0,
        ultimoError: m['ultimo_error'] as String?,
      );
}

/// Estado de sincronización de una cobranza local con la API.
class CobranzaOutboxEntry {
  final int idCobranzaLocal;
  final String uuid;
  final OutboxEstado estado;
  final int? receiptId;
  final int intentos;
  final String? ultimoError;

  CobranzaOutboxEntry({
    required this.idCobranzaLocal,
    required this.uuid,
    required this.estado,
    this.receiptId,
    this.intentos = 0,
    this.ultimoError,
  });

  factory CobranzaOutboxEntry.fromMap(Map<String, dynamic> m) =>
      CobranzaOutboxEntry(
        idCobranzaLocal: m['id_cobranza_local'] as int,
        uuid: m['uuid'] as String,
        estado: OutboxEstado.values.byName(m['estado'] as String),
        receiptId: m['receipt_id'] as int?,
        intentos: (m['intentos'] as int?) ?? 0,
        ultimoError: m['ultimo_error'] as String?,
      );
}

class SyncStateDatabaseHelper {
  SyncStateDatabaseHelper._();
  static final SyncStateDatabaseHelper instance = SyncStateDatabaseHelper._();

  Database? _db;

  Future<Database> get _database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    return openDatabase(
      join(dir.path, 'movil_sync.db'),
      version: 4,
      onCreate: (db, _) async {
        await db.execute(_kPedidoOutboxDDL);
        await db.execute(_kCobranzaLocalDDL);
        await db.execute(_kCobranzaOutboxDDL);
        await db.execute(_kClienteOutboxDDL);
        await db.execute(_kArticuloOutboxDDL);
        await db.execute(_kAjusteStockLocalDDL);
        await db.execute(_kAjusteStockOutboxDDL);
        await db.execute(_kOrdenCompraLocalDDL);
        await db.execute(_kOrdenCompraOutboxDDL);
      },
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) {
          await db.execute(_kCobranzaLocalDDL);
          await db.execute(_kCobranzaOutboxDDL);
        }
        if (oldVersion < 3) {
          await db.execute(_kClienteOutboxDDL);
          await db.execute(_kArticuloOutboxDDL);
        }
        if (oldVersion < 4) {
          await db.execute(_kAjusteStockLocalDDL);
          await db.execute(_kAjusteStockOutboxDDL);
          await db.execute(_kOrdenCompraLocalDDL);
          await db.execute(_kOrdenCompraOutboxDDL);
        }
      },
    );
  }

  static const _kPedidoOutboxDDL = '''
    CREATE TABLE pedido_outbox (
      id_pedido_local INTEGER PRIMARY KEY,
      uuid TEXT NOT NULL UNIQUE,
      estado TEXT NOT NULL DEFAULT 'pendiente',
      sales_document_id INTEGER,
      intentos INTEGER NOT NULL DEFAULT 0,
      ultimo_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''';

  static const _kCobranzaLocalDDL = '''
    CREATE TABLE cobranza_local (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cod_cliente INTEGER NOT NULL,
      fecha TEXT NOT NULL,
      importe REAL NOT NULL,
      forma_pago TEXT NOT NULL,
      detalle_json TEXT,
      referencia TEXT,
      notas TEXT,
      firma BLOB,
      creado_at TEXT NOT NULL
    )
  ''';

  static const _kCobranzaOutboxDDL = '''
    CREATE TABLE cobranza_outbox (
      id_cobranza_local INTEGER PRIMARY KEY,
      uuid TEXT NOT NULL UNIQUE,
      estado TEXT NOT NULL DEFAULT 'pendiente',
      receipt_id INTEGER,
      intentos INTEGER NOT NULL DEFAULT 0,
      ultimo_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''';

  // Trazabilidad de altas de cliente / artículo desde la app (solo online:
  // se registran cuando el ERP responde con el id real).
  static const _kClienteOutboxDDL = '''
    CREATE TABLE cliente_outbox (
      uuid TEXT PRIMARY KEY,
      customer_id INTEGER,
      nombre TEXT,
      estado TEXT NOT NULL DEFAULT 'sincronizado',
      ultimo_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''';

  static const _kArticuloOutboxDDL = '''
    CREATE TABLE articulo_outbox (
      uuid TEXT PRIMARY KEY,
      product_id INTEGER,
      descripcion TEXT,
      estado TEXT NOT NULL DEFAULT 'sincronizado',
      ultimo_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''';

  static const _kAjusteStockLocalDDL = '''
    CREATE TABLE ajuste_stock_local (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      cod_articulo INTEGER NOT NULL,
      descripcion_articulo TEXT,
      cod_deposito INTEGER NOT NULL,
      descripcion_deposito TEXT,
      cantidad_contada REAL NOT NULL,
      cantidad_sistema REAL,
      observaciones TEXT,
      creado_at TEXT NOT NULL
    )
  ''';

  static const _kAjusteStockOutboxDDL = '''
    CREATE TABLE ajuste_stock_outbox (
      id_ajuste_local INTEGER PRIMARY KEY,
      uuid TEXT NOT NULL UNIQUE,
      estado TEXT NOT NULL DEFAULT 'pendiente',
      submission_id INTEGER,
      diferencia_sugerida REAL,
      intentos INTEGER NOT NULL DEFAULT 0,
      ultimo_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''';

  static const _kOrdenCompraLocalDDL = '''
    CREATE TABLE orden_compra_local (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      proveedor_id INTEGER,
      proveedor_nombre TEXT,
      observaciones TEXT,
      items_json TEXT NOT NULL,
      creado_at TEXT NOT NULL
    )
  ''';

  static const _kOrdenCompraOutboxDDL = '''
    CREATE TABLE orden_compra_outbox (
      id_orden_local INTEGER PRIMARY KEY,
      uuid TEXT NOT NULL UNIQUE,
      estado TEXT NOT NULL DEFAULT 'pendiente',
      submission_id INTEGER,
      intentos INTEGER NOT NULL DEFAULT 0,
      ultimo_error TEXT,
      updated_at TEXT NOT NULL
    )
  ''';

  // ── pedidos ────────────────────────────────────────────────────────────────

  /// Da de alta (o resetea a pendiente) el pedido local en el outbox.
  /// Conserva el uuid si ya existía, para mantener la idempotencia.
  Future<String> enqueue(int idPedidoLocal, String Function() nuevoUuid) async {
    final db = await _database;
    final existing = await db.query('pedido_outbox',
        where: 'id_pedido_local = ?', whereArgs: [idPedidoLocal], limit: 1);

    final uuid = existing.isNotEmpty
        ? existing.first['uuid'] as String
        : nuevoUuid();

    await db.insert(
      'pedido_outbox',
      {
        'id_pedido_local': idPedidoLocal,
        'uuid': uuid,
        'estado': OutboxEstado.pendiente.name,
        'sales_document_id': existing.isNotEmpty
            ? existing.first['sales_document_id']
            : null,
        'intentos': existing.isNotEmpty ? existing.first['intentos'] : 0,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return uuid;
  }

  Future<void> markSincronizado(int idPedidoLocal, int? salesDocumentId) async {
    final db = await _database;
    await db.update(
      'pedido_outbox',
      {
        'estado': OutboxEstado.sincronizado.name,
        'sales_document_id': salesDocumentId,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id_pedido_local = ?',
      whereArgs: [idPedidoLocal],
    );
  }

  Future<void> markError(int idPedidoLocal, String error) async {
    final db = await _database;
    await db.rawUpdate(
      '''UPDATE pedido_outbox
         SET estado = ?, intentos = intentos + 1, ultimo_error = ?, updated_at = ?
         WHERE id_pedido_local = ?''',
      [OutboxEstado.error.name, error, DateTime.now().toIso8601String(), idPedidoLocal],
    );
  }

  Future<OutboxEntry?> find(int idPedidoLocal) async {
    final db = await _database;
    final rows = await db.query('pedido_outbox',
        where: 'id_pedido_local = ?', whereArgs: [idPedidoLocal], limit: 1);
    return rows.isEmpty ? null : OutboxEntry.fromMap(rows.first);
  }

  Future<List<OutboxEntry>> pendientes() async {
    final db = await _database;
    final rows = await db.query(
      'pedido_outbox',
      where: 'estado != ?',
      whereArgs: [OutboxEstado.sincronizado.name],
      orderBy: 'id_pedido_local ASC',
    );
    return rows.map(OutboxEntry.fromMap).toList();
  }

  Future<int> countPendientes() async {
    final db = await _database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM pedido_outbox WHERE estado != ?',
      [OutboxEstado.sincronizado.name],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  // ── cobranzas ──────────────────────────────────────────────────────────────

  Future<int> insertCobranza(Map<String, dynamic> row) async {
    final db = await _database;
    return db.insert('cobranza_local', {
      ...row,
      'creado_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> cobranzasLocales({int? codCliente}) async {
    final db = await _database;
    return db.query(
      'cobranza_local',
      where: codCliente == null ? null : 'cod_cliente = ?',
      whereArgs: codCliente == null ? null : [codCliente],
      orderBy: 'id DESC',
    );
  }

  Future<Map<String, dynamic>?> cobranzaLocal(int id) async {
    final db = await _database;
    final rows = await db.query('cobranza_local',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  /// Da de alta (o resetea a pendiente) la cobranza local en su outbox.
  Future<String> enqueueCobranza(
      int idCobranzaLocal, String Function() nuevoUuid) async {
    final db = await _database;
    final existing = await db.query('cobranza_outbox',
        where: 'id_cobranza_local = ?',
        whereArgs: [idCobranzaLocal],
        limit: 1);

    final uuid = existing.isNotEmpty
        ? existing.first['uuid'] as String
        : nuevoUuid();

    await db.insert(
      'cobranza_outbox',
      {
        'id_cobranza_local': idCobranzaLocal,
        'uuid': uuid,
        'estado': OutboxEstado.pendiente.name,
        'receipt_id':
            existing.isNotEmpty ? existing.first['receipt_id'] : null,
        'intentos': existing.isNotEmpty ? existing.first['intentos'] : 0,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return uuid;
  }

  Future<void> markCobranzaSincronizada(
      int idCobranzaLocal, int? receiptId) async {
    final db = await _database;
    await db.update(
      'cobranza_outbox',
      {
        'estado': OutboxEstado.sincronizado.name,
        'receipt_id': receiptId,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id_cobranza_local = ?',
      whereArgs: [idCobranzaLocal],
    );
  }

  Future<void> markCobranzaError(int idCobranzaLocal, String error) async {
    final db = await _database;
    await db.rawUpdate(
      '''UPDATE cobranza_outbox
         SET estado = ?, intentos = intentos + 1, ultimo_error = ?, updated_at = ?
         WHERE id_cobranza_local = ?''',
      [
        OutboxEstado.error.name,
        error,
        DateTime.now().toIso8601String(),
        idCobranzaLocal,
      ],
    );
  }

  Future<CobranzaOutboxEntry?> findCobranza(int idCobranzaLocal) async {
    final db = await _database;
    final rows = await db.query('cobranza_outbox',
        where: 'id_cobranza_local = ?',
        whereArgs: [idCobranzaLocal],
        limit: 1);
    return rows.isEmpty ? null : CobranzaOutboxEntry.fromMap(rows.first);
  }

  Future<List<CobranzaOutboxEntry>> cobranzasPendientes() async {
    final db = await _database;
    final rows = await db.query(
      'cobranza_outbox',
      where: 'estado != ?',
      whereArgs: [OutboxEstado.sincronizado.name],
      orderBy: 'id_cobranza_local ASC',
    );
    return rows.map(CobranzaOutboxEntry.fromMap).toList();
  }

  Future<int> countCobranzasPendientes() async {
    final db = await _database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) c FROM cobranza_outbox WHERE estado != ?',
      [OutboxEstado.sincronizado.name],
    );
    return (r.first['c'] as int?) ?? 0;
  }

  // ── altas de cliente / artículo (trazabilidad) ─────────────────────────────

  Future<void> registrarClienteCreado({
    required String uuid,
    required int customerId,
    required String nombre,
  }) async {
    final db = await _database;
    await db.insert(
      'cliente_outbox',
      {
        'uuid': uuid,
        'customer_id': customerId,
        'nombre': nombre,
        'estado': OutboxEstado.sincronizado.name,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> registrarArticuloCreado({
    required String uuid,
    required int productId,
    required String descripcion,
  }) async {
    final db = await _database;
    await db.insert(
      'articulo_outbox',
      {
        'uuid': uuid,
        'product_id': productId,
        'descripcion': descripcion,
        'estado': OutboxEstado.sincronizado.name,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── ajustes de stock ───────────────────────────────────────────────────────

  Future<int> insertAjusteStock(Map<String, dynamic> row) async {
    final db = await _database;
    return db.insert('ajuste_stock_local', {
      ...row,
      'creado_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> ajustesStockLocales() async {
    final db = await _database;
    return db.query('ajuste_stock_local', orderBy: 'id DESC');
  }

  Future<String> enqueueAjusteStock(
      int idAjusteLocal, String Function() nuevoUuid) async {
    final db = await _database;
    final existing = await db.query('ajuste_stock_outbox',
        where: 'id_ajuste_local = ?', whereArgs: [idAjusteLocal], limit: 1);
    final uuid =
        existing.isNotEmpty ? existing.first['uuid'] as String : nuevoUuid();

    await db.insert(
      'ajuste_stock_outbox',
      {
        'id_ajuste_local': idAjusteLocal,
        'uuid': uuid,
        'estado': OutboxEstado.pendiente.name,
        'submission_id':
            existing.isNotEmpty ? existing.first['submission_id'] : null,
        'diferencia_sugerida': existing.isNotEmpty
            ? existing.first['diferencia_sugerida']
            : null,
        'intentos': existing.isNotEmpty ? existing.first['intentos'] : 0,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return uuid;
  }

  Future<void> markAjusteStockSincronizado(
      int idAjusteLocal, int? submissionId, double? diferenciaSugerida) async {
    final db = await _database;
    await db.update(
      'ajuste_stock_outbox',
      {
        'estado': OutboxEstado.sincronizado.name,
        'submission_id': submissionId,
        'diferencia_sugerida': diferenciaSugerida,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id_ajuste_local = ?',
      whereArgs: [idAjusteLocal],
    );
  }

  Future<void> markAjusteStockError(int idAjusteLocal, String error) async {
    final db = await _database;
    await db.rawUpdate(
      '''UPDATE ajuste_stock_outbox
         SET estado = ?, intentos = intentos + 1, ultimo_error = ?, updated_at = ?
         WHERE id_ajuste_local = ?''',
      [
        OutboxEstado.error.name,
        error,
        DateTime.now().toIso8601String(),
        idAjusteLocal,
      ],
    );
  }

  Future<Map<String, dynamic>?> estadoAjusteStock(int idAjusteLocal) async {
    final db = await _database;
    final rows = await db.query('ajuste_stock_outbox',
        where: 'id_ajuste_local = ?', whereArgs: [idAjusteLocal], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  // ── órdenes de compra ──────────────────────────────────────────────────────

  Future<int> insertOrdenCompra(Map<String, dynamic> row) async {
    final db = await _database;
    return db.insert('orden_compra_local', {
      ...row,
      'creado_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> ordenesCompraLocales() async {
    final db = await _database;
    return db.query('orden_compra_local', orderBy: 'id DESC');
  }

  Future<String> enqueueOrdenCompra(
      int idOrdenLocal, String Function() nuevoUuid) async {
    final db = await _database;
    final existing = await db.query('orden_compra_outbox',
        where: 'id_orden_local = ?', whereArgs: [idOrdenLocal], limit: 1);
    final uuid =
        existing.isNotEmpty ? existing.first['uuid'] as String : nuevoUuid();

    await db.insert(
      'orden_compra_outbox',
      {
        'id_orden_local': idOrdenLocal,
        'uuid': uuid,
        'estado': OutboxEstado.pendiente.name,
        'submission_id':
            existing.isNotEmpty ? existing.first['submission_id'] : null,
        'intentos': existing.isNotEmpty ? existing.first['intentos'] : 0,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return uuid;
  }

  Future<void> markOrdenCompraSincronizada(
      int idOrdenLocal, int? submissionId) async {
    final db = await _database;
    await db.update(
      'orden_compra_outbox',
      {
        'estado': OutboxEstado.sincronizado.name,
        'submission_id': submissionId,
        'ultimo_error': null,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id_orden_local = ?',
      whereArgs: [idOrdenLocal],
    );
  }

  Future<void> markOrdenCompraError(int idOrdenLocal, String error) async {
    final db = await _database;
    await db.rawUpdate(
      '''UPDATE orden_compra_outbox
         SET estado = ?, intentos = intentos + 1, ultimo_error = ?, updated_at = ?
         WHERE id_orden_local = ?''',
      [
        OutboxEstado.error.name,
        error,
        DateTime.now().toIso8601String(),
        idOrdenLocal,
      ],
    );
  }

  Future<Map<String, dynamic>?> estadoOrdenCompra(int idOrdenLocal) async {
    final db = await _database;
    final rows = await db.query('orden_compra_outbox',
        where: 'id_orden_local = ?', whereArgs: [idOrdenLocal], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }
}
