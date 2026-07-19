import 'package:flutter/material.dart';
import '../ble_service.dart';
import '../cloud_eyes.dart';
import '../image_pipeline.dart';
import '../slot_metadata.dart';

class CloudEyesScreen extends StatefulWidget {
  final EyeBle ble;
  final Future<void> Function()? onSlotMetaChanged;
  const CloudEyesScreen({super.key, required this.ble, this.onSlotMetaChanged});
  @override
  State<CloudEyesScreen> createState() => _CloudEyesScreenState();
}

class _CloudEyesScreenState extends State<CloudEyesScreen> {
  final _api = GithubCloudEyes();
  List<CloudEye>? _eyes;
  String? _error;
  bool _loading = false;

  // Download-Status
  bool   _downloading = false;
  int    _downloadDone = 0;
  int    _downloadTotal = 0;
  String _downloadName = '';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() { _loading = true; _error = null; });
    try {
      final list = await _api.list();
      // Bereits installierte Bilder ausblenden - die User loescht sie via Long-press
      // im Eye-Grid, dann tauchen sie hier wieder auf.
      final installed = await SlotMetadataStore.getInstalledUrls(widget.ble.deviceId);
      final visible = list.where((e) => !installed.contains(e.downloadUrl)).toList();
      if (!mounted) return;
      setState(() { _eyes = visible; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  Future<void> _downloadToSlot(CloudEye eye, int slot) async {
    if (_downloading) return;
    setState(() {
      _downloading = true;
      _downloadDone = 0;
      _downloadTotal = 0;
      _downloadName = '${eye.name} -> Slot ${slot + 1}';
    });
    try {
      final pngBytes = await _api.download(eye);
      final rgb565 = pngToRgb565(pngBytes);
      await widget.ble.uploadEye(slot, rgb565, onProgress: (sent, total) {
        if (!mounted) return;
        setState(() { _downloadDone = sent; _downloadTotal = total; });
      });
      // Slot-Metadata persistieren
      await SlotMetadataStore.set(widget.ble.deviceId, slot, eye.name, eye.downloadUrl);
      await widget.onSlotMetaChanged?.call();
      // Cloud-Tab Liste aktualisieren (Bild verschwindet weil installiert)
      await _refresh();
      if (!mounted) return;
      // Status-Dialog: zeigt Slave-Forward Progress + Auto-Reconnect zum Receipt-Read
      await _showSlaveForwardDialog(eye.name, slot);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download-Fehler: $e')),
      );
    } finally {
      if (mounted) setState(() { _downloading = false; });
    }
  }

  /// Zeigt einen Status-Dialog mit Countdown waehrend Master->Slave forwarded,
  /// disconnected die App fuer Coex-Schutz, reconnected dann fuer Receipt-Read.
  Future<void> _showSlaveForwardDialog(String eyeName, int slot) async {
    // App disconnecten - Master forwarded jetzt ohne BLE-Coex.
    // Mit Timeout: wenn disconnect haengt (Android-BT-State stuck), nicht ewig blockieren.
    try {
      await widget.ble.disconnect().timeout(const Duration(seconds: 5));
    } catch (_) {}

    if (!mounted) return;
    // Non-dismissable Dialog mit Countdown
    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _SlaveForwardDialog(ble: widget.ble, eyeName: eyeName, slot: slot),
    );

    if (!mounted) return;
    if (result != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result)));
    }
    // Force-Refresh: stellt sicher dass die Screen nach Dialog-Close sauber neu rendert.
    // Falls BLE in einem komischen Zustand ist, vermeidet das einen schwarzen Frame.
    setState(() {});
  }

  Future<void> _pickSlotAndDownload(CloudEye eye) async {
    final slot = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('"${eye.name}" auf welchen Slot herunterladen?'),
        children: [
          for (int s = 0; s < kCloudSlotCount; s++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, s),
              child: Row(children: [
                const Icon(Icons.cloud_download),
                const SizedBox(width: 8),
                Text('Slot ${s + 1}'),
              ]),
            ),
        ],
      ),
    );
    if (slot != null) await _downloadToSlot(eye, slot);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_downloading)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Card(
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Lade auf Augen: $_downloadName',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _downloadTotal > 0 ? _downloadDone / _downloadTotal : null,
                    ),
                    const SizedBox(height: 4),
                    Text('$_downloadDone / $_downloadTotal Chunks',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: Colors.red.withOpacity(0.2),
            padding: const EdgeInsets.all(12),
            child: Text(_error!),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _eyes == null || _eyes!.isEmpty
                    ? ListView(
                        children: const [
                          SizedBox(height: 200),
                          Center(child: Text('Keine Augen in der Cloud gefunden.\n'
                              'Der Admin hat noch keine Augen bereit gestellt.',
                              textAlign: TextAlign.center)),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _eyes!.length,
                        itemBuilder: (_, i) {
                          final e = _eyes![i];
                          return Card(
                            child: ListTile(
                              leading: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  e.downloadUrl,
                                  width: 56, height: 56, fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                                ),
                              ),
                              title: Text(e.name),
                              subtitle: Text('${(e.sizeBytes / 1024).toStringAsFixed(1)} KB'),
                              trailing: ElevatedButton.icon(
                                icon: const Icon(Icons.cloud_download),
                                label: const Text('Download'),
                                onPressed: _downloading ? null : () => _pickSlotAndDownload(e),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

/// Status-Dialog der waehrend Master->Slave-Forward angezeigt wird.
/// - Startet bei Dialog-Open einen Reconnect-Timer (15s)
/// - Nach Reconnect liest er CHR_SLAVE_RECEIPT, zeigt unique/total
/// - Bei Re-Request: wartet weiter, liest erneut
class _SlaveForwardDialog extends StatefulWidget {
  final EyeBle ble;
  final String eyeName;
  final int    slot;
  const _SlaveForwardDialog({required this.ble, required this.eyeName, required this.slot});
  @override
  State<_SlaveForwardDialog> createState() => _SlaveForwardDialogState();
}

class _SlaveForwardDialogState extends State<_SlaveForwardDialog> {
  String _status = 'Lade auf Slave...';
  String _detail = 'Geschaetzt ~15 Sekunden';
  bool   _done = false;
  bool   _closed = false;          // Guard gegen doppeltes pop
  bool   _pendingReconnect = false;
  int    _reconnectAttempts = 0;
  static const int _maxReconnects = 5;
  // Notfall-Timeout: Dialog schliesst sich nach 90s auf jeden Fall.
  // Verhindert haengenden Dialog wenn BLE-Reconnect aus irgendeinem Grund tot bleibt.
  static const Duration _emergencyTimeout = Duration(seconds: 90);

  @override
  void initState() {
    super.initState();
    // Nach 15s Auto-Reconnect-Versuch
    Future.delayed(const Duration(seconds: 15), _tryReconnect);
    // Emergency-Close - falls alle anderen Wege fehlschlagen
    Future.delayed(_emergencyTimeout, _emergencyClose);
    widget.ble.addListener(_onBleUpdate);
  }

  @override
  void dispose() {
    widget.ble.removeListener(_onBleUpdate);
    super.dispose();
  }

  /// Schliesst den Dialog genau einmal. Schuetzt vor double-pop falls mehrere
  /// Future-Delayed gleichzeitig auf pop() abzielen.
  void _safePop(String? result) {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop(result);
  }

  /// Notfall-Schliesser nach 90s. Wenn _done schon true, dann tut diese
  /// Funktion nichts (regulaerer Close laeuft schon). Sonst Force-Close.
  void _emergencyClose() {
    if (_closed || !mounted) return;
    setState(() {
      _status = 'Zeitueberschreitung';
      _detail = 'Konnte nicht abschliessen - bitte App neu oeffnen falls noetig';
      _done = true;
    });
    _safePop(null);
  }

  void _onBleUpdate() {
    if (!mounted || _done || _closed) return;
    // Wenn wir nach Reconnect eine Receipt sehen, Status updaten
    final unique = widget.ble.slaveUniqueReceived;
    final total  = widget.ble.slaveTotalChunks;
    final round  = widget.ble.slaveReRequestRound;
    if (total > 0) {
      if (unique >= total) {
        setState(() {
          _status = 'Fertig!';
          _detail = 'Bild komplett auf beiden Augen (${unique}/${total} Chunks)';
          _done = true;
        });
        Future.delayed(const Duration(seconds: 2), () {
          _safePop('"${widget.eyeName}" erfolgreich uebertragen ($unique/$total Chunks)');
        });
      } else {
        setState(() {
          _detail = 'Re-Request Runde $round laeuft: $unique/$total Chunks';
        });
        // Noch nicht komplett -> warte weiter, ggf. erneut Receipt holen.
        // Guard: nur EIN Reconnect-Timer pro 5s-Fenster, sonst koennen viele
        // Notifies in Serie viele parallele _tryReconnect-Calls triggern.
        if (!_pendingReconnect) {
          _pendingReconnect = true;
          Future.delayed(const Duration(seconds: 5), () {
            _pendingReconnect = false;
            _tryReconnect();
          });
        }
      }
    }
  }

  Future<void> _tryReconnect() async {
    if (!mounted || _done) return;
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnects) {
      setState(() {
        _status = 'Konnte Slave-Status nicht abrufen';
        _detail = 'Bild ist wahrscheinlich auf beiden Augen, aber keine Bestaetigung';
        _done = true;
      });
      Future.delayed(const Duration(seconds: 2), () => _safePop(null));
      return;
    }
    try {
      if (!widget.ble.connected) {
        setState(() { _detail = 'Reconnect $_reconnectAttempts/$_maxReconnects...'; });
        await widget.ble.reconnect();
      }
    } catch (e) {
      // Reconnect fehlgeschlagen, nochmal in 3s versuchen
      Future.delayed(const Duration(seconds: 3), _tryReconnect);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_status),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_done) const LinearProgressIndicator(),
          const SizedBox(height: 16),
          Text(_detail, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        if (!_done)
          TextButton(
            onPressed: () => _safePop('Abgebrochen — Bild wird trotzdem fertig uebertragen'),
            child: const Text('Abbrechen'),
          ),
      ],
    );
  }
}
