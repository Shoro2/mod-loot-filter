# mod-loot-filter

> Lies zuerst [`INDEX.md`](./INDEX.md). Mechanik & Hooks: [`functions.md`](./functions.md). Folder-Layout: [`data_structure.md`](./data_structure.md). Offenes: [`todo.md`](./todo.md). Commit-Spur: [`log.md`](./log.md).

## Was ist das Modul?

AzerothCore-Modul für **WoW 3.3.5a (WotLK)**. Bietet ein regelbasiertes **automatisches Item-Filterungssystem** für gelootete Gegenstände: der Spieler legt eigene Filterregeln per AIO-UI an, und passende Items werden anschließend automatisch verkauft (Vendor), entzaubert oder gelöscht. Eine Whitelist-Aktion ("Keep") erlaubt das Schützen wertvoller Items vor breiteren Regeln.

Per-Character — jeder Charakter hat seine eigenen Regeln, gespeichert in `acore_characters`.

## Rolle im Gesamtprojekt

```
Loot-Quelle (manuell, mod-auto-loot)
        │
        ▼ sScriptMgr->OnPlayerLootItem()
        │
   ┌────┴────────────────────────────────────────┐
   ▼                                              ▼
mod-paragon-itemgen  (Bonus-Stats anwenden)   mod-loot-filter  (filtern: Keep / Sell / DE / Delete)
```

Das Modul hängt am gemeinsamen `OnPlayerLootItem`-Hook. Es funktioniert sowohl mit mod-auto-loot (AOE-Loot im Radius) als auch mit manuellem Looting. Es erwartet **kein** spezielles Hook-Pattern — die Regelauswertung läuft pro Item, das im Inventar landet.

## Custom-Daten

| Typ | Eintrag | Bemerkung |
|-----|--------|-----------|
| **DB-Tabellen (acore_characters)** | `character_loot_filter` | Per-Char Regeln (Bedingung, Operator, Wert, Aktion, Priorität, enabled) |
| | `character_loot_filter_settings` | Master-Toggle + Statistik (totalSold, totalDisenchanted, totalDeleted) |
| **DBC-Patches** | keine | |
| **Custom-Spells** | keine | |
| **Custom-Items/NPCs** | keine | |
| **AIO-Handler-Namen** | `LF` (Server) / `LF_Client` (Client) | Details: [`functions.md`](./functions.md#aio-handler) |
| **Slash-Commands** | `/lf`, `/lootfilter` | öffnet die Filter-UI |
| **GM-Commands** | `.lootfilter reload`, `.lootfilter toggle`, `.lootfilter stats` | alle `SEC_PLAYER` |

## Filter-Mechanik (Top-Level)

| Bedingungstyp | Operatoren |
|---------------|------------|
| Quality, Item Level, Sell Price, Item Class, Item Subclass, Item ID | `=`, `>`, `<` |
| Cursed Status | bool |
| Name Contains | substring |

Aktionen: **Keep** (Whitelist) / **Sell** (Vendor) / **Disenchant** (mit Skill-Fallback auf Sell) / **Delete**. Regeln laufen in Prioritäts-Reihenfolge — niedrigster Wert zuerst, **erster Match gewinnt**.

Cursed-Erkennung: Modul liest Slot-11-Enchantment auf jedem Item. Werte `920001` ("Cursed"-Marker) und Range `950001-950099` (Passive-Spells) werden als "cursed" gewertet. → Abhängigkeit zu mod-paragon-itemgen für die Slot-11-Convention.

## Konfiguration (Top-Level)

`conf/loot_filter.conf.dist`:

- `LootFilter.Enable` (Master-Toggle)
- `LootFilter.AllowSell`, `AllowDisenchant`, `AllowDelete`
- `LootFilter.LogActions`
- `LootFilter.MaxRulesPerChar = 30`

Details und Defaults: [`functions.md`](./functions.md#konfiguration).

## Was das Modul **nicht** tut

- **kein** AH-/Mail-Filter — wirkt nur auf `OnPlayerLootItem`-Events
- **kein** Auto-Use (z.B. Quest-Items automatisch öffnen)
- **kein** Equipment-Auto-Equip
- **kein** Bulk-Import / -Export von Regelsets — Regeln müssen per UI angelegt werden (siehe [`todo.md`](./todo.md))
- **keine** Server-Defaults — neue Charaktere starten ohne Regeln (siehe [`todo.md`](./todo.md))

## Lizenz

GPL v2.
