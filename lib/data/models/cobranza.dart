import 'dart:convert';
import 'dart:typed_data';

/// Forma de pago de una cobranza registrada en la calle.
enum CobranzaFormaPago { efectivo, cheque, transferencia }

/// Una pre-cobranza que el vendedor registra desde la app. En modo API se
/// materializa como un `Receipt` en Borrador en el ERP (administración lo
/// confirma). El detalle de cheque / transferencia viaja serializado en
/// `detalleJson`.
class Cobranza {
  final int? id;
  final int codCliente;
  final String fecha; // yyyy-MM-dd
  final double importe;
  final CobranzaFormaPago formaPago;
  final Map<String, dynamic> detalle;
  final String? referencia;
  final String? notas;
  final Uint8List? firma;

  const Cobranza({
    this.id,
    required this.codCliente,
    required this.fecha,
    required this.importe,
    required this.formaPago,
    this.detalle = const {},
    this.referencia,
    this.notas,
    this.firma,
  });

  factory Cobranza.fromMap(Map<String, dynamic> m) => Cobranza(
        id: m['id'] as int?,
        codCliente: m['cod_cliente'] as int,
        fecha: m['fecha'] as String,
        importe: (m['importe'] as num).toDouble(),
        formaPago: CobranzaFormaPago.values.byName(m['forma_pago'] as String),
        detalle: m['detalle_json'] == null || (m['detalle_json'] as String).isEmpty
            ? const {}
            : (jsonDecode(m['detalle_json'] as String) as Map<String, dynamic>),
        referencia: m['referencia'] as String?,
        notas: m['notas'] as String?,
        firma: m['firma'] as Uint8List?,
      );

  Map<String, dynamic> toDbMap() => {
        if (id != null) 'id': id,
        'cod_cliente': codCliente,
        'fecha': fecha,
        'importe': importe,
        'forma_pago': formaPago.name,
        'detalle_json': detalle.isEmpty ? null : jsonEncode(detalle),
        'referencia': referencia,
        'notas': notas,
        'firma': firma,
      };

  /// Payload para `POST /api/{tenant}/cobranzas`. Los campos de cheque /
  /// transferencia salen planos del mapa `detalle` (mismas keys que el DTO
  /// `CrearCobranzaMovilData` del backend).
  Map<String, dynamic> toApiPayload(String uuid) => {
        'uuid': uuid,
        'codCliente': codCliente,
        'fecha': fecha,
        'importe': importe,
        'formaPago': formaPago.name,
        'referencia': referencia,
        'notas': notas,
        'firmaBase64':
            firma != null && firma!.isNotEmpty ? base64Encode(firma!) : null,
        ...detalle,
      };
}
