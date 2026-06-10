import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/pedido_cabecera.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../data/repositories/pedido_repository.dart';
import '../../providers/pedido_provider.dart';
import '../pedidos/nuevo_pedido_screen.dart';
import '../pedidos/pedido_detalle_screen.dart';

class ClienteDetalleScreen extends StatefulWidget {
  final Cliente cliente;

  const ClienteDetalleScreen({super.key, required this.cliente});

  @override
  State<ClienteDetalleScreen> createState() => _ClienteDetalleScreenState();
}

class _ClienteDetalleScreenState extends State<ClienteDetalleScreen> {
  final _pedidoRepo = PedidoRepository();
  List<PedidoCabecera> _pedidos = [];
  bool _loadingPedidos = true;
  String _simbolo = '\$';

  @override
  void initState() {
    super.initState();
    _loadPedidos();
  }

  Future<void> _loadPedidos() async {
    final pedidos = await _pedidoRepo.getByCliente(widget.cliente.codigo);
    final simbolo = await ParametrosRepository.simboloMoneda();
    if (mounted) setState(() { _pedidos = pedidos; _loadingPedidos = false; _simbolo = simbolo; });
  }

  void _goNuevoPedido() {
    context.read<PedidoProvider>()
      ..reset()
      ..setCliente(widget.cliente);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NuevoPedidoScreen()),
    ).then((_) => _loadPedidos());
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    final saldoColor =
        widget.cliente.saldo > 0 ? Colors.red.shade700 : Colors.green.shade700;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.cliente.nombre),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadPedidos),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Info del cliente ───────────────────────────────────────────────
          _InfoCard(children: [
            _Row(Icons.numbers, 'Código', widget.cliente.codigo.toString()),
            _Row(Icons.person, 'Nombre', widget.cliente.nombre),
            _Row(Icons.home, 'Domicilio', widget.cliente.domicilio),
            _Row(Icons.location_city, 'Localidad', widget.cliente.localidad),
            if (widget.cliente.telefono.isNotEmpty)
              _Row(Icons.phone, 'Teléfono', widget.cliente.telefono),
            _Row(Icons.badge, 'CUIT', widget.cliente.nroCuit),
            _Row(Icons.price_change, 'Lista de precios',
                'Lista ${widget.cliente.nrolPrecios}'),
          ]),
          const SizedBox(height: 16),

          // ── Saldo ──────────────────────────────────────────────────────────
          Card(
            color: widget.cliente.saldo > 0
                ? Colors.red.shade50
                : Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Text('Saldo',
                    style: TextStyle(color: saldoColor, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  fmt.format(widget.cliente.saldo),
                  style: TextStyle(
                      color: saldoColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Nuevo pedido ───────────────────────────────────────────────────
          ElevatedButton.icon(
            onPressed: _goNuevoPedido,
            icon: const Icon(Icons.add_shopping_cart),
            label: const Text('Nuevo Pedido para este cliente'),
          ),
          const SizedBox(height: 24),

          // ── Pedidos del cliente ────────────────────────────────────────────
          Row(children: [
            const Icon(Icons.receipt_long, size: 18, color: Colors.grey),
            const SizedBox(width: 6),
            Text(
              'PEDIDOS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.2,
              ),
            ),
            if (_pedidos.isNotEmpty) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text('${_pedidos.length}',
                    style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ]),
          const SizedBox(height: 8),

          if (_loadingPedidos)
            const Center(child: CircularProgressIndicator())
          else if (_pedidos.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(children: [
                  Icon(Icons.receipt_long, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  const Text('Sin pedidos para este cliente',
                      style: TextStyle(color: Colors.grey)),
                ]),
              ),
            )
          else
            ...(_pedidos.map((p) => _PedidoClienteTile(
                  pedido: p,
                  simbolo: _simbolo,
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PedidoDetalleScreen(idPedido: p.id!)),
                    );
                    _loadPedidos();
                  },
                ))),

          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _PedidoClienteTile extends StatelessWidget {
  final PedidoCabecera pedido;
  final VoidCallback onTap;
  final String simbolo;

  const _PedidoClienteTile({required this.pedido, required this.onTap, required this.simbolo});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            '#${pedido.nroPedido ?? pedido.id}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(pedido.fecha),
        subtitle: pedido.quienRecibio.isNotEmpty
            ? Text('Recibió: ${pedido.quienRecibio}',
                style: const TextStyle(fontSize: 12))
            : null,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$simbolo${fmt.format(pedido.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            if (pedido.firma != null)
              const Icon(Icons.draw, size: 14, color: Colors.green),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final List<Widget> children;

  const _InfoCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: children),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _Row(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
