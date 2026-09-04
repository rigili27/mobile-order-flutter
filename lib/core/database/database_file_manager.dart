import 'dart:io';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../app_mode.dart';
import 'database_helper.dart';
import 'orden_preparacion_database_helper.dart';

class DatabaseFileManager {
  DatabaseFileManager._();
  static final DatabaseFileManager instance = DatabaseFileManager._();

  Future<String> get _dir async => (await getApplicationDocumentsDirectory()).path;

  // Modo WiFi: moviles.db / backup_moviles.db / temp.db.
  // Modo API: los mismos con sufijo _api (para no pisar la base de WiFi).
  String get _active => AppMode.isApi ? 'moviles_api.db' : 'moviles.db';
  String get _backup => AppMode.isApi ? 'backup_moviles_api.db' : 'backup_moviles.db';
  String get _temp => AppMode.isApi ? 'temp_moviles_api.db' : 'temp.db';

  Future<String> get activePath async => join(await _dir, _active);
  Future<String> get backupPath async => join(await _dir, _backup);
  Future<String> get tempPath async => join(await _dir, _temp);

  /// Crea una copia de la DB activa en el directorio temporal del sistema.
  /// El archivo se llama moviles.db para que al compartir/exportar tenga el nombre correcto.
  Future<File> prepareExport() async {
    final src = await activePath;
    final tmpDir = await getTemporaryDirectory();
    final dst = join(tmpDir.path, 'moviles.db');
    return File(src).copy(dst);
  }

  /// Reemplaza la DB activa por el archivo recibido en tempPath.
  /// Secuencia segura: validar → backup → renombrar.
  Future<ImportResult> importFromTemp() async {
    final helper = DatabaseHelper.instance;
    final tmp = await tempPath;
    final active = await activePath;
    final backup = await backupPath;

    if (!await File(tmp).exists()) {
      return ImportResult.error('Archivo temporal no encontrado.');
    }

    final valid = await helper.validateDatabase(tmp);
    if (!valid) {
      await File(tmp).delete().catchError((_) {});
      return ImportResult.error('El archivo recibido no es una base de datos válida.');
    }

    await helper.close();

    try {
      // Solo hacer backup si existe una DB activa (puede no haber en estado noDatabase).
      final activeFile = File(active);
      if (await activeFile.exists()) {
        final backupFile = File(backup);
        if (await backupFile.exists()) await backupFile.delete();
        await activeFile.rename(backup);
      }
      await File(tmp).rename(active);
    } catch (e) {
      // Intentar restaurar el backup si algo salió mal
      final backupFile = File(backup);
      if (!await File(active).exists() && await backupFile.exists()) {
        await backupFile.rename(active);
      }
      await helper.reopen();
      return ImportResult.error('Error al reemplazar la base de datos: $e');
    }

    await helper.reopen();
    await OrdenPreparacionDatabaseHelper.instance.clearOrders();
    return ImportResult.success();
  }

  Future<void> cleanTemp() async {
    final tmp = File(await tempPath);
    if (await tmp.exists()) await tmp.delete();
  }
}

class ImportResult {
  final bool ok;
  final String? errorMessage;

  const ImportResult._({required this.ok, this.errorMessage});

  factory ImportResult.success() => const ImportResult._(ok: true);
  factory ImportResult.error(String msg) => ImportResult._(ok: false, errorMessage: msg);
}
