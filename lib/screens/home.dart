import 'package:flutter/material.dart';
import '../ble_service.dart';
import '../slot_metadata.dart';
import 'settings.dart';
import 'diagnostics.dart';
import 'cloud_eyes_screen.dart';

class HomeScreen extends StatefulWidget {
  final EyeBle ble;
  const HomeScreen({super.key, required this.ble});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  // Slot-Metadata Cache: [slot_idx] -> SlotMeta? (null = leer)
  final List<SlotMeta?> _slotMeta = List<SlotMeta?>.filled(kCloudSlotCount, null);

  @override
  void initState() {
    super.initState();
    widget.ble.addListener(_onBleUpdate);
    _loadSlotMeta();
  }

  @override
  void dispose() {
    widget.ble.removeListener(_onBleUpdate);
    super.dispose();
  }

  void _onBleUpdate() {
    // Wenn sich pair_id geaendert hat (Reconnect anderer Geraet) -> neu laden
    _loadSlotMeta();
    if (mounted) setState(() {});
  }

  Future<void> _loadSlotMeta() async {
    final pid = widget.ble.deviceId;
    for (int s = 0; s < kCloudSlotCount; s++) {
      _slotMeta[s] = await SlotMetadataStore.get(pid, s);
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteSlot(int slot) async {
    final pid = widget.ble.deviceId;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cloud-Slot ${slot + 1} loeschen?'),
        content: Text(_slotMeta[slot] != null
            ? '"${_slotMeta[slot]!.name}" wird von beiden Augen entfernt.'
            : 'Slot wird auf beiden Augen geleert.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Loeschen')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.ble.deleteEye(slot);
      await SlotMetadataStore.clear(pid, slot);
      _slotMeta[slot] = null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Slot ${slot + 1} geleert')),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Loesch-Fehler: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = widget.ble;
    final screens = [
      _EyeGrid(ble: ble, slotMeta: _slotMeta, onDeleteSlot: _deleteSlot),
      CloudEyesScreen(ble: ble, onSlotMetaChanged: _loadSlotMeta),
      SettingsScreen(ble: ble),
      DiagnosticsScreen(ble: ble),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(ble.device?.platformName ?? 'EyePair'),
        actions: [
          if (ble.connected)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.bluetooth_connected, color: Colors.lightGreen),
            )
          else
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.bluetooth_disabled, color: Colors.red),
            ),
          IconButton(
            icon: const Icon(Icons.link_off),
            onPressed: () async {
              await ble.disconnect();
              if (mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: screens[_tab],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grid_view), label: 'Augen'),
          NavigationDestination(icon: Icon(Icons.cloud_download), label: 'Cloud'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Einstellungen'),
          NavigationDestination(icon: Icon(Icons.analytics), label: 'Diagnose'),
        ],
      ),
    );
  }
}

/// Augen-Grid: hardcoded Augen (Asset-Vorschau) + Cloud-Slots mit echter Bild-Vorschau.
class _EyeGrid extends StatelessWidget {
  final EyeBle ble;
  final List<SlotMeta?> slotMeta;
  final Future<void> Function(int slot) onDeleteSlot;
  const _EyeGrid({required this.ble, required this.slotMeta, required this.onDeleteSlot});

  int get _totalCount => kHardcodedEyeCount + kCloudSlotCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _totalCount,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (_, i) {
        final isCloud  = i >= kHardcodedEyeCount;
        final cloudSlot = isCloud ? (i - kHardcodedEyeCount) : -1;
        final meta = isCloud ? slotMeta[cloudSlot] : null;
        // Master meldet via CHR_SLOT_STATUS welche Slots auf der LittleFS belegt sind.
        // Wichtig nach Reinstall: lokale Metadaten weg, aber Master hat die Bilder noch.
        final occupied = isCloud && (ble.slotOccupiedMask & (1 << cloudSlot)) != 0;
        final selected = i == ble.eyeId;
        return Material(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => ble.setEyeId(i),
            onLongPress: isCloud ? () => onDeleteSlot(cloudSlot) : null,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: isCloud
                          ? (meta != null
                              ? Image.network(
                                  meta.url,
                                  fit: BoxFit.cover,
                                  cacheWidth: 200,
                                  errorBuilder: (_, __, ___) =>
                                      const Icon(Icons.broken_image),
                                )
                              : Container(
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: Center(
                                    child: occupied
                                        // Reinstall-Fall: Master kennt den Slot noch, App nicht.
                                        // Reiner Text, kein Icon - User weiss "da ist was".
                                        ? Text('belegt',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Theme.of(context).colorScheme.onSurfaceVariant))
                                        // Echt leer: Cloud-Icon + Text (Originalverhalten).
                                        : Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.cloud,
                                                  size: 32,
                                                  color: Theme.of(context).colorScheme.outline),
                                              const SizedBox(height: 4),
                                              Text('leer',
                                                  style: TextStyle(
                                                      fontSize: 11,
                                                      color: Theme.of(context).colorScheme.outline)),
                                            ],
                                          ),
                                  ),
                                ))
                          : Image.asset(kEyeAssets[i], fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    isCloud
                        ? (meta != null ? meta.name : 'Cloud ${cloudSlot + 1}')
                        : kEyeLabels[i],
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
