import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/api_sync_provider.dart';
import 'nueva_orden_compra_screen.dart';

/// Listado de las propuestas de orden de compra que este dispositivo mandó.
/// Quedan pendientes de aprobación en el ERP (Preventa → Órdenes de compra
/// de la app).
class OrdenesCompraScreen extends StatefulWidget {
  const OrdenesCompraScreen({super.key});

  @override
  State<OrdenesCompraScreen> createState() => _OrdenesCompraScreenState();
}

class _OrdenesCompraScreenState extends State<OrdenesCompraScreen> {
  List<Map<String, dynamic>> _ordenes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final ordenes = await context.read<ApiSyncProvider>().ordenesCompraLocales();
    if (mounted) setState(() { _ordenes = ordenes; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Órdenes de compra')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _ordenes.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('Sin órdenes de compra registradas')),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _ordenes.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final o = _ordenes[i];
                        final items = (jsonDecode(o['items_json'] as String) as List)
                            .cast<Map<String, dynamic>>();
                        return ListTile(
                          title: Text((o['proveedor_nombre'] as String?)?.isNotEmpty == true
                              ? o['proveedor_nombre'] as String
                              : 'Sin proveedor'),
                          subtitle: Text('${items.length} artículo(s)'),
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
            MaterialPageRoute(builder: (_) => const NuevaOrdenCompraScreen()),
          );
          if (ok == true) _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva orden'),
      ),
    );
  }
}
