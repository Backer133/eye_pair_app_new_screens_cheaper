// GitHub-API Client fuer cloud-eyes/ Ordner.
// Manueller Workflow: PNG ins Repo pushen, App listet via GitHub Contents API.

import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class CloudEye {
  final String name;        // Dateiname ohne Extension, z.B. "Maus"
  final String fileName;    // Originaler Dateiname inkl. Extension
  final String downloadUrl; // raw.githubusercontent.com URL
  final int    sizeBytes;
  CloudEye({
    required this.name,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeBytes,
  });
}

class GithubCloudEyes {
  // Neues, vom alten eye-pair-app abgeschottetes Repo (oeffentlich, damit die App
  // die Augen ohne Login ueber die GitHub-API laden kann).
  static const String repo = 'Backer133/eye_pair_app_new_screens_cheaper';
  static const String path = 'cloud-eyes';
  static const String branch = 'main';

  /// Liest Ordner-Inhalt via GitHub Contents API.
  /// Filtert auf .png/.jpg/.jpeg Dateien.
  Future<List<CloudEye>> list() async {
    final url = Uri.parse('https://api.github.com/repos/$repo/contents/$path?ref=$branch');
    final r = await http.get(url, headers: {
      'Accept': 'application/vnd.github.v3+json',
    });
    if (r.statusCode != 200) {
      throw Exception('GitHub API ${r.statusCode}: ${r.body}');
    }
    final List<dynamic> items = json.decode(r.body);
    final eyes = <CloudEye>[];
    for (final it in items) {
      final n = it['name'] as String;
      final lower = n.toLowerCase();
      if (!lower.endsWith('.png') && !lower.endsWith('.jpg') && !lower.endsWith('.jpeg')) continue;
      eyes.add(CloudEye(
        name: n.split('.').first,
        fileName: n,
        downloadUrl: it['download_url'] as String,
        sizeBytes: it['size'] as int,
      ));
    }
    eyes.sort((a, b) => a.name.compareTo(b.name));
    return eyes;
  }

  /// Laedt das PNG/JPG als Bytes runter.
  Future<Uint8List> download(CloudEye e) async {
    final r = await http.get(Uri.parse(e.downloadUrl));
    if (r.statusCode != 200) {
      throw Exception('Download fehlgeschlagen: ${r.statusCode}');
    }
    return r.bodyBytes;
  }
}
