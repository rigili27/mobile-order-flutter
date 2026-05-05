import '../../core/database/database_helper.dart';
import '../models/cliente.dart';

class ClienteRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Cliente>> getAll() async {
    final rows = await _db.db.query('CliMovil', orderBy: 'NOMBRE');
    return rows.map(Cliente.fromMap).toList();
  }

  Future<List<Cliente>> search(String query) async {
    if (query.trim().isEmpty) return getAll();
    final q = '%${query.trim()}%';
    final rows = await _db.db.rawQuery(
      '''SELECT * FROM CliMovil
         WHERE NOMBRE LIKE ? OR LOCALIDAD LIKE ? OR NROCUIT LIKE ?
         OR CAST(CODIGO AS TEXT) LIKE ?
         ORDER BY NOMBRE''',
      [q, q, q, q],
    );
    return rows.map(Cliente.fromMap).toList();
  }

  Future<Cliente?> findByCodigo(int codigo) async {
    final rows = await _db.db.query(
      'CliMovil',
      where: 'CODIGO = ?',
      whereArgs: [codigo],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Cliente.fromMap(rows.first);
  }
}
