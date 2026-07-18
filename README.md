# EyePair App

Flutter-App zur Steuerung des ESP32-S3-LCD-1.28 Augen-Paars via BLE (240x240-Displays,
Master↔Slave-Sync über Kabel). Cloud-Augen werden als 240x240-RGB565-Bilder hochgeladen.
Optionaler Zugangsschutz per 6-stelligem Code (in der Firmware aktivierbar).

## Erstes Setup

Flutter SDK ≥ 3.4 muss installiert sein (https://docs.flutter.dev/get-started/install).

```bash
cd eye_pair_app
flutter create .          # erzeugt android/, ios/, web/, etc. Templates
flutter pub get           # installiert flutter_blue_plus + permission_handler
```

Nach `flutter create .` müssen die folgenden Plattform-Files angepasst werden — sonst funktioniert BLE nicht.

## Android-Berechtigungen

In `android/app/src/main/AndroidManifest.xml` direkt unter dem `<manifest>` Tag einfügen:

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN"
    android:usesPermissionFlags="neverForLocation"
    tools:targetApi="s" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

Und im `<manifest>` Tag selbst: `xmlns:tools="http://schemas.android.com/tools"` ergänzen.

In `android/app/build.gradle`: `minSdkVersion 21` setzen (sonst geht flutter_blue_plus nicht).

## iOS-Berechtigungen

In `ios/Runner/Info.plist` ergänzen:

```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>EyePair benoetigt Bluetooth um sich mit den Augen-Modulen zu verbinden.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>EyePair benoetigt Bluetooth um sich mit den Augen-Modulen zu verbinden.</string>
```

## Bauen + Installieren

### Android (einfach)

```bash
flutter build apk --release
# APK liegt in build/app/outputs/flutter-apk/app-release.apk
# Per USB/Email auf Telefon, "Installation aus unbekannten Quellen erlauben"
```

### iOS ohne $99 Developer Account (Sideloading)

**Variante A — mit Mac + Xcode (empfohlen):**
1. `flutter build ios --release --no-codesign`
2. `open ios/Runner.xcworkspace`
3. In Xcode: Runner-Target → Signing & Capabilities → "Add Account" mit Apple-ID
4. "Team" auf Personal Team setzen
5. Bundle Identifier auf etwas einzigartiges setzen, z.B. `com.deinname.eyepair`
6. iPhone per USB anschliessen → "Run" Button drücken → App installiert
7. iPhone: Einstellungen → Allgemein → VPN & Geräteverwaltung → eigenes Profil vertrauen
8. **Limit: App ist 7 Tage gültig**, dann erneut über Xcode installieren

**Variante B — ohne Mac:**
1. Sideloadly (Windows/macOS/Linux) herunterladen: https://sideloadly.io/
2. .ipa irgendwo bauen lassen (z.B. Codemagic, GitHub Actions, kostenfrei für kleine Projekte)
3. Sideloadly: Apple-ID eingeben, .ipa per Drag&Drop → installiert auf iPhone

Beide Wege haben die 7-Tage-Beschränkung weil kostenlose Apple-ID keine Long-Term-Signierung erlaubt.

## Verwendung

1. ESPs einschalten — Master zeigt seinen Namen (z.B. `Augen Thomas`) als BLE-Geraet
2. App starten → Scan automatisch
3. Geraet antippen → verbindet; der Zugangscode (Standard **123456**) wird automatisch
   gesendet. Passt er, ist die Steuerung freigeschaltet.
4. Tabs:
   - **Augen**: Grid mit Designs, Antippen wechselt Master+Slave
   - **Einstellungen**: Animation an/aus; **Zugang** (Status + Code eingeben) und
     **Zugangscode aendern** (neuen 6-stelligen Code fuer dieses Augenpaar setzen)
   - **Diagnose**: Live-Status

Der **Admin-Key** (fest in der Firmware) verbindet auf alle Augenpaare — einfach als Code
eingeben, falls der geraetespezifische Code unbekannt ist.

## Bei Problemen

- **Kein EyePair sichtbar**: Master neu booten, im Serial-Log nach `BLE GATT bereit` schauen
- **Connect failed**: BLE-Cache von Telefon leeren (Einstellungen → Bluetooth → Geraet vergessen)
- **Nicht autorisiert**: In den Einstellungen unter „Zugang" den richtigen 6-stelligen Code
  eingeben (Standard 123456, oder den Admin-Key)
