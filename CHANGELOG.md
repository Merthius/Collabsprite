# Changelog

## 0.6.0 beta — 2026-09-25

- Löschen einzelner oder mehrerer ausgewählter Frames und Ebenen (einschließlich einer vorhandenen Gruppe samt Unterebenen) wird an alle Teilnehmenden übertragen. Überlebende Cels und persönliche Pixel-Verläufe werden neu zugeordnet.
- Layer duplizieren sowie Ebenenname, Sichtbarkeit, Sperre, Deckkraft, Mischmodus und durchgehende Cels; Frame-Dauer, Cel-Deckkraft/Z-Index und die erste Palette werden synchronisiert.
- Der Beitritt erscheint kurz als Aseprite-Statushinweis. Die geplante Übertragung fremder Mauszeiger wurde auf Wunsch verworfen.
- Protokoll 3 sichert indexbezogene Aktionen gegen veraltete Ebenen-/Frame-Nummern ab. Nicht kompatibel mit 0.5.0: Alle Teilnehmenden müssen dieselbe Version installieren.
- Automatisierte Server-/Protokolltests und ein nativer Aseprite-Test mit zwei Verbindungen bestanden. Ein realer Zwei-PC-Test im LAN/Radmin-Netz bleibt offen.

## 0.5.0 beta — 2026-09-24

- Eine einzige kompakte Oberfläche für Erstellen/Beitreten ohne lokale oder Radmin-Moduswahl.
- Direkte Zusammenarbeit zwischen PCs im selben LAN ohne Radmin; über verschiedene Netzwerke derselbe Ablauf mit gemeinsamem Radmin VPN.
- Einladungscode enthält verfügbare LAN-/VPN-Adressen; der Gast prüft sie im Hintergrund und verbindet sich mit der erreichbaren Adresse. Die Einladung kann nach VPN-Start erneut kopiert werden.
- Sitzungssuche fragt lokale Subnetz-Broadcasts und Radmin ab. Firewall-Freigabe auf privaten/Domain-Netzen für das lokale Subnetz ergänzt.
- Protokoll 2: Version 0.5.0 ist nicht mit alten 0.4.2-Sitzungen kompatibel. Alle Teilnehmenden müssen aktualisieren.
- Automatisierter Test über die LAN-Adresse eines Rechners ergänzt; Zwei-PC-Test und Radmin-Ende-zu-Ende-Prüfung stehen noch aus.

## 0.4.2 beta — 2026-09-24

- Lokales Erstellen blockiert die Aseprite-Oberfläche nicht mehr: der noch synchrone Ausgabe-Pipe-Aufruf wurde durch einen kurzlebigen Script-Host-Starter ersetzt.
- Host und Gast nutzen dieselbe installierbare Datei; getrennte kompakte Ansichten für Erstellen und Beitreten.
- Lokal-Modus im sichtbaren Aseprite 1.3.18.6 bis zum Status „Verbunden“ geprüft. 9/9 automatisierte Node-Tests bestanden.
- Globaler Zwei-PC-/Radmin-geschlossen-/UAC-Ablauf bleibt Beta und ist noch nicht vollständig geprüft.

Earlier development notes are summarized in the [technical notes](docs/technical-notes.md); the Git history begins with this public beta.
