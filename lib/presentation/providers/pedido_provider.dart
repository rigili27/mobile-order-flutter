import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import '../../data/models/articulo.dart';
import '../../data/models/cliente.dart';
import '../../data/models/pedido_cabecera.dart';
import '../../data/models/pedido_detalle.dart';
import '../../data/repositories/cuenta_corriente_repository.dart';
import '../../data/repositories/parametros_repository.dart';
import '../../data/repositories/pedido_repository.dart';

class ItemPedido {
  final Articulo articulo;
  double cantidad;
  double precio;
  double porDto;
  String comentario;
  int? deposito;

  ItemPedido({
    required this.articulo,
    required this.cantidad,
    required this.precio,
    this.porDto = 0,
    this.comentario = '',
    this.deposito,
  });

  double get importe => PedidoDetalle.calcularImporte(cantidad, precio, porDto);
}

class PedidoProvider extends ChangeNotifier {
  final _repo = PedidoRepository();

  Cliente? _cliente;
  final List<ItemPedido> _items = [];
  List<int>? _firma;
  List<int>? _existingFirma; // firma original al editar
  String _quienRecibio = '';
  String _comentarios = '';
  int? _nroPedido;
  String? _tipoVenta;
  bool _saving = false;
  String? _errorMessage;

  // null = pedido nuevo no guardado
  // non-null = pedido ya en DB (editando o auto-guardado)
  int? _pedidoId;

  Cliente? get cliente => _cliente;
  List<ItemPedido> get items => List.unmodifiable(_items);
  List<int>? get firma => _firma;
  String get quienRecibio => _quienRecibio;
  String get comentarios => _comentarios;
  int? get nroPedido => _nroPedido;
  String? get tipoVenta => _tipoVenta;
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

  void setNroPedido(int? v) {
    _nroPedido = v;
    notifyListeners();
  }

  void setTipoVenta(String? v) {
    _tipoVenta = v;
    notifyListeners();
  }

  /// Carga un pedido existente para edición.
  void loadForEdit(PedidoCabecera cab, Cliente cli, List<ItemPedido> items) {
    _pedidoId = cab.id;
    _cliente = cli;
    _items
      ..clear()
      ..addAll(items);
    _quienRecibio = cab.quienRecibio;
    _comentarios = cab.comentarios;
    _nroPedido = cab.nroPedido;
    _tipoVenta = cab.tipoVenta;
    _existingFirma = cab.firma;
    _firma = null;
    _saving = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Guarda silenciosamente sin firma ni validación de UI.
  /// Crea el pedido si `_pedidoId == null`, lo actualiza si ya existe.
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
      // silent — user not shown error for auto-save
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

    // Si el usuario no firmó pero había firma previa (edición), conservar la original.
    final firmaFinal = _firma ?? _existingFirma;

    try {
      if (_pedidoId != null) {
        // Modo edición / actualización
        final cab = PedidoCabecera(
          id: _pedidoId,
          codCliente: _cliente!.codigo,
          codVendedor: codVendedor,
          fecha: DateFormat('yyyy-MM-dd').format(DateTime.now()),
          comentarios: _comentarios,
          nroPedido: _pedidoId,
          quienRecibio: _quienRecibio,
          firma: firmaFinal,
          tipoVenta: _tipoVenta,
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
        await _syncCuentaCorriente(_pedidoId!);
        _saving = false;
        notifyListeners();
        return _pedidoId;
      } else {
        // Pedido nuevo
        final fecha = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final cabecera = PedidoCabecera(
          codCliente: _cliente!.codigo,
          codVendedor: codVendedor,
          fecha: fecha,
          comentarios: _comentarios,
          nroPedido: _nroPedido,
          quienRecibio: _quienRecibio,
          firma: firmaFinal,
          tipoVenta: _tipoVenta,
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
        await _syncCuentaCorriente(idPedido);

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
    _nroPedido = null;
    _tipoVenta = null;
    _saving = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Si cta_cte está activo, borra y recrea el movimiento de PedMCCte de este pedido.
  Future<void> _syncCuentaCorriente(int idPedido) async {
    if (_cliente == null) return;
    if (!await ParametrosRepository.ctaCteActivo()) return;
    await CuentaCorrienteRepository().syncMovimientoPedido(
      idPedido: idPedido,
      codCliente: _cliente!.codigo,
      tipoVenta: _tipoVenta ?? 'C',
      total: total,
    );
  }

  // ── helpers ───────────────────────────────────────────────────────────────

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
