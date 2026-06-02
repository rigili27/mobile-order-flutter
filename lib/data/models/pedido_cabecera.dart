class PedidoCabecera {
  final int? id;
  final int codCliente;
  final int codVendedor;
  final String fecha;
  final String comentarios;
  final int? nroPedido;
  final String quienRecibio;
  final List<int>? firma;
  double total;

  PedidoCabecera({
    this.id,
    required this.codCliente,
    required this.codVendedor,
    required this.fecha,
    this.comentarios = '',
    this.nroPedido,
    this.quienRecibio = '',
    this.firma,
    this.total = 0,
  });

  factory PedidoCabecera.fromMap(Map<String, dynamic> map) => PedidoCabecera(
        id: map['ID'] as int?,
        codCliente: map['CODCLIENTE'] as int,
        codVendedor: map['CODVENDEDOR'] as int,
        fecha: (map['FECHA'] as String? ?? ''),
        comentarios: (map['COMENTARIOS'] as String? ?? '').trim(),
        nroPedido: map['NROPEDIDO'] as int?,
        quienRecibio: (map['QUIENRECIBIO'] as String? ?? '').trim(),
        firma: map['FIRMA'] != null ? List<int>.from(map['FIRMA'] as List) : null,
        total: (map['total'] as num? ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        if (id != null) 'ID': id,
        'CODCLIENTE': codCliente,
        'CODVENDEDOR': codVendedor,
        'FECHA': fecha,
        'COMENTARIOS': comentarios,
        'NROPEDIDO': nroPedido,
        'QUIENRECIBIO': quienRecibio,
        'FIRMA': firma,
      };

  // COMENTARIOS guarda "TipoServicio||NotasLibres". Ambas partes son opcionales.
  static const _sep = '||';

  static String encodeComentarios(String tipo, String notas) {
    if (tipo.isEmpty && notas.isEmpty) return '';
    if (notas.isEmpty) return tipo;
    if (tipo.isEmpty) return '$_sep$notas';
    return '$tipo$_sep$notas';
  }

  static String decodeTipo(String raw) {
    final idx = raw.indexOf(_sep);
    return idx < 0 ? raw : raw.substring(0, idx);
  }

  static String decodeNotas(String raw) {
    final idx = raw.indexOf(_sep);
    return idx < 0 ? '' : raw.substring(idx + _sep.length);
  }
}
