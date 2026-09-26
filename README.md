<img src="branding/collabsprite-icon.svg" width="96" height="96" alt="Collabsprite-Logo: zwei farbige Pixel-Hälften ergeben ein gemeinsames Herz">

# Collabsprite

[![Version](https://img.shields.io/badge/version-0.6.5%20beta-7c5cff)](https://github.com/Merthius/Collabsprite/releases/tag/v0.6.5) [![Windows](https://img.shields.io/badge/platform-Windows-2575d0)](#voraussetzungen) [![MIT](https://img.shields.io/badge/license-MIT-31a67a)](LICENSE) [![Tests](https://github.com/Merthius/Collabsprite/actions/workflows/tests.yml/badge.svg)](https://github.com/Merthius/Collabsprite/actions/workflows/tests.yml)

**Gemeinsam Pixel-Art und Animationen direkt in Aseprite bearbeiten.** Eine Person hostet, die anderen treten bei. Alle nutzen dieselbe Erweiterung und dieselben Rasterebenen und Frames. `Strg+Z`/`Strg+Y` wirken auf die eigenen synchronisierten Pixelaktionen, ohne neuere fremde Pixel zu entfernen.

**[⬇ Collabsprite für Aseprite herunterladen](https://github.com/Merthius/Collabsprite/releases/download/v0.6.5/Collabsprite.aseprite-extension)** · [English guide](README.en.md) · [Probleme & Grenzen](#probleme-und-grenzen)

Version **0.6.5 Beta** enthält alles für **Erstellen und Beitreten in einer Datei**, einschließlich der Host-Laufzeit für Windows x64. Eine separate Node.js-Installation ist nicht erforderlich. Die Paketierung ist korrigiert: Aseprite erkennt jetzt Collabsprite statt versehentlich die enthaltene Bibliothek „ws“. Updates von Entwicklungsständen funktionieren ebenfalls.

Die **Diagnosekonsole ist dauerhaft enthalten**: **Ansicht → Collabsprite → Diagnosekonsole → Protokoll kopieren**. Das lokale Protokoll unter `%TEMP%\Collabsprite-debug.log` bleibt nach einem Neustart erhalten und ist auf 512 KiB begrenzt. Es enthält technische Ereignisse und Fehler, keine Bilddaten oder Einladungscodes. **Neues Protokoll** leert die Aufnahme; nur **vor** dem erneuten Auslösen eines Fehlers verwenden. Schutz gegen wiederholte Timer-Aufrufe während Freigabedialogen wurde ergänzt. Ob dies den gemeldeten „C stack overflow“ auf dem betroffenen Freund-PC behebt, bleibt dort zu prüfen.

## Schnellstart

![Schematischer Schnellstart: installieren, Sitzung erstellen, beitreten](docs/quick-start.svg)

*Die Grafik zeigt den Ablauf schematisch; sie ist kein Screenshot der Aseprite-Oberfläche.*

> [!IMPORTANT]
> Collabsprite ist eine **Beta für Windows**. Die direkte LAN-Verbindung wurde mit zwei Clients über die LAN-Adresse eines Rechners automatisiert geprüft; ein Ende-zu-Ende-Test mit zwei verschiedenen PCs, Radmin VPN, Firewall-Freigabe und nativer Aseprite-Oberfläche steht noch aus. Speichert eure Arbeit zusätzlich regelmäßig als `.aseprite`-Datei.

## Voraussetzungen

| | Host | Gast |
| --- | --- | --- |
| Aseprite | Ja, getestet mit 1.3.18.6 | Ja |
| Diese Erweiterung | Ja | Ja, **dieselbe Version** |
| Windows 10/11 x64 | Ja, Host-Laufzeit enthalten | Ja |
| [Radmin VPN](https://www.radmin-vpn.com/) | Nur bei verschiedenen Netzwerken | Nur bei verschiedenen Netzwerken |

Keine Cloud-Anmeldung, kein externer Collabsprite-Server und keine separate Host-Erweiterung. Die Sitzung läuft auf dem **Host-PC** (Port `8766`). Es gibt **nur einen Ablauf**: Erstellen oder Beitreten. Im selben WLAN/LAN verbinden sich verschiedene PCs direkt, **ohne Radmin**. Über verschiedene Netzwerke treten beide zuerst demselben Radmin-VPN-Netz bei; danach funktionieren dieselben Schaltflächen. „Lokal“ meint hier die direkte Netzwerkverbindung, nicht zwei Aseprite-Fenster auf einem PC.

## Installation – auf jedem PC

1. Lade auf der [Release-Seite](https://github.com/Merthius/Collabsprite/releases/tag/v0.6.5) unter **Assets** die einzelne Datei **`Collabsprite.aseprite-extension`** herunter. Das automatisch angebotene „Source code (zip)“ ist **nicht** der Installer.
2. Öffne Aseprite → **Bearbeiten → Einstellungen → Erweiterungen → Erweiterung hinzufügen** und wähle die Datei. Ein Doppelklick auf die Datei kann ebenfalls funktionieren ([offizielle Aseprite-Anleitung](https://www.aseprite.org/docs/extensions/)).
3. Starte Aseprite neu. Öffne **Ansicht → Collabsprite → Server erstellen / beitreten**.

Für Host und Gäste gilt exakt dieselbe Installationsdatei. Du kannst jederzeit zwischen Erstellen und Beitreten wählen. Die enthaltene Node.js-Laufzeit (24.21.0) startet nur beim Hosten im Hintergrund.

### Eine ältere Version aktualisieren

1. Sitzungskopie speichern und die laufende Sitzung über **Trennen** beenden.
2. Die neue **`Collabsprite.aseprite-extension`** über **Erweiterung hinzufügen** auswählen und das Update von **pixelkollab-native / Collabsprite** auf **0.6.5** bestätigen. Die technische Kennung `pixelkollab-native` bleibt absichtlich gleich.
3. Aseprite auf **allen beteiligten PCs neu starten**. Unter **Ansicht → Collabsprite → Info** muss **0.6.5** stehen.

**„Update“** im Collabsprite-Menü lädt das geprüfte Paket nach Downloads; danach wird es wie oben installiert. Es installiert sich nicht stillschweigend selbst. Bei sehr alten oder fehlerhaften Builds das Paket direkt von dieser Seite laden.

Falls zuvor **„ws 8.21.3“** im Installationsdialog erschien: Das war ein Fehler unserer älteren Pakete. Installiere die korrigierte Datei erneut; ein vorhandener separater „ws“-Eintrag ist keine Collabsprite-Version. Nicht den Quellcode-ZIP verwenden.

## Sitzung erstellen – Host

1. Öffne in Aseprite ein **RGB-Bild**. Collabsprite erzeugt beim Start eine **Sitzungskopie**; das Original bleibt unangetastet.
2. Öffne **Ansicht → Collabsprite → Server erstellen / beitreten**, trage bei **Dein Name** einen Namen ein und wähle **Erstellen**.
3. Nur wenn ihr in **verschiedenen Netzwerken** seid: Starte Radmin VPN und tritt eurem gemeinsamen VPN-Netz bei.
4. Klicke **Sitzung erstellen**. Der Host-Server startet im Hintergrund. Warte auf **Aktive Sitzung: Verbunden**.
5. Klicke **Einladung kopieren** und sende den gesamten Code privat an deine Freunde. Der Code enthält erreichbare LAN- und gegebenenfalls Radmin-Adressen.

Radmin wird nicht automatisch geöffnet: Im LAN wird es nicht gebraucht, und für das VPN musst du selbst das richtige Netzwerk wählen. Beim ersten Start kann Windows eine einmalige Firewallfreigabe verlangen. Bestätige sie selbst; Collabsprite umgeht diese Abfrage nicht. Für direkte LAN-Verbindungen sollte Windows das Netzwerk als **Privat** einstufen.

## Sitzung beitreten – Gast

1. Installiere dieselbe Erweiterung, starte Aseprite neu und öffne **Ansicht → Collabsprite → Server erstellen / beitreten → Beitreten**. Ein eigenes Bild musst du dafür nicht öffnen.
2. Falls ihr nicht im selben LAN seid: Starte Radmin VPN und tritt demselben VPN-Netz wie der Host bei.
3. Füge den privaten **Einladungscode** ein und klicke **Beitreten**. Collabsprite probiert die enthaltenen Adressen der Reihe nach. Du kannst alternativ **Sitzungen suchen** verwenden; falls die Suche nichts zeigt, nutze den Einladungscode.
4. Warte auf **Verbunden** und zeichne in der neuen Sitzungskopie.

Der Einladungscode hat etwa die Form `192.168.1.10:8766,26.1.2.3:8766/RAUM/TOKEN`; ohne aktives Radmin fehlt die `26.…`-Adresse. Der ganze Code ist ein **Zugangsschlüssel**: nicht öffentlich posten oder in Issues/Screenshots zeigen. Wenn Radmin erst später gestartet wird, **Einladung kopieren** erneut anklicken.

## Gemeinsam arbeiten und speichern

- Normale Aseprite-Werkzeuge wie Stift, Radierer, Füllen und Formen sowie **abgeschlossene** Auswahl-, Einfüge- und Verschiebeaktionen werden geteilt. Während eines gehaltenen Pinselstrichs oder einer schwebenden Auswahl erscheint noch keine Live-Vorschau beim Gegenüber.
- Alle Teilnehmenden können über Aseprites normale Befehle Rasterebenen und Frames **am Ende** hinzufügen und vorhandene Ebenen kopieren. Einzelne und mehrere ausgewählte Ebenen/Frames können gelöscht werden; beim Löschen einer Gruppe verschwinden ihre Unterebenen. Ebenenname, Sichtbarkeit, Sperre, Deckkraft und Mischmodus sowie Frame-Dauer, Cel-Deckkraft/Z-Index und die erste Palette werden geteilt. Umordnen und manche komplexe Strukturänderungen bleiben gesperrt.
- `Strg+Z`/`Strg+Y` schalten nur die **eigenen synchronisierten Pixelaktionen** um. Fremde spätere Beiträge bleiben erhalten; neue Ebenen und Frames gehören nicht zu diesem Pixel-Verlauf.
- Speichere die Sitzungskopie über **Datei → Speichern unter** als `.aseprite`, damit Ebenen und Frames erhalten bleiben. Der Host legt zusätzlich automatische Sitzungs-Backups lokal im `data`-Ordner an; sie ersetzen kein eigenes Speichern. Ältere Sicherungen blockieren keinen neuen Hoststart; Collabsprite lädt die acht zuletzt geänderten Sitzungen und lässt ältere Dateien unangetastet.
- Wenn der Host das Sitzungsbild oder Aseprite schließt, wird der Hintergrundserver nach dem Backup beendet und Port `8766` wieder frei. Die Gäste werden getrennt und sollten ihre Sitzungskopie speichern.
- **Trennen** beendet die Verbindung. Nach einem Netzabbruch gibt es noch keine automatische Wiederverbindung oder Zusammenführung von Offline-Änderungen.

## So funktioniert es

```text
Gast-PC A ── LAN oder Radmin VPN ──┐
                                  ├── Host-PC: Collabsprite-Server ── Sitzungskopie + Backup
Gast-PC B ── LAN oder Radmin VPN ──┘
```

Der Host ordnet und prüft die Änderungen. Die Verbindung benutzt WebSocket **ohne eigene Ende-zu-Ende-Verschlüsselung**; nutzt deshalb nur ein vertrauenswürdiges LAN oder VPN. Ein privater Einladungscode schützt die Sitzung zusätzlich. Die Windows-Firewall erlaubt Port `8766` nur für den benötigten Node-Prozess, im **lokalen Subnetz** auf privaten/Domain-Netzen und für **Radmin-Adressen** (`26.0.0.0/8`).

## Probleme und Grenzen

| Problem | Prüfen |
| --- | --- |
| **Sitzung erscheint nicht** | Beide PCs im selben LAN oder Radmin-Netz? Sonst den vollständigen Einladungscode einfügen. VPN-Broadcast kann scheitern. |
| **Host startet nicht** | Aktuellen Installer erneut installieren, Aseprite neu starten und Diagnosekonsole öffnen; die Host-Laufzeit ist enthalten. |
| **Windows fragt nach Freigabe** | Beim ersten Start ist eine begrenzte Firewallregel nötig; die Abfrage selbst bestätigen. |
| **LAN-Gast erreicht den Host nicht** | Windows-Netzwerkprofil auf dem Host auf **Privat** prüfen; Host-Firewall und WLAN-Client-Isolation prüfen. |
| **„C stack overflow“ beim Beitreten** | Aktualisiere Host und Gäste auf dieselbe Version. Nach dem Fehler **Diagnosekonsole → Protokoll kopieren**; Aseprite-Version und genauen Schritt in einem [Issue](https://github.com/Merthius/Collabsprite/issues) ergänzen. |
| **Aseprite reagiert nicht** | Speichere ungesicherte Arbeit und melde den genauen Schritt in einem [Issue](https://github.com/Merthius/Collabsprite/issues). |
| **Verbindung weg** | Sitzungskopie speichern; Host/Netz prüfen und bewusst neu beitreten. Offline-Änderungen werden nicht automatisch gemischt. |

Unterstützt werden RGB/RGBA-Rasterebenen. Nicht vollständig synchronisiert werden u. a. Tilemaps, Referenzebenen, Tags, Slices, Farbprofile, verknüpfte Cels und animierte Paletten. Auswahl, Zoom und Farbauswahl sind persönliche Arbeitsansichten. Grenzen: maximal 8 Personen, 1024×1024 Pixel, 32 Ebenen, 120 Frames und 4.194.304 Cel-Pixel. **0.6.5 verwendet weiterhin Protokoll 3; 0.5.0-Sitzungen sind nicht kompatibel.** [Technische Details](docs/technical-notes.md).

## Entwickeln und beitragen

```powershell
npm ci
npm test
./build.ps1
```

Der Build legt den Installer im benachbarten Ordner `../output/` ab. `test/` enthält automatisierte Server-/Protokolltests und native Aseprite-Testskripte. Hinweise zu Fehlern und Pull Requests stehen in [CONTRIBUTING.md](CONTRIBUTING.md). **Sitzungsdateien aus `data/`, private Einladungscodes und Bilder gehören nie in ein öffentliches Issue oder einen Commit.**

Collabsprite steht unter der [MIT-Lizenz](LICENSE). Die mit dem Installer ausgelieferte `ws`-Bibliothek steht ebenfalls unter MIT; die unveränderte Node.js-Laufzeit enthält ihre vollständigen Lizenzhinweise in `runtime/LICENSE`. Dieses Community-Projekt ist nicht offiziell mit Aseprite oder Radmin VPN verbunden.

## Logo

Die türkise und die orange Hälfte ergeben zusammen ein Pixel-Herz – zwei Menschen, ein gemeinsames Bild. Für Discord und andere Projektlisten kannst du das [Logo als PNG (512 × 512)](branding/collabsprite-icon-512.png) oder als [skalierbare SVG](branding/collabsprite-icon.svg) verwenden. Das [GitHub-Vorschaubild](branding/collabsprite-social-preview.png) ist ebenfalls im Repository. Die Grafiken sind wie der Code MIT-lizenziert.
