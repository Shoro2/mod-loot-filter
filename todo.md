# TODOs — mod-loot-filter

> Offene Aufgaben für dieses Modul. Erledigte TODOs in `log.md` festhalten und hier entfernen.

## Sicherheit

- [ ] **(mittel)** SQL-Injection-Risiko in Lua: `LootFilter_Server.lua` nutzt `CharDBExecute` mit String-Concat (Eluna kennt keine Prepared Statements). Mitigation: pro Handler-Arg explizite Validierung (Typ-Check, Whitelist für `conditionType`/`action`/`operator`, Length-Limit für `conditionStr`).

## Funktionale Verbesserungen

- [ ] **(niedrig)** Per-Item-Klassen-Konfiguration für `LootTemplates_Disenchant`: aktuell wird das globale Disenchant-Template verwendet. Wäre nett: optional pro Quality-Stufe einen Bonus-Faktor.
- [ ] **(niedrig)** Bulk-Import / Export von Filter-Regeln (z.B. JSON-String per Slash-Command), damit Spieler Regelsets teilen können.
- [ ] **(niedrig)** Regel-Templates als Server-Defaults: aktuell sind nur die Preset-Buttons in der UI verdrahtet. Server-seitige Default-Regeln pro neuem Charakter wären sinnvoll.

## Doku

- [ ] keine offenen Punkte.

## Konvention

Erledigte Items NICHT durchstreichen — entfernen und in `log.md` dokumentieren.
