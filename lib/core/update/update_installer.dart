// Copiado idéntico en firma-digital, mobile-order-flutter y
// kiosko-pos-flutter (lib/core/update/): un cambio acá va en las tres apps.

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

import 'update_info.dart';

class UpdateInstallException implements Exception {
  UpdateInstallException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Plataforma tal como la nombra el ERP (App\Enums\ReleasePlatform).
String currentPlatform() {
  if (Platform.isAndroid) return 'android';
  if (Platform.isWindows) return 'windows';
  if (Platform.isLinux) return 'linux';
  throw UnsupportedError('Plataforma sin actualizaciones: ${Platform.operatingSystem}');
}

/// ABI principal del equipo (ej. arm64-v8a), para bajar el APK de esa
/// arquitectura. El ERP cae al APK universal si no hay uno específico.
Future<String?> currentAbi() async {
  if (!Platform.isAndroid) return null;
  final abis = (await DeviceInfoPlugin().androidInfo).supportedAbis;
  return abis.isEmpty ? null : abis.first;
}

/// Descarga el instalador a un temporal, reportando progreso 0.0-1.0, y
/// verifica tamaño y sha256 contra lo que informó el ERP: un archivo
/// cortado o alterado nunca llega al instalador del sistema.
Future<File> downloadRelease(
  ReleaseDownload download, {
  void Function(double progress)? onProgress,
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  final http.StreamedResponse response;
  try {
    response = await httpClient.send(http.Request('GET', Uri.parse(download.url)));
  } catch (_) {
    throw UpdateInstallException('No se pudo descargar la actualización. Verificá la conexión a internet.');
  }

  if (response.statusCode != 200) {
    throw UpdateInstallException('La descarga falló (HTTP ${response.statusCode}). Probá de nuevo.');
  }

  final dir = Directory('${(await getTemporaryDirectory()).path}/updates');
  await dir.create(recursive: true);
  final file = File('${dir.path}/${download.filename}');
  final sink = file.openWrite();

  final total = download.size > 0 ? download.size : (response.contentLength ?? 0);
  var received = 0;
  try {
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call((received / total).clamp(0.0, 1.0));
    }
  } catch (_) {
    await sink.close();
    await file.delete().catchError((_) => file);
    throw UpdateInstallException('Se cortó la descarga. Probá de nuevo.');
  }
  await sink.close();

  await verifyDownloadedFile(file, download);

  return file;
}

Future<void> verifyDownloadedFile(File file, ReleaseDownload download) async {
  final length = await file.length();
  final digest = (await sha256.bind(file.openRead()).first).toString();

  if (length != download.size || digest != download.sha256) {
    await file.delete().catchError((_) => file);
    throw UpdateInstallException('El archivo descargado está incompleto o dañado. Probá de nuevo.');
  }
}

/// Abre el instalador del sistema. En Android el usuario confirma la
/// instalación (no hay forma de evitarlo sin MDM) y el sistema reinicia la
/// app al terminar. En Windows corre el Setup en silencio y cierra la app
/// (Inno Setup la vuelve a abrir). En Linux instala el .deb con pkexec.
Future<void> installRelease(File file) async {
  if (Platform.isAndroid) {
    final result = await OpenFilex.open(file.path, type: 'application/vnd.android.package-archive');
    if (result.type == ResultType.permissionDenied) {
      throw UpdateInstallException(
        'Android bloqueó la instalación. Activá "Permitir de esta fuente" para esta app y volvé a tocar "Actualizar".',
      );
    }
    if (result.type != ResultType.done) {
      throw UpdateInstallException('No se pudo abrir el instalador: ${result.message}');
    }
    return;
  }

  if (Platform.isWindows) {
    await Process.start(
      file.path,
      ['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS', '/RESTARTAPPLICATIONS'],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  if (Platform.isLinux) {
    final result = await Process.run('pkexec', ['apt-get', 'install', '-y', '--reinstall', file.path]);
    if (result.exitCode != 0) {
      throw UpdateInstallException(
        'No se pudo instalar la actualización (${result.exitCode}). Instalala a mano con: sudo apt install ${file.path}',
      );
    }
    return;
  }

  throw UpdateInstallException('Esta plataforma no admite actualizaciones automáticas.');
}
