# Loot Filter UI Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
> Executed inline by the author session (Opus), task by task, each task ending green and committed.

**Goal:** Replace the loot filter window and its data model as specified in
`docs/superpowers/specs/2026-10-09-loot-filter-ui-rework-design.md` (approved 2026-10-09).

**Architecture:** C++ is the only owner of the rules: a pure, core-free header (`LootFilterRules.h`)
holds the model, matching, evaluation, validation, message codec, ordering and the legacy migration; the
core glue (`LootFilter.cpp`) holds the cache, DB writes, hooks, actions and the addon-message transport.
The client window is AIO-shipped Lua that talks to the core with addon messages (`LFLT` up, `LFLS` down).

**Tech Stack:** AzerothCore 3.3.5a module (C++17, MSVC), MySQL 8.4, WoW 3.3.5a FrameXML Lua shipped by AIO
(mod-ale), Lua 5.2 for the offline client harness.

## Global Constraints

- Branch `claude/loot-filter-ui-22d6de83` in every repo touched; worktrees
  `C:\wowstuff\core-worktrees\lfui\mod-loot-filter` and `C:\wowstuff\vault-worktrees\lfui`.
- No build in `dcore_bin`, no install into `dcore`, no restart, no Lua deploy, and no change to
  `modules\mod-loot-filter` until the coordinator passes the end of the CoA round-4 window.
- English in code, docs and commits; Conventional Commits; commit trailer
  `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.
- Limits: 4 conditions per rule, 40 text characters (letters, digits, space, `'-.,`), messages ≤ 250
  bytes, rules per character = `LootFilter.MaxRulesPerChar` (default 30).
- Ids: actions 0 keep, 1 sell, 2 disenchant, 3 delete, 4 store; condition types 0 quality, 1 item level,
  2 sell price, 3 item type, 5 cursed, 6 item, 7 name; operators 0 is, 1 at least, 2 at most; results
  0–4 action, 5 no rule, 6 protected; chat modes 0 every, 1 summary (default), 2 none.
- Evidence tiers: T0 code, T1 offline/workbench verified, T2 operator in game. Claim only what ran.

---

### Task 1: Pure rule logic with an offline test

**Files:**
- Create: `src/LootFilterRules.h` (header-only; includes only `Define.h` and the standard library)
- Create: `tests/rules_test.cpp`, `tests/build_offline.cmd`

**Interfaces (produced, used by Tasks 3 and 4):**
- `namespace LootFilterRules`: enums `Action`, `Result`, `CondType`, `Op`, `ChatMode`; structs
  `Condition{type,op,value,value2,text}`, `Rule{id,position,action,enabled,conditions}`,
  `ItemFacts{entry,quality,itemLevel,sellPrice,itemClass,subClass,cursed,questItem,name}`,
  `Verdict{result,position}`, `LegacyRow{characterId,ruleId,ruleGroup,type,op,value,text,action,priority,enabled}`,
  `MigrationResult{rules,disabled,dropped}`.
- Functions: `AllowedMask(bool,bool,bool)`, `Matches`, `Evaluate(rules,item,mask)`, `ValidCondition`,
  `ValidRule`, `ParseUInt(s,max,out)`, `Split(s,sep)`, `EncodeConditions`, `DecodeConditions`,
  `EncodeRule`, `DecodeRule(fields,at,rule)`, `Insert(rules,rule,pos)`, `Move(rules,id,pos)`,
  `Remove(rules,id)`, `Renumber(rules)`, `ClientToServer(cbag,cslot,bag,slot)`,
  `ServerToClient(bag,slot,cbag,cslot)`, `MigrateCharacter(rows)`.

- [ ] Write `tests/rules_test.cpp` covering: every condition type matching and not matching; operators
  at the boundaries; first-match order; disabled rules skipped; action masked by config skipped;
  quest item → protected; no match → no rule; codec round trip incl. empty text and 4 conditions;
  decode rejects (bad type, op on item type, text with `|:;`, 41 chars, 5 conditions, non-digits,
  overflow); move/insert/remove renumbering; bag mapping both ways and out-of-range; migration of the
  host's 19 rules (anonymised) to the exact expected rules, plus edge cases (`< 0`, `> 4` conditions,
  class + subclass merge, lone subclass, op on class, long name, KEEP → STORE, all rows disabled).
- [ ] Run `tests\build_offline.cmd` → fails to compile (header missing).
- [ ] Write `src/LootFilterRules.h`.
- [ ] Run `tests\build_offline.cmd` → `rules_test: all N checks passed`.
- [ ] Commit `feat(Core): Add the pure loot filter rule model`.

### Task 2: Schema SQL

**Files:**
- Modify (rewrite): `data/sql/db-characters/loot_filter_tables.sql`
- Create: `tests/schema_test.ps1` (applies the file twice to a scratch schema `lf_schema_test` on
  MySQL84 and checks columns; drops the scratch schema afterwards)

- [ ] Write the file: `CREATE TABLE IF NOT EXISTS` for `character_loot_filter_rule`,
  `character_loot_filter_condition`, `character_loot_filter_settings` (new shape); a procedure that adds
  `chatMode` and `totalStored` and widens `totalSold` only when needed; no reference to
  `character_loot_filter` any more.
- [ ] Run the schema test: two applications, no error, final columns as specified, also on a schema
  that starts from the old shape (old settings table + old rule table present).
- [ ] Commit `feat(DB): Add the rule and condition tables`.

### Task 3: Core glue

**Files:**
- Modify (rewrite): `src/LootFilter.cpp`, `src/LootFilter.h`

Responsibilities: per-character state (settings, totals, rules, rate limiter, batch summary) behind one
mutex; load at login, erase at logout; startup migration (legacy table → `MigrateCharacter` per
character → one transaction → rename to `character_loot_filter_legacy`) and rule-id counter; addon
message intake in `OnPlayerBeforeSendChatMessage` (prefix `LFLT\t`), replies with prefix `LFLS`;
handlers G, R, D, M, E, F, C, X, T, S; every rule mutation rewrites the character's rule set in one
transaction; loot path builds `ItemFacts`, defers one tick, evaluates with the cached rules, acts (KEEP,
STORE, SELL with money cap, DISENCHANT, DELETE), writes statistics through, sends an `L` log message,
prints chat per mode (every action with item link, or one summary per batch, or none) unless
`LootFilter.LogActions = 0`; commands `.lootfilter reload|toggle|stats` (toggle also sends `F`).

- [ ] Write the glue against the Task 1 interfaces.
- [ ] Compile check happens in Task 7 (the core cannot be compiled outside `dcore_bin`).
- [ ] Commit `feat(Core): Rework the loot filter around a cached rule model`.

### Task 4: Client window

**Files:**
- Create: `lua_scripts/LootFilter_Client.lua`, `lua_scripts/LootFilter_Server.lua` (stub)
- Delete: `Loot_Filter_LUA/`
- Create: `tests/client_test.lua` (mocked FrameXML API)

Window per the mockup: title bar (Filter on box, close), tabs Rules / Test / Log, rule list with
sentences, badges, on/off, ↑ ↓ edit delete, templates menu, clear all; editor with up to four condition
rows (type/operator/value widgets per type, nested Class › Subclass menu, g/s/c price boxes, item box
filled by Shift-click or drop, 40-char name box), action radios greyed per server flags, position
dropdown; Test tab item slot (drop or Shift-click) and "Check my bags"; Log tab (100 entries, totals,
chat mode radios); draggable minimap button with saved angle; `AIO.SavePosition`; `/lf`, `/lootfilter`,
`LootFilter_Toggle()`; transport `SendAddonMessage("LFLT", …, "WHISPER", UnitName("player"))` and
`CHAT_MSG_ADDON` prefix `LFLS`.

- [ ] Write `tests/client_test.lua` (sentence builder, condition codec, editor validation, message
  handling for I/R/N/T/S/Z/L/F/!, rule list rendering, test slot flow).
- [ ] Run it with the harness Lua → fails.
- [ ] Write the client and the stub; delete `Loot_Filter_LUA/`.
- [ ] Run → passes; run `luac -p`-equivalent syntax check on both files.
- [ ] Commit `feat(UI): Rebuild the loot filter window`.

### Task 5: Module docs and config

**Files:** `CLAUDE.md`, `INDEX.md`, `README.md`, `data_structure.md`, `functions.md`, `log.md`,
`todo.md`, `conf/loot_filter.conf.dist`

- [ ] Rewrite the docs for the new model, protocol, files and deploy ownership; `log.md` newest first;
  remove finished `todo.md` items; config descriptions (`LogActions` = server-wide chat switch).
- [ ] Commit `docs: Document the reworked loot filter`.

### Task 6: Deploy ownership

**Files:** `share-public/python_scripts/fl_host_sync_policy.json` (vault worktree),
`fl-lua-scripts/.gitignore` + untrack `LootFilter/` (in the deploy checkout, only those paths staged).

- [ ] Add `"LootFilter": "mod-loot-filter"` to `lua.module_owned`, update the note.
- [ ] fl-lua-scripts: ignore `LootFilter/`, `git rm --cached` its two files, README table row moved to
  the "not here" list. Commit and push only these paths (the checkout holds other sessions' WIP).

### Task 7: Workbench T1 (after the coordinator's end line)

- [ ] `modules\mod-loot-filter`: fetch, check out the branch tip (detached), build `dcore_bin`
  (`--parallel 4`, fallback `--parallel 2 -- -p:CL_MPCount=8`), keep
  `worldserver.exe.pre_lootfilterui_20261009`, install.
- [ ] Deploy `lua_scripts/*.lua` into `dcore\lua_scripts\LootFilter\`.
- [ ] Restart via `scripts\worldserver_restart.ps1` (holds `tools\shared.lock`, re-checks online players).
- [ ] Boot: migration log line, errors log = the 74 CoA lines only, updater applied the schema file.
- [ ] Bots: `tests/loot_filter.tbs` (rules via the protocol path where possible, loot, assert money,
  storage rows, bag contents, statistics, summary line).
- [ ] Probe client (CRTEST1): open `/lf`, exercise each tab, screenshot each, quit the probe.

### Task 8: Merge, push, vault, host ledger

- [ ] Merge the branch into `main` (`--no-ff`), push; `modules\mod-loot-filter` back on `main`.
- [ ] Vault (worktree): `claude_log.md` (append at END), `12-server-todo.md` (mass-pull row: F1 + F11
  loot-filter half done; new T2 item), `15-host-migration-log.md` MIG entry (next free id after
  checking the ledger end), `05-modules.md`, `09-db-tables.md`; merge to vault `main`, push.
- [ ] Local memory: loot filter rework facts.
