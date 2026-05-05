class Deposito {
  final int id;
  final int codigo;
  final int codArticulo;
  final String descripcion;
  final String descArticulo;
  final double stock;

  const Deposito({
    required this.id,
    required this.codigo,
    required this.codArticulo,
    required this.descripcion,
    required this.descArticulo,
    required this.stock,
  });

  factory Deposito.fromMap(Map<String, dynamic> map) => Deposito(
        id: map['ID'] as int,
        codigo: map['CODIGO'] as int,
        codArticulo: map['CODARTICULO'] as int,
        descripcion: (map['DESCRIPCION'] as String? ?? '').trim(),
        descArticulo: (map['DESCARTICULO'] as String? ?? '').trim(),
        stock: (map['STOCK'] as num? ?? 0).toDouble(),
      );
}
