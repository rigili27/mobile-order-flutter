// Copiado idéntico en firma-digital, mobile-order-flutter y
// kiosko-pos-flutter (lib/core/update/): un cambio acá va en las tres apps.

import 'package:flutter/material.dart';

import 'update_controller.dart';

/// Envuelve toda la app (desde `MaterialApp.builder`): muestra el aviso de
/// versión nueva arriba de cualquier pantalla y, si la versión instalada
/// quedó por debajo de la mínima, la pantalla de actualización obligatoria.
///
/// [navigatorKey] es el del MaterialApp: este widget queda por encima del
/// Navigator, así que los diálogos se abren con su contexto.
/// [watch] suma otros Listenable que cambian `isBusy`/`canEnforceMandatory`
/// (ej. el provider del turno o de la sesión de firma), para redibujar.
class UpdateGate extends StatelessWidget {
  const UpdateGate({
    super.key,
    required this.controller,
    required this.navigatorKey,
    required this.child,
    this.watch = const [],
    this.hideBannerWhileBusy = false,
  });

  final UpdateController controller;
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final List<Listenable> watch;

  /// true donde el aviso molestaría a quien usa la pantalla (ej. la tablet
  /// de firma mientras el cliente firma).
  final bool hideBannerWhileBusy;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, ...watch]),
      builder: (context, _) {
        if (controller.mustUpdate) {
          return MandatoryUpdateScreen(controller: controller);
        }

        final showBanner = controller.showBanner && !(hideBannerWhileBusy && controller.busy);

        return Column(
          children: [
            if (showBanner) UpdateBanner(controller: controller, navigatorKey: navigatorKey),
            Expanded(child: child),
          ],
        );
      },
    );
  }
}

class UpdateBanner extends StatelessWidget {
  const UpdateBanner({super.key, required this.controller, required this.navigatorKey});

  final UpdateController controller;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = controller.latest!;
    final busy = controller.busy;
    final hasNotes = (latest.notes ?? '').trim().isNotEmpty;

    return Material(
      color: scheme.primaryContainer,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              Icon(Icons.system_update, color: scheme.onPrimaryContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nueva versión ${latest.version} disponible',
                      style: TextStyle(fontWeight: FontWeight.w600, color: scheme.onPrimaryContainer),
                    ),
                    if (busy)
                      Text(
                        controller.busyReason ?? 'Podés actualizar cuando termines lo que estás haciendo.',
                        style: TextStyle(fontSize: 12, color: scheme.onPrimaryContainer),
                      ),
                  ],
                ),
              ),
              if (hasNotes)
                TextButton(
                  onPressed: () => showUpdateNotes(navigatorKey.currentContext!, controller),
                  child: const Text('Novedades'),
                ),
              TextButton(onPressed: controller.dismiss, child: const Text('Más tarde')),
              const SizedBox(width: 4),
              FilledButton(
                onPressed: busy || controller.working ? null : () => runUpdate(navigatorKey.currentContext!, controller),
                child: const Text('Actualizar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MandatoryUpdateScreen extends StatelessWidget {
  const MandatoryUpdateScreen({super.key, required this.controller});

  final UpdateController controller;

  @override
  Widget build(BuildContext context) {
    final latest = controller.latest!;
    final working = controller.working;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.system_update, size: 56),
                  const SizedBox(height: 16),
                  Text('Hay que actualizar la app', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text(
                    'Esta versión (${controller.installedVersion ?? '?'}) ya no funciona con el sistema. '
                    'Instalá la versión ${latest.version} para seguir.',
                    textAlign: TextAlign.center,
                  ),
                  if ((latest.notes ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(latest.notes!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
                  ],
                  if (controller.pendingWarning != null) ...[
                    const SizedBox(height: 16),
                    Text(controller.pendingWarning!, textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 24),
                  if (working) ...[
                    LinearProgressIndicator(
                      value: controller.status == UpdateStatus.downloading && controller.progress > 0
                          ? controller.progress
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(controller.status == UpdateStatus.installing ? 'Abriendo el instalador…' : 'Descargando…'),
                  ] else
                    FilledButton.icon(
                      onPressed: controller.install,
                      icon: const Icon(Icons.download),
                      label: const Text('Actualizar ahora'),
                    ),
                  if (controller.status == UpdateStatus.error && controller.errorMessage != null) ...[
                    const SizedBox(height: 16),
                    Text(controller.errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showUpdateNotes(BuildContext context, UpdateController controller) async {
  final latest = controller.latest;
  if (latest == null) return;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Novedades de la versión ${latest.version}'),
      content: SingleChildScrollView(child: Text(latest.notes ?? '')),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cerrar')),
      ],
    ),
  );
}

/// Confirma (avisando si hay pendientes de sincronizar), descarga con barra
/// de progreso y abre el instalador. Los errores se muestran en un diálogo.
/// [context] tiene que estar debajo del Navigator.
Future<void> runUpdate(BuildContext context, UpdateController controller) async {
  final warning = controller.pendingWarning;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Actualizar a la versión ${controller.latest?.version ?? ''}'),
      content: Text(
        [
          'Se descarga la versión nueva y se abre el instalador. Los datos de la app se conservan.',
          if (warning != null) warning,
        ].join('\n\n'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Actualizar')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _UpdateProgressDialog(controller: controller),
  );

  if (controller.status == UpdateStatus.error && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('No se pudo actualizar'),
        content: Text(controller.errorMessage ?? 'Error desconocido.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cerrar')),
        ],
      ),
    );
    controller.clearError();
  }
}

/// Arranca la instalación al abrirse y se cierra sola cuando termina (bien o
/// con error), una sola vez aunque el diálogo se redibuje.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog({required this.controller});

  final UpdateController controller;

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget.controller.install().whenComplete(() {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    return PopScope(
      canPop: false,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, child) => AlertDialog(
          title: Text(controller.status == UpdateStatus.installing ? 'Abriendo el instalador…' : 'Descargando actualización…'),
          content: LinearProgressIndicator(
            value: controller.status == UpdateStatus.downloading && controller.progress > 0 ? controller.progress : null,
          ),
        ),
      ),
    );
  }
}
