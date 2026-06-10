import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../data/models/cliente.dart';
import '../../../data/repositories/cliente_repository.dart';
import 'cliente_detalle_screen.dart';

class ClientesScreen extends StatefulWidget {
  const ClientesScreen({super.key});

  @override
  State<ClientesScreen> createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  final _repo = ClienteRepository();
  final _searchCtrl = TextEditingController();
  List<Cliente> _clientes = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load('');
    _searchCtrl.addListener(() => _load(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load(String query) async {
    setState(() => _loading = true);
    final results = await _repo.search(query);
    if (mounted) setState(() { _clientes = results; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar por nombre, código, CUIT...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () { _searchCtrl.clear(); _load(''); },
                      )
                    : null,
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _clientes.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
                        itemCount: _clientes.length,
                        itemBuilder: (_, i) => _ClienteTile(
                          cliente: _clientes[i],
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ClienteDetalleScreen(cliente: _clientes[i]),
                            ),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

class _ClienteTile extends StatelessWidget {
  final Cliente cliente;
  final VoidCallback onTap;

  const _ClienteTile({required this.cliente, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    final saldoColor = cliente.saldo > 0 ? Colors.red.shade700 : Colors.green.shade700;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          cliente.codigo.toString(),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      title: Text(cliente.nombre, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(cliente.localidad.isNotEmpty ? cliente.localidad : cliente.domicilio),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(fmt.format(cliente.saldo),
              style: TextStyle(color: saldoColor, fontWeight: FontWeight.bold, fontSize: 13)),
          const Text('saldo', style: TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      ),
      onTap: onTap,
    );
  }
}
