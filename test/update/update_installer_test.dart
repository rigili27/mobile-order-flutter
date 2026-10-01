// Copiado idéntico en las tres apps (test/update/): ver lib/core/update/.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:mobile_order_flutter/core/update/update_info.dart';
import 'package:mobile_order_flutter/core/update/update_installer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() async => dir = await Directory.systemTemp.createTemp('update_test'));
  tearDown(() async => dir.delete(recursive: true));

  ReleaseDownload downloadFor(List<int> bytes, {String? sha, int? size}) => ReleaseDownload(
        url: 'https://landlord.test/x',
        filename: 'app.apk',
        sha256: sha ?? sha256.convert(bytes).toString(),
        size: size ?? bytes.length,
      );

  test('acepta un archivo con el tamaño y el sha256 informados', () async {
    final bytes = List<int>.generate(4096, (i) => i % 256);
    final file = await File('${dir.path}/app.apk').writeAsBytes(bytes);

    await verifyDownloadedFile(file, downloadFor(bytes));

    expect(await file.exists(), isTrue);
  });

  test('rechaza y borra un archivo alterado o cortado', () async {
    final bytes = List<int>.generate(4096, (i) => i % 256);

    final altered = await File('${dir.path}/a.apk').writeAsBytes(bytes);
    await expectLater(verifyDownloadedFile(altered, downloadFor(bytes, sha: '0' * 64)), throwsA(isA<UpdateInstallException>()));
    expect(await altered.exists(), isFalse);

    final truncated = await File('${dir.path}/b.apk').writeAsBytes(bytes.sublist(0, 100));
    await expectLater(verifyDownloadedFile(truncated, downloadFor(bytes)), throwsA(isA<UpdateInstallException>()));
    expect(await truncated.exists(), isFalse);
  });

  test('el nombre del archivo nunca puede ser una ruta', () {
    expect(safeFilename('firma-2.1.0-arm64-v8a.apk'), 'firma-2.1.0-arm64-v8a.apk');
    for (final bad in ['../../.bashrc', '/etc/passwd', 'a/b.apk', '..', '.oculto', r'C:\x.exe', '']) {
      expect(() => safeFilename(bad), throwsA(isA<UpdateInstallException>()), reason: bad);
    }
  });

  test('no descarga por http contra un servidor que no es la propia máquina', () async {
    final download = downloadFor([1, 2, 3]);
    final insecure = ReleaseDownload(url: 'http://landlord.miempresa.com/x', filename: download.filename, sha256: download.sha256, size: download.size);

    await expectLater(downloadRelease(insecure), throwsA(isA<UpdateInstallException>()));
  });
}
