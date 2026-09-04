import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/api/api_config.dart';
import '../../core/api/preventa_api.dart';
import '../../core/api/catalog_importer.dart';
import '../../core/database/sync_state_database_helper.dart';
import '../../data/models/articulo.dart';
import '../../data/models/cliente.dart';
import '../../data/models/pedido_cabecera.dart';
import '../../data/repositories/articulo_repository.dart';
import '../../data/repositories/cliente_repository.dart';
import '../../data/repositories/cobranza_repository.dart';
import '../../data/repositories/parametros_repository.dart';
import '../../data/repositories/pedido_repository.dart';

enum ApiSyncStatus { idle, syncing, pushing, error }

class ApiSyncProvider extends ChangeNotifier {
  ApiSyncProvider({PreventaApi? api, CatalogImporter? importer})
      : _api = api ?? PreventaApi(),
        _importer = importer ?? CatalogImporter();

  final PreventaApi _api;
  final CatalogImporter _importer;
  final _pedidoRepo = PedidoRepository();
  final _cobranzaRepo = CobranzaRepository();
  final _clienteRepo = ClienteRepository();
  final _articuloRepo = ArticuloRepository();
  final _outbox = SyncStateDatabaseHelper.instance;

  ApiSyncStatus _status = ApiSyncStatus.idle;
  String? _errorMessage;
  DateTime? _lastSync;
  int _pendientes = 0;
  int _cobranzasPendientes = 0;
  List<String> _advertencias = const [];

  ApiSyncStatus get status => _status;
  String? get errorMessage => _errorMessage;
  DateTime? get lastSync => _lastSync;
  int get pendientes => _pendientes;
  int get cobranzasPendientes => _cobranzasPendientes;

  /// Avisos de la última sincronización (p. ej. clientes con listas de precio
  /// que no entran en los 3 slots de la app).
  List<String> get advertencias => _advertencias;
  bool get busy => _status == ApiSyncStatus.syncing || _status == ApiSyncStatus.pushing;

  /// Cada cuánto revalida el catálogo automáticamente (ver [autoSync]).
  static const autoSyncInterval = Duration(minutes: 15);

  Future<void> refreshState() async {
    _lastSync = await ApiConfig.lastSync();
    _pendientes = await _outbox.countPendientes();
    _cobranzasPendientes = await _outbox.countCobranzasPendientes();
    notifyListeners();
  }

  /// Sincroniza el catálogo si hay sesión API y la última sync quedó vieja
  /// (o nunca se hizo). Best-effort y silencioso: no muestra errores ni
  /// bloquea. Se llama al abrir el Home y al volver la app a primer plano.
  Future<bool> autoSync({bool force = false}) async {
    if (busy) return false;
    if (!await ApiConfig.hasSession()) return false;

    if (!force) {
      final last = await ApiConfig.lastSync();
      if (last != null &&
          DateTime.now().difference(last) < autoSyncInterval) {
        return false;
      }
    }

    return sincronizarCatalogo();
  }

  /// Descarga el catálogo y lo vuelca en la base local.
  Future<bool> sincronizarCatalogo() async {
    if (busy) return false;
    _status = ApiSyncStatus.syncing;
    _errorMessage = null;
    notifyListeners();
    try {
      final catalogo = await _api.fetchCatalogo();
      await _importer.import(catalogo);
      await ApiConfig.markSynced();
      ParametrosRepository.invalidateCache();
      _advertencias = (catalogo['advertencias'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [];
      _status = ApiSyncStatus.idle;
      await refreshState();
      return true;
    } on ApiException catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      _fail('Error al sincronizar: $e');
      return false;
    }
  }

  /// Sube un pedido local recién guardado (o lo reintenta).
  Future<bool> subirPedido(int idPedidoLocal) async {
    if (!await ApiConfig.hasSession()) return false;
    _status = ApiSyncStatus.pushing;
    _errorMessage = null;
    notifyListeners();

    try {
      final uuid = await _outbox.enqueue(idPedidoLocal, _uuidV4);
      final payload = await _buildPayload(idPedidoLocal, uuid);
      if (payload == null) {
        await _outbox.markError(idPedidoLocal, 'No se encontró el pedido local.');
        _fail('No se encontró el pedido local.');
        return false;
      }
      final salesDocumentId = await _api.pushPedido(payload);
      await _outbox.markSincronizado(idPedidoLocal, salesDocumentId);
      _status = ApiSyncStatus.idle;
      await refreshState();
      return true;
    } on ApiException catch (e) {
      await _outbox.markError(idPedidoLocal, e.message);
      _fail(e.message);
      return false;
    } catch (e) {
      await _outbox.markError(idPedidoLocal, e.toString());
      _fail('Error al subir el pedido: $e');
      return false;
    }
  }

  /// Reintenta todos los pedidos pendientes / con error.
  Future<void> reintentarPendientes() async {
    final pendientes = await _outbox.pendientes();
    for (final entry in pendientes) {
      await subirPedido(entry.idPedidoLocal);
    }
  }

  Future<OutboxEntry?> estadoDe(int idPedidoLocal) => _outbox.find(idPedidoLocal);

  // ── cobranzas ──────────────────────────────────────────────────────────────

  /// Sube una cobranza local recién guardada (o la reintenta). Best-effort: si
  /// falla queda "pendiente" en el outbox.
  Future<bool> subirCobranza(int idCobranzaLocal) async {
    if (!await ApiConfig.hasSession()) return false;
    _status = ApiSyncStatus.pushing;
    _errorMessage = null;
    notifyListeners();

    try {
      final uuid = await _outbox.enqueueCobranza(idCobranzaLocal, _uuidV4);
      final cobranza = await _cobranzaRepo.getById(idCobranzaLocal);
      if (cobranza == null) {
        await _outbox.markCobranzaError(
            idCobranzaLocal, 'No se encontró la cobranza local.');
        _fail('No se encontró la cobranza local.');
        return false;
      }
      final receiptId = await _api.pushCobranza(cobranza.toApiPayload(uuid));
      await _outbox.markCobranzaSincronizada(idCobranzaLocal, receiptId);
      _status = ApiSyncStatus.idle;
      await refreshState();
      return true;
    } on ApiException catch (e) {
      await _outbox.markCobranzaError(idCobranzaLocal, e.message);
      _fail(e.message);
      return false;
    } catch (e) {
      await _outbox.markCobranzaError(idCobranzaLocal, e.toString());
      _fail('Error al subir la cobranza: $e');
      return false;
    }
  }

  Future<void> reintentarCobranzasPendientes() async {
    final pendientes = await _outbox.cobranzasPendientes();
    for (final entry in pendientes) {
      await subirCobranza(entry.idCobranzaLocal);
    }
  }

  Future<CobranzaOutboxEntry?> estadoDeCobranza(int idCobranzaLocal) =>
      _outbox.findCobranza(idCobranzaLocal);

  // ── altas de cliente / artículo (online) ───────────────────────────────────

  /// Crea un cliente en el ERP (queda pendiente de revisión) y lo inserta en
  /// la base local con el código real. Requiere conexión. Devuelve el
  /// `Cliente` local o null si falló (`errorMessage` tiene el detalle).
  Future<Cliente?> crearCliente({
    required String nombre,
    String? cuit,
    int? condicionIva,
    String? condicionVenta,
    String? telefono,
    String? email,
    String? domicilio,
    String? localidad,
  }) async {
    if (!await ApiConfig.hasSession()) {
      _fail('Necesitás conexión con el servidor para crear un cliente.');
      return null;
    }
    _status = ApiSyncStatus.pushing;
    _errorMessage = null;
    notifyListeners();

    final uuid = _uuidV4();
    try {
      final id = await _api.pushCliente({
        'uuid': uuid,
        'nombre': nombre,
        'cuit': cuit,
        'condicionIva': condicionIva,
        'condicionVenta': condicionVenta,
        'telefono': telefono,
        'email': email,
        'domicilio': domicilio,
        'localidad': localidad,
      });
      if (id == null) {
        _fail('El servidor no devolvió el id del cliente.');
        return null;
      }
      final cliente = Cliente(
        codigo: id,
        nombre: nombre,
        domicilio: domicilio ?? '',
        localidad: localidad ?? '',
        telefono: telefono ?? '',
        nroCuit: cuit ?? '',
        codCatIva: condicionIva,
        nrolPrecios: 1,
        saldo: 0,
      );
      await _clienteRepo.insertLocal(cliente);
      await _outbox.registrarClienteCreado(
          uuid: uuid, customerId: id, nombre: nombre);
      _status = ApiSyncStatus.idle;
      notifyListeners();
      return cliente;
    } on ApiException catch (e) {
      _fail(e.message);
      return null;
    } catch (e) {
      _fail('No se pudo crear el cliente: $e');
      return null;
    }
  }

  /// Crea un artículo provisorio en el ERP y lo inserta en la base local con
  /// el código real (queda con `pendiente = true`). Requiere conexión.
  Future<Articulo?> crearArticulo({
    required String descripcion,
    String? codigoBarra,
    double? precio,
    double? costo,
  }) async {
    if (!await ApiConfig.hasSession()) {
      _fail('Necesitás conexión con el servidor para crear un artículo.');
      return null;
    }
    _status = ApiSyncStatus.pushing;
    _errorMessage = null;
    notifyListeners();

    final uuid = _uuidV4();
    try {
      final id = await _api.pushArticulo({
        'uuid': uuid,
        'descripcion': descripcion,
        'codigoBarra': codigoBarra,
        'precio': precio,
        'costo': costo,
      });
      if (id == null) {
        _fail('El servidor no devolvió el id del artículo.');
        return null;
      }
      final articulo = Articulo(
        codigo: id,
        descripcion: descripcion,
        stockActual: 0,
        prevtaPub1: precio ?? 0,
        prevtaPub2: precio ?? 0,
        prevtaPub3: precio ?? 0,
        alicuota: 21,
        codigoBarra: codigoBarra ?? '',
        sku: '',
        pendiente: true,
      );
      await _articuloRepo.insertLocal(articulo);
      await _outbox.registrarArticuloCreado(
          uuid: uuid, productId: id, descripcion: descripcion);
      _status = ApiSyncStatus.idle;
      notifyListeners();
      return articulo;
    } on ApiException catch (e) {
      _fail(e.message);
      return null;
    } catch (e) {
      _fail('No se pudo crear el artículo: $e');
      return null;
    }
  }

  // ── stock y compras (online) ────────────────────────────────────────────────

  /// Propone un ajuste de stock (conteo). Requiere conexión. Devuelve la
  /// diferencia sugerida (contado - sistema) o null si falló.
  Future<double?> crearAjusteStock({
    required int codArticulo,
    required String descArticulo,
    required int codDeposito,
    required String descDeposito,
    required double cantidadContada,
    String? observaciones,
  }) async {
    if (!await ApiConfig.hasSession()) {
      _fail('Necesitás conexión con el servidor para controlar stock.');
      return null;
    }
    _status = ApiSyncStatus.pushing;
    _errorMessage = null;
    notifyListeners();

    final uuid = _uuidV4();
    try {
      final res = await _api.pushAjusteStock({
        'uuid': uuid,
        'codArticulo': codArticulo,
        'codDeposito': codDeposito,
        'cantidadContada': cantidadContada,
        'observaciones': observaciones,
      });
      final id = res['id'] as int?;
      final diferencia = (res['diferenciaSugerida'] as num?)?.toDouble() ?? 0;

      final idLocal = await _outbox.insertAjusteStock({
        'cod_articulo': codArticulo,
        'descripcion_articulo': descArticulo,
        'cod_deposito': codDeposito,
        'descripcion_deposito': descDeposito,
        'cantidad_contada': cantidadContada,
        'cantidad_sistema': cantidadContada - diferencia,
        'observaciones': observaciones,
      });
      await _outbox.enqueueAjusteStock(idLocal, () => uuid);
      await _outbox.markAjusteStockSincronizado(idLocal, id, diferencia);

      _status = ApiSyncStatus.idle;
      notifyListeners();
      return diferencia;
    } on ApiException catch (e) {
      _fail(e.message);
      return null;
    } catch (e) {
      _fail('No se pudo enviar el ajuste de stock: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> ajustesStockLocales() =>
      _outbox.ajustesStockLocales();

  /// Propone una orden de compra. Requiere conexión.
  Future<bool> crearOrdenCompra({
    int? proveedorId,
    String? proveedorNombre,
    String? observaciones,
    required List<Map<String, dynamic>> items,
  }) async {
    if (!await ApiConfig.hasSession()) {
      _fail('Necesitás conexión con el servidor para generar una orden de compra.');
      return false;
    }
    _status = ApiSyncStatus.pushing;
    _errorMessage = null;
    notifyListeners();

    final uuid = _uuidV4();
    try {
      final id = await _api.pushOrdenCompra({
        'uuid': uuid,
        'proveedorId': proveedorId,
        'proveedorSugerido': proveedorNombre,
        'observaciones': observaciones,
        'items': [
          for (final item in items)
            {
              'codArticulo': item['codArticulo'],
              'cantidad': item['cantidad'],
              'costoEstimado': item['costoEstimado'],
            },
        ],
      });

      final idLocal = await _outbox.insertOrdenCompra({
        'proveedor_id': proveedorId,
        'proveedor_nombre': proveedorNombre,
        'observaciones': observaciones,
        'items_json': jsonEncode(items),
      });
      await _outbox.enqueueOrdenCompra(idLocal, () => uuid);
      await _outbox.markOrdenCompraSincronizada(idLocal, id);

      _status = ApiSyncStatus.idle;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      _fail(e.message);
      return false;
    } catch (e) {
      _fail('No se pudo enviar la orden de compra: $e');
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> ordenesCompraLocales() =>
      _outbox.ordenesCompraLocales();

  Future<Map<String, dynamic>?> _buildPayload(int idPedidoLocal, String uuid) async {
    final cab = await _pedidoRepo.getById(idPedidoLocal);
    if (cab == null) return null;
    final detalles = await _pedidoRepo.getDetalles(idPedidoLocal);

    return {
      'uuid': uuid,
      'codCliente': cab.codCliente,
      'fecha': cab.fecha,
      'tipoServicio': PedidoCabecera.decodeTipo(cab.comentarios),
      'notas': PedidoCabecera.decodeNotas(cab.comentarios),
      'quienRecibio': cab.quienRecibio,
      'tipoVenta': cab.tipoVenta,
      'firmaBase64': cab.firma != null && cab.firma!.isNotEmpty
          ? base64Encode(cab.firma!)
          : null,
      'items': [
        for (final d in detalles)
          {
            'codArticulo': d.codArticulo,
            'cantidad': d.cantidad,
            'precio': d.precio,
            'porDto': d.porDto,
            'comentario': d.comentario.isEmpty ? null : d.comentario,
            'deposito': d.deposito,
          },
      ],
    };
  }

  void _fail(String message) {
    _status = ApiSyncStatus.error;
    _errorMessage = message;
    notifyListeners();
  }

  static String _uuidV4() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int start, int end) => [
          for (var i = start; i < end; i++)
            bytes[i].toRadixString(16).padLeft(2, '0')
        ].join();
    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
