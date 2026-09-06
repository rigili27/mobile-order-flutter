import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../data/models/articulo.dart';
import '../../../data/models/deposito.dart';
import '../../../data/repositories/articulo_repository.dart';
import '../../../data/repositories/deposito_repository.dart';
import '../../../data/repositories/parametros_repository.dart';
import '../../../core/database/sync_state_database_helper.dart';
import '../../providers/api_sync_provider.dart';

/// Control de stock (modo API): la lista COMPLETA de artículos, cada uno se
/// puede marcar como "controlado" con su conteo. Al enviar, cada artículo
/// controlado se propone como ajuste de stock al ERP (queda pendiente de
/// confirmación). El estado se guarda localmente en `control_stock_local`.
class ControlStockScreen extends StatefulWidget {
  const ControlStockScreen({super.key});

  @override
  State<ControlStockScreen> createState() => _ControlStockScreenState();
}

class _ControlStockScreenState extends State<ControlStockScreen> {
  final _repo = ArticuloRepository();
  final _depoRepo = DepositoRepository();
  final _outbox = SyncStateDatabaseHelper.instance;
  final _searchCtrl = TextEditingController();

  List<Deposito> _depositos = [];
  Deposito? _deposito;
  List<Articulo> _articulos = [];
  Map<int, Map<String, dynamic>> _control = {};
  Map<int, double> _stockSistema = {};
  bool _loading = true;
  bool _enviando = false;
  bool _depositoFijo = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() => _loadArticulos());
    _init();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final depos = await _depoRepo.getAll();
    final asignado = await ParametrosRepository.depositoAsignado();
    setState(() {
      _depositos = depos;
      if (asignado != null) {
        _depositoFijo = true;
        _deposito = depos.where((d) => d.codigo == asignado).firstOrNull ??
            (depos.isNotEmpty ? depos.first : null);
      } else {
        _deposito = depos.isNotEmpty ? depos.first : null;
      }
    });
    await _loadArticulos();
  }

  Future<void> _loadArticulos() async {
    if (_deposito == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    final arts = await _repo.search(_searchCtrl.text);
    final control = await _outbox.controlStockPorArticulo(_deposito!.codigo);
    final entries = await _depoRepo.getAllEntries();
    final stock = <int, double>{};
    for (final e in entries) {
      if (e.codigo == _deposito!.codigo) stock[e.codArticulo] = e.stock;
    }
    if (!mounted) return;
    setState(() {
      _articulos = arts;
      _control = control;
      _stockSistema = stock;
      _loading = false;
    });
  }

  int get _controlados =>
      _control.values.where((c) => (c['controlado'] as int? ?? 0) == 1).length;

  Future<void> _marcar(Articulo art) async {
    final ctrl = TextEditingController(
      text: (_control[art.codigo]?['cantidad_contada'] as num?)
              ?.toString() ??
          '',
    );
    final res = await showDialog<double?>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(art.descripcion, style: const TextStyle(fontSize: 15)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          decoration: InputDecoration(
            labelText: 'Cantidad contada',
            helperText:
                'Sistema: ${(_stockSistema[art.codigo] ?? 0).toStringAsFixed(2)}',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = double.tryParse(
                  ctrl.text.replaceAll(',', '.').trim());
              Navigator.pop(context, v);
            },
            child: const Text('Marcar controlado'),
          ),
        ],
      ),
    );
    if (res == null) return;
    await _outbox.setControlStock(
      codArticulo: art.codigo,
      codDeposito: _deposito!.codigo,
      controlado: true,
      cantidadContada: res,
    );
    await _loadArticulos();
  }

  Future<void> _desmarcar(Articulo art) async {
    await _outbox.setControlStock(
      codArticulo: art.codigo,
      codDeposito: _deposito!.codigo,
      controlado: false,
    );
    await _loadArticulos();
  }

  Future<void> _enviar() async {
    if (_deposito == null || _controlados == 0 || _enviando) return;
    setState(() => _enviando = true);
    final sync = context.read<ApiSyncProvider>();
    final controlados =
        await _outbox.controlStockControlados(_deposito!.codigo);
    int ok = 0;
    for (final row in controlados) {
      final codArt = row['cod_articulo'] as int;
      final cant = (row['cantidad_contada'] as num?)?.toDouble();
      if (cant == null) continue;
      final art = await _repo.findByCodigo(codArt);
      final r = await sync.crearAjusteStock(
        codArticulo: codArt,
        descArticulo: art?.descripcion ?? '',
        codDeposito: _deposito!.codigo,
        descDeposito: _deposito!.descripcion,
        cantidadContada: cant,
      );
      if (r != null) ok++;
    }
    if (ok > 0) await _outbox.limpiarControlStock(_deposito!.codigo);
    await _loadArticulos();
    if (!mounted) return;
    setState(() => _enviando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$ok ajuste(s) enviado(s) al ERP (pendientes de confirmar).')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Control de stock'),
        actions: [
          if (_enviando)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white)),
            )
          else
            TextButton.icon(
              onPressed: _controlados == 0 ? null : _enviar,
              icon: const Icon(Icons.cloud_upload, color: Colors.white),
              label: Text('Enviar ($_controlados)',
                  style: const TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Column(children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(children: [
            if (_depositoFijo)
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Depósito: ${_deposito?.descripcion ?? '—'}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              )
            else
              DropdownButtonFormField<Deposito>(
                initialValue: _deposito,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Depósito',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: _depositos
                    .map((d) => DropdownMenuItem(
                        value: d, child: Text(d.descripcion)))
                    .toList(),
                onChanged: (d) {
                  setState(() => _deposito = d);
                  _loadArticulos();
                },
              ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar artículo...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _articulos.isEmpty
                  ? const Center(child: Text('Sin artículos'))
                  : ListView.builder(
                      itemCount: _articulos.length,
                      itemBuilder: (_, i) {
                        final art = _articulos[i];
                        final c = _control[art.codigo];
                        final controlado =
                            (c?['controlado'] as int? ?? 0) == 1;
                        final contada =
                            (c?['cantidad_contada'] as num?)?.toDouble();
                        final sistema = _stockSistema[art.codigo] ?? 0;
                        return ListTile(
                          leading: IconButton(
                            icon: Icon(
                              controlado
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: controlado ? Colors.green : Colors.grey,
                            ),
                            onPressed: () => controlado
                                ? _desmarcar(art)
                                : _marcar(art),
                          ),
                          title: Text(art.descripcion,
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text(
                            'Sistema: ${sistema.toStringAsFixed(2)}'
                            '${controlado && contada != null ? '   ·   Contado: ${contada.toStringAsFixed(2)}' : ''}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: controlado && contada != null
                              ? Text(
                                  (contada - sistema).toStringAsFixed(2),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: (contada - sistema) == 0
                                        ? Colors.grey
                                        : ((contada - sistema) > 0
                                            ? Colors.green
                                            : Colors.red),
                                  ),
                                )
                              : null,
                          onTap: () => _marcar(art),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
