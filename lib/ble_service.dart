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
  // Paar-Kopplung. 6E400010 ist bereits svcDiag -> kollisionsfreier Block ab 0012.
  static final Guid chrPairCtrl     = Guid("6E400012-B5A3-F393-E0A9-E50E24DCCA9E");  // WRITE: Kommando (+MAC)
  static final Guid chrPairFound    = Guid("6E400013-B5A3-F393-E0A9-E50E24DCCA9E");  // READ/NOTIFY: ein Fund
  static final Guid chrPairState    = Guid("6E400014-B5A3-F393-E0A9-E50E24DCCA9E");  // READ/NOTIFY: Zustand

  static final Guid svcDiag      = Guid("6E400010-B5A3-F393-E0A9-E50E24DCCA9E");
  // Funk-Status: 1 = zweiter Screen (Slave) per ESP-NOW verbunden, 0 = nicht.
  static final Guid chrSlaveLink = Guid("6E400016-B5A3-F393-E0A9-E50E24DCCA9E");
  // ESP-NOW-Verbindungsqualitaet: [0]=state, [1..2]=silence_ms (LE), [3]=loss_pct.
  static final Guid chrLinkDiag  = Guid("6E400017-B5A3-F393-E0A9-E50E24DCCA9E");
}

const int kHardcodedEyeCount = 4;   // A7, A10, A12, A13 (in dieser Reihenfolge!)
const int kCloudSlotCount    = 5;   // 5 Slots in LittleFS auf ESP

// Werks-Standard-Zugangscode (muss zu DEFAULT_DEVICE_KEY in der Firmware passen).
// Referenzwert/Hinweis fuer den User - wird NICHT mehr automatisch gesendet: der Code
// muss bei jedem Verbinden manuell eingegeben werden (auch dieser Default).
const int kDefaultDeviceKey = 123456;

// Der Admin-Code steht BEWUSST NICHT in der App: dieses Repo ist oeffentlich, und
// ein veroeffentlichter Admin-Code waere der Generalschluessel fuer alle Augen.
// Ob die aktuelle Sitzung Admin-Rechte hat, meldet die Firmware ueber
// CHR_AUTH_STATUS (0 = gesperrt, 1 = Geraete-Code, 2 = Admin).

/// Ein vom Master gefundener koppelbarer Slave (aus CHR_PAIR_FOUND).
class FoundSlave {
  final List<int> mac;      // 6 Bytes
  final int rssi;           // dBm, negativ
  final bool alreadyBound;  // gebunden - egal an wen
  final bool boundToOther;  // gebunden an einen ANDEREN Master als diesen
  const FoundSlave(this.mac, this.rssi, this.alreadyBound, this.boundToOther);

  /// Gehoert zu genau dem Master, mit dem die App gerade verbunden ist.
  bool get boundToThisMaster => alreadyBound && !boundToOther;
  /// Frei zum Koppeln.
  bool get free => !alreadyBound;

  String get macStr =>
      mac.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');
  /// Letzte zwei Bytes, z.B. "FD:D8" - kurz genug fuer die Liste.
  String get shortId => macStr.substring(12);
}

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
  // Funk-Status: haengt der zweite Screen (Slave) per ESP-NOW dran? Kommt aus dem
  // Pair-State, den der Master ueber CHR_SLAVE_LINK meldet.
  bool slaveLinked = false;
  // ESP-NOW-Funk-Diagnose (aus CHR_LINK_DIAG): Zustand + Qualitaet der Verbindung.
  int linkState = 0;    // PairState: 4=LINKED 5=DEGRADED 6=LOST (siehe linkStateName)
  int silenceMs = 0;    // ms seit letztem Signal vom Slave
  int lossPct   = 0;    // Master->Slave Unicast-Verlustrate in %
  // WLAN-Kanal des Masters und der zuletzt vom Slave gemeldete Kanal (0 = unbekannt).
  // Bei bestehender Verbindung sind beide zwangslaeufig gleich - ESP-NOW funktioniert
  // nur so. Auseinanderlaufende Werte heissen: der Slave sucht noch.
  int masterChannel = 0;
  int slaveChannel  = 0;
  StreamSubscription<List<int>>? _subLinkDiag;
  bool connected = false;
  // Zugangsschutz: true = Verbindung ist autorisiert (Steuerung freigeschaltet).
  bool authorized = false;
  /// Vom Master gemeldetes Auth-Level: 0 = gesperrt, 1 = Geraete-Code, 2 = Admin.
  int authLevel = 0;
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
  // --- Paar-Kopplung ---
  final List<FoundSlave> pairingFound = [];
  int pairingState = 0;   // 0 idle, 1 scannend, 2 bindend, 3 entkoppelnd, 4 Fehler
  int pairingError = 0;   // siehe pairingErrorText
  List<int> boundMac = const [0, 0, 0, 0, 0, 0];
  int boundPairId = 0;
  /// true, wenn in dieser Sitzung mit dem Admin-Code autorisiert wurde.
  bool isAdmin = false;
  StreamSubscription<List<int>>? _subPairFound;
  StreamSubscription<List<int>>? _subPairState;

  bool get isBound => boundMac.any((b) => b != 0);

  String get boundMacStr =>
      boundMac.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

  String get pairingErrorText {
    switch (pairingError) {
      case 1: return 'Der Slave hat die Kopplung nicht bestaetigt';
      case 2: return 'Der Slave gehoert schon zu einem anderen Master';
      case 3: return 'Dafuer wird der Admin-Code gebraucht';
      case 4: return 'Slave nicht gefunden';
      case 5: return 'Eigene Kopplung geloest, aber der Slave hat sich nicht '
                     'gemeldet - er haelt sich weiter fuer gebunden. Mit dem '
                     'Admin-Code zwangsloesen.';
      default: return '';
    }
  }

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

  /// Klartext des ESP-NOW-Verbindungszustands (PairState aus der Firmware).
  ///
  /// Ohne Kopplung steht die Firmware bewusst in PS_LOST (die Discovery-Maschinerie
  /// ist stillgelegt). "Verloren" laese sich dort als Stoerung, obwohl schlicht noch
  /// kein Partner gebunden ist - deshalb der eigene Text.
  String get linkStateName {
    if (!isBound) return 'Nicht gekoppelt';
    switch (linkState) {
      case 4: return 'Verbunden';
      case 5: return 'Instabil';
      case 6: return 'Verloren';
      case 3: return 'Koppeln...';
      case 2: return 'Suche...';
      case 1: return 'Reconnect...';
      default: return 'Startet...';
    }
  }

  /// CHR_AUTH_STATUS liefert das Auth-Level: 0 = gesperrt, 1 = Geraete-Code,
  /// 2 = Admin-Code. Aeltere Firmware kennt nur 0/1 - deshalb ">= 1" statt "== 1".
  void _parseAuthLevel(int level) {
    authLevel  = level;
    authorized = level >= 1;
    isAdmin    = level >= 2;
  }

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
          if (v.isNotEmpty) { _parseAuthLevel(v[0]); notifyListeners(); }
        });
        final init = await cs.read();
        if (init.isNotEmpty) _parseAuthLevel(init[0]);
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
    // Auf die AENDERUNG des Levels warten, nicht auf "authorized". Sonst laeuft
    // ein Wechsel vom Geraete- auf den Admin-Code sofort durch, ohne dass die
    // Antwort der Firmware da ist - isAdmin waere dann noch nicht gesetzt.
    final before = authLevel;
    await _writeKey(c, key);
    for (int i = 0; i < 20 && authLevel == before; i++) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    if (authorized) {
      _sessionKey = key;   // korrekter Code -> nur fuer diese Sitzung merken (RAM)
      // isAdmin wurde bereits aus CHR_AUTH_STATUS gesetzt (_parseAuthLevel) -
      // die App muss den Admin-Code dafuer nicht kennen.
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
    if (c == null || locked || newKey < 0 || newKey > 999999) return false;
    await _writeKey(c, newKey);
    // Gegenprobe: mit dem neuen Code neu autorisieren. Die Firmware liest den
    // Schluessel nicht zurueck - er liegt dort nur als Hash - also ist das der
    // einzige Weg festzustellen, ob der Wechsel wirklich angekommen ist.
    // Ohne diese Pruefung meldete die App auch dann Erfolg, wenn der Write
    // verworfen wurde, und der Nutzer verliesse sich auf einen Code, der nicht gilt.
    // Nebenwirkung: War die Sitzung als Admin angemeldet, faellt sie damit auf
    // die normale Geraete-Berechtigung zurueck.
    final ok = await authenticateWith(newKey);
    if (ok) _sessionKey = newKey;
    return ok;
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
    await _subLinkDiag?.cancel();
    await _subSlaveReceipt?.cancel();
    await _subAuthStatus?.cancel();
    await _subPairFound?.cancel();
    await _subPairState?.cancel();
    await _subConn?.cancel();
    _chars.clear();
    try { await device?.disconnect(); } catch (_) {}
    connected = false;
    authorized = false;
    authLevel = 0;
    authSupported = false;
    slaveLinked = false;
    pairingFound.clear();
    pairingState = 0;
    pairingError = 0;
    isAdmin = false;
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
    final diag = await _readBytes(EyeUuids.chrLinkDiag);
    if (diag != null && diag.length >= 4) _parseLinkDiag(diag);
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

  void _parseLinkDiag(List<int> v) {
    linkState = v[0];
    silenceMs = v[1] | (v[2] << 8);
    lossPct   = v[3];
    // Bytes 4/5 kamen erst spaeter dazu - aeltere Firmware sendet nur 4 Bytes.
    if (v.length >= 6) {
      masterChannel = v[4];
      slaveChannel  = v[5];
    }
  }

  Future<void> _subscribeNotifies() async {
    final ce = _chars[EyeUuids.chrEyeId];
    if (ce != null) {
      await ce.setNotifyValue(true);
      _subEyeId = ce.lastValueStream.listen((v) {
        if (v.isNotEmpty) { eyeId = v[0]; notifyListeners(); }
      });
    }
    // Funk-Status live mitverfolgen (Master notifyt 1x/s).
    final cl = _chars[EyeUuids.chrSlaveLink];
    if (cl != null) {
      await cl.setNotifyValue(true);
      _subSlaveLink = cl.lastValueStream.listen((v) {
        if (v.isNotEmpty) { slaveLinked = v[0] == 1; notifyListeners(); }
      });
    }
    // ESP-NOW-Verbindungsqualitaet live (state / silence / loss).
    final cd = _chars[EyeUuids.chrLinkDiag];
    if (cd != null) {
      await cd.setNotifyValue(true);
      _subLinkDiag = cd.lastValueStream.listen((v) {
        if (v.length >= 4) { _parseLinkDiag(v); notifyListeners(); }
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

    // --- Kopplung: ein Fund pro Notify (8 Bytes), Zustand als 9-Byte-Block ---
    final cpf = _chars[EyeUuids.chrPairFound];
    if (cpf != null) {
      await cpf.setNotifyValue(true);
      _subPairFound = cpf.lastValueStream.listen((v) {
        if (v.length < 8) return;
        final mac = v.sublist(0, 6);
        if (pairingFound.any((f) => _macEq(f.mac, mac))) return;
        final rssi = v[6] > 127 ? v[6] - 256 : v[6];   // int8
        pairingFound.add(FoundSlave(
          mac, rssi, (v[7] & 0x01) != 0, (v[7] & 0x02) != 0));
        notifyListeners();
      });
    }
    final cps = _chars[EyeUuids.chrPairState];
    if (cps != null) {
      await cps.setNotifyValue(true);
      _subPairState = cps.lastValueStream.listen((v) {
        if (v.length < 9) return;
        _parsePairState(v);
        notifyListeners();
      });
      try {
        final init = await cps.read();
        if (init.length >= 9) _parsePairState(init);
      } catch (_) {}
    }
  }

  void _parsePairState(List<int> v) {
    pairingState = v[0];
    boundPairId  = v[1];
    pairingError = v[2];
    boundMac     = v.sublist(3, 9);
  }

  bool _macEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // ===== Kopplung =====

  Future<void> _pairCmd(int cmd, [List<int>? mac]) async {
    final c = _chars[EyeUuids.chrPairCtrl];
    if (c == null || locked) return;
    await c.write(<int>[cmd, ...?mac], withoutResponse: false);
  }

  /// Startet die Suche nach koppelbaren Slaves. Der Master wechselt dafuer auf
  /// Kanal 6 und funkt 60 s lang; danach laeuft der Modus von selbst aus.
  Future<void> startPairingScan() async {
    pairingFound.clear();
    pairingError = 0;
    notifyListeners();
    await _pairCmd(0x01);
  }

  Future<void> stopPairingScan()            => _pairCmd(0x02);
  /// Laesst das Auge 5 s blinken - so erkennt der Nutzer, welcher Slave gemeint ist.
  Future<void> identifySlave(List<int> mac) => _pairCmd(0x03, mac);
  Future<void> bindSlave(List<int> mac)     => _pairCmd(0x04, mac);
  Future<void> unbindOwn()                  => _pairCmd(0x05);
  /// Nur mit Admin-Code: loest die Bindung eines fremden Slaves (defekter Master).
  Future<void> unbindAdmin(List<int> mac)   => _pairCmd(0x06, mac);

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

  /// Setzt die Display-Helligkeit beider Augen (0..255). Der Master stellt sein
  /// eigenes Backlight und schiebt den Wert per ConfigMsg an den Slave weiter.
  ///
  /// War frueher ausgebaut mit der Begruendung, es funktioniere auf dem ESP32
  /// nicht zuverlaessig. Die eigentliche Ursache lag in der Firmware: ledcAttach()
  /// lief vor tft.begin(), und TFT_eSPI::init() reisst den Backlight-Pin danach
  /// als normalen GPIO an sich - die PWM war damit wirkungslos. Seit die
  /// Zuordnung nach tft.begin() passiert, geht es.
  Future<void> setBrightness(int value) async {
    if (locked) return;
    final v = value.clamp(0, 255);
    final c = _chars[EyeUuids.chrBrightness]; if (c == null) return;
    await c.write([v], withoutResponse: false);
    brightness = v; notifyListeners();
  }

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
