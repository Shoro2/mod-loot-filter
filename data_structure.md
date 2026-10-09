# File and directory structure — mod-loot-filter

> Static inventory. Maintain this when adding/removing files.

## Tree

```
mod-loot-filter/
├── conf/
│   ├── conf.sh.dist                       # Build: SQL path registration for auto-update
│   └── loot_filter.conf.dist              # Module configuration (template)
├── data/sql/db-characters/
│   └── loot_filter_tables.sql             # Schema: rule, condition, settings (idempotent)
├── docs/superpowers/
│   ├── specs/2026-10-09-loot-filter-ui-rework-design.md   # approved design of the rework
│   └── plans/2026-10-09-loot-filter-ui-rework.md          # its implementation plan
├── lua_scripts/                           # deployed to <server>/lua_scripts/LootFilter/
│   ├── LootFilter_Client.lua              # the window, shipped to the client by AIO
│   └── LootFilter_Server.lua              # empty stub (overwrites the old AIO handlers)
├── src/
│   ├── LootFilter.h                       # AddLootFilterScripts()
│   ├── LootFilter.cpp                     # core glue: cache, hooks, actions, messages, commands
│   ├── LootFilterRules.h                  # pure rule logic (no core includes besides Define.h)
│   └── mod_loot_filter_loader.cpp         # Addmod_loot_filterScripts()
├── tests/
│   ├── build_offline.cmd                  # builds + runs rules_test and client_test (writes build/)
│   ├── rules_test.cpp                     # LootFilterRules.h: 204 checks
│   ├── client_test.lua                    # the window against a mocked FrameXML API: 93 checks
│   └── schema_test.ps1                    # the SQL twice on a scratch schema (workbench MySQL)
├── include.sh                             # Build integration (registers SQL paths)
├── CLAUDE.md, INDEX.md, README.md, data_structure.md, functions.md, log.md, todo.md
└── .gitignore                             # build/
```

`src/` is the only folder AzerothCore compiles (`GetPathToModuleSource` → `<module>/src`), so `tests/`
never reaches the worldserver. `LootFilterRules.h` is header-only: no CMake re-configure is needed.

## File purposes

| File | Purpose |
|-------|-------|
| `src/LootFilterRules.h` | `Condition`, `Rule`, `ItemFacts`, `Verdict`; `Matches`, `Evaluate`; `ValidCondition`, `ValidRule`; codec (`EncodeRule`, `DecodeRule`, …); ordering (`Insert`, `Move`, `Remove`); bag addressing; `MigrateCharacter` |
| `src/LootFilter.cpp` | `WorldScript` (config, startup migration, rule-id counter), `PlayerScript` (login/logout cache, loot hook, addon-message intake, character deletion), `CommandScript` (`.lootfilter`) |
| `lua_scripts/LootFilter_Client.lua` | window: Rules tab + editor, Test tab, Log tab, minimap button, slash commands; global `LootFilterUI` (model + functions) and `LootFilter_Toggle()` |
| `data/sql/db-characters/loot_filter_tables.sql` | creates the three tables; adds `chatMode`/`totalStored` and widens `totalSold` on an old settings table |
| `conf/loot_filter.conf.dist` | `LootFilter.Enable`, `AllowSell`, `AllowDisenchant`, `AllowDelete`, `LogActions`, `MaxRulesPerChar` |

## DB tables (`acore_characters`)

| Table | PK | Contents |
|---------|----|--------|
| `character_loot_filter_rule` | `ruleId` (assigned by the core) | characterId, position (1-based order), action, enabled |
| `character_loot_filter_condition` | (`ruleId`, `slot`) | type, op, value, value2, text |
| `character_loot_filter_settings` | `characterId` | filterEnabled, chatMode, totalSold, totalDisenchanted, totalDeleted, totalStored |
| `character_loot_filter_legacy` | `ruleId` | the old one-condition rows, renamed after the migration; not read |

## External dependencies

- **azerothcore-wotlk** (core): ScriptMgr hooks, `Item`, `LootTemplates_Disenchant`, DBC stores (random
  property/suffix names for item links).
- **mod-ale + AIO** (`lua_scripts/AIO_Server/`): ship the window to the client.
- **mod-paragon-itemgen** (optional): slot 11 enchant ids behind the "cursed" condition.
- **mod-endless-storage** (optional): the `custom_endless_storage` table (To storage, disenchant mats).
- **mod-auto-loot** (optional): AoE loot fires the same `OnPlayerLootItem`.
