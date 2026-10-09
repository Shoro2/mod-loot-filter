# INDEX — mod-loot-filter

Entry point for AI tools. Read this file first, then the ones listed below as needed.

## Files in this repo

| File | Purpose |
|-------|-------|
| `INDEX.md` | this file — navigation |
| `CLAUDE.md` | **What** this module is, who owns what, ids, tables, config |
| `data_structure.md` | folder/file listing and DB tables |
| `functions.md` | **How** it works: hooks, evaluation, actions, addon messages, migration, tests |
| `log.md` | minimal commit log (newest first) |
| `todo.md` | open tasks with priority |
| `docs/superpowers/specs/2026-10-09-loot-filter-ui-rework-design.md` | the approved design of the 2026-10 rework |
| `docs/superpowers/plans/2026-10-09-loot-filter-ui-rework.md` | its implementation plan |

## Cross-Repo

- Project overview & conventions: [`share-public/AI_GUIDE.md`](https://github.com/Shoro2/share-public/blob/main/AI_GUIDE.md)
- Cross-repo history: [`share-public/claude_log.md`](https://github.com/Shoro2/share-public/blob/main/claude_log.md)
- Modules overview: `share-public/docs/World of Warcraft/05-modules.md`; DB tables: `09-db-tables.md`
- Host deploys: `share-public/docs/World of Warcraft/forgotten-land/15-host-migration-log.md`

## Quick Facts

- AzerothCore module for **WoW 3.3.5a**; window `/lf` (Rules / Test / Log), AIO-shipped Lua
- A rule = one action + up to 4 AND-ed conditions; first match from the top decides; quest items never touched
- The core owns the rules (cache, only writer); the window talks to it with addon messages `LFLT` / `LFLS`
- DB: `character_loot_filter_rule`, `_condition`, `_settings` in `acore_characters` (+ `_legacy` after the migration)
- Offline tests: `tests\build_offline.cmd` (C++ rule logic + Lua window), `tests\schema_test.ps1` (SQL)
