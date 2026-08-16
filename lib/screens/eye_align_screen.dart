import 'package:flutter/material.dart';

import '../ble_service.dart';
import '../theme.dart';

/// Richtet ein einzelnes Auge auf seine Maskenöffnung aus.
///
/// Jede Maske ist handgeschnitzt, deshalb hat jedes Auge eigene Werte — anders als
/// die Bewegung, die für beide gleich sein muss. Die zwei Regler sind bewusst
/// orthogonal: Verschieben ändert die Öffnungshöhe nicht und umgekehrt, sonst würde
/// das Einstellen zum Ping-Pong.
class EyeAlignScreen extends StatefulWidget {
  final EyeBle ble;
  const EyeAlignScreen({super.key, required this.ble});
  @override
  State<EyeAlignScreen> createState() => _EyeAlignScreenState();
}

class _EyeAlignScreenState extends State<EyeAlignScreen> {
  int _target = 0;               // 0 = Master, 1 = Slave
  bool _guides = true;           // beim Öffnen an - man will ja sehen, wo die Kante liegt
  int? _previewYOff;             // während des Ziehens
  int? _previewVisH;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.ble.setEyeGuides(true);
    });
  }

  @override
  void dispose() {
    // Hilfslinien nie am Auge stehen lassen - sonst wundert man sich später,
    // warum ein grüner Strich im Gesicht klebt.
    widget.ble.setEyeGuides(false);
    super.dispose();
  }

  int _yOff(EyeBle ble) => _previewYOff ?? ble.eyeYOff[_target];
  int _visH(EyeBle ble) => _previewVisH ?? ble.eyeVisH[_target];

  void _send(EyeBle ble, {required bool persist}) {
    ble.setEyeGeom(_target, _yOff(ble), _visH(ble), persist: persist);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        return Scaffold(
          appBar: AppBar(title: const Text('Augen ausrichten')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Master'), icon: Icon(Icons.memory)),
                  ButtonSegment(value: 1, label: Text('Slave'),  icon: Icon(Icons.visibility)),
                ],
                selected: {_target},
                onSelectionChanged: (s) => setState(() {
                  _target = s.first;
                  _previewYOff = null;
                  _previewVisH = null;
                }),
              ),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline, color: kAccentGlow),
                  title: const Text('Welches Auge ist das?'),
                  subtitle: const Text('Laesst das gewaehlte Auge kurz blinken'),
                  trailing: FilledButton.tonal(
                    onPressed: _identify,
                    child: const Text('Blinken'),
                  ),
                ),
              ),
              SwitchListTile(
                secondary: const Icon(Icons.straighten, color: kAccentGlow),
                title: const Text('Hilfslinien'),
                subtitle: const Text('Markiert die Kanten des sichtbaren Bereichs'),
                value: _guides,
                activeColor: kAccent,
                onChanged: (v) {
                  setState(() => _guides = v);
                  ble.setEyeGuides(v);
                },
              ),
              const SizedBox(height: 8),
              _slider(
                icon: Icons.swap_vert,
                title: 'Vertikale Position',
                hint: 'Bis die Pupille mittig im Ausschnitt sitzt',
                value: _yOff(ble).toDouble(),
                min: -60, max: 60,
                label: '${_yOff(ble)} px',
                onChanged: (v) => setState(() => _previewYOff = v.round()),
                onChangeEnd: (v) {
                  _previewYOff = v.round();
                  _send(ble, persist: true);
                  _previewYOff = null;
                },
                onPreview: () => _send(ble, persist: false),
              ),
              _slider(
                icon: Icons.height,
                title: 'Sichtbare Hoehe',
                hint: 'Bis die schwarzen Raender hinter dem Holz verschwinden',
                value: _visH(ble).toDouble(),
                min: 60, max: 240,
                label: '${_visH(ble)} px',
                onChanged: (v) => setState(() => _previewVisH = v.round()),
                onChangeEnd: (v) {
                  _previewVisH = v.round();
                  _send(ble, persist: true);
                  _previewVisH = null;
                },
                onPreview: () => _send(ble, persist: false),
              ),
              const SizedBox(height: 12),
              const Text(
                'Die Ausrichtung gilt nur fuer das gewaehlte Auge. Bewegung und '
                'Blinzeln stellst du unter "Bewegung & Blinzeln" ein - die gelten '
                'fuer beide zusammen.',
                style: TextStyle(fontSize: 12, color: Colors.white38),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _identify() async {
    final mac = _target == 0 ? null : widget.ble.boundMac;
    if (_target == 0) {
      // Der Master ist das Auge, mit dem die App gerade verbunden ist - das ist
      // ohnehin eindeutig, aber ein Hinweis hilft beim Einbau in die Maske.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Das ist das Auge, mit dem du verbunden bist.'),
      ));
      return;
    }
    if (mac == null || !widget.ble.isBound) return;
    await widget.ble.identifySlave(mac);
  }

  Widget _slider({
    required IconData icon,
    required String title,
    required String hint,
    required double value,
    required double min,
    required double max,
    required String label,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    required VoidCallback onPreview,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: kAccentGlow),
                const SizedBox(width: 12),
                Expanded(child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(label, style: const TextStyle(color: Colors.white70)),
              ],
            ),
            Slider(
              min: min, max: max,
              value: value.clamp(min, max),
              activeColor: kAccent,
              // Waehrend des Ziehens Vorschau ohne Flash-Schreiben, gespeichert
              // wird erst beim Loslassen.
              onChanged: widget.ble.locked ? null : (v) { onChanged(v); onPreview(); },
              onChangeEnd: onChangeEnd,
            ),
            Text(hint, style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ],
        ),
      ),
    );
  }
}
