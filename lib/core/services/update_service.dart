import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

// Cambiar por el nombre exacto del repo en GitHub
const _kGithubOwner = 'rigili27';
const _kGithubRepo = 'mobile-order-flutter';

class UpdateInfo {
  final String version;
  final String downloadUrl;
  final String changelog;

  const UpdateInfo({
    required this.version,
    required this.downloadUrl,
    required this.changelog,
  });
}

class UpdateService {
  UpdateService._();
  static final instance = UpdateService._();

  Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
    try {
      final response = await http
          .get(
            Uri.parse(
                'https://api.github.com/repos/$_kGithubOwner/$_kGithubRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github.v3+json'},
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final tagName =
          ((data['tag_name'] as String?) ?? '').replaceAll(RegExp(r'^v'), '');

      if (tagName.isEmpty || !_isNewer(tagName, currentVersion)) return null;

      final assets = (data['assets'] as List<dynamic>?) ?? [];
      final apkAsset = assets.cast<Map<String, dynamic>>().firstWhere(
            (a) => (a['name'] as String).endsWith('.apk'),
            orElse: () => {},
          );

      if (apkAsset.isEmpty) return null;

      return UpdateInfo(
        version: tagName,
        downloadUrl: apkAsset['browser_download_url'] as String,
        changelog: (data['body'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  Future<File> downloadApk(
    UpdateInfo info,
    void Function(double progress) onProgress,
  ) async {
    final tmpDir = await getTemporaryDirectory();
    final apkFile = File('${tmpDir.path}/updates/update.apk');
    await apkFile.parent.create(recursive: true);

    final request = http.Request('GET', Uri.parse(info.downloadUrl));
    final response = await request.send();
    final total = response.contentLength ?? 0;
    var received = 0;

    final sink = apkFile.openWrite();
    await for (final chunk in response.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    await sink.flush();
    await sink.close();

    return apkFile;
  }

  bool _isNewer(String remote, String current) {
    final r = _parseVersion(remote);
    final c = _parseVersion(current);
    for (var i = 0; i < r.length && i < c.length; i++) {
      if (r[i] > c[i]) return true;
      if (r[i] < c[i]) return false;
    }
    return r.length > c.length;
  }

  List<int> _parseVersion(String v) =>
      v.split('.').map((s) => int.tryParse(s.trim()) ?? 0).toList();
}
