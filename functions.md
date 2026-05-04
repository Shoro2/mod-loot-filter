# Functions & mechanics — mod-loot-filter

> Detailed function and mechanics reference. For content/purpose docs see `CLAUDE.md`.

## Module loader

### `Addmod_loot_filterScripts()`
- **File**: `src/mod_loot_filter_loader.cpp`
- **Effect**: registers the `LootFilter` class (`PlayerScript` + `WorldScript` + `CommandScript`).

## Enums (`src/LootFilter.h`)

```cpp
enum LootFilterCondition {
    QUALITY = 0, ITEM_LEVEL = 1, SELL_PRICE = 2, ITEM_CLASS = 3,
    ITEM_SUBCLASS = 4, IS_CURSED = 5, ITEM_ID = 6, NAME_CONTAINS = 7
};

enum LootFilterOp {  // only for numeric conditions
    OP_EQUALS = 0, OP_GREATER = 1, OP_LESS = 2
};

enum LootFilterAction {
    KEEP = 0, SELL = 1, DISENCHANT = 2, DELETE = 3
};
```

## Hook points (PlayerScript)

| Hook | Behavior |
|------|-----------|
| `OnPlayerLogin` | `LoadRulesForPlayer(guid)` + `LoadSettingsForPlayer(guid)` → into in-memory cache |
| `OnPlayerLootItem` | **Deferred** to the next server tick (see note below), then `EvaluateFilter(player, item)` |
| `OnPlayerLogout` | Persist stats, invalidate cache |

`WorldScript`:
| Hook | Behavior |
|------|-----------|
| `OnAfterConfigLoad` | read all 6 config keys via `sConfigMgr->GetOption<>()` |

> **Important — deferred eval**: The filter evaluation does **not** happen synchronously in `OnPlayerLootItem`. The hook only inserts the item into a pending queue; the actual evaluation runs on the next server tick. Reason: mod-paragon-itemgen also modifies slot 11 in the `OnPlayerLootItem` hook — if the filter checked immediately, the `IsParagonCursedItem` detection would be racy.

## Core functions (`src/LootFilter.cpp`)

| Function | Purpose |
|----------|-------|
| `EvaluateFilter(Player*, Item*)` | iterates rules in priority order, returns the **first** matching action |
| `MatchesCondition(rule, item, proto)` | eval of a single rule: switches on `conditionType` to the matching field, compares via `conditionOp` |
| `ApplyAction(player, item, action, rule)` | dispatches to `SellItem` / `DisenchantItem` / `DeleteItem` / Keep+storage deposit |
| `SellItem(Player*, Item*)` | increments `totalSold` by `SellPrice * count`, item destroy, money formatted (`Xg Ys Zc`) |
| `DisenchantItem(Player*, Item*)` | rolls `LootTemplates_Disenchant` (no skill check), materials in inventory or (if eligible) Endless Storage; fallback for non-disenchantable: keep |
| `DeleteItem(Player*, Item*)` | hard destroy without reward |
| `IsParagonCursedItem(Item*)` | checks slot 11 for enchant ID `920001` or range `950001`-`950099` |
| `LoadRulesForPlayer(guid)` | prepared SELECT on `character_loot_filter` ORDER BY priority |
| `LoadSettingsForPlayer(guid)` | prepared SELECT on `character_loot_filter_settings` |
| `IsStorageEligible(item)` | true if class 7 (TradeGoods stackable) or class 3 (gem stackable) or class 9 (recipe) |

### Action special cases

- **`SellPrice == 0`** → action is converted to Keep (items cannot be sold for 0 copper).
- **Item not disenchantable** → Disenchant action falls back to Keep (previously: to Sell — corrected on 2026-03-22).
- **Keep + item is storage-eligible** → deposited into `custom_endless_storage` instead of held in the inventory. Log entry "Stored [item] x N in Storage".

## Priority eval

```
all rules (standalone + group) sorted together in priority ASC
  └─ per rule: MatchesCondition?
     └─ yes → return action  (first match wins)
```

Behavior since 2026-03-22 (commit `8818661`): previously standalone rules always took precedence over group rules, which undermined the priority.

## Money format

```
Input: 12345 copper
Output: "1g 23s 45c"
```

Implemented in a small helper function (see `LootFilter.cpp`). Zero parts are dropped ("1g" instead of "1g 0s 0c").

## Chat commands (CommandScript)

```
.lootfilter reload    → reload rules + settings from DB (in-memory cache)
.lootfilter toggle    → flip filterEnabled bit, persist
.lootfilter stats     → output totalSold (g/s/c), totalDisenchanted, totalDeleted
```

All `SEC_PLAYER`. No cooldown.

## AIO handlers (Lua)

Server side (client → server, in `LootFilter_Server.lua`):

| Handler | Args | Effect |
|---------|------|---------|
| `RequestData` | — | sends rules + settings to client |
| `AddRule` | conditionType, conditionOp, conditionValue, conditionStr, action, priority | INSERT `character_loot_filter`, in-memory cache update |
| `DeleteRule` | ruleId | DELETE + cache update |
| `ToggleRule` | ruleId | UPDATE enabled |
| `ToggleFilter` | — | UPDATE settings.filterEnabled |
| `UpdatePriority` | ruleId, newPriority | UPDATE + re-sort |
| `DeleteAllRules` | — | DELETE WHERE characterId = ? |

Client side (server → client, in `LootFilter_Client.lua`):

| Handler | Args | Effect |
|---------|------|---------|
| `ReceiveSettings` | filterEnabled, totalSold, totalDisenchanted, totalDeleted | UI update |
| `ClearRules` | — | clear client-side rule cache |
| `ReceiveRule` | ruleId, conditionType, op, value, str, action, priority, enabled | single rule to client |
| `RefreshUI` | — | trigger UI redraw |

## Configuration options

| Key | Default | Effect |
|-----------|---------|---------|
| `LootFilter.Enable` | `true` | master toggle |
| `LootFilter.AllowSell` | `true` | allow Sell action |
| `LootFilter.AllowDisenchant` | `true` | allow DE action |
| `LootFilter.AllowDelete` | `true` | allow Delete action |
| `LootFilter.LogActions` | `true` | sysmessage per filter action |
| `LootFilter.MaxRulesPerChar` | `30` | limit for `AddRule` |

If an `Allow*` option is set to `false`, the corresponding action falls back to Keep (with log).

## Known limitations

- **Eluna Lua DB calls** use string concatenation (no PreparedStatement equivalent in Eluna).
- **Cursed detection** only works if mod-paragon-itemgen has already set the slot 11 entry — hence the deferred eval.
- **`LootTemplates_Disenchant`** is global — no server config per item quality possible, everything is vanilla DE loot.
