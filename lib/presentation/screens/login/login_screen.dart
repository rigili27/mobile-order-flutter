import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import '../../../core/api/api_config.dart';
import '../../../data/models/vendedor.dart';
import '../../../data/repositories/vendedor_repository.dart';
import '../../providers/api_sync_provider.dart';
import '../../providers/auth_provider.dart';
import '../home/home_screen.dart';
import 'qr_pairing_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _repo = VendedorRepository();
  final _claveCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  List<Vendedor> _vendors = [];
  Vendedor? _selected;
  bool _loadingVendors = true;
  bool _obscureClave = true;
  String _version = '';
  bool _apiMode = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadMode();
    _loadVersion();
  }

  Future<void> _loadMode() async {
    final apiMode = await ApiConfig.isConfigured();
    if (mounted) setState(() => _apiMode = apiMode);
    if (!apiMode) _loadVendors();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _version = 'v${info.version}');
  }

  Future<void> _loadVendors() async {
    try {
      final vendors = await _repo.getAll();
      setState(() {
        _vendors = vendors;
        // Pre-select first vendor if only one
        if (vendors.length == 1) _selected = vendors.first;
        _loadingVendors = false;
      });
    } catch (_) {
      setState(() => _loadingVendors = false);
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _submitting = true);
    try {
      if (_apiMode) {
        final ok = await context
            .read<AuthProvider>()
            .loginConApi(_emailCtrl.text, _claveCtrl.text);
        if (!ok || !mounted) return;
        // Trae el catálogo actualizado tras iniciar sesión.
        final synced =
            await context.read<ApiSyncProvider>().sincronizarCatalogo();
        if (!mounted) return;
        if (!synced) {
          final msg = context.read<ApiSyncProvider>().errorMessage;
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Sesión iniciada, pero falló la sincronización: ${msg ?? 'error de red'}'),
          ));
        }
      } else {
        if (_selected == null) return;
        final ok = await context
            .read<AuthProvider>()
            .loginVendor(_selected!, _claveCtrl.text);
        if (!ok || !mounted) return;
      }
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _claveCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF1565C0),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              elevation: 8,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long,
                          size: 64, color: Color(0xFF1565C0)),
                      const SizedBox(height: 8),
                      Text(
                        'Toma Pedidos',
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: const Color(0xFF1565C0)),
                      ),
                      const SizedBox(height: 32),

                      // ── Usuario o email (modo API) ─────────────────────
                      if (_apiMode)
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.text,
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Usuario o email',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Ingresá tu usuario o email.'
                              : null,
                        )
                      // ── Selector de vendedor (modo WiFi) ────────────────
                      else if (_loadingVendors)
                        const CircularProgressIndicator()
                      else
                        DropdownButtonFormField<Vendedor>(
                          decoration: const InputDecoration(
                            labelText: 'Vendedor',
                            prefixIcon: Icon(Icons.person),
                            border: OutlineInputBorder(),
                          ),
                          value: _selected,
                          isExpanded: true,
                          items: [
                            // Admin siempre al principio
                            DropdownMenuItem(
                              value: AuthProvider.adminVendedor,
                              child: const Text('Administrador'),
                            ),
                            ..._vendors.map(
                              (v) => DropdownMenuItem(
                                value: v,
                                child:
                                    // Text('${v.codigo} — ${v.nombre}'),
                                    Text('${v.nombre}'),
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            setState(() {
                              _selected = v;
                              _claveCtrl.clear();
                            });
                          },
                          validator: (v) =>
                              v == null ? 'Seleccioná un vendedor.' : null,
                        ),

                      const SizedBox(height: 16),

                      // ── Clave ───────────────────────────────────────────
                      TextFormField(
                        controller: _claveCtrl,
                        decoration: InputDecoration(
                          labelText: _apiMode
                              ? 'Contraseña'
                              : _isAdminSelected
                                  ? 'Contraseña de administrador'
                                  : 'Clave (dejar vacío si no tiene)',
                          prefixIcon: const Icon(Icons.lock),
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureClave
                                ? Icons.visibility
                                : Icons.visibility_off),
                            onPressed: () =>
                                setState(() => _obscureClave = !_obscureClave),
                          ),
                        ),
                        obscureText: _obscureClave,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                      ),

                      if (auth.errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          auth.errorMessage!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ],

                      const SizedBox(height: 24),
                      (_submitting || auth.state == AuthState.loading)
                          ? const CircularProgressIndicator()
                          : ElevatedButton.icon(
                              onPressed: (_apiMode || _selected != null)
                                  ? _login
                                  : null,
                              icon: const Icon(Icons.login),
                              label: const Text('Ingresar'),
                            ),
                      const SizedBox(height: 12),
                      TextButton.icon(
                        onPressed: (_submitting ||
                                auth.state == AuthState.loading)
                            ? null
                            : () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const QrPairingScreen()),
                                ),
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Escanear QR de acceso'),
                      ),
                      if (_version.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          _version,
                          style: const TextStyle(
                              fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  bool get _isAdminSelected =>
      _selected?.codigo == AuthProvider.adminCodigo;
}
