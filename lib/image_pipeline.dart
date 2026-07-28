// PNG -> 280x280 RGB565 Konvertierung fuer Cloud-Eye-Upload via BLE.
// Zielgeraet: ESP32-S3-LCD-1.28 (GC9A01, 240x240-Display). Die Bilder sind bewusst
// oversized (280, OLED-Prinzip): zentriert ragen sie ueber den Displayrand, damit bei
// der Gaze-Bewegung kein weisser Rand entsteht - 1:1 wie die eingebauten Default-Augen.
// Byte-Reihenfolge: big-endian (high-byte zuerst) - passt zu den Default-Augen
// (LV_COLOR_16_SWAP=1) und zum Firmware-Flush mit swap=false.

import 'dart:typed_data';
import 'package:image/image.dart' as img;

const int kEyeWidth  = 280;
const int kEyeHeight = 280;
const int kRgb565ByteCount = kEyeWidth * kEyeHeight * 2;  // 156800 Bytes

/// Decodiert PNG/JPG, resized auf 240x240, konvertiert zu RGB565 LE.
/// Bild wird unveraendert uebertragen - keine Hintergrund-Konvertierung.
/// Tipp: PNG bitte direkt mit weissem Hintergrund hochladen (Display ist weiss).
Uint8List pngToRgb565(Uint8List pngBytes) {
  final src = img.decodeImage(pngBytes);
  if (src == null) {
    throw Exception('PNG/JPG konnte nicht dekodiert werden');
  }
  final resized = (src.width != kEyeWidth || src.height != kEyeHeight)
      ? img.copyResize(src, width: kEyeWidth, height: kEyeHeight, interpolation: img.Interpolation.linear)
      : src;

  final out = Uint8List(kRgb565ByteCount);
  int o = 0;
  for (int y = 0; y < kEyeHeight; y++) {
    for (int x = 0; x < kEyeWidth; x++) {
      final p = resized.getPixel(x, y);
      final r = p.r.toInt();
      final g = p.g.toInt();
      final b = p.b.toInt();

      final r5 = (r >> 3) & 0x1F;
      final g6 = (g >> 2) & 0x3F;
      final b5 = (b >> 3) & 0x1F;
      final v = (r5 << 11) | (g6 << 5) | b5;
      // big-endian (High-Byte zuerst): passt zur Byte-Reihenfolge der Default-Augen
      // (LV_COLOR_16_SWAP=1) und zum Display-Flush mit swap=false. Sonst byte-vertauscht
      // -> Cloud-Auge erscheint als buntes Rauschen ("1000 Striche").
      out[o++] = (v >> 8) & 0xFF;
      out[o++] = v & 0xFF;
    }
  }
  return out;
}
