import 'package:flutter/material.dart';
import '../../../core/api/api_config.dart';
import '../../../data/repositories/parametros_repository.dart';

class ConfiguracionAvanzadaScreen extends StatefulWidget {
  const ConfiguracionAvanzadaScreen({super.key});

  @override
  State<ConfiguracionAvanzadaScreen> createState() => _ConfiguracionAvanzadaScreenState();
}

class _ConfiguracionAvanzadaScreenState extends State<ConfiguracionAvanzadaScreen> {
  final _repo = ParametrosRepository();
  final _controller = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _columnaMissing = false;
  bool _apiMode = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final params = await _repo.get();
    final apiMode = await ApiConfig.isConfigured();
    setState(() {
      _apiMode = apiMode;
      _columnaMissing = params.configuracion == null;
      _controller.text = params.configuracion ?? '';
      _loading = false;
    });
  }

  bool get _readOnly => _columnaMissing || _apiMode;

  Future<void> _save() async {
    setState(() => _saving = true);
    await _repo.updateConfiguracion(_controller.text.trim());
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración guardada')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración Avanzada')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_columnaMissing || _apiMode)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade400),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.orange),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _apiMode
                                  ? 'En modo API la configuración la administra el ERP '
                                      '(Preventa → Config. de la app). Acá solo se muestra.'
                                  : 'La columna CONFIGURACION no existe en esta base de datos.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'CONFIGURACION',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Formato: clave=valor;clave2=valor2',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _controller,
                    enabled: !_readOnly,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'moneda=dolar;orden_preparacion=false',
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (!_apiMode)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: (_readOnly || _saving) ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
