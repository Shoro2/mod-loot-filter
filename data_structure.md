# File and directory structure — mod-loot-filter

> Static inventory. Maintain this when adding/removing files.

## Tree

```
mod-loot-filter/
├── conf/
│   ├── conf.sh.dist                       # Build: SQL path registration for auto-update
│   └── loot_filter.conf.dist              # Module configuration (template)
├── data/sql/
│   └── db-characters/
│       └── loot_filter_tables.sql         # Schema: character_loot_filter + ..._settings
├── Loot_Filter_LUA/
│   ├── LootFilter_Client.lua              # AIO client UI (frame, lists, form, presets)
│   └── LootFilter_Server.lua              # AIO server logic: handlers, DB calls
├── src/
│   ├── LootFilter.h                       # Header: enums (Condition, Op, Action), constants
│   ├── LootFilter.cpp                     # Core: eval logic, Sell/DE/Delete, hooks, commands
│   └── mod_loot_filter_loader.cpp         # Loader: Addmod_loot_filterScripts()
├── include.sh                             # Build integration (registers SQL paths)
├── pull_request_template.md               # GitHub PR template (if present)
├── CLAUDE.md                              # Detailed content doc
├── README.md                              # GitHub readme (short)
├── log.md                                 # Commit log (modular)
├── data_structure.md                      # This file
└── functions.md                           # Mechanics and function reference
```

## File purposes

| File | Purpose |
|-------|-------|
| `conf/loot_filter.conf.dist` | `LootFilter.Enable`, `AllowSell`, `AllowDisenchant`, `AllowDelete`, `LogActions`, `MaxRulesPerChar` |
| `conf/conf.sh.dist` | sourced by AzerothCore during auto-update, lists SQL paths |
| `data/sql/db-characters/loot_filter_tables.sql` | Schema + migration for the `conditionOp` column |
| `Loot_Filter_LUA/LootFilter_Server.lua` | Eluna script, registers server handlers (`AddRule`, `DeleteRule`, `ToggleRule`, `ToggleFilter`, `UpdatePriority`, `DeleteAllRules`, `RequestData`) |
| `Loot_Filter_LUA/LootFilter_Client.lua` | WoW frame code (sent to the client via AIO): rule list, add form, preset buttons, minimap button, stats display |
| `src/LootFilter.h` | Enums: `LootFilterCondition`, `LootFilterOp`, `LootFilterAction`. Constants. |
| `src/LootFilter.cpp` | Hooks (`OnPlayerLogin`, `OnPlayerLootItem`, `OnPlayerLogout`, `OnAfterConfigLoad`), eval functions, action implementations |
| `src/mod_loot_filter_loader.cpp` | `Addmod_loot_filterScripts()` — entry point |
| `include.sh` | Build integration: source `conf/conf.sh.dist` |

## Size notes (as of 2026-05-01)

- All C++ files < 50 KB → individually readable
- All Lua files < 30 KB → individually readable
- SQL schema ~3 KB → individually readable

## External dependencies

- **azerothcore-wotlk** (core): `PlayerScript`, `WorldScript`, `CommandScript`, `Item`, `LootTemplates_Disenchant`, prepared statement API.
- **AIO framework**: `lua_scripts/AIO.lua` + dependencies (from `share-public/AIO_Server/`).
- **mod-paragon-itemgen** (optional): "Is Cursed" condition checks slot 11 enchantment IDs (920001 / 950001-950099).
- **mod-endless-storage** (optional): the Keep action and DE action can deposit items directly into `custom_endless_storage` instead of into the inventory.
- **mod-auto-loot** (optional): provides the `OnPlayerLootItem` events this module reacts to.

## DB tables (`acore_characters`)

| Table | PK | Contents |
|---------|----|--------|
| `character_loot_filter` | `ruleId` (auto) | Rules per character |
| `character_loot_filter_settings` | `characterId` | Master toggle + statistics |

## SQL convention for new migrations

New schema changes go into `data/sql/db-characters/<description>.sql` with `IF NOT EXISTS`/idempotent statements. Auto-update detects new files automatically.
