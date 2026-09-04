import '../../core/database/database_helper.dart';
import '../models/parametros.dart';

class ParametrosRepository {
  final _db = DatabaseHelper.instance;

  static Parametros? _cache;

  static Future<String> simboloMoneda() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.monedaDolar ? 'U\$S ' : '\$';
  }

  static Future<bool> ordenPreparacionActivo() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.ordenPreparacion;
  }

  static Future<bool> tipoServicioActivo() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.tipoServicio;
  }

  static Future<bool> nroPedidoActivo() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.nroPedidoVisible;
  }

  static Future<bool> ctaCteActivo() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.ctaCteActivo;
  }

  static Future<bool> apiActivo() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.apiActivo;
  }

  static Future<bool> permitePedidos() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permitePedidos;
  }

  static Future<bool> permiteCobranzas() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permiteCobranzas;
  }

  static Future<bool> permiteAltaClientes() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permiteAltaClientes;
  }

  static Future<bool> permiteAltaArticulos() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permiteAltaArticulos;
  }

  static Future<bool> permiteVerPrecios() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permiteVerPrecios;
  }

  static Future<bool> permiteStock() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permiteStock;
  }

  static Future<bool> permiteGenerarCompra() async {
    _cache ??= await ParametrosRepository().get();
    return _cache!.permiteGenerarCompra;
  }

  static void invalidateCache() => _cache = null;

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

  /// Actualiza el campo CONFIGURACION en ParaMovil.
  /// Si la columna no existe en la DB, no hace nada.
  Future<void> updateConfiguracion(String value) async {
    ParametrosRepository.invalidateCache();
    final columns = await _db.db.rawQuery('PRAGMA table_info(ParaMovil)');
    final existe = columns.any((c) => (c['name'] as String?)?.toUpperCase() == 'CONFIGURACION');
    if (!existe) return;
    final count = (await _db.db.rawQuery('SELECT COUNT(*) as c FROM ParaMovil'))
            .first['c'] as int? ??
        0;
    if (count > 0) {
      await _db.db.rawUpdate('UPDATE ParaMovil SET CONFIGURACION = ?', [value]);
    }
  }
}
