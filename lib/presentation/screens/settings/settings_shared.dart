import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app.dart';
import '../../providers/auth_provider.dart';
import '../login/login_screen.dart';

/// Se llama siempre que la DB activa cambió (recibida por HTTP/FTP, borrada
/// o restaurada desde assets, o sincronizada en modo API). Corre el reinit
/// que necesite el caller (`onDatabaseReady`, p. ej. `DatabaseHelper.init()`
/// en `_AppRoot`) y SIEMPRE fuerza logout + navegación a Login, sin importar
/// qué usuario estaba logueado ni desde qué pantalla de Configuración se
/// llamó.
///
/// Usa `rootNavigatorKey` en vez de un `BuildContext` local: si
/// `onDatabaseReady` viene de `_AppRoot` (arranque sin DB), puede disparar un
/// rebuild que reemplaza la pantalla actual (por ejemplo por LoginScreen) y
/// desmonta su propio BuildContext a mitad de camino.
/// `rootNavigatorKey.currentContext` es el del Navigator raíz, que nunca se
/// desmonta mientras la app corre.
Future<void> onDbChanged(Future<void> Function()? onDatabaseReady) async {
  try {
    await onDatabaseReady?.call();
  } catch (_) {}
  try {
    await rootNavigatorKey.currentContext?.read<AuthProvider>().logout();
  } catch (_) {}
  rootNavigatorKey.currentState?.pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const LoginScreen()),
    (route) => false,
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}

/// Tile de navegación hacia una sub-pantalla de Configuración — para que el
/// menú principal se mantenga corto y cada sección pesada viva en su propia
/// pantalla.
class SettingsNavCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const SettingsNavCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}
