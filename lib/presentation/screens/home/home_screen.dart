import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pedido_provider.dart';
import '../../providers/update_provider.dart';
import '../../widgets/update_dialog.dart';
import '../admin/configuracion_avanzada_screen.dart';
import '../articulos/articulos_screen.dart';
import '../clientes/clientes_screen.dart';
import '../login/login_screen.dart';
import '../orden_preparacion/ordenes_preparacion_screen.dart';
import '../pedidos/nuevo_pedido_screen.dart';
import '../pedidos/pedidos_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _ordenPreparacion = false;
  bool _monedaDolar = false;

  @override
  void initState() {
    super.initState();
    _reloadConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkForUpdates());
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
    final dolar = await ParametrosRepository.simboloMoneda();
    if (mounted) {
      setState(() {
        _ordenPreparacion = orden;
        _monedaDolar = dolar == 'U\$S ';
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
            _MenuCard(
              icon: Icons.settings,
              label: 'Configuración',
              color: Colors.grey.shade700,
              onTap: () {
                final ctx = context;
                Navigator.push(
                  ctx,
                  MaterialPageRoute(
                    builder: (_) => SettingsScreen(
                      onDatabaseReady: () async {
                        await ctx.read<AuthProvider>().logout();
                        if (ctx.mounted) {
                          Navigator.of(ctx).pushAndRemoveUntil(
                            MaterialPageRoute(
                                builder: (_) => const LoginScreen()),
                            (route) => false,
                          );
                        }
                      },
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
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
      ),
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
