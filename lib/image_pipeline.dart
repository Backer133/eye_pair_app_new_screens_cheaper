// PNG -> 320x320 RGB565 Konvertierung fuer Cloud-Eye-Upload via BLE.
// Zielgeraet: ESP32-S3-LCD-1.28 (GC9A01, 240x240-Display). Die Bilder sind bewusst
// oversized (320 auf 240, OLED-Prinzip): zentriert ragen sie ueber den Displayrand,
// damit weder Ausrichtung noch Blickbewegung einen leeren Rand erzeugen - 1:1 wie
// die eingebauten Default-Augen. Der Ueberschuss muss halbe sichtbare Hoehe PLUS
// vertikalen Ausschlag abdecken; bei 280 reichte er dafuer nicht.
// Byte-Reihenfolge: big-endian (high-byte zuerst) - passt zu den Default-Augen
// (LV_COLOR_16_SWAP=1) und zum Firmware-Flush mit swap=false.

import 'dart:typed_data';
import 'package:image/image.dart' as img;

const int kEyeWidth  = 320;
const int kEyeHeight = 320;
const int kRgb565ByteCount = kEyeWidth * kEyeHeight * 2;  // 204800 Bytes

/// So gross wird das Auge selbst gezeichnet. Der Rest der 320er-Leinwand ist
/// fortgesetzter Rand. Wuerde man stattdessen auf volle 320 skalieren, waeren
/// Cloud-Augen 14 % groesser als die eingebauten - und die einmal gemachte
/// Ausrichtung wuerde je nach gewaehltem Auge nicht mehr passen.
const int kEyeContent = 280;

/// Decodiert PNG/JPG, skaliert das Auge auf 280x280 und legt es mittig auf eine
/// 320x320-Leinwand, deren Rand aus den Randpixeln fortgesetzt wird. Ergebnis als
/// RGB565, big-endian.
Uint8List pngToRgb565(Uint8List pngBytes) {
  final src = img.decodeImage(pngBytes);
  if (src == null) {
    throw Exception('PNG/JPG konnte nicht dekodiert werden');
  }
  final content = (src.width != kEyeContent || src.height != kEyeContent)
      ? img.copyResize(src, width: kEyeContent, height: kEyeContent,
                       interpolation: img.Interpolation.linear)
      : src;

  // Leinwand mit fortgesetztem Rand: jedes Pixel ausserhalb des Inhalts uebernimmt
  // den naechstgelegenen Inhaltsrand (Clamp). Bei den Augen ist das die gleichmaessige
  // helle Sklera, der Uebergang faellt deshalb nicht auf.
  final pad = (kEyeWidth - kEyeContent) ~/ 2;
  final resized = img.Image(width: kEyeWidth, height: kEyeHeight);
  for (int y = 0; y < kEyeHeight; y++) {
    final sy = (y - pad).clamp(0, kEyeContent - 1);
    for (int x = 0; x < kEyeWidth; x++) {
      final sx = (x - pad).clamp(0, kEyeContent - 1);
      resized.setPixel(x, y, content.getPixel(sx, sy));
    }
  }

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
