import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../data/models/articulo.dart';
import '../../../data/models/deposito.dart';
import '../../../data/repositories/articulo_repository.dart';
import '../../../data/repositories/deposito_repository.dart';
import '../../providers/api_sync_provider.dart';

/// Conteo/ajuste de stock ("controlar stock"). Manda una propuesta al ERP;
/// queda pendiente hasta que un admin la confirma.
class NuevoAjusteStockScreen extends StatefulWidget {
  const NuevoAjusteStockScreen({super.key});

  @override
  State<NuevoAjusteStockScreen> createState() => _NuevoAjusteStockScreenState();
}

class _NuevoAjusteStockScreenState extends State<NuevoAjusteStockScreen> {
  final _artRepo = ArticuloRepository();
  final _depRepo = DepositoRepository();
  final _searchCtrl = TextEditingController();
  final _cantidadCtrl = TextEditingController();
  final _observacionesCtrl = TextEditingController();

  List<Articulo> _articulos = [];
  List<Deposito> _depositos = [];
  Articulo? _seleccionado;
  int? _depositoSeleccionado;
  bool _scanning = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _loadArticulos('');
    _loadDepositos();
    _searchCtrl.addListener(() => _loadArticulos(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cantidadCtrl.dispose();
    _observacionesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadArticulos(String q) async {
    final results = await _artRepo.search(q);
    if (mounted) setState(() => _articulos = results);
  }

  Future<void> _loadDepositos() async {
    final results = await _depRepo.getAll();
    if (mounted) {
      setState(() {
        _depositos = results;
        if (results.length == 1) _depositoSeleccionado = results.first.codigo;
      });
    }
  }

  Future<void> _scanBarcode() async {
    final status = await Permission.camera.request();
    if (!status.isGranted) return;
    setState(() => _scanning = true);
  }

  void _onBarcodeDetected(BarcodeCapture capture) async {
    final code = capture.barcodes.firstOrNull?.rawValue;
    if (code == null) return;
    setState(() => _scanning = false);
    final art = await _artRepo.findByBarcode(code);
    if (art != null) {
      setState(() => _seleccionado = art);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró producto con barcode: $code')),
      );
    }
  }

  Future<void> _guardar() async {
    if (_seleccionado == null) {
      _snack('Elegí un artículo.');
      return;
    }
    if (_depositoSeleccionado == null) {
      _snack('Elegí un depósito.');
      return;
    }
    final cantidad =
        double.tryParse(_cantidadCtrl.text.trim().replaceAll(',', '.'));
    if (cantidad == null || cantidad < 0) {
      _snack('Cantidad inválida.');
      return;
    }

    setState(() => _guardando = true);

    final deposito =
        _depositos.firstWhere((d) => d.codigo == _depositoSeleccionado);

    final diferencia = await context.read<ApiSyncProvider>().crearAjusteStock(
          codArticulo: _seleccionado!.codigo,
          descArticulo: _seleccionado!.descripcion,
          codDeposito: deposito.codigo,
          descDeposito: deposito.descripcion,
          cantidadContada: cantidad,
          observaciones: _observacionesCtrl.text.trim().isEmpty
              ? null
              : _observacionesCtrl.text.trim(),
        );

    if (!mounted) return;
    if (diferencia == null) {
      setState(() => _guardando = false);
      _snack(context.read<ApiSyncProvider>().errorMessage ??
          'No se pudo enviar el ajuste.');
      return;
    }

    _snack(diferencia == 0
        ? 'Sin diferencia contra el sistema. Enviado igual para registro.'
        : 'Enviado. Diferencia sugerida: ${diferencia > 0 ? '+' : ''}${diferencia.toStringAsFixed(2)}. Queda pendiente de confirmar.');
    Navigator.pop(context, true);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Escanear artículo'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => setState(() => _scanning = false),
          ),
        ),
        body: MobileScanner(onDetect: _onBarcodeDetected),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nuevo conteo de stock'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Escanear barcode',
            onPressed: _scanBarcode,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_seleccionado == null) ...[
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar artículo...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 400,
              child: _articulos.isEmpty
                  ? const Center(child: Text('Sin resultados'))
                  : ListView.builder(
                      itemCount: _articulos.length,
                      itemBuilder: (_, i) {
                        final art = _articulos[i];
                        return ListTile(
                          dense: true,
                          title: Text(art.descripcion),
                          subtitle: Text('Stock sistema: ${art.stockActual}'),
                          onTap: () => setState(() => _seleccionado = art),
                        );
                      },
                    ),
            ),
          ] else ...[
            ListTile(
              tileColor: Colors.blue.shade50,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              title: Text(_seleccionado!.descripcion,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Stock sistema: ${_seleccionado!.stockActual}'),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _seleccionado = null),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _depositoSeleccionado,
              decoration: const InputDecoration(
                  labelText: 'Depósito', border: OutlineInputBorder()),
              items: _depositos
                  .map((d) => DropdownMenuItem(
                      value: d.codigo, child: Text(d.descripcion)))
                  .toList(),
              onChanged: (v) => setState(() => _depositoSeleccionado = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cantidadCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Cantidad contada',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _observacionesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Observaciones (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Enviar conteo'),
            ),
          ],
        ],
      ),
    );
  }
}
