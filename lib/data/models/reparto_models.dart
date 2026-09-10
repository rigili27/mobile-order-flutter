import 'dart:convert';

// Modelos del modo repartidor. Espejan el payload de
// `GET /api/{tenant}/reparto/hojas-de-ruta` del ERP (DeliveryDriverService).

class ParadaRenglon {
  final int? stockMovementId;
  final String articulo;
  final String? sku;
  final double cantidad;
  final double entregado;

  ParadaRenglon({
    this.stockMovementId,
    required this.articulo,
    this.sku,
    required this.cantidad,
    required this.entregado,
  });

  factory ParadaRenglon.fromApi(Map<String, dynamic> j) => ParadaRenglon(
        stockMovementId: (j['stockMovementId'] as num?)?.toInt(),
        articulo: (j['articulo'] as String?) ?? '—',
        sku: j['sku'] as String?,
        cantidad: (j['cantidad'] as num?)?.toDouble() ?? 0,
        entregado: (j['entregado'] as num?)?.toDouble() ?? 0,
      );

  factory ParadaRenglon.fromRow(Map<String, dynamic> r) => ParadaRenglon(
        stockMovementId: r['stock_movement_id'] as int?,
        articulo: (r['articulo'] as String?) ?? '—',
        sku: r['sku'] as String?,
        cantidad: (r['cantidad'] as num?)?.toDouble() ?? 0,
        entregado: (r['entregado'] as num?)?.toDouble() ?? 0,
      );

  Map<String, dynamic> toRow(int paradaId) => {
        'parada_id': paradaId,
        'stock_movement_id': stockMovementId,
        'articulo': articulo,
        'sku': sku,
        'cantidad': cantidad,
        'entregado': entregado,
      };
}

class Parada {
  final int id;
  final int hojaId;
  final int orden;
  final String estado;
  final int? remitoId;
  final String cliente;
  final String? telefono;
  final String? direccion;
  final double? lat;
  final double? lng;
  final DateTime? ventanaDesde;
  final DateTime? ventanaHasta;
  final String? instrucciones;
  final List<ParadaRenglon> renglones;

  Parada({
    required this.id,
    required this.hojaId,
    required this.orden,
    required this.estado,
    this.remitoId,
    required this.cliente,
    this.telefono,
    this.direccion,
    this.lat,
    this.lng,
    this.ventanaDesde,
    this.ventanaHasta,
    this.instrucciones,
    this.renglones = const [],
  });

  bool get resuelta =>
      const ['entregada', 'parcial', 'no_entregada', 'reprogramada'].contains(estado);

  static String estadoLabel(String e) => switch (e) {
        'pendiente' => 'Pendiente',
        'en_camino' => 'En camino',
        'entregada' => 'Entregada',
        'parcial' => 'Entrega parcial',
        'no_entregada' => 'No entregada',
        'reprogramada' => 'Reprogramada',
        _ => e,
      };

  factory Parada.fromApi(int hojaId, Map<String, dynamic> j) => Parada(
        id: (j['id'] as num).toInt(),
        hojaId: hojaId,
        orden: (j['orden'] as num?)?.toInt() ?? 0,
        estado: (j['estado'] as String?) ?? 'pendiente',
        remitoId: (j['remitoId'] as num?)?.toInt(),
        cliente: (j['cliente'] as String?) ?? '—',
        telefono: j['telefono'] as String?,
        direccion: j['direccion'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        ventanaDesde: DateTime.tryParse(j['ventanaDesde'] as String? ?? ''),
        ventanaHasta: DateTime.tryParse(j['ventanaHasta'] as String? ?? ''),
        instrucciones: j['instrucciones'] as String?,
        renglones: ((j['renglones'] as List<dynamic>?) ?? const [])
            .map((e) => ParadaRenglon.fromApi(e as Map<String, dynamic>))
            .toList(),
      );

  factory Parada.fromRow(Map<String, dynamic> r, List<ParadaRenglon> renglones) => Parada(
        id: r['id'] as int,
        hojaId: r['hoja_id'] as int,
        orden: (r['orden'] as num?)?.toInt() ?? 0,
        estado: (r['estado'] as String?) ?? 'pendiente',
        remitoId: r['remito_id'] as int?,
        cliente: (r['cliente'] as String?) ?? '—',
        telefono: r['telefono'] as String?,
        direccion: r['direccion'] as String?,
        lat: (r['lat'] as num?)?.toDouble(),
        lng: (r['lng'] as num?)?.toDouble(),
        ventanaDesde: DateTime.tryParse(r['ventana_desde'] as String? ?? ''),
        ventanaHasta: DateTime.tryParse(r['ventana_hasta'] as String? ?? ''),
        instrucciones: r['instrucciones'] as String?,
        renglones: renglones,
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'hoja_id': hojaId,
        'orden': orden,
        'estado': estado,
        'remito_id': remitoId,
        'cliente': cliente,
        'telefono': telefono,
        'direccion': direccion,
        'lat': lat,
        'lng': lng,
        'ventana_desde': ventanaDesde?.toIso8601String(),
        'ventana_hasta': ventanaHasta?.toIso8601String(),
        'instrucciones': instrucciones,
      };
}

class HojaRuta {
  final int id;
  final String fecha;
  final String estado;
  final String? deposito;
  final int? distanciaM;
  final int? duracionEstimadaS;
  final String? notas;
  final List<Parada> paradas;

  /// Trazado del recorrido optimizado: lista de puntos [lat, lng] (OSRM).
  final List<List<double>> recorrido;

  HojaRuta({
    required this.id,
    required this.fecha,
    required this.estado,
    this.deposito,
    this.distanciaM,
    this.duracionEstimadaS,
    this.notas,
    this.paradas = const [],
    this.recorrido = const [],
  });

  int get total => paradas.length;
  int get resueltas => paradas.where((p) => p.resuelta).length;
  bool get enCurso => estado == 'en_curso';
  bool get asignada => estado == 'asignada';

  static List<List<double>> _parseRecorrido(dynamic raw) {
    final list = raw is String
        ? (raw.isEmpty ? const [] : jsonDecode(raw) as List<dynamic>)
        : (raw as List<dynamic>? ?? const []);
    return list
        .whereType<List<dynamic>>()
        .where((p) => p.length >= 2)
        .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
        .toList();
  }

  static String estadoLabel(String e) => switch (e) {
        'asignada' => 'Asignada',
        'en_curso' => 'En curso',
        'cerrada' => 'Cerrada',
        'cancelada' => 'Cancelada',
        _ => e,
      };

  factory HojaRuta.fromApi(Map<String, dynamic> j) {
    final id = (j['id'] as num).toInt();
    return HojaRuta(
      id: id,
      fecha: (j['fecha'] as String?) ?? '',
      estado: (j['estado'] as String?) ?? 'asignada',
      deposito: j['deposito'] as String?,
      distanciaM: (j['distanciaM'] as num?)?.toInt(),
      duracionEstimadaS: (j['duracionEstimadaS'] as num?)?.toInt(),
      notas: j['notas'] as String?,
      paradas: ((j['paradas'] as List<dynamic>?) ?? const [])
          .map((e) => Parada.fromApi(id, e as Map<String, dynamic>))
          .toList(),
      recorrido: _parseRecorrido(j['recorrido']),
    );
  }

  factory HojaRuta.fromRow(Map<String, dynamic> r, List<Parada> paradas) => HojaRuta(
        id: r['id'] as int,
        fecha: (r['fecha'] as String?) ?? '',
        estado: (r['estado'] as String?) ?? 'asignada',
        deposito: r['deposito'] as String?,
        distanciaM: r['distancia_m'] as int?,
        duracionEstimadaS: r['duracion_s'] as int?,
        notas: r['notas'] as String?,
        paradas: paradas,
        recorrido: _parseRecorrido(r['recorrido_json']),
      );

  Map<String, dynamic> toRow() => {
        'id': id,
        'fecha': fecha,
        'estado': estado,
        'deposito': deposito,
        'distancia_m': distanciaM,
        'duracion_s': duracionEstimadaS,
        'notas': notas,
        'recorrido_json': recorrido.isEmpty ? null : jsonEncode(recorrido),
        'updated_at': DateTime.now().toIso8601String(),
      };
}
