import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../data/models/articulo.dart';
import '../../data/models/cliente.dart';
import '../../data/models/pedido_cabecera.dart';
import '../../data/models/pedido_detalle.dart';
import '../../data/repositories/orden_preparacion_repository.dart';
import 'pedido_provider.dart';

class OrdenPreparacionProvider extends ChangeNotifier {
  final _repo = OrdenPreparacionRepository();

  Cliente? _cliente;
  final List<ItemPedido> _items = [];
  List<int>? _firma;
  List<int>? _existingFirma;
  String _quienRecibio = '';
  String _comentarios = '';
  bool _saving = false;
  String? _errorMessage;
  int? _pedidoId;

  Cliente? get cliente => _cliente;
  List<ItemPedido> get items => List.unmodifiable(_items);
  List<int>? get firma => _firma;
  String get quienRecibio => _quienRecibio;
  String get comentarios => _comentarios;
  bool get saving => _saving;
  String? get errorMessage => _errorMessage;
  bool get hasItems => _items.isNotEmpty;
  int? get pedidoId => _pedidoId;

  double get total => _items.fold(0, (sum, i) => sum + i.importe);

  void setCliente(Cliente c) {
    _cliente = c;
    notifyListeners();
  }

  void addItem(ItemPedido item) {
    final idx = _items.indexWhere((i) => i.articulo.codigo == item.articulo.codigo);
    if (idx >= 0) {
      _items[idx].cantidad += item.cantidad;
      _items[idx].precio = item.precio;
      _items[idx].porDto = item.porDto;
      _items[idx].deposito = item.deposito;
    } else {
      _items.add(item);
    }
    notifyListeners();
  }

  void removeItem(int index) {
    _items.removeAt(index);
    notifyListeners();
  }

  void updateItem(int index, ItemPedido updated) {
    _items[index] = updated;
    notifyListeners();
  }

  void setFirma(List<int> bytes) {
    _firma = bytes;
    notifyListeners();
  }

  void setQuienRecibio(String v) {
    _quienRecibio = v;
    notifyListeners();
  }

  void setComentarios(String v) {
    _comentarios = v;
    notifyListeners();
  }

  void loadForEdit(PedidoCabecera cab, Cliente cli, List<ItemPedido> items) {
    _pedidoId = cab.id;
    _cliente = cli;
    _items
      ..clear()
      ..addAll(items);
    _quienRecibio = cab.quienRecibio;
    _comentarios = cab.comentarios;
    _existingFirma = cab.firma;
    _firma = null;
    _saving = false;
    _errorMessage = null;
    notifyListeners();
  }

  Future<void> autoGuardar(int codVendedor) async {
    if (_cliente == null || _items.isEmpty) return;
    if (_saving) return;
    try {
      final cab = _buildCabecera(codVendedor);
      final detalles = _buildDetalles(_pedidoId ?? 0);
      if (_pedidoId == null) {
        final id = await _repo.insertCabecera(cab);
        await _repo.insertDetalles(
            detalles.map((d) => PedidoDetalle(
                  idPedido: id,
                  codArticulo: d.codArticulo,
                  cantidad: d.cantidad,
                  precio: d.precio,
                  importe: d.importe,
                  unidad: d.unidad,
                  porDto: d.porDto,
                  comentario: d.comentario,
                  deposito: d.deposito,
                )).toList());
        _pedidoId = id;
        notifyListeners();
      } else {
        final cabConId = PedidoCabecera(
          id: _pedidoId,
          codCliente: cab.codCliente,
          codVendedor: cab.codVendedor,
          fecha: cab.fecha,
          comentarios: cab.comentarios,
          nroPedido: _pedidoId,
          quienRecibio: cab.quienRecibio,
          firma: _existingFirma,
        );
        await _repo.updatePedido(
          _pedidoId!,
          cabConId,
          detalles.map((d) => PedidoDetalle(
                idPedido: _pedidoId!,
                codArticulo: d.codArticulo,
                cantidad: d.cantidad,
                precio: d.precio,
                importe: d.importe,
                unidad: d.unidad,
                porDto: d.porDto,
                comentario: d.comentario,
                deposito: d.deposito,
              )).toList(),
        );
      }
    } catch (_) {
      // silent
    }
  }

  Future<int?> guardar(int codVendedor) async {
    if (_cliente == null || _items.isEmpty) {
      _errorMessage = 'Seleccioná un cliente y al menos un producto.';
      notifyListeners();
      return null;
    }

    _saving = true;
    _errorMessage = null;
    notifyListeners();

    final firmaFinal = _firma ?? _existingFirma;

    try {
      if (_pedidoId != null) {
        final cab = PedidoCabecera(
          id: _pedidoId,
          codCliente: _cliente!.codigo,
          codVendedor: codVendedor,
          fecha: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          comentarios: _comentarios,
          nroPedido: _pedidoId,
          quienRecibio: _quienRecibio,
          firma: firmaFinal,
        );
        final detalles = _items
            .map((i) => PedidoDetalle(
                  idPedido: _pedidoId!,
                  codArticulo: i.articulo.codigo,
                  cantidad: i.cantidad,
                  precio: i.precio,
                  importe: i.importe,
                  unidad: i.articulo.unidad,
                  porDto: i.porDto,
                  comentario: i.comentario,
                  deposito: i.deposito,
                ))
            .toList();
        await _repo.updatePedido(_pedidoId!, cab, detalles);
        _saving = false;
        notifyListeners();
        return _pedidoId;
      } else {
        final fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final cabecera = PedidoCabecera(
          codCliente: _cliente!.codigo,
          codVendedor: codVendedor,
          fecha: fecha,
          comentarios: _comentarios,
          quienRecibio: _quienRecibio,
          firma: firmaFinal,
        );

        final idPedido = await _repo.insertCabecera(cabecera);
        final detalles = _items
            .map((i) => PedidoDetalle(
                  idPedido: idPedido,
                  codArticulo: i.articulo.codigo,
                  cantidad: i.cantidad,
                  precio: i.precio,
                  importe: i.importe,
                  unidad: i.articulo.unidad,
                  porDto: i.porDto,
                  comentario: i.comentario,
                  deposito: i.deposito,
                ))
            .toList();
        await _repo.insertDetalles(detalles);

        if (firmaFinal != null) {
          await _repo.updateFirma(idPedido, firmaFinal);
        }

        _saving = false;
        notifyListeners();
        return idPedido;
      }
    } catch (e) {
      _saving = false;
      _errorMessage = 'Error al guardar: $e';
      notifyListeners();
      return null;
    }
  }

  void reset() {
    _cliente = null;
    _items.clear();
    _firma = null;
    _existingFirma = null;
    _pedidoId = null;
    _quienRecibio = '';
    _comentarios = '';
    _saving = false;
    _errorMessage = null;
    notifyListeners();
  }

  PedidoCabecera _buildCabecera(int codVendedor) => PedidoCabecera(
        codCliente: _cliente!.codigo,
        codVendedor: codVendedor,
        fecha: DateFormat('yyyy-MM-dd').format(DateTime.now()),
        comentarios: _comentarios,
        quienRecibio: _quienRecibio,
      );

  List<PedidoDetalle> _buildDetalles(int idPedido) => _items
      .map((i) => PedidoDetalle(
            idPedido: idPedido,
            codArticulo: i.articulo.codigo,
            cantidad: i.cantidad,
            precio: i.precio,
            importe: i.importe,
            unidad: i.articulo.unidad,
            porDto: i.porDto,
            comentario: i.comentario,
            deposito: i.deposito,
          ))
      .toList();
}
