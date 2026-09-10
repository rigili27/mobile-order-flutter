import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/api/preventa_api.dart' show ApiException;
import '../../core/api/reparto_api.dart';
import '../../core/database/reparto_database_helper.dart';
import '../../data/models/reparto_models.dart';
import '../../data/repositories/reparto_repository.dart';

enum RepartoSync { idle, syncing, error }

/// Orquesta el modo repartidor: baja las hojas de ruta asignadas, marca
/// paradas en camino, confirma entregas (con cola offline idempotente) y
/// reprograma. Espeja `ApiSyncProvider` pero mucho más chico.
class RepartoProvider extends ChangeNotifier {
  final _api = RepartoApi();
  final _repo = RepartoRepository();

  RepartoSync _status = RepartoSync.idle;
  String? _error;
  List<HojaRuta> _hojas = [];
  int _pendientes = 0;

  RepartoSync get status => _status;
  bool get syncing => _status == RepartoSync.syncing;
  String? get error => _error;
  List<HojaRuta> get hojas => _hojas;
  int get pendientes => _pendientes;

  Future<void> cargarLocal() async {
    _hojas = await _repo.getHojas();
    _pendientes = await _repo.outboxPendienteCount();
    notifyListeners();
  }

  /// Baja las hojas del ERP + reintenta la cola de confirmaciones.
  Future<bool> sincronizar() async {
    _status = RepartoSync.syncing;
    _error = null;
    notifyListeners();
    try {
      final data = await _api.fetchHojas();
      final hojas = data
          .map((e) => HojaRuta.fromApi(e as Map<String, dynamic>))
          .toList();
      await _repo.replaceHojas(hojas);
      await _flushOutbox();
      await cargarLocal();
      _status = RepartoSync.idle;
      notifyListeners();
      return true;
    } on ApiException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail('No se pudo sincronizar: $e');
    }
  }

  Future<bool> iniciarHoja(int hojaId) async {
    try {
      await _api.iniciarHoja(hojaId);
      await _repo.setEstadoHoja(hojaId, 'en_curso');
      await cargarLocal();
      return true;
    } on ApiException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail('$e');
    }
  }

  Future<bool> marcarEnCamino(int paradaId) async {
    try {
      final res = await _api.paradaEnCamino(paradaId);
      await _repo.setEstadoParada(paradaId, (res['estado'] as String?) ?? 'en_camino');
      await cargarLocal();
      return true;
    } on ApiException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail('$e');
    }
  }

  Future<bool> reprogramar(int paradaId, String? motivo) async {
    try {
      await _api.reprogramar(paradaId, motivo);
      await _repo.setEstadoParada(paradaId, 'reprogramada');
      await cargarLocal();
      return true;
    } on ApiException catch (e) {
      return _fail(e.message);
    } catch (e) {
      return _fail('$e');
    }
  }

  /// Encola la confirmación (idempotente por uuid) y trata de subirla ya.
  /// Devuelve true si quedó registrada localmente (aunque el POST falle, la
  /// cola reintenta en la próxima sync).
  Future<bool> confirmarEntrega({
    required Parada parada,
    required String outcome, // entregada | parcial | rechazada
    String? recibidoPor,
    String? dni,
    String? firmaBase64,
    bool dejadoSinFirma = false,
    List<String> fotosBase64 = const [],
    double? lat,
    double? lng,
    String? notas,
    List<Map<String, dynamic>> renglones = const [],
  }) async {
    final payload = <String, dynamic>{
      'uuid': RepartoDatabaseHelper.uuidV4(),
      'outcome': outcome,
      'recibidoPor': recibidoPor,
      'dni': dni,
      'firmaBase64': firmaBase64,
      'dejadoSinFirma': dejadoSinFirma,
      'fotos': fotosBase64,
      'lat': lat,
      'lng': lng,
      'confirmadoEn': DateTime.now().toUtc().toIso8601String(),
      'notas': notas,
      'renglones': renglones,
    };

    await _repo.enqueueEntrega(parada.id, payload);
    // Estado local optimista.
    await _repo.setEstadoParada(parada.id, switch (outcome) {
      'parcial' => 'parcial',
      'rechazada' => 'no_entregada',
      _ => 'entregada',
    });

    try {
      final res = await _api.confirmarEntrega(parada.id, payload);
      await _repo.marcarOutbox(payload['uuid'] as String,
          estado: 'sincronizado', pruebaId: (res['pruebaId'] as num?)?.toInt());
      _error = null;
    } on ApiException catch (e) {
      await _repo.marcarOutbox(payload['uuid'] as String, estado: 'error', error: e.message);
      _error = 'La entrega quedó guardada; se reintentará: ${e.message}';
    } catch (e) {
      await _repo.marcarOutbox(payload['uuid'] as String, estado: 'error', error: '$e');
      _error = 'La entrega quedó guardada; se reintentará.';
    }

    await cargarLocal();
    return true;
  }

  Future<void> _flushOutbox() async {
    for (final row in await _repo.outboxPendiente()) {
      final uuid = row['uuid'] as String;
      final paradaId = row['parada_id'] as int;
      final payload = jsonDecode(row['payload_json'] as String) as Map<String, dynamic>;
      try {
        final res = await _api.confirmarEntrega(paradaId, payload);
        await _repo.marcarOutbox(uuid,
            estado: 'sincronizado', pruebaId: (res['pruebaId'] as num?)?.toInt());
      } catch (_) {
        // se reintenta en la próxima sync
      }
    }
  }

  Future<void> reintentarPendientes() async {
    _status = RepartoSync.syncing;
    notifyListeners();
    await _flushOutbox();
    await cargarLocal();
    _status = RepartoSync.idle;
    notifyListeners();
  }

  bool _fail(String message) {
    _status = RepartoSync.error;
    _error = message;
    notifyListeners();
    return false;
  }
}
