# Technische Hinweise / Technical notes

## Architektur

- Beide Seiten installieren dieselbe Aseprite-Erweiterung (`extension/`). Nur der Host startet `server.mjs` mit Node.js.
- Im lokalen Modus bindet der Server an `127.0.0.1:8765`. Im Radmin-Modus nutzt er Port `8766`; der Host und alle Gäste müssen im selben Radmin-VPN sein.
- Die Erweiterung tauscht Sitzungsdaten über WebSocket mit dem Host aus. Der Host prüft Nachrichten, ordnet Operationen und hält einen autorbezogenen Verlauf für Pixel-Undo/Redo.
- Einladungen enthalten Adresse, Raum-ID und Token. Der Token wird auf dem Server gehasht; **den vollständigen Einladungscode vertraulich behandeln**.
- Der Host schreibt lokale JSON-Backups in `data/`. Dieser Ordner ist vom Repository ausgeschlossen. Bitte zusätzlich die Sitzungskopie regelmäßig als `.aseprite` speichern.

## Synchronisationsmodell

Die Synchronisierung geschieht nach abgeschlossenen Aktionen. Temporäre schwebende Cels und ein noch gehaltener Pinselstrich werden nicht als stabile Änderung verteilt. Neu angefügte Ebenen und Frames werden geteilt; Löschen/Umordnen und viele Metadatenänderungen sind während einer Sitzung nicht unterstützt. Undo/Redo betrifft serverseitig nur eigene Pixeloperationen, nicht Strukturänderungen.

## Sicherheit und Grenzen

Collabsprite ist eine Beta, kein öffentlich erreichbarer Dienst. WebSocket hat hier keine eigene Ende-zu-Ende-Verschlüsselung. Über verschiedene PCs nur mit einem **vertrauenswürdigen VPN** arbeiten und den Einladungscode privat teilen. Der globale Firewall-Helfer erlaubt TCP/UDP `8766` nur für Radmin-Adressen (`26.0.0.0/8`) und den benötigten Node-Prozess. Windows-Freigaben müssen vom Nutzer bestätigt werden.

Maximalwerte: 8 Teilnehmende; 1024×1024 Bildpunkte; 32 Ebenen inklusive Gruppen; 120 Frames; 4.194.304 Cel-Pixel. Der persönliche Verlauf hält nur jüngere Pixelaktionen (bis 256 Aktionen bzw. etwa 500.000 Pixelbeiträge). Unterstützt sind RGB/RGBA-Rasterebenen; Tilemaps, Referenzebenen und Nicht-RGB-Dokumente nicht. Tags, Slices, Farbprofile, animierte Paletten und verknüpfte Cels werden nicht dauerhaft synchronisiert. Augen/Schlösser, Auswahl, Zoom und Farbauswahl bleiben lokal.

## Entwicklung und Tests

`npm ci` installiert die mitgelieferte `ws`-Abhängigkeit; `npm test` prüft Server, Protokoll und mehrere WebSocket-Clients. `./build.ps1` erstellt `../output/Collabsprite.aseprite-extension`. `test/bootstrap.ps1` prüft den Hintergrundstarter auf einem isolierten lokalen Testport. Native Aseprite-Tests liegen unter `test/*.lua` und benötigen eine lokale Aseprite-Installation.

Bislang bestätigt: lokale Sitzungserstellung im sichtbaren Aseprite 1.3.18.6, zwei lokale Aseprite-Instanzen mit gegenseitigen Pixeln und eigenem Undo/Redo, Node-Protokolltests. Noch offen: durchgehender Zwei-PC-Test über Radmin VPN, VPN-Sitzungssuche, Start mit geschlossenem Radmin und UAC-Ablauf sowie ein nativer Test mit lange gehaltenem Mausstrich.
