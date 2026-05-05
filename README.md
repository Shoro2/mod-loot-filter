# mod-loot-filter

Rule-based automatic loot filter for an [AzerothCore](https://www.azerothcore.org/) **WoW 3.3.5a (WotLK)** server.

## What it does

Every time an item lands in a player's inventory, the module evaluates a per-character set of rules and decides — based on quality, item level, vendor price, item class/subclass, item ID, name match, or cursed status — what to do with it: **Keep** (whitelist), **Sell** at the vendor price, **Disenchant** (with automatic fallback to Sell when Enchanting skill is missing), or **Delete**.

Rules are managed in-game through a full WoW UI (no out-of-game tools needed) and stored per character in the database, so every alt has its own filter set.

## Key features

- **8 condition types**: Quality, Item Level, Sell Price, Item Class, Item Subclass, Item ID, Cursed status, Name contains (substring)
- **4 actions**: Keep, Sell, Disenchant, Delete
- **Priority ordering**: rules evaluate in priority order, first match wins
- **Cursed detection** integrated with [mod-paragon-itemgen](https://github.com/Shoro2/mod-paragon-itemgen) (recognizes the slot-11 cursed marker `920001` and the passive-spell enchantment range `950001-950099`)
- Works with both manual looting and AOE loot from [mod-auto-loot](https://github.com/Shoro2/mod-auto-loot)
- Per-character statistics: `totalSold`, `totalDisenchanted`, `totalDeleted`
- Slash commands: `/lf`, `/lootfilter` — opens the filter UI
- GM/player commands: `.lootfilter reload`, `.lootfilter toggle`, `.lootfilter stats`
- Up to 30 rules per character (configurable)

## Installation

1. Place this module inside the AzerothCore `modules/` directory:
   ```bash
   cd azerothcore-wotlk/modules
   git clone https://github.com/Shoro2/mod-loot-filter.git
   ```
2. Re-run CMake and build the server:
   ```bash
   cd ../build
   cmake .. -DCMAKE_INSTALL_PREFIX=$HOME/azeroth-server \
            -DCMAKE_BUILD_TYPE=RelWithDebInfo \
            -DSCRIPTS=static -DMODULES=static
   make -j$(nproc) && make install
   ```
3. Apply the SQL files shipped under `data/sql/db-characters/` (the AzerothCore SQL updater picks them up automatically).
4. Copy the config and adjust if needed:
   ```bash
   cp $HOME/azeroth-server/etc/loot_filter.conf.dist $HOME/azeroth-server/etc/loot_filter.conf
   ```
5. The client side requires the [AIO addon](https://github.com/Rochet2/AIO) installed in `Interface/AddOns/`. The filter UI ships with this module's Lua sources and is delivered to the client by AIO automatically.
6. Restart the world server. In-game, type `/lf` to open the filter UI and create your first rule.

## Configuration (excerpt)

`conf/loot_filter.conf.dist`:

- `LootFilter.Enable` — master toggle
- `LootFilter.AllowSell`, `AllowDisenchant`, `AllowDelete` — disable individual actions globally
- `LootFilter.LogActions` — server log of every applied rule
- `LootFilter.MaxRulesPerChar` (default `30`)

## Limitations

- Acts only on `OnPlayerLootItem` (not on AH purchases, mail, or trade)
- No auto-use (quest items, etc.) and no auto-equip
- No bulk import/export of rule sets — rules are created in-game
- New characters start with no rules

## Requirements

- [AzerothCore](https://github.com/azerothcore/azerothcore-wotlk) (WoW 3.3.5a / WotLK)
- [AIO framework](https://github.com/Rochet2/AIO) — for the in-game UI

## Optional integrations

- [mod-paragon-itemgen](https://github.com/Shoro2/mod-paragon-itemgen) — for cursed-item recognition via the slot-11 enchantment convention
- [mod-auto-loot](https://github.com/Shoro2/mod-auto-loot) — works seamlessly together; auto-looted items pass through the filter

## License

GPL v2 (see `LICENSE`).
