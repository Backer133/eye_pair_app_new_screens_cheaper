# Cloud-Augen

Neue Augenbilder einfach hier hineinlegen und pushen. Um die Vorschaubilder musst du
dich **nicht** kuemmern, die erzeugt GitHub selbst (siehe unten).

## Ein neues Auge hinzufuegen

1. **Bild erstellen** — PNG oder JPG, quadratisch. Die vorhandenen Augen sind
   1024 x 1024; kleiner geht, unter 320 x 320 wird es unscharf.
2. **Aussagekraeftig benennen**, z.B. `Drache.png`. **Keine Punkte im Namen** ausser
   der Dateiendung — der Name vor dem ersten Punkt ist der Anzeigename in der App.
3. **Committen und pushen:**
   ```bash
   git add cloud-eyes/Drache.png
   git commit -m "Neues Auge: Drache"
   git push
   ```
4. **Warten, bis GitHub das Vorschaubild erzeugt hat** (etwa eine Minute, siehe
   Reiter "Actions"). Danach in der App den Cloud-Bildschirm oeffnen und nach unten
   ziehen zum Aktualisieren.
5. **Herunterladen** antippen, Slot waehlen. Die Uebertragung laeuft in zwei Schritten:
   erst vom Handy zum Master, dann per Funk weiter zum zweiten Auge. Der Fortschritt
   wird angezeigt; das zweite Auge bestaetigt am Ende den Empfang.

## Vorschaubilder — laufen automatisch

In `thumbs/` liegen verkleinerte Fassungen (192 px, WebP, rund 5 KB je Auge). Die App
zeigt in der Liste diese statt der vollen Bilder.

**Das ist kein Schoenheitsdetail.** Ohne sie lud die App die vollen Augen herunter, nur
um daraus 56 x 56 Pixel grosse Vorschauen zu zeichnen: elf Augen mal 1,5 MB sind
16,3 MB bei *jedem* Oeffnen des Bildschirms. GitHub hat den Zugriff daraufhin gedrosselt
(HTTP 429 bzw. 503) — und weil Vorschau und Download an derselben URL haengen, fiel
beides gleichzeitig aus.

Erzeugt werden sie von `.github/workflows/thumbs.yml`, sobald ein Bild in diesem Ordner
dazukommt oder sich aendert. Der Ablauf schreibt das Ergebnis selbst zurueck.

Von Hand geht es auch — noetig ist das nur, wenn der Ablauf einmal fehlschlaegt:

```bash
pip install pillow
python cloud-eyes/make_thumbs.py
git add cloud-eyes/thumbs && git commit -m "Vorschaubilder neu erzeugt" && git push
```

Das Skript entfernt auch Vorschauen von Augen, die es nicht mehr gibt.

Fehlt zu einem Auge das Vorschaubild, zeigt die App ersatzweise das volle Bild. Es geht
also nichts kaputt — es wird nur wieder unnoetig viel geladen.

## Technisches Format

- **Ziel:** ESP32-S3-LCD-1.28 mit rundem GC9A01, 240 x 240 Pixel
- **Aufbereitung in der App:** Bild auf 280 x 280 skaliert und mittig auf eine
  320 x 320 grosse Flaeche gelegt. Der Rand wird nach aussen fortgesetzt, damit bei
  Blickbewegung und Maskenausrichtung nie ein leerer Rand sichtbar wird. Ein
  gleichmaessiger Bildrand (wie die helle Lederhaut) faellt dabei nicht auf, ein
  gemusterter schon.
- **Farbformat:** RGB565, High-Byte zuerst. Ergibt 204 800 Bytes je Auge.
- **Auf dem Geraet:** `/eyes/0X.bin` im LittleFS. Es gibt **4 Slots** — mehr passen
  nicht in die 917 504 Bytes grosse Partition.

## Tipps

- Kraeftige, kontrastreiche Augen wirken auf dem kleinen runden Display am besten.
- Die Pupille gehoert in die Bildmitte: die Feinausrichtung auf den Maskenschlitz
  passiert spaeter in der App, sie geht aber von einem mittigen Auge aus.
- Transparente Bereiche sind erlaubt, werden auf dem Geraet aber nicht transparent
  dargestellt — dort erscheint, was im Bild darunter gespeichert ist.
