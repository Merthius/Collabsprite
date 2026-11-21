# Review und Prüfstand 0.13.0

21. November 2026 · Windows · Aseprite 1.3.18.6 · lokale Prüfung der Beta

Geprüft wurden insbesondere Sitzungszustände und Lebenszyklus, Netzwerk-/Notizvalidierung, Synchronisation und eigenes Undo/Redo, asynchrone Skizzen, native Dialoge, Paketierung und Updates. Die Änderungen und Bedienung beschreibt der [Versionshinweis](releases/v0.13.0.md). Dieser Prüfstand belegt die genannten Szenarien, keine vollständige Fehlerfreiheit oder vollständige Aseprite-Funktionsparität.

| Prüfung | Ergebnis |
| --- | --- |
| Server-/Datentests | 75 bestanden, 0 fehlgeschlagen, 0 übersprungen |
| Native Batchsuite | 21 Prüfskripte bestanden; separate Profile und eigene Testbilder |
| Native Host-/Gast-Dokumente über echten WebSocket-Server | Frames, Gruppen, Links, Tags, Canvas, eigenes Undo/Redo, paralleles Malen, Konflikte und Löschen bestanden |
| Paketstart ohne globales Node | Bestanden mit enthaltener Runtime |
| Host-Lebenszyklus | Normales und erzwungenes Ende echter Aseprite-Prozesse sichern bestätigte Arbeit und geben TCP/UDP frei |
| Startabbruch | Timeout/Exit/Doppelstart sowie erhaltenes Abbruchsignal und Quittierung durch einen spät gestarteten Worker geprüft |
| Update | Versionen, Paketidentität/-Pfade/-Hash, Sicherungen und gesperrte Dateien bestanden |
| Windows-Bildimporthelfer | IDataObject/Mehrfachdateien/Drop-Daten und atomare Mailbox unter Windows PowerShell 5.1 bestanden |
| Sichtbare Oberfläche | Erstellen, Beitreten, aktive Sitzung und Trennen in separatem 400-%-Aseprite-Profil geprüft; Netzwerkzustände der GUI-Fixture simuliert |
| Abhängigkeiten | `npm audit --omit=dev --audit-level=moderate`: keine gemeldeten Schwachstellen |

Zusätzliche Regressionen decken acht gleichzeitig auffindbare Räume mit langen Unicode-Namen, ungültige Notizzeichen, fehlerhafte Suchantworten, Adapter-Duplikate, Empfangsbudget, erhaltene manuelle Dialoggröße und mehrere Skizzenstriche bei verzögerter Bestätigung ab. Ein laufender Strich darf nicht vor dem Loslassen übertragen oder durch ein älteres Häkchen verworfen werden.

Die alte native Dokument-Testbrücke überschritt durch viele einzelne curl-Prozessstarts das 180-s-Limit. Eine private sequenzierte Dateimailbox führt dieselben Szenarien mit echten WebSockets in rund sieben Sekunden aus. **Nur der Testtransport wurde verändert.** Der ältere Einfenster-/Batch-Starter brauchte vor seiner Korrektur 13,69 bzw. 5,41 Sekunden; nach einer Prozessmomentaufnahme statt mehrerer WMI-Abfragen wurden 0,57 und im Abschlusslauf 1,87 Sekunden gemessen. Die reguläre Mehrfenster-UI löst den Besitzer weiterhin im Hintergrund auf. Diese lokalen Messungen sind keine garantierten Laufzeiten auf anderen PCs.

## Paket

Ein gemeinsamer Host-/Gast-Installer, Protokoll 14 / Notizformat 9 unverändert. 65 Archiveinträge, 43 Quellfiles bytegleich, Rootmanifest zuerst; keine privaten Sitzungs- oder Testdaten enthalten.

- Datei: `Collabsprite.aseprite-extension`
- Version: `0.13.0`
- Größe: `36.234.808` Byte
- SHA-256: `65D3C6DF25812C013FD1B49B9E8766E4C6A0E2244D519138E19C9279C8B7ACAD`

Die Prüfsumme oben gehört zum [Installer der Beta 0.13.0](https://github.com/Merthius/Collabsprite/releases/download/v0.13.0/Collabsprite.aseprite-extension).

## Noch im praktischen Einsatz prüfen

Zwei physische PCs über LAN/Radmin, lange Sitzungen, der historische Stack-overflow auf dem konkreten Gast-PC, Grafiktablett, echte Explorer-/Picker-Gesten und Windows Snap Assist bleiben offen. Die Netzwerkprüfungen auf dem lokalen LAN-/Radmin-Adapter ersetzen diese Gerätekombinationen nicht. Nicht bestätigte Entwürfe sind nicht gegen einen harten Programmabsturz abgesichert. Native Bild-, JSON- und Transaktionsschritte bleiben unteilbar. Gast-Speichersperren sind Bedienregeln und kein DRM.
