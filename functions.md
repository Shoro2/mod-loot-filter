# Functions & mechanics — mod-loot-filter

> How the module works. For purpose and ids see `CLAUDE.md`; the design rationale is in
> `docs/superpowers/specs/2026-10-09-loot-filter-ui-rework-design.md`.

## Module loader

`Addmod_loot_filterScripts()` (`src/mod_loot_filter_loader.cpp`) → `AddLootFilterScripts()` registers
`LootFilter_World`, `LootFilter_Player`, `LootFilter_Command`.

## Hooks

| Script | Hook | Behaviour |
|------|------|-----------|
| World | `OnAfterConfigLoad` | reads the six `LootFilter.*` keys (`MaxRulesPerChar` clamped 1-100) |
| World | `OnStartup` | `MigrateLegacyTable()` (below), then the rule-id counter = `MAX(ruleId) + 1` |
| Player | `OnPlayerLogin` | `LoadState()`: settings row (created if missing) + rules with conditions → cache |
| Player | `OnPlayerLogout` | flushes the pending statistics batch, drops the cache entry |
| Player | `OnPlayerLootItem` | if the filter is on and the character has rules: schedules `LootFilterEvent` for the next tick — **no DB access** |
| Player | `OnPlayerBeforeSendChatMessage` | takes addon whispers starting with `LFLT\t` (≤ 250 bytes payload) → `HandleRequest()` |
| Player | `OnPlayerDeleteFromDB` | deletes the character's rule, condition and settings rows in the deletion transaction |

The loot evaluation runs one tick late because mod-paragon-itemgen sets the slot 11 enchant (the cursed
marker) in the same loot hook.

## Evaluation (`LootFilterRules::Evaluate`)

```
quest item (class 12, Bonding 4/5, StartQuest > 0)  → PROTECTED, nothing happens
for rule in position order:
    skip if off, empty, or its action is switched off by LootFilter.Allow*
    all conditions match → that rule's action
no rule matched → NO RULE, the item stays
```

`Matches`: quality / item level / sell price compare with is (=), at least (≥), at most (≤); item type =
class and (subclass or 255 = any); cursed = slot 11 enchant 920001 or 950001-950099; item = entry; name =
case-insensitive substring of `Name1`.

## Actions (`Act` → `Record`)

| Action | Effect | Falls back to KEEP when |
|---|---|---|
| 0 Keep | nothing | — |
| 4 To storage | `custom_endless_storage` += count, item destroyed | not storage-eligible (recipe; stackable food; stackable trade goods or gem) |
| 1 Sell | money += SellPrice × count, item destroyed | sell price 0 or the money would pass `MAX_MONEY_AMOUNT` → **stored if storage-eligible**, else kept |
| 2 Disenchant | `LootTemplates_Disenchant` rolled; storable mats to the storage, the rest to the bags (mail if full); item destroyed | `DisenchantID` 0 → **stored if storage-eligible**, else kept |
| 3 Delete | item destroyed | — |

The action acts on the item the loot hook reports, i.e. the whole stack the loot merged into (unchanged
behaviour). `Record` then:

- adds to the cached totals and the **batch** (sold items + money, disenchanted, stored, deleted); the
  first entry of a batch schedules `LootFilterSummaryEvent` one tick later, which writes the batch as one
  `UPDATE … SET total = total + …` and, in chat mode 1, prints the summary line
  (`[Loot Filter] Sold 5 for 2s 40c, disenchanted 1, stored 6, deleted 1.`);
- sends the window an `L` message;
- in chat mode 0 prints one line per action with item links (`Sold [Broken Fang] x4 for 1s 60c.`,
  `Kept [X] (no vendor price).` …). `LootFilter.LogActions = 0` silences both chat modes.

## Window requests (`HandleRequest`)

Rate limit per character: 20 messages burst, 10 per second refill; a bag scan at most every 2 s
(`!|busy`). Every rule change rewrites the character's rules in one transaction (`SaveRules`) and answers
with the full list.

## Addon messages

Fields are separated by `|`; a condition is `type:op:value:value2:text`, conditions are joined by `;`;
a rule is `id|position|action|enabled|conditions`.

| Client → core (`LFLT`) | Meaning |
|---|---|
| `G` | send settings and rules |
| `R|id|pos|action|enabled|conds` | save; `id` 0 = new; `pos` 0 or past the end = last |
| `D|id` · `M|id|pos` · `E|id|on` | delete · move · switch on/off |
| `F|on` · `C|mode` · `X` | filter on/off · chat mode 0/1/2 · delete all rules |
| `T|bag|slot` · `S` | test one bag slot · scan all bags (client bag 0-4, slot 1-n) |

| Core → client (`LFLS`) | Meaning |
|---|---|
| `I|enabled|chatMode|maxRules|allowSell|allowDE|allowDel|sold|de|del|stored` | settings, limits, totals |
| `R|…` per rule, then `N|count` | the rule list (the client swaps it in on `N`) |
| `T|bag|slot|result|position|entry` | test result: 0-4 action, 5 no rule, 6 protected |
| `S|bag|slot|result|position|entry` per item, then `Z|count` | bag scan |
| `L|action|entry|suffix|count|money|position|entry:count,…` | one action happened |
| `F|on` | filter state (also after `.lootfilter toggle`) |
| `!|code` | `limit`, `invalid`, `action`, `notfound`, `busy`, `noitem`, `disabled` |

Bag addressing: client bag 0 slot n = server bag 255 slot 22+n; client bag b (1-4) slot n = server bag
slot 18+b, slot n-1.

## Startup migration (`MigrateLegacyTable`)

Runs while `character_loot_filter` exists. If `character_loot_filter_rule` already has rows the old table
is only renamed; if `character_loot_filter_legacy` already exists nothing happens (error logged). Otherwise
orphan condition rows are deleted, the old rows are read per character, `MigrateCharacter()` builds the
rules, one transaction inserts them, the rule count is checked (a failed commit only logs, so a mismatch
leaves the old table in place for the next start), then `RENAME TABLE character_loot_filter TO
character_loot_filter_legacy`. New rule ids come from a counter set at startup (and raised by
`.lootfilter reload`) to one above every id in the rule and condition tables. Log line:
`mod-loot-filter: migrated N rule(s) of M character(s) … (X switched off for review, Y dropped)`.

`MigrateCharacter`: standalone row = one rule; group = one rule from its enabled rows (all rows, switched
off, when none was enabled), action of the lowest-priority row; order = priority, standalone before group,
lowest rule id; `>` v → at least v+1, `<` v → at most v-1; class + subclass rows → one item-type
condition, a lone subclass → weapon (old client label) or armor; old KEEP on trade goods / gems / recipes /
consumables → TO STORAGE. Switched off for review: anything not expressible exactly (operator on class,
subclass or item, odd or long names, more than four conditions, `< 0`) and **item level / sell price rows
with '='** in SELL / DISENCHANT / DELETE rules, which the March 2026 UI saved for "below" (a KEEP with
'=' stays on as it behaves today: switching a KEEP off would widen every rule below it).

## Commands

| Command | Effect |
|---|---|
| `.lootfilter reload` | re-reads settings and rules from the DB (after manual SQL) and sends them to the window |
| `.lootfilter toggle` | filter on/off, saved, window updated |
| `.lootfilter stats` | totals |
| `.lootfilter request <payload>` | the window's protocol from chat (same handler, limits, validation); the answers are also printed as `LFLS <message>` — for test bots and debugging |

## Configuration

| Key | Default | Effect |
|-----------|---------|---------|
| `LootFilter.Enable` | 1 | master switch (off: no state, no filtering, the window gets `!|disabled`) |
| `LootFilter.AllowSell` / `AllowDisenchant` / `AllowDelete` | 1 | 0 = rules with that action are skipped and the editor greys it out |
| `LootFilter.LogActions` | 1 | 0 = no chat output in any chat mode |
| `LootFilter.MaxRulesPerChar` | 30 | 1-100 |

## Tests

- `tests\build_offline.cmd` — compiles `tests/rules_test.cpp` against `LootFilterRules.h` (MSVC, `/W4 /WX`,
  only `Define.h` from the core) and runs the client harness `tests/client_test.lua` with a Lua 5.2 built
  from `dcore_bin\_deps\lua52-src` into `build\`.
- `tests/loot_filter.tbs` — mod-fl-testbots scenario (queue `loot_filter`): a bot kills Wild Turkeys (32820, one
  Wild Turkey 44834 each, looted by mod-auto-loot) under SELL, TO STORAGE, KEEP, KEEP-over-DELETE (off and on),
  filter off, a bag scan and invalid requests, and checks the bags.
- `tests\schema_test.ps1` — the SQL file twice on a scratch schema `lf_schema_test` (fresh and on the old
  tables), dropped afterwards.

## Known limitations

- Rules edited by hand in the DB need `.lootfilter reload` (the cache is the source of truth).
- Item links in the log are built from entry + random property id; the suffix factor is not sent, so a
  random-suffix tooltip may show other stat values than the real item.
