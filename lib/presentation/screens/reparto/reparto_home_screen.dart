import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/reparto_provider.dart';
import '../login/login_screen.dart';
import '../settings/settings_screen.dart';
import 'hoja_ruta_screen.dart';

/// Home del modo repartidor: lista de hojas de ruta asignadas para hoy.
class RepartoHomeScreen extends StatefulWidget {
  const RepartoHomeScreen({super.key});

  @override
  State<RepartoHomeScreen> createState() => _RepartoHomeScreenState();
}

class _RepartoHomeScreenState extends State<RepartoHomeScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    final prov = context.read<RepartoProvider>();
    await prov.cargarLocal();
    await prov.sincronizar();
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Querés cerrar la sesión actual?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Salir')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<AuthProvider>().logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final prov = context.watch<RepartoProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Mis hojas de ruta', style: TextStyle(fontSize: 18)),
            if (auth.vendedor != null)
              Text(auth.vendedor!.nombre,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.normal)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Configuración',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Cerrar sesión', onPressed: _logout),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _sync,
        child: Column(
          children: [
            if (prov.syncing) const LinearProgressIndicator(),
            if (prov.error != null)
              Container(
                width: double.infinity,
                color: Colors.red.shade50,
                padding: const EdgeInsets.all(12),
                child: Text(prov.error!, style: TextStyle(color: Colors.red.shade900, fontSize: 13)),
              ),
            if (prov.pendientes > 0)
              Container(
                width: double.infinity,
                color: Colors.orange.shade50,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${prov.pendientes} entrega(s) sin sincronizar',
                          style: TextStyle(color: Colors.orange.shade900, fontSize: 13)),
                    ),
                    TextButton(
                      onPressed: prov.syncing ? null : () => prov.reintentarPendientes(),
                      child: const Text('Reintentar'),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: prov.hojas.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(
                          child: Text(
                            prov.syncing ? 'Cargando…' : 'No tenés hojas de ruta asignadas.',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: prov.hojas.length,
                      itemBuilder: (_, i) {
                        final h = prov.hojas[i];
                        return Card(
                          child: ListTile(
                            title: Text('Hoja Nº ${h.id} · ${h.fecha}'),
                            subtitle: Text(
                                '${h.resueltas}/${h.total} paradas · ${h.deposito ?? ''}'),
                            trailing: Chip(
                              label: Text(HojaRutaEstadoChip.label(h.estado)),
                              backgroundColor: h.enCurso
                                  ? Colors.blue.shade100
                                  : Colors.grey.shade200,
                            ),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => HojaRutaScreen(hojaId: h.id)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class HojaRutaEstadoChip {
  static String label(String e) => switch (e) {
        'asignada' => 'Asignada',
        'en_curso' => 'En curso',
        'cerrada' => 'Cerrada',
        _ => e,
      };
}
