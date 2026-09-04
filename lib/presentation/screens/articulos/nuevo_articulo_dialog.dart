import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/articulo.dart';
import '../../providers/api_sync_provider.dart';

/// Diálogo de alta de artículo provisorio (solo modo API). Crea el Product
/// real (inactivo) en el ERP y devuelve el `Articulo` local ya insertado, o
/// null si se canceló / falló.
Future<Articulo?> showNuevoArticuloDialog(
  BuildContext context, {
  String? descripcionInicial,
  String? barcodeInicial,
}) async {
  final descCtrl = TextEditingController(text: descripcionInicial ?? '');
  final precioCtrl = TextEditingController();
  final costoCtrl = TextEditingController();
  final barcodeCtrl = TextEditingController(text: barcodeInicial ?? '');

  final confirmar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Artículo nuevo'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'Descripción'),
              autofocus: true,
            ),
            TextField(
              controller: precioCtrl,
              decoration: const InputDecoration(labelText: 'Precio de venta'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: costoCtrl,
              decoration: const InputDecoration(labelText: 'Costo (opcional)'),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
            ),
            TextField(
              controller: barcodeCtrl,
              decoration:
                  const InputDecoration(labelText: 'Código de barra (opcional)'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Crear')),
      ],
    ),
  );

  if (confirmar != true || descCtrl.text.trim().isEmpty || !context.mounted) {
    return null;
  }

  final provider = context.read<ApiSyncProvider>();
  final art = await provider.crearArticulo(
    descripcion: descCtrl.text.trim(),
    codigoBarra:
        barcodeCtrl.text.trim().isEmpty ? null : barcodeCtrl.text.trim(),
    precio: double.tryParse(precioCtrl.text.trim().replaceAll(',', '.')),
    costo: double.tryParse(costoCtrl.text.trim().replaceAll(',', '.')),
  );

  if (art == null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(provider.errorMessage ?? 'No se pudo crear el artículo.'),
    ));
  }
  return art;
}
