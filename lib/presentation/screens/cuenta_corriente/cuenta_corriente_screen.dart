import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/cuenta_corriente_movimiento.dart';
import '../../../data/repositories/cuenta_corriente_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../pedidos/pedido_detalle_screen.dart';

/// Listado global de movimientos de cuenta corriente (todos los clientes).
class CuentaCorrienteScreen extends StatefulWidget {
  const CuentaCorrienteScreen({super.key});

  @override
  State<CuentaCorrienteScreen> createState() => _CuentaCorrienteScreenState();
}

class _CuentaCorrienteScreenState extends State<CuentaCorrienteScreen> {
  final _repo = CuentaCorrienteRepository();
  List<CuentaCorrienteMovimiento> _movimientos = [];
  bool _loading = true;
  String _simbolo = '\$';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final movimientos = await _repo.getAll();
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
  final CuentaCorrienteMovimiento movimiento;
  final String simbolo;

  const _MovimientoTile({required this.movimiento, required this.simbolo});

  static const _tipoVentaLabels = {
    'C': 'Cuenta Corriente',
    'E': 'Efectivo',
    'T': 'Transferencia',
  };

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    final esDebe = movimiento.importe < 0;
    final color = esDebe ? Colors.red.shade700 : Colors.green.shade700;
    final tienePedido = movimiento.idPedMovil != null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(esDebe ? Icons.arrow_upward : Icons.arrow_downward,
              color: color, size: 20),
        ),
        title: Text(
          movimiento.clienteNombre ?? 'Cliente ${movimiento.codCliente}',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${_tipoVentaLabels[movimiento.tipoVenta] ?? movimiento.tipoVenta}'
          '${tienePedido ? ' · Pedido #${movimiento.pedidoNro ?? movimiento.idPedMovil}'
              '${movimiento.pedidoFecha != null ? ' · ${movimiento.pedidoFecha}' : ''}' : ' (manual)'}',
        ),
        trailing: Text(
          '$simbolo${fmt.format(movimiento.importe)}',
          style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
        ),
        onTap: tienePedido
            ? () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PedidoDetalleScreen(idPedido: movimiento.idPedMovil!)),
                )
            : null,
      ),
    );
  }
}
