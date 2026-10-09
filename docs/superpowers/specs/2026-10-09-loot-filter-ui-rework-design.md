# Loot filter UI rework — design

Date: 2026-10-09 · Module: `mod-loot-filter` · Branch: `claude/loot-filter-ui-22d6de83`
Mockup: https://claude.ai/artifact/EYrD4p3h6ypSBtVdNqYwwh (four new screens + today's window)
Status: **APPROVED** by the operator on 2026-10-09 16:20 UTC ("ja" to the proposal as drawn, without
the optional extras: buyback for sold items, "unusable by my class", "binding").

## 1. Why

Survey on 2026-10-09 (workbench checkout fast-forwarded `2677d02` → `a4da1a2`, the June fixes):

| # | Finding | Evidence |
|---|---|---|
| 1 | Host and workbench run the Lua of 2026-03-22. It has no operator field, so "Item Level below" / "Sell Price below" rules are stored with `conditionOp = 0` and the core evaluates them as **equals**. | `C:\wowstuff\dcore\lua_scripts\LootFilter\*.lua` equals the host backup of 2026-10-09 (CR-normalised); both differ from `Loot_Filter_LUA/`; host dump: 1 of 19 rules is `(type 1, op 0, Delete)` |
| 2 | Two sources of truth for the Lua: the module's `Loot_Filter_LUA/` (newer, never deployed) and `fl-lua-scripts/LootFilter/` (deployed). The host sync tool treats `LootFilter/` as workbench-owned. | `share-public/python_scripts/fl_host_sync_policy.json`, `lua.module_owned` lists only Dungeon_Challenge and Storage |
| 3 | AND groups are numbered by hand; every condition row carries its own action and priority, but only the lowest-priority row's action counts. The list is sorted by group, the core by priority, so the shown order is not the evaluation order. | `LootFilter.cpp` `EvaluateFilter` (`groupRules.front()`); client `RefreshUI` sort |
| 4 | Conditions cannot be edited (only action / priority / group). | client `OpenEditPopup` |
| 5 | "Item Subclass" ignores the class: subclass 1 is Cloth, Two-Handed Axe, … | `MatchesCondition`, `FILTER_COND_ITEM_SUBCLASS` |
| 6 | Statistics are lost: every loot reloads the settings row, which is only written at logout, so only the last loot batch of a session is counted. | `OnPlayerLootItem` → `LoadSettingsForPlayer`; `SaveStats` only in `OnPlayerLogout` |
| 7 | Rendering a subclass rule raises a Lua error (`WEAPON_SUBCLASS` is a local declared after `UpdateRuleList`). | client lines 518 vs 720 |
| 8 | Quest items are not protected: an item-level or price based Delete rule destroys quest drops. | no class 12 / quest-bond check |
| 9 | "Keep" silently moves storage-eligible items into the Endless Storage (the Ranger key-craft hazard in FL/15). | `KeepItem` → `IsStorageEligible` |
| 10 | Every filtered item prints one chat line. | `conf_LogActions` per action; mass-pull plan F11 |
| 11 | Two synchronous character-DB reads per looted item. | mass-pull plan F1 (`10-mass-pull-performance-plan.md`) |
| 12 | Minimap button fixed at TOPLEFT 6,-6, on top of the Forgotten Talents button. | command-hub thread |

## 2. Goals and non-goals

Goals: the window of the mockup (Rules, editor, Test, Log); a data model where a rule is one action plus
up to four AND-ed conditions at an explicit position; one source of truth for the Lua; fixes for
findings 1–12. Non-goals: OR inside a rule, rule import/export, server default rules, AH/mail
filtering, localisation (the client and every FL window are enUS), the three optional extras.

## 3. What the player sees

- **Rules tab**: numbered list in evaluation order. Each rule is a sentence ("Quality is Uncommon and
  Item level at most 150") with an action badge (KEEP, TO STORAGE, SELL, DISENCHANT, DELETE), an on/off
  box, ↑, ↓, edit, delete. Hint above: "Checked from top to bottom. The first rule that matches
  decides. Quest items are never touched." Line below the last rule: "No rule matches: the item stays
  in your bags." Footer: New rule, Templates ▾, Clear all (confirm), the session line (sold + gold,
  disenchanted, stored, deleted), `n / max rules`.
- **Editor** (replaces the list): up to four condition rows `[type ▾] [operator ▾] [value]` with a
  remove button, "Add condition", the action as a radio list with one-line explanations (actions
  disabled by the server config are greyed out), position dropdown, Cancel / Save rule. Values:
  quality dropdown (quality colours), number box (item level), g/s/c boxes (sell price), nested
  Class › Subclass dropdown with "any" (item type), Cursed / Not cursed, an item box filled by
  Shift-click or by dropping an item (item), a text box of at most 40 characters (name contains).
- **Test tab**: an item slot (drop an item or Shift-click it in the bags); the server answers with the
  rule that matches and its action, "protected (quest item)" or "no rule". "Check my bags" evaluates
  every bag item without acting and shows counts per result plus the list (item, result, rule).
- **Log tab**: the last 100 actions of the session, newest first (time, action, item link × count,
  money or materials, rule number), lifetime totals, and the chat mode: every action / one summary per
  loot (default) / none, with an example line.
- **Templates** (open the editor pre-filled): Sell grey items, Sell white armor, Sell white weapons,
  Disenchant green items, Keep cursed items, Keep rare and better, Store trade goods.
- Title bar: "Filter on" box and close. Minimap button draggable around the rim, position stored per
  character; window position stored (`AIO.SavePosition`). Unchanged entry points for the command hub:
  `/lf`, `/lootfilter`, `SlashCmdList.LOOTFILTER`, `.lootfilter toggle|stats|reload`; new global
  `LootFilter_Toggle()`. An open window follows `.lootfilter toggle`.

## 4. Behaviour

- Quest items (class 12, `Bonding` 4 or 5, or `StartQuest` > 0) are never touched; the Test tab shows
  them as protected.
- Rules are checked in position order; disabled rules are skipped; the first rule whose conditions all
  match decides. A rule whose action is switched off by `LootFilter.Allow*` is skipped, as today. No
  match → the item stays.
- Actions: KEEP = stays in the bags (no deposit any more); TO STORAGE = deposited into
  `custom_endless_storage` when storage-eligible (unchanged predicate), otherwise stays; SELL,
  DISENCHANT, DELETE unchanged, including today's fallbacks (sell price 0 → kept, not disenchantable →
  kept).
- Operators: is (=), at least (≥), at most (≤) for quality, item level and sell price; "is" for item
  type, cursed and item; "contains" (case-insensitive, `Name1`) for name.
- Chat output per character: 0 = every action (with item links), 1 = one summary per loot batch
  (default), 2 = none. `LootFilter.LogActions = 0` keeps silencing all chat output server-wide. The Log
  tab receives every action regardless of the mode.
- Statistics are written through when an action happens (`totalSold` widened to BIGINT, new
  `totalStored`).

## 5. Data model (`acore_characters`)

```
character_loot_filter_rule      ruleId INT UNSIGNED PK AUTO_INCREMENT, characterId INT UNSIGNED,
                                position TINYINT UNSIGNED (1-based), action TINYINT UNSIGNED,
                                enabled TINYINT UNSIGNED; KEY (characterId, position)
character_loot_filter_condition ruleId INT UNSIGNED, slot TINYINT UNSIGNED (0-3), type TINYINT UNSIGNED,
                                op TINYINT UNSIGNED, value INT UNSIGNED, value2 INT UNSIGNED,
                                text VARCHAR(40); PK (ruleId, slot)
character_loot_filter_settings  + chatMode TINYINT UNSIGNED DEFAULT 1, + totalStored INT UNSIGNED,
                                totalSold → BIGINT UNSIGNED
```

Action ids: 0 keep, 1 sell, 2 disenchant, 3 delete, 4 store (the core's internal "no action" leaves 4).
Condition types keep the old numbers: 0 quality, 1 item level, 2 sell price, 3 item type (value =
class, value2 = subclass or 255 = any), 5 cursed (value 1/0), 6 item (value = entry), 7 name contains
(text); 4 is retired. Operators: 0 is, 1 at least, 2 at most.

Migration (in `data/sql/db-characters/loot_filter_tables.sql`, idempotent and guarded by
`INFORMATION_SCHEMA`, because the updater re-applies a module file whenever its bytes change), only
while `character_loot_filter` exists and the new rule table is empty:

1. Each enabled standalone row becomes a one-condition rule; each group becomes one rule from its
   enabled rows, action = the action of its lowest-priority row; a group or row with no enabled row
   becomes a disabled rule with all of its conditions.
2. Positions follow the old evaluation order: priority, then the lowest `ruleId`.
3. `>` v becomes `≥` v+1, `<` v becomes `≤` v−1 (`< 0` matched nothing: the rule is disabled).
4. A group's class row and subclass row merge into one item-type condition; a lone subclass row
   becomes item type weapon (if the subclass id is a weapon subclass, as the old client labelled it)
   or armor.
5. An old KEEP rule that selects trade goods, gems, recipes or consumables by item class becomes TO
   STORAGE, so it keeps depositing.
6. A group with more than four enabled rows becomes a **disabled** rule with its first four conditions
   by priority (dropping an AND condition would widen the rule, which matters for Delete).
7. The old table is renamed `character_loot_filter_legacy`; nothing is dropped.

## 6. Architecture

```
client UI (Lua, shipped by AIO) ──addon "LFLT"──▶ C++ (the only owner)
                                ◀──addon "LFLS"── cache, CRUD, validation, evaluation,
                                                  actions, statistics, test/scan, log events
```

- **C++ is the only writer** of the three tables and updates the per-character cache with every
  write (login load, CRUD, `.lootfilter toggle|reload`). Nothing reads the DB on loot. This removes the
  mass-pull plan's F1 without its risk: F1 was demoted because Lua CRUD wrote behind a cache (a deleted
  Delete rule could still destroy items); with no second writer that cannot happen. Out-of-band SQL
  needs `.lootfilter reload` (declared, as in the plan).
- Code split: `src/LootFilterRules.{h,cpp}` holds the pure logic — rule/condition model, `ItemFacts`,
  matching, evaluation, the message codec and validation — with no core includes, so an offline test
  compiles it alone; `src/LootFilter.cpp` holds the core glue (hooks, DB, cache, actions, messages,
  commands).
- Transport follows `mod-fl-player-reports`: the client whispers itself addon messages with prefix
  `LFLT`; `OnPlayerBeforeSendChatMessage` takes them; answers go out as `SMSG_MESSAGECHAT` with
  `LANG_ADDON` and prefix `LFLS`, a different prefix so the client ignores echoes. Rate limit per
  player: burst 20 messages, refill 10 per second; a bag scan at most every 2 seconds.
- Messages are `|`-separated and at most 250 bytes. A condition is `type:op:value:value2:text`,
  conditions are joined by `;`, the text allows letters, digits, space and `'-.,` (≤ 40 characters).
  - client → core: `G` (send everything), `R|id|pos|action|enabled|conds` (save; id 0 = new),
    `D|id`, `M|id|pos`, `E|id|on`, `F|on`, `C|mode`, `X` (delete all), `T|bag|slot`, `S` (scan);
    `on` is 0 or 1.
  - core → client: `I|enabled|chatMode|maxRules|allowSell|allowDE|allowDel|sold|de|del|stored`,
    `R|id|pos|action|enabled|conds` per rule, `N|count` (end of list), `T|bag|slot|result|rule`,
    `S|bag|slot|result|rule` per item and `Z|count` at the end, `L|action|entry|suffix|count|money|rule|matEntry:count,…`,
    `F|on`, `!|code`.
  - result codes: 0–4 = action, 5 = no rule, 6 = protected.
- Bag addressing: client bag 0 slots 1–16 = server bag 255 slots 23–38; client bags 1–4 = server bag
  slots 19–22, client slot n = server slot n−1.
- The server Lua becomes a stub that keeps its file name, so a deploy overwrites the old AIO handlers
  instead of leaving them live (the host policy never deletes). The client file registers itself with
  `AIO.AddAddon()`.
- The Lua moves into `mod-loot-filter/lua_scripts/` and becomes module-owned:
  `fl_host_sync_policy.json` gains `"LootFilter": "mod-loot-filter"`, `fl-lua-scripts` ignores
  `LootFilter/` (like Dungeon_Challenge and Storage), and the workbench copy is deployed from the module
  checkout.
- The summary chat mode is the loot-filter half of the mass-pull plan's F11.

## 7. Testing

- Offline: a standalone C++ test of `LootFilterRules` (codec round trips, validation rejects, matching,
  evaluation order, quest protection), compiled with `cl` like `mod-fl-player-reports/tests`; a Lua
  harness with a mocked WoW API for the client (sentences, editor validation, message building and
  parsing, list handling); the migration SQL run against a scratch schema loaded with the host's 19
  rules (from the nightly dump, local only) and with constructed edge cases.
- T1 on the workbench in a free build window: build, boot, errors baseline (the 74 CoA lines), a
  `mod-fl-testbots` scenario (sell, store, disenchant, delete, keep, quest protection, summary line,
  statistics in the DB), the probe client (CRTEST) for the four tabs with a screenshot each.
- T2: the operator in game.

## 8. Rollout

Workbench first (build coordinated with the CoA round-4 window), merge to `main`, push. Host: one MIG
entry — module pull + rebuild (the updater applies the SQL at boot), the two Lua files deployed from the
module checkout into `lua_scripts/LootFilter/`, the policy change. No `ClientCacheVersion` bump (no
cached template changes). Vault: module docs, `05-modules.md`, `09-db-tables.md`, the mass-pull row in
`12-server-todo.md` (F1 and the loot-filter half of F11 done here), `claude_log.md`.
