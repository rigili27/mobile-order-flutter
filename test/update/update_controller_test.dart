// Copiado idéntico en las tres apps (test/update/): ver lib/core/update/.

import 'dart:convert';
import 'dart:io';

import 'package:mobile_order_flutter/core/update/update_client.dart';
import 'package:mobile_order_flutter/core/update/update_controller.dart';
import 'package:mobile_order_flutter/core/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'update_client_test.dart' show latestJson;

UpdateController controllerFor(
  Map<String, dynamic> json, {
  bool Function()? isBusy,
  bool Function()? canEnforceMandatory,
  List<String>? installed,
  Object? installError,
}) {
  return UpdateController(
    client: UpdateClient(
      app: 'firma',
      baseUrl: 'https://landlord.test',
      client: MockClient((_) async => http.Response(jsonEncode(json), 200)),
    ),
    isBusy: isBusy,
    busyReason: () => 'Hay una firma en curso.',
    canEnforceMandatory: canEnforceMandatory,
    currentVersion: () async => '2.0.0',
    abi: () async => 'arm64-v8a',
    platform: () => 'android',
    downloader: (download, onProgress) async {
      onProgress(1);
      return File(download.filename);
    },
    installer: (file) async {
      if (installError != null) throw installError;
      installed?.add(file.path);
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('con versión nueva muestra el aviso, y "Más tarde" lo oculta', () async {
    final updates = controllerFor(latestJson());

    await updates.check();

    expect(updates.installedVersion, '2.0.0');
    expect(updates.updateAvailable, isTrue);
    expect(updates.showBanner, isTrue);
    expect(updates.mustUpdate, isFalse);

    updates.dismiss();
    expect(updates.showBanner, isFalse);
  });

  test('sin versión nueva no avisa', () async {
    final updates = controllerFor(latestJson(update: false));

    await updates.check();

    expect(updates.updateAvailable, isFalse);
    expect(updates.showBanner, isFalse);
  });

  test('la versión mínima bloquea solo cuando la app lo permite', () async {
    var shiftOpen = true;
    final updates = controllerFor(latestJson(mandatory: true), canEnforceMandatory: () => !shiftOpen);

    await updates.check();
    expect(updates.mustUpdate, isFalse, reason: 'con turno abierto no se bloquea');
    expect(updates.showBanner, isTrue);

    shiftOpen = false;
    expect(updates.mustUpdate, isTrue);
    expect(updates.showBanner, isFalse);
  });

  test('instala la versión nueva', () async {
    final installed = <String>[];
    final updates = controllerFor(latestJson(), installed: installed);

    await updates.check();
    await updates.install();

    expect(installed, ['firma-2.1.0-arm64-v8a.apk']);
    expect(updates.status, UpdateStatus.idle);
    expect(updates.progress, 1);
  });

  test('no instala con una operación en curso', () async {
    final installed = <String>[];
    final updates = controllerFor(latestJson(), isBusy: () => true, installed: installed);

    await updates.check();
    await updates.install();

    expect(installed, isEmpty);
    expect(updates.status, UpdateStatus.error);
    expect(updates.errorMessage, 'Hay una firma en curso.');

    updates.clearError();
    expect(updates.status, UpdateStatus.idle);
  });

  test('un error al instalar queda como mensaje, no como excepción', () async {
    final updates = controllerFor(latestJson(), installError: UpdateInstallException('Android bloqueó la instalación.'));

    await updates.check();
    await updates.install();

    expect(updates.status, UpdateStatus.error);
    expect(updates.errorMessage, 'Android bloqueó la instalación.');
  });

  test('un error de red en la consulta automática se calla; en la manual se devuelve', () async {
    final updates = UpdateController(
      client: UpdateClient(app: 'firma', baseUrl: 'https://landlord.test', client: MockClient((_) async => http.Response('', 503))),
      currentVersion: () async => '2.0.0',
      abi: () async => null,
      platform: () => 'android',
    );

    expect(await updates.check(), isNull);
    expect(await updates.check(manual: true), contains('HTTP 503'));
    expect(updates.status, UpdateStatus.idle);
  });
}
