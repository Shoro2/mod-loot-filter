# Change Log — mod-loot-filter

> Minimal commit log. One line per change with a reference to the commit.

## 2026

- 2026-10-09 — T1 on the workbench: build (0 warnings) + boot 19:58 local (the updater re-applied the schema file; "migrated 14 rule(s) of 2 character(s) … (1 switched off for review, 0 dropped)"; errors log unchanged), probe look with CRTEST1 (window via AIO, four views, rules saved end to end), bot scenario `tests/loot_filter.tbs` run 574 PASSED 57/0 (runs 567-573 fixed the scenario: event-only Wild Turkeys, Death Touch refused, auto-loot skips groups, corpses picked, near-teleport timing). Review fixes: sell/disenchant fallback stores again, migration count check, protective '=' rules stay on, editor menus, stuck test/scan. Host: MIG-113 (vault FL/15).
- 2026-10-09 — feat(UI): the window rebuilt (Rules with editor, Test, Log), Lua moved to `lua_scripts/`, the server Lua is an empty stub; offline harness `tests/client_test.lua` (93 checks) — branch `claude/loot-filter-ui-22d6de83`.
- 2026-10-09 — feat(Core): the core owns the rules (cache, only writer, no DB reads on loot), addon messages `LFLT`/`LFLS`, quest items protected, KEEP split from the new TO STORAGE, gold-cap check, statistics per batch, chat modes, startup migration of the old table, character deletion cleanup.
- 2026-10-09 — feat(DB): rule + condition tables, settings gain `chatMode`/`totalStored`, `totalSold` BIGINT; `tests/schema_test.ps1`.
- 2026-10-09 — feat(Core): pure rule model `src/LootFilterRules.h` + `tests/rules_test.cpp` (204 checks, incl. the production host's 19 rules).
- 2026-10-09 — docs: design spec and plan of the rework under `docs/superpowers/` (approved by the operator the same day).
- 2026-06-03 — fix: no auto-storage unless a rule matches ([99ac596](https://github.com/Shoro2/mod-loot-filter/commit/99ac596f7edd2acb93ef5041a5a9ca80705069f5)) — extends the previous fix: with the filter enabled, items that matched no rule (or characters with no rules) fell through to `KEEP` and were still swept into `custom_endless_storage`. All fall-throughs (null template, no rules, no match) now return `FILTER_ACTION_NONE`; storage deposit only happens via an explicit matching Keep rule.
- 2026-06-03 — fix: take no action when the per-character filter is disabled ([7161021](https://github.com/Shoro2/mod-loot-filter/commit/7161021e2203859da5661f5f82a90d309ea68143)) — "Filter: OFF" (`filterEnabled = false`) still routed items through `KEEP`, which auto-deposited storage-eligible mats (Trade Goods/Gems/Recipes/stackable Food, e.g. *Chunk of Boar Meat*) into `custom_endless_storage`. New `FILTER_ACTION_NONE` is returned for the disabled / no-settings case so the module is fully inert when off.
- 2026-05-01 — fix(security): whitelist enum args + MySQL-correct SQL escape ([68af457](https://github.com/Shoro2/mod-loot-filter/commit/68af4576a000054cc132fa4d549b8ffc7c89153f)) — `LootFilter_Server.lua` validates via Dep_Validation: `condType`/`action`/`condOp` as whitelist sets, `ruleId`/`condValue`/`priority`/`ruleGroup` as bounded ints, `condStr` length limit + `Validate.SqlEscape` (`''` instead of `\'` for MySQL NO_BACKSLASH_ESCAPES mode). Resolves M4 from `todo.md`.
- 2026-03-26 — feat: comparison operators (=, >, <) for filter rules ([44322b5](https://github.com/Shoro2/mod-loot-filter/commit/44322b54f788d44459686cbeb05d2cd29d4f10ad)) — new DB column `conditionOp` plus migration for existing rules.
- 2026-03-22 — fix: cursed detection, gold formatting, keep unsellable items ([19a497d](https://github.com/Shoro2/mod-loot-filter/commit/19a497d12ecff2bc9e04b6ab4cf86dae9058f281)) — filter eval deferred to next tick (mod-paragon-itemgen must apply enchants first); money as g/s/c; SellPrice=0 keep; non-disenchantable keep.
- 2026-03-22 — feat: auto-deposit kept items + DE materials into Endless Storage ([a2a1887](https://github.com/Shoro2/mod-loot-filter/commit/a2a1887541df7725241852b60cb9bb7311ac8bb3)) — Trade Goods/Gems/Recipes go directly into `custom_endless_storage` via the Keep action.
- 2026-03-22 — fix: allow disenchant without Enchanting skill ([b24d9d1](https://github.com/Shoro2/mod-loot-filter/commit/b24d9d164c07f57f92602e0f106378ccf4ae1df0)).
- 2026-03-22 — fix: add Keep logging + DE fallback messages ([5807cbe](https://github.com/Shoro2/mod-loot-filter/commit/5807cbe69b704af3e89eb582cf046a2c64654a4b)).
- 2026-03-22 — fix: evaluate all rules by priority, not standalone-first ([8818661](https://github.com/Shoro2/mod-loot-filter/commit/8818661a6150e46be3be3eeb4f5ef937ac6d96d9)) — Sell White (pri 20) previously took precedence over Keep Trade Goods (G3, pri 2).
- 2026-03-22 — fix(Core): format strings + rule cache sync ([Merge #13](https://github.com/Shoro2/mod-loot-filter/commit/662ad967a2831176c56babf8167fd73c4ef1e867)).
- 2026-03-22 — docs: update CLAUDE.md ([Merge #14](https://github.com/Shoro2/mod-loot-filter/commit/0c65d364bebaacc3bde67e2f58e472e5b447bec9)).
- 2026-03-22 — docs: update CLAUDE.md ([Merge #15](https://github.com/Shoro2/mod-loot-filter/commit/002c526115643492a07b3e4793f09fb75f7c2f3b)).

## Convention

Append new entries at the top. Detailed descriptions belong in the commit body or in `share-public/claude_log.md`.
