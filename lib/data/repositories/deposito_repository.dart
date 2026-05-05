import '../../core/database/database_helper.dart';
import '../models/deposito.dart';

class DepositoRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Deposito>> getByArticulo(int codArticulo) async {
    final rows = await _db.db.query(
      'DepoMovil',
      where: 'CODARTICULO = ?',
      whereArgs: [codArticulo],
      orderBy: 'DESCRIPCION',
    );
    return rows.map(Deposito.fromMap).toList();
  }

  Future<List<Deposito>> getAll() async {
    final rows = await _db.db.rawQuery(
      'SELECT DISTINCT CODIGO, DESCRIPCION FROM DepoMovil ORDER BY DESCRIPCION',
    );
    return rows
        .map((r) => Deposito(
              id: 0,
              codigo: r['CODIGO'] as int,
              codArticulo: 0,
              descripcion: (r['DESCRIPCION'] as String? ?? '').trim(),
              descArticulo: '',
              stock: 0,
            ))
        .toList();
  }

  /// Returns all DepoMovil rows (each article×deposit combination with its stock).
  Future<List<Deposito>> getAllEntries() async {
    final rows = await _db.db.query('DepoMovil', orderBy: 'DESCRIPCION');
    return rows.map(Deposito.fromMap).toList();
  }
}
