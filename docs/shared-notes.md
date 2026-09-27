# Ideenwand: freie Elemente und magnetische Stapel

Diese Anleitung beschreibt den **Release 0.10.0 Beta / Protokoll 7**. Sie ersetzt die Karten-/Unterpunkt-Bedienung aus 0.8.x. Host und Gäste benötigen denselben neuen Installer.

## Eine freie Fläche

Die Wand hat keine Suchleiste, Werkzeugleiste oder dauerhaften Aktionsbuttons. Öffnen über **Ansicht → Collabsprite → Gemeinsame Notizen**. Der Fenstertitel nennt das zugehörige Bild. **X** schließt nur diese Ansicht, nicht die Sitzung.

Rechtsklick auf die freie Fläche:

- **Text**: eine leere Box erscheint, direkt losschreiben.
- **Checkliste**, **Punktliste**, **Nummerierte Liste**: jede Zeile ist ein Listenpunkt; bei Checklisten Kästchen anklicken.
- **Referenzbild …**: im Dateidialog PNG, JPG/JPEG, WebP, GIF oder BMP auswählen. Bei Animationen wird das erste Bild verwendet.

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

Rechtsklick auf eine Box zeigt **sieben Pastellfarben**. Die Farbe gehört nur dieser Box, nicht dem gesamten Stapel. Bei Listen lässt sich dort auch die Listenart umstellen.

## Auf der Wand bewegen

- Leere Fläche ziehen oder mittlere Maustaste: Ausschnitt verschieben.
- Mausrad: um den Mauszeiger zoomen. Umschalt+Mausrad: vertikal verschieben.
- Rechtsklick → **Alles ins Bild**: alle Elemente sichtbar machen.
- Rechtsklick → **Element löschen**: nur diese Box löschen; der verbleibende Stapel wird wieder verbunden.
- **Teilstapel löschen** entfernt zusätzlich alles darunter.
- **Entf/Rücktaste** bei ausgewählter, nicht bearbeiteter Box löscht nur diese.
- **Strg+Z/Y**: eigener Notizverlauf. Während der Texteingabe zunächst nur Eingabe-Undo. Rechtsklick bietet Rückgängig und die letzte Löschwiederherstellung.

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
