import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import '../../../core/services/pdf_service.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/parametros.dart';
import '../../../data/models/pedido_cabecera.dart';
import '../../../data/models/pedido_detalle.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../data/repositories/orden_preparacion_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../data/repositories/vendedor_repository.dart';
import '../../providers/orden_preparacion_provider.dart';
import 'nueva_orden_preparacion_screen.dart';

class OrdenPreparacionDetalleScreen extends StatefulWidget {
  final int idOrden;

  const OrdenPreparacionDetalleScreen({super.key, required this.idOrden});

  @override
  State<OrdenPreparacionDetalleScreen> createState() =>
      _OrdenPreparacionDetalleScreenState();
}

class _OrdenPreparacionDetalleScreenState
    extends State<OrdenPreparacionDetalleScreen> {
  final _repo = OrdenPreparacionRepository();
  final _clienteRepo = ClienteRepository();
  final _paramRepo = ParametrosRepository();
  final _vendedorRepo = VendedorRepository();

  PedidoCabecera? _cabecera;
  List<PedidoDetalle> _detalles = [];
  Cliente? _cliente;
  Parametros? _parametros;
  String _vendedorNombre = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final cabecera = await _repo.getById(widget.idOrden);
    final detalles = await _repo.getDetalles(widget.idOrden);
    Cliente? cliente;
    String vendedorNombre = '';
    if (cabecera != null) {
      cliente = await _clienteRepo.findByCodigo(cabecera.codCliente);
      if (cabecera.codVendedor > 0) {
        final v = await _vendedorRepo.findByCodigo(cabecera.codVendedor);
        vendedorNombre = v?.nombre ?? '';
      }
    }
    final parametros = await _paramRepo.get();
    if (mounted) {
      setState(() {
        _cabecera = cabecera;
        _detalles = detalles;
        _cliente = cliente;
        _parametros = parametros;
        _vendedorNombre = vendedorNombre;
        _loading = false;
      });
    }
  }

  Future<void> _editarOrden() async {
    if (_cabecera == null) return;
    context.read<OrdenPreparacionProvider>().reset();
    await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) =>
              NuevaOrdenPreparacionScreen(editOrdenId: _cabecera!.id!)),
    );
    _load();
  }

  Future<void> _generarPdf() async {
    if (_cabecera == null || _cliente == null || _parametros == null) return;
    final bytes = await PdfService.instance.generarRemito(
      cabecera: _cabecera!,
      detalles: _detalles,
      cliente: _cliente!,
      parametros: _parametros!,
      vendedorNombre: _vendedorNombre,
    );
    await Printing.sharePdf(
      bytes: bytes,
      filename: 'orden_prep_${_cabecera!.nroPedido ?? _cabecera!.id}.pdf',
    );
  }

  Future<void> _eliminarOrden() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded, color: Colors.red),
          SizedBox(width: 8),
          Text('Eliminar orden'),
        ]),
        content: Text(
          '¿Eliminar la orden #${_cabecera!.nroPedido ?? _cabecera!.id}?\n\n'
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    await _repo.deletePedido(widget.idOrden);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_cabecera == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Orden de Preparación')),
        body: const Center(child: Text('Orden no encontrada.')),
      );
    }

    final fmt = NumberFormat('#,##0.00', 'es_AR');

    return Scaffold(
      appBar: AppBar(
        title: Text('Orden #${_cabecera!.nroPedido ?? _cabecera!.id}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Editar orden',
            onPressed: _editarOrden,
          ),
          IconButton(
            icon: const Icon(Icons.picture_as_pdf),
            tooltip: 'Generar PDF',
            onPressed: _generarPdf,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Eliminar orden',
            onPressed: _eliminarOrden,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow('Orden N°', '${_cabecera!.nroPedido ?? _cabecera!.id}'),
                  _InfoRow('Fecha', _cabecera!.fecha),
                  _InfoRow('Cliente', _cliente?.nombre ?? 'Cód. ${_cabecera!.codCliente}'),
                  if (_cliente != null) _InfoRow('Localidad', _cliente!.localidad),
                  if (_vendedorNombre.isNotEmpty) _InfoRow('Vendedor', _vendedorNombre),
                  if (_cabecera!.quienRecibio.isNotEmpty)
                    _InfoRow('Recibió', _cabecera!.quienRecibio),
                  if (_cabecera!.comentarios.isNotEmpty)
                    _InfoRow('Tipo', _cabecera!.comentarios),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),
          const Text('Detalle',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),

          ..._detalles.map((d) => Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  title: Text(d.descripcionArticulo ?? 'Cód. ${d.codArticulo}',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  subtitle: Text(
                    '${d.sku.isNotEmpty ? 'SKU: ${d.sku} · ' : ''}'
                    'Cant: ${d.cantidad} · P: \$${fmt.format(d.precio)}'
                    '${d.porDto > 0 ? ' · Dto: ${d.porDto}%' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: Text('\$${fmt.format(d.importe)}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              )),

          const Divider(),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              'TOTAL: \$${fmt.format(_cabecera!.total)}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),

          if (_cabecera!.firma != null && _cabecera!.firma!.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Text('Firma:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              height: 120,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.memory(
                Uint8List.fromList(_cabecera!.firma!),
                fit: BoxFit.contain,
              ),
            ),
          ],

          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _generarPdf,
            icon: const Icon(Icons.picture_as_pdf),
            label: const Text('Compartir PDF'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _eliminarOrden,
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            label: const Text('Eliminar orden',
                style: TextStyle(color: Colors.red)),
            style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Colors.red)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text('$label:',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
