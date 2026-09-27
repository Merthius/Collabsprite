# Multiplayer: notwendige Funktionen und Codeprüfung

Stand: 27.09.2026, **0.7.0 Beta**. Kein vollständiges Sicherheitsgutachten. Automatisierte Tests wurden an diesem Rechner ausgeführt; Aussagen über den betroffenen Freund-PC wären unbelegt. Die Härtungen aus 0.6.6/0.6.7 sind enthalten.

## Was Collabsprite unbedingt braucht

| Priorität | Funktion | Stand |
| --- | --- | --- |
| 1 | Gemeinsamer, eindeutig geordneter Bildzustand; keine falschen Cels bei konkurrierenden Änderungen | Pixel, Rasterebenen/Frames und ausgewählte Eigenschaften synchronisiert. Veraltete Indizes werden nicht blind angewendet. Nicht alle Aseprite-Funktionen unterstützt. |
| 1 | Eigener Undo-Verlauf, fremde Beiträge bleiben erhalten | Für Pixelaktionen vorhanden, auch nach Gast-Austritt. Noch nicht für Struktur-/Metadatenänderungen. |
| 1 | Änderungen behalten, Abschluss bestätigen und Backups | Geordnetes Trennen aus 0.6.6; in 0.6.7 sichtbare Sicherungsfehler, Wiederholungsversuch und abgesicherter Abschluss einer laufenden Sicherung. |
| 1 | Ehrlicher Verbindungs-/Übertragungsstatus | Offene Pixelaktionen sichtbar; fehlende Antworten nach 15 s anzeigen, nach 60 s Wiederverbindung versuchen und die lokale Ansicht behalten. |
| 1 | Sichere Wiederaufnahme nach Netzwerkunterbrechung | **0.7.0:** private Resume-Lease bis 120 s, gleicher Tab/Autor/erhaltener Pixel-Verlauf; bestätigte Operationen nicht doppelt, unbestätigte per ID abgleichen. Zeichnen pausiert. Nicht über Programm-/Server-Neustart hinweg und kein allgemeines Offline-Merging. |
| 1 | Zugang kontrollieren | Einladung und Netzwerkbegrenzung vorhanden. Neu: Host kann weitere Beitritte sperren. Suche und bekannte Codes respektieren die Sperre. Bestehende Gäste bleiben verbunden. |
| 1 | Schutz vor kaputten Daten und übermäßiger Last | Eingangs-/Ausgangsgrenzen, Ratenbegrenzung, frühere Browser-Abweisung, Validierung vor Pixel-Allokation ergänzt. Nur in vertrauenswürdigem LAN/VPN betreiben. |
| 2 | Konflikte bei gleichzeitigem Zeichnen und Strukturänderungen lösen | **0.7.0:** feste Ebenen-/Frame-IDs für Pixelaktionen; überlebende Ziele werden sicher umnummeriert. Gelöschtes tatsächliches Ziel: lokale Ansicht behalten, Abgleich stoppen. Veraltete reine Strukturaktionen nichtfatal ablehnen. Veraltete Metadatenindizes bleiben eine Abbruchgrenze. |
| 2 | Versehentliche gemeinsame Löschungen wiederherstellen | **0.7.0:** eigener Menübefehl stellt letzte gemeinsame Löschung wieder her, keine Gesamtbild-Rücksetzung. Bis 20 Löschaktionen / 4.194.304 gelöschte Cel-Pixel. Frühere Pixelhistorie gelöschter Cels wird nicht wiederhergestellt; allgemeines Struktur-/Metadaten-Undo bleibt offen. |
| 2 | Verständliche Diagnose, gleiche Versionen, ein Installer | Vorhanden. Diagnose enthält keine Pixel oder Einladungscodes. Ein Paket für Host und Gast. |

Chat, Maus-Namens-Tags und persönliche gesperrte Ebenen sind auf Nutzerwunsch keine Ziele. Ein Gast-Speicherverbot bleibt lediglich eine UI-Regel, kein Kopierschutz: Bearbeiten erfordert den Empfang von Bilddaten.

## Konkrete Funde und Korrekturen

- **Unnötige Abbrüche:** Letztes Frame/letzte Rasterebene löschen oder ein Größenlimit erreichen wurde wie ein Protokollfehler behandelt. Jetzt nichtfataler Hinweis; dieselbe Verbindung bleibt nutzbar. Auch veraltete reine Strukturaktionen werden abgelehnt, nicht automatisch wiederholt.
- **Unbegrenzter Nachrichteneingang im Lua-Client:** jetzt maximal 2.048 wartende Nachrichten/128 MiB Rohtext, bis 64 Nachrichten pro Timerdurchlauf. Einzelne Nachrichten maximal 64 MiB. Unbestätigte ausgehende Pixelaktionen ebenfalls auf 2.048/64 MiB begrenzt; lokale Ansicht wird bei Fehlern nicht geschlossen. Diese Grenzen ersetzen keinen Schutz vor einem bösartigen Host im selben vertrauenswürdigen Netz.
- **Empfangspause ohne sichtbaren Status:** eigener zeitbasierter Heartbeat, Warteanzeige und Frist ergänzt. Ab 0.7.0 begrenzte, authentifizierte Wiederaufnahme statt sofortigem endgültigem Abbruch; Grenzen oben beachten.
- **Sicherungsfehler unsichtbar:** Host erhält Status und einmaligen Hinweis, nach erfolgreichem Wiederholungsversuch Entwarnung. Schreibfehler lassen die Sitzung als ungesichert markiert. Temporäre Datei, Flush und Umbenennen bleiben getrennt von manuellem `.aseprite`-Speichern; kein Versprechen völliger Stromausfallsicherheit.
- **Abschluss während laufender Sicherung:** koaleszierte Schreibarbeit, erneuter letzter Flush beim Shutdown; in Bearbeitung befindliche Räume werden nicht verdrängt. Mehrfaches Schließen ist idempotent.
- **Ressourcenverbrauch durch Nachrichtenflut:** Server-Budget pro Verbindung (2.048 Nachrichten Burst, 256/s; 128 MiB Burst, 16 MiB/s), maximal 8 KiB für Steuerbefehle, globale Handshake-/Discovery-Budgets. Kompressionskontexte werden nicht über Nachrichten hinweg wiederverwendet. Diese Grenzwerte sind Schutzschranken, kein Lasttest-Zertifikat.
- **Nach erstem Protokollfehler weiter verarbeitete Nachrichten:** Verbindung wird als abgewiesen markiert; bereits anstehende weitere Nachrichten dürfen nichts mehr verändern.
- **Ungültige Cel-Indizes und Gruppenreihenfolge:** numerische IDs und zusammenhängende Tiefensortierung validiert. Ohne diese Annahme konnte eine Gruppenlöschung andere Cel-Indizes auf dem Client treffen. Snapshot-Größe und Metadaten werden auch beim Client vor Bildpuffer-Allokation geprüft.
- **Wachsender Speicherbedarf durch alte Teilnehmerkennungen:** nur verbundene Teilnehmer oder Autoren mit noch nutzbarem Verlauf bleiben im Index; Pixelbeiträge werden dabei nicht entfernt.
- **Irreführende Sicherheitsbeschreibung:** Netzwerksuche verteilt bei offenen Sitzungen den Einladungscode. Dokumentation nennt dies jetzt ausdrücklich. Die neue Beitrittssperre schützt zusätzliche Beitritte, ist aber kein Passwort/keine Einzelgenehmigung und entfernt keine schon verbundenen Gäste.

## Prüfungen

- 37 Node-Tests: zusätzlich ID-Rebase, gelöschte Fragmente/Gruppen/Mehrfachauswahl, persönliche Undo-Erhaltung, begrenzte/atomare Recovery, geschützte Wiederaufnahme, verlorene Bestätigungen, halboffene Verbindung, Lease-Ablauf und konkurrierende Wiederherstellungsklicks.
- Sieben Aseprite-1.3.18.6-Batchskripte: `plain`, `codec`, `callbacks`, `lifecycle`, `controller`, `safety`, `resume`. Echte Bildobjekte, Speicherbefehle, unveränderter Tab und Schutz lokal veränderter Offline-Ansicht.
- Neuer nativer Wiederverbindungstest: absichtlich verlorene Bestätigung, lokal wartender ungesendeter Strich, fremde Ebenen-/Frame-Löschung, Wiederaufnahme, eigenes Undo, zweifache Löschwiederherstellung, danach Host-Undo. Zwei echte native WebSockets, nur Wegwerf-Bilder.
- Nativer Aseprite-Test mit zwei echten WebSocket-Verbindungen: Struktur, Pixel-Undo, Metadaten, letzter Gast-Strich/Trennen, Beitrittssperre und Ablehnung des letzten Frame-Löschens ohne Abbruch. Computer-Use-Kontrolle der separaten Testkopie; keine Nutzerbilder.
- Ein-Installer-Build, isolierter Hintergrundstart ohne globales Node, kontrolliertes Serverende und Update-/Hash-Prüfung bestanden. `npm audit --omit=dev`: keine gemeldeten Schwachstellen der erfassten npm-Abhängigkeiten; keine Prüfung sämtlicher Windows-/Aseprite-Komponenten.

Weiterhin erforderlich: Test auf zwei echten PCs im LAN/Radmin, längerer gemeinsamer Praxistest, echter Freund-PC-Stack-overflow und Rennen aus gehaltenem Pinselstrich plus Strukturänderung. Keine dieser Prüfungen wird durch einen Ein-PC-Test ersetzt.

Die Schutzmaßnahmen orientieren sich an [OWASPs WebSocket Security Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/WebSocket_Security_Cheat_Sheet.html), besonders Validierung, Zugriffskontrolle, Lastbegrenzung und Protokollierung. **Collabsprite nutzt hier weiterhin `ws://`, nicht eigenes TLS/WSS; daher ausschließlich vertrauenswürdiges LAN/VPN und keine öffentliche Portweiterleitung.**
