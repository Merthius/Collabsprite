# Mitmachen / Contributing

Fehlerberichte, verständliche Anleitungen und kleine, gut getestete Änderungen sind willkommen. Bitte suche zuerst in den [Issues](https://github.com/Merthius/Collabsprite/issues) nach einem ähnlichen Thema.

Für einen Fehlerbericht hilfreich: Aseprite-Version, Collabsprite-Version, Windows-Version, Netzwerk (LAN/Radmin), Host oder Gast, genaue Schritte, erwartetes und tatsächliches Verhalten sowie das kopierte Protokoll aus **Datei → Multiplayer (Collabsprite) → Diagnosekonsole**. **Keine Einladungscodes, VPN-Netzwerkkennwörter, privaten IP-/Kontaktangaben, Nutzerbilder oder Dateien aus `data/` posten.** Wenn ein Screenshot einen Code zeigt, verdecke ihn vorher.

Für Quellcodeänderungen: `npm ci`, `npm test`, bei Änderungen am Starter zusätzlich `./build.ps1` und `./test/bootstrap.ps1`. Bei Änderungen an der Aseprite-Integration bitte einen nativen Test in einer frischen Sitzungskopie beschreiben. Vorhandene Bilddateien nicht überschreiben. Größere Änderungen oder Protokolländerungen zuerst als Issue besprechen.

Weitere lokale Prüfungen unter Windows:

- `pwsh -NoProfile -File test/native-suite.ps1`: native Batchprüfungen mit getrenntem Profil. Bei abweichendem Installationsort `-Aseprite "Pfad/aseprite.exe"` ergänzen.
- `node test/native-document.mjs`: zwei native Dokumente mit echtem WebSocket-Server; bei Bedarf `ASEPRITE_EXE` setzen. Die Test-Mailbox liegt in einem eigenen temporären Verzeichnis und wird anschließend entfernt.
- `pwsh -NoProfile -File test/update.ps1`: Paketvalidierung, Versionen, Hash, Sicherung und gesperrte Dateien mit lokalen Fixtures.
- `test/board-files.ps1` mit **Windows PowerShell 5.1** ausführen: der Windows-Importhelfer nutzt .NET Framework, nicht PowerShell 7/.NET. CI prüft ihn ebenfalls.
- `test/session-window.lua` und `test/notes-ui.lua` sind sichtbare GUI-Fixtures, keine Batchtests. In einem separaten Profil über `ASEPRITE_USER_FOLDER` starten; nie die reguläre Installation dafür verändern. Der Sitzungsdialog-Test simuliert die Verbindung, prüft aber echte native Dialoge. Netzwerkverhalten prüfen die anderen Tests.

English: Please include reproducible steps and test results in pull requests. Never include invitation codes, VPN credentials, personal artwork, or `data/` backups. This project is currently a Windows beta; two-PC Radmin behavior still needs verification.
