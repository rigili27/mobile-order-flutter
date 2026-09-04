import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/cobranza.dart';
import '../../../data/models/movimiento_cta_cte_vista.dart';
import '../../../data/repositories/cuenta_corriente_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../pedidos/pedido_detalle_screen.dart';

/// Listado global de movimientos de cuenta corriente (todos los clientes).
/// En modo API incluye las cobranzas registradas desde la app, incluso las
/// que el ERP todavía no confirmó.
class CuentaCorrienteScreen extends StatefulWidget {
  const CuentaCorrienteScreen({super.key});

  @override
  State<CuentaCorrienteScreen> createState() => _CuentaCorrienteScreenState();
}

class _CuentaCorrienteScreenState extends State<CuentaCorrienteScreen> {
  final _repo = CuentaCorrienteRepository();
  List<MovimientoCtaCteVista> _movimientos = [];
  bool _loading = true;
  String _simbolo = '\$';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final movimientos = await _repo.getVistaAll();
    final simbolo = await ParametrosRepository.simboloMoneda();
    if (mounted) {
      setState(() {
        _movimientos = movimientos;
        _simbolo = simbolo;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuenta Corriente'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _movimientos.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 64, color: Colors.grey),
                      SizedBox(height: 8),
                      Text('Sin movimientos de cuenta corriente'),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    itemCount: _movimientos.length,
                    itemBuilder: (_, i) => _MovimientoTile(
                      movimiento: _movimientos[i],
                      simbolo: _simbolo,
                    ),
                  ),
                ),
    );
  }
}

class _MovimientoTile extends StatelessWidget {
  final MovimientoCtaCteVista movimiento;
  final String simbolo;

  const _MovimientoTile({required this.movimiento, required this.simbolo});

  static const _formaPagoLabels = {
    CobranzaFormaPago.efectivo: 'Efectivo',
    CobranzaFormaPago.cheque: 'Cheque',
    CobranzaFormaPago.transferencia: 'Transferencia',
  };

  static const _estadoLabels = {
    EstadoCobranzaSync.pendienteSubir: 'Pendiente de subir',
    EstadoCobranzaSync.sinConfirmar: 'Sin confirmar',
    EstadoCobranzaSync.confirmada: 'Confirmada',
  };

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    final esDebe = movimiento.importe < 0;
    final color = esDebe ? Colors.red.shade700 : Colors.green.shade700;
    final esCobranza = movimiento.origen == MovimientoOrigen.cobranza;
    final tienePedido = movimiento.idPedido != null;

    final subtitlePartes = <String>[
      if (esCobranza)
        'Cobranza · ${_formaPagoLabels[movimiento.formaPago] ?? ''}'
      else if (tienePedido)
        'Pedido'
      else
        'Movimiento manual',
      if (movimiento.fecha != null) movimiento.fecha!,
      if (esCobranza && movimiento.estadoSync != null)
        _estadoLabels[movimiento.estadoSync!]!,
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
        title: Text(
          movimiento.clienteNombre ?? 'Cliente ${movimiento.codCliente}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitlePartes.join(' · ')),
        trailing: Text(
          '$simbolo${fmt.format(movimiento.importe)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
        ),
        onTap: tienePedido
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PedidoDetalleScreen(idPedido: movimiento.idPedido!)),
                )
            : null,
      ),
    );
  }
}
