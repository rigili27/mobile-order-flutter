import '../../core/database/database_helper.dart';
import '../models/cuenta_corriente_movimiento.dart';
import '../models/movimiento_cta_cte_vista.dart';
import 'cobranza_repository.dart';

class CuentaCorrienteRepository {
  final _db = DatabaseHelper.instance;
  final _cobranzaRepo = CobranzaRepository();

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

  /// Listado unificado para modo API: los `PedMCCte` + las cobranzas locales
  /// (incluso sin confirmar por el ERP), ordenado por fecha desc.
  Future<List<MovimientoCtaCteVista>> getVistaByCliente(int codCliente) async {
    final movimientos = await getByCliente(codCliente);
    final cobranzas = await _cobranzaRepo.getByCliente(codCliente);

    final vistas = <MovimientoCtaCteVista>[
      ...movimientos.map(MovimientoCtaCteVista.dePedMcCte),
    ];
    for (final c in cobranzas) {
      final estado =
          c.id == null ? null : (await _cobranzaRepo.estadoDe(c.id!))?.estado;
      vistas.add(MovimientoCtaCteVista.deCobranza(c, estado));
    }
    _ordenar(vistas);
    return vistas;
  }

  /// Idem [getVistaByCliente] pero para todos los clientes (listado global).
  Future<List<MovimientoCtaCteVista>> getVistaAll() async {
    final movimientos = await getAll();
    final cobranzas = await _cobranzaRepo.getAll();

    final vistas = <MovimientoCtaCteVista>[
      ...movimientos.map(MovimientoCtaCteVista.dePedMcCte),
    ];
    for (final c in cobranzas) {
      final estado =
          c.id == null ? null : (await _cobranzaRepo.estadoDe(c.id!))?.estado;
      vistas.add(MovimientoCtaCteVista.deCobranza(c, estado));
    }
    _ordenar(vistas);
    return vistas;
  }

  void _ordenar(List<MovimientoCtaCteVista> vistas) {
    vistas.sort((a, b) {
      final fa = a.fecha ?? '';
      final fb = b.fecha ?? '';
      return fb.compareTo(fa); // yyyy-MM-dd ordena lexicográficamente
    });
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
