import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_config.dart';

/// Error de la API pensado para mostrar directo al usuario.
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  final bool unauthorized;

  ApiException(this.message, {this.statusCode})
      : unauthorized = statusCode == 401;

  @override
  String toString() => message;
}

/// Cliente HTTP de la API de Preventa Móvil de GestionERP.
/// Base: `<baseUrl>/api/<tenant>`.
class PreventaApi {
  PreventaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _timeout = Duration(seconds: 30);

  Future<Uri> _uri(String path) async {
    final base = (await ApiConfig.baseUrl())?.replaceAll(RegExp(r'/+$'), '');
    final tenant = await ApiConfig.tenant();
    if (base == null || base.isEmpty || tenant == null || tenant.isEmpty) {
      throw ApiException('Configurá la URL del servidor y el código de empresa.');
    }
    return Uri.parse('$base/api/$tenant/$path');
  }

  Future<Map<String, String>> _headers({bool auth = true}) async {
    final h = {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
    };
    if (auth) {
      final token = await ApiConfig.token();
      if (token != null && token.isNotEmpty) {
        h['Authorization'] = 'Bearer $token';
      }
    }
    return h;
  }

  /// Login del vendedor (`usuario` = nombre de usuario o email). Devuelve el
  /// `codigo` del vendedor y persiste el token.
  Future<int> login({
    required String usuario,
    required String password,
    required String deviceName,
  }) async {
    final res = await _client
        .post(
          await _uri('login'),
          headers: await _headers(auth: false),
          body: jsonEncode({
            'usuario': usuario,
            'password': password,
            'deviceName': deviceName,
          }),
        )
        .timeout(_timeout);

    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo iniciar sesión.'),
          statusCode: res.statusCode);
    }

    await ApiConfig.setToken(body['token'] as String);
    return (body['vendedor'] as Map<String, dynamic>)['codigo'] as int;
  }

  /// Canjea un código de emparejamiento (escaneado del QR) por un token
  /// Sanctum. No usa `ApiConfig` — la URL y el tenant vienen del propio QR y
  /// todavía no están persistidos. Devuelve `{token, vendedor, tenant}`.
  Future<Map<String, dynamic>> pairWithCode({
    required String baseUrl,
    required String tenant,
    required String code,
    required String deviceName,
  }) async {
    final base = baseUrl.replaceAll(RegExp(r'/+$'), '');
    final res = await _client
        .post(
          Uri.parse('$base/api/$tenant/pair'),
          headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
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

  Future<void> logout() async {
    try {
      await _client
          .post(await _uri('logout'), headers: await _headers())
          .timeout(_timeout);
    } catch (_) {
      // best-effort; el token local se limpia igual
    }
    await ApiConfig.setToken(null);
  }

  /// Snapshot del catálogo (vendedores, clientes, articulos, depositos, parametros).
  Future<Map<String, dynamic>> fetchCatalogo() async {
    final res = await _client
        .get(await _uri('catalogo'), headers: await _headers())
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo sincronizar el catálogo.'),
          statusCode: res.statusCode);
    }
    return body;
  }

  /// Sube un pedido. Devuelve el id del comprobante creado en el ERP.
  Future<int?> pushPedido(Map<String, dynamic> payload) async {
    final res = await _client
        .post(
          await _uri('pedidos'),
          headers: await _headers(),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo subir el pedido.'),
          statusCode: res.statusCode);
    }
    return body['id'] as int?;
  }

  /// Sube una cobranza. Devuelve el id del `Receipt` (Borrador) creado en el ERP.
  Future<int?> pushCobranza(Map<String, dynamic> payload) async {
    final res = await _client
        .post(
          await _uri('cobranzas'),
          headers: await _headers(),
          body: jsonEncode(payload),
        )
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo subir la cobranza.'),
          statusCode: res.statusCode);
    }
    return body['id'] as int?;
  }

  /// Da de alta un cliente en el ERP (queda pendiente de revisión). Devuelve
  /// el id real del Customer.
  Future<int?> pushCliente(Map<String, dynamic> payload) async {
    final res = await _client
        .post(await _uri('clientes'),
            headers: await _headers(), body: jsonEncode(payload))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo crear el cliente.'),
          statusCode: res.statusCode);
    }
    return body['id'] as int?;
  }

  /// Da de alta un artículo provisorio en el ERP. Devuelve el id real del
  /// Product (inactivo hasta que el admin lo confirme).
  Future<int?> pushArticulo(Map<String, dynamic> payload) async {
    final res = await _client
        .post(await _uri('articulos'),
            headers: await _headers(), body: jsonEncode(payload))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo crear el artículo.'),
          statusCode: res.statusCode);
    }
    return body['id'] as int?;
  }

  /// Propone un ajuste de stock (conteo). Devuelve `{id, diferenciaSugerida}`.
  Future<Map<String, dynamic>> pushAjusteStock(Map<String, dynamic> payload) async {
    final res = await _client
        .post(await _uri('stock/ajustes'),
            headers: await _headers(), body: jsonEncode(payload))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo enviar el ajuste de stock.'),
          statusCode: res.statusCode);
    }
    return body;
  }

  /// Propone una orden de compra. Devuelve el id de la propuesta (pendiente
  /// de aprobación en el ERP).
  Future<int?> pushOrdenCompra(Map<String, dynamic> payload) async {
    final res = await _client
        .post(await _uri('ordenes-compra'),
            headers: await _headers(), body: jsonEncode(payload))
        .timeout(_timeout);
    final body = _decode(res);
    if (res.statusCode != 200) {
      throw ApiException(_errorMessage(body, 'No se pudo enviar la orden de compra.'),
          statusCode: res.statusCode);
    }
    return body['id'] as int?;
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
