class Articulo {
  final int codigo;
  final String descripcion;
  final int? unidad;
  final double stockActual;
  final double prevtaPub1;
  final double prevtaPub2;
  final double prevtaPub3;
  final double alicuota;
  final int? moneda;
  final String codigoBarra;
  final String sku;

  /// Artículo provisorio creado desde la app, a la espera de confirmación del
  /// ERP. Igual se puede usar en un pedido.
  final bool pendiente;

  /// Precio por lista de precio real del ERP (modo API): `codLista -> precio`.
  /// Vacío en modo WiFi — ahí se usan los slots [prevtaPub1..3].
  final Map<int, double> precios;

  const Articulo({
    required this.codigo,
    required this.descripcion,
    this.unidad,
    required this.stockActual,
    required this.prevtaPub1,
    required this.prevtaPub2,
    required this.prevtaPub3,
    required this.alicuota,
    this.moneda,
    required this.codigoBarra,
    required this.sku,
    this.pendiente = false,
    this.precios = const {},
  });

  factory Articulo.fromMap(Map<String, dynamic> map) => Articulo(
        codigo: map['CODIGO'] as int,
        descripcion: (map['DESCRIPCION'] as String? ?? '').trim(),
        unidad: map['UNIDAD'] as int?,
        stockActual: (map['STOCKACTUAL'] as num? ?? 0).toDouble(),
        prevtaPub1: (map['PREVTAPUB1'] as num? ?? 0).toDouble(),
        prevtaPub2: (map['PREVTAPUB2'] as num? ?? 0).toDouble(),
        prevtaPub3: (map['PREVTAPUB3'] as num? ?? 0).toDouble(),
        alicuota: (map['ALICUTA'] as num? ?? 0).toDouble(),
        moneda: map['MONEDA'] as int?,
        codigoBarra: (map['CODIGOBARRA'] as String? ?? '').trim(),
        sku: (map['SKU'] as String? ?? '').trim(),
        pendiente: (map['PENDIENTE'] as int? ?? 0) == 1,
        precios: preciosFromMap(map['__precios']),
      );

  /// `map['__precios']` es una lista de `{COD_LISTA, PRECIO}` inyectada por
  /// [ArticuloRepository] cuando lee las listas del ERP (tabla ArtMovilPrecio).
  static Map<int, double> preciosFromMap(Object? raw) {
    if (raw is! List) return const {};
    return {
      for (final r in raw.whereType<Map>())
        (r['COD_LISTA'] as num).toInt(): (r['PRECIO'] as num? ?? 0).toDouble(),
    };
  }

  Map<String, dynamic> toMap() => {
        'CODIGO': codigo,
        'DESCRIPCION': descripcion,
        'UNIDAD': unidad,
        'STOCKACTUAL': stockActual,
        'PREVTAPUB1': prevtaPub1,
        'PREVTAPUB2': prevtaPub2,
        'PREVTAPUB3': prevtaPub3,
        'ALICUTA': alicuota,
        'MONEDA': moneda,
        'CODIGOBARRA': codigoBarra,
        'SKU': sku,
        'PENDIENTE': pendiente ? 1 : 0,
      };

  /// Precio bajo el slot 1..3 (modo WiFi / catálogo base).
  double precioParaLista(int nrolPrecios) {
    return switch (nrolPrecios) {
      2 => prevtaPub2,
      3 => prevtaPub3,
      _ => prevtaPub1,
    };
  }

  /// Precio bajo una lista real del ERP (modo API). Cae al slot 1 si esa
  /// lista no vino en el detalle.
  double precioParaListaId(int? codLista) {
    if (codLista != null && precios.containsKey(codLista)) {
      return precios[codLista]!;
    }
    return prevtaPub1;
  }

  bool get esDolar => moneda == 2;
}
