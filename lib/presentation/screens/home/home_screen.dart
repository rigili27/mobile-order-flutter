import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/api/api_config.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../providers/api_sync_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pedido_provider.dart';
import '../../providers/update_provider.dart';
import '../../widgets/update_dialog.dart';
import '../admin/configuracion_avanzada_screen.dart';
import '../articulos/articulos_screen.dart';
import '../cobranzas/cobranzas_screen.dart';
import '../clientes/clientes_screen.dart';
import '../compras/ordenes_compra_screen.dart';
import '../cuenta_corriente/cuenta_corriente_screen.dart';
import '../login/login_screen.dart';
import '../orden_preparacion/ordenes_preparacion_screen.dart';
import '../pedidos/nuevo_pedido_screen.dart';
import '../pedidos/pedidos_screen.dart';
import '../settings/settings_screen.dart';
import '../stock/ajustes_stock_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _ordenPreparacion = false;
  bool _ctaCteActivo = false;
  bool _monedaDolar = false;
  bool _apiMode = false;
  bool _permitePedidos = true;
  bool _permiteCobranzas = true;
  bool _permiteStock = false;
  bool _permiteGenerarCompra = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reloadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdates();
      _autoSync();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _autoSync();
  }

  /// Sincroniza el catálogo en segundo plano si la última quedó vieja.
  /// Al terminar recarga los flags de config (pueden haber cambiado).
  Future<void> _autoSync() async {
    final cambio = await context.read<ApiSyncProvider>().autoSync();
    if (cambio && mounted) _reloadConfig();
  }

  void _checkForUpdates() {
    context.read<UpdateProvider>().checkForUpdate().then((_) {
      if (!mounted) return;
      final upd = context.read<UpdateProvider>();
      if (upd.state == UpdateState.updateAvailable && upd.updateInfo != null) {
        showDialog(
          context: context,
          builder: (_) => const UpdateDialog(),
        );
      }
    });
  }

  Future<void> _reloadConfig() async {
    ParametrosRepository.invalidateCache();
    final orden = await ParametrosRepository.ordenPreparacionActivo();
    final ctaCte = await ParametrosRepository.ctaCteActivo();
    final dolar = await ParametrosRepository.simboloMoneda();
    final apiMode = await ApiConfig.isConfigured();
    final permitePedidos = await ParametrosRepository.permitePedidos();
    final permiteCobranzas = await ParametrosRepository.permiteCobranzas();
    final permiteStock = await ParametrosRepository.permiteStock();
    final permiteGenerarCompra = await ParametrosRepository.permiteGenerarCompra();
    if (mounted) {
      setState(() {
        _ordenPreparacion = orden;
        _ctaCteActivo = ctaCte;
        _monedaDolar = dolar == 'U\$S ';
        _apiMode = apiMode;
        _permitePedidos = permitePedidos;
        _permiteCobranzas = permiteCobranzas;
        _permiteStock = permiteStock;
        _permiteGenerarCompra = permiteGenerarCompra;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final vendedor = auth.vendedor;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Toma Pedidos', style: TextStyle(fontSize: 18)),
            if (vendedor != null)
              Text(vendedor.nombre,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Text(
                _monedaDolar ? '🇺🇸' : '🇦🇷',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ),
          if (auth.isAdmin)
            IconButton(
              icon: const Icon(Icons.tune),
              tooltip: 'Configuración Avanzada',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const ConfiguracionAvanzadaScreen()),
              ).then((_) => _reloadConfig()),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Cerrar sesión',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cerrar sesión'),
                  content: const Text('¿Querés cerrar la sesión actual?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Salir')),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          children: [
            _MenuCard(
              icon: Icons.people,
              label: 'Clientes',
              color: Colors.blue.shade700,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ClientesScreen()),
              ),
            ),
            _MenuCard(
              icon: Icons.inventory_2,
              label: 'Productos',
              color: Colors.green.shade700,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ArticulosScreen()),
              ),
            ),
            _MenuCard(
              icon: Icons.receipt_long,
              label: 'Pedidos',
              color: Colors.orange.shade700,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PedidosScreen()),
              ),
            ),
            if (_ordenPreparacion)
              _MenuCard(
                icon: Icons.assignment_outlined,
                label: 'Orden de Preparación',
                color: Colors.purple.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const OrdenesPreparacionScreen()),
                ),
              ),
            if (_ctaCteActivo)
              _MenuCard(
                icon: Icons.account_balance_wallet_outlined,
                label: 'Cuenta Corriente',
                color: Colors.teal.shade700,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CuentaCorrienteScreen()),
                ),
              ),
            if (_ctaCteActivo && _apiMode && _permiteCobranzas)
              _MenuCard(
                icon: Icons.payments_outlined,
                label: 'Cobranzas',
                color: Colors.indigo.shade600,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CobranzasScreen()),
                ),
              ),
            if (_apiMode && _permiteStock)
              _MenuCard(
                icon: Icons.inventory_outlined,
                label: 'Stock',
                color: Colors.brown.shade600,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AjustesStockScreen()),
                ),
              ),
            if (_apiMode && _permiteGenerarCompra)
              _MenuCard(
                icon: Icons.local_shipping_outlined,
                label: 'Órdenes de compra',
                color: Colors.deepOrange.shade600,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const OrdenesCompraScreen()),
                ),
              ),
            _MenuCard(
              icon: Icons.settings,
              label: 'Configuración',
              color: Colors.grey.shade700,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ).then((_) {
                  if (mounted) _reloadConfig();
                });
              },
            ),
          ],
        ),
      ),
      floatingActionButton: _permitePedidos
          ? FloatingActionButton.extended(
              onPressed: () {
                context.read<PedidoProvider>().reset();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NuevoPedidoScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('Nuevo Pedido'),
              backgroundColor: Theme.of(context).colorScheme.primary,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }
}

class _MenuCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: Icon(icon, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 12),
            Text(label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
