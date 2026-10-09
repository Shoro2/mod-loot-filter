# mod-loot-filter

> Read [`INDEX.md`](./INDEX.md) first. Mechanics & hooks: [`functions.md`](./functions.md). Folder layout: [`data_structure.md`](./data_structure.md). Open items: [`todo.md`](./todo.md). Commit trail: [`log.md`](./log.md). Design of the 2026-10 rework: [`docs/superpowers/specs/2026-10-09-loot-filter-ui-rework-design.md`](./docs/superpowers/specs/2026-10-09-loot-filter-ui-rework-design.md).

## What is this module?

AzerothCore module for **WoW 3.3.5a**: every looted item is checked against the character's rules and then
kept, stored in the Endless Storage, sold, disenchanted or deleted. A **rule** is one action plus up to
**four AND-ed conditions**; rules are checked **top to bottom** and the **first match decides**. No match →
the item stays in the bags. **Quest items are never touched.**

Per character, managed in game in the window `/lf` (Rules / Test / Log tabs).

## Who owns what

```
client window (lua_scripts/LootFilter_Client.lua, shipped by AIO)
        │  addon message "LFLT\t…" (whisper to self)      ▲ "LFLS\t…"
        ▼                                                  │
src/LootFilter.cpp  — the ONLY writer of the tables; per-character cache; actions; statistics
src/LootFilterRules.h — pure logic: model, matching, codec, ordering, migration (offline-tested)
```

- The core keeps a per-character cache (loaded at login, updated with every write) — **nothing reads the DB
  on loot**. Out-of-band SQL needs `.lootfilter reload`.
- `lua_scripts/LootFilter_Server.lua` is an empty stub on purpose (it overwrites the pre-2026-10 AIO
  handlers on deploy; the host deploy never deletes).
- **Deploy**: the module owns its Lua (`fl_host_sync_policy.json` → `module_owned`); the files go to
  `lua_scripts/LootFilter/` on the workbench and the host. `fl-lua-scripts` no longer tracks `LootFilter/`.

## Custom data

| Type | Entry | Note |
|-----|--------|-----------|
| DB (`acore_characters`) | `character_loot_filter_rule` | ruleId (assigned by the core), characterId, position, action, enabled |
| | `character_loot_filter_condition` | ruleId, slot 0-3, type, op, value, value2, text |
| | `character_loot_filter_settings` | filterEnabled, chatMode, totalSold (BIGINT copper), totalDisenchanted, totalDeleted, totalStored |
| | `character_loot_filter_legacy` | the pre-2026-10 table, renamed after the one-time migration; kept, never read |
| Addon prefixes | `LFLT` (client → core), `LFLS` (core → client) | formats in [`functions.md`](./functions.md#addon-messages) |
| Slash | `/lf`, `/lootfilter` (`reload`, `minimap`) | global `LootFilter_Toggle()` for the command hub |
| Commands | `.lootfilter reload`, `.lootfilter toggle`, `.lootfilter stats`, `.lootfilter request <payload>` | `SEC_PLAYER`; `request` = the window's protocol from chat (bots, debugging) |
| Saved var (client) | `LootFilterUI_Prefs` | minimap angle / hidden, per character (AIO) |
| DBC / spells / items / NPCs | none | |

## Rules (top level)

| Condition (type id) | Operators / value |
|---|---|
| Quality (0) | is / at least / at most · 0-7 |
| Item level (1) | is / at least / at most · 0-65535 |
| Sell price (2) | is / at least / at most · copper |
| Type (3) | is · class + subclass (255 = any) |
| Cursed (5) | is · 1 cursed / 0 not (slot 11 = 920001 or 950001-950099, mod-paragon-itemgen) |
| Item (6) | is · item entry |
| Name contains (7) | text ≤ 40 chars, letters/digits/space/`'-.,`, case-insensitive, `Name1` |

Actions: **0 Keep** (stays, no deposit) · **1 Sell** · **2 Disenchant** (mats to the Endless Storage) ·
**3 Delete** · **4 To storage** (storage-eligible items deposited, others stay). Sell price 0, not
disenchantable, not storable, or the gold cap → the item is kept instead.

## Configuration

`LootFilter.Enable`, `AllowSell`, `AllowDisenchant`, `AllowDelete` (a disallowed action makes its rules
skip), `LogActions` (server-wide chat switch), `MaxRulesPerChar` (default 30, clamped 1-100). The chat
mode per character (every action / one summary per loot = default / none) is set in the Log tab.

## What this module does **not** do

- no AH / mail / trade filtering — only `OnPlayerLootItem`
- no OR inside a rule (use two rules), no rule import/export, no server default rules (see `todo.md`)
- no auto-use, no auto-equip
