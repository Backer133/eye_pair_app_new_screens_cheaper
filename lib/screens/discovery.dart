import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../ble_service.dart';
import '../theme.dart';
import 'home.dart';

class DiscoveryScreen extends StatefulWidget {
  final EyeBle ble;
  const DiscoveryScreen({super.key, required this.ble});
  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen>
    with SingleTickerProviderStateMixin {
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _subScan;
  StreamSubscription<bool>? _subScanning;
  bool _scanning = false;   // vom echten BLE-Stack (FlutterBluePlus.isScanning)
  bool _starting = false;   // _scan() laeuft gerade (Stop/Debounce/Start)
  String? _error;
  String? _connectingId;   // remoteId des Geraets, zu dem gerade verbunden wird
  DateTime _lastScanStart = DateTime.fromMillisecondsSinceEpoch(0);
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
    // Scan-Status direkt vom BLE-Stack ableiten: bleibt bis zum Timeout true, damit
    // der "Neu suchen"-Button waehrend eines laufenden Scans wirklich gesperrt ist
    // (verhindert das schnelle Neu-Starten, das Android drosselt).
    _subScanning = FlutterBluePlus.isScanning.listen((s) {
      if (mounted) setState(() => _scanning = s);
    });
    // Ergebnisse DAUERHAFT mitschreiben und NICHT bei jedem Neu-Suchen loeschen -
    // so verschwindet ein einmal gefundenes Auge nicht mehr aus der Liste, auch
    // wenn ein spaeterer Scan (z.B. wegen Android-Drossel) nichts liefert.
    _subScan = FlutterBluePlus.onScanResults.listen((rs) {
      for (final r in rs) {
        final idx = _results.indexWhere((x) => x.device.remoteId == r.device.remoteId);
        if (idx >= 0) {
          _results[idx] = r;
        } else {
          _results.add(r);
        }
      }
      _results.sort((a, b) => b.rssi.compareTo(a.rssi));   // staerkstes Signal zuerst
      if (mounted) setState(() {});
    });
    _start();
  }

  Future<void> _start() async {
    await _ensurePermissions();
    if (!await FlutterBluePlus.isSupported) {
      setState(() => _error = "BLE wird auf diesem Geraet nicht unterstuetzt");
      return;
    }
    _scan();
  }

  Future<void> _ensurePermissions() async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();
    }
  }

  Future<void> _scan() async {
    if (_starting || _scanning) return;   // kein Doppelstart
    setState(() { _starting = true; _error = null; });
    try {
      // Laufenden Scan sauber stoppen.
      if (FlutterBluePlus.isScanningNow) {
        try { await FlutterBluePlus.stopScan(); } catch (_) {}
      }
      // Mindestabstand zwischen Scan-Starts: Android sperrt den Scanner nach zu
      // vielen Starts (5 in 30 s) stumm. Der Gap haelt uns sicher darunter.
      final since = DateTime.now().difference(_lastScanStart);
      const minGap = Duration(seconds: 3);
      if (since < minGap) await Future.delayed(minGap - since);
      if (!mounted) return;
      _lastScanStart = DateTime.now();
      // onScanResults-Listener laeuft dauerhaft (siehe initState) -> Ergebnisse
      // werden gemerged, nicht geloescht.
      await FlutterBluePlus.startScan(
        withServices: [EyeUuids.svcEyeCtrl],
        timeout: const Duration(seconds: 8),
        androidUsesFineLocation: false,
      );
    } catch (e) {
      if (mounted) setState(() => _error = "Scan-Fehler: $e");
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _connect(ScanResult r) async {
    setState(() => _connectingId = r.device.remoteId.str);
    try {
      await FlutterBluePlus.stopScan();
      await widget.ble.connectAndDiscover(r.device);
      if (!mounted) return;
      setState(() => _connectingId = null);
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HomeScreen(ble: widget.ble),
      ));
      // Zurueck von Home -> erneut scannen.
      if (mounted) _scan();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectingId = null;
        _error = "Verbindungs-Fehler: $e";
      });
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    _subScan?.cancel();
    _subScanning?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _header(),
            if (_error != null) _errorBar(_error!),
            Expanded(
              child: _results.isEmpty ? _emptyState() : _deviceList(),
            ),
          ],
        ),
      ),
      floatingActionButton: Builder(builder: (_) {
        final busy = _scanning || _starting;
        return FloatingActionButton.extended(
          onPressed: busy ? null : _scan,
          backgroundColor: busy ? kSurfaceHi : kAccent,
          icon: busy
              ? const SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))
              : const Icon(Icons.refresh, color: Colors.white),
          label: Text(busy ? 'Suche laeuft' : 'Neu suchen',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        );
      }),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: kAccent.withOpacity(.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.remove_red_eye, color: kAccentGlow),
          ),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('SBP Eye Settings',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(
                _scanning
                    ? 'Suche nach Augenpaaren...'
                    : '${_results.length} Augenpaar${_results.length == 1 ? '' : 'e'} gefunden',
                style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(.55)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorBar(String msg) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBad.withOpacity(.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBad.withOpacity(.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: kBad, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(color: kBad, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _radar(),
          const SizedBox(height: 28),
          Text(
            _scanning ? 'Suche Augenpaare...' : 'Keine Augenpaare gefunden',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _scanning
                  ? 'Augen einschalten und in der Naehe bleiben.'
                  : 'Stelle sicher, dass die Augen mit Strom versorgt sind, und tippe auf "Neu suchen".',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(.5), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  /// Pulsierender Radar-Ring waehrend der Suche (statisch, wenn nicht gescannt).
  Widget _radar() {
    return SizedBox(
      width: 160, height: 160,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, child) {
          return Stack(
            alignment: Alignment.center,
            children: [
              if (_scanning) ...[
                _ring(_pulse.value),
                _ring((_pulse.value + 0.5) % 1.0),
              ],
              Container(
                width: 76, height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: kAccent.withOpacity(.16),
                  border: Border.all(color: kAccent.withOpacity(.5), width: 2),
                ),
                child: Icon(
                  _scanning ? Icons.bluetooth_searching : Icons.bluetooth_disabled,
                  color: kAccentGlow, size: 34,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _ring(double t) {
    final size = 76 + t * 84;
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: kAccent.withOpacity((1 - t) * 0.5)),
      ),
    );
  }

  Widget _deviceList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _deviceCard(_results[i]),
    );
  }

  Widget _deviceCard(ScanResult r) {
    final name = r.advertisementData.advName.isNotEmpty
        ? r.advertisementData.advName
        : (r.device.platformName.isNotEmpty ? r.device.platformName : 'Augenpaar');
    final connecting = _connectingId == r.device.remoteId.str;

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: connecting ? null : () => _connect(r),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.remove_red_eye, color: kAccentGlow, size: 26),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        SignalBars(r.rssi),
                        const SizedBox(width: 8),
                        Text('${r.rssi} dBm',
                            style: TextStyle(
                                fontSize: 12, color: Colors.white.withOpacity(.5))),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              connecting
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: kAccentGlow))
                  : Transform.rotate(
                      angle: -math.pi / 4,
                      child: Icon(Icons.arrow_forward, color: Colors.white.withOpacity(.4)),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
