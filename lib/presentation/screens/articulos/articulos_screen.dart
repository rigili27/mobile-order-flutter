import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../data/models/articulo.dart';
import '../../../data/models/deposito.dart';
import '../../../data/repositories/articulo_repository.dart';
import '../../../data/repositories/deposito_repository.dart';

class ArticulosScreen extends StatefulWidget {
  const ArticulosScreen({super.key});

  @override
  State<ArticulosScreen> createState() => _ArticulosScreenState();
}

class _ArticulosScreenState extends State<ArticulosScreen> {
  final _repo = ArticuloRepository();
  final _depoRepo = DepositoRepository();
  final _searchCtrl = TextEditingController();

  List<Articulo> _articulos = [];
  List<Deposito> _depositosFiltro = [];
  Map<int, List<Deposito>> _stockPorArticulo = {};
  bool _loading = true;
  bool _scanning = false;
  int _listaPrecios = 1;
  int? _depositoFiltro;

  @override
  void initState() {
    super.initState();
    _loadDepositos();
    _load('');
    _searchCtrl.addListener(() => _load(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDepositos() async {
    final [filtros, entries] = await Future.wait([
      _depoRepo.getAll(),
      _depoRepo.getAllEntries(),
    ]);
    final stockMap = <int, List<Deposito>>{};
    for (final d in entries as List<Deposito>) {
      if (d.stock > 0) stockMap.putIfAbsent(d.codArticulo, () => []).add(d);
    }
    if (mounted) {
      setState(() {
        _depositosFiltro = filtros as List<Deposito>;
        _stockPorArticulo = stockMap;
      });
    }
  }

  Future<void> _load(String query) async {
    setState(() => _loading = true);
    final results = _depositoFiltro != null
        ? await _repo.searchByDeposito(query, _depositoFiltro!)
        : await _repo.search(query);
    if (mounted) setState(() { _articulos = results; _loading = false; });
  }

  Future<void> _scanBarcode() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;
    setState(() => _scanning = true);
  }

  void _onBarcodeDetected(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    setState(() => _scanning = false);
    final art = await _repo.findByBarcode(code);
    if (art != null) {
      _searchCtrl.text = art.descripcion;
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró producto con barcode: $code')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Escanear producto'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _scanning = false),
          ),
        ),
        body: MobileScanner(onDetect: _onBarcodeDetected),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Productos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear barcode',
            onPressed: _scanBarcode,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Filtros ────────────────────────────────────────────────────────
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _listaPrecios,
                  decoration: const InputDecoration(
                    labelText: 'Lista precios',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [1, 2, 3]
                      .map((i) => DropdownMenuItem(
                          value: i, child: Text('Lista $i')))
                      .toList(),
                  onChanged: (v) => setState(() => _listaPrecios = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<int?>(
                  value: _depositoFiltro,
                  decoration: const InputDecoration(
                    labelText: 'Depósito',
                    isDense: true,
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    ..._depositosFiltro.map((d) => DropdownMenuItem(
                        value: d.codigo, child: Text(d.descripcion))),
                  ],
                  onChanged: (v) {
                    setState(() => _depositoFiltro = v);
                    _load(_searchCtrl.text);
                  },
                ),
              ),
            ]),
          ),

          // ── Buscador ───────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, código, SKU, barcode...',
                prefixIcon: const Icon(Icons.search),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _searchCtrl.clear(); _load(''); },
                      )
                    : null,
              ),
            ),
          ),

          // ── Lista ──────────────────────────────────────────────────────────
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _articulos.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
                        itemCount: _articulos.length,
                        itemBuilder: (_, i) {
                          final art = _articulos[i];
                          return _ArticuloTile(
                            articulo: art,
                            listaPrecios: _listaPrecios,
                            depositos: _stockPorArticulo[art.codigo] ?? [],
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _ArticuloTile extends StatelessWidget {
  final Articulo articulo;
  final int listaPrecios;
  final List<Deposito> depositos;

  const _ArticuloTile({
    required this.articulo,
    required this.listaPrecios,
    required this.depositos,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    final precio = articulo.precioParaLista(listaPrecios);

    final stockLines = depositos.isEmpty
        ? 'Sin stock en depósitos'
        : depositos
            .map((d) => '${d.descripcion}: ${d.stock.toStringAsFixed(2)}')
            .join('  |  ');

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.green.shade100,
        child: const Icon(Icons.inventory_2, color: Colors.green),
      ),
      title: Text(articulo.descripcion,
          style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (articulo.sku.isNotEmpty)
            Text('SKU: ${articulo.sku}',
                style: const TextStyle(fontSize: 11)),
          if (articulo.codigoBarra.isNotEmpty)
            Text('Barcode: ${articulo.codigoBarra}',
                style: const TextStyle(fontSize: 11)),
          Text(stockLines,
              style: TextStyle(
                  fontSize: 11,
                  color: depositos.isEmpty
                      ? Colors.red.shade400
                      : Colors.grey.shade700)),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text('\$${fmt.format(precio)}',
              style:
                  const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text('Lista $listaPrecios',
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          if (articulo.esDolar)
            const Text('USD',
                style: TextStyle(fontSize: 10, color: Colors.blue)),
        ],
      ),
      isThreeLine: true,
    );
  }
}
