import '../../core/database/database_helper.dart';
import '../models/parametros.dart';

class ParametrosRepository {
  final _db = DatabaseHelper.instance;

  Future<Parametros> get() async {
    final rows = await _db.db.query('ParaMovil', limit: 1);
    if (rows.isEmpty) return Parametros.empty;
    return Parametros.fromMap(rows.first);
  }

  /// Actualiza el campo FTP en ParaMovil (IP:puerto del servidor de la PC).
  Future<void> updateFtp(String value) async {
    final count = (await _db.db.rawQuery('SELECT COUNT(*) as c FROM ParaMovil'))
            .first['c'] as int? ??
        0;
    if (count > 0) {
      await _db.db.rawUpdate('UPDATE ParaMovil SET FTP = ?', [value]);
    }
  }
}
