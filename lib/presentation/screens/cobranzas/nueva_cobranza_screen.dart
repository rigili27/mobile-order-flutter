import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';

import '../../../core/api/api_config.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/cobranza.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../data/repositories/cobranza_repository.dart';
import '../../providers/api_sync_provider.dart';

/// Registro de una pre-cobranza en la calle. En modo API se sube como un
/// `Receipt` en Borrador al ERP (administración lo confirma). El detalle de
/// cheque / transferencia viaja plano en el payload (mismas keys que el DTO
/// `CrearCobranzaMovilData`).
class NuevaCobranzaScreen extends StatefulWidget {
  final Cliente? cliente;

  const NuevaCobranzaScreen({super.key, this.cliente});

  @override
  State<NuevaCobranzaScreen> createState() => _NuevaCobranzaScreenState();
}

class _NuevaCobranzaScreenState extends State<NuevaCobranzaScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repo = CobranzaRepository();
  final _sigController =
      SignatureController(penStrokeWidth: 3, penColor: Colors.black);

  final _importeCtrl = TextEditingController();
  final _referenciaCtrl = TextEditingController();
  final _notasCtrl = TextEditingController();

  // cheque
  final _chBancoCtrl = TextEditingController();
  final _chSucursalCtrl = TextEditingController();
  final _chNumeroCtrl = TextEditingController();
  final _chLibradorCtrl = TextEditingController();
  final _chCuitCtrl = TextEditingController();
  DateTime? _chEmision;
  DateTime? _chVencimiento;
  bool _chElectronico = false;

  // transferencia
  final _trBancoCtrl = TextEditingController();
  final _trComprobanteCtrl = TextEditingController();
  final _trDetalleCtrl = TextEditingController();
  DateTime? _trFecha;

  Cliente? _cliente;
  DateTime _fecha = DateTime.now();
  CobranzaFormaPago _formaPago = CobranzaFormaPago.efectivo;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _cliente = widget.cliente;
  }

  @override
  void dispose() {
    _sigController.dispose();
    for (final c in [
      _importeCtrl,
      _referenciaCtrl,
      _notasCtrl,
      _chBancoCtrl,
      _chSucursalCtrl,
      _chNumeroCtrl,
      _chLibradorCtrl,
      _chCuitCtrl,
      _trBancoCtrl,
      _trComprobanteCtrl,
      _trDetalleCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String _fmtFecha(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Future<void> _selectCliente() async {
    final cliente = await showSearch<Cliente?>(
      context: context,
      delegate: _ClienteSearchDelegate(),
    );
    if (cliente != null && mounted) setState(() => _cliente = cliente);
  }

  Future<DateTime?> _pickDate(DateTime? initial) => showDatePicker(
        context: context,
        initialDate: initial ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime(2100),
      );

  Map<String, dynamic> _detalle() {
    switch (_formaPago) {
      case CobranzaFormaPago.cheque:
        return {
          'chequeBanco': _chBancoCtrl.text.trim(),
          'chequeSucursal': _chSucursalCtrl.text.trim().isEmpty
              ? null
              : _chSucursalCtrl.text.trim(),
          'chequeNumero': _chNumeroCtrl.text.trim(),
          'chequeFechaEmision':
              _chEmision == null ? null : _fmtFecha(_chEmision!),
          'chequeFechaVencimiento':
              _chVencimiento == null ? null : _fmtFecha(_chVencimiento!),
          'chequeLibrador': _chLibradorCtrl.text.trim(),
          'chequeCuitLibrador': _chCuitCtrl.text.trim(),
          'chequeElectronico': _chElectronico,
        };
      case CobranzaFormaPago.transferencia:
        return {
          'transferBanco': _trBancoCtrl.text.trim().isEmpty
              ? null
              : _trBancoCtrl.text.trim(),
          'transferComprobante': _trComprobanteCtrl.text.trim(),
          'transferFecha': _trFecha == null ? null : _fmtFecha(_trFecha!),
          'transferDetalle': _trDetalleCtrl.text.trim().isEmpty
              ? null
              : _trDetalleCtrl.text.trim(),
        };
      case CobranzaFormaPago.efectivo:
        return const {};
    }
  }

  String? _validarDetalle() {
    if (_formaPago == CobranzaFormaPago.cheque) {
      if (_chBancoCtrl.text.trim().isEmpty ||
          _chNumeroCtrl.text.trim().isEmpty ||
          _chLibradorCtrl.text.trim().isEmpty ||
          _chCuitCtrl.text.trim().isEmpty ||
          _chEmision == null ||
          _chVencimiento == null) {
        return 'Completá todos los datos del cheque.';
      }
    }
    if (_formaPago == CobranzaFormaPago.transferencia) {
      if (_trComprobanteCtrl.text.trim().isEmpty || _trFecha == null) {
        return 'Completá el comprobante y la fecha de la transferencia.';
      }
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cliente == null) {
      _snack('Seleccioná un cliente.');
      return;
    }
    final errDetalle = _validarDetalle();
    if (errDetalle != null) {
      _snack(errDetalle);
      return;
    }

    setState(() => _guardando = true);

    Uint8List? firma;
    if (_sigController.isNotEmpty) {
      firma = await _sigController.toPngBytes(height: 200, width: 400);
    }

    final cobranza = Cobranza(
      codCliente: _cliente!.codigo,
      fecha: _fmtFecha(_fecha),
      importe: double.parse(_importeCtrl.text.trim().replaceAll(',', '.')),
      formaPago: _formaPago,
      detalle: _detalle(),
      referencia: _referenciaCtrl.text.trim().isEmpty
          ? null
          : _referenciaCtrl.text.trim(),
      notas: _notasCtrl.text.trim().isEmpty ? null : _notasCtrl.text.trim(),
      firma: firma,
    );

    try {
      final id = await _repo.insert(cobranza);
      if (await ApiConfig.hasSession() && mounted) {
        // ignore: use_build_context_synchronously
        unawaited(context.read<ApiSyncProvider>().subirCobranza(id));
      }
      if (!mounted) return;
      _snack('Cobranza registrada.');
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        _snack('No se pudo guardar la cobranza: $e');
      }
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva cobranza')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(_cliente?.nombre ?? 'Seleccionar cliente'),
                subtitle: _cliente == null
                    ? null
                    : Text('${_cliente!.codigo} · ${_cliente!.localidad}'),
                trailing: const Icon(Icons.search),
                onTap: _selectCliente,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _importeCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Importe',
                prefixIcon: Icon(Icons.attach_money),
                border: OutlineInputBorder(),
              ),
              validator: (v) {
                final parsed =
                    double.tryParse((v ?? '').trim().replaceAll(',', '.'));
                if (parsed == null || parsed <= 0) return 'Importe inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event),
              title: const Text('Fecha'),
              subtitle: Text(_fmtFecha(_fecha)),
              trailing: const Icon(Icons.edit_calendar),
              onTap: () async {
                final d = await _pickDate(_fecha);
                if (d != null) setState(() => _fecha = d);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<CobranzaFormaPago>(
              initialValue: _formaPago,
              decoration: const InputDecoration(
                labelText: 'Forma de pago',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                    value: CobranzaFormaPago.efectivo, child: Text('Efectivo')),
                DropdownMenuItem(
                    value: CobranzaFormaPago.cheque, child: Text('Cheque')),
                DropdownMenuItem(
                    value: CobranzaFormaPago.transferencia,
                    child: Text('Transferencia')),
              ],
              onChanged: (v) =>
                  setState(() => _formaPago = v ?? CobranzaFormaPago.efectivo),
            ),
            const SizedBox(height: 12),
            if (_formaPago == CobranzaFormaPago.cheque) ..._chequeFields(),
            if (_formaPago == CobranzaFormaPago.transferencia)
              ..._transferFields(),
            TextFormField(
              controller: _referenciaCtrl,
              decoration: const InputDecoration(
                labelText: 'Referencia (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _notasCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notas (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Firma del cliente',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Signature(
              controller: _sigController,
              height: 150,
              backgroundColor: Colors.grey.shade100,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _sigController.clear,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Limpiar'),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _guardando ? null : _guardar,
              icon: _guardando
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save),
              label: const Text('Guardar cobranza'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _chequeFields() => [
        TextFormField(
          controller: _chBancoCtrl,
          decoration: const InputDecoration(
              labelText: 'Banco', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _chSucursalCtrl,
          decoration: const InputDecoration(
              labelText: 'Sucursal (opcional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _chNumeroCtrl,
          decoration: const InputDecoration(
              labelText: 'Número de cheque', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await _pickDate(_chEmision);
                if (d != null) setState(() => _chEmision = d);
              },
              child: Text(_chEmision == null
                  ? 'Emisión'
                  : 'Emisión: ${_fmtFecha(_chEmision!)}'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () async {
                final d = await _pickDate(_chVencimiento);
                if (d != null) setState(() => _chVencimiento = d);
              },
              child: Text(_chVencimiento == null
                  ? 'Vencimiento'
                  : 'Vto: ${_fmtFecha(_chVencimiento!)}'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        TextFormField(
          controller: _chLibradorCtrl,
          decoration: const InputDecoration(
              labelText: 'Librador', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _chCuitCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              labelText: 'CUIT del librador', border: OutlineInputBorder()),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Cheque electrónico (ECHEQ)'),
          value: _chElectronico,
          onChanged: (v) => setState(() => _chElectronico = v),
        ),
        const SizedBox(height: 4),
      ];

  List<Widget> _transferFields() => [
        TextFormField(
          controller: _trBancoCtrl,
          decoration: const InputDecoration(
              labelText: 'Banco (opcional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _trComprobanteCtrl,
          decoration: const InputDecoration(
              labelText: 'Número de comprobante',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: () async {
            final d = await _pickDate(_trFecha);
            if (d != null) setState(() => _trFecha = d);
          },
          child: Text(_trFecha == null
              ? 'Fecha de la transferencia'
              : 'Fecha: ${_fmtFecha(_trFecha!)}'),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _trDetalleCtrl,
          decoration: const InputDecoration(
              labelText: 'Detalle (opcional)', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 4),
      ];
}

class _ClienteSearchDelegate extends SearchDelegate<Cliente?> {
  final _repo = ClienteRepository();

  _ClienteSearchDelegate() : super(searchFieldLabel: 'Buscar cliente...');

  @override
  List<Widget> buildActions(BuildContext ctx) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext ctx) => IconButton(
      icon: const Icon(Icons.arrow_back), onPressed: () => close(ctx, null));

  @override
  Widget buildResults(BuildContext ctx) => _buildList(ctx);

  @override
  Widget buildSuggestions(BuildContext ctx) => _buildList(ctx);

  Widget _buildList(BuildContext ctx) {
    return FutureBuilder<List<Cliente>>(
      future: _repo.search(query),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) return const Center(child: Text('Sin resultados'));
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (_, i) => ListTile(
            title: Text(list[i].nombre),
            subtitle: Text('${list[i].codigo} · ${list[i].localidad}'),
            onTap: () => close(ctx, list[i]),
          ),
        );
      },
    );
  }
}
