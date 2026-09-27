# Ideenwand: freie Elemente und magnetische Stapel

Diese Anleitung beschreibt **Collabsprite 0.11.0 Beta / Protokoll 7**. Die Ideenwand ersetzt die Karten-/Unterpunkt-Bedienung aus 0.8.x.

Die Collabsprite-Fenster starten begrenzt auf einen Teil des Aseprite-Fensters. Die Ideenwand wird nicht zusätzlich mit der UI-Skalierung aufgeblasen. Der Schriftatlas wird in vierfacher Auflösung geglättet; schmalere Boxen mit kleineren Abständen lassen mehr Platz. Bei **45 % Zoom** bleiben Boxen und Text in einer besser lesbaren Bildschirmgröße, während ihre Positionen näher zusammenrücken. Unterhalb von 45 % schrumpfen sie wieder, damit auch weit verteilte Wände in die Ansicht passen. Aseprites eigene Bildschirm-Skalierung und native Dateiauswahl/Sicherheitsdialoge bleiben unverändert.

## Eine freie Fläche

Die Wand hat keine Suchleiste. Oben schwebt eine kleine abgerundete Werkzeuginsel mit **Text**, **Checkliste**, **Punktliste**, **nummerierter Liste** und **Referenzbild**. Ein Klick fügt die neue Box direkt in die sichtbare Wand ein; ein Text lässt sich sofort schreiben. Öffnen über **Datei → Multiplayer (Collabsprite) → Gemeinsame Notizen**. Der Fenstertitel nennt das zugehörige Bild. **X** schließt nur diese Ansicht, nicht die Sitzung.

Ein **Rechtsklick auf freie Fläche** bietet nur **Einfügen**: kopierte Ideenwand-Boxen samt Eigenschaften/Verbindungen, Text aus anderen Programmen oder ein Bild aus der Zwischenablage. Für Referenzbilder per Werkzeuginsel öffnet sich ein Dateidialog für PNG, JPG/JPEG, WebP, GIF und BMP; bei Animationen wird das erste Bild verwendet.

Text anklicken, um ihn zu ändern. **Enter** setzt eine neue Zeile. **Strg+Enter**, **Escape**, Klick daneben oder normales Schließen übernimmt den Entwurf. Escape verwirft keinen Text. Strg+A/C/X/V und Auswahl per Maus funktionieren im Textfeld. Lange Zeilen umbrechen automatisch.

## Stapel verbinden und trennen

Eine Box **am Rand bzw. am kleinen oberen Griff** ziehen. Der Textbereich dient zum Schreiben. Bildboxen lassen sich auch innen greifen.

Die Unterkante eines freien Stapels ist magnetisch: die gezogene Box nahe darunter bewegen. Eine helle Linie zeigt die Andockstelle; loslassen verbindet die Boxen.

| Gegriffenes Element | Was sich bewegt |
| --- | --- |
| Ganz oben | Der gesamte Stapel |
| In der Mitte | Dieses Element und alle darunter; der obere Teil bleibt stehen |
| Ganz unten | Nur das letzte Element |

Jede Box kann genau eine Box unter sich haben. Kreise und widersprüchliche Verbindungen werden abgewiesen. Ein **Text am Stapelanfang ist automatisch größer und fett**; weiter unten normal. Es gibt keine separate Titel-Einstellung.

Ein **Rechtsklick auf eine Box** zeigt **Löschen**, **Kopieren**, **Duplizieren** und direkt darunter sieben kräftigere Farbfelder ohne weiteres Untermenü. Unter Kopieren lässt sich ein einzelnes Element, ein Teilstapel oder eine Mehrfachauswahl kopieren. Die Farbe gehört nur dieser Box; bereits gespeicherte alte Pastellfarben bleiben erhalten. Ein noch nicht übernommener Konfliktentwurf zeigt aus Sicherheitsgründen stattdessen seine Wiederherstellungsaktionen, damit kein Text verloren geht. Bei sehr wenig Platz lässt sich das Menü mit dem Mausrad scrollen. Abgehakte Checklistenpunkte werden durchgestrichen.

## Auf der Wand bewegen

- Mittlere Maustaste ziehen: Ausschnitt verschieben.
- Linke Maustaste über freie Fläche ziehen: Auswahlrechteck für mehrere Boxen. Mit **Umschalt** wird zu einer vorhandenen Auswahl hinzugefügt. Ausgewählte Boxen am Rand gemeinsam verschieben.
- Mausrad: um den Mauszeiger zoomen. Umschalt+Mausrad: vertikal verschieben.
- Unten rechts: aktueller **Zoom in Prozent** und daneben **Alle Boxen**; der Knopf passt die Ansicht dynamisch an alle vorhandenen Boxen an, auch wenn sie weit auseinanderliegen.
- **Entf/Rücktaste** löscht alle ausgewählten Boxen in einer gemeinsamen Aktion; der verbleibende Stapel wird wieder verbunden.
- **Strg+A/C/V/D**: alles auswählen, kopieren, einfügen, duplizieren. Kopierte Boxen behalten Text, Listenstatus, Referenzbild und Verbindungen; beim Einfügen erhalten sie neue IDs.
- **Strg+Z/Y**: eigener Notizverlauf, einschließlich der Mehrfachaktionen. Während der Texteingabe zunächst nur Eingabe-Undo.

## Gemeinsam bearbeiten

Alle dürfen Elemente erstellen, ändern und verschieben. Bestätigte Änderungen werden geteilt. Text wird beim Übernehmen gesendet, nicht bei jedem Buchstaben.

Kurze Feldreservierungen und Revisionsprüfungen verhindern stilles Überschreiben. Bei einem Konflikt bleibt der lokale Entwurf erhalten; ein roter Rand/Punkt markiert ihn. **Rechtsklick** bietet gemeinsamen Text ansehen, eigenen Text übernehmen, kopieren oder Entwurf verwerfen. Ein Übernehmen erfolgt nie automatisch über fremden Text.

Eine kurz unterbrochene Sitzung kann ausstehende Aktionen wiederholen, ohne sie doppelt anzuwenden. Gastbeiträge bleiben beim Host nach dem Verlassen. Bild-Undo und Notiz-Undo bleiben getrennt.

## Am Bild gespeichert

**Host: die Sitzungskopie als .aseprite oder .ase speichern.** Text, Listen, Farben, Verbindungen und Referenzbild-Pixel liegen in der Datei. Es werden keine externen Bildpfade gespeichert. Referenzen bleiben deshalb nach Umbenennen, Verschieben oder auf einem anderen PC sichtbar.

Ohne aktive Sitzung lassen sich eigene Bildnotizen ebenfalls bearbeiten. Beim Öffnen einer Datei mit Notizen erscheint die Wand automatisch einmal; nach bewusstem Schließen bleibt sie bis zum erneuten Öffnen geschlossen. Eine leere Datei öffnet nicht ungefragt die Wand.

PNG, GIF und Spritesheets enthalten keine Ideenwand. Die native Arbeitsdatei zusätzlich behalten. Bei Gästen gilt die bestehende Speicher-/Exportsperre, aber weiterhin **kein Kopierschutz**: zum gemeinsamen Arbeiten empfängt der Gast die Daten.

## Alte Notizen und Grenzen

Alte Karten werden beim Lesen übernommen: pro Hauptkarte entsteht ein Stapel in bisheriger Reihenfolge, Unterzweige werden hintereinander angeordnet. IDs, Titel, Notiztexte, Farben und alte Status-Metadaten bleiben erhalten. Alte Status-/Hierarchie-Bedienelemente existieren nicht mehr. Die ursprüngliche Datei wird erst beim Speichern aktualisiert. Vor dem ersten Speichern mit dieser Beta eine Dateikopie behalten; ältere Collabsprite-Versionen können Format 2 nicht bearbeiten.

- Maximal **128 Boxen**, **4096 UTF-8-Bytes Text pro Box** und **128 Listenpunkte**.
- Referenzen werden proportional auf höchstens **512 × 512** verkleinert; Originaldateien bleiben unverändert. Sehr große Quellen über 8192 × 8192 werden abgewiesen.
- Insgesamt **8 MiB** inklusive bis zu 20 Löschgruppen im Papierkorb. Bilder benötigen den meisten Platz.
- Persönlicher Notizverlauf: bis 32 Aktionen / 16 MiB pro Person während der laufenden Sitzung. Das Gesamtlimit kann große Löschgruppen aus dem Papierkorb verdrängen.
- Unbestätigte Entwürfe existieren nur in der laufenden App. **Ein Absturz oder erzwungenes Beenden kann sie verlieren.**
- Gemeinsame Bestätigung ist noch keine manuelle Dateispeicherung durch den Host.
- Die gebündelte Schrift deckt vor allem lateinische Zeichen ab. Nicht unterstützte Zeichen werden als Ersatzzeichen dargestellt; der gespeicherte Unicode-Text bleibt unverändert.
- Das ist ein frei bewegliches Aseprite-Fenster, keine fest angedockte Editorleiste.

Die Schrift basiert auf **Atkinson Hyperlegible** vom Braille Institute, SIL Open Font License 1.1. Lizenz: `extension/notes-font-OFL.txt`; reproduzierbarer Atlas: `tools/build-notes-font.py`.
