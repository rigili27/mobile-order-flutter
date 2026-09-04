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
  bool get nroPedidoVisible => _config['nropedido'] == 'true';
  bool get ctaCteActivo => _config['cta_cte'] == 'true';

  /// Confirmación que manda el ERP de que la base viene de la API. El switch
  /// real de modo lo maneja `ApiConfig`; esto es solo informativo.
  bool get apiActivo => _config['api'] == 'true';

  // Funciones habilitadas por vendedor (Preventa → Config. de la app). El
  // ERP las manda siempre explícitas (`=true`/`=false`); si faltan (base
  // vieja sin resincronizar) caen al mismo default que el backend:
  // habilitadas las que ya existían, apagadas las nuevas.
  bool get permitePedidos => _config['permite_pedidos'] != 'false';
  bool get permiteCobranzas => _config['permite_cobranzas'] != 'false';
  bool get permiteAltaClientes => _config['permite_alta_clientes'] != 'false';
  bool get permiteAltaArticulos => _config['permite_alta_articulos'] != 'false';
  bool get permiteVerPrecios => _config['permite_ver_precios'] != 'false';
  bool get permiteStock => _config['permite_stock'] == 'true';
  bool get permiteGenerarCompra => _config['permite_generar_compra'] == 'true';

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
