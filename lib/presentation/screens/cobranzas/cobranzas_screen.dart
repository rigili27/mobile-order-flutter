import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../core/database/sync_state_database_helper.dart';
import '../../../data/models/cobranza.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../data/repositories/cobranza_repository.dart';
import '../../providers/api_sync_provider.dart';
import 'nueva_cobranza_screen.dart';

/// Listado de las cobranzas registradas desde la app, con el estado de
/// sincronización de cada una (pendiente / sincronizada / error).
class CobranzasScreen extends StatefulWidget {
  const CobranzasScreen({super.key});

  @override
  State<CobranzasScreen> createState() => _CobranzasScreenState();
}

class _CobranzasScreenState extends State<CobranzasScreen> {
  final _repo = CobranzaRepository();
  final _clienteRepo = ClienteRepository();
  final _fmt = NumberFormat('#,##0.00', 'es_AR');

  List<Cobranza> _cobranzas = [];
  final Map<int, CobranzaOutboxEntry?> _estados = {};
  final Map<int, String> _nombresCliente = {};
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() => _cargando = true);
    final cobranzas = await _repo.getAll();
    for (final c in cobranzas) {
      if (c.id != null) _estados[c.id!] = await _repo.estadoDe(c.id!);
      _nombresCliente[c.codCliente] ??=
          (await _clienteRepo.findByCodigo(c.codCliente))?.nombre ??
              'Cliente ${c.codCliente}';
    }
    if (mounted) {
      setState(() {
        _cobranzas = cobranzas;
        _cargando = false;
      });
    }
  }

  Future<void> _reintentar() async {
    await context.read<ApiSyncProvider>().reintentarCobranzasPendientes();
    await _cargar();
  }

  ({Color color, String label, IconData icon}) _chip(OutboxEstado? e) {
    switch (e) {
      case OutboxEstado.sincronizado:
        return (
          color: Colors.green,
          label: 'Sincronizada',
          icon: Icons.cloud_done
        );
      case OutboxEstado.error:
        return (color: Colors.red, label: 'Error', icon: Icons.error_outline);
      case OutboxEstado.pendiente:
      case null:
        return (
          color: Colors.orange,
          label: 'Pendiente',
          icon: Icons.cloud_upload_outlined
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendientes = context.watch<ApiSyncProvider>().cobranzasPendientes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cobranzas'),
        actions: [
          if (pendientes > 0)
            TextButton.icon(
              onPressed: _reintentar,
              icon: const Icon(Icons.sync, color: Colors.white),
              label: Text('Reintentar ($pendientes)',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _cargar,
        child: _cargando
            ? const Center(child: CircularProgressIndicator())
            : _cobranzas.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('Sin cobranzas registradas')),
                    ],
                  )
                : ListView.separated(
                    itemCount: _cobranzas.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) {
                      final c = _cobranzas[i];
                      final estado =
                          c.id == null ? null : _estados[c.id!]?.estado;
                      final chip = _chip(estado);
                      return ListTile(
                        title: Text(_nombresCliente[c.codCliente] ??
                            'Cliente ${c.codCliente}'),
                        subtitle: Text(
                            '${c.fecha} · ${c.formaPago.name} · \$ ${_fmt.format(c.importe)}'),
                        trailing: Chip(
                          visualDensity: VisualDensity.compact,
                          avatar: Icon(chip.icon, size: 16, color: chip.color),
                          label: Text(chip.label,
                              style: TextStyle(color: chip.color, fontSize: 11)),
                        ),
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final ok = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const NuevaCobranzaScreen()),
          );
          if (ok == true) _cargar();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nueva cobranza'),
      ),
    );
  }
}
