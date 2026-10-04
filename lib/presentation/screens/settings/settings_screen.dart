import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../../core/api/api_config.dart';
import '../../../data/models/parametros.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../core/update/update_controller.dart';
import '../../../core/update/update_widgets.dart';
import '../login/qr_pairing_screen.dart';
import 'api_server_screen.dart';
import 'database_screen.dart';
import 'settings_shared.dart';
import 'wifi_transfer_screen.dart';

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
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Parametros? params;
    if (!widget.noDatabase) {
      try {
        params = await ParametrosRepository().get();
      } catch (_) {}
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final apiMode = await ApiConfig.isConfigured();

    if (mounted) {
      setState(() {
        _params = params;
        _apiMode = apiMode;
        _appVersion = 'v${packageInfo.version}';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final upd = context.watch<UpdateController>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuración'),
        automaticallyImplyLeading: !widget.noDatabase,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Advertencia principal: sin base de datos ──────────────────────
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
                              ? 'La app todavía no sincronizó. Entrá a "Servidor API" '
                                  'más abajo y tocá "Sincronizar catálogo".'
                              : 'La app no tiene base de datos. Usá alguna de las '
                                  'opciones de "Conexión" para recibirla, o restaurá '
                                  'la base de datos de ejemplo más abajo.'),
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
            const SizedBox(height: 24),
          ],

          // ── App / Actualizaciones ────────────────────────────────────────
          SectionTitle('Aplicación'),
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
                  if (upd.updateAvailable)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Versión ${upd.latest!.version} disponible',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: upd.status == UpdateStatus.checking || upd.working
                        ? null
                        : () async {
                            final error = await upd.check(manual: true);
                            if (!context.mounted) return;
                            if (error != null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(error)),
                              );
                            } else if (upd.updateAvailable) {
                              await runUpdate(context, upd);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text('La app está actualizada.')),
                              );
                            }
                          },
                    icon: upd.status == UpdateStatus.checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.system_update_outlined),
                    label: Text(upd.status == UpdateStatus.checking
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

          // ── Empresa ──────────────────────────────────────────────────────
          if (_params != null && _params!.razonSocial.isNotEmpty) ...[
            SectionTitle('Empresa'),
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

          // ── Conexión: QR / Servidor API / Transferencia WiFi ──────────────
          // Tres formas alternativas de conectar la app con la PC/ERP — cada
          // una vive en su propia pantalla para no mostrar los tres
          // formularios a la vez.
          SectionTitle('Conexión'),
          SettingsNavCard(
            icon: Icons.qr_code_scanner,
            title: 'Escanear código QR',
            subtitle: 'Emparejar el celular apuntando la cámara al ERP',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QrPairingScreen()),
              );
              _load();
            },
          ),
          const SizedBox(height: 8),
          SettingsNavCard(
            icon: Icons.dns_outlined,
            title: 'Servidor API',
            subtitle: _apiMode
                ? 'Configurado — sincronizar o cerrar sesión'
                : 'Configurar manualmente URL y código de empresa',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        ApiServerScreen(onDatabaseReady: widget.onDatabaseReady)),
              );
              _load();
            },
          ),
          if (!_apiMode) ...[
            const SizedBox(height: 8),
            SettingsNavCard(
              icon: Icons.wifi,
              title: 'Transferencia WiFi',
              subtitle: 'Recibir la base de datos desde la PC por la red local',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => WifiTransferScreen(
                        onDatabaseReady: widget.onDatabaseReady)),
              ),
            ),
          ],
          const SizedBox(height: 16),

          // ── Base de datos ────────────────────────────────────────────────
          SectionTitle('Base de datos'),
          SettingsNavCard(
            icon: Icons.storage_outlined,
            title: 'Base de datos',
            subtitle: 'Compartir, archivos locales, zona de peligro',
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        DatabaseScreen(onDatabaseReady: widget.onDatabaseReady)),
              );
              _load();
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
