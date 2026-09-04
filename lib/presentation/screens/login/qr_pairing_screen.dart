import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../providers/api_sync_provider.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';

/// Escaneo del QR de acceso generado por el ERP (Preventa → Vendedores).
/// Deja la sesión del vendedor abierta sin pedir usuario ni contraseña.
class QrPairingScreen extends StatefulWidget {
  const QrPairingScreen({super.key});

  @override
  State<QrPairingScreen> createState() => _QrPairingScreenState();
}

class _QrPairingScreenState extends State<QrPairingScreen> {
  bool _permitido = false;
  bool _procesando = false;
  bool _sesionLista = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _pedirPermiso();
  }

  Future<void> _pedirPermiso() async {
    final status = await Permission.camera.request();
    if (mounted) setState(() => _permitido = status.isGranted);
  }

  Future<void> _reintentarSync() async {
    setState(() {
      _procesando = true;
      _error = null;
    });
    final ok = await context.read<ApiSyncProvider>().sincronizarCatalogo();
    if (!mounted) return;
    if (ok) {
      _irAlHome();
    } else {
      setState(() {
        _procesando = false;
        _error =
            'Sigue fallando la sincronización. Podés entrar igual y reintentar desde el Home.';
      });
    }
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_procesando || _sesionLista) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null) return;

    Map<String, dynamic> data;
    try {
      data = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _error = 'El código escaneado no es un QR de acceso válido.');
      return;
    }

    final url = data['url'] as String?;
    final tenant = data['tenant'] as String?;
    final code = data['code'] as String?;
    if (data['v'] != 1 || url == null || tenant == null || code == null) {
      setState(() => _error = 'El QR no tiene el formato esperado.');
      return;
    }

    setState(() {
      _procesando = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final ok = await auth.adoptarSesionQr(baseUrl: url, tenant: tenant, code: code);
    if (!mounted) return;

    if (!ok) {
      setState(() {
        _procesando = false;
        _error = auth.errorMessage ?? 'No se pudo vincular el dispositivo.';
      });
      return;
    }

    final sync = context.read<ApiSyncProvider>();
    final ok2 = await sync.sincronizarCatalogo();
    if (!mounted) return;

    if (!ok2) {
      // La sesión ya quedó válida; solo falló el catálogo. Ofrecemos entrar
      // igual (el Home reintenta solo) o reintentar acá.
      setState(() {
        _procesando = false;
        _sesionLista = true;
        _error =
            'Sesión iniciada, pero no se pudo traer el catálogo: ${sync.errorMessage ?? 'error de red'}.';
      });
      return;
    }

    _irAlHome();
  }

  void _irAlHome() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Escanear QR de acceso')),
      body: Column(
        children: [
          Expanded(
            child: !_permitido
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Necesitamos permiso de cámara para escanear el QR.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      MobileScanner(onDetect: _onDetect),
                      if (_procesando)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Vinculando…',
                                    style: TextStyle(color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
          if (_error != null)
            Container(
              width: double.infinity,
              color: Colors.red.shade50,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(_error!, style: TextStyle(color: Colors.red.shade900)),
                  if (_sesionLista) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _procesando ? null : _reintentarSync,
                          child: const Text('Reintentar'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _procesando ? null : _irAlHome,
                          child: const Text('Entrar igual'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Pedí a administración el QR desde Preventa → Vendedores.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}
