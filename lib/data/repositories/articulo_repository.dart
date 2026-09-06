import '../../core/database/database_helper.dart';
import '../models/articulo.dart';
import '../models/lista_precio.dart';

class ArticuloRepository {
  final _db = DatabaseHelper.instance;

  /// Convierte filas de ArtMovil en [Articulo], adjuntando los precios por
  /// lista real del ERP (tabla ArtMovilPrecio) si existen. Una sola query
  /// para todo el lote.
  Future<List<Articulo>> _map(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];
    List<Map<String, Object?>> precios = const [];
    try {
      precios = await _db.db.query('ArtMovilPrecio');
    } catch (_) {
      // Base vieja sin la tabla (modo WiFi): se usan los slots.
    }
    final porArticulo = <int, List<Map<String, Object?>>>{};
    for (final p in precios) {
      porArticulo.putIfAbsent(p['COD_ARTICULO'] as int, () => []).add(p);
    }
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      m['__precios'] = porArticulo[r['CODIGO'] as int] ?? const [];
      return Articulo.fromMap(m);
    }).toList();
  }

  Future<List<Articulo>> getAll() async {
    return _map(await _db.db.query('ArtMovil', orderBy: 'DESCRIPCION'));
  }

  /// Listas de precio del ERP (modo API). Vacío en modo WiFi.
  Future<List<ListaPrecio>> getListas() async {
    try {
      final rows =
          await _db.db.query('ListaPrecioMovil', orderBy: 'NOMBRE');
      return rows.map(ListaPrecio.fromMap).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<Articulo>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    final q = '%${query.trim()}%';
    return _map(await _db.db.rawQuery(
      '''SELECT * FROM ArtMovil
         WHERE DESCRIPCION LIKE ? OR CODIGOBARRA LIKE ? OR SKU LIKE ?
         OR CAST(CODIGO AS TEXT) LIKE ?
         ORDER BY DESCRIPCION''',
      [q, q, q, q],
    ));
  }

  /// Inserta en la base local un artículo recién creado en el ERP (con el
  /// CODIGO real). Queda con PENDIENTE=1 hasta que un sync lo actualice.
  Future<void> insertLocal(Articulo articulo) async {
    await _db.db.insert('ArtMovil', articulo.toMap());
  }

  Future<Articulo?> findByCodigo(int codigo) async {
    final rows = await _db.db.query(
      'ArtMovil',
      where: 'CODIGO = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return (await _map(rows)).first;
  }

  Future<List<Articulo>> searchByDeposito(String query, int depositoCodigo) async {
    final q = '%${query.trim()}%';
    final hasQuery = query.trim().isNotEmpty;
    final rows = await _db.db.rawQuery(
      '''SELECT DISTINCT a.* FROM ArtMovil a
         INNER JOIN DepoMovil d ON d.CODARTICULO = a.CODIGO
         WHERE d.CODIGO = ?
         ${hasQuery ? 'AND (a.DESCRIPCION LIKE ? OR a.CODIGOBARRA LIKE ? OR a.SKU LIKE ? OR CAST(a.CODIGO AS TEXT) LIKE ?)' : ''}
         ORDER BY a.DESCRIPCION''',
      hasQuery ? [depositoCodigo, q, q, q, q] : [depositoCodigo],
    );
    return _map(rows);
  }

  Future<Articulo?> findByBarcode(String barcode) async {
    if (barcode.isEmpty) return null;
    final rows = await _db.db.rawQuery(
      'SELECT * FROM ArtMovil WHERE CODIGOBARRA = ? OR SKU = ? LIMIT 1',
      [barcode, barcode],
    );
    if (rows.isEmpty) return null;
    return (await _map(rows)).first;
  }
}
