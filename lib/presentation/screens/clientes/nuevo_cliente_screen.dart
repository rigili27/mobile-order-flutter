import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/cliente.dart';
import '../../providers/api_sync_provider.dart';

/// Alta de cliente desde la calle (solo modo API, requiere conexión). El ERP
/// crea el Customer real pendiente de revisión y devuelve el código.
class NuevoClienteScreen extends StatefulWidget {
  const NuevoClienteScreen({super.key});

  @override
  State<NuevoClienteScreen> createState() => _NuevoClienteScreenState();
}

class _NuevoClienteScreenState extends State<NuevoClienteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _cuitCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _domicilioCtrl = TextEditingController();
  final _localidadCtrl = TextEditingController();

  int? _condicionIva;
  String _condicionVenta = 'contado';
  bool _guardando = false;

  static const _condicionesIva = {
    1: 'Responsable Inscripto',
    6: 'Monotributo',
    4: 'Exento',
    5: 'Consumidor Final',
  };

  @override
  void dispose() {
    for (final c in [
      _nombreCtrl,
      _cuitCtrl,
      _telefonoCtrl,
      _emailCtrl,
      _domicilioCtrl,
      _localidadCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _guardando = true);

    final provider = context.read<ApiSyncProvider>();
    final Cliente? cliente = await provider.crearCliente(
      nombre: _nombreCtrl.text.trim(),
      cuit: _cuitCtrl.text.trim().isEmpty ? null : _cuitCtrl.text.trim(),
      condicionIva: _condicionIva,
      condicionVenta: _condicionVenta,
      telefono:
          _telefonoCtrl.text.trim().isEmpty ? null : _telefonoCtrl.text.trim(),
      email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      domicilio:
          _domicilioCtrl.text.trim().isEmpty ? null : _domicilioCtrl.text.trim(),
      localidad:
          _localidadCtrl.text.trim().isEmpty ? null : _localidadCtrl.text.trim(),
    );

    if (!mounted) return;
    if (cliente == null) {
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(provider.errorMessage ?? 'No se pudo crear el cliente.'),
      ));
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cliente creado. Queda pendiente de revisión.')),
    );
    Navigator.pop(context, cliente);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nuevo cliente')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nombreCtrl,
              decoration: const InputDecoration(
                  labelText: 'Nombre / Razón social',
                  border: OutlineInputBorder()),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cuitCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                  labelText: 'CUIT (opcional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _condicionIva,
              decoration: const InputDecoration(
                  labelText: 'Condición frente al IVA (opcional)',
                  border: OutlineInputBorder()),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin especificar')),
                ..._condicionesIva.entries.map((e) =>
                    DropdownMenuItem(value: e.key, child: Text(e.value))),
              ],
              onChanged: (v) => setState(() => _condicionIva = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _condicionVenta,
              decoration: const InputDecoration(
                  labelText: 'Condición de venta', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'contado', child: Text('Contado')),
                DropdownMenuItem(
                    value: 'cuenta_corriente', child: Text('Cuenta corriente')),
              ],
              onChanged: (v) =>
                  setState(() => _condicionVenta = v ?? 'contado'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefonoCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                  labelText: 'Teléfono (opcional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email (opcional)', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _domicilioCtrl,
              decoration: const InputDecoration(
                  labelText: 'Domicilio (opcional)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _localidadCtrl,
              decoration: const InputDecoration(
                  labelText: 'Localidad (opcional)',
                  border: OutlineInputBorder()),
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
              label: const Text('Crear cliente'),
            ),
          ],
        ),
      ),
    );
  }
}
