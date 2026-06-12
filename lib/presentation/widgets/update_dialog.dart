import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/update_provider.dart';

class UpdateDialog extends StatelessWidget {
  const UpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<UpdateProvider>(
      builder: (context, upd, _) {
        final info = upd.updateInfo;
        if (info == null) return const SizedBox.shrink();

        final isDownloading = upd.state == UpdateState.downloading;

        return AlertDialog(
          title: const Text('Actualización disponible'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Nueva versión: ${info.version}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              if (info.changelog.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Novedades:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 150),
                  child: SingleChildScrollView(
                    child: Text(
                      info.changelog,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
              if (isDownloading) ...[
                const SizedBox(height: 16),
                Text(
                  'Descargando... ${(upd.downloadProgress * 100).toStringAsFixed(0)}%',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: upd.downloadProgress),
              ],
              if (upd.state == UpdateState.error &&
                  upd.errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(
                  upd.errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  isDownloading ? null : () => Navigator.pop(context),
              child: const Text('Ahora no'),
            ),
            ElevatedButton(
              onPressed: isDownloading
                  ? null
                  : () =>
                      context.read<UpdateProvider>().downloadAndInstall(),
              child: const Text('Actualizar'),
            ),
          ],
        );
      },
    );
  }
}
