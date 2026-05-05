class Vendedor {
  final int codigo;
  final String nombre;
  final String clave;

  const Vendedor({
    required this.codigo,
    required this.nombre,
    required this.clave,
  });

  factory Vendedor.fromMap(Map<String, dynamic> map) => Vendedor(
        codigo: map['CODIGO'] as int,
        nombre: (map['NOMBRE'] as String? ?? '').trim(),
        clave: (map['CLAVE'] as String? ?? '').trim(),
      );

  Map<String, dynamic> toMap() => {
        'CODIGO': codigo,
        'NOMBRE': nombre,
        'CLAVE': clave,
      };
}
