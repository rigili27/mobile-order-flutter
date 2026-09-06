class Cliente {
  final int codigo;
  final String nombre;
  final String domicilio;
  final String localidad;
  final String telefono;
  final String nroCuit;
  final int? codCatIva;
  final int nrolPrecios;
  final double saldo;

  /// Id de la lista de precio real del cliente en el ERP (modo API). En modo
  /// WiFi es null y se usa [nrolPrecios] (slot 1..3).
  final int? codLista;

  /// Cliente dado de alta desde la app, a la espera de que el ERP lo revise.
  /// Igual se le pueden cargar pedidos.
  final bool pendiente;

  const Cliente({
    required this.codigo,
    required this.nombre,
    required this.domicilio,
    required this.localidad,
    required this.telefono,
    required this.nroCuit,
    this.codCatIva,
    required this.nrolPrecios,
    required this.saldo,
    this.codLista,
    this.pendiente = false,
  });

  factory Cliente.fromMap(Map<String, dynamic> map) => Cliente(
        codigo: map['CODIGO'] as int,
        nombre: (map['NOMBRE'] as String? ?? '').trim(),
        domicilio: (map['DOMICILIO'] as String? ?? '').trim(),
        localidad: (map['LOCALIDAD'] as String? ?? '').trim(),
        telefono: (map['TELEFONO'] as String? ?? '').trim(),
        nroCuit: (map['NROCUIT'] as String? ?? '').trim(),
        codCatIva: map['CODCATIVA'] as int?,
        nrolPrecios: (map['NROLPRECIOS'] as int?) ?? 1,
        saldo: (map['SALDO'] as num? ?? 0).toDouble(),
        codLista: map['COD_LISTA'] as int?,
        pendiente: (map['PENDIENTE'] as int? ?? 0) == 1,
      );

  Map<String, dynamic> toMap() => {
        'CODIGO': codigo,
        'NOMBRE': nombre,
        'DOMICILIO': domicilio,
        'LOCALIDAD': localidad,
        'TELEFONO': telefono,
        'NROCUIT': nroCuit,
        'CODCATIVA': codCatIva,
        'NROLPRECIOS': nrolPrecios,
        'SALDO': saldo,
        'COD_LISTA': codLista,
        'PENDIENTE': pendiente ? 1 : 0,
      };
}
