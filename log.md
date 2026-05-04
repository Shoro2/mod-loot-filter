# Change Log — mod-loot-filter

> Minimal commit log. One line per change with a reference to the commit.

## 2026

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
