import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/database/reparto_database_helper.dart';
import '../models/reparto_models.dart';

class RepartoRepository {
  Future<Database> get _db => RepartoDatabaseHelper.instance.db;

  /// Reemplaza todas las hojas/paradas/renglones con el snapshot de la API.
  /// No toca `entrega_outbox`.
  Future<void> replaceHojas(List<HojaRuta> hojas) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete('parada_renglon');
      await txn.delete('parada');
      await txn.delete('hoja_ruta');
      for (final h in hojas) {
        await txn.insert('hoja_ruta', h.toRow());
        for (final p in h.paradas) {
          await txn.insert('parada', p.toRow());
          for (final r in p.renglones) {
            await txn.insert('parada_renglon', r.toRow(p.id));
          }
        }
      }
    });
  }

  Future<List<HojaRuta>> getHojas() async {
    final db = await _db;
    final hojaRows = await db.query('hoja_ruta', orderBy: 'fecha, id');
    final result = <HojaRuta>[];
    for (final hr in hojaRows) {
      result.add(HojaRuta.fromRow(hr, await _paradasDe(hr['id'] as int)));
    }
    return result;
  }

  Future<HojaRuta?> getHoja(int id) async {
    final db = await _db;
    final rows = await db.query('hoja_ruta', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return HojaRuta.fromRow(rows.first, await _paradasDe(id));
  }

  Future<Parada?> getParada(int id) async {
    final db = await _db;
    final rows = await db.query('parada', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return Parada.fromRow(rows.first, await _renglonesDe(id));
  }

  Future<List<Parada>> _paradasDe(int hojaId) async {
    final db = await _db;
    final rows = await db.query('parada', where: 'hoja_id = ?', whereArgs: [hojaId], orderBy: 'orden, id');
    return [for (final r in rows) Parada.fromRow(r, await _renglonesDe(r['id'] as int))];
  }

  Future<List<ParadaRenglon>> _renglonesDe(int paradaId) async {
    final db = await _db;
    final rows = await db.query('parada_renglon', where: 'parada_id = ?', whereArgs: [paradaId], orderBy: 'id');
    return rows.map(ParadaRenglon.fromRow).toList();
  }

  Future<void> setEstadoHoja(int id, String estado) async {
    final db = await _db;
    await db.update('hoja_ruta', {'estado': estado}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setEstadoParada(int id, String estado) async {
    final db = await _db;
    await db.update('parada', {'estado': estado}, where: 'id = ?', whereArgs: [id]);
  }

  // ── outbox de confirmaciones de entrega ──────────────────────────────
  Future<String> enqueueEntrega(int paradaId, Map<String, dynamic> payload) async {
    final db = await _db;
    final uuid = payload['uuid'] as String;
    await db.insert(
      'entrega_outbox',
      {
        'uuid': uuid,
        'parada_id': paradaId,
        'payload_json': jsonEncode(payload),
        'estado': 'pendiente',
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return uuid;
  }

  Future<List<Map<String, dynamic>>> outboxPendiente() async {
    final db = await _db;
    return db.query('entrega_outbox',
        where: "estado IN ('pendiente', 'error')", orderBy: 'created_at');
  }

  Future<void> marcarOutbox(String uuid, {required String estado, int? pruebaId, String? error}) async {
    final db = await _db;
    await db.update(
      'entrega_outbox',
      {'estado': estado, 'prueba_id': pruebaId, 'error': error},
      where: 'uuid = ?',
      whereArgs: [uuid],
    );
  }

  Future<int> outboxPendienteCount() async {
    final db = await _db;
    final r = await db.rawQuery(
        "SELECT COUNT(*) c FROM entrega_outbox WHERE estado IN ('pendiente', 'error')");
    return Sqflite.firstIntValue(r) ?? 0;
  }
}
