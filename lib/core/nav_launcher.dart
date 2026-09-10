import 'package:url_launcher/url_launcher.dart';

/// Abre la app de mapas del celular (Google Maps / Waze / la que haya) para
/// el ruteo giro a giro hasta una coordenada. Todo gratis: usa las apps
/// instaladas, sin API key.
Future<bool> abrirNavegacion(double lat, double lng, {String? etiqueta}) async {
  final label = etiqueta != null ? Uri.encodeComponent(etiqueta) : null;

  final candidatos = <Uri>[
    // Android: arranca la navegación directamente en Google Maps.
    Uri.parse('google.navigation:q=$lat,$lng'),
    // Genérico Android/iOS: abre el punto en la app de mapas por defecto.
    Uri.parse('geo:$lat,$lng?q=$lat,$lng${label != null ? '($label)' : ''}'),
    // Fallback web (siempre funciona si hay navegador).
    Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng'),
  ];

  for (final uri in candidatos) {
    try {
      if (await canLaunchUrl(uri)) {
        return launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {
      // probamos el siguiente
    }
  }
  return false;
}
