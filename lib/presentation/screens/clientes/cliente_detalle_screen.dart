import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/cobranza.dart';
import '../../../data/models/cuenta_corriente_movimiento.dart';
import '../../../data/models/movimiento_cta_cte_vista.dart';
import '../../../data/models/pedido_cabecera.dart';
import '../../../core/api/api_config.dart';
import '../../../data/repositories/cuenta_corriente_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../data/repositories/pedido_repository.dart';
import '../../providers/pedido_provider.dart';
import '../cobranzas/nueva_cobranza_screen.dart';
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
  final _ctaCteRepo = CuentaCorrienteRepository();
  List<PedidoCabecera> _pedidos = [];
  List<MovimientoCtaCteVista> _movimientos = [];
  bool _loadingPedidos = true;
  bool _loadingMovimientos = true;
  String _simbolo = '\$';
  bool _ctaCteActivo = false;
  bool _apiMode = false;

  @override
  void initState() {
    super.initState();
    _loadPedidos();
    _init();
  }

  Future<void> _init() async {
    final ctaCte = await ParametrosRepository.ctaCteActivo();
    final apiMode = await ApiConfig.isConfigured();
    if (!mounted) return;
    setState(() {
      _ctaCteActivo = ctaCte;
      _apiMode = apiMode;
    });
    if (ctaCte) _loadMovimientos();
  }

  Future<void> _loadPedidos() async {
    final pedidos = await _pedidoRepo.getByCliente(widget.cliente.codigo);
    final simbolo = await ParametrosRepository.simboloMoneda();
    if (mounted) setState(() { _pedidos = pedidos; _loadingPedidos = false; _simbolo = simbolo; });
  }

  Future<void> _loadMovimientos() async {
    final movimientos = _apiMode
        ? await _ctaCteRepo.getVistaByCliente(widget.cliente.codigo)
        : (await _ctaCteRepo.getByCliente(widget.cliente.codigo))
            .map(MovimientoCtaCteVista.dePedMcCte)
            .toList();
    if (mounted) {
      setState(() {
        _movimientos = movimientos;
        _loadingMovimientos = false;
      });
    }
  }

  double get _cobranzasSinConfirmar => _movimientos
      .where((m) => m.esCobranzaNoConfirmada)
      .fold(0.0, (sum, m) => sum + m.importe);

  void _nuevoMovimientoCtaCte() {
    // Modo API: la cobranza se sube al ERP como un Receipt en Borrador.
    if (_apiMode) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => NuevaCobranzaScreen(cliente: widget.cliente),
        ),
      ).then((_) => _loadMovimientos());
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _MovimientoCtaCteSheet(codCliente: widget.cliente.codigo),
    ).then((_) => _loadMovimientos());
  }

  void _goNuevoPedido() {
    context.read<PedidoProvider>()
      ..reset()
      ..setCliente(widget.cliente);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NuevoPedidoScreen()),
    ).then((_) {
      _loadPedidos();
      if (_ctaCteActivo) _loadMovimientos();
    });
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
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadPedidos();
              if (_ctaCteActivo) _loadMovimientos();
            },
          ),
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
                Text(_cobranzasSinConfirmar > 0 ? 'Saldo confirmado' : 'Saldo',
                    style: TextStyle(color: saldoColor, fontSize: 14)),
                const SizedBox(height: 4),
                Text(
                  fmt.format(widget.cliente.saldo),
                  style: TextStyle(
                      color: saldoColor,
                      fontSize: 28,
                      fontWeight: FontWeight.bold),
                ),
                if (_cobranzasSinConfirmar > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Cobranzas sin confirmar: -${fmt.format(_cobranzasSinConfirmar)}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  Text(
                    'Saldo proyectado: ${fmt.format(widget.cliente.saldo - _cobranzasSinConfirmar)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
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
          if (_ctaCteActivo) ...[
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _nuevoMovimientoCtaCte,
              icon: Icon(_apiMode
                  ? Icons.payments_outlined
                  : Icons.account_balance_wallet_outlined),
              label: Text(_apiMode
                  ? 'Nueva cobranza'
                  : 'Nuevo movimiento de cuenta corriente'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade700,
                  foregroundColor: Colors.white),
            ),
          ],
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
                    if (_ctaCteActivo) _loadMovimientos();
                  },
                ))),

          if (_ctaCteActivo) ...[
            const SizedBox(height: 24),
            // ── Movimientos de cuenta corriente ─────────────────────────────
            Row(children: [
              const Icon(Icons.account_balance_wallet_outlined,
                  size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                'MOVIMIENTOS DE CUENTA CORRIENTE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary,
                  letterSpacing: 1.2,
                ),
              ),
              if (_movimientos.isNotEmpty) ...[
                const SizedBox(width: 8),
                Chip(
                  label: Text('${_movimientos.length}',
                      style: const TextStyle(fontSize: 11)),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ]),
            const SizedBox(height: 8),
            if (_loadingMovimientos)
              const Center(child: CircularProgressIndicator())
            else if (_movimientos.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 40, color: Colors.grey.shade400),
                    const SizedBox(height: 8),
                    const Text('Sin movimientos de cuenta corriente',
                        style: TextStyle(color: Colors.grey)),
                  ]),
                ),
              )
            else
              ..._movimientos.map((m) => _MovimientoTile(
                    movimiento: m,
                    simbolo: _simbolo,
                    onTap: m.idPedido == null
                        ? null
                        : () async {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => PedidoDetalleScreen(
                                      idPedido: m.idPedido!)),
                            );
                            _loadMovimientos();
                          },
                  )),
          ],

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

class _MovimientoTile extends StatelessWidget {
  final MovimientoCtaCteVista movimiento;
  final String simbolo;
  final VoidCallback? onTap;

  const _MovimientoTile({required this.movimiento, required this.simbolo, this.onTap});

  static const _formaPagoLabels = {
    CobranzaFormaPago.efectivo: 'Efectivo',
    CobranzaFormaPago.cheque: 'Cheque',
    CobranzaFormaPago.transferencia: 'Transferencia',
  };

  ({String label, Color color}) _estadoChip(EstadoCobranzaSync e) {
    switch (e) {
      case EstadoCobranzaSync.pendienteSubir:
        return (label: 'Pendiente de subir', color: Colors.orange);
      case EstadoCobranzaSync.sinConfirmar:
        return (label: 'Sin confirmar', color: Colors.blueGrey);
      case EstadoCobranzaSync.confirmada:
        return (label: 'Confirmada', color: Colors.green);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    final esDebe = movimiento.importe < 0;
    final color = esDebe ? Colors.red.shade700 : Colors.green.shade700;
    final esCobranza = movimiento.origen == MovimientoOrigen.cobranza;

    final titulo = switch (movimiento.origen) {
      MovimientoOrigen.pedido =>
        'Pedido #${movimiento.idPedido}',
      MovimientoOrigen.manual => 'Movimiento manual',
      MovimientoOrigen.cobranza =>
        'Cobranza · ${_formaPagoLabels[movimiento.formaPago] ?? ''}',
    };

    Widget? subtitle;
    if (esCobranza && movimiento.estadoSync != null) {
      final chip = _estadoChip(movimiento.estadoSync!);
      subtitle = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(children: [
          if (movimiento.fecha != null) ...[
            Text(movimiento.fecha!,
                style: const TextStyle(fontSize: 12, color: Colors.grey)),
            const SizedBox(width: 8),
          ],
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: chip.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(chip.label,
                style: TextStyle(fontSize: 11, color: chip.color)),
          ),
        ]),
      );
    } else if (movimiento.fecha != null) {
      subtitle = Text(movimiento.fecha!);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(
              esCobranza
                  ? Icons.payments_outlined
                  : (esDebe ? Icons.arrow_upward : Icons.arrow_downward),
              color: color,
              size: 20),
        ),
        title: Text(titulo),
        subtitle: subtitle,
        trailing: Text(
          '$simbolo${fmt.format(movimiento.importe)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
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

// ── Sheet para alta manual de movimiento de cuenta corriente ──────────────────

class _MovimientoCtaCteSheet extends StatefulWidget {
  final int codCliente;

  const _MovimientoCtaCteSheet({required this.codCliente});

  @override
  State<_MovimientoCtaCteSheet> createState() => _MovimientoCtaCteSheetState();
}

class _MovimientoCtaCteSheetState extends State<_MovimientoCtaCteSheet> {
  final _importeCtrl = TextEditingController();
  String _tipoVenta = 'E';
  bool _saving = false;

  static const _tipoVentaOpciones = {
    'E': 'Efectivo',
    'T': 'Transferencia',
  };

  @override
  void dispose() {
    _importeCtrl.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final valor = double.tryParse(_importeCtrl.text.replaceAll(',', '.')) ?? 0;
    if (valor <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('El importe debe ser mayor a 0.')));
      return;
    }
    setState(() => _saving = true);
    await CuentaCorrienteRepository().insertManual(CuentaCorrienteMovimiento(
      codCliente: widget.codCliente,
      tipoVenta: _tipoVenta,
      importe: valor.abs(),
    ));
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Movimiento registrado.')));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Nuevo movimiento de cuenta corriente',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          TextField(
            controller: _importeCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
            decoration: const InputDecoration(
              labelText: 'Importe',
              prefixIcon: Icon(Icons.attach_money),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(
              labelText: 'Tipo de venta',
              prefixIcon: Icon(Icons.payments_outlined),
              border: OutlineInputBorder(),
            ),
            value: _tipoVenta,
            items: _tipoVentaOpciones.entries
                .map((e) => DropdownMenuItem<String>(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) => setState(() => _tipoVenta = v ?? 'E'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _confirm,
            child: const Text('Guardar'),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
