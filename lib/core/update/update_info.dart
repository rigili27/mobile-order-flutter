// Copiado idéntico en firma-digital, mobile-order-flutter y
// kiosko-pos-flutter (lib/core/update/): un cambio acá va en las tres apps.

/// Respuesta de `GET <ERP>/api/apps/{app}/latest` (landlord del ERP).
class UpdateInfo {
  const UpdateInfo({
    required this.channel,
    required this.latest,
    required this.updateAvailable,
    required this.mandatory,
  });

  final String channel;

  /// null si no hay ninguna versión publicada para esta app y plataforma.
  final ReleaseInfo? latest;
  final bool updateAvailable;

  /// La versión instalada está por debajo de la mínima que exige el ERP.
  final bool mandatory;

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = json['latest'];
    return UpdateInfo(
      channel: json['channel'] as String? ?? 'stable',
      latest: latest is Map<String, dynamic> ? ReleaseInfo.fromJson(latest) : null,
      updateAvailable: json['update_available'] == true,
      mandatory: json['mandatory'] == true,
    );
  }
}

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.notes,
    required this.minSupportedVersion,
    required this.download,
  });

  final String version;
  final String? notes;
  final String? minSupportedVersion;
  final ReleaseDownload download;

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) => ReleaseInfo(
        version: json['version'] as String,
        notes: json['notes'] as String?,
        minSupportedVersion: json['min_supported_version'] as String?,
        download: ReleaseDownload.fromJson(json['download'] as Map<String, dynamic>),
      );
}

class ReleaseDownload {
  const ReleaseDownload({
    required this.url,
    required this.filename,
    required this.sha256,
    required this.size,
  });

  /// Link firmado del ERP, válido unos minutos: pedirlo de nuevo si vence.
  final String url;
  final String filename;
  final String sha256;
  final int size;

  factory ReleaseDownload.fromJson(Map<String, dynamic> json) => ReleaseDownload(
        url: json['url'] as String,
        filename: json['filename'] as String,
        sha256: (json['sha256'] as String).toLowerCase(),
        size: (json['size'] as num).toInt(),
      );
}
