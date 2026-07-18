import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../ble_service.dart';

class SettingsScreen extends StatefulWidget {
  final EyeBle ble;
  const SettingsScreen({super.key, required this.ble});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _anim;

  @override
  void initState() {
    super.initState();
    _anim = widget.ble.animEnabled == 1;
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
          ? 'Zugangscode geaendert'
          : 'Konnte Code nicht setzen (nicht autorisiert?)'),
    ));
  }

  Future<void> _enterCode() async {
    final code = await _promptCode('Zugangscode eingeben', '6-stellig');
    if (code == null) return;
    await widget.ble.authenticateWith(code);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: SwitchListTile(
                secondary: const Icon(Icons.movie_filter),
                title: const Text('Animation'),
                subtitle: Text(_anim
                    ? 'Augen-Animation laeuft'
                    : 'Augen zentriert (pausiert)'),
                value: _anim,
                onChanged: (v) {
                  setState(() => _anim = v);
                  ble.setAnimEnabled(v);
                },
              ),
            ),
            // Zugangsschutz nur anzeigen, wenn die Firmware ihn unterstuetzt.
            if (ble.authSupported) ...[
              const SizedBox(height: 8),
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(
                        ble.authorized ? Icons.lock_open : Icons.lock,
                        color: ble.authorized ? Colors.green : Colors.orange,
                      ),
                      title: const Text('Zugang'),
                      subtitle: Text(ble.authorized
                          ? 'Autorisiert - Steuerung freigeschaltet'
                          : 'Nicht autorisiert - Code noetig'),
                      trailing: ble.authorized
                          ? null
                          : TextButton(
                              onPressed: _enterCode,
                              child: const Text('Code eingeben'),
                            ),
                    ),
                    if (ble.authorized)
                      ListTile(
                        leading: const Icon(Icons.password),
                        title: const Text('Zugangscode aendern'),
                        subtitle: const Text(
                            'Neuen 6-stelligen Code fuer dieses Augenpaar setzen'),
                        onTap: _changeKey,
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 32),
            const Center(
              child: Text(
                'Created by Thomas Paul for Schafberg-Pass Sankt Gilgen',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        );
      },
    );
  }
}
