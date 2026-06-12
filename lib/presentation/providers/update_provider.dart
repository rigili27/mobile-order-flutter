import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/services/update_service.dart';

enum UpdateState { idle, checking, updateAvailable, downloading, error }

class UpdateProvider extends ChangeNotifier {
  UpdateState _state = UpdateState.idle;
  UpdateInfo? _updateInfo;
  double _downloadProgress = 0.0;
  String? _errorMessage;

  UpdateState get state => _state;
  UpdateInfo? get updateInfo => _updateInfo;
  double get downloadProgress => _downloadProgress;
  String? get errorMessage => _errorMessage;

  Future<void> checkForUpdate() async {
    if (_state == UpdateState.checking || _state == UpdateState.downloading) {
      return;
    }
    _state = UpdateState.checking;
    _updateInfo = null;
    _errorMessage = null;
    notifyListeners();

    try {
      final info = await PackageInfo.fromPlatform();
      final update = await UpdateService.instance.checkForUpdate(info.version);
      _updateInfo = update;
      _state = update != null ? UpdateState.updateAvailable : UpdateState.idle;
    } catch (_) {
      _state = UpdateState.idle;
    }
    notifyListeners();
  }

  Future<void> downloadAndInstall() async {
    if (_updateInfo == null) return;

    final status = await Permission.requestInstallPackages.request();
    if (!status.isGranted) {
      _errorMessage = 'Se necesita permiso para instalar aplicaciones.';
      _state = UpdateState.error;
      notifyListeners();
      return;
    }

    _state = UpdateState.downloading;
    _downloadProgress = 0;
    notifyListeners();

    try {
      final File apkFile = await UpdateService.instance.downloadApk(
        _updateInfo!,
        (progress) {
          _downloadProgress = progress;
          notifyListeners();
        },
      );
      await OpenFile.open(apkFile.path);
      _state = UpdateState.updateAvailable;
    } catch (e) {
      _errorMessage = 'Error al descargar: $e';
      _state = UpdateState.error;
    }
    notifyListeners();
  }

  void reset() {
    _state = UpdateState.idle;
    _updateInfo = null;
    _downloadProgress = 0;
    _errorMessage = null;
    notifyListeners();
  }
}
