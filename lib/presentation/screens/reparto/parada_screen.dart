import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/nav_launcher.dart';
import '../../../data/models/reparto_models.dart';
import '../../providers/reparto_provider.dart';
import 'confirmar_entrega_screen.dart';

/// Detalle de una parada + acciones del repartidor.
class ParadaScreen extends StatelessWidget {
  const ParadaScreen({super.key, required this.paradaId});

  final int paradaId;

  Parada? _find(RepartoProvider prov) {
    for (final h in prov.hojas) {
      for (final p in h.paradas) {
        if (p.id == paradaId) return p;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RepartoProvider>();
    final p = _find(prov);

    if (p == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Parada')),
        body: const Center(child: Text('La parada ya no está disponible.')),
      );
    }

    final tieneCoords = p.lat != null && p.lng != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('${p.orden}. ${p.cliente}'),
        actions: [
          if (tieneCoords)
            IconButton(
              icon: const Icon(Icons.navigation),
              tooltip: 'Navegar',
              onPressed: () async {
                final ok = await abrirNavegacion(p.lat!, p.lng!, etiqueta: p.cliente);
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('No hay una app de mapas para navegar.')));
                }
              },
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<RepartoProvider>().sincronizar(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _row(Icons.person, p.cliente),
            if (p.direccion != null && p.direccion!.isNotEmpty) _row(Icons.place, p.direccion!),
            if (p.telefono != null && p.telefono!.isNotEmpty) _row(Icons.phone, p.telefono!),
          if (p.remitoId != null) _row(Icons.description, 'Remito Nº ${p.remitoId}'),
          if (p.instrucciones != null && p.instrucciones!.isNotEmpty)
            _row(Icons.info_outline, p.instrucciones!),
          const Divider(height: 32),
          const Text('Artículos', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...p.renglones.map((r) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(r.articulo),
                subtitle: r.sku != null ? Text(r.sku!) : null,
                trailing: Text(_n(r.cantidad)),
              )),
          const SizedBox(height: 12),
          Chip(label: Text('Estado: ${Parada.estadoLabel(p.estado)}')),
          const SizedBox(height: 24),
          if (!p.resuelta) ...[
            if (p.estado == 'pendiente')
              OutlinedButton.icon(
                onPressed: () => context.read<RepartoProvider>().marcarEnCamino(p.id),
                icon: const Icon(Icons.directions_car),
                label: const Text('En camino'),
              ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ConfirmarEntregaScreen(paradaId: p.id)),
              ),
              icon: const Icon(Icons.check_circle),
              label: const Text('Confirmar entrega'),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => _reprogramar(context, p.id),
              icon: const Icon(Icons.schedule),
              label: const Text('Reprogramar'),
            ),
          ],
          ],
        ),
      ),
    );
  }

  Future<void> _reprogramar(BuildContext context, int paradaId) async {
    final ctrl = TextEditingController();
    final motivo = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reprogramar parada'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
          maxLines: 2,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Reprogramar')),
        ],
      ),
    );
    if (motivo == null || !context.mounted) return;
    final ok = await context.read<RepartoProvider>().reprogramar(paradaId, motivo.isEmpty ? null : motivo);
    if (context.mounted) {
      if (ok) {
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.read<RepartoProvider>().error ?? 'Error')));
      }
    }
  }

  Widget _row(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: Colors.grey.shade700),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      );

  static String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
