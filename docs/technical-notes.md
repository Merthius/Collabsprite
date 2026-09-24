# Technische Hinweise / Technical notes

## Architektur

- Beide Seiten installieren dieselbe Aseprite-Erweiterung (`extension/`). Nur der Host startet `server.mjs` mit Node.js.
- Seit Version 0.5.0 gibt es einen einzigen sichtbaren Netzwerkablauf auf Port `8766`. Im selben LAN verbindet sich ein Gast direkt; über verschiedene Netzwerke dient Radmin VPN als virtuelles LAN. Die alte Loopback-Variante bleibt nur für isolierte automatisierte Tests, nicht als Benutzeroption.
- Die Erweiterung tauscht Sitzungsdaten über WebSocket mit dem Host aus. Der Host prüft Nachrichten, ordnet Operationen und hält einen autorbezogenen Verlauf für Pixel-Undo/Redo.
- Einladungen enthalten eine oder mehrere LAN-/VPN-Adressen, Raum-ID und Token. Der Gast wählt im Hintergrund eine erreichbare Adresse; der Token wird auf dem Server gehasht. **Den vollständigen Einladungscode vertraulich behandeln**.
- Der Host schreibt lokale JSON-Backups in `data/`. Dieser Ordner ist vom Repository ausgeschlossen. Bitte zusätzlich die Sitzungskopie regelmäßig als `.aseprite` speichern.

## Synchronisationsmodell

Die Synchronisierung geschieht nach abgeschlossenen Aktionen. Temporäre schwebende Cels und ein noch gehaltener Pinselstrich werden nicht als stabile Änderung verteilt. In Version 0.6.0 werden Rasterebenen und Frames angefügt, dupliziert bzw. einzeln oder in Auswahl gelöscht; das Löschen einer vorhandenen Gruppe entfernt ihre Unterebenen. Ebenenname, Sichtbarkeit, Sperre, Deckkraft, Mischmodus und durchgehende Cels, Frame-Dauer, Cel-Deckkraft/Z-Index sowie die erste Palette werden übertragen. Ebene/Frame-Nummern werden bei Löschungen neu zugeordnet; veraltete indexbezogene Nachrichten werden abgewiesen statt auf falsche Cels angewendet. Undo/Redo betrifft serverseitig weiterhin nur eigene Pixeloperationen, nicht Struktur- oder Metadatenänderungen. Mauszeiger und Namens-Tags anderer Teilnehmender werden nicht übertragen.

## Sicherheit und Grenzen

Collabsprite ist eine Beta, kein öffentlich erreichbarer Dienst. WebSocket hat hier keine eigene Ende-zu-Ende-Verschlüsselung. Nur in einem **vertrauenswürdigen LAN oder VPN** arbeiten und den Einladungscode privat teilen. Der Firewall-Helfer erlaubt TCP/UDP `8766` nur für den benötigten Node-Prozess: lokales Subnetz auf privaten/Domain-Netzen sowie Radmin-Adressen (`26.0.0.0/8`). Auch der Server prüft die Quelladresse. Windows-Freigaben müssen vom Nutzer bestätigt werden.

Maximalwerte: 8 Teilnehmende; 1024×1024 Bildpunkte; 32 Ebenen inklusive Gruppen; 120 Frames; 4.194.304 Cel-Pixel. Der persönliche Verlauf hält nur jüngere Pixelaktionen (bis 256 Aktionen bzw. etwa 500.000 Pixelbeiträge). Unterstützt sind RGB/RGBA-Rasterebenen; Tilemaps, Referenzebenen und Nicht-RGB-Dokumente nicht. Tags, Slices, Farbprofile, animierte Paletten und verknüpfte Cels werden nicht dauerhaft synchronisiert. Ebenen-Umordnung, neue Gruppen innerhalb einer Sitzung, Canvas-Größe sowie Änderungen am Farbmodus bleiben gesperrt. Auswahlrahmen, Zoom und aktive Farbauswahl sind persönliche Arbeitsansichten und werden nicht geteilt.

## Entwicklung und Tests

`npm ci` installiert die mitgelieferte `ws`-Abhängigkeit; `npm test` prüft Server, Protokoll und mehrere WebSocket-Clients. `./build.ps1` erstellt `../output/Collabsprite.aseprite-extension`. `test/bootstrap.ps1` prüft den Hintergrundstarter auf einem isolierten lokalen Testport. Native Aseprite-Tests liegen unter `test/*.lua` und benötigen eine lokale Aseprite-Installation.

Bislang bestätigt: früherer Ein-PC-Testaufbau mit Sitzungserstellung im sichtbaren Aseprite 1.3.18.6 und zwei lokalen Aseprite-Instanzen mit gegenseitigen Pixeln und eigenem Undo/Redo; außerdem Node-Protokolltests. In 0.5.0 kam ein automatisierter Verbindungstest über die echte LAN-Adresse dieses Rechners hinzu. Für 0.6.0 wurden automatisierte Tests und ein nativer Aseprite-Test mit zwei Verbindungen für einfaches und mehrfaches Löschen, persönlichen Pixel-Verlauf und Metadaten bestanden. Das beweist noch keine Zusammenarbeit über zwei physische PCs. Noch offen: durchgehender Zwei-PC-Test im direkten LAN und über Radmin VPN, VPN-Sitzungssuche, UAC-/Firewall-Ablauf sowie ein nativer Test mit lange gehaltenem Mausstrich.
