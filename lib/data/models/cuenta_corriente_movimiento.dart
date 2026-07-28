class CuentaCorrienteMovimiento {
  final int? id;
  final int? idPedMovil; // null = movimiento manual, sin pedido asociado
  final int codCliente;
  final String tipoVenta; // 'C' | 'E' | 'T'
  final double importe; // negativo = debe, positivo = haber

  // Campos de solo lectura para listados (vienen de un JOIN, no se persisten).
  final String? clienteNombre;
  final String? pedidoFecha;
  final int? pedidoNro;

  CuentaCorrienteMovimiento({
    this.id,
    this.idPedMovil,
    required this.codCliente,
    required this.tipoVenta,
    required this.importe,
    this.clienteNombre,
    this.pedidoFecha,
    this.pedidoNro,
  });

  factory CuentaCorrienteMovimiento.fromMap(Map<String, dynamic> map) =>
      CuentaCorrienteMovimiento(
        id: map['ID'] as int?,
        idPedMovil: map['IDPEDMOVIL'] as int?,
        codCliente: map['CODCLIENTE'] as int,
        tipoVenta: (map['TIPOVENTA'] as String? ?? '').trim(),
        importe: (map['IMPORTE'] as num? ?? 0).toDouble(),
        clienteNombre: map['CLIENTE_NOMBRE'] as String?,
        pedidoFecha: map['PEDIDO_FECHA'] as String?,
        pedidoNro: map['PEDIDO_NRO'] as int?,
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'ID': id,
        'IDPEDMOVIL': idPedMovil,
        'CODCLIENTE': codCliente,
        'TIPOVENTA': tipoVenta,
        'IMPORTE': importe,
      };
}
