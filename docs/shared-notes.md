# Ideenwand: freie Elemente und magnetische Verbindungen

**Lokal vorbereitete Collabsprite 0.12.1 Beta** verwendet Protokoll 14 und Notizformat 9. Noch nicht veröffentlicht; der öffentliche Download bleibt 0.12.0. Alle Beteiligten einer 0.12.1-Sitzung müssen aktualisieren; Sitzungen mit älteren Versionen sind nicht kompatibel. Alte Dateien werden beim Lesen übernommen.

Die Ideenwand bleibt vollständig in Aseprite. Normale Texte verwenden Aseprites UI-Schrift, größere Haupttitel einen hart gerasterten, mitgelieferten OFL-Schriftatlas. Das Canvas wird automatisch an die UI-Skalierung angepasst; Karten und Bedienelemente haben klare Pixelkanten. Es öffnet sich kein Browser und kein lokaler Ideenwand-Dienst.

Die Karten sind kleiner und behalten eine feste, lesbare Größe. Die Wand lässt sich verschieben, aber bewusst nicht zoomen; so werden Schrift und Boxen nicht auf krumme Zwischenwerte skaliert. Aseprites native Dateiauswahl und Sicherheitsdialoge bleiben unverändert.

## Eine freie Fläche

Die Wand hat keine Suchleiste. Oben sitzt eine kleine pixelgenaue Werkzeuginsel mit **Text**, einem **Listenknopf** (ausklappbar: Checkliste, Punktliste, nummerierte Liste), **Referenzbild** und **Skizzenblatt**; eine separate Insel links enthält **Animationen/Tags**, rechts eine eigene Insel mit **Undo** und **Redo** als klare Links-/Rechtspfeile. Bei wenig Fensterbreite rücken Undo/Redo in die nächste Zeile. Text und Liste erscheinen direkt auf der Wand. Öffnen über **Datei → Multiplayer (Collabsprite) → Gemeinsame Notizen**. Die zusätzlichen Split- und Fensterleistenknöpfe entfallen; Schließen und Maximieren bleiben die normalen Windows-Fensterknöpfe.

Die Ideenwand ist ein **eigenständiges Windows-Fenster**. Sie ordnet Aseprite nicht mehr automatisch an. Ziehe ihre native Titelleiste selbst an den linken oder rechten Bildschirmrand, um Windows Snap Assist zu nutzen und anschließend Aseprite für die andere Seite auszuwählen. Dafür muss Aseprites experimentelle Einstellung **Mehrere Fenster** aktiviert sein; nach einer Änderung Aseprite neu starten. Ein kurzer, unsichtbarer Windows-Helfer löst nur die Fenster-Eigentümerbindung und aktiviert den üblichen Taskleistenstil; er verändert weder Aseprites Fenstergröße noch Einstellungen. Die Ideenwand kann weiterhin normal verschoben, skaliert, maximiert oder geschlossen werden. Die tatsächliche Snap-Assist-Auswahl auf dem Nutzerbildschirm bleibt vor Ort zu prüfen.

Der **Animationsknopf in der linken Insel** öffnet die Tag-Liste des geöffneten Aseprite-Bildes. Sie zeigt Name und Startframe-Vorschau jedes Tags. Einen Eintrag anklicken setzt ihn in die Mitte der Ideenwand; in die Wand ziehen setzt ihn am gewünschten Ort ab. Ein Animationselement zeigt zunächst den ersten Frame. Ein Klick darauf entfaltet eine waagerechte Frame-Leiste direkt auf der Wand: Klick auf ein Nachbarbild oder **Pfeil links/rechts** wählt einen anderen Frame; waagerechtes Ziehen blättert ebenfalls. Der hervorgehobene Frame bleibt stets am Ort der Box, die übrigen Bilder rücken daran vorbei. **Enter** oder ein zweiter Klick auf den hervorgehobenen Frame bestätigt die Auswahl; die gewählte absolute Aseprite-Framenummer wird am Bild gespeichert und geteilt. **Escape** oder Klick auf freie Fläche schließt die Leiste ohne neue Auswahl. Unten links stehen die absolute Framenummer und die Zahl aller Frames im Bild, unten rechts startet/stoppt der kleine Knopf eine lokale Vorschau. Der Knopf direkt daneben schaltet **¼-Geschwindigkeit** ein oder aus; das betrifft nur deine Vorschau, nicht die Framedauern des Bildes oder andere Personen. Kleine Sprites werden in der Box mit ganzzahliger, pixelgenauer Vergrößerung angezeigt (16 × 16 → 160 × 160).

Ein **Rechtsklick auf freie Fläche** bietet **Einfügen**, **Sortieren**, **Undo** und **Redo**. Einfügen übernimmt kopierte Ideenwand-Boxen samt Eigenschaften/Verbindungen, Text aus anderen Programmen oder ein Bild aus der Zwischenablage. Sortieren rückt getrennte Stapel zu einer annähernd quadratischen Anordnung zusammen und hält zuvor benachbarte Stapel möglichst beieinander; auch diese Anordnung lässt sich mit dem eigenen Undo zurücknehmen. Der Bildknopf öffnet direkt die Windows-Dateiauswahl für ein oder mehrere Bilder (PNG, JPG/JPEG, WebP, GIF, BMP). Bilddateien lassen sich auch direkt aus dem Explorer auf die Ideenwand ziehen. Dafür muss die Ideenwand als eigenes Fenster laufen (Aseprite: Mehrere Fenster). Höchstens 32 Dateien bis je 64 MiB pro Import; der gesamte Import ist eine gemeinsame Undo-Aktion. Ein unsichtbarer Windows-Helfer nimmt die Dateien entgegen und endet mit der Ideenwand. Aseprites Sicherheitsfreigaben für den Helfer und die temporäre Ergebnisdatei bleiben erforderlich. Bei animierten Bilddateien wird das erste Bild verwendet.

Ein **Doppelklick auf eine freie Stelle** erstellt sofort ein bearbeitbares Textelement. Ein **Doppelklick auf ein Text- oder Listenelement** beginnt dessen Bearbeitung; ein einzelner Klick wählt es aus, Ziehen bewegt es. **Enter** setzt eine neue Zeile. **Strg+Enter**, **Escape**, Klick daneben oder normales Schließen übernimmt den Entwurf. Escape verwirft keinen Text. Strg+A/C/X/V und Auswahl per Maus funktionieren im Textfeld. Lange Zeilen umbrechen automatisch.

Ein einfacher Klick auf ein Referenzbild öffnet eine Aseprite-Vorschau bei **100 % der eingebetteten Bildpixel**. Ein Klick auf den freien Rand oder das **X** schließt sie. Bei Bildern größer als die Vorschau kann man mit dem Mausrad bzw. Umschalt+Mausrad den Ausschnitt bewegen. Die Quelle bleibt unverändert; vor dem Einbetten wird sie weiterhin auf maximal 512 × 512 Pixel verkleinert.

## Skizzenblatt

Ab 0.12.1 steht rechts oben ein **Häkchen** statt eines X. Es übernimmt das Blatt als Bild auf der Ideenwand, ohne die 1000 × 1000-Pixel-Auflösung zu verlieren. Auch beim Schließen der Zeichenansicht werden Änderungen übernommen. Bei normalem Aseprite-Speichern oder -Schließen wartet Collabsprite auf diesen Vorgang und setzt den Befehl danach automatisch fort. Zur weiteren Bearbeitung das bestätigte Bild auf ein neues Skizzenblatt ziehen. Das Häkchen erstellt keine separate Datei im Dateisystem: Der Host muss das gemeinsame Bild mit der Wand weiterhin als `.aseprite` speichern.

Der kleine **Bildknopf neben dem Häkchen** öffnet die Dateiauswahl für PNG/JPG und weitere unterstützte Formate direkt für das offene Blatt. Ausgewählte Bilder werden auf dessen Pixeln eingefügt, nicht unsichtbar als Karten außerhalb der Zeichenansicht. Vorbereitung und Vorschauen laufen in kurzen Arbeitsschritten; eine kleine Statuszeile zeigt laufende Aufgaben. Unteilbare native Datei-/Metadatenoperationen können bei großen Bildern weiterhin kurz dauern. Bei einer fremden Änderung oder Löschung bleibt ein eigener offener Entwurf erhalten; das Häkchen legt ihn gegebenenfalls als separates Bild ab, statt fremde Arbeit zu überschreiben.

Der Blatt-Knopf hängt eine kleine Papiervorschau an den Mauszeiger; ein Klick auf freie Wand platziert das **1000 × 1000-Pixel-Blatt** als eigenes Element. Auf der Wand bleibt seine Vorschau klein; feine Striche werden in der Kartenminiatur sichtbar gehalten. Ein Klick öffnet die Zeichenansicht **im selben Ideenwandfenster**; das Häkchen rechts oben bestätigt das Blatt und kehrt zur Wand zurück. Die Werkzeuge sind links in einer schmalen Seitenleiste, während das Blatt rechts den verfügbaren quadratischen Platz nutzt. Das Mausrad vergrößert es nicht. Der Stift hat einen kurzen Größenregler und ein Zahlenfeld für **5 bis 20 Pixel**. Der Blockradierer behält separat **5 bis 100 Pixel**. **Alles löschen** leert das ganze Blatt und lässt sich mit Undo rückgängig machen. Die erste Palette des geöffneten Aseprite-Bildes ist darunter sichtbar. **Undo/Redo** in der Seitenleiste oder mit Strg+Z/Strg+Y gelten den letzten Strichen dieses Blatts; nach einer fremden Blattänderung wird ein alter Verlauf nicht über die neue Fassung geschrieben. **Drucksensitivität** ist standardmäßig aus; nur wenn sie eingeschaltet ist und das Eingabegerät Druckwerte an Aseprite liefert, ändert sich die Strichbreite. **Stabilisierung** gilt ausschließlich für den Stift und ist beim Radierer inaktiv. Die Darstellung wurde in einer separaten Testinstanz bei 400 % Aseprite-Skalierung geprüft; die Wirkung mit einem echten S-Pen/Grafiktablett bleibt noch zu prüfen. Bereits gespeicherte 128 × 128-Blätter bleiben lesbar und werden beim Bearbeiten pixelgenau auf 1000 × 1000 hochskaliert.

Ein Referenzbild oder eine Animationsbox lässt sich auf das Blatt ziehen. Aus dem geöffneten Filmstreifen lässt sich auch ein bestimmter Frame auf das Blatt ziehen. Das Bild wird passend auf die Blattfläche skaliert und ist danach Teil der dort bearbeitbaren Pixel; die ursprüngliche Referenz oder Animation bleibt unverändert. Jeder bestätigte Strich wird mit der gemeinsamen Ideenwand geteilt. Bei einem Versionskonflikt oder Netzabbruch bleibt ein noch nicht bestätigter Blattentwurf in der laufenden App offen, statt fremde Arbeit still zu überschreiben.

## Stapel verbinden und trennen

Eine Box **an beliebiger Stelle** ziehen – auch am Text. Ein Klick alleine bearbeitet nichts. Die nachfolgenden verbundenen Elemente bewegen sich mit. Um eine Verbindung zu lösen, die gewünschte Box über den magnetischen Bereich hinaus auf eine freie Stelle ziehen und loslassen.

Unten, links und rechts gibt es je eine magnetische Andockstelle. Eine helle Linie zeigt das Ziel; loslassen verbindet die Boxen. Die Ansicht verteilt die Zweige so, dass sie sich nicht überlagern. Jede der drei Seiten kann genau ein direkt verbundenes Element haben; weitere Elemente können daran hängen.

Beim Darüberfahren oder schon beim Annähern von außen erscheint ein **+** nur an den freien Seiten **unten, links und rechts**; oben nie. Zwischen verbundenen Boxen steht kein Plus. Das Plus bleibt beim Anfahren anklickbar und öffnet eine kleine Auswahl für Text, die drei Listenarten oder ein Bild. Das neue Element wird an genau dieser freien Seite angeheftet.

| Gegriffenes Element | Was sich bewegt |
| --- | --- |
| Ganz oben | Der gesamte verbundene Zweig |
| In der Mitte | Dieses Element mit seinen nachfolgenden Zweigen; der obere Teil bleibt stehen |
| Ganz unten | Nur das letzte Element |

Kreise und widersprüchliche Verbindungen werden abgewiesen. Ein **Text am Anfang eines freien Zweigs ist automatisch größer und fett** und als Haupttitel erkennbar; verbundene Texte sind normal. Es gibt keine separate Titel-Einstellung.

Ein **Rechtsklick auf eine Box** zeigt **Löschen**, **Kopieren**, **Ausschneiden**, **Duplizieren** und direkt darunter sieben kräftigere Farbfelder ohne weiteres Untermenü. **Kopieren** oder **Ausschneiden** nimmt genau das angeklickte Element samt allen daran hängenden Nachfolgern mit – niemals die Elemente oberhalb. Eine Mehrfachauswahl lässt sich mit **Strg+C** kopieren oder mit **Strg+X** ausschneiden. Erst nach erfolgreichem Kopieren in die Zwischenablage wird gelöscht. Die Farbe gehört nur dieser Box; bereits gespeicherte alte Pastellfarben bleiben erhalten. Ein noch nicht übernommener Konfliktentwurf zeigt aus Sicherheitsgründen stattdessen seine Wiederherstellungsaktionen, damit kein Text verloren geht. Bei sehr wenig Platz lässt sich das Menü mit dem Mausrad scrollen. Abgehakte Checklistenpunkte werden durchgestrichen.

## Auf der Wand bewegen

- Rechte oder mittlere Maustaste über freie Fläche ziehen: Ausschnitt verschieben. Ein ruhiger Rechtsklick öffnet das Kontextmenü.
- **Linke Maustaste** über freie Fläche ziehen: Auswahlrechteck für mehrere Boxen. Am Fensterrand verschiebt sich der Ausschnitt weiter, solange die Taste gehalten wird; so erreicht die Auswahl auch Elemente außerhalb des sichtbaren Bereichs. **Strg oder Umschalt + Ziehen** ergänzt die vorhandene Auswahl. Ausgewählte Boxen von jeder Stelle aus gemeinsam verschieben.
- Mausrad: Wand vertikal verschieben. Umschalt+Mausrad: horizontal verschieben. Karten und Schrift behalten ihre feste Pixelgröße.
- **Entf/Rücktaste** löscht alle ausgewählten Boxen in einer gemeinsamen Aktion; übrig gebliebene Zweige werden als freie Elemente erhalten.
- **Strg+A/C/X/V/D**: alles auswählen, kopieren, ausschneiden, einfügen, duplizieren. Kopierte Boxen behalten Text, Listenstatus, Referenzbild, Tag-Verknüpfung, gewählten absoluten Frame und Verbindungen; beim Einfügen erhalten sie neue IDs.
- **Strg+Z/Y**: eigener Notizverlauf, einschließlich der Mehrfachaktionen. Während der Texteingabe zunächst nur Eingabe-Undo.

## Gemeinsam bearbeiten

Alle dürfen Elemente erstellen, ändern und verschieben. Bestätigte Änderungen werden geteilt. Text wird beim Übernehmen gesendet, nicht bei jedem Buchstaben.

Oben rechts in jeder Box steht der Name der Person, die sie zuletzt geändert hat; direkt nach dem Einfügen ist dies die erstellende Person. Der Host-Server ordnet Änderungen dem angemeldeten Sitzungsnamen zu. Die Zuordnung bleibt mit dem Bild gespeichert. Bereits vorhandene Boxen aus alten Dateien haben keine nachträglich erfundene Autorenschaft. Aseprite zeigt den Beitritt und das Verlassen anderer Personen als kurze native Hinweise unten rechts.

Kurze Feldreservierungen und Revisionsprüfungen verhindern stilles Überschreiben. Bei einem Konflikt bleibt der lokale Entwurf erhalten; ein roter Rand/Punkt markiert ihn. **Rechtsklick** bietet „Entwurf kopieren“, „Gemeinsamen Text ansehen“, „Meinen Text übernehmen“ oder „Entwurf verwerfen“. Ein Übernehmen erfolgt nie automatisch über fremden Text.

Eine kurz unterbrochene Sitzung kann ausstehende Aktionen wiederholen, ohne sie doppelt anzuwenden. Gastbeiträge bleiben beim Host nach dem Verlassen. Bild-Undo und Notiz-Undo bleiben getrennt.

## Am Bild gespeichert

**Host: die Sitzungskopie als .aseprite oder .ase speichern.** Text, Listen, Farben, Verbindungen und Referenzbild-Pixel liegen in der Datei. Animationsboxen speichern den Namen und ursprünglichen Startframe des Tags sowie den bestätigten Auswahlframe; ihre Vorschau rendert die Pixel aus dem geöffneten Bild. Nach dem Umbenennen oder Entfernen eines Tags meldet die Box „Tag fehlt“, bis der Bezug wiederhergestellt wird. Es werden keine externen Bildpfade gespeichert. Referenzbilder bleiben deshalb nach Umbenennen, Verschieben oder auf einem anderen PC sichtbar.

Ohne aktive Sitzung lassen sich eigene Bildnotizen ebenfalls bearbeiten. Beim Öffnen einer Datei mit Notizen erscheint die Wand automatisch einmal; nach bewusstem Schließen bleibt sie bis zum erneuten Öffnen geschlossen. Eine leere Datei öffnet nicht ungefragt die Wand.

PNG, GIF und Spritesheets enthalten keine Ideenwand. Die native Arbeitsdatei zusätzlich behalten. Bei Gästen gilt die bestehende Speicher-/Exportsperre, aber weiterhin **kein Kopierschutz**: zum gemeinsamen Arbeiten empfängt der Gast die Daten.

## Alte Notizen und Grenzen

Alte Karten werden beim Lesen übernommen: Format 1 wird zuerst in bisheriger Reihenfolge zu Stapeln gewandelt, Format 2 erhält seine vertikalen Verbindungen und bekommt freie Seitenplätze, Format 3 bleibt einschließlich aller Verzweigungen erhalten, Format 4 übernimmt bei Animationsboxen den bisherigen Tag-Startframe als Auswahl, Format 5 erhält die neue Autorenliste und Format 6 bis 8 bleiben einschließlich Autoren und Blattpixeln erhalten. IDs, Titel, Notiztexte, Farben und alte Status-Metadaten bleiben erhalten. Die ursprüngliche Datei wird erst beim Speichern aktualisiert. Vor dem ersten Speichern mit dieser Version eine Dateikopie behalten; ältere Collabsprite-Versionen können Format 9 nicht bearbeiten.

- Maximal **128 Boxen**, **4096 UTF-8-Bytes Text pro Box** und **128 Listenpunkte**.
- Direkt importierte Referenzen werden proportional auf höchstens **512 × 512** verkleinert; bestätigte Skizzenbilder behalten **1000 × 1000**. Originaldateien bleiben unverändert. Sehr große Quellen über 8192 × 8192 werden abgewiesen.
- Animationsvorschauen rendern nur Sprites bis **4 Millionen Canvas-Pixel**. Bei größeren Sprites bleiben Tag-Verknüpfung und Frame-Auswahl erhalten, die Miniaturbilder werden aus Speicherschutzgründen nicht erzeugt.
- Insgesamt **8 MiB** inklusive bis zu 20 Löschgruppen im Papierkorb. Bilder und Skizzen benötigen den meisten Platz. Beim Speichern als `.aseprite` verteilt Collabsprite die Ideenwand auf überprüfte Metadatenabschnitte unter Aseprites Einzelwert-Grenze, damit auch ein Blatt nach dem erneuten Öffnen vollständig bleibt.
- Persönlicher Notizverlauf: bis 32 Aktionen / 16 MiB pro Person während der laufenden Sitzung. Das Gesamtlimit kann große Löschgruppen aus dem Papierkorb verdrängen.
- Unbestätigte Entwürfe existieren nur in der laufenden App. **Ein Absturz oder erzwungenes Beenden kann sie verlieren.**
- Gemeinsame Bestätigung ist noch keine manuelle Dateispeicherung durch den Host.
- Die native Aseprite-Schrift bestimmt, welche Zeichen sichtbar sind; der gespeicherte Unicode-Text bleibt unverändert.
- Die Ideenwand ist ein separates **Aseprite-Dialogfenster**, keine angedockte Leiste und kein Browserfenster.

Normale Texte kommen direkt von Aseprite. Für Haupttitel ist eine eingebettete Variante von Atkinson Hyperlegible unter der [SIL Open Font License](../extension/notes-font-OFL.txt) enthalten.
