# Funktionen & Mechaniken — mod-loot-filter

> Detaillierte Funktions- und Mechanik-Referenz. Inhalts-/Zweck-Doku siehe `CLAUDE.md`.

## Modul-Loader

### `Addmod_loot_filterScripts()`
- **Datei**: `src/mod_loot_filter_loader.cpp`
- **Wirkung**: registriert die `LootFilter`-Klasse (`PlayerScript` + `WorldScript` + `CommandScript`).

## Enums (`src/LootFilter.h`)

```cpp
enum LootFilterCondition {
    QUALITY = 0, ITEM_LEVEL = 1, SELL_PRICE = 2, ITEM_CLASS = 3,
    ITEM_SUBCLASS = 4, IS_CURSED = 5, ITEM_ID = 6, NAME_CONTAINS = 7
};

enum LootFilterOp {  // nur für numerische Conditions
    OP_EQUALS = 0, OP_GREATER = 1, OP_LESS = 2
};

enum LootFilterAction {
    KEEP = 0, SELL = 1, DISENCHANT = 2, DELETE = 3
};
```

## Hook-Punkte (PlayerScript)

| Hook | Verhalten |
|------|-----------|
| `OnPlayerLogin` | `LoadRulesForPlayer(guid)` + `LoadSettingsForPlayer(guid)` → in In-Memory-Cache |
| `OnPlayerLootItem` | **Deferred** auf nächsten Server-Tick (siehe Hinweis unten), dann `EvaluateFilter(player, item)` |
| `OnPlayerLogout` | Stats persistieren, Cache invalidieren |

`WorldScript`:
| Hook | Verhalten |
|------|-----------|
| `OnAfterConfigLoad` | alle 6 Konfig-Keys via `sConfigMgr->GetOption<>()` lesen |

> **Wichtig — Deferred Eval**: Die Filter-Auswertung erfolgt **nicht** synchron im `OnPlayerLootItem`. Der Hook fügt das Item nur in eine Pending-Queue ein; die eigentliche Evaluation läuft im nächsten Server-Tick. Grund: mod-paragon-itemgen modifiziert Slot 11 ebenfalls im `OnPlayerLootItem`-Hook — würde der Filter sofort prüfen, wäre die `IsParagonCursedItem`-Erkennung racy.

## Kern-Funktionen (`src/LootFilter.cpp`)

| Funktion | Zweck |
|----------|-------|
| `EvaluateFilter(Player*, Item*)` | iteriert Regeln in Prioritätsreihenfolge, gibt **erste** matchende Action zurück |
| `MatchesCondition(rule, item, proto)` | Eval einer einzelnen Regel: schaltet via `conditionType` auf passendes Feld, vergleicht via `conditionOp` |
| `ApplyAction(player, item, action, rule)` | Disptcht auf `SellItem` / `DisenchantItem` / `DeleteItem` / Keep+Storage-Deposit |
| `SellItem(Player*, Item*)` | erhöht `totalSold` um `SellPrice * count`, Item destroy, Money formatiert (`Xg Ys Zc`) |
| `DisenchantItem(Player*, Item*)` | rollt `LootTemplates_Disenchant` (kein Skill-Check), Materials in Inventar oder (falls eligible) Endless Storage; Fallback bei Non-disenchantable: Keep |
| `DeleteItem(Player*, Item*)` | hartes destroy ohne Reward |
| `IsParagonCursedItem(Item*)` | prüft Slot 11 auf Enchant-ID `920001` oder Range `950001`-`950099` |
| `LoadRulesForPlayer(guid)` | Prepared-SELECT auf `character_loot_filter` ORDER BY priority |
| `LoadSettingsForPlayer(guid)` | Prepared-SELECT auf `character_loot_filter_settings` |
| `IsStorageEligible(item)` | true wenn Class 7 (TradeGoods stackable) oder Class 3 (Gem stackable) oder Class 9 (Recipe) |

### Action-Special-Cases

- **`SellPrice == 0`** → Action wird zu Keep umgewandelt (Items lassen sich nicht für 0 Kupfer verkaufen).
- **Item nicht disenchantable** → Disenchant-Action fällt auf Keep zurück (vorher: auf Sell — wurde 2026-03-22 korrigiert).
- **Keep + Item ist storage-eligible** → wird in `custom_endless_storage` deponiert statt im Inventar gehalten. Log-Eintrag "Stored [item] x N in Storage".

## Prioritäts-Eval

```
alle Regeln (standalone + group) gemeinsam in priority ASC sortiert
  └─ pro Regel: MatchesCondition?
     └─ ja → return action  (first match wins)
```

Regelung seit 2026-03-22 (Commit `8818661`): vorher hatten standalone-Regeln immer Vorrang vor Group-Regeln, was die Priority untergrub.

## Money-Format

```
Eingabe: 12345 Kupfer
Ausgabe: "1g 23s 45c"
```

Implementiert in einer kleinen Helper-Funktion (siehe `LootFilter.cpp`). 0-Anteile werden weggelassen ("1g" statt "1g 0s 0c").

## Chat-Commands (CommandScript)

```
.lootfilter reload    → Rules + Settings aus DB neu laden (in-memory cache)
.lootfilter toggle    → filterEnabled bit kippen, persistieren
.lootfilter stats     → totalSold (g/s/c), totalDisenchanted, totalDeleted ausgeben
```

Alle `SEC_PLAYER`. Kein Cooldown.

## AIO-Handler (Lua)

Server-Side (Client → Server, in `LootFilter_Server.lua`):

| Handler | Args | Wirkung |
|---------|------|---------|
| `RequestData` | — | sendet Rules + Settings an Client |
| `AddRule` | conditionType, conditionOp, conditionValue, conditionStr, action, priority | INSERT `character_loot_filter`, in-memory cache update |
| `DeleteRule` | ruleId | DELETE + cache update |
| `ToggleRule` | ruleId | UPDATE enabled |
| `ToggleFilter` | — | UPDATE settings.filterEnabled |
| `UpdatePriority` | ruleId, newPriority | UPDATE + re-sort |
| `DeleteAllRules` | — | DELETE WHERE characterId = ? |

Client-Side (Server → Client, in `LootFilter_Client.lua`):

| Handler | Args | Wirkung |
|---------|------|---------|
| `ReceiveSettings` | filterEnabled, totalSold, totalDisenchanted, totalDeleted | UI-Update |
| `ClearRules` | — | client-side rule cache leeren |
| `ReceiveRule` | ruleId, conditionType, op, value, str, action, priority, enabled | einzelne Regel an Client |
| `RefreshUI` | — | UI-Redraw triggern |

## Konfigurations-Optionen

| Schlüssel | Default | Wirkung |
|-----------|---------|---------|
| `LootFilter.Enable` | `true` | Master-Toggle |
| `LootFilter.AllowSell` | `true` | Sell-Action erlauben |
| `LootFilter.AllowDisenchant` | `true` | DE-Action erlauben |
| `LootFilter.AllowDelete` | `true` | Delete-Action erlauben |
| `LootFilter.LogActions` | `true` | Sysmessage pro Filter-Action |
| `LootFilter.MaxRulesPerChar` | `30` | Limit für `AddRule` |

Bei `false` für eine `Allow*`-Option fällt die jeweilige Aktion auf Keep zurück (mit Log).

## Bekannte Einschränkungen

- **Eluna-Lua DB-Calls** verwenden String-Concatenation (kein PreparedStatement-Equivalent in Eluna).
- **Cursed-Detection** klappt nur, wenn mod-paragon-itemgen den Slot-11-Eintrag bereits gesetzt hat — daher der deferred-Eval.
- **`LootTemplates_Disenchant`** ist global — keine Server-Konfig pro Item-Quality möglich, alles vanilla DE-Loot.
