import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/articulo.dart';
import '../../../data/models/proveedor.dart';
import '../../../data/repositories/articulo_repository.dart';
import '../../../data/repositories/proveedor_repository.dart';
import '../../providers/api_sync_provider.dart';

class _RenglonCompra {
  final Articulo articulo;
  double cantidad = 1;
  double? costoEstimado;

  _RenglonCompra({required this.articulo});
}

/// Propuesta de orden de compra ("generar orden de compra"). Manda al ERP;
/// queda pendiente hasta que un admin la aprueba y elige el proveedor real.
class NuevaOrdenCompraScreen extends StatefulWidget {
  const NuevaOrdenCompraScreen({super.key});

  @override
  State<NuevaOrdenCompraScreen> createState() => _NuevaOrdenCompraScreenState();
}

class _NuevaOrdenCompraScreenState extends State<NuevaOrdenCompraScreen> {
  final _proveedorRepo = ProveedorRepository();
  final _proveedorSugeridoCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  List<Proveedor> _proveedores = [];
  int? _proveedorSeleccionado;
  final List<_RenglonCompra> _renglones = [];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _proveedorRepo.getAll().then((v) {
      if (mounted) setState(() => _proveedores = v);
    });
  }

  @override
  void dispose() {
    _proveedorSugeridoCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _agregarArticulo() async {
    final articulo = await showModalBottomSheet<Articulo>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _BuscarArticuloSheet(),
    );
    if (articulo == null) return;
    if (_renglones.any((r) => r.articulo.codigo == articulo.codigo)) {
      _snack('Ese artículo ya está en la orden.');
      return;
    }
    setState(() => _renglones.add(_RenglonCompra(articulo: articulo)));
  }

  Future<void> _guardar() async {
    if (_renglones.isEmpty) {
      _snack('Agregá al menos un artículo.');
      return;
    }
    if (_proveedorSeleccionado == null &&
        _proveedorSugeridoCtrl.text.trim().isEmpty) {
      _snack('Elegí un proveedor o escribí uno sugerido.');
      return;
    }

    setState(() => _guardando = true);

    final ok = await context.read<ApiSyncProvider>().crearOrdenCompra(
          proveedorId: _proveedorSeleccionado,
          proveedorNombre: _proveedorSeleccionado != null
              ? _proveedores
                  .firstWhere((p) => p.codigo == _proveedorSeleccionado)
                  .nombre
              : _proveedorSugeridoCtrl.text.trim(),
          observaciones: _observacionesCtrl.text.trim().isEmpty
              ? null
              : _observacionesCtrl.text.trim(),
          items: [
            for (final r in _renglones)
              {
                'codArticulo': r.articulo.codigo,
                'descripcion': r.articulo.descripcion,
                'cantidad': r.cantidad,
                'costoEstimado': r.costoEstimado,
              },
          ],
        );

    if (!mounted) return;
    if (!ok) {
      setState(() => _guardando = false);
      _snack(context.read<ApiSyncProvider>().errorMessage ??
          'No se pudo enviar la orden de compra.');
      return;
    }

    _snack('Orden de compra enviada. Queda pendiente de aprobación.');
    Navigator.pop(context, true);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva orden de compra')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<int>(
            initialValue: _proveedorSeleccionado,
            decoration: const InputDecoration(
                labelText: 'Proveedor', border: OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: null, child: Text('(sugerir por texto)')),
              ..._proveedores.map(
                  (p) => DropdownMenuItem(value: p.codigo, child: Text(p.nombre))),
            ],
            onChanged: (v) => setState(() => _proveedorSeleccionado = v),
          ),
          if (_proveedorSeleccionado == null) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _proveedorSugeridoCtrl,
              decoration: const InputDecoration(
                labelText: 'Proveedor sugerido',
                border: OutlineInputBorder(),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(children: [
            const Text('Artículos', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            TextButton.icon(
              onPressed: _agregarArticulo,
              icon: const Icon(Icons.add),
              label: const Text('Agregar'),
            ),
          ]),
          if (_renglones.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Text('Sin artículos todavía.', style: TextStyle(color: Colors.grey)),
            )
          else
            ..._renglones.map((r) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Text(r.articulo.descripcion,
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20),
                          onPressed: () => setState(() => _renglones.remove(r)),
                        ),
                      ]),
                      Row(children: [
                        Expanded(
                          child: TextFormField(
                            initialValue: r.cantidad.toString(),
                            decoration: const InputDecoration(labelText: 'Cantidad', isDense: true),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => r.cantidad =
                                double.tryParse(v.replaceAll(',', '.')) ?? r.cantidad,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            decoration: const InputDecoration(
                                labelText: 'Costo estimado (opcional)', isDense: true),
                            keyboardType:
                                const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => r.costoEstimado =
                                double.tryParse(v.replaceAll(',', '.')),
                          ),
                        ),
                      ]),
                    ]),
                  ),
                )),
          const SizedBox(height: 12),
          TextField(
            controller: _observacionesCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Observaciones (opcional)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: _guardando
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save),
            label: const Text('Enviar orden de compra'),
          ),
        ],
      ),
    );
  }
}

class _BuscarArticuloSheet extends StatefulWidget {
  const _BuscarArticuloSheet();

  @override
  State<_BuscarArticuloSheet> createState() => _BuscarArticuloSheetState();
}

class _BuscarArticuloSheetState extends State<_BuscarArticuloSheet> {
  final _repo = ArticuloRepository();
  final _searchCtrl = TextEditingController();
  List<Articulo> _articulos = [];

  @override
  void initState() {
    super.initState();
    _load('');
    _searchCtrl.addListener(() => _load(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String q) async {
    final results = await _repo.search(q);
    if (mounted) setState(() => _articulos = results);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          children: [
            const Text('Agregar artículo',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar producto...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollCtrl,
                itemCount: _articulos.length,
                itemBuilder: (_, i) {
                  final art = _articulos[i];
                  return ListTile(
                    title: Text(art.descripcion),
                    subtitle: Text('Stock: ${art.stockActual}'),
                    onTap: () => Navigator.pop(context, art),
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
