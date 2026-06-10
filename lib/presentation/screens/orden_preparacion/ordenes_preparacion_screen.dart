import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/database/orden_preparacion_database_helper.dart';
import '../../../core/services/pdf_service.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/parametros.dart';
import '../../../data/models/pedido_cabecera.dart';
import '../../../data/models/pedido_detalle.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../data/repositories/orden_preparacion_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../data/repositories/vendedor_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/orden_preparacion_provider.dart';
import 'nueva_orden_preparacion_screen.dart';
import 'orden_preparacion_detalle_screen.dart';

class OrdenesPreparacionScreen extends StatefulWidget {
  const OrdenesPreparacionScreen({super.key});

  @override
  State<OrdenesPreparacionScreen> createState() => _OrdenesPreparacionScreenState();
}

class _OrdenesPreparacionScreenState extends State<OrdenesPreparacionScreen> {
  final _repo = OrdenPreparacionRepository();
  final _clienteRepo = ClienteRepository();
  final _paramRepo = ParametrosRepository();
  final _vendedorRepo = VendedorRepository();
  List<PedidoCabecera> _ordenes = [];
  bool _loading = true;
  bool _generatingPdf = false;
  String _simbolo = '\$';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final codVendedor = context.read<AuthProvider>().vendedor?.codigo;
    if (codVendedor != null) {
      _ordenes = await _repo.getByVendedor(codVendedor);
    }
    final simbolo = await ParametrosRepository.simboloMoneda();
    if (mounted) setState(() { _loading = false; _simbolo = simbolo; });
  }

  Future<void> _generarPdfTodos() async {
    if (_ordenes.isEmpty) return;
    setState(() => _generatingPdf = true);
    try {
      final codigosUnicos = _ordenes.map((p) => p.codCliente).toSet();
      final Map<int, Cliente> clientes = {};
      for (final cod in codigosUnicos) {
        final cli = await _clienteRepo.findByCodigo(cod);
        if (cli != null) clientes[cod] = cli;
      }
      final Map<int, List<PedidoDetalle>> detallesPorPedido = {};
      for (final p in _ordenes) {
        detallesPorPedido[p.id!] = await _repo.getDetalles(p.id!);
      }
      final codigosVendedores = _ordenes.map((p) => p.codVendedor).toSet();
      final Map<int, String> vendedores = {};
      for (final cod in codigosVendedores) {
        if (cod > 0) {
          final v = await _vendedorRepo.findByCodigo(cod);
          if (v != null) vendedores[cod] = v.nombre;
        }
      }
      Parametros parametros;
      try {
        parametros = await _paramRepo.get();
      } catch (_) {
        parametros = Parametros.empty;
      }
      final bytes = await PdfService.instance.generarTodosPedidos(
        pedidos: _ordenes,
        clientes: clientes,
        detallesPorPedido: detallesPorPedido,
        parametros: parametros,
        vendedores: vendedores,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'ordenes_prep_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _compartirDB() async {
    try {
      final ordenPath = await OrdenPreparacionDatabaseHelper.instance.dbPath;
      if (!await File(ordenPath).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay órdenes para compartir.')),
          );
        }
        return;
      }
      final tmpDir = await getTemporaryDirectory();
      final dst = p.join(tmpDir.path, 'moviles_orden_preparacion.db');
      final copy = await File(ordenPath).copy(dst);
      await Share.shareXFiles(
        [XFile(copy.path, mimeType: 'application/octet-stream', name: 'moviles_orden_preparacion.db')],
        subject: 'Órdenes de Preparación',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al compartir: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Órdenes de Preparación'),
        actions: [
          if (_generatingPdf)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'PDF todas las órdenes',
              onPressed: _ordenes.isEmpty ? null : _generarPdfTodos,
            ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: 'Compartir base de órdenes',
            onPressed: _compartirDB,
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ordenes.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.assignment_outlined, size: 64, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('Sin órdenes registradas'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _goNuevaOrden,
                        icon: const Icon(Icons.add),
                        label: const Text('Crear primera orden'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _ordenes.length,
                    itemBuilder: (_, i) => _OrdenTile(
                      orden: _ordenes[i],
                      clienteRepo: _clienteRepo,
                      simbolo: _simbolo,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  OrdenPreparacionDetalleScreen(idOrden: _ordenes[i].id!)),
                        );
                        _load();
                      },
                      onEdit: () async {
                        context.read<OrdenPreparacionProvider>().reset();
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  NuevaOrdenPreparacionScreen(editOrdenId: _ordenes[i].id!)),
                        );
                        _load();
                      },
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goNuevaOrden,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _goNuevaOrden() {
    context.read<OrdenPreparacionProvider>().reset();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NuevaOrdenPreparacionScreen()),
    ).then((_) => _load());
  }
}

class _OrdenTile extends StatelessWidget {
  final PedidoCabecera orden;
  final ClienteRepository clienteRepo;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final String simbolo;

  const _OrdenTile(
      {required this.orden,
      required this.clienteRepo,
      required this.onTap,
      required this.onEdit,
      required this.simbolo});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.purple.shade100,
        child: Text(
          '#${orden.nroPedido ?? orden.id}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
      title: FutureBuilder(
        future: clienteRepo.findByCodigo(orden.codCliente),
        builder: (_, snap) => Text(
          snap.data?.nombre ?? 'Cliente ${orden.codCliente}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      subtitle: Text(orden.fecha),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$simbolo${fmt.format(orden.total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              if (orden.firma != null)
                const Icon(Icons.draw, size: 14, color: Colors.green),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            tooltip: 'Editar',
            onPressed: onEdit,
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}
