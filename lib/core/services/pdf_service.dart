import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../../data/models/cliente.dart';
import '../../data/models/parametros.dart';
import '../../data/models/pedido_cabecera.dart';
import '../../data/models/pedido_detalle.dart';

class PdfService {
  PdfService._();
  static final PdfService instance = PdfService._();

  final _currencyFmt = NumberFormat('#,##0.00', 'es_AR');

  Future<Uint8List> generarRemito({
    required PedidoCabecera cabecera,
    required List<PedidoDetalle> detalles,
    required Cliente cliente,
    required Parametros parametros,
    String vendedorNombre = '',
  }) async {
    final doc = pw.Document();

    pw.MemoryImage? firmaImage;
    if (cabecera.firma != null && cabecera.firma!.isNotEmpty) {
      firmaImage = pw.MemoryImage(Uint8List.fromList(cabecera.firma!));
    }

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) => [
          _buildHeader(parametros, cabecera, vendedorNombre),
          pw.SizedBox(height: 12),
          _buildClienteInfo(cliente),
          pw.SizedBox(height: 12),
          _buildItemsTable(detalles, enDolares: parametros.monedaDolar),
          pw.SizedBox(height: 8),
          _buildTotal(detalles, enDolares: parametros.monedaDolar),
          if (parametros.pdfLeyendaPrecioSinIva) ...[
            pw.SizedBox(height: 4),
            pw.Text('* Precios sin IVA',
                style: pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                    fontStyle: pw.FontStyle.italic)),
          ],
          if (PedidoCabecera.decodeTipo(cabecera.comentarios).isNotEmpty) ...[
            pw.SizedBox(height: 14),
            _buildServicioBadge(PedidoCabecera.decodeTipo(cabecera.comentarios)),
          ],
          if (PedidoCabecera.decodeNotas(cabecera.comentarios).isNotEmpty) ...[
            pw.SizedBox(height: 8),
            _buildNotasBox(PedidoCabecera.decodeNotas(cabecera.comentarios)),
          ],
          if (cabecera.quienRecibio.isNotEmpty) ...[
            pw.SizedBox(height: 8),
            pw.Text('Recibido por: ${cabecera.quienRecibio}',
                style: const pw.TextStyle(fontSize: 10)),
          ],
          if (firmaImage != null) ...[
            pw.SizedBox(height: 16),
            _buildFirma(firmaImage),
          ],
        ],
      ),
    );

    return doc.save();
  }

  pw.Widget _buildHeader(Parametros p, PedidoCabecera c, String vendedorNombre) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text(p.razonSocial,
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Text(p.domicilio, style: const pw.TextStyle(fontSize: 10)),
          pw.Text('CUIT: ${p.nroCuit}', style: const pw.TextStyle(fontSize: 10)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('PEDIDO N° ${c.nroPedido ?? c.id ?? ''}',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Fecha: ${c.fecha}', style: const pw.TextStyle(fontSize: 10)),
          if (vendedorNombre.isNotEmpty)
            pw.Text('Vendedor: $vendedorNombre',
                style: const pw.TextStyle(fontSize: 10)),
        ]),
      ],
    );
  }

  pw.Widget _buildClienteInfo(Cliente cli) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(border: pw.Border.all()),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('CLIENTE', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11)),
        pw.Text('${cli.codigo} - ${cli.nombre}', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('${cli.domicilio} - ${cli.localidad}', style: const pw.TextStyle(fontSize: 10)),
        if (cli.telefono.isNotEmpty)
          pw.Text('Tel: ${cli.telefono}', style: const pw.TextStyle(fontSize: 10)),
        pw.Text('CUIT: ${cli.nroCuit}', style: const pw.TextStyle(fontSize: 10)),
      ]),
    );
  }

  pw.Widget _buildItemsTable(List<PedidoDetalle> detalles, {bool enDolares = false}) {
    final headers = ['Código', 'Descripción', 'Cant.', 'Precio', 'Dto%', 'Importe'];
    return pw.Table(
      border: pw.TableBorder.all(width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(48),
        1: const pw.FlexColumnWidth(),
        2: const pw.FixedColumnWidth(36),
        3: const pw.FixedColumnWidth(60),
        4: const pw.FixedColumnWidth(36),
        5: const pw.FixedColumnWidth(64),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: headers
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.all(4),
                    child: pw.Text(h,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 9)),
                  ))
              .toList(),
        ),
        ...detalles.map((d) => pw.TableRow(children: [
              _cell(d.codArticulo.toString()),
              _descCell(d.descripcionArticulo ?? '', d.sku),
              _cell(d.cantidad.toStringAsFixed(2)),
              _cell(_currencyFmt.format(d.precio)),
              _cell(d.porDto > 0 ? '${d.porDto.toStringAsFixed(1)}%' : ''),
              _cell(_currencyFmt.format(d.importe), align: pw.TextAlign.right),
            ])),
      ],
    );
  }

  pw.Widget _cell(String text, {pw.TextAlign? align}) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(text,
            style: const pw.TextStyle(fontSize: 9),
            textAlign: align ?? pw.TextAlign.left),
      );

  pw.Widget _descCell(String descripcion, String sku) => pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(descripcion, style: const pw.TextStyle(fontSize: 9)),
            if (sku.isNotEmpty)
              pw.Text('SKU: $sku',
                  style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700)),
          ],
        ),
      );

  pw.Widget _buildTotal(List<PedidoDetalle> detalles, {bool enDolares = false}) {
    final total = detalles.fold<double>(0, (s, d) => s + d.importe);
    final simbolo = enDolares ? 'U\$S ' : '\$';
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        'TOTAL: $simbolo${_currencyFmt.format(total)}',
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  Future<Uint8List> generarTodosPedidos({
    required List<PedidoCabecera> pedidos,
    required Map<int, Cliente> clientes,
    required Map<int, List<PedidoDetalle>> detallesPorPedido,
    required Parametros parametros,
    Map<int, String>? vendedores,
  }) async {
    final doc = pw.Document();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (context) {
          final widgets = <pw.Widget>[];
          for (int i = 0; i < pedidos.length; i++) {
            if (i > 0) widgets.add(pw.NewPage());
            final p = pedidos[i];
            final cli = clientes[p.codCliente];
            final detalles = detallesPorPedido[p.id] ?? [];

            pw.MemoryImage? firmaImage;
            if (p.firma != null && p.firma!.isNotEmpty) {
              firmaImage = pw.MemoryImage(Uint8List.fromList(p.firma!));
            }

            final vendedorNombre = vendedores?[p.codVendedor] ?? '';
            widgets.addAll([
              _buildHeader(parametros, p, vendedorNombre),
              pw.SizedBox(height: 12),
              if (cli != null) _buildClienteInfo(cli),
              pw.SizedBox(height: 12),
              _buildItemsTable(detalles, enDolares: parametros.monedaDolar),
              pw.SizedBox(height: 8),
              _buildTotal(detalles, enDolares: parametros.monedaDolar),
              if (parametros.pdfLeyendaPrecioSinIva) ...[
                pw.SizedBox(height: 4),
                pw.Text('* Precios sin IVA',
                    style: pw.TextStyle(
                        fontSize: 8,
                        color: PdfColors.grey700,
                        fontStyle: pw.FontStyle.italic)),
              ],
              if (PedidoCabecera.decodeTipo(p.comentarios).isNotEmpty) ...[
                pw.SizedBox(height: 14),
                _buildServicioBadge(PedidoCabecera.decodeTipo(p.comentarios)),
              ],
              if (PedidoCabecera.decodeNotas(p.comentarios).isNotEmpty) ...[
                pw.SizedBox(height: 8),
                _buildNotasBox(PedidoCabecera.decodeNotas(p.comentarios)),
              ],
              if (p.quienRecibio.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text('Recibido por: ${p.quienRecibio}',
                    style: const pw.TextStyle(fontSize: 10)),
              ],
              if (firmaImage != null) ...[
                pw.SizedBox(height: 16),
                _buildFirma(firmaImage),
              ],
            ]);
          }
          return widgets;
        },
      ),
    );

    return doc.save();
  }

  pw.Widget _buildServicioBadge(String servicio) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 1.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Center(
        child: pw.Text(
          servicio,
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
      ),
    );
  }

  pw.Widget _buildNotasBox(String notas) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.5, color: PdfColors.grey600),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.Text('Comentarios:',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold,
                color: PdfColors.grey700)),
        pw.SizedBox(height: 3),
        pw.Text(notas, style: const pw.TextStyle(fontSize: 10)),
      ]),
    );
  }

  pw.Widget _buildFirma(pw.MemoryImage img) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('Firma:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      pw.SizedBox(height: 4),
      pw.Image(img, width: 160, height: 80, fit: pw.BoxFit.contain),
    ]);
  }
}
