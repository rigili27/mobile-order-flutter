class Parametros {
  final String razonSocial;
  final String domicilio;
  final String nroCuit;
  final double cotizacion;
  final String ftp;
  final List<int>? logo;

  const Parametros({
    required this.razonSocial,
    required this.domicilio,
    required this.nroCuit,
    required this.cotizacion,
    required this.ftp,
    this.logo,
  });

  factory Parametros.fromMap(Map<String, dynamic> map) => Parametros(
        razonSocial: (map['RAZONSOCIAL'] as String? ?? '').trim(),
        domicilio: (map['DOMICILIO'] as String? ?? '').trim(),
        nroCuit: (map['NROCUIT'] as String? ?? '').trim(),
        cotizacion: (map['COTIZACION'] as num? ?? 1).toDouble(),
        ftp: (map['FTP'] as String? ?? '').trim(),
        logo: map['LOGO'] != null ? List<int>.from(map['LOGO'] as List) : null,
      );

  static const empty = Parametros(
    razonSocial: '',
    domicilio: '',
    nroCuit: '',
    cotizacion: 1,
    ftp: '',
  );
}
