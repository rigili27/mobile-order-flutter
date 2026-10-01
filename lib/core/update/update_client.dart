// Copiado idéntico en firma-digital, mobile-order-flutter y
// kiosko-pos-flutter (lib/core/update/): un cambio acá va en las tres apps.

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'update_info.dart';

/// URL del landlord del ERP (ej. https://landlord.midominio.com). La inyecta
/// el workflow de release con `--dart-define=ERP_UPDATES_URL=...`; en un
/// build de desarrollo sin ese define, las actualizaciones quedan apagadas.
const erpUpdatesUrl = String.fromEnvironment('ERP_UPDATES_URL');

/// Solo https: el instalador se ejecuta con permisos de administrador en
/// escritorio, así que nunca se baja por un canal que se pueda interceptar.
/// http se acepta solo contra la propia máquina (desarrollo local).
bool isAllowedUpdateUri(Uri uri) {
  if (uri.scheme == 'https') return true;
  final host = uri.host;
  return uri.scheme == 'http' && (host == 'localhost' || host == '127.0.0.1' || host.endsWith('.localhost'));
}

class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => message;
}

class UpdateClient {
  UpdateClient({required this.app, String baseUrl = erpUpdatesUrl, http.Client? client})
      : _baseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl,
        _client = client ?? http.Client();

  /// Clave de la app en el ERP: 'kiosko', 'movil' o 'firma'.
  final String app;
  final String _baseUrl;
  final http.Client _client;

  bool get isConfigured => _baseUrl.isNotEmpty && isAllowedUpdateUri(Uri.parse(_baseUrl));

  Future<UpdateInfo> fetchLatest({
    required String platform,
    required String currentVersion,
    String? abi,
    String? tenant,
  }) async {
    if (!isConfigured) {
      throw UpdateCheckException('Este build no tiene configurado el servidor de actualizaciones (o no es https).');
    }

    final uri = Uri.parse('$_baseUrl/api/apps/$app/latest').replace(queryParameters: {
      'platform': platform,
      'current': currentVersion,
      if (abi != null) 'abi': abi,
      if (tenant != null && tenant.isNotEmpty) 'tenant': tenant,
    });

    final http.Response response;
    try {
      response = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw UpdateCheckException('No se pudo consultar si hay actualizaciones. Verificá la conexión a internet.');
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException('El servidor de actualizaciones respondió con un error (HTTP ${response.statusCode}).');
    }

    return UpdateInfo.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }
}
