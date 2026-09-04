import 'package:shared_preferences/shared_preferences.dart';

import '../app_mode.dart';
import '../database/database_helper.dart';

/// Configuración del modo API (sincronización contra GestionERP en vez de
/// contra una PC por WiFi). Todo vive en shared_preferences; si `baseUrl` y
/// `tenant` están seteados, la app opera en "modo API".
class ApiConfig {
  ApiConfig._();

  static const _kBaseUrl = 'api_base_url';
  static const _kTenant = 'api_tenant';
  static const _kToken = 'api_token';
  static const _kLastSync = 'api_last_sync';

  static Future<String?> baseUrl() async =>
      (await SharedPreferences.getInstance()).getString(_kBaseUrl);

  static Future<String?> tenant() async =>
      (await SharedPreferences.getInstance()).getString(_kTenant);

  static Future<String?> token() async =>
      (await SharedPreferences.getInstance()).getString(_kToken);

  static Future<DateTime?> lastSync() async {
    final raw = (await SharedPreferences.getInstance()).getString(_kLastSync);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// true si hay base URL + tenant configurados (con o sin sesión activa).
  static Future<bool> isConfigured() async {
    final prefs = await SharedPreferences.getInstance();
    final base = prefs.getString(_kBaseUrl);
    final tenant = prefs.getString(_kTenant);
    return base != null && base.trim().isNotEmpty && tenant != null && tenant.trim().isNotEmpty;
  }

  /// true si además hay token → sesión API iniciada.
  static Future<bool> hasSession() async =>
      await isConfigured() && (await token())?.isNotEmpty == true;

  static Future<void> setServer(String baseUrl, String tenant) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, baseUrl.trim());
    await prefs.setString(_kTenant, tenant.trim());
    await _aplicarCambioDeModo();
  }

  static Future<void> setToken(String? token) async {
    final prefs = await SharedPreferences.getInstance();
    if (token == null || token.isEmpty) {
      await prefs.remove(_kToken);
    } else {
      await prefs.setString(_kToken, token);
    }
  }

  static Future<void> markSynced() async {
    await (await SharedPreferences.getInstance())
        .setString(_kLastSync, DateTime.now().toIso8601String());
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in [_kBaseUrl, _kTenant, _kToken, _kLastSync]) {
      await prefs.remove(k);
    }
    await _aplicarCambioDeModo();
  }

  /// Recalcula el modo y cierra la base actual: la próxima apertura apunta al
  /// archivo del modo nuevo (`moviles.db` ↔ `moviles_api.db`). No la reabre acá
  /// — en modo API recién existe tras el primer sync (ver CatalogImporter).
  static Future<void> _aplicarCambioDeModo() async {
    await AppMode.refresh();
    await DatabaseHelper.instance.close();
  }
}
