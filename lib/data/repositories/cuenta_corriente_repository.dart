import '../../core/database/database_helper.dart';
import '../models/cuenta_corriente_movimiento.dart';

class CuentaCorrienteRepository {
  final _db = DatabaseHelper.instance;

  static const _select = '''
    SELECT m.*, c.NOMBRE AS CLIENTE_NOMBRE, p.FECHA AS PEDIDO_FECHA, p.NROPEDIDO AS PEDIDO_NRO
    FROM PedMCCte m
    LEFT JOIN CliMovil c ON c.CODIGO = m.CODCLIENTE
    LEFT JOIN PedCMovil p ON p.ID = m.IDPEDMOVIL
  ''';

  Future<List<CuentaCorrienteMovimiento>> getAll() async {
    final rows = await _db.db.rawQuery('$_select ORDER BY m.ID DESC');
    return rows.map(CuentaCorrienteMovimiento.fromMap).toList();
  }

  Future<List<CuentaCorrienteMovimiento>> getByCliente(int codCliente) async {
    final rows = await _db.db.rawQuery(
      '$_select WHERE m.CODCLIENTE = ? ORDER BY m.ID DESC',
      [codCliente],
    );
    return rows.map(CuentaCorrienteMovimiento.fromMap).toList();
  }

  /// Borra y vuelve a crear el movimiento asociado a un pedido (alta o re-guardado).
  Future<void> syncMovimientoPedido({
    required int idPedido,
    required int codCliente,
    required String tipoVenta,
    required double total,
  }) async {
    await _db.db.delete('PedMCCte', where: 'IDPEDMOVIL = ?', whereArgs: [idPedido]);
    final importe = tipoVenta == 'C' ? -total.abs() : total.abs();
    await _db.db.insert(
      'PedMCCte',
      CuentaCorrienteMovimiento(
        idPedMovil: idPedido,
        codCliente: codCliente,
        tipoVenta: tipoVenta,
        importe: importe,
      ).toMap(),
    );
  }

  Future<void> deleteMovimientosPedido(int idPedido) async {
    await _db.db.delete('PedMCCte', where: 'IDPEDMOVIL = ?', whereArgs: [idPedido]);
  }

  Future<int> insertManual(CuentaCorrienteMovimiento mov) async {
    return await _db.db.insert('PedMCCte', mov.toMap());
  }
}
