// Persistiert pro GERAET welche Cloud-Bilder in welchem Slot drauf sind.
// Schluessel ist die BLE-Adresse des Masters (stabil + eindeutig). Frueher war es
// die PAIR_ID - die ist seit dem identischen Flashen aller Master bei allen gleich
// und haette dazu gefuehrt, dass sich alle Augenpaare dieselben Eintraege teilen.
// Layout im SharedPreferences:
//   slot_<device_id>_<slot>_url   -> String (download_url, volles Bild)
//   slot_<device_id>_<slot>_thumb -> String (Vorschaubild, ~5 KB) - kann fehlen
//   slot_<device_id>_<slot>_name  -> String (Anzeigename)

import 'package:shared_preferences/shared_preferences.dart';
import 'ble_service.dart';  // kCloudSlotCount

class SlotMeta {
  final String name;
  /// Volles Bild (~1,5 MB). Bleibt gespeichert, weil daran erkannt wird, welche
  /// Cloud-Augen bereits installiert sind (siehe getInstalledUrls).
  final String url;
  /// Kleines Vorschaubild (~5 KB) fuer die Kacheln im Augen-Raster.
  ///
  /// Leer bei Eintraegen aus aelteren App-Versionen - dann faellt die Anzeige auf
  /// das volle Bild zurueck. Ohne diesen Weg lud das Augen-Raster bei vier belegten
  /// Slots rund 6 MB, nur um vier 56 dp grosse Kacheln zu zeichnen. Genau dieses
  /// Muster hat GitHub schon einmal zum Drosseln gebracht.
  final String thumbUrl;
  SlotMeta(this.name, this.url, this.thumbUrl);

  /// Was fuer die Kachel geladen werden soll.
  String get tileUrl => thumbUrl.isNotEmpty ? thumbUrl : url;
}

class SlotMetadataStore {
  static String _keyUrl(String dev, int slot)   => 'slot_${dev}_${slot}_url';
  static String _keyThumb(String dev, int slot) => 'slot_${dev}_${slot}_thumb';
  static String _keyName(String dev, int slot)  => 'slot_${dev}_${slot}_name';

  static Future<SlotMeta?> get(String deviceId, int slot) async {
    final sp = await SharedPreferences.getInstance();
    final url = sp.getString(_keyUrl(deviceId, slot));
    if (url == null || url.isEmpty) return null;
    final name  = sp.getString(_keyName(deviceId, slot)) ?? '?';
    final thumb = sp.getString(_keyThumb(deviceId, slot)) ?? '';
    return SlotMeta(name, url, thumb);
  }

  static Future<void> set(String deviceId, int slot, String name, String url,
                          String thumbUrl) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_keyUrl(deviceId, slot), url);
    await sp.setString(_keyThumb(deviceId, slot), thumbUrl);
    await sp.setString(_keyName(deviceId, slot), name);
  }

  static Future<void> clear(String deviceId, int slot) async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_keyUrl(deviceId, slot));
    await sp.remove(_keyThumb(deviceId, slot));
    await sp.remove(_keyName(deviceId, slot));
  }

  /// Set aller URLs die auf diesem Geraet derzeit in irgendeinem Slot installiert sind.
  /// Wird vom Cloud-Tab benutzt um bereits installierte Bilder auszublenden.
  static Future<Set<String>> getInstalledUrls(String deviceId) async {
    final sp = await SharedPreferences.getInstance();
    final urls = <String>{};
    for (int s = 0; s < kCloudSlotCount; s++) {
      final url = sp.getString(_keyUrl(deviceId, s));
      if (url != null && url.isNotEmpty) urls.add(url);
    }
    return urls;
  }
}
