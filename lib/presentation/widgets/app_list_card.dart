import 'package:flutter/material.dart';

/// Card estándar para los ítems de listado de la app (clientes, artículos,
/// pedidos, cobranzas, stock, órdenes de compra) — para que todos los
/// listados se vean igual.
class AppListCard extends StatelessWidget {
  /// Texto corto para el avatar circular (ej. código). Se ignora si se pasa
  /// [leadingIcon].
  final String? leadingText;
  final IconData? leadingIcon;
  final Color? leadingColor;

  final String title;

  /// Subtítulo simple; se ignora si se pasa [subtitleWidget].
  final String? subtitle;
  final Widget? subtitleWidget;

  final Widget? trailing;

  /// Etiqueta chica arriba a la derecha del título (ej. "Pendiente").
  final String? badge;
  final Color? badgeColor;

  final VoidCallback? onTap;

  const AppListCard({
    super.key,
    this.leadingText,
    this.leadingIcon,
    this.leadingColor,
    required this.title,
    this.subtitle,
    this.subtitleWidget,
    this.trailing,
    this.badge,
    this.badgeColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final avatarColor = leadingColor ?? scheme.primaryContainer;

    Widget? leading;
    if (leadingIcon != null) {
      leading = CircleAvatar(
        backgroundColor: avatarColor.withValues(alpha: 0.18),
        child: Icon(leadingIcon, color: avatarColor, size: 20),
      );
    } else if (leadingText != null) {
      leading = CircleAvatar(
        backgroundColor: avatarColor,
        child: Text(
          leadingText!,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        leading: leading,
        title: Row(
          children: [
            Flexible(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            if (badge != null) ...[
              const SizedBox(width: 6),
              _Badge(text: badge!, color: badgeColor ?? Colors.orange),
            ],
          ],
        ),
        subtitle: subtitleWidget ??
            (subtitle != null
                ? Text(subtitle!, style: const TextStyle(fontSize: 12))
                : null),
        trailing: trailing,
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
