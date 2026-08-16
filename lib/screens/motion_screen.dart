import 'package:flutter/material.dart';

import '../ble_service.dart';
import '../theme.dart';

/// Gestaltet die komplette Bewegung des Augenpaares.
///
/// Anders als die Maskenausrichtung gilt das hier für **beide** Augen: sie müssen mit
/// exakt denselben Werten rechnen, sonst blinzeln sie nicht mehr gleichzeitig. Die
/// Werkswerte und die drei Voreinstellungen liegen deshalb in der Firmware und werden
/// von dort zurückgemeldet — die App kennt sie gar nicht.
class MotionScreen extends StatefulWidget {
  final EyeBle ble;
  const MotionScreen({super.key, required this.ble});
  @override
  State<MotionScreen> createState() => _MotionScreenState();
}

class _MotionScreenState extends State<MotionScreen> {
  bool _advanced = false;
  AnimCfg? _preview;    // während des Ziehens; sonst gilt der Stand aus der Firmware

  AnimCfg? get _cfg => _preview ?? widget.ble.animCfg;

  void _live(AnimCfg next) {
    setState(() => _preview = next);
    widget.ble.setAnimCfg(next, persist: false);
  }

  void _commit() {
    final c = _preview;
    _preview = null;
    if (c != null) widget.ble.setAnimCfg(c, persist: true);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        final cfg = _cfg;

        return Scaffold(
          appBar: AppBar(title: const Text('Bewegung & Blinzeln')),
          body: cfg == null
              ? const Center(child: Text('Lese Einstellungen vom Auge ...'))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  children: [
                    const SectionHeader('Voreinstellungen', icon: Icons.auto_awesome),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            _preset(ble, 0, 'Ruhig',   Icons.self_improvement),
                            const SizedBox(width: 8),
                            _preset(ble, 1, 'Normal',  Icons.remove_red_eye),
                            const SizedBox(width: 8),
                            _preset(ble, 2, 'Lebhaft', Icons.bolt),
                          ],
                        ),
                      ),
                    ),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.restart_alt, color: kWarn),
                        title: const Text('Auf Werkseinstellung zuruecksetzen'),
                        subtitle: const Text('Stellt die urspruengliche Bewegung wieder her'),
                        onTap: ble.locked ? null : () {
                          _preview = null;
                          ble.resetAnimCfg();
                        },
                      ),
                    ),

                    const SizedBox(height: 8),
                    Card(
                      child: ExpansionTile(
                        initiallyExpanded: _advanced,
                        onExpansionChanged: (v) => setState(() => _advanced = v),
                        leading: const Icon(Icons.tune, color: kAccentGlow),
                        title: const Text('Erweitert',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('Jede Bewegung einzeln einstellen'),
                        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                        children: [
                          const _GroupLabel('Bewegung'),
                          _s(cfg, 'Verweildauer', 'Wie lange das Auge an einer Stelle bleibt',
                              cfg.holdMs.toDouble(), 500, 10000, '${(cfg.holdMs / 1000).toStringAsFixed(1)} s',
                              (v) => cfg.copyWith(holdMs: v.round())),
                          _s(cfg, 'Bewegungsdauer', 'Wie lange ein Blickwechsel dauert',
                              cfg.moveMs.toDouble(), 80, 1500, '${cfg.moveMs} ms',
                              (v) => cfg.copyWith(moveMs: v.round())),
                          _s(cfg, 'Anzahl Blickrichtungen', '3 = Mitte und oben; 5 ergaenzt unten',
                              cfg.posCount.toDouble(), 2, 5, '${cfg.posCount}',
                              (v) => cfg.copyWith(posCount: v.round()), divisions: 3),
                          _s(cfg, 'Ausschlag seitlich', 'Wie weit der Blick nach links und rechts geht',
                              cfg.ampX.toDouble(), 0, 40, '${cfg.ampX} px',
                              (v) => cfg.copyWith(ampX: v.round())),
                          _s(cfg, 'Ausschlag vertikal', 'Wie weit der Blick nach oben und unten geht',
                              cfg.ampY.toDouble(), 0, 40, '${cfg.ampY} px',
                              (v) => cfg.copyWith(ampY: v.round())),
                          _s(cfg, 'Schwung', 'Wie weit das Auge beim Wechsel ausholt',
                              cfg.arc.toDouble(), 0, 40, '${cfg.arc}',
                              (v) => cfg.copyWith(arc: v.round())),
                          _s(cfg, 'Weichheit', '0 = gleichmaessig, 100 = sanft anfahren und abbremsen',
                              cfg.ease.toDouble(), 0, 100, '${cfg.ease}',
                              (v) => cfg.copyWith(ease: v.round())),

                          const _GroupLabel('Blinzeln'),
                          _s(cfg, 'Haeufigkeit', 'Zeitfenster, in dem ein Lidschlag liegt',
                              cfg.blinkWindowMs.toDouble(), 1500, 20000,
                              '${(cfg.blinkWindowMs / 1000).toStringAsFixed(1)} s',
                              (v) => cfg.copyWith(blinkWindowMs: v.round())),
                          _s(cfg, 'Zufahren', 'Wie schnell das Lid schliesst',
                              cfg.blinkCloseMs.toDouble(), 40, 600, '${cfg.blinkCloseMs} ms',
                              (v) => cfg.copyWith(blinkCloseMs: v.round())),
                          _s(cfg, 'Geschlossen bleiben', 'Pause bei geschlossenem Auge',
                              cfg.blinkHoldMs.toDouble(), 0, 1500, '${cfg.blinkHoldMs} ms',
                              (v) => cfg.copyWith(blinkHoldMs: v.round())),
                          _s(cfg, 'Aufgehen', 'Wie schnell das Lid wieder oeffnet',
                              cfg.blinkOpenMs.toDouble(), 40, 600, '${cfg.blinkOpenMs} ms',
                              (v) => cfg.copyWith(blinkOpenMs: v.round())),

                          const Padding(
                            padding: EdgeInsets.fromLTRB(8, 8, 8, 0),
                            child: Text(
                              'Wird das Blinzeln laenger als sein Zeitfenster, hebt das Auge '
                              'das Fenster selbst an und meldet den korrigierten Wert zurueck.',
                              style: TextStyle(fontSize: 12, color: Colors.white38),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Diese Einstellungen gelten fuer beide Augen gemeinsam - nur so '
                      'blinzeln sie gleichzeitig und blicken in dieselbe Richtung.',
                      style: TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _preset(EyeBle ble, int index, String label, IconData icon) {
    return Expanded(
      child: FilledButton.tonalIcon(
        onPressed: ble.locked ? null : () {
          _preview = null;      // die Firmware meldet gleich den neuen Stand
          ble.applyAnimPreset(index);
        },
        icon: Icon(icon, size: 18),
        label: Text(label, overflow: TextOverflow.ellipsis),
      ),
    );
  }

  Widget _s(AnimCfg cfg, String title, String hint, double value, double min,
      double max, String label, AnimCfg Function(double) build,
      {int? divisions}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(label, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          Slider(
            min: min, max: max, divisions: divisions,
            value: value.clamp(min, max),
            activeColor: kAccent,
            // Live aufs Auge, aber ohne Flash-Schreiben - gespeichert wird erst
            // beim Loslassen.
            onChanged: widget.ble.locked ? null : (v) => _live(build(v)),
            onChangeEnd: (v) { _preview = build(v); _commit(); },
          ),
          Text(hint, style: const TextStyle(fontSize: 12, color: Colors.white38)),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String text;
  const _GroupLabel(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 2),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 12, letterSpacing: 1.2, color: kAccentGlow,
                fontWeight: FontWeight.w700)),
      );
}
