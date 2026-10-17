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

## Requirements

- AzerothCore WotLK (3.3.5a). The module uses only standard core hooks and no fork-only API; it was developed
  on the [Shoro2/azerothcore-wotlk](https://github.com/Shoro2/azerothcore-wotlk) fork and has not been built
  against vanilla upstream.
- [mod-ale](https://github.com/azerothcore/mod-ale) (Lua engine) and [AIO](https://github.com/Rochet2/AIO):
  AIO delivers the `/lf` window to the client. No client patch is needed.
- The other modules under "Optional integrations" are not required.

## Installation

1. Clone into the AzerothCore `modules/` directory and rebuild the server
   (`-DSCRIPTS=static -DMODULES=static`).
2. The SQL under `data/sql/db-characters/` is applied by the AzerothCore updater. A database with the
   first version's table is migrated once at worldserver start; the old table is kept as
   `character_loot_filter_legacy`.
3. Copy `conf/loot_filter.conf.dist` to your `configs/modules/` folder as `loot_filter.conf`.
4. Copy `lua_scripts/LootFilter_Client.lua` and `lua_scripts/LootFilter_Server.lua` into the server's
   `lua_scripts/LootFilter/` (needs [mod-ale](https://github.com/azerothcore/mod-ale) and
   [AIO](https://github.com/Rochet2/AIO); AIO delivers the window to the client).
5. Restart the worldserver and type `/lf` in game.

## Configuration

- `LootFilter.Enable` — master switch
- `LootFilter.AllowSell`, `AllowDisenchant`, `AllowDelete` — switch actions off server-wide
- `LootFilter.LogActions` — `0` silences all chat output of the filter
- `LootFilter.MaxRulesPerChar` — default `30`

## Commands and slash commands

In game `/lf` (or `/lootfilter`) opens the window; `/lf reload` refreshes its data from the server and `/lf minimap` shows or hides the minimap button.
Chat commands (any player): `.lootfilter reload` (reload your rules from the database after manual SQL),
`.lootfilter toggle` (filter on/off), `.lootfilter stats` (lifetime totals).

## Optional integrations

- [mod-paragon-itemgen](https://github.com/Shoro2/mod-paragon-itemgen) — the "cursed" condition
- [mod-endless-storage](https://github.com/Shoro2/mod-endless-storage) — the "To storage" action and
  disenchanting materials
- [mod-auto-loot](https://github.com/Shoro2/mod-auto-loot) — auto-looted items pass through the filter
