// Copiado idéntico en las tres apps (test/update/): ver lib/core/update/.

import 'dart:convert';

import 'package:mobile_order_flutter/core/update/update_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> latestJson({bool update = true, bool mandatory = false}) => {
      'app': 'firma',
      'platform': 'android',
      'channel': 'beta',
      'latest': {
        'version': '2.1.0',
        'version_code': 20100,
        'notes': 'Arreglos',
        'published_at': '2026-09-30T10:00:00-03:00',
        'min_supported_version': mandatory ? '2.1.0' : null,
        'download': {
          'url': 'https://landlord.test/api/apps/assets/1/download?signature=x',
          'filename': 'firma-2.1.0-arm64-v8a.apk',
          'abi': 'arm64-v8a',
          'sha256': 'AB' * 32,
          'size': 1234,
        },
      },
      'update_available': update,
      'mandatory': mandatory,
    };

void main() {
  test('arma la consulta al ERP y parsea la respuesta', () async {
    late Uri requested;
    final client = UpdateClient(
      app: 'firma',
      baseUrl: 'https://landlord.test/',
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode(latestJson()), 200);
      }),
    );

    final info = await client.fetchLatest(platform: 'android', currentVersion: '2.0.0', abi: 'arm64-v8a', tenant: 'acme');

    expect(requested.toString(), startsWith('https://landlord.test/api/apps/firma/latest?'));
    expect(requested.queryParameters, {'platform': 'android', 'current': '2.0.0', 'abi': 'arm64-v8a', 'tenant': 'acme'});
    expect(info.channel, 'beta');
    expect(info.updateAvailable, isTrue);
    expect(info.latest!.version, '2.1.0');
    expect(info.latest!.download.sha256, 'ab' * 32, reason: 'el sha256 se normaliza a minúsculas');
    expect(info.latest!.download.size, 1234);
  });

  test('sin versión publicada, latest es null', () async {
    final client = UpdateClient(
      app: 'firma',
      baseUrl: 'https://landlord.test',
      client: MockClient((_) async => http.Response(jsonEncode({'channel': 'stable', 'latest': null, 'update_available': false, 'mandatory': false}), 200)),
    );

    final info = await client.fetchLatest(platform: 'android', currentVersion: '2.0.0');

    expect(info.latest, isNull);
    expect(info.updateAvailable, isFalse);
  });

  test('un error HTTP o de red se informa como UpdateCheckException', () async {
    final error500 = UpdateClient(app: 'firma', baseUrl: 'https://landlord.test', client: MockClient((_) async => http.Response('', 500)));
    final offline = UpdateClient(app: 'firma', baseUrl: 'https://landlord.test', client: MockClient((_) async => throw Exception('sin red')));

    expect(() => error500.fetchLatest(platform: 'android', currentVersion: '2.0.0'), throwsA(isA<UpdateCheckException>()));
    expect(() => offline.fetchLatest(platform: 'android', currentVersion: '2.0.0'), throwsA(isA<UpdateCheckException>()));
  });

  test('sin URL configurada (build de desarrollo) no consulta nada', () async {
    final client = UpdateClient(app: 'firma', baseUrl: '', client: MockClient((_) async => fail('no debería consultar')));

    expect(client.isConfigured, isFalse);
    expect(() => client.fetchLatest(platform: 'android', currentVersion: '2.0.0'), throwsA(isA<UpdateCheckException>()));
  });

  test('solo acepta https, salvo la propia máquina en desarrollo', () {
    expect(isAllowedUpdateUri(Uri.parse('https://landlord.miempresa.com')), isTrue);
    expect(isAllowedUpdateUri(Uri.parse('http://landlord.localhost')), isTrue);
    expect(isAllowedUpdateUri(Uri.parse('http://127.0.0.1:8000')), isTrue);
    expect(isAllowedUpdateUri(Uri.parse('http://landlord.miempresa.com')), isFalse);
    expect(isAllowedUpdateUri(Uri.parse('ftp://landlord.miempresa.com')), isFalse);

    expect(UpdateClient(app: 'firma', baseUrl: 'http://landlord.miempresa.com').isConfigured, isFalse);
  });
}
