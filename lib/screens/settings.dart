import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../ble_service.dart';
import '../theme.dart';

class SettingsScreen extends StatefulWidget {
  final EyeBle ble;
  const SettingsScreen({super.key, required this.ble});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // App-Version (aus dem Paket -> folgt automatisch der pubspec-Version).
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() => _version = 'Version ${info.version} (Build ${info.buildNumber})');
      }
    } catch (_) {}
  }

  // Dialog fuer 6-stellige Code-Eingabe. Gibt die Zahl zurueck oder null.
  Future<int?> _promptCode(String title, String hint) async {
    final ctrl = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(hintText: hint, counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text);
              Navigator.pop(ctx, (v != null && v >= 0 && v <= 999999) ? v : null);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _changeKey() async {
    final code = await _promptCode('Neuen Zugangscode setzen', '6-stellig, z.B. 123456');
    if (code == null) return;
    final ok = await widget.ble.changeDeviceKey(code);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Zugangscode geaendert - gilt ab sofort'
          : 'Konnte Code nicht setzen (nicht autorisiert?)'),
    ));
  }

  Future<void> _renameDevice() async {
    final ctrl = TextEditingController(text: widget.ble.deviceName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Augenpaar benennen'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 23,
          decoration: const InputDecoration(hintText: 'z.B. Augen Thomas'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    final ok = await widget.ble.setDeviceName(name);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Name geaendert - beim naechsten Scan sichtbar'
          : 'Konnte Name nicht setzen (nicht autorisiert?)'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        final animOn = ble.animEnabled == 1;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            // ---- Augenpaar ----
            const SectionHeader('Augenpaar', icon: Icons.remove_red_eye),
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                leading: _iconBox(Icons.badge_outlined, kAccentGlow),
                title: Text(ble.deviceName.isEmpty ? 'Augenpaar' : ble.deviceName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Bluetooth-Name in der Geraeteliste'),
                trailing: FilledButton.tonalIcon(
                  onPressed: _renameDevice,
                  icon: const Icon(Icons.edit, size: 18),
                  label: const Text('Umbenennen'),
                ),
              ),
            ),

            // ---- Anzeige ----
            const SectionHeader('Anzeige', icon: Icons.tune),
            Card(
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                secondary: _iconBox(Icons.movie_filter_outlined, kAccentGlow),
                title: const Text('Animation',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(animOn
                    ? 'Augen-Animation laeuft'
                    : 'Augen zentriert (pausiert)'),
                value: animOn,
                activeColor: kAccent,
                onChanged: (v) => ble.setAnimEnabled(v),
              ),
            ),

            // ---- Zugangsschutz ----
            if (ble.authSupported) ...[
              const SectionHeader('Zugangsschutz', icon: Icons.shield_outlined),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: _iconBox(
                          ble.authorized ? Icons.lock_open : Icons.lock,
                          ble.authorized ? kGood : kWarn),
                      title: const Text('Status',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(ble.authorized
                          ? 'Steuerung freigeschaltet'
                          : 'Nicht autorisiert'),
                      trailing: StatusPill(
                        ble.authorized ? 'Autorisiert' : 'Gesperrt',
                        color: ble.authorized ? kGood : kWarn,
                        icon: ble.authorized ? Icons.check : Icons.lock,
                      ),
                    ),
                    const Divider(height: 1),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      leading: _iconBox(Icons.password, kAccentGlow),
                      title: const Text('Zugangscode aendern',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Neuen 6-stelligen Code fuer dieses Augenpaar'),
                      trailing: const Icon(Icons.chevron_right, color: Colors.white38),
                      onTap: _changeKey,
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 36),
            Center(
              child: Text(
                'Created by Thomas Paul for\nSchafberg-Pass Sankt Gilgen',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(.35),
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _version.isEmpty ? '' : _version,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(.30),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: color.withOpacity(.14),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}
