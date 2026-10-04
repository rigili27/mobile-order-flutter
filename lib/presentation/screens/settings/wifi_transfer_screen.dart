import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/http/http_transfer_server.dart';
import '../../../data/models/parametros.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../providers/auth_provider.dart';
import 'settings_shared.dart';

/// El celular levanta un servidor HTTP local; la PC abre la dirección en el
/// navegador para bajar o subir `moviles.db`. Alternativa a "Servidor API"
/// y a "Escanear QR" — una app solo usa uno de los tres métodos.
class WifiTransferScreen extends StatefulWidget {
  final Future<void> Function()? onDatabaseReady;

  const WifiTransferScreen({super.key, this.onDatabaseReady});

  @override
  State<WifiTransferScreen> createState() => _WifiTransferScreenState();
}

class _WifiTransferScreenState extends State<WifiTransferScreen> {
  final _httpServer = HttpTransferServer();
  bool _httpRunning = false;
  bool _startingHttp = false;
  String _wifiIp = '…';
  Parametros? _params;
  String _pcPath = r'C:/ftp';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Parametros? params;
    try {
      params = await ParametrosRepository().get();
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _params = params;
        _pcPath = prefs.getString('http_pc_path') ?? r'C:/ftp';
      });
    }
  }

  @override
  void dispose() {
    _httpServer.stop();
    super.dispose();
  }

  Future<void> _startHttpServer() async {
    if (_startingHttp || _httpRunning) return;
    setState(() => _startingHttp = true);
    try {
      final ip = await NetworkInfo().getWifiIP();
      final vendorName = context.read<AuthProvider>().vendedor?.nombre ?? '';
      final packageInfo = await PackageInfo.fromPlatform();
      await _httpServer.start(
          pcPath: _pcPath,
          vendorName: vendorName,
          appVersion: 'v${packageInfo.version}',
          ordenPreparacion: _params?.ordenPreparacion ?? false,
          onImportSuccess: () => onDbChanged(widget.onDatabaseReady));
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transferencia WiFi')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle('Servidor WiFi'),
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
        ],
      ),
    );
  }
}
