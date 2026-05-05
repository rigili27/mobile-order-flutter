import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_file_manager.dart';
import '../../core/ftp/ftp_client_service.dart';
import '../../data/repositories/parametros_repository.dart';

enum FtpOpState { idle, connecting, transferring, done, error }

class FtpProvider extends ChangeNotifier {
  final _fileManager = DatabaseFileManager.instance;
  final _paramRepo = ParametrosRepository();

  static const _keyUser = 'ftp_user';
  static const _keyPass = 'ftp_pass';

  String _ftpAddress = '';
  String _ftpUser = 'ftp';
  String _ftpPass = '1234';
  FtpOpState _opState = FtpOpState.idle;
  String? _statusMessage;

  String get ftpAddress => _ftpAddress;
  String get ftpUser => _ftpUser;
  String get ftpPass => _ftpPass;
  FtpOpState get opState => _opState;
  String? get statusMessage => _statusMessage;
  bool get isBusy =>
      _opState == FtpOpState.connecting || _opState == FtpOpState.transferring;

  Future<void> loadConfig() async {
    try {
      final p = await _paramRepo.get();
      if (p.ftp.isNotEmpty) _ftpAddress = p.ftp;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    _ftpUser = prefs.getString(_keyUser) ?? 'ftp';
    _ftpPass = prefs.getString(_keyPass) ?? '1234';
    notifyListeners();
  }

  void setAddress(String v) {
    _ftpAddress = v;
    notifyListeners();
  }

  void setCredentials(String user, String pass) {
    _ftpUser = user;
    _ftpPass = pass;
    notifyListeners();
  }

  Future<void> saveFtpConfig() async {
    try {
      await _paramRepo.updateFtp(_ftpAddress);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyUser, _ftpUser);
      await prefs.setString(_keyPass, _ftpPass);
      _statusMessage = 'Configuración FTP guardada.';
    } catch (e) {
      _statusMessage = 'Error al guardar: $e';
    }
    notifyListeners();
  }

  /// Verifica la conexión sin transferir archivos.
  Future<bool> testConnection() async {
    if (_ftpAddress.trim().isEmpty) {
      _statusMessage = 'Configurá la dirección IP del servidor FTP primero.';
      notifyListeners();
      return false;
    }
    _setOp(FtpOpState.connecting, 'Probando conexión con $_ftpAddress...');
    final client = FtpClientService.fromAddress(_ftpAddress, _ftpUser, _ftpPass);
    try {
      await client.testConnection();
      _setOp(FtpOpState.done, 'Conexión exitosa. Credenciales correctas.');
      return true;
    } catch (e) {
      _setOp(FtpOpState.error, '$e');
      return false;
    }
  }

  /// Descarga moviles.db desde el servidor FTP de la PC.
  Future<bool> importFromPc() async {
    if (_ftpAddress.trim().isEmpty) {
      _statusMessage = 'Configurá la dirección IP del servidor FTP primero.';
      notifyListeners();
      return false;
    }
    _setOp(FtpOpState.connecting, 'Conectando a $_ftpAddress...');

    final client =
        FtpClientService.fromAddress(_ftpAddress, _ftpUser, _ftpPass);
    try {
      await client.connect();
      _setOp(FtpOpState.transferring, 'Descargando moviles.db...');
      final tempPath = await _fileManager.tempPath;
      await client.downloadFile('moviles.db', tempPath);
    } catch (e) {
      await client.disconnect().catchError((_) {});
      _setOp(FtpOpState.error, 'Error FTP: $e');
      return false;
    }
    await client.disconnect().catchError((_) {});

    _setOp(FtpOpState.transferring, 'Validando e importando base de datos...');
    final result = await _fileManager.importFromTemp();
    if (result.ok) {
      _setOp(FtpOpState.done, 'Base de datos importada correctamente.');
      return true;
    } else {
      _setOp(FtpOpState.error, 'Error al importar: ${result.errorMessage}');
      return false;
    }
  }

  /// Sube moviles.db al servidor FTP de la PC.
  Future<bool> exportToPc() async {
    if (_ftpAddress.trim().isEmpty) {
      _statusMessage = 'Configurá la dirección IP del servidor FTP primero.';
      notifyListeners();
      return false;
    }
    _setOp(FtpOpState.connecting, 'Preparando exportación...');

    String exportFilePath;
    try {
      final exportFile = await _fileManager.prepareExport();
      exportFilePath = exportFile.path;
    } catch (e) {
      _setOp(FtpOpState.error, 'Error al crear copia de exportación: $e');
      return false;
    }

    _setOp(FtpOpState.connecting, 'Conectando a $_ftpAddress...');
    final client =
        FtpClientService.fromAddress(_ftpAddress, _ftpUser, _ftpPass);
    try {
      await client.connect();
      _setOp(FtpOpState.transferring, 'Subiendo base de datos...');
      await client.uploadFile(exportFilePath, 'moviles.db');
    } catch (e) {
      await client.disconnect().catchError((_) {});
      _setOp(FtpOpState.error, 'Error FTP: $e');
      return false;
    }
    await client.disconnect().catchError((_) {});

    _setOp(FtpOpState.done, 'Base de datos exportada correctamente.');
    return true;
  }

  void reset() {
    _opState = FtpOpState.idle;
    _statusMessage = null;
    notifyListeners();
  }

  void _setOp(FtpOpState state, String msg) {
    _opState = state;
    _statusMessage = msg;
    notifyListeners();
  }
}
