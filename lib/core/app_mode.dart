import 'package:shared_preferences/shared_preferences.dart';

/// Modo de operación de la app:
/// - **WiFi** (por defecto): base `moviles.db`, sincronización por servidor
///   WiFi / FTP / compartir archivo, login por dropdown de vendedor.
/// - **API**: base `moviles_api.db` (paralela, no pisa la de WiFi),
///   sincronización contra GestionERP, login por usuario/contraseña.
///
/// El modo lo determina si hay servidor API configurado (mismas claves que
/// `ApiConfig`). Se cachea en memoria (`isApi`) porque `DatabaseHelper.dbPath`
/// lo consulta seguido; hay que llamar `refresh()` al arrancar y cada vez que
/// cambia la configuración de API.
class AppMode {
  AppMode._();

  // Mismas claves que ApiConfig — acá se leen directo para no crear un ciclo
  // de imports con database_helper.
  static const _kBaseUrl = 'api_base_url';
  static const _kTenant = 'api_tenant';

  static bool _isApi = false;

  /// Valor cacheado. Válido después del primer `refresh()`.
  static bool get isApi => _isApi;

  /// Prefijo de archivo de base de datos según el modo.
  static String get dbBaseName => _isApi ? 'moviles_api.db' : 'moviles.db';

  static Future<bool> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final base = prefs.getString(_kBaseUrl)?.trim() ?? '';
    final tenant = prefs.getString(_kTenant)?.trim() ?? '';
    _isApi = base.isNotEmpty && tenant.isNotEmpty;
    return _isApi;
  }
}
