import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../providers/api_sync_provider.dart';
import 'nuevo_ajuste_stock_screen.dart';

/// Listado de los conteos/ajustes de stock que este dispositivo mandó.
/// Quedan pendientes de confirmación en el ERP (Preventa → Ajustes de stock).
class AjustesStockScreen extends StatefulWidget {
  const AjustesStockScreen({super.key});

  @override
  State<AjustesStockScreen> createState() => _AjustesStockScreenState();
}

class _AjustesStockScreenState extends State<AjustesStockScreen> {
  List<Map<String, dynamic>> _ajustes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ajustes = await context.read<ApiSyncProvider>().ajustesStockLocales();
    if (mounted) setState(() { _ajustes = ajustes; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes de stock')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _ajustes.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Sin conteos registrados')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _ajustes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = _ajustes[i];
                        final contada = (a['cantidad_contada'] as num).toDouble();
                        final sistema =
                            (a['cantidad_sistema'] as num?)?.toDouble();
                        final diferencia =
                            sistema != null ? contada - sistema : null;
                        return ListTile(
                          title: Text(a['descripcion_articulo'] as String? ??
                              'Artículo #${a['cod_articulo']}'),
                          subtitle: Text(
                              '${a['descripcion_deposito'] ?? ''} · Contado: ${fmt.format(contada)}'
                              '${diferencia != null ? ' · Dif: ${diferencia > 0 ? '+' : ''}${fmt.format(diferencia)}' : ''}'),
                          trailing: const Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text('Pendiente', style: TextStyle(fontSize: 11)),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const NuevoAjusteStockScreen()),
          );
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nuevo conteo'),
      ),
    );
  }
}
