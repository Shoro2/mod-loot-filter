/*
 * Offline test of src/LootFilterRules.h (no AzerothCore build needed).
 * Build and run: tests\build_offline.cmd
 */

#include "../src/LootFilterRules.h"

#include <cstdio>
#include <string>
#include <vector>

using namespace LootFilterRules;

namespace
{
    int g_checks = 0;
    int g_failures = 0;

    void Check(bool ok, char const* expr, int line)
    {
        ++g_checks;
        if (!ok)
        {
            ++g_failures;
            std::printf("FAIL line %d: %s\n", line, expr);
        }
    }

#define CHECK(x) Check((x), #x, __LINE__)

    Condition Cond(uint8 type, uint8 op, uint32 value, uint32 value2 = 0,
        std::string text = "")
    {
        Condition c;
        c.type = type;
        c.op = op;
        c.value = value;
        c.value2 = value2;
        c.text = std::move(text);
        return c;
    }

    Rule MakeRule(uint32 id, uint8 action, std::vector<Condition> conds,
        bool enabled = true)
    {
        Rule r;
        r.id = id;
        r.action = action;
        r.enabled = enabled;
        r.conditions = std::move(conds);
        return r;
    }

    ItemFacts Hood()
    {
        ItemFacts f;
        f.entry = 1001;
        f.quality = 2;
        f.itemLevel = 150;
        f.sellPrice = 9840;
        f.itemClass = 4;
        f.subClass = 1;
        f.cursed = false;
        f.questItem = false;
        f.name = "Vrykul Silk Hood of the Owl";
        return f;
    }

    bool SameCond(Condition const& a, Condition const& b)
    {
        return a.type == b.type && a.op == b.op && a.value == b.value
            && a.value2 == b.value2 && a.text == b.text;
    }

    bool SameConds(std::vector<Condition> const& a,
        std::vector<Condition> const& b)
    {
        if (a.size() != b.size())
            return false;
        for (std::size_t i = 0; i < a.size(); ++i)
            if (!SameCond(a[i], b[i]))
                return false;
        return true;
    }

    LegacyRow Row(uint32 character, uint32 ruleId, uint32 group, uint8 type,
        uint8 op, uint32 value, std::string text, uint8 action, uint8 priority,
        bool enabled)
    {
        LegacyRow r;
        r.characterId = character;
        r.ruleId = ruleId;
        r.ruleGroup = group;
        r.type = type;
        r.op = op;
        r.value = value;
        r.text = std::move(text);
        r.action = action;
        r.priority = priority;
        r.enabled = enabled;
        return r;
    }

    std::vector<LegacyRow> RowsOf(std::vector<LegacyRow> const& all,
        uint32 character)
    {
        std::vector<LegacyRow> out;
        for (LegacyRow const& r : all)
            if (r.characterId == character)
                out.push_back(r);
        return out;
    }
}

static void TestMatching()
{
    ItemFacts const item = Hood();

    CHECK(Matches(Cond(COND_QUALITY, OP_IS, 2), item));
    CHECK(!Matches(Cond(COND_QUALITY, OP_IS, 3), item));
    CHECK(Matches(Cond(COND_QUALITY, OP_AT_LEAST, 2), item));
    CHECK(!Matches(Cond(COND_QUALITY, OP_AT_LEAST, 3), item));
    CHECK(Matches(Cond(COND_QUALITY, OP_AT_MOST, 2), item));
    CHECK(!Matches(Cond(COND_QUALITY, OP_AT_MOST, 1), item));

    CHECK(Matches(Cond(COND_ITEM_LEVEL, OP_AT_MOST, 150), item));
    CHECK(!Matches(Cond(COND_ITEM_LEVEL, OP_AT_MOST, 149), item));
    CHECK(!Matches(Cond(COND_ITEM_LEVEL, OP_AT_LEAST, 151), item));
    CHECK(Matches(Cond(COND_ITEM_LEVEL, OP_IS, 150), item));

    CHECK(Matches(Cond(COND_SELL_PRICE, OP_AT_LEAST, 9840), item));
    CHECK(!Matches(Cond(COND_SELL_PRICE, OP_AT_LEAST, 9841), item));

    CHECK(Matches(Cond(COND_ITEM_TYPE, OP_IS, 4, ANY_SUBCLASS), item));
    CHECK(Matches(Cond(COND_ITEM_TYPE, OP_IS, 4, 1), item));
    CHECK(!Matches(Cond(COND_ITEM_TYPE, OP_IS, 4, 2), item));
    CHECK(!Matches(Cond(COND_ITEM_TYPE, OP_IS, 2, ANY_SUBCLASS), item));

    CHECK(!Matches(Cond(COND_CURSED, OP_IS, 1), item));
    CHECK(Matches(Cond(COND_CURSED, OP_IS, 0), item));
    ItemFacts cursed = item;
    cursed.cursed = true;
    CHECK(Matches(Cond(COND_CURSED, OP_IS, 1), cursed));

    CHECK(Matches(Cond(COND_ITEM, OP_IS, 1001), item));
    CHECK(!Matches(Cond(COND_ITEM, OP_IS, 1002), item));

    CHECK(Matches(Cond(COND_NAME, OP_IS, 0, 0, "silk HOOD"), item));
    CHECK(!Matches(Cond(COND_NAME, OP_IS, 0, 0, "Plate"), item));
    CHECK(!Matches(Cond(COND_NAME, OP_IS, 0, 0, ""), item));
}

static void TestEvaluate()
{
    std::vector<Rule> rules;
    rules.push_back(MakeRule(11, ACTION_KEEP, { Cond(COND_CURSED, OP_IS, 1) }));
    rules.push_back(MakeRule(12, ACTION_SELL, { Cond(COND_QUALITY, OP_IS, 0) }));
    rules.push_back(MakeRule(13, ACTION_DISENCHANT, {
        Cond(COND_QUALITY, OP_IS, 2), Cond(COND_ITEM_LEVEL, OP_AT_MOST, 150) }));
    rules.push_back(MakeRule(14, ACTION_DELETE,
        { Cond(COND_ITEM_LEVEL, OP_AT_MOST, 200) }));
    Renumber(rules);

    uint8 const all = AllowedMask(true, true, true);
    ItemFacts const item = Hood();

    Verdict v = Evaluate(rules, item, all);
    CHECK(v.result == ACTION_DISENCHANT);
    CHECK(v.position == 3);

    rules[2].enabled = false;
    v = Evaluate(rules, item, all);
    CHECK(v.result == ACTION_DELETE);
    CHECK(v.position == 4);
    rules[2].enabled = true;

    v = Evaluate(rules, item, AllowedMask(true, false, true));
    CHECK(v.result == ACTION_DELETE);
    CHECK(v.position == 4);

    v = Evaluate(rules, item, AllowedMask(false, false, false));
    CHECK(v.result == RESULT_NO_RULE);
    CHECK(v.position == 0);

    ItemFacts quest = item;
    quest.questItem = true;
    v = Evaluate(rules, quest, all);
    CHECK(v.result == RESULT_PROTECTED);
    CHECK(v.position == 0);

    ItemFacts big = item;
    big.quality = 3;
    big.itemLevel = 300;
    v = Evaluate(rules, big, all);
    CHECK(v.result == RESULT_NO_RULE);

    CHECK(Evaluate(std::vector<Rule>(), item, all).result == RESULT_NO_RULE);

    std::vector<Rule> empty;
    empty.push_back(MakeRule(20, ACTION_DELETE, {}));
    Renumber(empty);
    CHECK(Evaluate(empty, item, all).result == RESULT_NO_RULE);

    CHECK(AllowedMask(false, false, false)
        == ((1u << ACTION_KEEP) | (1u << ACTION_STORE)));
}

static void TestValidation()
{
    CHECK(ValidCondition(Cond(COND_QUALITY, OP_AT_MOST, 7)));
    CHECK(!ValidCondition(Cond(COND_QUALITY, OP_IS, 8)));
    CHECK(!ValidCondition(Cond(COND_QUALITY, 3, 1)));
    CHECK(ValidCondition(Cond(COND_ITEM_LEVEL, OP_AT_LEAST, 65535)));
    CHECK(!ValidCondition(Cond(COND_ITEM_LEVEL, OP_AT_LEAST, 65536)));
    CHECK(ValidCondition(Cond(COND_SELL_PRICE, OP_AT_LEAST, 4294967295u)));
    CHECK(ValidCondition(Cond(COND_ITEM_TYPE, OP_IS, 16, ANY_SUBCLASS)));
    CHECK(ValidCondition(Cond(COND_ITEM_TYPE, OP_IS, 4, 31)));
    CHECK(!ValidCondition(Cond(COND_ITEM_TYPE, OP_IS, 17, ANY_SUBCLASS)));
    CHECK(!ValidCondition(Cond(COND_ITEM_TYPE, OP_IS, 4, 32)));
    CHECK(!ValidCondition(Cond(COND_ITEM_TYPE, OP_AT_LEAST, 4, 1)));
    CHECK(ValidCondition(Cond(COND_CURSED, OP_IS, 1)));
    CHECK(!ValidCondition(Cond(COND_CURSED, OP_IS, 2)));
    CHECK(ValidCondition(Cond(COND_ITEM, OP_IS, 1)));
    CHECK(!ValidCondition(Cond(COND_ITEM, OP_IS, 0)));
    CHECK(!ValidCondition(Cond(COND_ITEM, OP_AT_MOST, 5)));
    CHECK(ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, "Frozen Orb's -.,")));
    CHECK(!ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, "")));
    CHECK(!ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, std::string(41, 'a'))));
    CHECK(ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, std::string(40, 'a'))));
    CHECK(!ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, "Tome: Fire")));
    CHECK(!ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, "a|b")));
    CHECK(!ValidCondition(Cond(COND_NAME, OP_IS, 0, 0, "a;b")));
    CHECK(!ValidCondition(Cond(COND_NAME, OP_IS, 1, 0, "abc")));
    CHECK(!ValidCondition(Cond(COND_QUALITY, OP_IS, 1, 0, "x")));
    CHECK(!ValidCondition(Cond(COND_QUALITY, OP_IS, 1, 5)));
    CHECK(!ValidCondition(Cond(4, OP_IS, 1)));
    CHECK(!ValidCondition(Cond(8, OP_IS, 1)));

    Rule ok = MakeRule(1, ACTION_STORE, { Cond(COND_ITEM_TYPE, OP_IS, 7, 255) });
    CHECK(ValidRule(ok));
    Rule badAction = ok;
    badAction.action = 5;
    CHECK(!ValidRule(badAction));
    Rule none = ok;
    none.conditions.clear();
    CHECK(!ValidRule(none));
    Rule five = ok;
    five.conditions.assign(5, Cond(COND_QUALITY, OP_IS, 1));
    CHECK(!ValidRule(five));
}

static void TestCodec()
{
    uint32 n = 0;
    CHECK(ParseUInt("0", 10, n) && n == 0);
    CHECK(ParseUInt("4294967295", 4294967295u, n) && n == 4294967295u);
    CHECK(!ParseUInt("4294967296", 4294967295u, n));
    CHECK(!ParseUInt("11", 10, n));
    CHECK(!ParseUInt("", 10, n));
    CHECK(!ParseUInt("+1", 10, n));
    CHECK(!ParseUInt("-1", 10, n));
    CHECK(!ParseUInt("1a", 10, n));
    CHECK(!ParseUInt("00000000001", 4294967295u, n));

    std::vector<std::string> parts = Split("a|b||c", '|');
    CHECK(parts.size() == 4 && parts[2].empty() && parts[3] == "c");
    CHECK(Split("", '|').size() == 1);

    std::vector<Condition> conds = { Cond(COND_QUALITY, OP_AT_MOST, 2),
        Cond(COND_ITEM_LEVEL, OP_AT_MOST, 150) };
    CHECK(EncodeConditions(conds) == "0:2:2:0:;1:2:150:0:");

    Rule r = MakeRule(7, ACTION_DISENCHANT, conds);
    r.position = 3;
    CHECK(EncodeRule(r) == "7|3|2|1|0:2:2:0:;1:2:150:0:");

    Rule back;
    std::vector<std::string> f = Split("R|" + EncodeRule(r), '|');
    CHECK(DecodeRule(f, 1, back));
    CHECK(back.id == 7 && back.position == 3 && back.action == ACTION_DISENCHANT);
    CHECK(back.enabled && SameConds(back.conditions, conds));

    std::vector<Condition> four = { Cond(COND_NAME, OP_IS, 0, 0, "silk hood"),
        Cond(COND_ITEM_TYPE, OP_IS, 4, 255), Cond(COND_CURSED, OP_IS, 0),
        Cond(COND_SELL_PRICE, OP_AT_LEAST, 100) };
    std::vector<Condition> four2;
    CHECK(DecodeConditions(EncodeConditions(four), four2));
    CHECK(SameConds(four, four2));

    std::vector<Condition> out;
    CHECK(!DecodeConditions("", out));
    CHECK(!DecodeConditions("4:0:1:0:", out));
    CHECK(!DecodeConditions("9:0:1:0:", out));
    CHECK(!DecodeConditions("3:1:4:255:", out));
    CHECK(!DecodeConditions("7:0:0:0:a:b", out));
    CHECK(!DecodeConditions("7:0:0:0:a;b", out));
    CHECK(!DecodeConditions("7:0:0:0:", out));
    CHECK(!DecodeConditions("0:0:a:0:", out));
    CHECK(!DecodeConditions("0:0::0:", out));
    CHECK(!DecodeConditions("2:1:4294967296:0:", out));
    CHECK(!DecodeConditions("0:0:1:0", out));
    CHECK(!DecodeConditions(
        "0:0:1:0:;0:0:1:0:;0:0:1:0:;0:0:1:0:;0:0:1:0:", out));
    CHECK(DecodeConditions("0:0:1:0:;0:0:1:0:;0:0:1:0:;0:0:1:0:", out)
        && out.size() == 4);

    std::vector<std::string> bad = Split("R|7|3|5|1|0:0:1:0:", '|');
    CHECK(!DecodeRule(bad, 1, back));
    bad = Split("R|7|3|2|2|0:0:1:0:", '|');
    CHECK(!DecodeRule(bad, 1, back));
    bad = Split("R|7|3|2|1", '|');
    CHECK(!DecodeRule(bad, 1, back));

    // The longest legal rule still fits into one addon message.
    std::vector<Condition> longest(4, Cond(COND_NAME, OP_IS, 0, 0,
        std::string(40, 'w')));
    Rule big = MakeRule(4294967295u, ACTION_STORE, longest);
    big.position = 255;
    CHECK(std::string("LFLS\tR|" + EncodeRule(big)).size() <= MAX_MESSAGE);
}

static void TestOrdering()
{
    std::vector<Rule> rules;
    Insert(rules, MakeRule(1, ACTION_SELL, { Cond(COND_QUALITY, OP_IS, 0) }), 0);
    Insert(rules, MakeRule(2, ACTION_SELL, { Cond(COND_QUALITY, OP_IS, 1) }), 0);
    Insert(rules, MakeRule(3, ACTION_SELL, { Cond(COND_QUALITY, OP_IS, 2) }), 0);
    CHECK(rules.size() == 3 && rules[2].id == 3 && rules[2].position == 3);

    CHECK(Move(rules, 3, 1));
    CHECK(rules[0].id == 3 && rules[1].id == 1 && rules[2].id == 2);
    CHECK(rules[0].position == 1 && rules[2].position == 3);

    CHECK(Move(rules, 3, 9));
    CHECK(rules[2].id == 3 && rules[2].position == 3);

    CHECK(!Move(rules, 77, 1));

    Insert(rules, MakeRule(4, ACTION_KEEP, { Cond(COND_CURSED, OP_IS, 1) }), 2);
    CHECK(rules[1].id == 4 && rules[1].position == 2 && rules.size() == 4);

    CHECK(Remove(rules, 1));
    CHECK(!Remove(rules, 1));
    CHECK(rules.size() == 3 && rules[0].id == 4 && rules[0].position == 1);
    CHECK(rules[2].position == 3);

    std::vector<Rule> loaded;
    Rule a = MakeRule(9, ACTION_SELL, { Cond(COND_QUALITY, OP_IS, 0) });
    a.position = 5;
    Rule b = MakeRule(8, ACTION_SELL, { Cond(COND_QUALITY, OP_IS, 1) });
    b.position = 2;
    loaded.push_back(a);
    loaded.push_back(b);
    SortByPosition(loaded);
    CHECK(loaded[0].id == 8 && loaded[0].position == 1);
    CHECK(loaded[1].id == 9 && loaded[1].position == 2);
}

static void TestBags()
{
    uint8 bag = 0;
    uint8 slot = 0;
    CHECK(ClientToServer(0, 1, bag, slot) && bag == 255 && slot == 23);
    CHECK(ClientToServer(0, 16, bag, slot) && bag == 255 && slot == 38);
    CHECK(!ClientToServer(0, 0, bag, slot));
    CHECK(!ClientToServer(0, 17, bag, slot));
    CHECK(ClientToServer(1, 1, bag, slot) && bag == 19 && slot == 0);
    CHECK(ClientToServer(4, 36, bag, slot) && bag == 22 && slot == 35);
    CHECK(!ClientToServer(4, 37, bag, slot));
    CHECK(!ClientToServer(5, 1, bag, slot));

    uint32 cbag = 0;
    uint32 cslot = 0;
    CHECK(ServerToClient(255, 23, cbag, cslot) && cbag == 0 && cslot == 1);
    CHECK(ServerToClient(255, 38, cbag, cslot) && cbag == 0 && cslot == 16);
    CHECK(!ServerToClient(255, 22, cbag, cslot));
    CHECK(!ServerToClient(255, 39, cbag, cslot));
    CHECK(ServerToClient(19, 0, cbag, cslot) && cbag == 1 && cslot == 1);
    CHECK(ServerToClient(22, 35, cbag, cslot) && cbag == 4 && cslot == 36);
    CHECK(!ServerToClient(23, 0, cbag, cslot));
}

// The production host's 19 rules from the nightly dump of 2026-10-09,
// character ids replaced by 1-3 (rule data only, no names).
static std::vector<LegacyRow> HostRows()
{
    return {
        Row(1, 7, 0, 0, 0, 0, "", 1, 10, true),
        Row(1, 8, 0, 0, 0, 1, "", 1, 20, true),
        Row(1, 9, 0, 0, 0, 2, "", 2, 30, true),
        Row(1, 10, 0, 0, 0, 3, "", 2, 100, true),
        Row(1, 11, 1, 0, 0, 4, "", 0, 1, true),
        Row(1, 12, 1, 5, 0, 1, "", 0, 1, true),
        Row(1, 14, 2, 0, 0, 4, "", 2, 50, true),
        Row(1, 15, 2, 5, 0, 0, "", 2, 50, true),
        Row(1, 17, 4, 3, 0, 5, "", 0, 2, true),
        Row(1, 18, 4, 0, 0, 1, "", 0, 2, true),
        Row(1, 19, 0, 5, 0, 1, "", 0, 3, true),
        Row(1, 20, 0, 3, 0, 7, "", 0, 2, true),
        Row(1, 21, 2, 1, 2, 230, "", 2, 50, true),
        Row(2, 22, 0, 0, 0, 0, "", 1, 10, true),
        Row(2, 23, 0, 0, 0, 1, "", 1, 20, true),
        Row(2, 24, 0, 0, 0, 2, "", 2, 30, true),
        Row(2, 25, 0, 1, 0, 50, "", 3, 15, true),
        Row(2, 26, 0, 5, 0, 1, "", 0, 1, true),
        Row(3, 27, 0, 0, 0, 0, "", 1, 10, true),
    };
}

static bool Expect(Rule const& r, uint8 position, uint8 action, bool enabled,
    std::vector<Condition> const& conds)
{
    return r.position == position && r.action == action
        && r.enabled == enabled && r.id == 0 && SameConds(r.conditions, conds);
}

static void TestMigrationHost()
{
    std::vector<LegacyRow> const all = HostRows();

    MigrationResult m1 = MigrateCharacter(RowsOf(all, 1));
    CHECK(m1.rules.size() == 9 && m1.disabled == 0 && m1.dropped == 0);
    if (m1.rules.size() == 9)
    {
        CHECK(Expect(m1.rules[0], 1, ACTION_KEEP, true,
            { Cond(COND_QUALITY, OP_IS, 4), Cond(COND_CURSED, OP_IS, 1) }));
        CHECK(Expect(m1.rules[1], 2, ACTION_STORE, true,
            { Cond(COND_ITEM_TYPE, OP_IS, 7, ANY_SUBCLASS) }));
        CHECK(Expect(m1.rules[2], 3, ACTION_KEEP, true,
            { Cond(COND_ITEM_TYPE, OP_IS, 5, ANY_SUBCLASS),
              Cond(COND_QUALITY, OP_IS, 1) }));
        CHECK(Expect(m1.rules[3], 4, ACTION_KEEP, true,
            { Cond(COND_CURSED, OP_IS, 1) }));
        CHECK(Expect(m1.rules[4], 5, ACTION_SELL, true,
            { Cond(COND_QUALITY, OP_IS, 0) }));
        CHECK(Expect(m1.rules[5], 6, ACTION_SELL, true,
            { Cond(COND_QUALITY, OP_IS, 1) }));
        CHECK(Expect(m1.rules[6], 7, ACTION_DISENCHANT, true,
            { Cond(COND_QUALITY, OP_IS, 2) }));
        CHECK(Expect(m1.rules[7], 8, ACTION_DISENCHANT, true,
            { Cond(COND_QUALITY, OP_IS, 4), Cond(COND_CURSED, OP_IS, 0),
              Cond(COND_ITEM_LEVEL, OP_AT_MOST, 229) }));
        CHECK(Expect(m1.rules[8], 9, ACTION_DISENCHANT, true,
            { Cond(COND_QUALITY, OP_IS, 3) }));
    }

    MigrationResult m2 = MigrateCharacter(RowsOf(all, 2));
    CHECK(m2.rules.size() == 5 && m2.disabled == 1 && m2.dropped == 0);
    if (m2.rules.size() == 5)
    {
        CHECK(Expect(m2.rules[0], 1, ACTION_KEEP, true,
            { Cond(COND_CURSED, OP_IS, 1) }));
        CHECK(Expect(m2.rules[1], 2, ACTION_SELL, true,
            { Cond(COND_QUALITY, OP_IS, 0) }));
        // Saved by the March UI as "Item Level below 50", evaluated as
        // "equals 50": kept as it behaves today, but switched off.
        CHECK(Expect(m2.rules[2], 3, ACTION_DELETE, false,
            { Cond(COND_ITEM_LEVEL, OP_IS, 50) }));
        CHECK(Expect(m2.rules[3], 4, ACTION_SELL, true,
            { Cond(COND_QUALITY, OP_IS, 1) }));
        CHECK(Expect(m2.rules[4], 5, ACTION_DISENCHANT, true,
            { Cond(COND_QUALITY, OP_IS, 2) }));
    }

    MigrationResult m3 = MigrateCharacter(RowsOf(all, 3));
    CHECK(m3.rules.size() == 1 && m3.disabled == 0);
    if (m3.rules.size() == 1)
        CHECK(Expect(m3.rules[0], 1, ACTION_SELL, true,
            { Cond(COND_QUALITY, OP_IS, 0) }));

    for (MigrationResult const* m : { &m1, &m2, &m3 })
        for (Rule const& r : m->rules)
            CHECK(ValidRule(r));
}

static void TestMigrationEdges()
{
    // "< 0" matched nothing: disabled.
    MigrationResult m = MigrateCharacter({ Row(9, 1, 0, 0, 2, 0, "", 3, 5, true) });
    CHECK(m.rules.size() == 1 && !m.rules[0].enabled && m.disabled == 1);

    // A KEEP saved by the March UI with '=' stays on (switching it off
    // would widen the rules below it); a SELL with '=' is switched off.
    m = MigrateCharacter({ Row(9, 1, 0, 1, 0, 50, "", 0, 5, true),
        Row(9, 2, 0, 2, 0, 100, "", 1, 6, true) });
    CHECK(m.rules.size() == 2 && m.rules[0].enabled && !m.rules[1].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_ITEM_LEVEL, OP_IS, 50) }));
    CHECK(m.disabled == 1);

    // "> v" becomes "at least v+1"; "< v" becomes "at most v-1".
    m = MigrateCharacter({ Row(9, 1, 0, 2, 1, 999, "", 3, 5, true),
        Row(9, 2, 0, 0, 2, 3, "", 1, 6, true) });
    CHECK(m.rules.size() == 2 && m.rules[0].enabled && m.rules[1].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_SELL_PRICE, OP_AT_LEAST, 1000) }));
    CHECK(SameConds(m.rules[1].conditions, { Cond(COND_QUALITY, OP_AT_MOST, 2) }));

    // Class row + subclass row merge into one item-type condition.
    m = MigrateCharacter({ Row(9, 30, 3, 3, 0, 4, "", 1, 5, true),
        Row(9, 31, 3, 4, 0, 1, "", 1, 5, true) });
    CHECK(m.rules.size() == 1 && m.rules[0].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_ITEM_TYPE, OP_IS, 4, 1) }));

    // A lone subclass row becomes weapon (if the old client named it a
    // weapon) or armor.
    m = MigrateCharacter({ Row(9, 1, 0, 4, 0, 3, "", 1, 5, true),
        Row(9, 2, 0, 4, 0, 9, "", 1, 6, true) });
    CHECK(m.rules.size() == 2);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_ITEM_TYPE, OP_IS, 2, 3) }));
    CHECK(SameConds(m.rules[1].conditions, { Cond(COND_ITEM_TYPE, OP_IS, 4, 9) }));

    // An operator on class cannot be expressed: disabled.
    m = MigrateCharacter({ Row(9, 1, 0, 3, 1, 2, "", 1, 5, true) });
    CHECK(m.rules.size() == 1 && !m.rules[0].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_ITEM_TYPE, OP_IS, 2, ANY_SUBCLASS) }));

    // Names: valid text stays; long or odd text is cleaned and disabled;
    // an empty name leaves no condition, and a rule without conditions is
    // dropped.
    m = MigrateCharacter({ Row(9, 1, 0, 7, 0, 0, "Frozen Orb", 0, 5, true) });
    CHECK(m.rules.size() == 1 && m.rules[0].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_NAME, OP_IS, 0, 0, "Frozen Orb") }));
    m = MigrateCharacter({ Row(9, 1, 0, 7, 0, 0, "Tome: Fire", 0, 5, true) });
    CHECK(m.rules.size() == 1 && !m.rules[0].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_NAME, OP_IS, 0, 0, "Tome Fire") }));
    m = MigrateCharacter({ Row(9, 1, 0, 7, 0, 0, std::string(50, 'x'), 0, 5, true) });
    CHECK(m.rules.size() == 1 && !m.rules[0].enabled);
    CHECK(m.rules[0].conditions.size() == 1
        && m.rules[0].conditions[0].text == std::string(40, 'x'));
    m = MigrateCharacter({ Row(9, 1, 0, 7, 0, 0, "", 3, 5, true) });
    CHECK(m.rules.empty() && m.dropped == 1);

    // KEEP on storable classes becomes TO STORAGE.
    m = MigrateCharacter({ Row(9, 1, 0, 3, 0, 3, "", 0, 5, true),
        Row(9, 2, 0, 3, 0, 0, "", 0, 6, true),
        Row(9, 3, 0, 3, 0, 9, "", 0, 7, true),
        Row(9, 4, 0, 3, 0, 2, "", 0, 8, true) });
    CHECK(m.rules.size() == 4);
    if (m.rules.size() == 4)
    {
        CHECK(m.rules[0].action == ACTION_STORE);
        CHECK(m.rules[1].action == ACTION_STORE);
        CHECK(m.rules[2].action == ACTION_STORE);
        CHECK(m.rules[3].action == ACTION_KEEP);
    }

    // More than four conditions: first four by priority, disabled.
    m = MigrateCharacter({ Row(9, 1, 5, 0, 0, 2, "", 1, 9, true),
        Row(9, 2, 5, 5, 0, 0, "", 1, 4, true),
        Row(9, 3, 5, 6, 0, 77, "", 1, 5, true),
        Row(9, 4, 5, 1, 1, 10, "", 1, 6, true),
        Row(9, 5, 5, 2, 2, 50, "", 1, 7, true) });
    CHECK(m.rules.size() == 1 && !m.rules[0].enabled);
    CHECK(SameConds(m.rules[0].conditions, { Cond(COND_CURSED, OP_IS, 0),
        Cond(COND_ITEM, OP_IS, 77), Cond(COND_ITEM_LEVEL, OP_AT_LEAST, 11),
        Cond(COND_SELL_PRICE, OP_AT_MOST, 49) }));

    // A group whose rows are all off stays off with every condition; a
    // partly-off group keeps only the rows the old core evaluated.
    m = MigrateCharacter({ Row(9, 1, 6, 0, 0, 2, "", 2, 5, false),
        Row(9, 2, 6, 5, 0, 0, "", 2, 6, false),
        Row(9, 3, 7, 0, 0, 3, "", 1, 7, true),
        Row(9, 4, 7, 5, 0, 1, "", 1, 8, false) });
    CHECK(m.rules.size() == 2);
    if (m.rules.size() == 2)
    {
        CHECK(!m.rules[0].enabled && m.rules[0].conditions.size() == 2);
        CHECK(m.rules[1].enabled);
        CHECK(SameConds(m.rules[1].conditions, { Cond(COND_QUALITY, OP_IS, 3) }));
    }

    // Unknown type: condition dropped, rule disabled; corrupt action:
    // rule dropped; item id with an operator or id 0 cannot be expressed.
    m = MigrateCharacter({ Row(9, 1, 8, 0, 0, 2, "", 1, 5, true),
        Row(9, 2, 8, 8, 0, 5, "", 1, 5, true),
        Row(9, 3, 0, 0, 0, 1, "", 7, 6, true),
        Row(9, 4, 0, 6, 1, 500, "", 3, 7, true),
        Row(9, 5, 0, 6, 0, 0, "", 3, 8, true) });
    CHECK(m.rules.size() == 2 && m.dropped == 2);
    if (m.rules.size() == 2)
    {
        CHECK(!m.rules[0].enabled
            && SameConds(m.rules[0].conditions, { Cond(COND_QUALITY, OP_IS, 2) }));
        CHECK(!m.rules[1].enabled
            && SameConds(m.rules[1].conditions, { Cond(COND_ITEM, OP_IS, 500) }));
    }

    // Order: priority, then standalone before group, then lowest rule id.
    m = MigrateCharacter({ Row(9, 5, 2, 0, 0, 4, "", 1, 3, true),
        Row(9, 6, 0, 0, 0, 3, "", 1, 3, true),
        Row(9, 2, 0, 0, 0, 2, "", 1, 3, true),
        Row(9, 1, 0, 0, 0, 1, "", 1, 9, true) });
    CHECK(m.rules.size() == 4);
    if (m.rules.size() == 4)
    {
        CHECK(m.rules[0].conditions[0].value == 2);
        CHECK(m.rules[1].conditions[0].value == 3);
        CHECK(m.rules[2].conditions[0].value == 4);
        CHECK(m.rules[3].conditions[0].value == 1);
    }
}

int main()
{
    TestMatching();
    TestEvaluate();
    TestValidation();
    TestCodec();
    TestOrdering();
    TestBags();
    TestMigrationHost();
    TestMigrationEdges();

    if (g_failures)
    {
        std::printf("rules_test: %d of %d checks FAILED\n", g_failures, g_checks);
        return 1;
    }
    std::printf("rules_test: all %d checks passed\n", g_checks);
    return 0;
}
