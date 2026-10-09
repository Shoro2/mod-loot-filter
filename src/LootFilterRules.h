/*
 * mod-loot-filter — pure rule logic
 *
 * The rule model, matching, evaluation, validation, the addon-message
 * codec, rule ordering, bag addressing and the migration of the old
 * one-condition rows. Nothing here touches the core (only Define.h for
 * the integer types), so tests/rules_test.cpp compiles it on its own.
 */

#ifndef LOOT_FILTER_RULES_H
#define LOOT_FILTER_RULES_H

#include "Define.h"
#include <algorithm>
#include <cstddef>
#include <string>
#include <utility>
#include <vector>

namespace LootFilterRules
{
    constexpr std::size_t MAX_CONDITIONS = 4;
    constexpr std::size_t MAX_TEXT = 40;
    constexpr std::size_t MAX_MESSAGE = 250;
    constexpr uint32 ANY_SUBCLASS = 255;
    constexpr uint32 MAX_QUALITY = 7;
    constexpr uint32 MAX_ITEM_LEVEL = 65535;
    constexpr uint32 MAX_ITEM_CLASS = 16;
    constexpr uint32 MAX_SUBCLASS = 31;

    enum Action : uint8
    {
        ACTION_KEEP       = 0,  // stays in the bags
        ACTION_SELL       = 1,  // vendor price straight to the player
        ACTION_DISENCHANT = 2,  // materials to the Endless Storage
        ACTION_DELETE     = 3,  // destroyed
        ACTION_STORE      = 4,  // storage-eligible items to the Endless Storage
        ACTION_COUNT      = 5
    };

    // Evaluation results: 0-4 are the actions above.
    enum Result : uint8
    {
        RESULT_NO_RULE   = 5,
        RESULT_PROTECTED = 6
    };

    // Numbers kept from the old rows; 4 (lone subclass) is retired.
    enum CondType : uint8
    {
        COND_QUALITY    = 0,
        COND_ITEM_LEVEL = 1,
        COND_SELL_PRICE = 2,
        COND_ITEM_TYPE  = 3,  // value = class, value2 = subclass or ANY
        COND_CURSED     = 5,  // value 1 = cursed, 0 = not cursed
        COND_ITEM       = 6,  // value = item entry
        COND_NAME       = 7   // text = case-insensitive substring of Name1
    };

    enum Op : uint8
    {
        OP_IS       = 0,
        OP_AT_LEAST = 1,
        OP_AT_MOST  = 2
    };

    enum ChatMode : uint8
    {
        CHAT_EVERY      = 0,
        CHAT_SUMMARY    = 1,
        CHAT_NONE       = 2,
        CHAT_MODE_COUNT = 3
    };

    struct Condition
    {
        uint8 type = COND_QUALITY;
        uint8 op = OP_IS;
        uint32 value = 0;
        uint32 value2 = 0;
        std::string text;
    };

    struct Rule
    {
        uint32 id = 0;
        uint8 position = 0;     // 1-based evaluation order
        uint8 action = ACTION_KEEP;
        bool enabled = true;
        std::vector<Condition> conditions;
    };

    // What the evaluator needs to know about one item.
    struct ItemFacts
    {
        uint32 entry = 0;
        uint32 quality = 0;
        uint32 itemLevel = 0;
        uint32 sellPrice = 0;
        uint32 itemClass = 0;
        uint32 subClass = 0;
        bool cursed = false;
        bool questItem = false;
        std::string name;
    };

    struct Verdict
    {
        uint8 result = RESULT_NO_RULE;
        uint8 position = 0;     // position of the deciding rule, 0 if none
    };

    // ---------------------------------------------------------------
    // Matching and evaluation
    // ---------------------------------------------------------------

    inline uint8 AllowedMask(bool sell, bool disenchant, bool del)
    {
        uint32 mask = (1u << ACTION_KEEP) | (1u << ACTION_STORE);
        if (sell)
            mask |= 1u << ACTION_SELL;
        if (disenchant)
            mask |= 1u << ACTION_DISENCHANT;
        if (del)
            mask |= 1u << ACTION_DELETE;
        return static_cast<uint8>(mask);
    }

    inline bool Compare(uint32 actual, uint8 op, uint32 expected)
    {
        switch (op)
        {
            case OP_IS:       return actual == expected;
            case OP_AT_LEAST: return actual >= expected;
            case OP_AT_MOST:  return actual <= expected;
            default:          return false;
        }
    }

    inline char LowerAscii(char c)
    {
        return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
    }

    inline std::string Lower(std::string s)
    {
        for (char& c : s)
            c = LowerAscii(c);
        return s;
    }

    inline bool Matches(Condition const& c, ItemFacts const& item)
    {
        switch (c.type)
        {
            case COND_QUALITY:
                return Compare(item.quality, c.op, c.value);
            case COND_ITEM_LEVEL:
                return Compare(item.itemLevel, c.op, c.value);
            case COND_SELL_PRICE:
                return Compare(item.sellPrice, c.op, c.value);
            case COND_ITEM_TYPE:
                return item.itemClass == c.value
                    && (c.value2 == ANY_SUBCLASS || item.subClass == c.value2);
            case COND_CURSED:
                return item.cursed == (c.value != 0);
            case COND_ITEM:
                return item.entry == c.value;
            case COND_NAME:
                return !c.text.empty()
                    && Lower(item.name).find(Lower(c.text)) != std::string::npos;
            default:
                return false;
        }
    }

    // `rules` must be in position order. Quest items are never touched; a
    // rule is skipped when it is off, empty, or its action is not allowed.
    inline Verdict Evaluate(std::vector<Rule> const& rules,
        ItemFacts const& item, uint8 allowedMask)
    {
        Verdict verdict;
        if (item.questItem)
        {
            verdict.result = RESULT_PROTECTED;
            return verdict;
        }

        for (Rule const& rule : rules)
        {
            if (!rule.enabled || rule.conditions.empty()
                || rule.action >= ACTION_COUNT
                || !(allowedMask & (1u << rule.action)))
                continue;

            bool all = true;
            for (Condition const& c : rule.conditions)
            {
                if (!Matches(c, item))
                {
                    all = false;
                    break;
                }
            }

            if (all)
            {
                verdict.result = rule.action;
                verdict.position = rule.position;
                return verdict;
            }
        }

        return verdict;
    }

    // ---------------------------------------------------------------
    // Validation
    // ---------------------------------------------------------------

    inline bool IsTextChar(char c)
    {
        return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')
            || (c >= '0' && c <= '9') || c == ' ' || c == '\''
            || c == '-' || c == '.' || c == ',';
    }

    inline bool ValidText(std::string const& text)
    {
        if (text.empty() || text.size() > MAX_TEXT)
            return false;
        return std::all_of(text.begin(), text.end(), IsTextChar);
    }

    inline bool ValidCondition(Condition const& c)
    {
        bool const plain = c.value2 == 0 && c.text.empty();
        switch (c.type)
        {
            case COND_QUALITY:
                return plain && c.op <= OP_AT_MOST && c.value <= MAX_QUALITY;
            case COND_ITEM_LEVEL:
                return plain && c.op <= OP_AT_MOST && c.value <= MAX_ITEM_LEVEL;
            case COND_SELL_PRICE:
                return plain && c.op <= OP_AT_MOST;
            case COND_ITEM_TYPE:
                return c.text.empty() && c.op == OP_IS
                    && c.value <= MAX_ITEM_CLASS
                    && (c.value2 <= MAX_SUBCLASS || c.value2 == ANY_SUBCLASS);
            case COND_CURSED:
                return plain && c.op == OP_IS && c.value <= 1;
            case COND_ITEM:
                return plain && c.op == OP_IS && c.value != 0;
            case COND_NAME:
                return c.op == OP_IS && c.value == 0 && c.value2 == 0
                    && ValidText(c.text);
            default:
                return false;
        }
    }

    inline bool ValidRule(Rule const& rule)
    {
        if (rule.action >= ACTION_COUNT || rule.conditions.empty()
            || rule.conditions.size() > MAX_CONDITIONS)
            return false;
        return std::all_of(rule.conditions.begin(), rule.conditions.end(),
            ValidCondition);
    }

    // ---------------------------------------------------------------
    // Message codec: fields split by '|', conditions by ';', condition
    // fields by ':' ("type:op:value:value2:text").
    // ---------------------------------------------------------------

    inline bool ParseUInt(std::string const& s, uint32 max, uint32& out)
    {
        if (s.empty() || s.size() > 10)
            return false;
        uint64 v = 0;
        for (char c : s)
        {
            if (c < '0' || c > '9')
                return false;
            v = v * 10 + static_cast<uint64>(c - '0');
        }
        if (v > max)
            return false;
        out = static_cast<uint32>(v);
        return true;
    }

    inline std::vector<std::string> Split(std::string const& s, char sep)
    {
        std::vector<std::string> parts;
        std::size_t start = 0;
        while (true)
        {
            std::size_t const at = s.find(sep, start);
            if (at == std::string::npos)
            {
                parts.push_back(s.substr(start));
                return parts;
            }
            parts.push_back(s.substr(start, at - start));
            start = at + 1;
        }
    }

    inline std::string EncodeCondition(Condition const& c)
    {
        return std::to_string(c.type) + ":" + std::to_string(c.op) + ":"
            + std::to_string(c.value) + ":" + std::to_string(c.value2) + ":"
            + c.text;
    }

    inline bool DecodeCondition(std::string const& s, Condition& out)
    {
        std::vector<std::string> const f = Split(s, ':');
        if (f.size() != 5)
            return false;
        uint32 type = 0;
        uint32 op = 0;
        Condition c;
        if (!ParseUInt(f[0], 255, type) || !ParseUInt(f[1], 255, op)
            || !ParseUInt(f[2], 0xFFFFFFFFu, c.value)
            || !ParseUInt(f[3], 0xFFFFFFFFu, c.value2))
            return false;
        c.type = static_cast<uint8>(type);
        c.op = static_cast<uint8>(op);
        c.text = f[4];
        if (!ValidCondition(c))
            return false;
        out = std::move(c);
        return true;
    }

    inline std::string EncodeConditions(std::vector<Condition> const& conds)
    {
        std::string s;
        for (std::size_t i = 0; i < conds.size(); ++i)
        {
            if (i)
                s += ';';
            s += EncodeCondition(conds[i]);
        }
        return s;
    }

    inline bool DecodeConditions(std::string const& s,
        std::vector<Condition>& out)
    {
        if (s.empty())
            return false;
        std::vector<std::string> const parts = Split(s, ';');
        if (parts.size() > MAX_CONDITIONS)
            return false;
        std::vector<Condition> conds;
        for (std::string const& p : parts)
        {
            Condition c;
            if (!DecodeCondition(p, c))
                return false;
            conds.push_back(std::move(c));
        }
        out = std::move(conds);
        return true;
    }

    // "id|position|action|enabled|conditions"
    inline std::string EncodeRule(Rule const& r)
    {
        return std::to_string(r.id) + "|" + std::to_string(r.position) + "|"
            + std::to_string(r.action) + "|" + (r.enabled ? "1" : "0") + "|"
            + EncodeConditions(r.conditions);
    }

    // Reads the five rule fields starting at f[at].
    inline bool DecodeRule(std::vector<std::string> const& f, std::size_t at,
        Rule& out)
    {
        if (f.size() < at + 5)
            return false;
        uint32 position = 0;
        uint32 action = 0;
        uint32 enabled = 0;
        Rule r;
        if (!ParseUInt(f[at], 0xFFFFFFFFu, r.id)
            || !ParseUInt(f[at + 1], 255, position)
            || !ParseUInt(f[at + 2], 255, action)
            || !ParseUInt(f[at + 3], 1, enabled)
            || !DecodeConditions(f[at + 4], r.conditions))
            return false;
        r.position = static_cast<uint8>(position);
        r.action = static_cast<uint8>(action);
        r.enabled = enabled != 0;
        if (!ValidRule(r))
            return false;
        out = std::move(r);
        return true;
    }

    // ---------------------------------------------------------------
    // Ordering: the vector order is the evaluation order; positions are
    // always 1..n after a change.
    // ---------------------------------------------------------------

    inline void Renumber(std::vector<Rule>& rules)
    {
        for (std::size_t i = 0; i < rules.size(); ++i)
            rules[i].position = static_cast<uint8>(i + 1);
    }

    inline void SortByPosition(std::vector<Rule>& rules)
    {
        std::stable_sort(rules.begin(), rules.end(),
            [](Rule const& a, Rule const& b)
            {
                if (a.position != b.position)
                    return a.position < b.position;
                return a.id < b.id;
            });
        Renumber(rules);
    }

    // pos 0 or past the end appends.
    inline void Insert(std::vector<Rule>& rules, Rule rule, uint32 pos)
    {
        if (pos == 0 || pos > rules.size())
            rules.push_back(std::move(rule));
        else
            rules.insert(rules.begin() + (pos - 1), std::move(rule));
        Renumber(rules);
    }

    inline bool Move(std::vector<Rule>& rules, uint32 id, uint32 pos)
    {
        auto it = std::find_if(rules.begin(), rules.end(),
            [id](Rule const& r) { return r.id == id; });
        if (it == rules.end())
            return false;
        Rule rule = std::move(*it);
        rules.erase(it);
        Insert(rules, std::move(rule), pos);
        return true;
    }

    inline bool Remove(std::vector<Rule>& rules, uint32 id)
    {
        auto it = std::find_if(rules.begin(), rules.end(),
            [id](Rule const& r) { return r.id == id; });
        if (it == rules.end())
            return false;
        rules.erase(it);
        Renumber(rules);
        return true;
    }

    // ---------------------------------------------------------------
    // Bag addressing. Client bag 0 slots 1-16 = server bag 255 slots
    // 23-38; client bags 1-4 = server bag slots 19-22, slot n = n-1.
    // ---------------------------------------------------------------

    constexpr uint8 SERVER_BAG_0 = 255;
    constexpr uint8 BACKPACK_FIRST = 23;
    constexpr uint8 BACKPACK_SIZE = 16;
    constexpr uint8 BAG_SLOT_FIRST = 19;
    constexpr uint8 BAG_COUNT = 4;
    constexpr uint8 MAX_BAG_SIZE = 36;

    inline bool ClientToServer(uint32 cbag, uint32 cslot, uint8& bag,
        uint8& slot)
    {
        if (cbag == 0)
        {
            if (cslot < 1 || cslot > BACKPACK_SIZE)
                return false;
            bag = SERVER_BAG_0;
            slot = static_cast<uint8>(BACKPACK_FIRST + cslot - 1);
            return true;
        }
        if (cbag > BAG_COUNT || cslot < 1 || cslot > MAX_BAG_SIZE)
            return false;
        bag = static_cast<uint8>(BAG_SLOT_FIRST + cbag - 1);
        slot = static_cast<uint8>(cslot - 1);
        return true;
    }

    inline bool ServerToClient(uint8 bag, uint8 slot, uint32& cbag,
        uint32& cslot)
    {
        if (bag == SERVER_BAG_0)
        {
            if (slot < BACKPACK_FIRST || slot >= BACKPACK_FIRST + BACKPACK_SIZE)
                return false;
            cbag = 0;
            cslot = slot - BACKPACK_FIRST + 1u;
            return true;
        }
        if (bag < BAG_SLOT_FIRST || bag >= BAG_SLOT_FIRST + BAG_COUNT
            || slot >= MAX_BAG_SIZE)
            return false;
        cbag = bag - BAG_SLOT_FIRST + 1u;
        cslot = slot + 1u;
        return true;
    }

    // ---------------------------------------------------------------
    // Migration of the old table (one condition per row, AND groups by
    // number, priority order, operators = > <).
    // ---------------------------------------------------------------

    struct LegacyRow
    {
        uint32 characterId = 0;
        uint32 ruleId = 0;
        uint32 ruleGroup = 0;   // 0 = standalone
        uint8 type = 0;         // old 3 = class, old 4 = subclass
        uint8 op = 0;           // old 0 '=', 1 '>', 2 '<'
        uint32 value = 0;
        std::string text;
        uint8 action = 0;
        uint8 priority = 0;
        bool enabled = true;
    };

    struct MigrationResult
    {
        std::vector<Rule> rules;    // positions 1..n, ids 0 (caller assigns)
        uint32 disabled = 0;        // rules switched off by the migration
        uint32 dropped = 0;         // units that could not become a rule
    };

    // Subclass ids the old client labelled as weapons (checked first).
    inline bool IsWeaponSubclass(uint32 sub)
    {
        switch (sub)
        {
            case 0: case 1: case 2: case 3: case 4: case 5: case 6: case 7:
            case 8: case 10: case 13: case 14: case 15: case 16: case 18:
            case 19: case 20:
                return true;
            default:
                return false;
        }
    }

    // Classes whose items the old KEEP moved into the Endless Storage:
    // consumable, gem, trade goods, recipe.
    inline bool IsStorableClass(uint32 itemClass)
    {
        return itemClass == 0 || itemClass == 3 || itemClass == 7
            || itemClass == 9;
    }

    namespace Detail
    {
        struct Unit
        {
            bool group = false;
            std::vector<LegacyRow> rows;
        };

        inline bool RowBefore(LegacyRow const& a, LegacyRow const& b)
        {
            if (a.priority != b.priority)
                return a.priority < b.priority;
            return a.ruleId < b.ruleId;
        }

        // Converts a value/operator pair; false = cannot be expressed.
        inline bool ConvertOp(uint8 oldOp, uint32 value, uint8& op,
            uint32& out)
        {
            switch (oldOp)
            {
                case 0:
                    op = OP_IS;
                    out = value;
                    return true;
                case 1:
                    op = OP_AT_LEAST;
                    if (value == 0xFFFFFFFFu)
                    {
                        out = value;
                        return false;
                    }
                    out = value + 1;
                    return true;
                case 2:
                    op = OP_AT_MOST;
                    if (value == 0)
                    {
                        out = 0;
                        return false;
                    }
                    out = value - 1;
                    return true;
                default:
                    op = OP_IS;
                    out = value;
                    return false;
            }
        }

        inline std::string CleanText(std::string const& text)
        {
            std::string out;
            for (char c : text)
                if (IsTextChar(c) && out.size() < MAX_TEXT)
                    out += c;
            return out;
        }
    }

    // `rows` are the rows of one character.
    inline MigrationResult MigrateCharacter(std::vector<LegacyRow> const& rows)
    {
        using namespace Detail;
        MigrationResult result;

        // 1. Units: every standalone row, every group number.
        std::vector<Unit> units;
        for (LegacyRow const& row : rows)
        {
            if (row.ruleGroup == 0)
            {
                Unit u;
                u.rows.push_back(row);
                units.push_back(std::move(u));
                continue;
            }
            auto it = std::find_if(units.begin(), units.end(),
                [&row](Unit const& u)
                {
                    return u.group && u.rows.front().ruleGroup == row.ruleGroup;
                });
            if (it == units.end())
            {
                Unit u;
                u.group = true;
                u.rows.push_back(row);
                units.push_back(std::move(u));
            }
            else
                it->rows.push_back(row);
        }

        struct Built
        {
            uint8 priority = 0;
            bool group = false;
            uint32 firstRuleId = 0;
            Rule rule;
        };
        std::vector<Built> built;

        for (Unit& unit : units)
        {
            // 2. The rows the old core evaluated: the enabled ones, or all
            // of them for a unit that was completely off.
            std::vector<LegacyRow> considered;
            for (LegacyRow const& r : unit.rows)
                if (r.enabled)
                    considered.push_back(r);
            bool enabled = !considered.empty();
            if (!enabled)
                considered = unit.rows;
            std::sort(considered.begin(), considered.end(), RowBefore);

            LegacyRow const& first = considered.front();
            if (first.action > ACTION_DELETE)
            {
                ++result.dropped;
                continue;
            }

            // 3. Conditions in row order. Class rows become item-type
            // conditions; subclass rows are joined afterwards. Anything that
            // cannot be expressed exactly switches the rule off rather than
            // widening it.
            std::vector<Condition> conds;
            std::vector<uint32> subclasses;
            for (LegacyRow const& r : considered)
            {
                Condition c;
                switch (r.type)
                {
                    case COND_QUALITY:
                    case COND_ITEM_LEVEL:
                    case COND_SELL_PRICE:
                    {
                        c.type = r.type;
                        if (!ConvertOp(r.op, r.value, c.op, c.value))
                            enabled = false;
                        // The March UI stored "below" as '=' for these two.
                        if (r.op == 0 && r.type != COND_QUALITY)
                            enabled = false;
                        uint32 const cap = r.type == COND_QUALITY ? MAX_QUALITY
                            : r.type == COND_ITEM_LEVEL ? MAX_ITEM_LEVEL
                            : 0xFFFFFFFFu;
                        if (c.value > cap)
                        {
                            c.value = cap;
                            enabled = false;
                        }
                        conds.push_back(c);
                        break;
                    }
                    case COND_ITEM_TYPE:
                        if (r.op != 0 || r.value > MAX_ITEM_CLASS)
                            enabled = false;
                        if (r.value > MAX_ITEM_CLASS)
                            continue;
                        c.type = COND_ITEM_TYPE;
                        c.value = r.value;
                        c.value2 = ANY_SUBCLASS;
                        conds.push_back(c);
                        break;
                    case 4: // old subclass row
                        if (r.op != 0 || r.value > MAX_SUBCLASS)
                            enabled = false;
                        if (r.value <= MAX_SUBCLASS)
                            subclasses.push_back(r.value);
                        break;
                    case COND_CURSED:
                        c.type = COND_CURSED;
                        c.value = r.value != 0 ? 1 : 0;
                        conds.push_back(c);
                        break;
                    case COND_ITEM:
                        if (r.op != 0 || r.value == 0)
                            enabled = false;
                        if (r.value == 0)
                            continue;
                        c.type = COND_ITEM;
                        c.value = r.value;
                        conds.push_back(c);
                        break;
                    case COND_NAME:
                    {
                        std::string const clean = CleanText(r.text);
                        if (clean != r.text || clean.empty())
                            enabled = false;
                        if (clean.empty())
                            continue;
                        c.type = COND_NAME;
                        c.text = clean;
                        conds.push_back(c);
                        break;
                    }
                    default:
                        enabled = false;
                        break;
                }
            }

            // 4. The first subclass joins the first item-type condition; any
            // other subclass becomes weapon or armor by the old client label.
            bool merged = false;
            for (uint32 sub : subclasses)
            {
                if (!merged)
                {
                    auto target = std::find_if(conds.begin(), conds.end(),
                        [](Condition const& x)
                        {
                            return x.type == COND_ITEM_TYPE
                                && x.value2 == ANY_SUBCLASS;
                        });
                    if (target != conds.end())
                    {
                        target->value2 = sub;
                        merged = true;
                        continue;
                    }
                }
                Condition t;
                t.type = COND_ITEM_TYPE;
                t.value = IsWeaponSubclass(sub) ? 2 : 4;
                t.value2 = sub;
                conds.push_back(t);
            }

            if (conds.empty())
            {
                ++result.dropped;
                continue;
            }
            if (conds.size() > MAX_CONDITIONS)
            {
                conds.resize(MAX_CONDITIONS);
                enabled = false;
            }

            Rule rule;
            rule.action = first.action;
            rule.enabled = enabled;
            rule.conditions = std::move(conds);

            // 5. The old KEEP deposited storable classes: make it explicit.
            if (rule.action == ACTION_KEEP)
                for (Condition const& c : rule.conditions)
                    if (c.type == COND_ITEM_TYPE && IsStorableClass(c.value))
                        rule.action = ACTION_STORE;

            if (!ValidRule(rule))
            {
                ++result.dropped;
                continue;
            }

            Built b;
            b.priority = first.priority;
            b.group = unit.group;
            b.firstRuleId = first.ruleId;
            b.rule = std::move(rule);
            built.push_back(std::move(b));
        }

        // 2. Old evaluation order: priority, standalone before groups,
        // then the lowest rule id.
        std::stable_sort(built.begin(), built.end(),
            [](Built const& a, Built const& b)
            {
                if (a.priority != b.priority)
                    return a.priority < b.priority;
                if (a.group != b.group)
                    return !a.group;
                return a.firstRuleId < b.firstRuleId;
            });

        for (Built& b : built)
        {
            if (!b.rule.enabled)
                ++result.disabled;
            result.rules.push_back(std::move(b.rule));
        }
        Renumber(result.rules);
        return result;
    }
}

#endif // LOOT_FILTER_RULES_H
