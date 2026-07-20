import 'package:flutter/material.dart';
import '../ble_service.dart';
import '../theme.dart';

class DiagnosticsScreen extends StatelessWidget {
  final EyeBle ble;
  const DiagnosticsScreen({super.key, required this.ble});

  @override
  Widget build(BuildContext context) {
    // Live aktualisieren, sobald der Master einen neuen Kabel-Status meldet.
    return ListenableBuilder(
      listenable: ble,
      builder: (context, _) {
        final linked = ble.slaveLinked;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const SectionHeader('Verbindung', icon: Icons.cable),
            _bigCard(
              icon: linked ? Icons.cable : Icons.link_off,
              color: linked ? kGood : kWarn,
              title: 'Zweiter Screen',
              value: linked ? 'Verbunden' : 'Nicht verbunden',
              sub: linked
                  ? 'Slave meldet sich ueber das Kabel'
                  : 'Kein Lebenszeichen - Kabel pruefen oder Slave stromlos',
            ),
            const SectionHeader('Zustand', icon: Icons.info_outline),
            _infoCard(
              rows: [
                _RowData(Icons.remove_red_eye, 'Augenpaar',
                    ble.deviceName.isEmpty ? '--' : ble.deviceName),
                _RowData(Icons.animation, 'Animation',
                    ble.animEnabled == 1 ? 'An' : 'Aus'),
                if (ble.authSupported)
                  _RowData(
                    ble.authorized ? Icons.lock_open : Icons.lock,
                    'Zugang',
                    ble.authorized ? 'Autorisiert' : 'Gesperrt',
                    pillColor: ble.authorized ? kGood : kWarn,
                  ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _bigCard({required IconData icon, required Color color,
                    required String title, required String value, String? sub}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: color.withOpacity(.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 32, color: color),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontSize: 13, color: Colors.white.withOpacity(.5))),
                  const SizedBox(height: 4),
                  Text(value,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, color: color)),
                  if (sub != null) ...[
                    const SizedBox(height: 4),
                    Text(sub,
                        style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(.45))),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoCard({required List<_RowData> rows}) {
    return Card(
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _row(rows[i]),
          ],
        ],
      ),
    );
  }

  Widget _row(_RowData d) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(d.icon, color: Colors.white54, size: 22),
      title: Text(d.label, style: const TextStyle(fontSize: 15)),
      trailing: d.pillColor != null
          ? StatusPill(d.value, color: d.pillColor!)
          : Text(d.value,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    );
  }
}

class _RowData {
  final IconData icon;
  final String label;
  final String value;
  final Color? pillColor;
  _RowData(this.icon, this.label, this.value, {this.pillColor});
}
