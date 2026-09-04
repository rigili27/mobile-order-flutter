import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/api/api_config.dart';
import '../../providers/api_sync_provider.dart';
import '../../providers/auth_provider.dart';

/// Card de "Servidor (API)" para la pantalla de Configuración. Convive con la
/// card de Transferencia WiFi; si no se configura nada, la app sigue en modo
/// WiFi como siempre.
class ApiServerCard extends StatefulWidget {
  /// Se llama tras una sincronización exitosa que pudo crear la base local
  /// (para que `_AppRoot` reintente `DatabaseHelper.init()`).
  final Future<void> Function()? onDatabaseReady;

  const ApiServerCard({super.key, this.onDatabaseReady});

  @override
  State<ApiServerCard> createState() => _ApiServerCardState();
}

class _ApiServerCardState extends State<ApiServerCard> {
  final _baseUrlCtrl = TextEditingController();
  final _tenantCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();

  bool _hasSession = false;
  bool _obscurePass = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _baseUrlCtrl.dispose();
    _tenantCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _baseUrlCtrl.text = await ApiConfig.baseUrl() ?? '';
    _tenantCtrl.text = await ApiConfig.tenant() ?? '';
    _hasSession = await ApiConfig.hasSession();
    if (mounted) {
      setState(() => _loading = false);
      await context.read<ApiSyncProvider>().refreshState();
    }
  }

  Future<void> _guardarServidor() async {
    final base = _baseUrlCtrl.text.trim();
    final tenant = _tenantCtrl.text.trim();
    if (base.isEmpty || tenant.isEmpty) {
      _snack('Completá la URL y el código de empresa.', error: true);
      return;
    }
    await ApiConfig.setServer(base, tenant);
    _snack('Servidor guardado.');
  }

  Future<void> _login() async {
    if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.isEmpty) {
      _snack('Ingresá email y contraseña.', error: true);
      return;
    }
    await _guardarServidor();
    if (!mounted) return;

    final ok = await context
        .read<AuthProvider>()
        .loginConApi(_emailCtrl.text, _passCtrl.text);
    if (!mounted) return;

    if (!ok) {
      _snack(context.read<AuthProvider>().errorMessage ?? 'No se pudo iniciar sesión.',
          error: true);
      return;
    }

    _passCtrl.clear();
    setState(() => _hasSession = true);
    await _sincronizar();
  }

  Future<void> _sincronizar() async {
    final sync = context.read<ApiSyncProvider>();
    final ok = await sync.sincronizarCatalogo();
    if (!mounted) return;
    if (ok) {
      _snack('Catálogo sincronizado.');
      await widget.onDatabaseReady?.call();
    } else {
      _snack(sync.errorMessage ?? 'No se pudo sincronizar.', error: true);
    }
  }

  Future<void> _cerrarSesion() async {
    await context.read<AuthProvider>().logout();
    if (!mounted) return;
    setState(() => _hasSession = false);
    _snack('Sesión cerrada.');
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red : Colors.green,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<ApiSyncProvider>();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Sincroniza clientes, artículos y precios directamente con '
              'GestionERP, y sube los pedidos al servidor. Alternativa a la '
              'transferencia por WiFi.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: Padding(
                padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
            else ...[
              TextField(
                controller: _baseUrlCtrl,
                enabled: !_hasSession,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'URL del servidor',
                  hintText: 'https://erp.miempresa.com',
                  prefixIcon: Icon(Icons.dns),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _tenantCtrl,
                enabled: !_hasSession,
                decoration: const InputDecoration(
                  labelText: 'Código de empresa',
                  hintText: 'miempresa',
                  prefixIcon: Icon(Icons.badge),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (!_hasSession) ...[
                TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.person),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    labelText: 'Contraseña',
                    prefixIcon: const Icon(Icons.lock),
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass
                          ? Icons.visibility
                          : Icons.visibility_off),
                      onPressed: () =>
                          setState(() => _obscurePass = !_obscurePass),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: sync.busy ? null : _login,
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar sesión y sincronizar'),
                ),
              ] else ...[
                Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 18),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Sesión activa'
                        '${sync.lastSync != null ? ' · última sync ${_fecha(sync.lastSync!)}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: sync.busy ? null : _sincronizar,
                  icon: sync.status == ApiSyncStatus.syncing
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.sync),
                  label: Text(sync.status == ApiSyncStatus.syncing
                      ? 'Sincronizando…'
                      : 'Sincronizar catálogo ahora'),
                ),
                if (sync.pendientes > 0) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: sync.busy
                        ? null
                        : () async {
                            await context
                                .read<ApiSyncProvider>()
                                .reintentarPendientes();
                          },
                    icon: const Icon(Icons.upload_file),
                    label: Text('Reintentar envíos pendientes (${sync.pendientes})'),
                  ),
                ],
                if (sync.advertencias.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      border: Border.all(color: Colors.amber.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 16, color: Colors.amber.shade800),
                          const SizedBox(width: 6),
                          Text('Avisos de la última sincronización',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.amber.shade900)),
                        ]),
                        const SizedBox(height: 4),
                        for (final a in sync.advertencias)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('• $a',
                                style: const TextStyle(fontSize: 11)),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: sync.busy ? null : _cerrarSesion,
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Cerrar sesión API'),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _fecha(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}
