# mod-loot-filter

> Read [`INDEX.md`](./INDEX.md) first. Mechanics & hooks: [`functions.md`](./functions.md). Folder layout: [`data_structure.md`](./data_structure.md). Open items: [`todo.md`](./todo.md). Commit trail: [`log.md`](./log.md).

## What is this module?

AzerothCore module for **WoW 3.3.5a (WotLK)**. Provides a rule-based **automatic item filtering system** for looted items: the player creates their own filter rules via the AIO UI, and matching items are automatically sold (vendor), disenchanted, or deleted afterwards. A whitelist action ("Keep") allows protecting valuable items from broader rules.

Per-character — every character has its own rules, stored in `acore_characters`.

## Role in the overall project

```
Loot source (manual, mod-auto-loot)
        │
        ▼ sScriptMgr->OnPlayerLootItem()
        │
   ┌────┴────────────────────────────────────────┐
   ▼                                              ▼
mod-paragon-itemgen  (apply bonus stats)      mod-loot-filter  (filter: Keep / Sell / DE / Delete)
```

The module hangs on the shared `OnPlayerLootItem` hook. It works both with mod-auto-loot (AOE loot in radius) and with manual looting. It expects **no** special hook pattern — rule evaluation runs per item that ends up in the inventory.

## Custom data

| Type | Entry | Note |
|-----|--------|-----------|
| **DB tables (acore_characters)** | `character_loot_filter` | Per-character rules (condition, operator, value, action, priority, enabled) |
| | `character_loot_filter_settings` | Master toggle + statistics (totalSold, totalDisenchanted, totalDeleted) |
| **DBC patches** | none | |
| **Custom spells** | none | |
| **Custom items/NPCs** | none | |
| **AIO handler names** | `LF` (server) / `LF_Client` (client) | Details: [`functions.md`](./functions.md#aio-handler) |
| **Slash commands** | `/lf`, `/lootfilter` | opens the filter UI |
| **GM commands** | `.lootfilter reload`, `.lootfilter toggle`, `.lootfilter stats` | all `SEC_PLAYER` |

## Filter mechanics (top level)

| Condition type | Operators |
|---------------|------------|
| Quality, Item Level, Sell Price, Item Class, Item Subclass, Item ID | `=`, `>`, `<` |
| Cursed status | bool |
| Name contains | substring |

Actions: **Keep** (whitelist) / **Sell** (vendor) / **Disenchant** (with skill fallback to Sell) / **Delete**. Rules run in priority order — lowest value first, **first match wins**.

Cursed detection: the module reads slot 11 enchantment on every item. Values `920001` ("Cursed" marker) and the range `950001-950099` (passive spells) are treated as "cursed". → dependency on mod-paragon-itemgen for the slot 11 convention.

## Configuration (top level)

`conf/loot_filter.conf.dist`:

- `LootFilter.Enable` (master toggle)
- `LootFilter.AllowSell`, `AllowDisenchant`, `AllowDelete`
- `LootFilter.LogActions`
- `LootFilter.MaxRulesPerChar = 30`

Details and defaults: [`functions.md`](./functions.md#configuration).

## What this module does **not** do

- **no** AH/mail filter — only acts on `OnPlayerLootItem` events
- **no** auto-use (e.g. quest items opened automatically)
- **no** equipment auto-equip
- **no** bulk import / export of rule sets — rules must be created via the UI (see [`todo.md`](./todo.md))
- **no** server defaults — new characters start without rules (see [`todo.md`](./todo.md))

## License

GPL v2.
