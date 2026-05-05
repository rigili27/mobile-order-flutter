import '../../core/database/database_helper.dart';
import '../models/vendedor.dart';

class VendedorRepository {
  final _db = DatabaseHelper.instance;

  Future<Vendedor?> findByCodigo(int codigo) async {
    final rows = await _db.db.query(
      'VendMovil',
      where: 'CODIGO = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Vendedor.fromMap(rows.first);
  }

  Future<List<Vendedor>> getAll() async {
    final rows = await _db.db.query('VendMovil', orderBy: 'NOMBRE');
    return rows.map(Vendedor.fromMap).toList();
  }
}
