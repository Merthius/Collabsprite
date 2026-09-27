# Effizienter gemeinsam zeichnen – 0.10.0 Beta

Enthält die in 0.9.0 entwickelten Funktionen. Host und Gäste brauchen
denselben neuen Installer: **0.10.0 verwendet Protokoll 7**, nicht Protokoll 5.
Die normalen Aseprite-Menüs und die Timeline bleiben die Bedienoberfläche.

| Gemeinsam bearbeiten | Bedienung in Aseprite |
| --- | --- |
| Ebenen und Gruppen | Anlegen, duplizieren, in Gruppen verschieben oder per Timeline umsortieren |
| Animationsframes | An der gewählten Stelle einfügen, verschieben, umkehren oder löschen |
| Verknüpfte Cels | Cels auswählen und verknüpfen/lösen; Zeichnen ändert die verknüpften Frames gemeinsam |
| Animationstags | Bereiche wie „Idle“ oder „Laufen“ inklusive Name, Farbe, Richtung und Wiederholungen bearbeiten |
| Arbeitsfläche und Bild | Vergrößern, zuschneiden, Größe ändern und Rasterebenen zusammenführen |
| Persönliches Rückgängig | `Strg+Z` / `Strg+Y` auch für eigene Ebenen-, Frame-, Tag- und Eigenschaftsänderungen |

## Was passiert bei gleichzeitigen Änderungen?

Unveränderte Teile kommen immer vom aktuellen Serverstand. Eine Ebenenumordnung
überschreibt deshalb nicht den Strich, den jemand inzwischen gesetzt hat.
Ebenen und Frames haben feste Kennungen, unabhängig von ihrer Position.

Wenn zwei Änderungen denselben Inhalt unvereinbar ändern, bleibt die Sitzung
verbunden. Die abgewiesene lokale Fassung wird in einem zusätzlichen Tab
**„Collabsprite – nicht synchronisierte Fassung“** erhalten. Ein kurzer Hinweis
erklärt den Konflikt. Nicht vorschnell schließen: mit dem Host vergleichen.
Auch für solche Gast-Tabs gilt die bisherige normale Speicher-/Exportsperre;
sie ist weiterhin kein Kopierschutz.

Eigene Struktur-Rücknahmen werden abgewiesen, wenn sie neuere fremde Beiträge
entfernen würden — etwa eine selbst angelegte Ebene löschen, auf der inzwischen
jemand anderes malt. Bei Zusammenführen oder Größenänderungen kann man ältere
Pixelaktionen erst wieder rückgängig machen, nachdem der betreffende Umbau
rückgängig gemacht wurde. Der eigene Verlauf bleibt flüchtig und begrenzt.

Eine bestätigte Strukturänderung ersetzt nicht die Ideenwand. Notizen und ihr
eigener Verlauf bleiben davon unabhängig.

## Bewusste Grenzen

- RGB/RGBA-Rasterebenen, maximal 1024 × 1024 Pixel, 32 Ebenen inklusive Gruppen,
  120 Frames, 4.194.304 Cel-Pixel und 256 Animationstags.
- Verknüpfte Cels müssen **dieselbe Position** haben. Unterschiedlich versetzte
  Cels mit gemeinsamem Bild zuerst in Aseprite entknüpfen. Sie werden nicht
  stillschweigend als unabhängige Kopien übertragen.
- Tilemaps, Referenzebenen, Farbmoduswechsel, Slices, Farbprofile und animierte
  Paletten gehören nicht zu dieser Erweiterung des Synchronisationsmodells.
- Auswahl, aktiver Frame, Zoom und Farbauswahl bleiben persönliche Ansichten.
  Übertragen werden abgeschlossene Aktionen, keine Vorschau während eines Strichs.
- Ein Netzabbruch genau während einer noch unbestätigten Strukturänderung
  behält die lokale Fassung und beendet den Abgleich vorsichtig. Nicht blind
  erneut anwenden. Normale kurze Pixel-Verbindungsabbrüche können weiter resumieren.
- Der persönliche Verlauf enthält bis 256 jüngere Aktionen; Pixel- und
  Struktur-Speicherbudgets können ältere Einträge früher entfernen. Fremde
  neuere Änderungen haben Vorrang vor einer unsicheren Rücknahme.

## Prüfung

`npm test` prüft unter anderem atomare Konflikte, persönliche Rücknahmen,
Metadaten-ABA (fremdes Ändern und Zurückändern), Links, Tags, Gruppierung,
Reihenfolge, Löschen, Canvas-Größe und Zusammenführen.

`test/structure.lua` prüft die echten nativen Aseprite-Objekte.
`node test/native-document.mjs` verbindet zwei native Client-Controller und
Sitzungsbilder über den Produktions-WebSocket-Server. Der Batch-Test nutzt
eine nur während des Tests laufende Loopback-Brücke zum Pumpen der Sockets.
Er prüft auch gleichzeitiges Zeichnen, Konfliktkopien und beidseitiges Undo.
Das ist **kein Test auf zwei physischen PCs**; LAN/Radmin-Langzeittests bleiben offen.

API-Grundlagen: [Ebenen](https://www.aseprite.org/api/layer),
[Frames](https://www.aseprite.org/api/frame),
[Cels](https://www.aseprite.org/api/cel) und
[Animationstags](https://www.aseprite.org/api/tag).
