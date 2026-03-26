# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Zentrales Projekt-Wiki**: Dieses Modul ist Teil eines Multi-Repo WoW-Server-Projekts. Die übergreifende Dokumentation, Zusatzinfos und Python-Tools befinden sich im [share-public](https://github.com/Shoro2/share-public) Repository:
> - [`CLAUDE.md`](https://github.com/Shoro2/share-public/blob/main/CLAUDE.md) — Gesamtarchitektur, SpellScript/DBC-Referenz, alle Custom-IDs, Modul-Übersicht
> - [`claude_log.md`](https://github.com/Shoro2/share-public/blob/main/claude_log.md) — Änderungshistorie, Projektpläne, priorisierte TODOs
>
> **Alle Änderungen an diesem oder den anderen Repos müssen dort geloggt werden.**

## Project Overview

**mod-loot-filter** is an AzerothCore module that provides automatic item filtering for items looted by [mod-auto-loot](https://github.com/Shoro2/mod-auto-loot). Players create filter rules via an AIO in-game UI, and matching items are automatically sold (vendor), disenchanted, or destroyed.

### Core Mechanics

- **Per-character filter rules** stored in `character_loot_filter` DB table
- **8 condition types**: Quality, Item Level, Sell Price, Item Class, Item Subclass, Cursed Status, Item ID, Name Contains
- **3 comparison operators**: Equals (=), Greater (>), Less (<) — selectable per rule for numeric conditions
- **4 actions**: Keep (whitelist), Auto-Sell, Disenchant, Delete
- **Priority system**: Rules are evaluated in priority order (lower = first); first match wins
- **AIO UI**: Full in-game frame with rule list, add form, presets, minimap button
- **Integration with mod-paragon-itemgen**: Detects cursed items via slot 11 enchantment (ID 920001 or 950001-950099)

### Filter Condition Types

| Type | ID | Description | Value |
|------|----|-------------|-------|
| Quality | 0 | Item quality (with operator) | 0=Poor, 1=Normal, 2=Uncommon, 3=Rare, 4=Epic, 5=Legendary |
| Item Level | 1 | Item level (with operator) | Numeric item level |
| Sell Price | 2 | Vendor price (with operator) | Copper amount |
| Item Class | 3 | Item class (with operator) | 0=Consumable, 2=Weapon, 4=Armor, 7=Trade Goods, etc. |
| Item Subclass | 4 | Item subclass (with operator) | Weapon/armor subtype |
| Is Cursed | 5 | Paragon cursed item | 1=cursed, 0=not cursed |
| Item ID | 6 | Specific item entry (with operator) | Item template entry ID |
| Name Contains | 7 | Name substring match | Case-insensitive string |

### Comparison Operators

| Operator | ID | Symbol | Description |
|----------|----|--------|-------------|
| Equals | 0 | = | Value must match exactly |
| Greater | 1 | > | Value must be greater than |
| Less | 2 | < | Value must be less than |

Operators are available for all numeric condition types (0-4, 6). Boolean (Is Cursed) and string (Name Contains) conditions ignore the operator.

### Filter Actions

| Action | ID | Description |
|--------|----|-------------|
| Keep | 0 | Whitelist — never filter this item |
| Sell | 1 | Auto-vendor for gold (SellPrice) |
| Disenchant | 2 | Auto-disenchant (requires Enchanting skill, falls back to sell) |
| Delete | 3 | Destroy immediately |

## File Structure

```
mod-loot-filter/
├── conf/
│   ├── conf.sh.dist                  # Build: SQL path registration
│   └── loot_filter.conf.dist        # Server config template
├── data/sql/
│   └── db-characters/
│       └── loot_filter_tables.sql   # character_loot_filter + character_loot_filter_settings tables
├── Loot_Filter_LUA/
│   ├── LootFilter_Client.lua        # AIO client: full filter management UI
│   └── LootFilter_Server.lua        # AIO server: DB operations, handler registration
├── src/
│   ├── mod_loot_filter_loader.cpp   # Module entry point (Addmod_loot_filterScripts)
│   ├── LootFilter.h                 # Header: enums, constants
│   └── LootFilter.cpp               # Core: filter evaluation, sell/DE/delete, hooks
├── include.sh                        # Build integration
├── CLAUDE.md                         # This file
└── README.md
```

## Database Schema

### `character_loot_filter` (characters DB)

Per-character filter rules.

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `characterId` | INT UNSIGNED | — | Character GUID |
| `ruleId` | INT UNSIGNED (PK, AUTO_INCREMENT) | — | Unique rule ID |
| `conditionType` | TINYINT UNSIGNED | 0 | LootFilterCondition enum |
| `conditionOp` | TINYINT UNSIGNED | 0 | LootFilterOp enum (0=equals, 1=greater, 2=less) |
| `conditionValue` | INT UNSIGNED | 0 | Numeric condition value |
| `conditionStr` | VARCHAR(128) | '' | String value (for name contains) |
| `action` | TINYINT UNSIGNED | 1 | LootFilterAction enum |
| `priority` | TINYINT UNSIGNED | 100 | Lower = checked first |
| `enabled` | TINYINT UNSIGNED | 1 | 0=disabled, 1=enabled |

### `character_loot_filter_settings` (characters DB)

Per-character master toggle and statistics.

| Column | Type | Default | Notes |
|--------|------|---------|-------|
| `characterId` | INT UNSIGNED (PK) | — | Character GUID |
| `filterEnabled` | TINYINT UNSIGNED | 1 | Master on/off |
| `totalSold` | INT UNSIGNED | 0 | Copper earned from auto-sell |
| `totalDisenchanted` | INT UNSIGNED | 0 | Items disenchanted count |
| `totalDeleted` | INT UNSIGNED | 0 | Items deleted count |

## Key Functions

### LootFilter.cpp

| Function | Purpose |
|----------|---------|
| `EvaluateFilter(Player*, Item*)` | Evaluates all rules against an item, returns first matching action |
| `MatchesCondition(rule, item, proto)` | Tests a single rule condition against item template |
| `SellItem(Player*, Item*)` | Destroys item, gives SellPrice gold |
| `DisenchantItem(Player*, Item*)` | Generates disenchant loot via LootTemplates_Disenchant, gives materials |
| `DeleteItem(Player*, Item*)` | Destroys item with no return |
| `IsParagonCursedItem(Item*)` | Checks slot 11 for cursed marker (920001) or passive spell (950001-950099) |
| `LoadRulesForPlayer(guid)` | Loads rules from DB into in-memory cache |
| `LoadSettingsForPlayer(guid)` | Loads settings from DB into in-memory cache |

### Hook Points

| Hook | Class | Trigger |
|------|-------|---------|
| `OnPlayerLogin` | PlayerScript | Load rules + settings into cache |
| `OnPlayerLogout` | PlayerScript | Save stats, clear cache |
| `OnPlayerLootItem` | PlayerScript | Evaluate filter on looted item |
| `OnAfterConfigLoad` | WorldScript | Load config values |

### Chat Commands

Registered under `.lootfilter` prefix, all `SEC_PLAYER`:
- `.lootfilter reload` — Reload rules from DB
- `.lootfilter toggle` — Toggle master filter on/off
- `.lootfilter stats` — Show filter statistics

### AIO Handlers (Lua)

| Handler | Direction | Purpose |
|---------|-----------|---------|
| `RequestData` | Client → Server | Request full rule + settings sync |
| `AddRule` | Client → Server | Create new filter rule |
| `DeleteRule` | Client → Server | Delete a rule by ID |
| `ToggleRule` | Client → Server | Toggle rule enabled/disabled |
| `ToggleFilter` | Client → Server | Toggle master filter |
| `UpdatePriority` | Client → Server | Change rule priority |
| `DeleteAllRules` | Client → Server | Delete all rules |
| `ReceiveSettings` | Server → Client | Send settings + stats |
| `ClearRules` | Server → Client | Clear client rule cache |
| `ReceiveRule` | Server → Client | Send a single rule |
| `RefreshUI` | Server → Client | Trigger UI update |

## Configuration

All options read via `sConfigMgr->GetOption<>()` in `OnAfterConfigLoad`:

| Key | Type | Default |
|-----|------|---------|
| `LootFilter.Enable` | bool | true |
| `LootFilter.AllowSell` | bool | true |
| `LootFilter.AllowDisenchant` | bool | true |
| `LootFilter.AllowDelete` | bool | true |
| `LootFilter.LogActions` | bool | true |
| `LootFilter.MaxRulesPerChar` | uint32 | 30 |

## Integration with Other Modules

### mod-auto-loot
mod-auto-loot calls `sScriptMgr->OnPlayerLootItem()` after storing items. mod-loot-filter hooks this same event to intercept and process items. The filter runs after the item is in the player's inventory.

### mod-paragon-itemgen
The "Is Cursed" condition (type 5) checks for paragon enchantment IDs:
- `920001` = "Cursed" marker enchantment (slot 11)
- `950001-950099` = Passive spell enchantments (slot 11, cursed items only)

## AIO Client UI

The client UI (`/lf` or `/lootfilter`) provides:
- **Rule list** with scrollable view, toggle/delete per rule
- **Add Rule form** with condition type dropdown, value input, action dropdown, priority
- **Preset buttons**: Sell Grey, Sell White, DE Green, Del <iLvl50, Keep Cursed
- **Master toggle** button with filter on/off state
- **Statistics** display: gold earned, items disenchanted, items deleted
- **Minimap button** for quick access

## Build & Integration

- Standard AzerothCore module: symlink or clone into `modules/` directory
- No custom `CMakeLists.txt` needed (uses auto-detection)
- Entry point: `Addmod_loot_filterScripts()` in `mod_loot_filter_loader.cpp`
- SQL files auto-discovered via `include.sh` → `conf/conf.sh.dist`
- Lua files: copy `Loot_Filter_LUA/` contents to server's `lua_scripts/` folder (requires AIO)

## Code Style

Follow AzerothCore C++ conventions:
- 4-space indentation, no tabs
- UTF-8 encoding, LF line endings
- `Type const*` (not `const Type*`)
- Use `uint32`, `uint8`, `int32` etc. from `Define.h`
- Backtick table/column names in SQL
