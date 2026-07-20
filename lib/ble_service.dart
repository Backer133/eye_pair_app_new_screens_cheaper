import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'image_pipeline.dart' show kRgb565ByteCount;

// UUIDs MUESSEN identisch zu denen im Master.ino sein!
class EyeUuids {
  static final Guid svcEyeCtrl   = Guid("6E400001-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrEyeId     = Guid("6E400002-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrBrightness= Guid("6E400003-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrAnimEn    = Guid("6E400004-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrEyeCount  = Guid("6E400006-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrEyeUpload    = Guid("6E400007-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrUploadStat   = Guid("6E400008-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrSlaveReceipt = Guid("6E400009-B5A3-F393-E0A9-E50E24DCCA9E");
  static final Guid chrSlotStatus   = Guid("6E40000A-B5A3-F393-E0A9-E50E24DCCA9E");
  // Zugangsschutz (BLE-Sicherheit)
  static final Guid chrAuth         = Guid("6E40000B-B5A3-F393-E0A9-E50E24DCCA9E");  // WRITE uint32: 6-stelliger Code
  static final Guid chrSetKey       = Guid("6E40000C-B5A3-F393-E0A9-E50E24DCCA9E");  // WRITE uint32: neuen Geraete-Key
  static final Guid chrAuthStatus   = Guid("6E40000D-B5A3-F393-E0A9-E50E24DCCA9E");  // READ/NOTIFY: 1=autorisiert
  static final Guid chrDeviceName   = Guid("6E40000E-B5A3-F393-E0A9-E50E24DCCA9E");  // READ/WRITE: Anzeigename

  static final Guid svcDiag      = Guid("6E400010-B5A3-F393-E0A9-E50E24DCCA9E");
  // Kabel-Status: 1 = zweiter Screen (Slave) haengt am Kabel, 0 = nicht verbunden.
  static final Guid chrSlaveLink = Guid("6E400016-B5A3-F393-E0A9-E50E24DCCA9E");
}

const int kHardcodedEyeCount = 4;   // A7, A10, A12, A13 (in dieser Reihenfolge!)
const int kCloudSlotCount    = 5;   // 5 Slots in LittleFS auf ESP

// Werks-Standard-Zugangscode (muss zu DEFAULT_DEVICE_KEY in der Firmware passen).
// Referenzwert/Hinweis fuer den User - wird NICHT mehr automatisch gesendet: der Code
// muss bei jedem Verbinden manuell eingegeben werden (auch dieser Default).
const int kDefaultDeviceKey = 123456;

// Asset-Namen zu Eye-Index. MUSS in der Reihenfolge identisch zu EYE_IMAGES[]
// im Master.ino + Slave.ino sein! Nur hardcoded Augen (Index 0..3).
const List<String> kEyeAssets = [
  'assets/eyes/A7.png',
  'assets/eyes/A10.png',
  'assets/eyes/A12.png',
  'assets/eyes/A13.png',
];
const List<String> kEyeLabels = [
  'A7','A10','A12','A13'
];

class EyeBle extends ChangeNotifier {
  BluetoothDevice? device;
  final Map<Guid, BluetoothCharacteristic> _chars = {};

  // State exposed to UI
  int eyeId = 0;
  int brightness = 255;
  int animEnabled = 1;
  int eyeCount = 0;
  // Kabel-Status: haengt der zweite Screen (Slave) am Kabel? Kommt aus dem
  // Lebenszeichen, das der Slave ueber UART an den Master schickt.
  bool slaveLinked = false;
  bool connected = false;
  // Zugangsschutz: true = Verbindung ist autorisiert (Steuerung freigeschaltet).
  bool authorized = false;
  bool authSupported = false;  // false = alte Firmware ohne Auth-Charakteristik
  // Zaehlt hoch bei jedem fehlgeschlagenen Code-Versuch (fuer UI-Feedback).
  int authAttempts = 0;
  // Nur im RAM (nie in SharedPreferences): der in DIESER App-Sitzung erfolgreich
  // eingegebene Zugangscode. Damit laufen interne Reconnects (z.B. Cloud-Upload)
  // still weiter, ein frischer App-Start / manuelles Verbinden aber verlangt den
  // Code erneut. So reicht App-Besitz allein nicht fuer Zugriff.
  int? _sessionKey;
  StreamSubscription<List<int>>? _subAuthStatus;
  // Frei waehlbarer Anzeigename dieses Augenpaars (aus CHR_DEVICE_NAME).
  String deviceName = "";
  // Slave-Receipt nach Cloud-Eye-Upload
  int slaveReceiptSlot      = 0;
  int slaveUniqueReceived   = 0;
  int slaveTotalChunks      = 0;
  int slaveReRequestRound   = 0;
  StreamSubscription<List<int>>? _subSlaveReceipt;
  // Slot-Bitmap (Bit n = Slot n hat ein Bild auf dem Master in LittleFS).
  // Wird nur EINMAL beim Connect aus CHR_SLOT_STATUS gelesen (kein Notify mehr -
  // das hat den ESP-NOW-Forward gestoert). Reicht fuer "belegt"-Anzeige nach
  // App-Reinstall: SharedPreferences leer, aber Master kennt den Status noch.
  int slotOccupiedMask      = 0;

  StreamSubscription<List<int>>? _subEyeId;
  StreamSubscription<List<int>>? _subSlaveLink;
  StreamSubscription<BluetoothConnectionState>? _subConn;

  Future<void> connectAndDiscover(BluetoothDevice d) async {
    device = d;
    await d.connect(timeout: const Duration(seconds: 10), autoConnect: false);

    _subConn = d.connectionState.listen((s) {
      connected = (s == BluetoothConnectionState.connected);
      notifyListeners();
    });

    final services = await d.discoverServices();
    for (final s in services) {
      for (final c in s.characteristics) {
        _chars[c.uuid] = c;
      }
    }

    await _readAll();
    await _subscribeNotifies();
    await _authenticate();   // Zugangscode (Default 123456) automatisch senden

    connected = true;
    notifyListeners();
  }

  // ===== Zugangsschutz =====

  /// Stabiler, eindeutiger Schluessel pro Geraet (BLE-Adresse). Wird fuer lokal
  /// gespeicherte Daten benutzt (Zugangscode, Cloud-Slot-Metadaten).
  String get deviceId => device?.remoteId.str ?? 'unknown';

  /// true = Firmware verlangt Autorisierung, aber wir sind (noch) nicht
  /// autorisiert -> die App muss die Steuerung sperren (Zugangs-Gate zeigen).
  bool get locked => authSupported && !authorized;

  Future<void> _writeKey(BluetoothCharacteristic c, int key) async {
    final b = ByteData(4)..setUint32(0, key, Endian.little);
    await c.write(b.buffer.asUint8List(), withoutResponse: false);
  }

  // Beim Connect: Auth-Status abonnieren. Es wird KEIN gespeicherter Code mehr
  // automatisch gesendet -> ohne Session-Key bleibt die Verbindung gesperrt und die
  // App zeigt das LockGate (Code-Eingabe noetig, auch beim ersten Verbinden).
  // Nur wenn in dieser Sitzung bereits ein Code erfolgreich eingegeben wurde
  // (_sessionKey), wird er still gesendet - damit interne Reconnects (Cloud-Upload)
  // nicht erneut nach dem Code fragen.
  // Alte Firmware ohne CHR_AUTH -> authSupported=false, alles gilt als frei.
  Future<void> _authenticate() async {
    final c = _chars[EyeUuids.chrAuth];
    if (c == null) {
      authSupported = false;
      authorized = true;
      notifyListeners();
      return;
    }
    authSupported = true;
    final cs = _chars[EyeUuids.chrAuthStatus];
    if (cs != null) {
      try {
        await cs.setNotifyValue(true);
        _subAuthStatus = cs.lastValueStream.listen((v) {
          if (v.isNotEmpty) { authorized = v[0] == 1; notifyListeners(); }
        });
        final init = await cs.read();
        if (init.isNotEmpty) authorized = init[0] == 1;
      } catch (_) {}
    }
    if (_sessionKey != null) {
      await _writeKey(c, _sessionKey!);
      // Kurz auf die Autorisierungs-Antwort warten, damit das Gate beim stillen
      // Reconnect nicht aufblitzt.
      for (int i = 0; i < 16 && !authorized; i++) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
    }
  }

  /// Manuelle Code-Eingabe (falls der gespeicherte Code nicht passt, z.B. anderer
  /// Nutzer / Admin-Key). Sendet den Code, wartet auf die Autorisierungs-Antwort
  /// der Firmware und merkt sich den Code NUR bei Erfolg. Gibt true zurueck, wenn
  /// die Verbindung danach autorisiert ist.
  Future<bool> authenticateWith(int key) async {
    final c = _chars[EyeUuids.chrAuth];
    if (c == null) return false;
    await _writeKey(c, key);
    // Auf die CHR_AUTH_STATUS-Notify der Firmware warten (bis ~1s).
    for (int i = 0; i < 20 && !authorized; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (authorized) {
      _sessionKey = key;   // korrekter Code -> nur fuer diese Sitzung merken (RAM)
      return true;
    }
    authAttempts++;        // falscher Code -> UI-Feedback
    notifyListeners();
    return false;
  }

  /// Aendert den Geraete-Key (nur wenn autorisiert). Merkt sich den neuen Code nur
  /// fuer diese Sitzung, damit ein stiller Reconnect ihn nutzt - beim naechsten
  /// App-Start wird wieder danach gefragt.
  Future<bool> changeDeviceKey(int newKey) async {
    final c = _chars[EyeUuids.chrSetKey];
    if (c == null || newKey < 0 || newKey > 999999) return false;
    await _writeKey(c, newKey);
    _sessionKey = newKey;
    return true;
  }

  /// Setzt den frei waehlbaren Anzeigenamen des Augenpaars (nur wenn autorisiert).
  /// Der neue Name erscheint beim naechsten Scan in der Geraeteliste.
  Future<bool> setDeviceName(String name) async {
    final c = _chars[EyeUuids.chrDeviceName];
    final trimmed = name.trim();
    if (c == null || trimmed.isEmpty || trimmed.length > 23) return false;
    await c.write(trimmed.codeUnits, withoutResponse: false);
    deviceName = trimmed;
    notifyListeners();
    return true;
  }

  /// Reconnect zum gleichen Master nach Disconnect (z.B. nach Cloud-Upload).
  /// Wirft Exception wenn kein device bekannt oder Reconnect fehlschlaegt.
  Future<void> reconnect() async {
    if (device == null) throw Exception('Kein vorheriges Geraet bekannt');
    await connectAndDiscover(device!);
  }

  /// [forget]=true vergisst den Sitzungs-Code -> der naechste Connect verlangt wieder
  /// die PIN (fuer den vom Nutzer ausgeloesten Trennen-Button). Der interne
  /// Cloud-Upload-Ablauf ruft disconnect() ohne forget, damit sein automatischer
  /// Reconnect still bleibt.
  Future<void> disconnect({bool forget = false}) async {
    await _subEyeId?.cancel();
    await _subSlaveLink?.cancel();
    await _subSlaveReceipt?.cancel();
    await _subAuthStatus?.cancel();
    await _subConn?.cancel();
    _chars.clear();
    try { await device?.disconnect(); } catch (_) {}
    connected = false;
    authorized = false;
    authSupported = false;
    slaveLinked = false;
    if (forget) _sessionKey = null;
    notifyListeners();
  }

  Future<void> _readAll() async {
    final eid   = await _readByte(EyeUuids.chrEyeId);
    final br    = await _readByte(EyeUuids.chrBrightness);
    final anim  = await _readByte(EyeUuids.chrAnimEn);
    final cnt   = await _readByte(EyeUuids.chrEyeCount);
    final link  = await _readByte(EyeUuids.chrSlaveLink);

    if (eid != null)  eyeId      = eid;
    if (br != null)   brightness = br;
    if (anim != null) animEnabled = anim;
    if (cnt != null)  eyeCount   = cnt;
    if (link != null) slaveLinked = link == 1;
    final rcp = await _readBytes(EyeUuids.chrSlaveReceipt);
    if (rcp != null && rcp.length >= 6) {
      _parseReceipt(rcp);
    }
    final slotMask = await _readByte(EyeUuids.chrSlotStatus);
    if (slotMask != null) slotOccupiedMask = slotMask;
    final nm = await _readBytes(EyeUuids.chrDeviceName);
    if (nm != null && nm.isNotEmpty) deviceName = String.fromCharCodes(nm);
  }

  void _parseReceipt(List<int> v) {
    slaveReceiptSlot    = v[0];
    slaveUniqueReceived = v[1] | (v[2] << 8);
    slaveTotalChunks    = v[3] | (v[4] << 8);
    slaveReRequestRound = v[5];
  }

  Future<void> _subscribeNotifies() async {
    final ce = _chars[EyeUuids.chrEyeId];
    if (ce != null) {
      await ce.setNotifyValue(true);
      _subEyeId = ce.lastValueStream.listen((v) {
        if (v.isNotEmpty) { eyeId = v[0]; notifyListeners(); }
      });
    }
    // Kabel-Status live mitverfolgen (Master notifyt 1x/s).
    final cl = _chars[EyeUuids.chrSlaveLink];
    if (cl != null) {
      await cl.setNotifyValue(true);
      _subSlaveLink = cl.lastValueStream.listen((v) {
        if (v.isNotEmpty) { slaveLinked = v[0] == 1; notifyListeners(); }
      });
    }
    final crcp = _chars[EyeUuids.chrSlaveReceipt];
    if (crcp != null) {
      await crcp.setNotifyValue(true);
      _subSlaveReceipt = crcp.lastValueStream.listen((v) {
        if (v.length >= 6) { _parseReceipt(v); notifyListeners(); }
      });
    }
    // chrSlotStatus wird nur EINMAL via _readAll gelesen - kein Notify-Subscribe,
    // weil das beim ESP zu BLE-Coex-Druck waehrend Forward gefuehrt hat.
  }

  Future<int?> _readByte(Guid uuid) async {
    final c = _chars[uuid];
    if (c == null) return null;
    try {
      final v = await c.read();
      return v.isNotEmpty ? v[0] : null;
    } catch (e) { return null; }
  }

  Future<List<int>?> _readBytes(Guid uuid) async {
    final c = _chars[uuid];
    if (c == null) return null;
    try { return await c.read(); } catch (e) { return null; }
  }

  Future<void> setEyeId(int id) async {
    if (locked) return;   // Firmware ignoriert den Write ohnehin -> nicht optimistisch anzeigen
    final c = _chars[EyeUuids.chrEyeId]; if (c == null) return;
    await c.write([id], withoutResponse: false);
    eyeId = id; notifyListeners();
  }

  // setBrightness entfernt - Funktioniert auf ESP32-C3 mit Arduino Core 2.x nicht zuverlaessig.

  Future<void> setAnimEnabled(bool en) async {
    if (locked) return;
    final c = _chars[EyeUuids.chrAnimEn]; if (c == null) return;
    await c.write([en ? 1 : 0], withoutResponse: false);
    animEnabled = en ? 1 : 0; notifyListeners();
  }

  // setPairId entfernt - PAIR_ID ist read-only und wird nur im Sketch-Code geaendert.

  // === Cloud-Eye Upload via BLE Chunks ===
  // Protocol-Header (6 Byte): cmd, slot, idx_lo, idx_hi, total_lo, total_hi
  // Payload: max 238 Byte data
  // Master quittiert nicht jeden Chunk - wir nutzen WRITE-WITH-RESPONSE damit
  // die BLE-Stack-Bestaetigung Flow-Control macht.
  static const int _kChunkSize = 238;

  Future<bool> uploadEye(int slot, Uint8List rgb565data,
                          {void Function(int sent, int total)? onProgress}) async {
    if (locked) return false;
    final c = _chars[EyeUuids.chrEyeUpload];
    if (c == null) return false;
    if (slot < 0 || slot >= kCloudSlotCount) return false;
    if (rgb565data.length != kRgb565ByteCount) {
      throw Exception('rgb565data muss genau $kRgb565ByteCount Bytes haben (ist ${rgb565data.length})');
    }
    final total = (rgb565data.length + _kChunkSize - 1) ~/ _kChunkSize;
    for (int i = 0; i < total; i++) {
      final start = i * _kChunkSize;
      final end   = (start + _kChunkSize) > rgb565data.length
                    ? rgb565data.length
                    : (start + _kChunkSize);
      final payload = <int>[
        0x01, slot,
        i & 0xFF, (i >> 8) & 0xFF,
        total & 0xFF, (total >> 8) & 0xFF,
        ...rgb565data.sublist(start, end),
      ];
      await c.write(payload, withoutResponse: false);
      onProgress?.call(i + 1, total);
    }
    // Commit-Marker
    await c.write([0x02, slot, 0, 0, 0, 0], withoutResponse: false);
    // Mask lokal setzen - Master notifyt nicht (BLE-Coex), wir wollen aber die
    // Slot-Status-Anzeige aktuell halten ohne Reconnect.
    slotOccupiedMask |= (1 << slot);
    notifyListeners();
    return true;
  }

  /// Loescht den Cloud-Slot auf Master + Slave.
  Future<void> deleteEye(int slot) async {
    if (locked) return;
    final c = _chars[EyeUuids.chrEyeUpload];
    if (c == null) return;
    if (slot < 0 || slot >= kCloudSlotCount) return;
    await c.write([0x03, slot, 0, 0, 0, 0], withoutResponse: false);
    // Mask lokal nachfuehren - Master notifyt nicht (BLE-Coex), wir muessten sonst
    // bis zum naechsten Connect warten bis "belegt" verschwindet.
    slotOccupiedMask &= ~(1 << slot);
    notifyListeners();
  }

}
