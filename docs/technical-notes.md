# Technische Hinweise / Technical notes

## Architektur

- Beide Seiten installieren dieselbe Aseprite-Erweiterung (`extension/`). Nur der Host startet `server.mjs` mit der gebündelten Node.js-Laufzeit (Windows x64, 24.21.0). Eine globale Node-Installation wird im Release nicht benötigt.
- Seit Version 0.5.0 gibt es einen einzigen sichtbaren Netzwerkablauf auf Port `8766`. Im selben LAN verbindet sich ein Gast direkt; über verschiedene Netzwerke dient Radmin VPN als virtuelles LAN. Die alte Loopback-Variante bleibt nur für isolierte automatisierte Tests, nicht als Benutzeroption.
- Die Erweiterung tauscht Sitzungsdaten über WebSocket mit dem Host aus. Der Host prüft Nachrichten, ordnet Operationen und hält einen autorbezogenen Verlauf für Pixel-Undo/Redo.
- Einladungen enthalten eine oder mehrere LAN-/VPN-Adressen, Raum-ID und Token. Der Gast wählt im Hintergrund eine erreichbare Adresse; der Token wird auf dem Server gehasht. **Den vollständigen Einladungscode vertraulich behandeln**.
- Der Host schreibt lokale JSON-Backups in `data/`. Dieser Ordner ist vom Repository ausgeschlossen. Bitte zusätzlich die Sitzungskopie regelmäßig als `.aseprite` speichern.
- Seit 0.6.1 beendet sich ein automatisch gestarteter Host-Server, wenn die letzte Host-Verbindung schließt (Sitzungsbild geschlossen, Erweiterung beendet oder Aseprite geschlossen). Der Shutdown wartet auf laufende Backups; ein Server ohne jemals verbundenen Host beendet sich nach rund 30 Sekunden Leerlauf. Die Gäste werden beim Host-Ende getrennt.
- Seit 0.6.4 werden eingehende WebSocket-JSON-Nachrichten mit einem gebündelten, begrenzten Lua-Parser in normale Lua-Tabellen umgewandelt. Das umgeht Aseprites table-artige JSON-Wrapper vorsorglich als Workaround für einen Gast-PC-Fehler „C stack overflow“; die Wirkung muss am betroffenen Gast-PC bestätigt werden.

## Paket und Diagnose ab 0.6.5

Der Build enthält zuerst das Collabsprite-`package.json`: Aseprite 1.3.18.6 wertet das erste Manifest aus, auch wenn es in einer Abhängigkeit liegt. `test/bootstrap.ps1` prüft diese Reihenfolge und den Hoststart ohne Node im PATH. `runtime.json` fixiert die offiziellen Download-URLs und SHA-256-Werte; `build.ps1` prüft alle Runtime-Dateien vor dem Verpacken. Der Build-Cache wird nicht veröffentlicht. Die Windows-x64-Laufzeit und vollständige Node-Lizenz liegen unter `runtime/`.

Die Diagnose ist Teil der regulären Beta. Dateizugriffe finden nicht im WebSocket-Empfang oder Paint-Callback der Diagnoseansicht statt. Der Haupttimer und Client schützen sich gegen Wiedereintritt durch Aseprites modale Freigabedialoge. `test/callbacks.lua` modelliert einen solchen verschachtelten Callback, verweigerte Dateifreigabe und einen dauerhaft wartenden Worker; der reale Fehler auf dem Freund-PC ist damit noch nicht abschließend erklärt.

## Synchronisationsmodell

### 0.8.0 / Protokoll 5: gemeinsame Notizen

`notes.mjs` verwaltet unabhängig vom Pixel-/Strukturverlauf einen Kartenbaum mit
stabilen 128-Bit-IDs, Eltern-ID, Position, Titel/Text, optionalem HEX-Feld, Status
und Feldrevisionen. Snapshots, Sitzungskopie und Backups enthalten `notes`.
Eine Pixel-/Strukturwiederherstellung ersetzt diesen Zustand nicht.

`note`-Aktionen werden atomar validiert und vom Server geordnet. Pro Client
höchstens eine ausstehende Notizaktion; separate Sequenz und gespeicherte letzte
Bestätigung erlauben idempotentes Wiederholen nach einem kurzen Resume.
Erwartete Feldkonflikte liefern `noteAck/ok=false`, keinen Sitzungsabbruch.
Der eigene Notizverlauf trägt Feldrevisionen: auch fremdes Ändern-und-zurück-Ändern
berechtigt nicht zu einer veralteten Rücknahme. Eigene Umkehrungen aktualisieren
nur die Erwartungen des eigenen Verlaufs. Ganze Zweiglöschungen verlangen den
bekannten Board-Stand, damit keine inzwischen hinzugefügten Ideen übersehen werden.

`noteLock` reserviert ein Feld 15 Sekunden, erneuert alle 5 Sekunden bei offenem
Editor. Transportende löst Reservierungen; andere Felder/Karten bleiben frei.
Geänderte Boards werden nach jeder bestätigten Aktion an die Teilnehmer gesendet,
keine Vollbild-Pixelsnapshots. Textänderungen werden bewusst erst mit Übernehmen
geteilt. Höchstens 64 Notiz-Steueraktionen Burst / 24 pro Sekunde je Verbindung;
Notiz-Operationsnachricht maximal 128 KiB. 128 Karten, Tiefe 24, Titel 120 und Text
2048 UTF-8-Bytes, 512 KiB inklusive Papierkorb. Je Person 32 Rücknahmen / 4 MiB
Verlauf; Papierkorb bis 20 Löschgruppen innerhalb des Gesamtlimits. Älteste
Papierkorbeinträge/Verlaufseinträge können beim Erreichen der Grenze entfallen.

`extension/notes.lua` speichert JSON ausschließlich in
`sprite.properties('Merthius/Collabsprite').board`. Native `.aseprite`-Roundtrips
und Save As wurden in Aseprite 1.3.18.6 geprüft. Änderungen markieren das Sprite
als ungespeichert; andere Namespaces und `sprite.data` bleiben unberührt.
`noteSaved` bestätigt ausschließlich einen vom Host gespeicherten Board-Stand;
Backup, Übertragung und manuelle Dateispeicherung sind verschiedene Zustände.
PNG/Spritesheets enthalten die Metadaten nicht. Die Gast-Speichersperre ist
weiterhin keine Sicherheits-/Kopierschutzgrenze.

`notes-ui.lua` zeichnet die Karten in einem nichtmodalen `Dialog:canvas()`.
Lokale Ansichtseinstellungen sind nicht im Board. Entwürfe bleiben nur im
Arbeitsspeicher und werden vor normalen Speichern-/Schließen-/Trennen-Befehlen
geprüft; bei hartem Abbruch ist Verlust möglich. Native Sprite-Wrapper sind zwar
`==`, aber nicht `rawequal` und als Lua-Tabellenschlüssel verschieden: Zustände
und die dauerhafte Gast-Rolle sind deshalb über `sprite.id` indiziert. Dies
verhindert wiederholtes Aufpoppen und schließt eine bisherige Guard-Lücke.
Dialog-Widgets werden nur bei Änderungen neu gesetzt; Notiz-UI-Fehler pausieren
die betreffende Aktualisierung, ohne die Pixelsitzung zu trennen.

Tests: 45 Node-Fälle einschließlich Drei-Peer-Notizen/Backups/Lease/Resume,
native Dateispeicherung, eigene Note-/Pixelhistorie und drei echte native
WebSockets in `test/native-notes.lua`. Die bisherigen Struktur-/Resume-Tests
bestanden erneut. Ein Rechner ersetzt weiterhin keinen Zwei-PC/Radmin-Test.

### 0.7.0 / Protokoll 4: Wiederaufnahme und gelöschte Inhalte

Die Erweiterung nutzt [Aseprites offizielle Plugin-API](https://www.aseprite.org/api/plugin#pluginnewcommand) für den zusätzlichen Wiederherstellungsbefehl. Beide Rollen bleiben in einem Installer; alle Teilnehmenden müssen aktualisieren.

Jede Ebene besitzt eine feste 128-Bit-ID, Frames eine parallele `frameIds`-Liste. IDs bleiben in Backups erhalten. Server und Client ordnen ausstehende Pixelaktionen anhand dieser IDs neu zu, statt inzwischen verschobene Indizes blind zu verwenden. Ist das tatsächliche Ziel gelöscht, stoppt der Client vor dem Umbau seiner Ansicht. Fremde Strukturänderungen mit überlebenden Zielen können dagegen abgeglichen werden. Metadaten-/reine Strukturaktionen werden nicht automatisch erneut abgespielt; veraltete Metadatenindizes können weiterhin einen sicheren Abbruch auslösen.

Ein `welcome` enthält einen individuellen zufälligen 256-Bit-Resume-Schlüssel; nur sein Hash liegt serverseitig in einer flüchtigen Lease. Nicht im Einladungscode, Diagnoseprotokoll oder Backup. `hello/mode=resume` verlangt Raum, Autor und diesen Schlüssel; der öffentliche Einladungscode genügt nicht. Höchstens 8 aktive/kurz unterbrochene Identitäten, Lease 120 s. Ein gültiger Resume ersetzt auch einen halb offenen Socket; alte Socket-Callbacks dürfen die neue Identität nicht abmelden. Eine Beitrittssperre lässt legitime Wiederaufnahme bestehender Gäste zu.

Beim Transportverlust hält der Client den Tab offen und sperrt vorübergehend die Bearbeitung. Wiederholungsabstand 1/2/4/8/10 s; aktuelle Server-Snapshot und `confirmedSeq` entfernen schon bestätigte Pixeloperationen, übrige werden mit derselben Sequenz genau einmal nachgeliefert. Server-`ack` für ältere Sequenzen verändert weder Bild noch Verlauf. Ein Snapshot-Abgleich ersetzt Inhalte im **selben** nativen Sprite, nicht in einem neuen Tab. Änderungen am pausierten lokalen Bild werden vor dem Abgleich erkannt und bleiben bei Abbruch erhalten. Kein allgemeines Offline-Merging; keine Wiederaufnahme nach Aseprite-/Server-Neustart oder absichtlichem Verlassen.

Explizites `leave` widerruft die Lease und beendet einen verwalteten letzten Host nach finalem Backup. Bei unerwartetem Verlust hält der Server den Port höchstens bis zum Lease-Ende für Resume offen. Ein nie benutzter Starter endet weiterhin nach 30 s. `Trennen` während einer Unterbrechung behält die lokale Ansicht; bei nicht erreichbarem Server läuft dessen Lease bis zum Fristende aus.

`delete`/`deleteMany` speichern nur gelöschte Strukturfragmente/Cels und kleine ID-Reihenfolgen. `restore` verlangt die aktuelle Recovery-ID und stellt die letzte gemeinsame Löschung atomar wieder her. Neue Inhalte in übrigen Cels und ihre persönliche Pixelhistorie bleiben erhalten; gelöschte Pixel kehren als Basis zurück, nicht mit alter gelöschter Undo-Historie. Bis 20 Löschaktionen und 4.194.304 gespeicherte Cel-Pixel insgesamt; älteste Einträge fallen heraus. Der Löschverlauf ist flüchtig und nicht in Server-Backups enthalten. Größen-/Strukturlimits werden vor Mutation geprüft. Zwei gleichzeitige Klicks auf dieselbe Recovery-ID stellen nicht versehentlich zwei Aktionen wieder her.

Regressionen: 37 Node-Tests, `test/resume.lua` mit echten nativen Bildobjekten sowie `test/native-reconnect.lua` mit zwei echten Aseprite-WebSockets, absichtlich verlorener Bestätigung, ungesendetem Strich, fremden Löschungen und anschließendem beidseitigem Undo. Zusätzlich alle bisherigen Batch-, Struktur-, Bootstrap-/Update-Tests. Zwei physische PCs sind damit weiterhin nicht nachgewiesen.

### Historischer lokaler Stand 0.6.7: Härtung (in 0.7.0 enthalten)

Die folgenden Absätze dokumentieren die damaligen Grenzen; die Aussagen zu fehlenden IDs/Resume sind durch 0.7.0 oben ersetzt.

Die [Multiplayer-Prüfung](multiplayer-checklist.md) dokumentiert die Prioritäten,
Funde, Tests und verbleibenden Grenzen. Zusätzliche Nachrichten `admission`,
`backup` und `rejected` erweitern Protokoll 3; für das vollständige Verhalten
dieselbe 0.6.7 auf Host und Gästen verwenden. Öffentlicher Stand bleibt 0.6.5.
Host-Zugriffskontrolle ist serverseitig, die Gast-Speichersperre dagegen nur UI.

Die offene Sitzungssuche liefert Einladungen an erreichbare LAN-/VPN-Peers.
`admission=false` verhindert neue Beitritte und Discovery, trennt aber keine
bestehenden Teilnehmer. Ein verwaistes Backup kann nur lokal mit bekanntem
Token als Host wiederaufgenommen werden; dabei sind weitere Beitritte zunächst
gesperrt. Reconnect mit bewahrter Teilnehmeridentität/Undo ist noch nicht vorhanden.

Erwartete Ablehnungen (letzte Ebene/letztes Frame, Größenlimit, veraltete reine
Strukturaktion) trennen die Sitzung nicht. Veraltete Pixel-/Metadatenoperationen
und Strukturwechsel bei unbestätigten Pixeln erfordern weiterhin einen sicheren
Abbruch, bis ein getestetes Rebase-/stabile-ID-Modell vorhanden ist. Solche
Operationen niemals blind erneut senden: die Indizes könnten andere Cels meinen.

Sicherungsmeldungen gehen nur an den Host. Die gemeldete Revision ist die
tatsächlich geschriebene, nicht notwendigerweise die neueste Bildrevision.
Schreiben über temporäre Datei, Dateiflush und Rename; der Shutdown wartet
auf eine laufende ältere Sicherung und schreibt danach noch offene Änderungen.
Ein fehlgeschlagener Versuch lässt `dirty=true` und wird periodisch wiederholt.
Das ersetzt kein manuelles Speichern und garantiert keine Stromausfallsicherheit.

Lokaler Stand 0.6.6: Reguläres Trennen erfasst den letzten abgeschlossenen
Strich und wartet asynchron auf eine geordnete Ping/Pong-Bestätigung des
Servers. Weitere währenddessen abgeschlossene Änderungen erfordern eine neue
Bestätigung. Nach zehn Sekunden ohne Bestätigung bleibt die Sitzung offen.
CloseFile/CloseAllFiles/Exit über den Command-Hook nutzen denselben Ablauf;
harte Prozessabbrüche und direkte Skript-/native Schließpfade können ihn umgehen.
Bei Verbindungsende wird ein zuvor empfangener finaler Patch noch gerendert.
Native Transaktionen wählen explizit das Sitzungsdokument und stellen einen
zuvor aktiven anderen Tab (oder keinen aktiven Tab) anschließend wieder her.
So gehen Empfangsänderungen nicht in den Undo-Verlauf eines fremden Dokuments.
Presence alleine löst keinen Pixel-Scan mehr aus. Austritt entfernt ausschließlich
die Netzwerkmitgliedschaft, nicht Pixelbeiträge/Verlauf; er stößt ein Backup an.

Speichern/Exportieren ist in normalen Aseprite-Befehlen des Gast-Sitzungsbilds
gesperrt. Die Rolle bleibt für das Dokument nach Trennung erhalten; reguläres
Gast-Trennen schließt seine Sitzungskopie erst nach bestätigtem Transfer.
Diese lokale UI-Regel schützt nicht vor Skripten, Zwischenablage, Bildschirmkopie,
Wiederherstellungsdateien, alten oder veränderten Clients. Gastgeräte empfangen
weiterhin vollständige Bilddaten. Es gibt ausdrücklich keine DRM-Garantie.

Regressionen: `test/lifecycle.lua` (Aseprite Batch, echte Dokumente mit
deterministischem Transport), `test/controller.lua` (Menü-/Schließrouting),
`test/network.test.mjs` (Gast geht, Host-Undo, Wiederherstellung), sowie
`test/native-structure.lua` mit echten Aseprite-WebSocket-Verbindungen.

Die Synchronisierung geschieht nach abgeschlossenen Aktionen. Temporäre schwebende Cels und ein noch gehaltener Pinselstrich werden nicht als stabile Änderung verteilt. In Version 0.6.0 werden Rasterebenen und Frames angefügt, dupliziert bzw. einzeln oder in Auswahl gelöscht; das Löschen einer vorhandenen Gruppe entfernt ihre Unterebenen. Ebenenname, Sichtbarkeit, Sperre, Deckkraft, Mischmodus und durchgehende Cels, Frame-Dauer, Cel-Deckkraft/Z-Index sowie die erste Palette werden übertragen. Ebene/Frame-Nummern werden bei Löschungen neu zugeordnet; veraltete indexbezogene Nachrichten werden abgewiesen statt auf falsche Cels angewendet. Undo/Redo betrifft serverseitig weiterhin nur eigene Pixeloperationen, nicht Struktur- oder Metadatenänderungen. Mauszeiger und Namens-Tags anderer Teilnehmender werden nicht übertragen.

## Sicherheit und Grenzen

Collabsprite ist eine Beta, kein öffentlich erreichbarer Dienst. WebSocket hat hier keine eigene Ende-zu-Ende-Verschlüsselung. Nur in einem **vertrauenswürdigen LAN oder VPN** arbeiten und den Einladungscode privat teilen. Der Firewall-Helfer erlaubt TCP/UDP `8766` nur für den benötigten Node-Prozess: lokales Subnetz auf privaten/Domain-Netzen sowie Radmin-Adressen (`26.0.0.0/8`). Auch der Server prüft die Quelladresse. Windows-Freigaben müssen vom Nutzer bestätigt werden.

Maximalwerte: 8 Teilnehmende; 1024×1024 Bildpunkte; 32 Ebenen inklusive Gruppen; 120 Frames; 4.194.304 Cel-Pixel. Der persönliche Verlauf hält nur jüngere Pixelaktionen (bis 256 Aktionen bzw. etwa 500.000 Pixelbeiträge). Unterstützt sind RGB/RGBA-Rasterebenen; Tilemaps, Referenzebenen und Nicht-RGB-Dokumente nicht. Tags, Slices, Farbprofile, animierte Paletten und verknüpfte Cels werden nicht dauerhaft synchronisiert. Ebenen-Umordnung, neue Gruppen innerhalb einer Sitzung, Canvas-Größe sowie Änderungen am Farbmodus bleiben gesperrt. Auswahlrahmen, Zoom und aktive Farbauswahl sind persönliche Arbeitsansichten und werden nicht geteilt.

## Entwicklung und Tests

`npm ci` installiert die mitgelieferte `ws`-Abhängigkeit; `npm test` prüft Server, Protokoll und mehrere WebSocket-Clients. `./build.ps1` erstellt `../output/Collabsprite.aseprite-extension`. `test/bootstrap.ps1` prüft den Hintergrundstarter auf einem isolierten lokalen Testport. Native Aseprite-Tests liegen unter `test/*.lua` und benötigen eine lokale Aseprite-Installation.

Bislang bestätigt: früherer Ein-PC-Testaufbau mit Sitzungserstellung im sichtbaren Aseprite 1.3.18.6 und zwei lokalen Aseprite-Instanzen mit gegenseitigen Pixeln und eigenem Undo/Redo; außerdem Node-Protokolltests. In 0.5.0 kam ein automatisierter Verbindungstest über die echte LAN-Adresse dieses Rechners hinzu. Für 0.6.0 wurden automatisierte Tests und ein nativer Aseprite-Test mit zwei Verbindungen für einfaches und mehrfaches Löschen, persönlichen Pixel-Verlauf und Metadaten bestanden. Das beweist noch keine Zusammenarbeit über zwei physische PCs. Noch offen: durchgehender Zwei-PC-Test im direkten LAN und über Radmin VPN, VPN-Sitzungssuche, UAC-/Firewall-Ablauf sowie ein nativer Test mit lange gehaltenem Mausstrich.
