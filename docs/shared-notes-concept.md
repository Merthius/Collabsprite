# Collabsprite – Gemeinsame Ideenwand

Historischer Entwurf vom 27.09.2026, vor der Umsetzung. **Durch 0.8.0 umgesetzt; aktuelle Bedienung und geprüfte Grenzen stehen in [Gemeinsame Ideenwand](shared-notes.md).** Die folgenden Vorschläge bleiben zur Nachvollziehbarkeit unverändert. Abweichung: Texte werden bewusst mit „Übernehmen“ geteilt, nicht automatisch bei jedem Tippen; Fenstertitel „Ideenwand“ mit eigener Zeile „Bild:“.

## Grundidee

Zu jedem Bild gehört eine gemeinsame Ideenwand aus verbundenen Karten. Host und Gäste können Ideen gleichberechtigt hinzufügen, ändern und ordnen. Die Wand ist kein Chat: Sie hält fest, was zum Bild gehört und wie es gestaltet werden soll.

Beispiel – jede eckige Klammer entspricht einer Karte, jede Verbindung einer Unterordnung:

```text
[Hexe]
  ├── [Kleidung]
  │     └── [Kleid]
  │           ├── [Farbe: Dunkelviolett]
  │           └── [Details: Flicken, ausgefranster Saum]
  └── [Waffe / Werkzeug]
        └── [Besen]
              ├── [Stiel: krummes Holz]
              ├── [Borsten: strohgelb]
              └── [Besonderheit: leuchtet beim Fliegen]
```

Die eigentliche Oberfläche zeigt Karten und Verbindungslinien, keine eingerückte Textliste. Mehrere Hauptkarten sind möglich, zum Beispiel „Hexe“, „Haus“ und „Animationen“.

## Öffnen und schließen

- Beim Erstellen oder Beitreten einer Sitzung öffnet sich die zum Bild gehörende Ideenwand einmal automatisch. Bei einem gespeicherten Bild mit vorhandenen Notizen erscheint sie auch beim erneuten Öffnen des Bildes einmal.
- Ein normales, schließbares Fenster mit dem Titel **„Notizen – Bildname“**. Es blockiert das Zeichnen nicht; keine zusätzliche App und kein Browser erforderlich.
- **X** schließt nur das eigene Fenster. Inhalte, Zusammenarbeit und das Fenster der anderen bleiben erhalten. Fremde Änderungen und kurze Wiederverbindungen öffnen es nicht erneut.
- Wieder öffnen über **Ansicht → Collabsprite → Gemeinsame Notizen**. Auch ohne aktive Sitzung soll der Besitzer die gespeicherten Notizen lesen und bearbeiten können.
- Bei mehreren Bildern muss immer eindeutig sein, zu welchem Bild die Wand gehört. Ein Wechsel des Bild-Tabs darf unbestätigten Text nicht verwerfen oder einem anderen Bild zuordnen.

## Kompakte Bedienung

Oben reichen **„+ Karte“**, **Suche** und **„Alles anzeigen“**. Weitere Aktionen erscheinen an der ausgewählten Karte oder per Rechtsklick.

- Eine Karte hat einen kurzen **Titel** und bei Bedarf einen **Notiztext**. Lange Texte öffnen sich zur Bearbeitung, statt die gesamte Wand zu überladen.
- **„+ Unterkarte“** verbindet eine neue Karte automatisch mit der ausgewählten Karte. Karten lassen sich verschieben und einem anderen Zweig zuordnen.
- **Automatisch anordnen** hält größere Wände lesbar. Unterzweige lassen sich einklappen; Mausrad zoomt, Ziehen auf freier Fläche verschiebt die Ansicht.
- Zoom, Ausschnitt, Auswahl und eingeklappte Zweige sind persönlich. Karteninhalte, Verbindungen und bewusst geänderte Kartenpositionen sind gemeinsam.
- Rechtsklick: Unterkarte, Umbenennen/Bearbeiten, Duplizieren, Löschen. Beim Löschen einer Karte mit Kindern: **„Unterkarten behalten“** oder **„Ganzen Zweig löschen“**. Kein unbeabsichtigter Verlust ganzer Ideenketten.

## Sinnvolle Ergänzungen

1. **Farbfelder mit HEX-Wert:** Besonders nützlich für Pixelart, zum Beispiel „Kleid: #5E3A79“. Ein Farbfeld ist eine optionale Eigenschaft, keine Pflicht für jede Karte.
2. **Kleiner Status:** „Idee“, „Festgelegt“ oder „Erledigt“. Optional und dezent, damit Vorschläge von beschlossenen Designs unterscheidbar sind.
3. **Eigene Änderungen zurücknehmen:** Notiz-Undo bleibt vom Pixel-Undo getrennt. Eine Rücknahme darf späteren Text anderer Personen nicht entfernen; im Konflikt wird sie nicht blind ausgeführt.
4. **Gelöschte Karten wiederherstellen:** Ein begrenzter Papierkorb schützt auch Unterkarten und ihre Verbindungen. Die Wiederherstellung ersetzt nicht die komplette aktuelle Wand.
5. **Bearbeitungshinweis:** Ein kleiner Name an einer gerade bearbeiteten Karte zeigt, dass dort jemand schreibt. Keine Pop-ups bei jeder Änderung und keine Chatfunktion.

Nicht für die erste Version nötig: Dateianhänge, freie Zeichnungen auf der Notizwand, Kommentare, Benachrichtigungsflut, komplexe Aufgabenverwaltung oder beliebige Querverbindungen. Eine klare Eltern-Kind-Struktur reicht für den gewünschten Ablauf und verhindert unübersichtliche Verbindungsnetze.

## Gemeinsames Bearbeiten ohne Textverlust

Verschiedene Karten sollen gleichzeitig bearbeitbar sein. Für dasselbe Textfeld empfehle ich zunächst eine **kurze Bearbeitungsreservierung**: „Mert bearbeitet diesen Text“. Sie endet beim Abschließen, Schließen oder nach einem begrenzten Verbindungsabbruch. Das reserviert keine Karte dauerhaft für eine Person; alle können jedes Feld bearbeiten, sobald es frei ist.

Versionen pro Feld und Bestätigungen durch den Host sichern Änderungen zusätzlich ab. Ein veralteter Entwurf darf neueren Text nicht still überschreiben. Er bleibt erhalten und wird zum Vergleichen angeboten. Unterschiedliche Felder derselben Karte können unabhängig geändert werden.

Kurze Textänderungen werden gebündelt übertragen; Zeichnen darf dadurch nicht stocken. Neue Gäste erhalten den aktuellen Stand. Bestätigte Beiträge bleiben erhalten, wenn ein Gast geht. Nach einem Abbruch werden bestätigte Änderungen nicht doppelt eingetragen; noch nicht bestätigte Entwürfe bleiben bis zum erfolgreichen Abgleich erhalten. Kein unkontrolliertes Offline-Zusammenführen.

## Mit dem Bild speichern

**Empfohlener Hauptweg: Notizen innerhalb der `.aseprite`-Datei speichern.** Aseprite bietet Erweiterungs-Eigenschaften an Sprites; das Dateiformat unterstützt diese Daten. Deshalb ist keine nur über den Dateinamen verknüpfte separate Notizdatei als Standard nötig. Dies ist eine technische Grundlage, noch kein getesteter Collabsprite-Speicherablauf. [API: Properties](https://www.aseprite.org/api/properties), [Dateiformat: User Data](https://github.com/aseprite/aseprite/blob/main/docs/ase-file-specs.md#user-data-chunk-0x2020).

- Der **Host** speichert Bild und Notizen gemeinsam. Gäste bearbeiten die gemeinsame Wand, benötigen aber keinen eigenen Speicherdialog. Die bisherige Gast-Speicherregel bleibt eine Bedienungssperre, kein Kopierschutz.
- Beim Start einer Sitzung werden bereits vorhandene Notizen aus dem geöffneten Bild in die Sitzungskopie übernommen. Das Original wird nicht heimlich überschrieben. Der Host speichert die **Sitzungskopie** mit den aktuellen Bild- und Notizänderungen.
- Öffnet der Host später diese gespeicherte Datei und startet eine neue Sitzung, stehen genau deren gespeicherte Notizen wieder zur Verfügung – auch neuen Gästen und nach Umbenennen oder Verschieben der Datei.
- **„Speichern unter“** nimmt die Wand in die neue Datei mit. Zwei getrennte Dateien werden dadurch nicht dauerhaft miteinander synchronisiert, auch wenn sie dieselbe Ursprungsversion der Wand enthalten.
- Bestätigte Notizen gehören zusätzlich in das vorhandene automatische Host-Sitzungsbackup. Dieses schützt vor Abstürzen, ersetzt aber nicht das bewusste Speichern der `.aseprite`-Datei.
- Die Anzeige unterscheidet **„Wird übertragen“**, **„Mit Host synchronisiert“** und **„In Datei gespeichert“**. Beim Gast darf eine Übertragungsbestätigung nicht fälschlich als gespeicherte Datei erscheinen.
- Auch reine Notizänderungen müssen als ungespeicherte Änderungen erkennbar sein. Schließen/Speichern wartet auf ausstehende Änderungen oder erklärt klar, was noch nicht bestätigt wurde.
- PNG und Spritesheet bleiben reine Bildexporte; dort werden die Notizen nicht als zuverlässig erhalten versprochen. Vor einem ausschließlich solchen Speichern: Hinweis, zusätzlich `.aseprite` zu behalten. Ein separater Notizexport kann später ergänzt werden, ist aber nicht der normale Arbeitsablauf.

## Technische Leitplanken für die Umsetzung

**Belegter Ausgangspunkt:** Collabsprite 0.7.0 hat noch kein Notizmodell. Die geprüften Snapshot-/Codec-Pfade übertragen keine entsprechenden Sprite-Eigenschaften. Eine Dateieigenschaft allein würde daher beim Erstellen der Sitzungskopie nicht genügen.

Vorgeschlagene Umsetzung:

- Eigenes versioniertes Datenformat mit stabilen Karten-IDs, Eltern-ID, Reihenfolge, Position, Titel, Text, optional Farbe/Status und Feldrevisionen. Ein Namespace wie `Merthius/Collabsprite` lässt fremde Erweiterungsdaten und die allgemeinen Benutzernotizen unangetastet.
- Board-Daten ausdrücklich in Aufnahme, Serverzustand, Beitritt, Wiederverbindung, Sitzungskopie und Backup einbeziehen. Eine Pixel-/Struktur-Wiederherstellung darf nicht nebenbei die Notizen zurücksetzen.
- Host prüft Operationen, Identität, Revisionen, erlaubte Feldwerte und Baumstruktur. Keine Zyklen, verwaisten Verbindungen, beliebigen Dateipfade oder ausführbaren Inhalte. Texte ausschließlich als Text behandeln.
- Größen-, Tiefen- und Ratenlimits vor Allokation prüfen; Wand iterativ durchlaufen. Keine Rückkehr zu unbeschränkter Rekursion oder UI-Arbeit direkt aus WebSocket-Callbacks. Inhalte gehören nicht ins Diagnoseprotokoll.
- Aseprites `Dialog:canvas()` bietet Zeichen- und Mausereignisse als Grundlage für die Kartenansicht. Ein nicht blockierender Dialog ist dokumentiert; ein beliebig angedocktes natives Panel wird nicht versprochen. [Dialog-API](https://www.aseprite.org/api/dialog#dialogcanvas).
- **Wichtiger Prüfpunkt:** Änderungen an Aseprite-Properties erzeugen Undo-Einträge. Notizspeicherung, Dirty-Zustand, vorhandenes persönliches Pixel-Undo und neuer Notiz-Verlauf müssen bewusst getrennt und gemeinsam getestet werden. Nicht bei jeder Taste unkontrolliert das gesamte Board in die Sprite-Properties schreiben. [Properties und Undo](https://www.aseprite.org/api/properties).

## Abnahmekriterien vor einer Veröffentlichung

- Host und mindestens zwei Gäste: parallele Kartenänderungen, Konkurrenz um dasselbe Feld, Löschen während fremder Bearbeitung, Wiederherstellung ohne fremde Änderungen zu verlieren.
- Später Beitritt, Gast verlässt, kurzer Abbruch und Wiederverbindung: bestätigte Notizen bleiben erhalten, Entwürfe gehen nicht still verloren.
- `.aseprite` speichern, schließen, neu öffnen, umbenennen, verschieben und „Speichern unter“: richtige Wand am richtigen Bild; unabhängige Kopien bleiben unabhängig.
- Sitzungskopie, Host-Backup, Wiederherstellung und Pixel-Undo verändern keine falsche Notizversion; reine Notizänderungen lösen einen korrekten Speicherhinweis aus.
- Mehrere offene Bilder, unterschiedliche UI-Skalierungen und große Wände: klare Zuordnung, bedienbare Karten und weiterhin flüssiges Zeichnen.
- Grenzen und beschädigte Daten: verständlicher Fehler, keine Abstürze, keine Überschreibung der bisherigen Wand, keine Notiztexte in Logs.

**Nächster Schritt wäre die Implementierung mit diesen Prüfungen. Dieser Entwurf verändert weder die Erweiterung noch den veröffentlichten Release.**
