import '../../core/database/database_helper.dart';
import '../models/articulo.dart';

class ArticuloRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Articulo>> getAll() async {
    final rows = await _db.db.query('ArtMovil', orderBy: 'DESCRIPCION');
    return rows.map(Articulo.fromMap).toList();
  }

  Future<List<Articulo>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    final q = '%${query.trim()}%';
    final rows = await _db.db.rawQuery(
      '''SELECT * FROM ArtMovil
         WHERE DESCRIPCION LIKE ? OR CODIGOBARRA LIKE ? OR SKU LIKE ?
         OR CAST(CODIGO AS TEXT) LIKE ?
         ORDER BY DESCRIPCION''',
      [q, q, q, q],
    );
    return rows.map(Articulo.fromMap).toList();
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
    return Articulo.fromMap(rows.first);
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
    return rows.map(Articulo.fromMap).toList();
  }

  Future<Articulo?> findByBarcode(String barcode) async {
    if (barcode.isEmpty) return null;
    final rows = await _db.db.rawQuery(
      'SELECT * FROM ArtMovil WHERE CODIGOBARRA = ? OR SKU = ? LIMIT 1',
      [barcode, barcode],
    );
    if (rows.isEmpty) return null;
    return Articulo.fromMap(rows.first);
  }
}
