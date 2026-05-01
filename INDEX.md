# INDEX — mod-loot-filter

Einstiegspunkt für KI-Tools. Lies zuerst diese Datei, dann nach Bedarf die unten gelisteten.

## Files in diesem Repo

| Datei | Größe | Zweck |
|-------|------:|-------|
| `INDEX.md` | <1 KB | diese Datei — Navigation |
| `CLAUDE.md` | ~5 KB | **Was** ist dieses Modul, welche Rolle, welche IDs/DB-Tabellen |
| `data_structure.md` | ~4 KB | exakte Folder/File-Auflistung |
| `functions.md` | ~6 KB | **Wie** funktioniert das Modul: Hooks, Mechanik, Konfig, AIO-Handler |
| `log.md` | ~2 KB | minimaler Commit-Log (eine Zeile pro Commit) |
| `todo.md` | ~1 KB | offene Aufgaben mit Priorität |

## Cross-Repo

- Projekt-Übersicht & Konventionen: [`share-public/AI_GUIDE.md`](https://github.com/Shoro2/share-public/blob/main/AI_GUIDE.md)
- Cross-Repo-Historie: [`share-public/claude_log.md`](https://github.com/Shoro2/share-public/blob/main/claude_log.md)
- AzerothCore-Architektur: [`share-public/docs/02-architecture.md`](https://github.com/Shoro2/share-public/blob/main/docs/02-architecture.md)
- AIO-Framework-Patterns: [`share-public/docs/04-aio-framework.md`](https://github.com/Shoro2/share-public/blob/main/docs/04-aio-framework.md)
- KI-Workflow & Doku-Konvention: [`share-public/docs/08-ai-workflow.md`](https://github.com/Shoro2/share-public/blob/main/docs/08-ai-workflow.md)

## Quick Facts

- AzerothCore-Modul für **WoW 3.3.5a**
- Zweck: regelbasiertes Auto-Sell / Disenchant / Delete für gelootete Items
- C++ Hook-Layer + AIO-Lua-UI (`/lf` oder `/lootfilter`)
- DB: 2 Tabellen in `acore_characters` (`character_loot_filter`, `character_loot_filter_settings`)
- Setzt **mod-auto-loot** voraus (oder manuelles Loot — beide feuern `OnPlayerLootItem`)
- Erkennt Cursed Items aus mod-paragon-itemgen via Slot-11-Enchantment-IDs (920001, 950001-950099)
