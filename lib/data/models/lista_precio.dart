/// Lista de precio del ERP (modo API), cacheada en `ListaPrecioMovil`.
class ListaPrecio {
  final int codigo;
  final String nombre;

  const ListaPrecio({required this.codigo, required this.nombre});

  factory ListaPrecio.fromMap(Map<String, dynamic> m) => ListaPrecio(
        codigo: m['CODIGO'] as int,
        nombre: (m['NOMBRE'] as String? ?? '').trim(),
      );
}
