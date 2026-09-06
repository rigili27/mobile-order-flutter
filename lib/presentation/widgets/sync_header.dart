import 'package:flutter/material.dart';

/// Fila reutilizable "Última sincronización: hace X" + botón para sincronizar
/// ahora. Se usa en las pantallas que consultan datos on-demand del ERP
/// (cuenta corriente, artículos, pedidos).
class SyncHeader extends StatelessWidget {
  final DateTime? lastSync;
  final bool syncing;
  final Future<void> Function() onSync;
  final String? label;

  const SyncHeader({
    super.key,
    required this.lastSync,
    required this.syncing,
    required this.onSync,
    this.label,
  });

  static String formatoRelativo(DateTime? t) {
    if (t == null) return 'nunca';
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'recién';
    if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
    if (d.inHours < 24) return 'hace ${d.inHours} h';
    return 'hace ${d.inDays} d';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Icon(Icons.sync, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${label ?? 'Última sincronización'}: ${formatoRelativo(lastSync)}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
          if (syncing)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Sincronizar ahora',
              onPressed: () => onSync(),
            ),
        ],
      ),
    );
  }
}
