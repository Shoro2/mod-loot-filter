# mod-loot-filter

Rule-based automatic loot filter for an [AzerothCore](https://www.azerothcore.org/) **WoW 3.3.5a (WotLK)** server.

## What it does

Every looted item is checked against the character's rules and then **kept**, moved **to the Endless
Storage**, **sold** at the vendor price, **disenchanted**, or **deleted**. A rule is one action plus up to
four conditions that must all match (quality, item level, sell price, type as class and subclass, cursed,
a specific item, part of the name). Rules are checked from the top; the first one that matches decides,
and an item that matches nothing stays in the bags. Quest items are never touched.

Everything is managed in game in one window (`/lf`):

- **Rules** — the rules in order, written as sentences; move, switch off, edit, delete; templates for the
  common cases.
- **Test** — drop an item on the slot (or Shift-click it) to see which rule would act, or check the whole
  bags at once. Nothing is changed.
- **Log** — this session's actions with item links, lifetime totals, and how much the filter writes to chat
  (every action, one summary per loot, or nothing).

## Installation

1. Clone into the AzerothCore `modules/` directory and rebuild the server
   (`-DSCRIPTS=static -DMODULES=static`).
2. The SQL under `data/sql/db-characters/` is applied by the AzerothCore updater. A database with the
   first version's table is migrated once at worldserver start; the old table is kept as
   `character_loot_filter_legacy`.
3. Copy `conf/loot_filter.conf.dist` to `loot_filter.conf` next to the other module configs.
4. Copy `lua_scripts/LootFilter_Client.lua` and `lua_scripts/LootFilter_Server.lua` into the server's
   `lua_scripts/LootFilter/` (needs [mod-ale](https://github.com/azerothcore/mod-ale) and
   [AIO](https://github.com/Rochet2/AIO); AIO delivers the window to the client).
5. Restart the worldserver and type `/lf` in game.

## Configuration

- `LootFilter.Enable` — master switch
- `LootFilter.AllowSell`, `AllowDisenchant`, `AllowDelete` — switch actions off server-wide
- `LootFilter.LogActions` — `0` silences all chat output of the filter
- `LootFilter.MaxRulesPerChar` — default `30`

## Optional integrations

- [mod-paragon-itemgen](https://github.com/Shoro2/mod-paragon-itemgen) — the "cursed" condition
- [mod-endless-storage](https://github.com/Shoro2/mod-endless-storage) — the "To storage" action and
  disenchanting materials
- [mod-auto-loot](https://github.com/Shoro2/mod-auto-loot) — auto-looted items pass through the filter

## License

GPL v2.
