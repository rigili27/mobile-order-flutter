import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/reparto_models.dart';
import '../../providers/reparto_provider.dart';
import '../../widgets/app_list_card.dart';
import 'hoja_ruta_mapa_screen.dart';
import 'parada_screen.dart';

/// Detalle de una hoja de ruta: paradas en orden + "Iniciar reparto".
/// Se actualiza arrastrando hacia abajo (pull-to-refresh).
class HojaRutaScreen extends StatelessWidget {
  const HojaRutaScreen({super.key, required this.hojaId});

  final int hojaId;

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<RepartoProvider>();
    final hoja = prov.hojas.where((h) => h.id == hojaId).firstOrNull;

    if (hoja == null) {
      return Scaffold(
        appBar: AppBar(title: Text('Hoja Nº $hojaId')),
        body: const Center(child: Text('La hoja ya no está disponible.')),
      );
    }

    final tieneCoords = hoja.paradas.any((p) => p.lat != null && p.lng != null);

    return Scaffold(
      appBar: AppBar(
        title: Text('Hoja Nº ${hoja.id} · ${hoja.fecha}'),
        actions: [
          if (tieneCoords)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'Ver en el mapa',
              onPressed: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => HojaRutaMapaScreen(hojaId: hoja.id))),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => context.read<RepartoProvider>().sincronizar(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (prov.syncing) const LinearProgressIndicator(),
            if (hoja.notas != null && hoja.notas!.isNotEmpty)
              Container(
                width: double.infinity,
                color: Colors.amber.shade50,
                padding: const EdgeInsets.all(12),
                child: Text(hoja.notas!, style: const TextStyle(fontSize: 13)),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Text('${hoja.resueltas}/${hoja.total} entregadas',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (hoja.distanciaM != null)
                    Text('${(hoja.distanciaM! / 1000).toStringAsFixed(1)} km',
                        style: const TextStyle(color: Colors.grey)),
                ],
              ),
            ),
            for (final p in hoja.paradas)
              AppListCard(
                leadingText: '${p.orden}',
                leadingColor: p.resuelta ? Colors.green : Colors.blueGrey,
                title: p.cliente,
                subtitle: [
                  if (p.direccion != null && p.direccion!.isNotEmpty) p.direccion,
                  if (p.ventanaDesde != null)
                    'Ventana ${_hm(p.ventanaDesde!)}–${p.ventanaHasta != null ? _hm(p.ventanaHasta!) : ''}',
                ].whereType<String>().join(' · '),
                trailing: Text(Parada.estadoLabel(p.estado),
                    style: TextStyle(
                        fontSize: 12,
                        color: p.resuelta ? Colors.green.shade700 : Colors.orange.shade800)),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ParadaScreen(paradaId: p.id)),
                ),
              ),
            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomNavigationBar: hoja.asignada
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: () async {
                    final ok = await context.read<RepartoProvider>().iniciarHoja(hoja.id);
                    if (!ok && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(context.read<RepartoProvider>().error ?? 'Error')));
                    }
                  },
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Iniciar reparto'),
                ),
              ),
            )
          : null,
    );
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}
