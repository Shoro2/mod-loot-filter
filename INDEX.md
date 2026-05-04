# INDEX — mod-loot-filter

Entry point for AI tools. Read this file first, then the ones listed below as needed.

## Files in this repo

| File | Size | Purpose |
|-------|------:|-------|
| `INDEX.md` | <1 KB | this file — navigation |
| `CLAUDE.md` | ~5 KB | **What** this module is, what role, which IDs/DB tables |
| `data_structure.md` | ~4 KB | exact folder/file listing |
| `functions.md` | ~6 KB | **How** the module works: hooks, mechanics, config, AIO handlers |
| `log.md` | ~2 KB | minimal commit log (one line per commit) |
| `todo.md` | ~1 KB | open tasks with priority |

## Cross-Repo

- Project overview & conventions: [`share-public/AI_GUIDE.md`](https://github.com/Shoro2/share-public/blob/main/AI_GUIDE.md)
- Cross-repo history: [`share-public/claude_log.md`](https://github.com/Shoro2/share-public/blob/main/claude_log.md)
- AzerothCore architecture: [`share-public/docs/02-architecture.md`](https://github.com/Shoro2/share-public/blob/main/docs/02-architecture.md)
- AIO framework patterns: [`share-public/docs/04-aio-framework.md`](https://github.com/Shoro2/share-public/blob/main/docs/04-aio-framework.md)
- AI workflow & doc convention: [`share-public/docs/08-ai-workflow.md`](https://github.com/Shoro2/share-public/blob/main/docs/08-ai-workflow.md)

## Quick Facts

- AzerothCore module for **WoW 3.3.5a**
- Purpose: rule-based auto-sell / disenchant / delete for looted items
- C++ hook layer + AIO Lua UI (`/lf` or `/lootfilter`)
- DB: 2 tables in `acore_characters` (`character_loot_filter`, `character_loot_filter_settings`)
- Requires **mod-auto-loot** (or manual loot — both fire `OnPlayerLootItem`)
- Detects cursed items from mod-paragon-itemgen via slot 11 enchantment IDs (920001, 950001-950099)
