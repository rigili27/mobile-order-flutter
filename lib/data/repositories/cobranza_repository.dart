import '../../core/database/sync_state_database_helper.dart';
import '../models/cobranza.dart';

/// CRUD de las cobranzas locales sobre `movil_sync.db` (base propia de la
/// app). Nunca toca `moviles_api.db` / `moviles.db`.
class CobranzaRepository {
  final _sync = SyncStateDatabaseHelper.instance;

  Future<int> insert(Cobranza cobranza) =>
      _sync.insertCobranza(cobranza.toDbMap());

  Future<List<Cobranza>> getAll() async {
    final rows = await _sync.cobranzasLocales();
    return rows.map(Cobranza.fromMap).toList();
  }

  Future<List<Cobranza>> getByCliente(int codCliente) async {
    final rows = await _sync.cobranzasLocales(codCliente: codCliente);
    return rows.map(Cobranza.fromMap).toList();
  }

  Future<Cobranza?> getById(int id) async {
    final row = await _sync.cobranzaLocal(id);
    return row == null ? null : Cobranza.fromMap(row);
  }

  Future<CobranzaOutboxEntry?> estadoDe(int id) => _sync.findCobranza(id);
}
