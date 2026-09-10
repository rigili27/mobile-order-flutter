import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';
import 'preventa_api.dart' show ApiException;

/// Cliente HTTP del modo repartidor de GestionERP.
/// Base: `<baseUrl>/api/<tenant>/reparto`.
class RepartoApi {
  RepartoApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 30);

  Future<Uri> _uri(String path) async {
    final base = (await ApiConfig.baseUrl())?.replaceAll(RegExp(r'/+$'), '');
    final tenant = await ApiConfig.tenant();
    if (base == null || base.isEmpty || tenant == null || tenant.isEmpty) {
      throw ApiException('Configurá la URL del servidor y el código de empresa.');
    }
    return Uri.parse('$base/api/$tenant/reparto/$path');
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (auth) {
      final token = await ApiConfig.token();
      if (token != null && token.isNotEmpty) h['Authorization'] = 'Bearer $token';
    }
    return h;
  }

  /// Canjea un código de emparejamiento (del QR del ERP: Reparto →
  /// Repartidores) por un token Sanctum. Devuelve `{token, repartidor, tenant}`.
  Future<Map<String, dynamic>> pairWithCode({
    required String baseUrl,
    required String tenant,
    required String code,
    required String deviceName,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final res = await _client
        .post(
          Uri.parse('$base/api/$tenant/reparto/pair'),
          headers: const {'Accept': 'application/json', 'Content-Type': 'application/json'},
          body: jsonEncode({'code': code, 'deviceName': deviceName}),
        )
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo vincular el dispositivo.'),
          statusCode: res.statusCode);
    }
    return body;
  }

  /// Login por usuario/clave. Devuelve `{token, repartidor}` y persiste el token.
  Future<Map<String, dynamic>> login({
    required String usuario,
    required String password,
    required String deviceName,
  }) async {
    final res = await _client
        .post(
          await _uri('login'),
          headers: await _headers(auth: false),
          body: jsonEncode({'usuario': usuario, 'password': password, 'deviceName': deviceName}),
        )
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo iniciar sesión.'),
          statusCode: res.statusCode);
    }
    await ApiConfig.setToken(body['token'] as String);
    return body;
  }

  Future<void> logout() async {
    try {
      await _client.post(await _uri('logout'), headers: await _headers()).timeout(_timeout);
    } catch (_) {}
    await ApiConfig.setToken(null);
  }

  /// Hojas de ruta asignadas al repartidor. Devuelve la lista `hojas`.
  Future<List<dynamic>> fetchHojas() async {
    final res = await _client.get(await _uri('hojas-de-ruta'), headers: await _headers()).timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudieron traer las hojas de ruta.'),
          statusCode: res.statusCode);
    }
    return (body['hojas'] as List<dynamic>?) ?? const [];
  }

  Future<Map<String, dynamic>> iniciarHoja(int hojaId) =>
      _post('hojas-de-ruta/$hojaId/iniciar', null, 'No se pudo iniciar la hoja de ruta.');

  Future<Map<String, dynamic>> paradaEnCamino(int paradaId) =>
      _post('paradas/$paradaId/en-camino', null, 'No se pudo marcar la parada.');

  Future<Map<String, dynamic>> confirmarEntrega(int paradaId, Map<String, dynamic> payload) =>
      _post('paradas/$paradaId/confirmar', payload, 'No se pudo confirmar la entrega.');

  Future<Map<String, dynamic>> reprogramar(int paradaId, String? motivo) =>
      _post('paradas/$paradaId/reprogramar', {'motivo': motivo}, 'No se pudo reprogramar la parada.');

  Future<Map<String, dynamic>> _post(String path, Map<String, dynamic>? payload, String fallback) async {
    final res = await _client
        .post(await _uri(path),
            headers: await _headers(), body: payload == null ? null : jsonEncode(payload))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, fallback), statusCode: res.statusCode);
    }
    return body;
  }

  Map<String, dynamic> _decode(http.Response res) {
    if (res.body.isEmpty) return {};
    try {
      final decoded = jsonDecode(res.body);
      return decoded is Map<String, dynamic> ? decoded : {'data': decoded};
    } catch (_) {
      return {};
    }
  }

  String _errorMessage(Map<String, dynamic> body, String fallback) {
    if (body['message'] is String && (body['message'] as String).isNotEmpty) {
      final errors = body['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) return first.first.toString();
      }
      return body['message'] as String;
    }
    return fallback;
  }
}
