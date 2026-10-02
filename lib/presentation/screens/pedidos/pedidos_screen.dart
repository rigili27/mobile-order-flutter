import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/database/database_file_manager.dart';
import '../../../core/services/pdf_service.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/parametros.dart';
import '../../../data/models/pedido_cabecera.dart';
import '../../../data/models/pedido_detalle.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../data/repositories/pedido_repository.dart';
import '../../../data/repositories/vendedor_repository.dart';
import '../../../core/api/api_config.dart';
import '../../../core/database/sync_state_database_helper.dart';
import '../../providers/api_sync_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/pedido_provider.dart';
import '../../widgets/sync_header.dart';
import 'nuevo_pedido_screen.dart';
import 'pedido_detalle_screen.dart';

class PedidosScreen extends StatefulWidget {
  const PedidosScreen({super.key});

  @override
  State<PedidosScreen> createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  final _pedidoRepo = PedidoRepository();
  final _clienteRepo = ClienteRepository();
  final _paramRepo = ParametrosRepository();
  final _vendedorRepo = VendedorRepository();
  List<PedidoCabecera> _pedidos = [];
  Map<int, OutboxEntry> _syncEstados = {};
  // Oculta los pedidos que el ERP ya remitió, facturó o canceló: para el
  // vendedor ya no hay nada que hacer con ellos. Se recuerda entre sesiones.
  bool _soloPendientes = true;
  static const _kSoloPendientes = 'pedidos_solo_pendientes';
  bool _loading = true;
  bool _generatingPdf = false;
  bool _sharingDb = false;
  bool _apiMode = false;
  bool _syncing = false;
  DateTime? _lastSync;
  String _simbolo = '\$';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      final v = prefs.getBool(_kSoloPendientes);
      if (v != null && mounted) setState(() => _soloPendientes = v);
    });
    _load().then((_) => _refrescarEstadosErp());
  }

  /// Trae del ERP en qué quedó cada pedido (en segundo plano: la lista local
  /// se muestra primero, sin esperar a la red).
  Future<void> _refrescarEstadosErp() async {
    if (!_apiMode) return;
    await context.read<ApiSyncProvider>().actualizarEstadosPedidos();
    if (mounted) await _load();
  }

  Future<void> _setSoloPendientes(bool v) async {
    setState(() => _soloPendientes = v);
    try {
      (await SharedPreferences.getInstance()).setBool(_kSoloPendientes, v);
    } catch (_) {}
  }

  List<PedidoCabecera> get _visibles => _apiMode && _soloPendientes
      ? _pedidos.where((p) => _syncEstados[p.id]?.cerradoEnErp != true).toList()
      : _pedidos;

  Future<void> _load() async {
    setState(() => _loading = true);
    final codVendedor = context.read<AuthProvider>().vendedor?.codigo;
    if (codVendedor != null) {
      _pedidos = await _pedidoRepo.getByVendedor(codVendedor);
    }
    final simbolo = await ParametrosRepository.simboloMoneda();
    final apiMode = await ApiConfig.isConfigured();
    final estados = <int, OutboxEntry>{};
    if (apiMode) {
      for (final p in _pedidos) {
        if (p.id == null) continue;
        final e = await SyncStateDatabaseHelper.instance.find(p.id!);
        if (e != null) estados[p.id!] = e;
      }
    }
    if (mounted) {
      setState(() {
        _loading = false;
        _simbolo = simbolo;
        _apiMode = apiMode;
        _syncEstados = estados;
      });
    }
  }

  Future<void> _sync() async {
    if (_syncing) return;
    final sync = context.read<ApiSyncProvider>();
    setState(() => _syncing = true);
    await sync.reintentarPendientes();
    await sync.actualizarEstadosPedidos();
    await _load();
    if (mounted) {
      setState(() {
        _syncing = false;
        _lastSync = DateTime.now();
      });
    }
  }

  Future<void> _compartirDB() async {
    setState(() => _sharingDb = true);
    try {
      final activePath = await DatabaseFileManager.instance.activePath;
      if (!await File(activePath).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay base de datos para compartir.')),
          );
        }
        return;
      }
      final exportFile = await DatabaseFileManager.instance.prepareExport();
      await Share.shareXFiles(
        [XFile(exportFile.path, mimeType: 'application/octet-stream', name: 'moviles.db')],
        subject: 'Base de datos pedidos',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al compartir: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _sharingDb = false);
    }
  }

  Future<void> _generarPdfTodos() async {
    if (_pedidos.isEmpty) return;
    setState(() => _generatingPdf = true);
    try {
      final codigosUnicos = _pedidos.map((p) => p.codCliente).toSet();
      final Map<int, Cliente> clientes = {};
      for (final cod in codigosUnicos) {
        final cli = await _clienteRepo.findByCodigo(cod);
        if (cli != null) clientes[cod] = cli;
      }
      final Map<int, List<PedidoDetalle>> detallesPorPedido = {};
      for (final p in _pedidos) {
        detallesPorPedido[p.id!] = await _pedidoRepo.getDetalles(p.id!);
      }
      final codigosVendedores = _pedidos.map((p) => p.codVendedor).toSet();
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
        pedidos: _pedidos,
        clientes: clientes,
        detallesPorPedido: detallesPorPedido,
        parametros: parametros,
        vendedores: vendedores,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'pedidos_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf',
      );
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos'),
        actions: [
          if (_sharingDb)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Compartir base de datos',
              onPressed: _compartirDB,
            ),
          if (_generatingPdf)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.picture_as_pdf),
              tooltip: 'PDF todos los pedidos',
              onPressed: _pedidos.isEmpty ? null : _generarPdfTodos,
            ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: Column(children: [
        if (_apiMode)
          SyncHeader(
            lastSync: _lastSync,
            syncing: _syncing,
            onSync: _sync,
            label: 'Pedidos',
          ),
        if (_apiMode)
          SwitchListTile(
            dense: true,
            title: const Text('Solo pendientes'),
            subtitle: const Text('Oculta los pedidos ya remitidos o facturados'),
            value: _soloPendientes,
            onChanged: _setSoloPendientes,
          ),
        Expanded(
          child: _buildLista(),
        ),
      ]),
      floatingActionButton: FloatingActionButton(
        onPressed: _goNuevoPedido,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLista() {
    final pedidos = _visibles;
    if (!_loading && pedidos.isEmpty && _pedidos.isNotEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No hay pedidos pendientes. Apagá "Solo pendientes" para ver los remitidos y facturados.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return _loading
          ? const Center(child: CircularProgressIndicator())
          : _pedidos.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.receipt_long, size: 64, color: Colors.grey),
                      const SizedBox(height: 8),
                      const Text('Sin pedidos registrados'),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _goNuevoPedido,
                        icon: const Icon(Icons.add),
                        label: const Text('Crear primer pedido'),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: pedidos.length,
                    itemBuilder: (_, i) => _PedidoTile(
                      pedido: pedidos[i],
                      clienteRepo: _clienteRepo,
                      simbolo: _simbolo,
                      syncEstado: _apiMode
                          ? (_syncEstados[pedidos[i].id]?.estado ??
                              OutboxEstado.pendiente)
                          : null,
                      estadoErp: _syncEstados[pedidos[i].id]?.estadoErp,
                      editable: _syncEstados[pedidos[i].id]?.editable ?? true,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  PedidoDetalleScreen(idPedido: pedidos[i].id!)),
                        );
                        _load();
                      },
                      onEdit: () async {
                        context.read<PedidoProvider>().reset();
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  NuevoPedidoScreen(editPedidoId: pedidos[i].id!)),
                        );
                        _load();
                      },
                    ),
                  ),
                );
  }

  void _goNuevoPedido() {
    context.read<PedidoProvider>().reset();
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NuevoPedidoScreen()),
    ).then((_) => _load());
  }
}

class _PedidoTile extends StatelessWidget {
  final PedidoCabecera pedido;
  final ClienteRepository clienteRepo;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final String simbolo;
  final OutboxEstado? syncEstado;
  final String? estadoErp;
  final bool editable;

  const _PedidoTile(
      {required this.pedido,
      required this.clienteRepo,
      required this.onTap,
      required this.onEdit,
      required this.simbolo,
      this.syncEstado,
      this.estadoErp,
      this.editable = true});

  ({String label, Color color, IconData icon}) get _chip {
    // Lo que ya hizo el ERP con el pedido manda sobre el estado de subida.
    switch (estadoErp) {
      case 'remitido':
        return (label: 'Remitido', color: Colors.blueGrey, icon: Icons.local_shipping);
      case 'facturado':
        return (label: 'Facturado', color: Colors.blueGrey, icon: Icons.receipt);
      case 'cancelado':
        return (label: 'Cancelado', color: Colors.grey, icon: Icons.block);
    }
    switch (syncEstado) {
      case OutboxEstado.sincronizado:
        return (label: 'Sincronizado', color: Colors.green, icon: Icons.cloud_done);
      case OutboxEstado.error:
        return (label: 'Error de sync', color: Colors.red, icon: Icons.cloud_off);
      case OutboxEstado.pendiente:
      case null:
        return (label: 'Pendiente', color: Colors.orange, icon: Icons.cloud_upload);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          '#${pedido.nroPedido ?? pedido.id}',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
        ),
      ),
      title: FutureBuilder(
        future: clienteRepo.findByCodigo(pedido.codCliente),
        builder: (_, snap) => Text(
          snap.data?.nombre ?? 'Cliente ${pedido.codCliente}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      subtitle: syncEstado == null
          ? Text(pedido.fecha)
          : Row(children: [
              Text(pedido.fecha, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 8),
              Icon(_chip.icon, size: 13, color: _chip.color),
              const SizedBox(width: 3),
              Text(_chip.label,
                  style: TextStyle(fontSize: 11, color: _chip.color)),
            ]),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$simbolo${fmt.format(pedido.total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              if (pedido.firma != null)
                const Icon(Icons.draw, size: 14, color: Colors.green),
            ],
          ),
          IconButton(
            icon: Icon(editable ? Icons.edit_outlined : Icons.lock_outline, size: 20),
            tooltip: editable ? 'Editar' : 'Ya no se puede editar',
            onPressed: editable ? onEdit : null,
          ),
        ],
      ),
      onTap: onTap,
      ),
    );
  }
}
