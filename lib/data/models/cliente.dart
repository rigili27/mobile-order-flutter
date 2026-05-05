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
      };
}
