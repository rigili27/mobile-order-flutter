import '../../core/database/database_helper.dart';
import '../models/pedido_cabecera.dart';
import '../models/pedido_detalle.dart';

class PedidoRepository {
  final _db = DatabaseHelper.instance;

  static const _cabeceraSelect = '''
    SELECT p.*,
      (SELECT COALESCE(SUM(d.IMPORTE), 0) FROM PedDMovil d WHERE d.IDPEDIDO = p.ID) AS total
    FROM PedCMovil p
  ''';

  /// codVendedor == -1 → retorna todos los pedidos (modo admin).
  Future<List<PedidoCabecera>> getByVendedor(int codVendedor) async {
    final whereClause =
        codVendedor == -1 ? '' : 'WHERE p.CODVENDEDOR = $codVendedor';
    final rows = await _db.db.rawQuery(
      '$_cabeceraSelect $whereClause ORDER BY p.ID DESC',
    );
    return rows.map(PedidoCabecera.fromMap).toList();
  }

  Future<List<PedidoCabecera>> getByCliente(int codCliente) async {
    final rows = await _db.db.rawQuery(
      '$_cabeceraSelect WHERE p.CODCLIENTE = ? ORDER BY p.ID DESC',
      [codCliente],
    );
    return rows.map(PedidoCabecera.fromMap).toList();
  }

  Future<List<PedidoDetalle>> getDetalles(int idPedido) async {
    final rows = await _db.db.rawQuery(
      '''SELECT d.*, a.DESCRIPCION, a.SKU
         FROM PedDMovil d
         LEFT JOIN ArtMovil a ON a.CODIGO = d.CODARTICULO
         WHERE d.IDPEDIDO = ?
         ORDER BY d.ID''',
      [idPedido],
    );
    return rows.map(PedidoDetalle.fromMap).toList();
  }

  Future<int> insertCabecera(PedidoCabecera p) async {
    final id = await _db.db.insert('PedCMovil', p.toMap());
    await _db.db.update(
      'PedCMovil',
      {'NROPEDIDO': id},
      where: 'ID = ?',
      whereArgs: [id],
    );
    return id;
  }

  Future<void> insertDetalles(List<PedidoDetalle> detalles) async {
    final batch = _db.db.batch();
    for (final d in detalles) {
      batch.insert('PedDMovil', d.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateFirma(int idPedido, List<int> firmaBytes) async {
    await _db.db.update(
      'PedCMovil',
      {'FIRMA': firmaBytes},
      where: 'ID = ?',
      whereArgs: [idPedido],
    );
  }

  Future<void> updatePedido(
      int id, PedidoCabecera cabecera, List<PedidoDetalle> detalles) async {
    final batch = _db.db.batch();
    batch.update('PedCMovil', cabecera.toMap(), where: 'ID = ?', whereArgs: [id]);
    batch.delete('PedDMovil', where: 'IDPEDIDO = ?', whereArgs: [id]);
    for (final d in detalles) {
      batch.insert('PedDMovil', d.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> deletePedido(int idPedido) async {
    final batch = _db.db.batch();
    batch.delete('PedDMovil', where: 'IDPEDIDO = ?', whereArgs: [idPedido]);
    batch.delete('PedCMovil', where: 'ID = ?', whereArgs: [idPedido]);
    batch.delete('PedMCCte', where: 'IDPEDMOVIL = ?', whereArgs: [idPedido]);
    await batch.commit(noResult: true);
  }

  Future<PedidoCabecera?> getById(int id) async {
    final rows = await _db.db.rawQuery(
      '$_cabeceraSelect WHERE p.ID = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) return null;
    return PedidoCabecera.fromMap(rows.first);
  }
}
