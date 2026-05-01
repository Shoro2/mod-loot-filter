# Datei- und Verzeichnisstruktur — mod-loot-filter

> Statisches Inventar. Bei Hinzufügen/Löschen von Files hier mitpflegen.

## Tree

```
mod-loot-filter/
├── conf/
│   ├── conf.sh.dist                       # Build: SQL-Pfad-Registrierung für Auto-Update
│   └── loot_filter.conf.dist              # Modul-Konfiguration (Template)
├── data/sql/
│   └── db-characters/
│       └── loot_filter_tables.sql         # Schema: character_loot_filter + ..._settings
├── Loot_Filter_LUA/
│   ├── LootFilter_Client.lua              # AIO Client-UI (Frame, Listen, Form, Presets)
│   └── LootFilter_Server.lua              # AIO Server-Logik: Handler, DB-Calls
├── src/
│   ├── LootFilter.h                       # Header: Enums (Condition, Op, Action), Konstanten
│   ├── LootFilter.cpp                     # Core: Eval-Logik, Sell/DE/Delete, Hooks, Commands
│   └── mod_loot_filter_loader.cpp         # Loader: Addmod_loot_filterScripts()
├── include.sh                             # Build-Integration (registriert SQL-Pfade)
├── pull_request_template.md               # GitHub PR-Template (falls vorhanden)
├── CLAUDE.md                              # Detaillierte Inhalts-Doku
├── README.md                              # GitHub-Readme (kurz)
├── log.md                                 # Commit-Log (modular)
├── data_structure.md                      # Diese Datei
└── functions.md                           # Mechanik- und Funktions-Referenz
```

## Datei-Zwecke

| Datei | Zweck |
|-------|-------|
| `conf/loot_filter.conf.dist` | `LootFilter.Enable`, `AllowSell`, `AllowDisenchant`, `AllowDelete`, `LogActions`, `MaxRulesPerChar` |
| `conf/conf.sh.dist` | wird von AzerothCore beim Auto-Update gesourct, listet SQL-Pfade |
| `data/sql/db-characters/loot_filter_tables.sql` | Schema + Migration für `conditionOp`-Spalte |
| `Loot_Filter_LUA/LootFilter_Server.lua` | Eluna-Script, registriert Server-Handler (`AddRule`, `DeleteRule`, `ToggleRule`, `ToggleFilter`, `UpdatePriority`, `DeleteAllRules`, `RequestData`) |
| `Loot_Filter_LUA/LootFilter_Client.lua` | WoW-Frame-Code (per AIO an Client gesendet): Regelliste, Add-Form, Preset-Buttons, Minimap-Button, Stats-Display |
| `src/LootFilter.h` | Enums: `LootFilterCondition`, `LootFilterOp`, `LootFilterAction`. Constants. |
| `src/LootFilter.cpp` | Hooks (`OnPlayerLogin`, `OnPlayerLootItem`, `OnPlayerLogout`, `OnAfterConfigLoad`), Eval-Funktionen, Action-Implementierungen |
| `src/mod_loot_filter_loader.cpp` | `Addmod_loot_filterScripts()` — Einstiegspunkt |
| `include.sh` | Build-Integration: source `conf/conf.sh.dist` |

## Größenhinweise (Stand: 2026-05-01)

- Alle C++-Files je < 50 KB → einzeln lesbar
- Lua-Files je < 30 KB → einzeln lesbar
- SQL-Schema ~3 KB → einzeln lesbar

## Externe Abhängigkeiten

- **azerothcore-wotlk** (Core): `PlayerScript`, `WorldScript`, `CommandScript`, `Item`, `LootTemplates_Disenchant`, Prepared-Statement-API.
- **AIO Framework**: `lua_scripts/AIO.lua` + Dependencies (aus `share-public/AIO_Server/`).
- **mod-paragon-itemgen** (optional): "Is Cursed"-Condition prüft Slot-11-Enchantment-IDs (920001 / 950001-950099).
- **mod-endless-storage** (optional): Keep-Action und DE-Action können Items direkt in `custom_endless_storage` deponieren statt ins Inventar.
- **mod-auto-loot** (optional): liefert die `OnPlayerLootItem`-Events, auf die dieses Modul reagiert.

## DB-Tabellen (`acore_characters`)

| Tabelle | PK | Inhalt |
|---------|----|--------|
| `character_loot_filter` | `ruleId` (auto) | Regeln pro Charakter |
| `character_loot_filter_settings` | `characterId` | Master-Toggle + Statistiken |

## SQL-Konvention für neue Migrationen

Neue Schema-Änderungen kommen in `data/sql/db-characters/<beschreibung>.sql` mit `IF NOT EXISTS`/idempotenten Statements. Auto-Update erkennt Neuzugänge automatisch.
