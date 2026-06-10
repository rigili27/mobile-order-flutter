class Parametros {
  final String razonSocial;
  final String domicilio;
  final String nroCuit;
  final double cotizacion;
  final String ftp;
  final List<int>? logo;
  final String? configuracion;

  const Parametros({
    required this.razonSocial,
    required this.domicilio,
    required this.nroCuit,
    required this.cotizacion,
    required this.ftp,
    this.logo,
    this.configuracion,
  });

  Map<String, String> get _config {
    if (configuracion == null || configuracion!.trim().isEmpty) return {};
    return Map.fromEntries(
      configuracion!.split(';')
          .map((e) => e.split('='))
          .where((e) => e.length == 2)
          .map((e) => MapEntry(e[0].trim(), e[1].trim())),
    );
  }

  bool get monedaDolar => _config['moneda'] == 'dolar';
  bool get ordenPreparacion => _config['orden_preparacion'] == 'true';
  bool get tipoServicio => _config['tipo_servicio'] == 'true';
  bool get pdfLeyendaPrecioSinIva => _config['pdf_leyenda_precio_sin_iva'] == 'true';

  factory Parametros.fromMap(Map<String, dynamic> map) => Parametros(
        razonSocial: (map['RAZONSOCIAL'] as String? ?? '').trim(),
        domicilio: (map['DOMICILIO'] as String? ?? '').trim(),
        nroCuit: (map['NROCUIT'] as String? ?? '').trim(),
        cotizacion: (map['COTIZACION'] as num? ?? 1).toDouble(),
        ftp: (map['FTP'] as String? ?? '').trim(),
        logo: map['LOGO'] != null ? List<int>.from(map['LOGO'] as List) : null,
        configuracion: map.entries
            .where((e) => e.key.toUpperCase() == 'CONFIGURACION')
            .map((e) => e.value as String?)
            .firstOrNull,
      );

  static const empty = Parametros(
    razonSocial: '',
    domicilio: '',
    nroCuit: '',
    cotizacion: 1,
    ftp: '',
  );
}
