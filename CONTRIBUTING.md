# Mitmachen / Contributing

Fehlerberichte, verständliche Anleitungen und kleine, gut getestete Änderungen sind willkommen. Bitte suche zuerst in den [Issues](https://github.com/Merthius/Collabsprite/issues) nach einem ähnlichen Thema.

Für einen Fehlerbericht hilfreich: Aseprite-Version, Collabsprite-Version, Windows-Version, Netzwerk (LAN/Radmin), Host oder Gast, genaue Schritte, erwartetes und tatsächliches Verhalten sowie das kopierte Protokoll aus **Ansicht → Collabsprite → Diagnosekonsole**. **Keine Einladungscodes, VPN-Netzwerkkennwörter, privaten IP-/Kontaktangaben, Nutzerbilder oder Dateien aus `data/` posten.** Wenn ein Screenshot einen Code zeigt, verdecke ihn vorher.

Für Quellcodeänderungen: `npm ci`, `npm test`, bei Änderungen am Starter zusätzlich `./build.ps1` und `./test/bootstrap.ps1`. Bei Änderungen an der Aseprite-Integration bitte einen nativen Test in einer frischen Sitzungskopie beschreiben. Vorhandene Bilddateien nicht überschreiben. Größere Änderungen oder Protokolländerungen zuerst als Issue besprechen.

English: Please include reproducible steps and test results in pull requests. Never include invitation codes, VPN credentials, personal artwork, or `data/` backups. This project is currently a Windows beta; two-PC Radmin behavior still needs verification.
