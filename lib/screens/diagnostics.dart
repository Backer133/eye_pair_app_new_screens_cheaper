import 'package:flutter/material.dart';
import '../ble_service.dart';

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
          padding: const EdgeInsets.all(16),
          children: [
            _bigCard(
              icon: linked ? Icons.cable : Icons.link_off,
              color: linked ? Colors.green : Colors.orange,
              title: 'Zweiter Screen',
              value: linked ? 'Verbunden' : 'Nicht verbunden',
              sub: linked
                  ? 'Slave meldet sich ueber das Kabel'
                  : 'Kein Lebenszeichen - Kabel pruefen oder Slave stromlos',
            ),
            _row(Icons.remove_red_eye, 'Augenpaar',
                 ble.deviceName.isEmpty ? '--' : ble.deviceName),
            _row(Icons.image, 'Aktuelles Auge',
                 ble.eyeId < kEyeLabels.length ? kEyeLabels[ble.eyeId] : '?'),
            _row(Icons.animation, 'Animation',
                 ble.animEnabled == 1 ? 'an' : 'aus'),
            if (ble.authSupported)
              _row(ble.authorized ? Icons.lock_open : Icons.lock, 'Zugang',
                   ble.authorized ? 'autorisiert' : 'gesperrt'),
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
            Icon(icon, size: 48, color: color),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(value,
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: color)),
                  if (sub != null)
                    Text(sub, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Card(
      child: ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(value,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
