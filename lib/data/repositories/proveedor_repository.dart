import '../../core/database/database_helper.dart';
import '../models/proveedor.dart';

/// Solo lectura: los proveedores vienen del catálogo (`CatalogImporter`),
/// tabla local `ProvMovil`.
class ProveedorRepository {
  final _db = DatabaseHelper.instance;

  Future<List<Proveedor>> getAll() async {
    final rows = await _db.db.query('ProvMovil', orderBy: 'NOMBRE');
    return rows.map(Proveedor.fromMap).toList();
  }
}
