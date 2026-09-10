import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import '../../../data/models/reparto_models.dart';
import '../../providers/reparto_provider.dart';

class ConfirmarEntregaScreen extends StatefulWidget {
  const ConfirmarEntregaScreen({super.key, required this.paradaId});

  final int paradaId;

  @override
  State<ConfirmarEntregaScreen> createState() => _ConfirmarEntregaScreenState();
}

class _ConfirmarEntregaScreenState extends State<ConfirmarEntregaScreen> {
  final _sig = SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  final _recibio = TextEditingController();
  final _dni = TextEditingController();
  final _notas = TextEditingController();
  final _picker = ImagePicker();

  String _outcome = 'entregada'; // entregada | parcial | rechazada
  bool _sinFirma = false;
  bool _enviando = false;
  final List<Uint8List> _fotos = [];
  final Map<int, TextEditingController> _entregado = {};
  final Map<int, TextEditingController> _motivo = {};

  Parada? _parada;

  @override
  void initState() {
    super.initState();
    final prov = context.read<RepartoProvider>();
    for (final h in prov.hojas) {
      for (final p in h.paradas) {
        if (p.id == widget.paradaId) _parada = p;
      }
    }
    for (final r in _parada?.renglones ?? const <ParadaRenglon>[]) {
      final key = r.stockMovementId ?? r.hashCode;
      _entregado[key] = TextEditingController(text: _n(r.cantidad));
      _motivo[key] = TextEditingController();
    }
  }

  @override
  void dispose() {
    _sig.dispose();
    _recibio.dispose();
    _dni.dispose();
    _notas.dispose();
    for (final c in _entregado.values) {
      c.dispose();
    }
    for (final c in _motivo.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _tomarFoto() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 60, maxWidth: 1600);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    setState(() => _fotos.add(bytes));
  }

  Future<Position?> _ubicacion() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(timeLimit: Duration(seconds: 8)),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _confirmar() async {
    final parada = _parada;
    if (parada == null) return;

    if (_sinFirma && _fotos.isEmpty) {
      _snack('Si dejás la mercadería sin firma, sacá al menos una foto.');
      return;
    }
    if (!_sinFirma && _outcome != 'rechazada' && _sig.isEmpty) {
      _snack('Falta la firma de quien recibe.');
      return;
    }

    setState(() => _enviando = true);

    String? firmaBase64;
    if (!_sinFirma && _sig.isNotEmpty) {
      final png = await _sig.toPngBytes(height: 200, width: 400);
      if (png != null) firmaBase64 = base64Encode(png);
    }

    final pos = await _ubicacion();
    if (!mounted) return;

    final renglones = <Map<String, dynamic>>[];
    if (_outcome != 'entregada') {
      for (final r in parada.renglones) {
        final key = r.stockMovementId ?? r.hashCode;
        final entregado = double.tryParse(_entregado[key]?.text.replaceAll(',', '.') ?? '') ?? r.cantidad;
        renglones.add({
          'stockMovementId': r.stockMovementId,
          'entregado': _outcome == 'rechazada' ? 0 : entregado,
          'motivo': _motivo[key]?.text.trim().isEmpty ?? true ? null : _motivo[key]!.text.trim(),
        });
      }
    }

    await context.read<RepartoProvider>().confirmarEntrega(
          parada: parada,
          outcome: _outcome,
          recibidoPor: _recibio.text.trim().isEmpty ? null : _recibio.text.trim(),
          dni: _dni.text.trim().isEmpty ? null : _dni.text.trim(),
          firmaBase64: firmaBase64,
          dejadoSinFirma: _sinFirma,
          fotosBase64: _fotos.map(base64Encode).toList(),
          lat: pos?.latitude,
          lng: pos?.longitude,
          notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
          renglones: renglones,
        );

    if (!mounted) return;
    setState(() => _enviando = false);
    final err = context.read<RepartoProvider>().error;
    _snack(err ?? 'Entrega registrada.');
    Navigator.of(context)
      ..pop()
      ..pop(); // vuelve a la hoja de ruta
  }

  void _snack(String m) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final parada = _parada;
    if (parada == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Confirmar entrega')),
        body: const Center(child: Text('La parada ya no está disponible.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('Entrega · ${parada.cliente}')),
      body: AbsorbPointer(
        absorbing: _enviando,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'entregada', label: Text('Completa')),
                ButtonSegment(value: 'parcial', label: Text('Parcial')),
                ButtonSegment(value: 'rechazada', label: Text('Rechazada')),
              ],
              selected: {_outcome},
              onSelectionChanged: (s) => setState(() => _outcome = s.first),
            ),
            const SizedBox(height: 16),
            if (_outcome == 'parcial') ...[
              const Text('Cantidad entregada por artículo',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ...parada.renglones.map((r) {
                final key = r.stockMovementId ?? r.hashCode;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${r.articulo} (de ${_n(r.cantidad)})'),
                      Row(
                        children: [
                          SizedBox(
                            width: 90,
                            child: TextField(
                              controller: _entregado[key],
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(labelText: 'Entregado'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _motivo[key],
                              decoration: const InputDecoration(labelText: 'Motivo del faltante'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }),
              const Divider(height: 24),
            ],
            TextField(
              controller: _recibio,
              decoration: const InputDecoration(labelText: 'Nombre de quien recibe'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _dni,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'DNI de quien recibe'),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Dejado sin firma'),
              subtitle: const Text('Materiales dejados en el lugar — requiere foto'),
              value: _sinFirma,
              onChanged: (v) => setState(() => _sinFirma = v),
            ),
            if (!_sinFirma && _outcome != 'rechazada') ...[
              const SizedBox(height: 8),
              const Text('Firma', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)),
                child: Signature(controller: _sig, height: 180, backgroundColor: Colors.grey.shade100),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(onPressed: () => _sig.clear(), child: const Text('Borrar')),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Fotos', style: TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                TextButton.icon(
                  onPressed: _tomarFoto,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Sacar foto'),
                ),
              ],
            ),
            if (_fotos.isNotEmpty)
              SizedBox(
                height: 90,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _fotos.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.memory(_fotos[i], width: 90, height: 90, fit: BoxFit.cover),
                      ),
                      Positioned(
                        right: 0,
                        child: GestureDetector(
                          onTap: () => setState(() => _fotos.removeAt(i)),
                          child: Container(
                            color: Colors.black54,
                            child: const Icon(Icons.close, size: 18, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _notas,
              decoration: const InputDecoration(labelText: 'Observaciones (opcional)'),
              maxLines: 2,
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _enviando ? null : _confirmar,
              icon: _enviando
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: Text(_enviando ? 'Guardando…' : 'Confirmar entrega'),
            ),
          ],
        ),
      ),
    );
  }

  static String _n(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();
}
