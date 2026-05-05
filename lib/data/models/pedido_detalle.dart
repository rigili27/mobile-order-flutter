class PedidoDetalle {
  final int? id;
  final int idPedido;
  final int codArticulo;
  final double cantidad;
  final double precio;
  final double importe;
  final int? unidad;
  final double porDto;
  final String comentario;
  final int? deposito;

  // Campos extendidos (join con ArtMovil)
  final String? descripcionArticulo;
  final String sku;

  const PedidoDetalle({
    this.id,
    required this.idPedido,
    required this.codArticulo,
    required this.cantidad,
    required this.precio,
    required this.importe,
    this.unidad,
    this.porDto = 0,
    this.comentario = '',
    this.deposito,
    this.descripcionArticulo,
    this.sku = '',
  });

  factory PedidoDetalle.fromMap(Map<String, dynamic> map) => PedidoDetalle(
        id: map['ID'] as int?,
        idPedido: map['IDPEDIDO'] as int,
        codArticulo: map['CODARTICULO'] as int,
        cantidad: (map['CANTIDAD'] as num? ?? 0).toDouble(),
        precio: (map['PRECIO'] as num? ?? 0).toDouble(),
        importe: (map['IMPORTE'] as num? ?? 0).toDouble(),
        unidad: map['UNIDAD'] as int?,
        porDto: (map['PORDTO'] as num? ?? 0).toDouble(),
        comentario: (map['COMENTARIO'] as String? ?? '').trim(),
        deposito: map['DEPOSITO'] as int?,
        descripcionArticulo: map['DESCRIPCION'] as String?,
        sku: (map['SKU'] as String? ?? '').trim(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'ID': id,
        'IDPEDIDO': idPedido,
        'CODARTICULO': codArticulo,
        'CANTIDAD': cantidad,
        'PRECIO': precio,
        'IMPORTE': importe,
        'UNIDAD': unidad,
        'PORDTO': porDto,
        'COMENTARIO': comentario,
        'DEPOSITO': deposito,
      };

  static double calcularImporte(double cantidad, double precio, double porDto) =>
      cantidad * precio * (1 - porDto / 100);

  PedidoDetalle copyWith({
    double? cantidad,
    double? precio,
    double? porDto,
    String? comentario,
    int? deposito,
  }) {
    final c = cantidad ?? this.cantidad;
    final p = precio ?? this.precio;
    final d = porDto ?? this.porDto;
    return PedidoDetalle(
      id: id,
      idPedido: idPedido,
      codArticulo: codArticulo,
      cantidad: c,
      precio: p,
      importe: calcularImporte(c, p, d),
      unidad: unidad,
      porDto: d,
      comentario: comentario ?? this.comentario,
      deposito: deposito ?? this.deposito,
      descripcionArticulo: descripcionArticulo,
      sku: sku,
    );
  }
}
