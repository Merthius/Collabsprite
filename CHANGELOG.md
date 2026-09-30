# Changelog

## 0.12.0 beta — 2026-09-30

This release includes the development milestones below. Both host and guests must update: protocol 13 / notes format 8 replaces protocol 7 / notes format 2.

- Native, pixel-perfect Aseprite idea board at a fixed readable scale, with magnetic three-sided branches, inline editing, marquee selection, cut/copy/undo, author labels and compact responsive tool islands. No browser or automatic split layout.
- Animation tag cards with enlarged small sprites, absolute frame selection, filmstrip navigation, playback and quarter-speed preview.
- Shared 1000×1000 sketch sheets with a compact sidebar, palette, optional pressure sensitivity, pen-only stabilization, undo/redo and clear-all. Pen size is 5–20 px; block eraser size is **5–100 px**, enforced for both slider and typed input. Live thumbnails also show unconfirmed local sketches.
- Direct Windows reference-image selection, multiple-file import and bounded external image drop support. Embedded references remain at most 512×512 pixels; source files are unchanged.
- Remove the redundant “Letzte Löschung wiederherstellen” menu entry. Normal personal undo/redo remains available; legacy recovery data and protocol handling are retained for compatibility.
- Fix session-search UI filtering to match protocol 13; compatible discovered hosts are no longer hidden by an outdated protocol check.
- Closing the host image tab disconnects its session using stable document IDs. A hidden verified-process watcher also stops the server when its owning Aseprite exits or is terminated, flushes confirmed work to backup and releases TCP/UDP ports. It never closes another Aseprite instance. Brief network interruptions while Aseprite is still running retain the existing reconnect lease.
- Automated owner-process, tab-close, size-boundary, native document and network regressions. Two-PC/Radmin, tablet pressure and actual Windows Snap Assist still need real-device testing; this remains a beta.

The following dev entries are historical milestones, not separate installer choices; later entries supersede earlier UI behavior and limits.

## 0.12.0-dev.9 — lokal, noch nicht veröffentlicht

- Skizzenminiaturen werden aus den aktuellen Blattpixeln in der tatsächlichen Vorschaugröße erzeugt, auf weißem Grund und ohne erneutes verlustreiches Schrumpfen. Auch noch unbestätigte Entwürfe bleiben auf der Wand sichtbar. Vollauflösende Bilder werden nicht dauerhaft für jede Karte im Speicher gehalten.
- Stiftgröße über Regler und Zahlenfeld auf 5–20 px begrenzt; der Blockradierer behält separat seine Größe von 1–200 px. „Alles löschen“ leert das Blatt und ist rückgängig machbar; fremde neuere Blattversionen werden weiterhin geschützt.
- Referenzbild-Knopf öffnet direkt die Windows-Dateiauswahl mit Mehrfachauswahl. Ein Windows-Helfer nimmt Bilddateien beim Ziehen auf die Ideenwand entgegen; Import erfolgt atomar und über den bestehenden Notizabgleich. Höchstens 32 Dateien pro Import, 64 MiB pro Quelldatei; eingebettete Referenzen bleiben maximal 512×512.
- Separate Animationsinsel links und einheitliche klare Links-/Rechtspfeile für Undo/Redo auf Wand und Skizzenblatt. Alle drei Inseln bleiben auch in schmalen Ansichten erreichbar.

## 0.12.0-dev.8 — lokal, noch nicht veröffentlicht

- Die automatische Aufteilung von Aseprite und Ideenwand sowie ihr Split-Knopf sind entfernt. Die Ideenwand wird unter Windows als eigenständiges Fenster statt als angehängtes Werkzeugfenster registriert; der Nutzer kann die Windows-Einrastfunktion selbst verwenden. Aseprite wird dabei nicht verschoben oder vergrößert.
- Der Animations-/Tag-Knopf sitzt ohne Trennleiste in derselben Werkzeuginsel wie Text, Liste, Bild und Skizzenblatt. Bei schmalen Fenstern rücken Undo/Redo in eine zweite Reihe; die Skizzenblatt-Seitenleiste behält ihre eigenen Undo-/Redo-Knöpfe.
- Der Radierer entfernt quadratische Blöcke und setzt bei schnellen Strichen weniger, überlappende Stempel. Auch diagonale Linien bleiben ohne Lücken radiert.
- Native Aseprite-Tests für schmale Ansichten und Radierstriche sowie eine isolierte Windows-Eigentümer-/Taskleistenstil-Prüfung bestanden. Echtes Snap Assist mit zwei produktiven Aseprite-Fenstern und 400-%-Nutzerskalierung bleibt vor Ort zu prüfen.

## 0.12.0-dev.7 — lokal, noch nicht veröffentlicht

- Die Skizzenblattwerkzeuge liegen in einer schmalen linken Seitenleiste. Das unvergrößerbare Blatt nutzt rechts daneben die gesamte verfügbare quadratische Fläche.
- Stift und Radierer teilen sich einen Größenregler und ein direkt beschreibbares Zahlenfeld. Die Eingabe wird auf 1–200 Pixel begrenzt.
- Zwei Knöpfe und Strg+Z/Strg+Y machen die eigenen letzten Blattstriche rückgängig bzw. stellen sie wieder her. Bei einem Versionskonflikt mit einer anderen Person wird kein fremdes Blatt überschrieben.
- Die Ideenwand-Karte erhält eine kontrastreiche weiße Blattfläche und eine Vorschau, die selbst einzelne Bildpixel beim Verkleinern erhält. Neue Striche erscheinen nach dem bestätigten Speichern auf der Karte.
- Native Aseprite-Proben prüfen Seitenleiste, Eingabegrenze, Blatt-Undo/-Redo, sichtbare Kartenvorschau und Dateispeicherung; die 67 automatisierten Server-/Protokolltests bleiben grün.

## 0.12.0-dev.6 — lokal, noch nicht veröffentlicht

- Die Skizzenblattansicht hält das Blatt fest unterhalb der Werkzeugleiste; Mausradbewegungen zoomen das Blatt nicht mehr. Die Bedienelemente werden über dem Blatt gezeichnet und bleiben sichtbar.
- Pinselgröße und Stabilisierungsstärke haben kurze, kompakte Regler statt einer Leiste über die gesamte Fensterbreite.
- Stabilisierung wirkt nur auf den Stift. Beim Radierer sind Checkbox und Stärke inaktiv; die Stifteinstellung bleibt für den nächsten Stiftwechsel erhalten.

## 0.12.0-dev.5 — lokal, noch nicht veröffentlicht

- Skizzenblätter zeichnen nun auf 1000 × 1000 echten Pixeln; auf der Ideenwand bleiben sie kleine Vorschaubilder. Alte 128 × 128-Blätter werden beim Öffnen pixelgenau hochskaliert. Lauflängenkodierung und eine begrenzte Base64-Ausweichkodierung bewahren auch dicht bemalte Blätter beim Speichern und Teilen.
- Die Zeichenansicht liegt im vorhandenen Ideenwandfenster. Stift und Radierer, ein Pinselgrößenregler, sichtbare Bildpalette, standardmäßig ausgeschaltete Drucksensitivität sowie optionaler Stabilisierungsregler ersetzen das alte Farbauswahl-Popup.
- Die echte Fensterteilung nutzt links ungefähr ein Drittel des Windows-Arbeitsbereichs. Der unsichtbare Helfer wartet kürzer; die Ideenwand zeigt nur noch den Teilungsknopf, während die nativen Fensterknöpfe erhalten bleiben.
- Protokoll 13 und Notizformat 8 trennen den neuen Bilddatentyp von älteren Clients. Ein beim nativen Host/Gast-Test gefundener Hoststartfehler wurde behoben: Aseprites leere Lua-Autorentabelle wird serverseitig sicher normalisiert.
- 67 Node-Tests einschließlich eines vollständigen 1000er-Blatttransfers mit spätem Beitritt, native Zeichen-/Speicher-/Bedienungstests, Host-Lebenszyklus und ein vollständiger nativer Host/Gast-Dokumententest bestanden. Echtes Grafiktablett, 400-%-Anzeige und zwei physische PCs bleiben offen. Öffentliche Version und reguläre Aseprite-Installation sind unverändert.

## 0.12.0-dev.4 — lokal, noch nicht veröffentlicht

- Animationsboxen haben neben Play einen lokalen Schalter für ¼-Geschwindigkeit. Die drei Listenarten stecken nun in einem ausklappbaren Werkzeugknopf.
- Neue 128 × 128-Pixel-Skizzenblätter: auf freier Wand platzieren, mit Stift oder Radierer zeichnen, Größe und Farben aus der Bildpalette wählen; optional wird Aseprites Stift-Druckwert auf die Strichbreite angewendet. Referenzbilder und Animationsframes lassen sich als bearbeitbare Vorlage auf das Blatt legen.
- Die geteilte Ansicht ordnet jetzt bei aktiviertem Aseprite-Mehrfenster-Modus das native Ideenwandfenster und den Editor als zwei echte Windows-Fenster nebeneinander an. Schließen stellt die vorherige Editor-Geometrie wieder her. Damit ist die überdeckende Aufteilung aus dev.3 ersetzt.
- Aseprite kürzt einzelne sehr lange Eigenschaften beim Wiederöffnen. Die Ideenwand wird deshalb in höchstens 60.000 Zeichen lange, mit Prüfsumme und Gesamtlänge kontrollierte Eigenschaften aufgeteilt; ein Speichertest mit einem vollständigen Blatt und erneutem Öffnen ist grün.
- Die Werkzeugleiste bleibt auch in einem sehr schmalen Split-Fenster bedienbar: Tag-Auswahl in der oberen Leiste, Verlaufsknöpfe bei Bedarf in einer zweiten Reihe. Das Skizzenblattfenster zeigt Stift, Radierer, Palette und Druck auch bei hoher Aseprite-Skalierung. Der Paketbau funktioniert mit PowerShell 5.1 und 7.
- Notizformat 7 und Protokoll 12; alle Beteiligten brauchen denselben neuen Build. Die öffentliche 0.11.0 und die reguläre Aseprite-Installation sind unverändert.

## 0.12.0-dev.3 — lokal, noch nicht veröffentlicht

- Freie Fläche: Linkszug wählt wieder per Rechteck, Rechtszug verschiebt die Wand; ein Rechtsklick ohne Ziehen öffnet weiterhin das Menü. Mittlere Maustaste und Mausrad bleiben verfügbar.
- Eigene pixelgenaue Fensterleiste mit Schließen, Maximieren/Wiederherstellen und schmaler geteilter Ansicht innerhalb Aseprites. Die geteilte Ansicht startet beim Erstellen und Beitreten automatisch. Der Dialog wird beim Moduswechsel in passender Canvasgröße neu aufgebaut, damit alle Werkzeuge sichtbar bleiben.
- Jede Ideenwand-Box zeigt ihren zuletzt ändernden Sitzungsnamen oben rechts. Der Host ordnet Namen serverseitig zu; Zuordnungen werden mit der Bilddatei gespeichert. Native Statushinweise melden nun auch das Verlassen anderer Personen.
- Notizformat 6 übernimmt ältere Formate einschließlich 5; Protokoll 11 erfordert denselben lokalen Build bei allen Teilnehmenden. Noch nicht öffentlich veröffentlicht oder in der regulären Aseprite-Installation ersetzt.

## 0.12.0-dev.2 — lokal, noch nicht veröffentlicht

- Animationselemente zeigen kleine Sprites pixelgenau vergrößert (16 × 16 → 160 × 160). Der bestätigte Frame ist eine absolute Aseprite-Framenummer und wird mit Bild und Sitzung gespeichert; Enter oder erneuter Klick auf den hervorgehobenen Filmstreifen-Frame bestätigt ihn.
- Lokale Abspiel-/Stopp-Vorschau unten rechts an der Animationsbox. Sie nutzt Aseprites Frame-Dauern und Tag-Richtung, ohne den gespeicherten Frame während der Vorschau zu verändern.
- Freie Anschlussseiten berücksichtigen jetzt auch die Verbindung zum Elternelement. Linkes Ziehen auf leerer Ideenwand schwenkt den Ausschnitt; die Rechteckauswahl liegt auf Umschalt+Ziehen (Strg+Umschalt ergänzt).
- Notizformat 5 migriert Formate 1–4; Protokoll 10 verlangt denselben neuen Build bei allen Sitzungsteilnehmern.

## 0.12.0-dev.1 — lokal, noch nicht veröffentlicht

- Tag-/Loop-Auswahl oben links mit Startbild und Namen; per Klick oder Ziehen als verknüpftes Animationselement einsetzen. Der native Filmstreifen lässt sich per Klick, Pfeiltasten oder horizontalem Ziehen durchblättern; der selektierte Frame bleibt am Boxanker. Die Ansichtsauswahl ist lokal, die Tag-Verknüpfung wird mit dem Bild gespeichert.
- Freie Plus-Seiten reagieren auch auf Annäherung knapp außerhalb der Box. Ausschneiden im Elementmenü und mit Strg+X kopiert zuerst und löscht dann Element und Nachfolger beziehungsweise die Mehrfachauswahl. Die Rechteckauswahl schwenkt am Fensterrand automatisch weiter.
- Die native Aseprite-Ideenwand öffnet eingebettete Referenzbilder per Klick in einer 100-%-Vorschau; freier Rand oder X schließt sie. Die bisherige 512 × 512-Pixel-Grenze eingebetteter Bilder bleibt bestehen.
- Elemente lassen sich innerhalb ihrer gesamten Box ziehen und durch Ablegen abseits einer Andockstelle lösen. Doppelklick bearbeitet ein Element oder erstellt auf freier Fläche direkt Text. Ein eingeblendetes + fügt an freien Unter-, Links- oder Rechtsseiten Text, Listen oder Bilder ein; zwischen verbundenen Boxen erscheint keines.
- Magnetische Verbindungen nach unten, links und rechts mit kollisionsfreiem Zweiglayout. Das einfache Kontextmenü-Kopieren nimmt nur das angeklickte Element und seine Nachfolger; ältere Zwischenablagen bleiben lesbar.
- Größere pixelgenaue Haupttitel, direkte Farbfelder ohne überflüssige Beschriftung, pixelgenaue Inseln und eine separate Undo-/Redo-Insel. Freier Rechtsklick bietet Einfügen, räumlich kompakte Sortierung sowie Undo/Redo; Sortieren bleibt eine einzige eigene rückgängig machbare Aktion.
- Notizformat 4 übernimmt Formate 1 bis 3 beim Lesen. Protokoll 9 verlangt dieselbe Version bei allen Teilnehmern. Neue Regressionstests prüfen Zweige, Abhängen, Kopieren, Direkteingabe, Bild-/Animationvorschau und gemeinsame Validierung.

## 0.10.0 beta — 2026-09-27

First public release after 0.8.0; includes the previously unpublished 0.8.1–0.9.0 work below. All peers need protocol 7.

- Replace the old card/outline UI with a single toolbar-free, search-free canvas. Right-click inserts text, checklists, bullet/numbered lists and local reference images; edit directly on the surface. Seven pastel presets and bundled OFL proportional typography.
- Magnetic vertical stacks: drag any box edge to move that box and everything below. Moving a middle/bottom box detaches exactly that tail. Snap preview, single-child/cycle validation, optimistic link guards and personal undo. Root text becomes larger and bold automatically.
- Embed references as bounded RGBA data (at most 512 × 512, first frame) in native file properties and shared snapshots. No local paths or remote image URLs. PNG/JPEG/WebP/GIF/BMP import, image aspect ratio preserved. Board limit 8 MiB including trash; note history 16 MiB per author.
- Migrate format-1 branching notes into ordered format-2 stacks without discarding IDs, text, colors or legacy status metadata. Original files change only when saved. Protocol 7 requires all participants to update; no silent downgrade.
- Preserve direct UTF-8 editing, leases, stale-draft protection and ACK-before-state handling. Enter creates a line; Ctrl+Enter, click outside or normal close commits. Network, geometry, native persistence and native-render regressions added.


## 0.9.0 development milestone — first shipped in 0.10.0

- Enable native layer/group organization, middle-frame insertion and frame reordering, linked cels at the same position, animation tags, canvas resize/crop and raster-layer merging for hosts and guests.
- Add validated, server-ordered three-way document transactions. Keep stable layer/frame identities and surviving pixel stacks; preserve unrelated concurrent edits and note history. Conflicts keep a separate local native draft, without disconnecting the session or bypassing guest save guards.
- Extend per-author undo/redo to structure and metadata. Protect newer foreign edits, including change-and-change-back. Refuse destructive inverses rather than deleting peer work; retain pre-transform pixel history when the original structure is restored. Bound document-history memory.
- Protocol 6 requires every participant to update. Native cel tracking handles insertion/reordering without assuming that Aseprite's positional Frame wrapper is an identity. Recreate real native links, not just identical pixel copies. Tags retain ranges, names, colors, animation direction and repeat counts.
- Add server, native batch and two-controller/production-WebSocket integration regressions. Keep unsupported offset linked cels and in-flight structural reconnect limitations explicit. Includes the updater and inline-note foundations below.

## 0.8.2 development milestone — first shipped in 0.10.0

- Simplify the idea board: create an empty card and type its title directly, with nested properties inside freely positioned root cards. Add points with inline + / Tab, siblings with Shift+Tab; commit with Enter or clicking away. Multiline notes, UTF-8 editing, selection, clipboard and input undo stay on the board.
- Preserve existing note IDs, text, saved coordinates, per-field leases, personal history and file persistence; no data migration or protocol change. Keep advanced color/status/parent controls in the options menu.
- Wait for the authoritative note snapshot after acknowledgement before starting chained edits. Preserve in-flight typing and conflicting drafts instead of overwriting newer peer text. Block board keys from affecting the drawing canvas.
- Add native inline-edit, persistence, conflict and acknowledgement-order regression tests. Contains the 0.8.1 updater foundation below; the old inline hierarchy UI was replaced in 0.10.0.

## 0.8.1 development milestone — first shipped in 0.10.0

- Update now shows a nonmodal phase window and hands the verified download directly to Aseprite's native installer. No browsing for the downloaded file; Aseprite still asks for installation/update confirmation. Restart after installation, without forcing an app exit.
- Distinguish current, downloading, verification, installation, cancellation and verified installed states. Prevent duplicate updates, recursive callbacks and updates during an active session or unapplied note edit. Closing the progress window before installation cancels installation (an in-flight download may finish).
- Verify package identity/version, root manifest order and safe paths in addition to the GitHub SHA-256 digest. Back up installed code/preferences and check for locked host files before handing over; do not modify live code in the worker. Session data is excluded and left untouched.
- Avoid dependency on Get-FileHash module discovery in the Windows worker. Add updater and UI-controller regression tests. Protocol remains 5.

## 0.8.0 beta — 2026-09-27

- Shared idea board: native, nonmodal connected cards with child branches, text, HEX color, status, dragging, zoom/pan, search, folding and arrangement.
- Host/guest field editing with short leases, per-field revisions, explicit Apply, retained in-memory drafts and conflict comparison. No note text in diagnostic logs.
- Separate personal note undo/redo, bounded trash, idempotent note replay after a lost acknowledgement, late-join synchronization and durable guest contributions.
- Embed notes in `.aseprite`/`.ase` properties, session copies and host backups. Preserve unrelated user/plugin properties; distinguish transmission from actual host file save. PNG/spritesheet warning.
- Fix native sprite identity handling: fresh Lua wrappers for the same document no longer spawn repeated note windows or bypass the detached guest save guard. Avoid unnecessary dialog relayout and overlapping card text at reduced zoom.
- Add card/tree/size/rate/history limits, atomic validation and expected conflict rejection without ending the session. A note panel error pauses its timer instead of killing pixel synchronization.
- Protocol 5: all peers must update. One Windows x64 installer continues to include host, guest and diagnostics. Existing two-PC/Radmin and long-session limitations remain.

Earlier 0.7.0 release details: [reconnection and deletion recovery](docs/releases/v0.7.0.md).

## 0.6.5 beta — 2026-09-26

- Fix the installer manifest order: Aseprite previously detected the nested ws package (8.21.3) before Collabsprite. The root manifest is now first and covered by a package regression check.
- Bundle checksum-pinned, unmodified Node.js 24.21.0 for Windows x64 with its license: one download can host or join, without installing Node separately.
- Repair Collabsprite-owned firewall rules when the runtime path changes.
- Guard timer/client reentrancy during permission dialogs, defer WebSocket decoding/logging to the guarded timer, and terminate denied/expired startup polling. This is not yet confirmed as the affected friend's stack-overflow fix.
- Accept dev.1/prerelease versions in the updater and allow time for the larger package.
- Local developer installation now uses the release archive and writes Aseprite's update inventory.
- Add a persistent, size-bounded diagnostic log and live Aseprite console with one-click copy/reset controls.
- Log connection stages, WebSocket message types/sizes, safe snapshot counts, and full Lua tracebacks while redacting invite codes, endpoints, and Windows user-profile names. Pixel and image payloads are never logged.
- Capture JSON-decode and client tick errors before disconnecting, to help diagnose the guest-PC “C stack overflow” report.

## 0.6.4 beta — 2026-09-25

- Die Beitrittsantwort wird jetzt mit einem begrenzten Lua-Parser statt über Aseprites table-artige JSON-Werte verarbeitet. Das umgeht vorsorglich den gemeldeten C-Stack-Überlauf; die Ursache muss auf dem betroffenen Gast-PC noch verifiziert werden.
- Der Join-Test prüft nun eine vollständige Willkommensnachricht samt Erzeugung eines Sitzungssprites, Unicode-Escapes, Zahlen und zu tiefe JSON-Eingaben.
- Serverseitiges Protokoll bleibt 3 und ist mit 0.6.3 kompatibel.

## 0.6.3 beta — 2026-09-25

- Ein voller Sicherungsordner blockiert keinen Hoststart mehr: Die acht zuletzt geänderten Sitzungen werden geladen; bei Bedarf wird nur ein ältester, inaktiver Speicherplatz im Arbeitsspeicher wiederverwendet. Sicherungsdateien werden nicht gelöscht.
- Netzwerkantworten werden beim Umwandeln in Lua-Tabellen auf maximale Verschachtelung begrenzt. Bei Fehlern zeigt die Aseprite-Konsole jetzt einmalig einen Traceback, damit Abstürze wie „Stack overflow“ genauer nachvollzogen werden können.
- Serverseitiger Protokollstand bleibt 3; bestehende 0.6.x-Clients bleiben grundsätzlich kompatibel.

## 0.6.2 beta — 2026-09-25

- Unter **Ansicht → Collabsprite** stehen jetzt die drei Befehle **Server erstellen / beitreten**, **Update** und **Info**. Ein eigener Hauptmenüpunkt neben „Datei“ ist mit Aseprites Erweiterungs-API nicht möglich.
- **Update** prüft veröffentlichte GitHub-Releases ohne blockierende Netzwerkanfrage in Aseprite, lädt bei einer neueren Version die Installationsdatei in den Downloads-Ordner und verifiziert ihren SHA-256-Wert. Installation und Neustart bleiben bewusst beim Nutzer.
- **Info** zeigt die installierte Version, Merthius als Entwickler, MIT-Lizenz und die Projektadresse.

## 0.6.1 beta — 2026-09-25

- Der automatisch gestartete Host-Server beendet sich, sobald das Sitzungsbild oder Aseprite auf dem Host geschlossen wird. Gäste allein halten ihn nicht offen; ein weiterer aktiver Host im selben Prozess bleibt ungestört.
- Das Sitzungsbackup wird vor dem Freigeben des Ports abgeschlossen. Ein noch nicht verbundenes, verlassenes Startfenster läuft spätestens nach rund 30 Sekunden Leerlauf aus.
- Regressions- und Hintergrundprozess-Test prüfen, dass nach dem Schließen des Hosts der Port für einen Neustart frei ist. Protokoll 3 bleibt kompatibel zu 0.6.0.

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
