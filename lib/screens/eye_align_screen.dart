import 'package:flutter/material.dart';

import '../ble_service.dart';
import '../theme.dart';

/// Richtet ein einzelnes Auge auf seine Maskenöffnung aus.
///
/// Die Bedienung folgt der tatsächlichen Situation: Man steht vor der Maske, hält das
/// Handy in einer Hand und schaut abwechselnd aufs Auge und aufs Display. Deshalb eine
/// Vorschau statt bloßer Zahlen, Schrittknöpfe neben jedem Regler, und die zwei
/// Einstellungen als nummerierte Schritte statt als gleichwertige Kästen.
///
/// Jede Maske ist handgeschnitzt, die Werte gelten deshalb je Auge — anders als die
/// Bewegung, die für beide identisch sein muss.
class EyeAlignScreen extends StatefulWidget {
  final EyeBle ble;
  const EyeAlignScreen({super.key, required this.ble});
  @override
  State<EyeAlignScreen> createState() => _EyeAlignScreenState();
}

class _EyeAlignScreenState extends State<EyeAlignScreen> {
  int _target = 0;               // 0 = Master, 1 = Slave
  bool _guides = true;           // beim Öffnen an: man will die Kante sehen
  int? _previewYOff;
  int? _previewVisH;

  static const int _minY = -60, _maxY = 60;
  static const int _minH = 60,  _maxH = 240;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.ble.setEyeGuides(true));
  }

  @override
  void dispose() {
    // Hilfslinien nie stehen lassen - ein grüner Strich im Gesicht fällt später auf.
    widget.ble.setEyeGuides(false);
    super.dispose();
  }

  int _yOff(EyeBle b) => _previewYOff ?? b.eyeYOff[_target];
  int _visH(EyeBle b) => _previewVisH ?? b.eyeVisH[_target];

  void _send(EyeBle b, {required bool persist}) =>
      b.setEyeGeom(_target, _yOff(b), _visH(b), persist: persist);

  void _stepY(EyeBle b, int delta) {
    setState(() => _previewYOff = (_yOff(b) + delta).clamp(_minY, _maxY));
    _send(b, persist: true);
    _previewYOff = null;
  }

  void _stepH(EyeBle b, int delta) {
    setState(() => _previewVisH = (_visH(b) + delta).clamp(_minH, _maxH));
    _send(b, persist: true);
    _previewVisH = null;
  }

  String _yLabel(int v) {
    if (v == 0) return 'Mitte';
    return v < 0 ? '${-v} nach oben' : '$v nach unten';
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.ble,
      builder: (context, _) {
        final ble = widget.ble;
        final yOff = _yOff(ble);
        final visH = _visH(ble);

        return Scaffold(
          appBar: AppBar(title: const Text('Augen ausrichten')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              // --- Auswahl + Blinken in einer Zeile: "welches Auge stelle ich ein" ---
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Master')),
                        ButtonSegment(value: 1, label: Text('Slave')),
                      ],
                      selected: {_target},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() {
                        _target = s.first;
                        _previewYOff = null;
                        _previewVisH = null;
                      }),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: ble.locked ? null : _identify,
                    icon: const Icon(Icons.lightbulb_outline),
                    tooltip: 'Dieses Auge blinken lassen',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- Vorschau: macht aus zwei Zahlen ein Bild ---
              Center(
                child: SizedBox(
                  width: 150, height: 150,
                  child: CustomPaint(painter: _EyePreview(yOff: yOff, visH: visH)),
                ),
              ),
              const SizedBox(height: 24),

              _step(
                number: '1',
                title: 'Auge mittig setzen',
                hint: 'Bis die Pupille mitten im Ausschnitt sitzt',
                value: _yLabel(yOff),
                raw: '$yOff px',
                sliderValue: yOff.toDouble(),
                min: _minY.toDouble(), max: _maxY.toDouble(),
                onChanged: (v) { setState(() => _previewYOff = v.round()); _send(ble, persist: false); },
                onChangeEnd: (v) { _previewYOff = v.round(); _send(ble, persist: true); _previewYOff = null; },
                onMinus: () => _stepY(ble, -2),
                onPlus:  () => _stepY(ble,  2),
              ),

              _step(
                number: '2',
                title: 'Ausschnitt anpassen',
                hint: 'Bis die dunklen Ränder hinter dem Holz verschwinden',
                value: '${(visH * 100 / 240).round()} % des Displays',
                raw: '$visH px',
                sliderValue: visH.toDouble(),
                min: _minH.toDouble(), max: _maxH.toDouble(),
                onChanged: (v) { setState(() => _previewVisH = v.round()); _send(ble, persist: false); },
                onChangeEnd: (v) { _previewVisH = v.round(); _send(ble, persist: true); _previewVisH = null; },
                onMinus: () => _stepH(ble, -2),
                onPlus:  () => _stepH(ble,  2),
              ),

              const SizedBox(height: 8),
              const Divider(),

              // --- Aktionszeile: Werkzeuge, keine eigenen Karten ---
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.straighten, color: kAccentGlow),
                title: const Text('Hilfslinien am Auge'),
                subtitle: const Text('Markiert die Kanten des Ausschnitts'),
                value: _guides,
                activeColor: kAccent,
                onChanged: (v) { setState(() => _guides = v); ble.setEyeGuides(v); },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restart_alt, color: kWarn),
                title: const Text('Auf Mitte zuruecksetzen'),
                subtitle: Text('Nur ${_target == 0 ? "Master" : "Slave"} - '
                               'das andere Auge bleibt unveraendert'),
                onTap: ble.locked ? null : () {
                  _previewYOff = null;
                  _previewVisH = null;
                  ble.resetEyeGeom(_target);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _identify() async {
    // Frueher zeigte der Master hier nur eine Textmeldung - beim Einbau in die Maske
    // braucht man das Blinken aber auf beiden Augen gleichermassen.
    if (_target == 0) {
      await widget.ble.identifySelf();
    } else if (widget.ble.isBound) {
      await widget.ble.identifySlave(widget.ble.boundMac);
    }
  }

  Widget _step({
    required String number,
    required String title,
    required String hint,
    required String value,
    required String raw,
    required double sliderValue,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
    required ValueChanged<double> onChangeEnd,
    required VoidCallback onMinus,
    required VoidCallback onPlus,
  }) {
    final locked = widget.ble.locked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Schrittnummer statt Icon: zeigt die Reihenfolge, die sonst niemand kennt.
              Container(
                width: 22, height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(number,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: kAccentGlow)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Text(value, style: const TextStyle(color: kAccentGlow, fontSize: 13)),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 32, top: 2),
            child: Text(hint,
                style: const TextStyle(fontSize: 12, color: Colors.white38)),
          ),
          Row(
            children: [
              IconButton(
                onPressed: locked ? null : onMinus,
                icon: const Icon(Icons.remove),
                tooltip: 'Feiner: 2 weniger',
              ),
              Expanded(
                child: Slider(
                  min: min, max: max,
                  value: sliderValue.clamp(min, max),
                  activeColor: kAccent,
                  onChanged: locked ? null : onChanged,
                  onChangeEnd: onChangeEnd,
                ),
              ),
              IconButton(
                onPressed: locked ? null : onPlus,
                icon: const Icon(Icons.add),
                tooltip: 'Feiner: 2 mehr',
              ),
              SizedBox(
                width: 46,
                child: Text(raw,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11, color: Colors.white30)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Schematische Vorschau des Auges: Kreis = Display, dunkle Balken = vom Holz verdeckt,
/// Punkt = Pupillenlage. Ersetzt die Vorstellungskraft, die zwei Pixelwerte sonst
/// verlangen würden.
class _EyePreview extends CustomPainter {
  final int yOff;
  final int visH;
  const _EyePreview({required this.yOff, required this.visH});

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final c = Offset(r, r);
    final scale = size.width / 240.0;      // Display ist 240 px breit

    // Displayfläche
    canvas.drawCircle(c, r, Paint()..color = kSurfaceHi);

    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: r)));

    // Auge: heller Kreis, um yOff verschoben
    final eyeC = Offset(r, r + yOff * scale);
    canvas.drawCircle(eyeC, r * 0.62, Paint()..color = const Color(0xFFDCE3F0));
    canvas.drawCircle(eyeC, r * 0.26, Paint()..color = kAccent);

    // Abdeckung oben und unten - genau die Balken, die auch das Gerät zeichnet
    final half = visH / 2.0;
    final topH    = ((120 + yOff - half) * scale).clamp(0.0, size.height);
    final bottomH = ((120 - yOff - half) * scale).clamp(0.0, size.height);
    final cover = Paint()..color = const Color(0xEE07080C);
    if (topH > 0)    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, topH), cover);
    if (bottomH > 0) {
      canvas.drawRect(
          Rect.fromLTWH(0, size.height - bottomH, size.width, bottomH), cover);
    }

    // Kanten des sichtbaren Bandes markieren
    final edge = Paint()
      ..color = kGood
      ..strokeWidth = 1.5;
    if (topH > 0)    canvas.drawLine(Offset(0, topH), Offset(size.width, topH), edge);
    if (bottomH > 0) {
      canvas.drawLine(Offset(0, size.height - bottomH),
                      Offset(size.width, size.height - bottomH), edge);
    }
    canvas.restore();

    canvas.drawCircle(c, r,
        Paint()..color = Colors.white10..style = PaintingStyle.stroke..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant _EyePreview old) =>
      old.yOff != yOff || old.visH != visH;
}
