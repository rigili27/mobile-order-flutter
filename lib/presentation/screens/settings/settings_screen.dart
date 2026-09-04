import 'dart:io';
import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/api/api_config.dart';
import '../../../core/database/database_file_manager.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/orden_preparacion_database_helper.dart';
import '../../../app.dart';
import '../../../core/http/http_transfer_server.dart';
import '../../../data/models/parametros.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/ftp_provider.dart';
import '../../providers/update_provider.dart';
import '../../widgets/update_dialog.dart';
import '../login/login_screen.dart';
import 'api_server_card.dart';

class SettingsScreen extends StatefulWidget {
  /// Cuando true, la app no tiene DB y muestra la UI de "esperando base de datos".
  final bool noDatabase;
  final String? dbError;
  /// Callback que se llama cuando la DB fue recibida e inicializada correctamente.
  final Future<void> Function()? onDatabaseReady;

  const SettingsScreen({
    super.key,
    this.noDatabase = false,
    this.dbError,
    this.onDatabaseReady,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Parametros? _params;
  bool _apiMode = false;
  final _httpServer = HttpTransferServer();
  bool _httpRunning = false;
  bool _startingHttp = false;
  String _wifiIp = '…';
  List<_DbFileInfo> _dbFiles = [];
  String _appVersion = '';

  final _ftpIpCtrl = TextEditingController();
  final _ftpPortCtrl = TextEditingController(text: '2221');
  final _ftpUserCtrl = TextEditingController(text: 'ftp');
  final _ftpPassCtrl = TextEditingController(text: '1234');
  bool _ftpPassObscure = true;
  final _pcPathCtrl = TextEditingController(text: r'C:/ftp');

  String get _ftpAddress =>
      '${_ftpIpCtrl.text.trim()}:${_ftpPortCtrl.text.trim()}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Se llama siempre que la DB activa cambió (recibida por HTTP/FTP, borrada
  /// o restaurada desde assets). Corre el reinit que necesite el caller
  /// (`widget.onDatabaseReady`, p. ej. `DatabaseHelper.init()` en `_AppRoot`)
  /// y SIEMPRE fuerza logout + navegación a Login, sin importar qué usuario
  /// estaba logueado ni desde dónde se abrió esta pantalla.
  ///
  /// Usa `rootNavigatorKey` en vez de `context`/`this.context` en todos los
  /// pasos: si `widget.onDatabaseReady` viene de `_AppRoot` (arranque sin DB),
  /// puede disparar un rebuild que reemplaza esta misma pantalla (por ejemplo
  /// por LoginScreen) y desmonta nuestro propio BuildContext a mitad de
  /// camino. `rootNavigatorKey.currentContext` es el del Navigator raíz, que
  /// nunca se desmonta mientras la app corre.
  Future<void> _onDbChanged() async {
    try {
      await widget.onDatabaseReady?.call();
    } catch (_) {}
    try {
      await rootNavigatorKey.currentContext?.read<AuthProvider>().logout();
    } catch (_) {}
    rootNavigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _load() async {
    final ftp = context.read<FtpProvider>();
    await ftp.loadConfig();

    Parametros? params;
    if (!widget.noDatabase) {
      try {
        params = await ParametrosRepository().get();
      } catch (_) {}
    }

    final prefs = await SharedPreferences.getInstance();
    final pcPath = prefs.getString('http_pc_path') ?? r'C:/ftp';
    final packageInfo = await PackageInfo.fromPlatform();
    final apiMode = await ApiConfig.isConfigured();

    if (mounted) {
      setState(() {
        _params = params;
        _apiMode = apiMode;
        _appVersion = 'v${packageInfo.version}';
        final stored = ftp.ftpAddress;
        final parts = stored.split(':');
        _ftpIpCtrl.text = parts[0];
        if (parts.length > 1 && parts[1].isNotEmpty) _ftpPortCtrl.text = parts[1];
        _ftpUserCtrl.text = ftp.ftpUser;
        _ftpPassCtrl.text = ftp.ftpPass;
        _pcPathCtrl.text = pcPath;
      });
    }
    await _loadDbFiles();
  }

  Future<void> _loadDbFiles() async {
    final dir = (await getApplicationDocumentsDirectory()).path;
    final entries = [
      ('moviles.db', _apiMode ? 'Base WiFi' : 'Base activa'),
      ('backup_moviles.db', 'Respaldo WiFi'),
      ('moviles_api.db', _apiMode ? 'Base activa (API)' : 'Base API'),
      ('backup_moviles_api.db', 'Respaldo API'),
      ('movil_sync.db', 'Estado de sync'),
      if (_params?.ordenPreparacion ?? false)
        ('moviles_orden_preparacion.db', 'Órdenes Prep.'),
    ];
    final result = <_DbFileInfo>[];
    for (final (name, label) in entries) {
      final f = File(p.join(dir, name));
      if (await f.exists()) {
        final stat = await f.stat();
        result.add(_DbFileInfo(
            name: name, label: label, sizeBytes: stat.size, modified: stat.modified));
      }
    }
    if (mounted) setState(() => _dbFiles = result);
  }

  Future<void> _saveFtpAddress() async {
    final ftp = context.read<FtpProvider>();
    ftp.setAddress(_ftpAddress);
    ftp.setCredentials(_ftpUserCtrl.text.trim(), _ftpPassCtrl.text.trim());
    await ftp.saveFtpConfig();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Configuración FTP guardada.'),
            backgroundColor: Colors.green),
      );
    }
  }

  Future<void> _probarConexion() async {
    final ftp = context.read<FtpProvider>();
    ftp.reset();
    ftp.setAddress(_ftpAddress);
    ftp.setCredentials(_ftpUserCtrl.text.trim(), _ftpPassCtrl.text.trim());
    await ftp.testConnection();
  }

  Future<void> _importar() async {
    final ftp = context.read<FtpProvider>();
    ftp.reset();
    ftp.setAddress(_ftpAddress);
    ftp.setCredentials(_ftpUserCtrl.text.trim(), _ftpPassCtrl.text.trim());
    final ok = await ftp.importFromPc();
    if (ok) await _onDbChanged();
  }

  Future<void> _confirmarImportar() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orange),
          SizedBox(width: 8),
          Text('Importar base de datos'),
        ]),
        content: const Text(
          'Esta acción reemplazará todos los datos locales con los de la PC.\n\n'
          '⚠ Los pedidos que no hayas exportado se perderán.\n\n'
          '¿Querés continuar?',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.orange),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Importar')),
        ],
      ),
    );
    if (confirm == true) _importar();
  }

  void _hintImportar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mantené presionado para importar la base de datos.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  Future<void> _exportar() async {
    final ftp = context.read<FtpProvider>();
    ftp.reset();
    ftp.setAddress(_ftpAddress);
    ftp.setCredentials(_ftpUserCtrl.text.trim(), _ftpPassCtrl.text.trim());
    await ftp.exportToPc();
  }

  Future<void> _eliminarDB() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar base de datos'),
        content: const Text(
          '¿Estás seguro? Se eliminarán todos los datos locales. '
          'Necesitarás recibir una nueva base de datos desde la PC.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await DatabaseHelper.instance.deleteDatabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Base de datos eliminada.'),
            backgroundColor: Colors.orange),
      );
      await _onDbChanged();
    }
  }

  Future<void> _startHttpServer() async {
    if (_startingHttp || _httpRunning) return;
    setState(() => _startingHttp = true);
    try {
      final ip = await NetworkInfo().getWifiIP();
      final pcPath = _pcPathCtrl.text.trim().isEmpty ? r'C:/ftp' : _pcPathCtrl.text.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('http_pc_path', pcPath);
      final vendorName = context.read<AuthProvider>().vendedor?.nombre ?? '';
      final packageInfo = await PackageInfo.fromPlatform();
      await _httpServer.start(
          pcPath: pcPath,
          vendorName: vendorName,
          appVersion: 'v${packageInfo.version}',
          ordenPreparacion: _params?.ordenPreparacion ?? false,
          onImportSuccess: _onDbChanged);
      if (mounted) {
        setState(() {
          _httpRunning = true;
          _wifiIp = ip ?? '(sin WiFi)';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo iniciar el servidor WiFi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _startingHttp = false);
    }
  }

  Future<void> _stopHttpServer() async {
    try {
      await _httpServer.stop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al detener el servidor: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _httpRunning = false);
    }
  }

  Future<void> _compartirDB() async {
    try {
      final mgr = DatabaseFileManager.instance;
      final files = <XFile>[];

      final activePath = await mgr.activePath;
      if (await File(activePath).exists()) {
        final exportFile = await mgr.prepareExport();
        files.add(XFile(exportFile.path,
            mimeType: 'application/octet-stream', name: 'moviles.db'));
      }

      final backupPath = await mgr.backupPath;
      if (await File(backupPath).exists()) {
        files.add(XFile(backupPath,
            mimeType: 'application/octet-stream', name: 'backup_moviles.db'));
      }

      if (_params?.ordenPreparacion ?? false) {
        final ordenPath = await OrdenPreparacionDatabaseHelper.instance.dbPath;
        if (await File(ordenPath).exists()) {
          final tmpDir = await getTemporaryDirectory();
          final dst = p.join(tmpDir.path, 'moviles_orden_preparacion.db');
          final copy = await File(ordenPath).copy(dst);
          files.add(XFile(copy.path,
              mimeType: 'application/octet-stream',
              name: 'moviles_orden_preparacion.db'));
        }
      }

      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay base de datos para compartir.')),
          );
        }
        return;
      }

      await Share.shareXFiles(files, subject: 'Base de datos moviles');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al compartir: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _restaurarDesdeAssets() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar BD inicial'),
        content: const Text(
            'Se restaurará la base de datos de ejemplo incluida en la app. '
            'Los datos actuales se perderán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await DatabaseHelper.instance.deleteDatabase();
    await DatabaseHelper.instance.copyFromAssets();
    await _onDbChanged();
  }

  @override
  void dispose() {
    _httpServer.stop();
    _ftpIpCtrl.dispose();
    _ftpPortCtrl.dispose();
    _ftpUserCtrl.dispose();
    _ftpPassCtrl.dispose();
    _pcPathCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ftp = context.watch<FtpProvider>();
    final upd = context.watch<UpdateProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        automaticallyImplyLeading: !widget.noDatabase,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── App / Actualizaciones ────────────────────────────────────────
          _SectionTitle('Aplicación'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Versión instalada: ${_appVersion.isEmpty ? '…' : _appVersion}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                  if (upd.state == UpdateState.updateAvailable &&
                      upd.updateInfo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Versión ${upd.updateInfo!.version} disponible',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: upd.state == UpdateState.checking
                        ? null
                        : () async {
                            await upd.checkForUpdate();
                            if (!context.mounted) return;
                            final current = context.read<UpdateProvider>();
                            if (current.state == UpdateState.updateAvailable) {
                              showDialog(
                                context: context,
                                builder: (_) => const UpdateDialog(),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('La app está actualizada.')),
                              );
                            }
                          },
                    icon: upd.state == UpdateState.checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.system_update_outlined),
                    label: Text(upd.state == UpdateState.checking
                        ? 'Verificando...'
                        : 'Buscar actualización'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Servidor (API) ───────────────────────────────────────────────
          _SectionTitle('Servidor (API)'),
          ApiServerCard(onDatabaseReady: widget.onDatabaseReady),
          const SizedBox(height: 16),

          // ── Banner "sin base de datos" ───────────────────────────────────
          if (widget.noDatabase) ...[
            Card(
              color: Colors.orange.shade50,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.orange.shade300)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        size: 48, color: Colors.orange.shade700),
                    const SizedBox(height: 8),
                    Text(
                      widget.dbError != null
                          ? 'Error en la base de datos'
                          : 'Sin base de datos',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.orange.shade900),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.dbError ??
                          (_apiMode
                              ? 'La app todavía no sincronizó. Iniciá sesión en '
                                  '"Servidor (API)" y tocá "Sincronizar catálogo".'
                              : 'La app no tiene base de datos. Usá "Transferencia '
                                  'WiFi" para recibirla desde la PC, o restaurá la '
                                  'base de datos de ejemplo.'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (widget.dbError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.dbError!,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (!_apiMode) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _restaurarDesdeAssets,
                icon: const Icon(Icons.restore),
                label: const Text('Restaurar base de datos de ejemplo'),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white),
              ),
            ],
            const SizedBox(height: 24),
          ],

          // ── Empresa ──────────────────────────────────────────────────────
          if (_params != null && _params!.razonSocial.isNotEmpty) ...[
            _SectionTitle('Empresa'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_params!.razonSocial,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      if (_params!.domicilio.isNotEmpty)
                        Text(_params!.domicilio,
                            style: const TextStyle(fontSize: 13)),
                      if (_params!.nroCuit.isNotEmpty)
                        Text('CUIT: ${_params!.nroCuit}',
                            style: const TextStyle(fontSize: 13)),
                      if (_params!.cotizacion != 1)
                        Text(
                            'Cotización USD: \$${_params!.cotizacion.toStringAsFixed(2)}',
                            style: const TextStyle(fontSize: 13)),
                    ]),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Modo WiFi: servidor + compartir DB (oculto en modo API) ──────
          if (!_apiMode) ...[
          // ── Servidor WiFi (HTTP) ─────────────────────────────────────────
          _SectionTitle('Transferencia WiFi'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text(
                  'El celular levanta un servidor web. Abrí la dirección '
                  'en el navegador de la PC para bajar o subir la base de datos. '
                  'No requiere configuración de firewall.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                // TextField(
                //   controller: _pcPathCtrl,
                //   decoration: const InputDecoration(
                //     labelText: 'Ruta en la PC',
                //     hintText: r'C:/ftp',
                //     helperText: 'Carpeta donde se guarda moviles.db en la PC',
                //     prefixIcon: Icon(Icons.folder_outlined),
                //     border: OutlineInputBorder(),
                //   ),
                //   enabled: !_httpRunning,
                // ),
                const SizedBox(height: 12),
                if (_httpRunning) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Column(children: [
                      Row(children: [
                        Icon(Icons.circle, size: 10, color: Colors.green.shade700),
                        const SizedBox(width: 6),
                        Text('Servidor activo',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.green.shade800)),
                      ]),
                      const SizedBox(height: 8),
                      const Text('Abrí esta dirección en la PC:',
                          style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      SelectableText(
                        'http://$_wifiIp:${HttpTransferServer.defaultPort}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _stopHttpServer,
                    icon: const Icon(Icons.stop),
                    label: const Text('Detener servidor'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        backgroundColor: Colors.red.shade700,
                        foregroundColor: Colors.white),
                  ),
                ] else
                  ElevatedButton.icon(
                    onPressed: _startingHttp ? null : _startHttpServer,
                    icon: _startingHttp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.wifi),
                    label: Text(_startingHttp
                        ? 'Iniciando…'
                        : 'Iniciar servidor WiFi'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 44),
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Conexión FTP ─────────────────────────────────────────────────
          // _SectionTitle('Servidor FTP (PC)'),
          // Card(
          //   child: Padding(
          //     padding: const EdgeInsets.all(16),
          //     child: Column(
          //       crossAxisAlignment: CrossAxisAlignment.start,
          //       children: [
          //         const Text(
          //           'La PC corre el servidor FTP. Ingresá su IP y puerto.',
          //           style: TextStyle(fontSize: 12, color: Colors.grey),
          //         ),
          //         const SizedBox(height: 12),
          //         Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          //           Expanded(
          //             flex: 3,
          //             child: TextField(
          //               controller: _ftpIpCtrl,
          //               decoration: const InputDecoration(
          //                 labelText: 'IP del servidor',
          //                 hintText: '192.168.1.100',
          //                 prefixIcon: Icon(Icons.computer),
          //                 border: OutlineInputBorder(),
          //               ),
          //               keyboardType: TextInputType.number,
          //               textInputAction: TextInputAction.next,
          //               onChanged: (_) =>
          //                   context.read<FtpProvider>().setAddress(_ftpAddress),
          //             ),
          //           ),
          //           const SizedBox(width: 8),
          //           SizedBox(
          //             width: 90,
          //             child: TextField(
          //               controller: _ftpPortCtrl,
          //               decoration: const InputDecoration(
          //                 labelText: 'Puerto',
          //                 border: OutlineInputBorder(),
          //               ),
          //               keyboardType: TextInputType.number,
          //               textInputAction: TextInputAction.done,
          //               onSubmitted: (_) => _saveFtpAddress(),
          //               onChanged: (_) =>
          //                   context.read<FtpProvider>().setAddress(_ftpAddress),
          //             ),
          //           ),
          //         ]),
          //         const SizedBox(height: 10),
          //         Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          //           Expanded(
          //             child: TextField(
          //               controller: _ftpUserCtrl,
          //               decoration: const InputDecoration(
          //                 labelText: 'Usuario',
          //                 prefixIcon: Icon(Icons.person),
          //                 border: OutlineInputBorder(),
          //               ),
          //               textInputAction: TextInputAction.next,
          //             ),
          //           ),
          //           const SizedBox(width: 8),
          //           Expanded(
          //             child: TextField(
          //               controller: _ftpPassCtrl,
          //               decoration: InputDecoration(
          //                 labelText: 'Contraseña',
          //                 prefixIcon: const Icon(Icons.lock),
          //                 border: const OutlineInputBorder(),
          //                 suffixIcon: IconButton(
          //                   icon: Icon(_ftpPassObscure
          //                       ? Icons.visibility
          //                       : Icons.visibility_off),
          //                   onPressed: () => setState(
          //                       () => _ftpPassObscure = !_ftpPassObscure),
          //                 ),
          //               ),
          //               obscureText: _ftpPassObscure,
          //               textInputAction: TextInputAction.done,
          //               onSubmitted: (_) => _saveFtpAddress(),
          //             ),
          //           ),
          //         ]),
          //         const SizedBox(height: 12),
          //         Row(children: [
          //           Expanded(
          //             child: ElevatedButton.icon(
          //               onPressed: _saveFtpAddress,
          //               icon: const Icon(Icons.save),
          //               label: const Text('Guardar'),
          //               style: ElevatedButton.styleFrom(
          //                   minimumSize: const Size(0, 44)),
          //             ),
          //           ),
          //           const SizedBox(width: 8),
          //           Expanded(
          //             child: ElevatedButton.icon(
          //               onPressed: ftp.isBusy ? null : _probarConexion,
          //               icon: const Icon(Icons.wifi_find),
          //               label: const Text('Probar'),
          //               style: ElevatedButton.styleFrom(
          //                 minimumSize: const Size(0, 44),
          //                 backgroundColor: Colors.teal.shade700,
          //                 foregroundColor: Colors.white,
          //               ),
          //             ),
          //           ),
          //         ]),
          //       ],
          //     ),
          //   ),
          // ),
          // const SizedBox(height: 16),

          // ── Estado de operación FTP ──────────────────────────────────────
          if (ftp.statusMessage != null)
            Card(
              color: _ftpStateColor(ftp.opState).withValues(alpha: 0.1),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(children: [
                  if (ftp.isBusy)
                    const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                  else
                    Icon(_ftpStateIcon(ftp.opState),
                        color: _ftpStateColor(ftp.opState)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(ftp.statusMessage!,
                        style: const TextStyle(fontSize: 13)),
                  ),
                ]),
              ),
            ),

          const SizedBox(height: 16),

          // ── Importar / Exportar ──────────────────────────────────────────
          _SectionTitle('Base de datos'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // const Text(
                //   'IMPORTAR: Conecta al FTP de la PC y descarga la base de datos.',
                //   style: TextStyle(fontSize: 12, color: Colors.grey),
                // ),
                // const SizedBox(height: 10),
                // ElevatedButton.icon(
                //   onPressed: ftp.isBusy ? null : _hintImportar,
                //   onLongPress: ftp.isBusy ? null : _confirmarImportar,
                //   icon: const Icon(Icons.download),
                //   label: const Text('Importar desde PC'),
                //   style: ElevatedButton.styleFrom(
                //       minimumSize: const Size(double.infinity, 44),
                //       backgroundColor: Colors.blue.shade700,
                //       foregroundColor: Colors.white),
                // ),
                // const Divider(height: 24),
                // const Text(
                //   'EXPORTAR: Sube la base de datos al FTP de la PC.',
                //   style: TextStyle(fontSize: 12, color: Colors.grey),
                // ),
                // const SizedBox(height: 10),
                // ElevatedButton.icon(
                //   onPressed: (ftp.isBusy || widget.noDatabase)
                //       ? null
                //       : _exportar,
                //   icon: const Icon(Icons.upload),
                //   label: const Text('Exportar a PC'),
                //   style: ElevatedButton.styleFrom(
                //       minimumSize: const Size(double.infinity, 44),
                //       backgroundColor: Colors.green.shade700,
                //       foregroundColor: Colors.white),
                // ),
                // const Divider(height: 24),
                const Text(
                  'COMPARTIR: Envía la base de datos por WhatsApp u otra app.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _compartirDB,
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir base de datos'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 24),
          ], // fin modo WiFi

          // ── Archivos de base de datos ────────────────────────────────────
          ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(child: _SectionTitle('Archivos de base de datos')),
                TextButton.icon(
                  onPressed: _loadDbFiles,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Actualizar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            Card(
              child: _dbFiles.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No se encontraron archivos.',
                          style: TextStyle(fontSize: 13, color: Colors.grey)),
                    )
                  : Column(
                      children: _dbFiles
                          .map((f) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.storage_outlined,
                                    color: Colors.blueGrey),
                                title: Text(f.name,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    '${_fmtDate(f.modified)} · ${_fmtSize(f.sizeBytes)}',
                                    style: const TextStyle(fontSize: 11)),
                                trailing: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                      color: Colors.blueGrey.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.blueGrey.shade200)),
                                  child: Text(f.label,
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.blueGrey.shade700)),
                                ),
                              ))
                          .toList(),
                    ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Zona de peligro ──────────────────────────────────────────────
          _SectionTitle('Zona de peligro'),
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.red.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(
                  _apiMode
                      ? 'Elimina la base local de la API (moviles_api.db). '
                          'Tras esto hay que volver a sincronizar. No toca la base WiFi.'
                      : 'Elimina la base de datos local. '
                          'Útil si la DB está corrupta y no podés ingresar.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _eliminarDB,
                  icon: const Icon(Icons.delete_forever),
                  label: Text(_apiMode
                      ? 'Eliminar base local (API)'
                      : 'Eliminar base de datos'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Color _ftpStateColor(FtpOpState s) => switch (s) {
        FtpOpState.done => Colors.green,
        FtpOpState.error => Colors.red,
        _ => Colors.blue,
      };

  IconData _ftpStateIcon(FtpOpState s) => switch (s) {
        FtpOpState.done => Icons.check_circle,
        FtpOpState.error => Icons.error,
        _ => Icons.info,
      };
}

class _DbFileInfo {
  final String name;
  final String label;
  final int sizeBytes;
  final DateTime modified;
  const _DbFileInfo(
      {required this.name,
      required this.label,
      required this.sizeBytes,
      required this.modified});
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
