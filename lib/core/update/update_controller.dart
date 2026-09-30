// Copiado idéntico en firma-digital, mobile-order-flutter y
// kiosko-pos-flutter (lib/core/update/): un cambio acá va en las tres apps.

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'update_client.dart';
import 'update_info.dart';
import 'update_installer.dart';

enum UpdateStatus { idle, checking, downloading, installing, error }

/// Estado de las actualizaciones de la app, sin depender de Provider ni de
/// Riverpod (es un ChangeNotifier: cada app lo expone como le resulte).
///
/// Consulta al ERP al arrancar, al volver a primer plano (como mucho cada
/// [minResumeInterval]) y cada [checkInterval]. Los errores de una consulta
/// automática se callan — un equipo sin internet simplemente no se entera
/// de la versión nueva hasta la próxima.
///
/// La app decide cuándo no se puede instalar ([isBusy], ej. una venta o una
/// firma en curso) y cuándo se puede bloquear por versión mínima
/// ([canEnforceMandatory], ej. Kiosko nunca a mitad de turno).
class UpdateController extends ChangeNotifier with WidgetsBindingObserver {
  UpdateController({
    required UpdateClient client,
    bool Function()? isBusy,
    String? Function()? busyReason,
    String? Function()? pendingWarning,
    Future<String?> Function()? tenant,
    bool Function()? canEnforceMandatory,
    Future<String> Function()? currentVersion,
    Future<String?> Function()? abi,
    String Function()? platform,
    Future<File> Function(ReleaseDownload download, void Function(double) onProgress)? downloader,
    Future<void> Function(File file)? installer,
    this.checkInterval = const Duration(hours: 6),
    this.minResumeInterval = const Duration(minutes: 30),
  })  : _client = client,
        _isBusy = isBusy ?? (() => false),
        _busyReason = busyReason ?? (() => null),
        _pendingWarning = pendingWarning ?? (() => null),
        _tenant = tenant ?? (() async => null),
        _canEnforceMandatory = canEnforceMandatory ?? (() => true),
        _currentVersion = currentVersion ?? _packageVersion,
        _abi = abi ?? currentAbi,
        _platform = platform ?? currentPlatform,
        _downloader = downloader ?? ((d, onProgress) => downloadRelease(d, onProgress: onProgress)),
        _installer = installer ?? installRelease;

  final UpdateClient _client;
  final bool Function() _isBusy;
  final String? Function() _busyReason;
  final String? Function() _pendingWarning;
  final Future<String?> Function() _tenant;
  final bool Function() _canEnforceMandatory;
  final Future<String> Function() _currentVersion;
  final Future<String?> Function() _abi;
  final String Function() _platform;
  final Future<File> Function(ReleaseDownload, void Function(double)) _downloader;
  final Future<void> Function(File) _installer;
  final Duration checkInterval;
  final Duration minResumeInterval;

  Timer? _timer;
  DateTime? _lastCheck;
  String? _dismissedVersion;

  UpdateStatus status = UpdateStatus.idle;
  UpdateInfo? info;
  String? installedVersion;
  String? errorMessage;
  double progress = 0;

  static Future<String> _packageVersion() async => (await PackageInfo.fromPlatform()).version;

  bool get isConfigured => _client.isConfigured;

  ReleaseInfo? get latest => info?.latest;

  bool get updateAvailable => info?.updateAvailable == true && info?.latest != null;

  /// Hay que bloquear la app hasta actualizar: la versión instalada está
  /// por debajo de la mínima y la app dice que ahora se puede bloquear.
  bool get mustUpdate => updateAvailable && info!.mandatory && _canEnforceMandatory();

  /// Se muestra el aviso: hay versión nueva y no se la descartó con "Más
  /// tarde" en esta sesión (una versión todavía más nueva vuelve a avisar).
  bool get showBanner => updateAvailable && !mustUpdate && _dismissedVersion != latest!.version;

  bool get busy => _isBusy();

  String? get busyReason => _busyReason();

  String? get pendingWarning => _pendingWarning();

  bool get working => status == UpdateStatus.downloading || status == UpdateStatus.installing;

  void start() {
    if (!isConfigured) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(checkInterval, (_) => check());
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final last = _lastCheck;
    if (last == null || DateTime.now().difference(last) >= minResumeInterval) {
      check();
    }
  }

  /// Consulta al ERP. Con [manual] (botón "Buscar actualización") devuelve
  /// el error para mostrarlo; en automático lo calla.
  Future<String?> check({bool manual = false}) async {
    if (!isConfigured) {
      return manual ? 'Este build no tiene configurado el servidor de actualizaciones.' : null;
    }
    if (status == UpdateStatus.checking || working) return null;

    status = UpdateStatus.checking;
    notifyListeners();

    try {
      installedVersion ??= await _currentVersion();
      info = await _client.fetchLatest(
        platform: _platform(),
        currentVersion: installedVersion!,
        abi: await _abi(),
        tenant: await _tenant(),
      );
      _lastCheck = DateTime.now();
      errorMessage = null;
      status = UpdateStatus.idle;
      return null;
    } on UpdateCheckException catch (e) {
      status = UpdateStatus.idle;
      return manual ? e.message : null;
    } finally {
      notifyListeners();
    }
  }

  void dismiss() {
    _dismissedVersion = latest?.version;
    notifyListeners();
  }

  /// Baja e instala la versión nueva. Vuelve a consultar antes de bajar: el
  /// link de descarga del ERP vence a los pocos minutos, y en el medio pudo
  /// haberse publicado otra versión.
  Future<void> install() async {
    if (working) return;
    if (busy) {
      _fail(busyReason ?? 'Terminá la operación en curso antes de actualizar.');
      return;
    }

    final checkError = await check(manual: true);
    if (checkError != null) {
      _fail(checkError);
      return;
    }
    if (!updateAvailable) {
      _fail('Ya tenés la última versión.');
      return;
    }

    try {
      status = UpdateStatus.downloading;
      progress = 0;
      errorMessage = null;
      notifyListeners();

      final file = await _downloader(latest!.download, (p) {
        progress = p;
        notifyListeners();
      });

      status = UpdateStatus.installing;
      notifyListeners();

      await _installer(file);
      status = UpdateStatus.idle;
      notifyListeners();
    } on UpdateInstallException catch (e) {
      _fail(e.message);
    }
  }

  void clearError() {
    if (status != UpdateStatus.error) return;
    status = UpdateStatus.idle;
    errorMessage = null;
    notifyListeners();
  }

  void _fail(String message) {
    status = UpdateStatus.error;
    errorMessage = message;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
