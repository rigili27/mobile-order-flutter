import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/api/api_config.dart';
import '../../../core/database/database_file_manager.dart';
import '../../../core/database/database_helper.dart';
import '../../../core/database/orden_preparacion_database_helper.dart';
import '../../../data/models/parametros.dart';
import '../../../data/repositories/parametros_repository.dart';
import 'settings_shared.dart';

/// Compartir la base de datos, ver los archivos locales, y las acciones
/// destructivas (eliminar DB / restaurar la de ejemplo) — todo junto para no
/// saturar el menú principal de Configuración.
class DatabaseScreen extends StatefulWidget {
  final Future<void> Function()? onDatabaseReady;

  const DatabaseScreen({super.key, this.onDatabaseReady});

  @override
  State<DatabaseScreen> createState() => _DatabaseScreenState();
}

class _DatabaseScreenState extends State<DatabaseScreen> {
  Parametros? _params;
  bool _apiMode = false;
  List<_DbFileInfo> _dbFiles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiMode = await ApiConfig.isConfigured();
    Parametros? params;
    try {
      params = await ParametrosRepository().get();
    } catch (_) {}
    if (mounted) setState(() { _apiMode = apiMode; _params = params; });
    await _loadDbFiles();
  }

  Future<void> _loadDbFiles() async {
    final dir = (await getApplicationDocumentsDirectory()).path;
    final entries = [
      ('moviles.db', _apiMode ? 'Base WiFi' : 'Base activa'),
      ('backup_moviles.db', 'Respaldo WiFi'),
      ('moviles_api.db', _apiMode ? 'Base activa (API)' : 'Base API'),
      ('backup_moviles_api.db', 'Respaldo API'),
      ('movil_sync.db', 'Estado de sync'),
      if (_params?.ordenPreparacion ?? false)
        ('moviles_orden_preparacion.db', 'Órdenes Prep.'),
    ];
    final result = <_DbFileInfo>[];
    for (final (name, label) in entries) {
      final f = File(p.join(dir, name));
      if (await f.exists()) {
        final stat = await f.stat();
        result.add(_DbFileInfo(
            name: name, label: label, sizeBytes: stat.size, modified: stat.modified));
      }
    }
    if (mounted) setState(() => _dbFiles = result);
  }

  Future<void> _compartirDB() async {
    try {
      final mgr = DatabaseFileManager.instance;
      final files = <XFile>[];

      final activePath = await mgr.activePath;
      if (await File(activePath).exists()) {
        final exportFile = await mgr.prepareExport();
        files.add(XFile(exportFile.path,
            mimeType: 'application/octet-stream', name: 'moviles.db'));
      }

      final backupPath = await mgr.backupPath;
      if (await File(backupPath).exists()) {
        files.add(XFile(backupPath,
            mimeType: 'application/octet-stream', name: 'backup_moviles.db'));
      }

      if (_params?.ordenPreparacion ?? false) {
        final ordenPath = await OrdenPreparacionDatabaseHelper.instance.dbPath;
        if (await File(ordenPath).exists()) {
          final tmpDir = await getTemporaryDirectory();
          final dst = p.join(tmpDir.path, 'moviles_orden_preparacion.db');
          final copy = await File(ordenPath).copy(dst);
          files.add(XFile(copy.path,
              mimeType: 'application/octet-stream',
              name: 'moviles_orden_preparacion.db'));
        }
      }

      if (files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay base de datos para compartir.')),
          );
        }
        return;
      }

      await Share.shareXFiles(files, subject: 'Base de datos moviles');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error al compartir: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _eliminarDB() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar base de datos'),
        content: const Text(
          '¿Estás seguro? Se eliminarán todos los datos locales. '
          'Necesitarás recibir una nueva base de datos desde la PC.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await DatabaseHelper.instance.deleteDatabase();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Base de datos eliminada.'),
            backgroundColor: Colors.orange),
      );
      await onDbChanged(widget.onDatabaseReady);
    }
  }

  Future<void> _restaurarDesdeAssets() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restaurar BD inicial'),
        content: const Text(
            'Se restaurará la base de datos de ejemplo incluida en la app. '
            'Los datos actuales se perderán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restaurar')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    await DatabaseHelper.instance.deleteDatabase();
    await DatabaseHelper.instance.copyFromAssets();
    await onDbChanged(widget.onDatabaseReady);
  }

  static String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    final date =
        '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    final time =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '$date $time';
  }

  static String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Base de datos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Compartir ────────────────────────────────────────────────────
          SectionTitle('Compartir'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                const Text(
                  'Envía la base de datos por WhatsApp u otra app.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: _compartirDB,
                  icon: const Icon(Icons.share),
                  label: const Text('Compartir base de datos'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44)),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 16),

          // ── Archivos ─────────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: SectionTitle('Archivos de base de datos')),
              TextButton.icon(
                onPressed: _loadDbFiles,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Actualizar', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          Card(
            child: _dbFiles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No se encontraron archivos.',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  )
                : Column(
                    children: _dbFiles
                        .map((f) => ListTile(
                              dense: true,
                              leading: const Icon(Icons.storage_outlined,
                                  color: Colors.blueGrey),
                              title: Text(f.name,
                                  style: const TextStyle(
                                      fontSize: 13,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  '${_fmtDate(f.modified)} · ${_fmtSize(f.sizeBytes)}',
                                  style: const TextStyle(fontSize: 11)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                    color: Colors.blueGrey.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: Colors.blueGrey.shade200)),
                                child: Text(f.label,
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.blueGrey.shade700)),
                              ),
                            ))
                        .toList(),
                  ),
          ),
          const SizedBox(height: 16),

          // ── Zona de peligro ──────────────────────────────────────────────
          SectionTitle('Zona de peligro'),
          Card(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Colors.red.shade200)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Text(
                  _apiMode
                      ? 'Elimina la base local de la API (moviles_api.db). '
                          'Tras esto hay que volver a sincronizar. No toca la base WiFi.'
                      : 'Elimina la base de datos local. '
                          'Útil si la DB está corrupta y no podés ingresar.',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _eliminarDB,
                  icon: const Icon(Icons.delete_forever),
                  label: Text(_apiMode
                      ? 'Eliminar base local (API)'
                      : 'Eliminar base de datos'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      backgroundColor: Colors.red.shade700,
                      foregroundColor: Colors.white),
                ),
              ]),
            ),
          ),

          if (!_apiMode) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _restaurarDesdeAssets,
              icon: const Icon(Icons.restore),
              label: const Text('Restaurar base de datos de ejemplo'),
              style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white),
            ),
          ],
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _DbFileInfo {
  final String name;
  final String label;
  final int sizeBytes;
  final DateTime modified;
  const _DbFileInfo(
      {required this.name,
      required this.label,
      required this.sizeBytes,
      required this.modified});
}
