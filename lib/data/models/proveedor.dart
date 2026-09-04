class Proveedor {
  final int codigo;
  final String nombre;

  const Proveedor({required this.codigo, required this.nombre});

  factory Proveedor.fromMap(Map<String, dynamic> map) => Proveedor(
        codigo: map['CODIGO'] as int,
        nombre: (map['NOMBRE'] as String? ?? '').trim(),
      );
}
