import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/articulo.dart';
import '../../../data/models/deposito.dart';
import '../../../data/models/lista_precio.dart';
import '../../../data/repositories/articulo_repository.dart';
import '../../../data/repositories/deposito_repository.dart';
import '../../../data/repositories/parametros_repository.dart';

/// Detalle de un artículo con paridad al ERP: todas las listas de precio y el
/// stock desglosado por depósito.
class ArticuloDetalleScreen extends StatefulWidget {
  final Articulo articulo;

  const ArticuloDetalleScreen({super.key, required this.articulo});

  @override
  State<ArticuloDetalleScreen> createState() => _ArticuloDetalleScreenState();
}

class _ArticuloDetalleScreenState extends State<ArticuloDetalleScreen> {
  final _repo = ArticuloRepository();
  final _depoRepo = DepositoRepository();
  List<ListaPrecio> _listas = [];
  List<Deposito> _stock = [];
  String _simbolo = '\$';
  bool _mostrarPrecio = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final listas = await _repo.getListas();
    final entries = await _depoRepo.getAllEntries();
    final simbolo = await ParametrosRepository.simboloMoneda();
    final verPrecios = await ParametrosRepository.permiteVerPrecios();
    if (!mounted) return;
    setState(() {
      _listas = listas;
      _stock = entries
          .where((d) => d.codArticulo == widget.articulo.codigo && d.stock != 0)
          .toList();
      _simbolo = simbolo;
      _mostrarPrecio = verPrecios;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.articulo;
    final fmt = NumberFormat('#,##0.00', 'es_AR');

    // Listas del ERP + fallback a los 3 slots si no hay listas cacheadas.
    final filasPrecio = <(String, double)>[];
    if (_listas.isNotEmpty && a.precios.isNotEmpty) {
      for (final l in _listas) {
        if (a.precios.containsKey(l.codigo)) {
          filasPrecio.add((l.nombre, a.precios[l.codigo]!));
        }
      }
    }
    if (filasPrecio.isEmpty) {
      filasPrecio.addAll([
        ('Lista 1', a.prevtaPub1),
        ('Lista 2', a.prevtaPub2),
        ('Lista 3', a.prevtaPub3),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: Text(a.descripcion)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _row(Icons.numbers, 'Código', a.codigo.toString()),
                _row(Icons.inventory_2, 'Descripción', a.descripcion),
                if (a.sku.isNotEmpty) _row(Icons.qr_code, 'SKU', a.sku),
                if (a.codigoBarra.isNotEmpty)
                  _row(Icons.barcode_reader, 'Barcode', a.codigoBarra),
                _row(Icons.percent, 'Alícuota IVA', '${a.alicuota}%'),
                if (a.esDolar) _row(Icons.attach_money, 'Moneda', 'USD'),
                if (a.pendiente)
                  _row(Icons.hourglass_empty, 'Estado',
                      'Pendiente de confirmación del ERP'),
              ]),
            ),
          ),
          const SizedBox(height: 16),
          _titulo('LISTAS DE PRECIO'),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (final (nombre, precio) in filasPrecio)
                  ListTile(
                    dense: true,
                    title: Text(nombre, style: const TextStyle(fontSize: 13)),
                    trailing: Text(
                      _mostrarPrecio
                          ? '$_simbolo${fmt.format(precio)}'
                          : '—',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _titulo('STOCK POR DEPÓSITO'),
          const SizedBox(height: 8),
          if (_stock.isEmpty)
            const Card(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text('Sin stock en depósitos',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            Card(
              child: Column(
                children: [
                  for (final d in _stock)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.warehouse, size: 20),
                      title: Text(d.descripcion,
                          style: const TextStyle(fontSize: 13)),
                      trailing: Text(d.stock.toStringAsFixed(2),
                          style:
                              const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _titulo(String t) => Text(t,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: 1.2,
      ));

  Widget _row(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        Text('$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
