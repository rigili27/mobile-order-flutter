import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:signature/signature.dart';
import '../../../data/models/articulo.dart';
import '../../../data/models/cliente.dart';
import '../../../data/models/deposito.dart';
import '../../../data/repositories/articulo_repository.dart';
import '../../../data/repositories/cliente_repository.dart';
import '../../../data/repositories/deposito_repository.dart';
import '../../../data/repositories/orden_preparacion_repository.dart';
import '../../providers/auth_provider.dart';
import '../../providers/orden_preparacion_provider.dart';
import '../../providers/pedido_provider.dart';
import 'orden_preparacion_detalle_screen.dart';

class NuevaOrdenPreparacionScreen extends StatefulWidget {
  final int? editOrdenId;

  const NuevaOrdenPreparacionScreen({super.key, this.editOrdenId});

  @override
  State<NuevaOrdenPreparacionScreen> createState() =>
      _NuevaOrdenPreparacionScreenState();
}

class _NuevaOrdenPreparacionScreenState
    extends State<NuevaOrdenPreparacionScreen> {
  final _quienCtrl = TextEditingController();
  String? _selectedServicio;
  final _sigController =
      SignatureController(penStrokeWidth: 3, penColor: Colors.black);
  bool _loadingEdit = false;

  static const _servicioOpciones = ['Garantía', 'Reparación', 'Reparación interna'];

  bool get _isEditing => widget.editOrdenId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadForEdit());
    }
  }

  @override
  void dispose() {
    _quienCtrl.dispose();
    _sigController.dispose();
    super.dispose();
  }

  Future<void> _loadForEdit() async {
    setState(() => _loadingEdit = true);
    final repo = OrdenPreparacionRepository();
    final artRepo = ArticuloRepository();
    final cliRepo = ClienteRepository();

    final cabecera = await repo.getById(widget.editOrdenId!);
    if (cabecera == null || !mounted) {
      setState(() => _loadingEdit = false);
      return;
    }

    final detalles = await repo.getDetalles(widget.editOrdenId!);
    final cliente = await cliRepo.findByCodigo(cabecera.codCliente);

    final items = <ItemPedido>[];
    for (final d in detalles) {
      final art = await artRepo.findByCodigo(d.codArticulo);
      if (art != null) {
        items.add(ItemPedido(
          articulo: art,
          cantidad: d.cantidad,
          precio: d.precio,
          porDto: d.porDto,
          comentario: d.comentario,
          deposito: d.deposito,
        ));
      }
    }

    if (!mounted) return;
    final provider = context.read<OrdenPreparacionProvider>();
    provider.loadForEdit(cabecera, cliente ?? _dummyCliente(cabecera.codCliente), items);
    _quienCtrl.text = cabecera.quienRecibio;
    setState(() {
      _selectedServicio = _servicioOpciones.contains(cabecera.comentarios)
          ? cabecera.comentarios
          : null;
      _loadingEdit = false;
    });
  }

  Cliente _dummyCliente(int codigo) => Cliente(
        codigo: codigo,
        nombre: 'Cliente $codigo',
        domicilio: '',
        localidad: '',
        telefono: '',
        nroCuit: '',
        nrolPrecios: 1,
        saldo: 0,
      );

  void _tryAutoSave() {
    final codVendedor = context.read<AuthProvider>().vendedor?.codigo;
    if (codVendedor != null) {
      context.read<OrdenPreparacionProvider>().autoGuardar(codVendedor);
    }
  }

  Future<bool> _onWillPop() async {
    final provider = context.read<OrdenPreparacionProvider>();
    if (!provider.hasItems || provider.pedidoId != null) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Orden sin guardar'),
        content: const Text(
            'Hay productos agregados pero no se seleccionó cliente. '
            'Si salís ahora, se perderán.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Quedarme')),
          TextButton(
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Descartar')),
        ],
      ),
    );
    return discard == true;
  }

  Future<void> _selectCliente() async {
    final cliente = await showSearch<Cliente?>(
      context: context,
      delegate: _ClienteSearchDelegate(),
    );
    if (cliente != null && mounted) {
      context.read<OrdenPreparacionProvider>().setCliente(cliente);
      _tryAutoSave();
    }
  }

  Future<void> _addProducto() async {
    final provider = context.read<OrdenPreparacionProvider>();
    final cliente = provider.cliente;
    if (cliente == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero seleccioná un cliente.')),
      );
      return;
    }
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _AddProductoSheet(nrolPrecios: cliente.nrolPrecios),
    );
    _tryAutoSave();
  }

  Future<void> _guardar() async {
    final provider = context.read<OrdenPreparacionProvider>();
    final auth = context.read<AuthProvider>();

    if (_sigController.isNotEmpty) {
      final sigData = await _sigController.toPngBytes(height: 200, width: 400);
      if (sigData != null) provider.setFirma(sigData.toList());
    }
    provider.setQuienRecibio(_quienCtrl.text.trim());
    provider.setComentarios(_selectedServicio ?? '');

    final idOrden = await provider.guardar(auth.vendedor!.codigo);
    if (!mounted) return;

    if (idOrden != null) {
      provider.reset();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
            builder: (_) => OrdenPreparacionDetalleScreen(idOrden: idOrden)),
      );
    } else if (provider.errorMessage != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(provider.errorMessage!)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<OrdenPreparacionProvider>();
    final fmt = NumberFormat('#,##0.00', 'es_AR');

    if (_loadingEdit) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cargando orden...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return PopScope(
      canPop: !provider.hasItems || provider.pedidoId != null,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final ok = await _onWillPop();
        if (ok && mounted) nav.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing
              ? 'Editar Orden #${widget.editOrdenId}'
              : 'Nueva Orden de Preparación'),
          actions: [
            if (provider.hasItems)
              TextButton.icon(
                onPressed: provider.saving ? null : _guardar,
                icon: const Icon(Icons.save, color: Colors.white),
                label: const Text('GUARDAR', style: TextStyle(color: Colors.white)),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionHeader(icon: Icons.person, title: 'Cliente'),
            Card(
              child: ListTile(
                title: provider.cliente == null
                    ? const Text('Toca para seleccionar cliente',
                        style: TextStyle(color: Colors.grey))
                    : Text(provider.cliente!.nombre,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: provider.cliente != null
                    ? Text(
                        'Cód. ${provider.cliente!.codigo} · Lista ${provider.cliente!.nrolPrecios}')
                    : null,
                trailing: const Icon(Icons.chevron_right),
                onTap: _selectCliente,
              ),
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(
                    child: _SectionHeader(
                        icon: Icons.inventory_2, title: 'Productos')),
                TextButton.icon(
                  onPressed: _addProducto,
                  icon: const Icon(Icons.add),
                  label: const Text('Agregar'),
                ),
              ],
            ),
            if (provider.items.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(
                      child: Text('Sin productos. Tocá "Agregar".',
                          style: TextStyle(color: Colors.grey))),
                ),
              )
            else
              ...provider.items.asMap().entries.map((e) {
                final idx = e.key;
                final item = e.value;
                return _ItemCard(
                  item: item,
                  onRemove: () {
                    provider.removeItem(idx);
                    _tryAutoSave();
                  },
                  onEdit: () async {
                    final updated = await _editItem(item);
                    if (updated != null) {
                      provider.updateItem(idx, updated);
                      _tryAutoSave();
                    }
                  },
                );
              }),

            if (provider.hasItems) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'TOTAL: \$${fmt.format(provider.total)}',
                  style:
                      const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
            ],

            const SizedBox(height: 16),
            _SectionHeader(icon: Icons.build_circle_outlined, title: 'Tipo de servicio'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: DropdownButtonFormField<String?>(
                  decoration: const InputDecoration(
                    labelText: 'Tipo de servicio',
                    prefixIcon: Icon(Icons.assignment_outlined),
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedServicio,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Sin especificar',
                          style: TextStyle(color: Colors.grey)),
                    ),
                    ..._servicioOpciones.map(
                      (s) => DropdownMenuItem<String?>(
                          value: s, child: Text(s)),
                    ),
                  ],
                  onChanged: (v) => setState(() => _selectedServicio = v),
                ),
              ),
            ),

            const SizedBox(height: 16),
            _SectionHeader(icon: Icons.handshake, title: 'Entrega'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: TextField(
                  controller: _quienCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Quién recibió',
                    prefixIcon: Icon(Icons.person_outline),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),
            _SectionHeader(icon: Icons.draw, title: 'Firma del cliente'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Signature(
                    controller: _sigController,
                    height: 150,
                    backgroundColor: Colors.grey.shade100,
                  ),
                  const SizedBox(height: 8),
                  Row(children: [
                    Text(
                      _isEditing && provider.pedidoId != null
                          ? 'Firma aquí para reemplazar la existente'
                          : 'Firma aquí arriba',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _sigController.clear,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Limpiar'),
                    ),
                  ]),
                ]),
              ),
            ),

            const SizedBox(height: 24),
            if (provider.saving)
              const Center(child: CircularProgressIndicator())
            else
              ElevatedButton.icon(
                onPressed:
                    provider.hasItems && provider.cliente != null ? _guardar : null,
                icon: const Icon(Icons.save),
                label: Text(_isEditing ? 'ACTUALIZAR ORDEN' : 'GUARDAR ORDEN'),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Future<ItemPedido?> _editItem(ItemPedido item) async {
    return showModalBottomSheet<ItemPedido>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _EditItemSheet(item: item),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(title,
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: Theme.of(context).colorScheme.primary)),
      ]),
    );
  }
}

// ── Card de item ───────────────────────────────────────────────────────────────

class _ItemCard extends StatelessWidget {
  final ItemPedido item;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _ItemCard({required this.item, required this.onRemove, required this.onEdit});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00', 'es_AR');
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text(item.articulo.descripcion,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          'Cant: ${item.cantidad} · P: \$${fmt.format(item.precio)}'
          '${item.porDto > 0 ? ' · Dto: ${item.porDto}%' : ''}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('\$${fmt.format(item.importe)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: onEdit),
            IconButton(
                icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                onPressed: onRemove),
          ],
        ),
      ),
    );
  }
}

// ── Búsqueda de clientes ───────────────────────────────────────────────────────

class _ClienteSearchDelegate extends SearchDelegate<Cliente?> {
  final _repo = ClienteRepository();

  _ClienteSearchDelegate() : super(searchFieldLabel: 'Buscar cliente...');

  @override
  List<Widget> buildActions(BuildContext ctx) =>
      [IconButton(icon: const Icon(Icons.clear), onPressed: () => query = '')];

  @override
  Widget buildLeading(BuildContext ctx) =>
      IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => close(ctx, null));

  @override
  Widget buildResults(BuildContext ctx) => _buildList(ctx);

  @override
  Widget buildSuggestions(BuildContext ctx) => _buildList(ctx);

  Widget _buildList(BuildContext ctx) {
    return FutureBuilder<List<Cliente>>(
      future: _repo.search(query),
      builder: (_, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
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

// ── Sheet para agregar producto ────────────────────────────────────────────────

class _AddProductoSheet extends StatefulWidget {
  final int nrolPrecios;

  const _AddProductoSheet({required this.nrolPrecios});

  @override
  State<_AddProductoSheet> createState() => _AddProductoSheetState();
}

class _AddProductoSheetState extends State<_AddProductoSheet> {
  final _artRepo = ArticuloRepository();
  final _depRepo = DepositoRepository();
  final _searchCtrl = TextEditingController();
  final _cantCtrl = TextEditingController(text: '1');
  final _precioCtrl = TextEditingController();
  final _dtoCtrl = TextEditingController(text: '0');
  final _comentCtrl = TextEditingController();

  List<Articulo> _articulos = [];
  List<Deposito> _depositos = [];
  Articulo? _selected;
  int? _depositoSeleccionado;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadArticulos('');
    _searchCtrl.addListener(() => _loadArticulos(_searchCtrl.text));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cantCtrl.dispose();
    _precioCtrl.dispose();
    _dtoCtrl.dispose();
    _comentCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadArticulos(String q) async {
    final results = await _artRepo.search(q);
    if (mounted) setState(() => _articulos = results);
  }

  Future<void> _selectArticulo(Articulo art) async {
    final depositos = await _depRepo.getByArticulo(art.codigo);
    setState(() {
      _selected = art;
      _depositos = depositos;
      _depositoSeleccionado = depositos.isNotEmpty ? depositos.first.codigo : null;
      _precioCtrl.text = art.precioParaLista(widget.nrolPrecios).toStringAsFixed(2);
    });
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
      _selectArticulo(art);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se encontró producto con barcode: $code')),
      );
    }
  }

  void _confirm() {
    if (_selected == null) return;
    final cantidad = double.tryParse(_cantCtrl.text.replaceAll(',', '.')) ?? 0;
    final precio = double.tryParse(_precioCtrl.text.replaceAll(',', '.')) ?? 0;
    final dto = double.tryParse(_dtoCtrl.text.replaceAll(',', '.')) ?? 0;
    if (cantidad <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('La cantidad debe ser mayor a 0.')));
      return;
    }
    context.read<OrdenPreparacionProvider>().addItem(ItemPedido(
          articulo: _selected!,
          cantidad: cantidad,
          precio: precio,
          porDto: dto,
          comentario: _comentCtrl.text.trim(),
          deposito: _depositoSeleccionado,
        ));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            AppBar(
              title: const Text('Escanear producto'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _scanning = false),
              ),
            ),
            Expanded(
              child: MobileScanner(
                onDetect: _onBarcodeDetected,
              ),
            ),
          ],
        ),
      );
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (_, scrollCtrl) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: ListView(
          controller: scrollCtrl,
          children: [
            Row(children: [
              const Text('Agregar producto',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Escanear barcode',
                onPressed: _scanBarcode,
              ),
            ]),
            const SizedBox(height: 8),

            if (_selected == null) ...[
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: 'Buscar producto...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 800,
                child: _articulos.isEmpty
                    ? const Center(child: Text('Sin resultados'))
                    : ListView.builder(
                        itemCount: _articulos.length,
                        itemBuilder: (_, i) {
                          final art = _articulos[i];
                          return ListTile(
                            dense: true,
                            title: Text(art.descripcion),
                            subtitle: Text(
                              '${art.sku.isNotEmpty ? 'SKU: ${art.sku} · ' : ''}'
                              'Stock: ${art.stockActual}',
                              style: TextStyle(
                                color: art.stockActual <= 0
                                    ? Colors.red.shade700
                                    : null,
                              ),
                            ),
                            trailing: Text('\$${art.prevtaPub1.toStringAsFixed(2)}'),
                            onTap: () => _selectArticulo(art),
                          );
                        },
                      ),
              ),
            ] else ...[
              ListTile(
                tileColor: Colors.blue.shade50,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                title: Text(_selected!.descripcion,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  'Cód. ${_selected!.codigo}'
                  '${_selected!.sku.isNotEmpty ? ' · SKU: ${_selected!.sku}' : ''}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _selected = null;
                    _depositos = [];
                  }),
                ),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _cantCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Cantidad', border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _precioCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Precio',
                        prefixText: '\$',
                        border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _dtoCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Dto %',
                        suffixText: '%',
                        border: OutlineInputBorder()),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
                  ),
                ),
              ]),
              if (_depositos.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                      labelText: 'Depósito', border: OutlineInputBorder()),
                  value: _depositoSeleccionado,
                  items: _depositos
                      .map((d) => DropdownMenuItem(
                            value: d.codigo,
                            child: Text(
                                '${d.descripcion} (${d.stock.toStringAsFixed(0)})'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _depositoSeleccionado = v),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _comentCtrl,
                decoration: const InputDecoration(
                    labelText: 'Comentario (opcional)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('Agregar a la orden'),
              ),
              const SizedBox(height: 16),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Sheet para editar item ─────────────────────────────────────────────────────

class _EditItemSheet extends StatefulWidget {
  final ItemPedido item;

  const _EditItemSheet({required this.item});

  @override
  State<_EditItemSheet> createState() => _EditItemSheetState();
}

class _EditItemSheetState extends State<_EditItemSheet> {
  late final TextEditingController _cantCtrl;
  late final TextEditingController _precioCtrl;
  late final TextEditingController _dtoCtrl;
  late final TextEditingController _comentCtrl;

  @override
  void initState() {
    super.initState();
    _cantCtrl = TextEditingController(text: widget.item.cantidad.toStringAsFixed(2));
    _precioCtrl = TextEditingController(text: widget.item.precio.toStringAsFixed(2));
    _dtoCtrl = TextEditingController(text: widget.item.porDto.toStringAsFixed(2));
    _comentCtrl = TextEditingController(text: widget.item.comentario);
  }

  @override
  void dispose() {
    _cantCtrl.dispose();
    _precioCtrl.dispose();
    _dtoCtrl.dispose();
    _comentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.item.articulo.descripcion,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: TextField(
              controller: _cantCtrl,
              decoration: const InputDecoration(
                  labelText: 'Cantidad', border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            )),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
              controller: _precioCtrl,
              decoration: const InputDecoration(
                  labelText: 'Precio',
                  prefixText: '\$',
                  border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            )),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
              controller: _dtoCtrl,
              decoration: const InputDecoration(
                  labelText: 'Dto %',
                  suffixText: '%',
                  border: OutlineInputBorder()),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]'))],
            )),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _comentCtrl,
            decoration: const InputDecoration(
                labelText: 'Comentario', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              final c = double.tryParse(_cantCtrl.text.replaceAll(',', '.')) ??
                  widget.item.cantidad;
              final p = double.tryParse(_precioCtrl.text.replaceAll(',', '.')) ??
                  widget.item.precio;
              final d = double.tryParse(_dtoCtrl.text.replaceAll(',', '.')) ??
                  widget.item.porDto;
              Navigator.pop(
                context,
                ItemPedido(
                  articulo: widget.item.articulo,
                  cantidad: c,
                  precio: p,
                  porDto: d,
                  comentario: _comentCtrl.text.trim(),
                  deposito: widget.item.deposito,
                ),
              );
            },
            child: const Text('Actualizar'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
