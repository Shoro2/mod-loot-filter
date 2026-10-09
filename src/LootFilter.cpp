/*
 * mod-loot-filter — core glue
 *
 * Owns the per-character rules (cache + the only writer of the tables),
 * filters looted items one tick after the loot hook, executes the action,
 * keeps statistics, and serves the window over addon messages: the client
 * whispers itself "LFLT\t<payload>", the answers go out with prefix "LFLS".
 * The rule model, codec and migration are in LootFilterRules.h.
 */

#include "LootFilter.h"
#include "LootFilterRules.h"
#include "Bag.h"
#include "Chat.h"
#include "CommandScript.h"
#include "Config.h"
#include "DBCStores.h"
#include "DatabaseEnv.h"
#include "EventProcessor.h"
#include "Item.h"
#include "Log.h"
#include "LootMgr.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "StringFormat.h"
#include "Timer.h"
#include "World.h"
#include "WorldPacket.h"
#include "WorldSession.h"
#include <algorithm>
#include <atomic>
#include <map>
#include <mutex>
#include <unordered_map>
#include <utility>
#include <vector>

using namespace Acore::ChatCommands;
namespace LFR = LootFilterRules;

namespace
{
    // ------------------------------------------------------------
    // Configuration
    // ------------------------------------------------------------

    bool conf_Enable = true;
    bool conf_AllowSell = true;
    bool conf_AllowDisenchant = true;
    bool conf_AllowDelete = true;
    bool conf_LogActions = true;
    uint32 conf_MaxRulesPerChar = 30;

    constexpr char const* PREFIX_IN = "LFLT\t";
    constexpr std::size_t PREFIX_IN_LEN = 5;
    constexpr char const* PREFIX_OUT = "LFLS";
    constexpr char const* CHAT_TAG = "|cff888888[Loot Filter]|r ";
    constexpr uint32 TOKEN_BURST = 20;
    constexpr uint32 TOKEN_REFILL_MS = 100;
    constexpr uint32 SCAN_INTERVAL_MS = 2000;

    uint8 AllowedMask()
    {
        return LFR::AllowedMask(conf_AllowSell, conf_AllowDisenchant,
            conf_AllowDelete);
    }

    // ------------------------------------------------------------
    // Per-character state
    // ------------------------------------------------------------

    // What happened since the last flush: the statistics delta written to
    // the DB and, in summary mode, the chat line.
    struct FilterBatch
    {
        uint32 soldItems = 0;
        uint64 money = 0;
        uint32 disenchanted = 0;
        uint32 stored = 0;
        uint32 deleted = 0;
        bool pending = false;

        bool Empty() const
        {
            return !soldItems && !disenchanted && !stored && !deleted;
        }
    };

    struct FilterState
    {
        bool filterEnabled = true;
        uint8 chatMode = LFR::CHAT_SUMMARY;
        uint64 totalSold = 0;
        uint32 totalDisenchanted = 0;
        uint32 totalDeleted = 0;
        uint32 totalStored = 0;
        std::vector<LFR::Rule> rules;   // evaluation order
        uint32 tokens = TOKEN_BURST;
        uint32 lastRefill = 0;
        uint32 lastScan = 0;
        bool scanned = false;
        FilterBatch batch;
    };

    std::mutex s_mutex;
    std::unordered_map<uint32, FilterState> s_states;
    std::atomic<uint32> s_nextRuleId{ 1 };

    // ------------------------------------------------------------
    // Item helpers
    // ------------------------------------------------------------

    // Paragon cursed items carry enchant 920001 or a passive 950001-950099
    // in slot 11 (PROP_ENCHANTMENT_SLOT_4), set by mod-paragon-itemgen.
    bool IsParagonCursedItem(Item const* item)
    {
        uint32 const enchId =
            item->GetEnchantmentId(static_cast<EnchantmentSlot>(11));
        return enchId == 920001 || (enchId >= 950001 && enchId <= 950099);
    }

    bool IsQuestItem(ItemTemplate const* proto)
    {
        return proto->Class == ITEM_CLASS_QUEST
            || proto->Bonding == BIND_QUEST_ITEM
            || proto->Bonding == BIND_QUEST_ITEM1
            || proto->StartQuest != 0;
    }

    LFR::ItemFacts Facts(Item const* item, ItemTemplate const* proto)
    {
        LFR::ItemFacts f;
        f.entry = proto->ItemId;
        f.quality = proto->Quality;
        f.itemLevel = proto->ItemLevel;
        f.sellPrice = proto->SellPrice;
        f.itemClass = proto->Class;
        f.subClass = proto->SubClass;
        f.cursed = IsParagonCursedItem(item);
        f.questItem = IsQuestItem(proto);
        f.name = proto->Name1;
        return f;
    }

    // Same predicate as mod-endless-storage: recipes, stackable food,
    // stackable trade goods and gems.
    bool IsStorageEligible(ItemTemplate const* proto)
    {
        if (proto->Class == ITEM_CLASS_RECIPE)
            return true;
        if (proto->Class == ITEM_CLASS_CONSUMABLE && proto->SubClass == 5
            && proto->GetMaxStackSize() > 1)
            return true;
        if ((proto->Class == ITEM_CLASS_TRADE_GOODS
            || proto->Class == ITEM_CLASS_GEM)
            && proto->GetMaxStackSize() > 1)
            return true;
        return false;
    }

    void DepositToStorage(uint32 guid, ItemTemplate const* proto, uint32 count)
    {
        CharacterDatabase.Execute(
            "INSERT INTO custom_endless_storage "
            "(character_id, item_entry, item_class, item_subclass, amount) "
            "VALUES ({}, {}, {}, {}, {}) "
            "ON DUPLICATE KEY UPDATE amount = amount + {}",
            guid, proto->ItemId, proto->Class, proto->SubClass, count, count);
    }

    std::string FormatMoney(uint64 copper)
    {
        uint64 const gold = copper / 10000;
        uint64 const silver = (copper % 10000) / 100;
        std::string result;
        if (gold > 0)
            result += std::to_string(gold) + "g ";
        if (silver > 0 || gold > 0)
            result += std::to_string(silver) + "s ";
        result += std::to_string(copper % 100) + "c";
        return result;
    }

    std::string ItemLink(ItemTemplate const* proto, int32 randomProperty)
    {
        std::string name = proto->Name1;
        char const* suffix = nullptr;
        uint8 const locale = sWorld->GetDefaultDbcLocale();
        if (randomProperty > 0)
        {
            if (ItemRandomPropertiesEntry const* e =
                sItemRandomPropertiesStore.LookupEntry(
                    static_cast<uint32>(randomProperty)))
                suffix = e->Name[locale];
        }
        else if (randomProperty < 0)
        {
            if (ItemRandomSuffixEntry const* e =
                sItemRandomSuffixStore.LookupEntry(
                    static_cast<uint32>(-randomProperty)))
                suffix = e->Name[locale];
        }
        if (suffix && *suffix)
            name += std::string(" ") + suffix;

        uint32 const color = proto->Quality < MAX_ITEM_QUALITY
            ? ItemQualityColors[proto->Quality] : 0xffffffff;
        return Acore::StringFormat("|c{:08x}|Hitem:{}:0:0:0:0:0:{}:0:0|h[{}]|h|r",
            color, proto->ItemId, randomProperty, name);
    }

    std::string CountSuffix(uint32 count)
    {
        return count > 1 ? " x" + std::to_string(count) : std::string();
    }

    // ------------------------------------------------------------
    // Addon messages to the window
    // ------------------------------------------------------------

    void SendAddon(Player* player, std::string const& message)
    {
        if (!player || !player->GetSession())
            return;
        std::string const full = std::string(PREFIX_OUT) + "\t" + message;
        WorldPacket data(SMSG_MESSAGECHAT, full.size() + 32);
        data << uint8(CHAT_MSG_WHISPER) << int32(LANG_ADDON);
        data << player->GetGUID() << uint32(0) << player->GetGUID();
        data << uint32(full.size() + 1) << full << uint8(0);
        player->GetSession()->SendPacket(&data);
    }

    // Where the answers to one request go: the window, and with `echo` also
    // the chat of the command that made it (.lootfilter request).
    struct Reply
    {
        Player* player;
        ChatHandler* echo;

        void operator()(std::string const& message) const
        {
            SendAddon(player, message);
            if (echo)
                echo->SendSysMessage("LFLS " + message);
        }
    };

    void SendSettings(Reply const& out, FilterState const& st)
    {
        out(Acore::StringFormat("I|{}|{}|{}|{}|{}|{}|{}|{}|{}|{}",
            st.filterEnabled ? 1 : 0, st.chatMode, conf_MaxRulesPerChar,
            conf_AllowSell ? 1 : 0, conf_AllowDisenchant ? 1 : 0,
            conf_AllowDelete ? 1 : 0, st.totalSold, st.totalDisenchanted,
            st.totalDeleted, st.totalStored));
    }

    void SendRules(Reply const& out, FilterState const& st)
    {
        for (LFR::Rule const& rule : st.rules)
            out("R|" + LFR::EncodeRule(rule));
        out("N|" + std::to_string(st.rules.size()));
    }

    // ------------------------------------------------------------
    // Database
    // ------------------------------------------------------------

    // Every rule change rewrites the character's whole rule set in one
    // transaction: at most 30 rules of 4 conditions, and the cache stays the
    // single source of truth.
    void SaveRules(uint32 guid, std::vector<LFR::Rule> const& rules)
    {
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        trans->Append(
            "DELETE c FROM character_loot_filter_condition AS c "
            "INNER JOIN character_loot_filter_rule AS r ON r.ruleId = c.ruleId "
            "WHERE r.characterId = {}", guid);
        trans->Append(
            "DELETE FROM character_loot_filter_rule WHERE characterId = {}",
            guid);
        for (LFR::Rule const& rule : rules)
        {
            trans->Append(
                "INSERT INTO character_loot_filter_rule "
                "(ruleId, characterId, position, action, enabled) "
                "VALUES ({}, {}, {}, {}, {})",
                rule.id, guid, rule.position, rule.action,
                rule.enabled ? 1 : 0);
            for (std::size_t i = 0; i < rule.conditions.size(); ++i)
            {
                LFR::Condition const& c = rule.conditions[i];
                std::string text = c.text;
                CharacterDatabase.EscapeString(text);
                trans->Append(
                    "INSERT INTO character_loot_filter_condition "
                    "(ruleId, slot, type, op, value, value2, text) "
                    "VALUES ({}, {}, {}, {}, {}, {}, '{}')",
                    rule.id, i, c.type, c.op, c.value, c.value2, text);
            }
        }
        CharacterDatabase.CommitTransaction(trans);
    }

    void SaveSettings(uint32 guid, FilterState const& st)
    {
        CharacterDatabase.Execute(
            "UPDATE character_loot_filter_settings SET filterEnabled = {}, "
            "chatMode = {} WHERE characterId = {}",
            st.filterEnabled ? 1 : 0, st.chatMode, guid);
    }

    void FlushBatch(uint32 guid, FilterBatch const& b)
    {
        if (b.Empty())
            return;
        CharacterDatabase.Execute(
            "UPDATE character_loot_filter_settings SET "
            "totalSold = totalSold + {}, "
            "totalDisenchanted = totalDisenchanted + {}, "
            "totalDeleted = totalDeleted + {}, "
            "totalStored = totalStored + {} WHERE characterId = {}",
            b.money, b.disenchanted, b.deleted, b.stored, guid);
    }

    FilterState LoadState(uint32 guid)
    {
        FilterState st;
        if (QueryResult result = CharacterDatabase.Query(
            "SELECT filterEnabled, chatMode, totalSold, totalDisenchanted, "
            "totalDeleted, totalStored FROM character_loot_filter_settings "
            "WHERE characterId = {}", guid))
        {
            Field* f = result->Fetch();
            st.filterEnabled = f[0].Get<uint8>() != 0;
            st.chatMode = std::min<uint8>(f[1].Get<uint8>(),
                static_cast<uint8>(LFR::CHAT_MODE_COUNT - 1));
            st.totalSold = f[2].Get<uint64>();
            st.totalDisenchanted = f[3].Get<uint32>();
            st.totalDeleted = f[4].Get<uint32>();
            st.totalStored = f[5].Get<uint32>();
        }
        else
            CharacterDatabase.Execute(
                "INSERT IGNORE INTO character_loot_filter_settings "
                "(characterId) VALUES ({})", guid);

        if (QueryResult result = CharacterDatabase.Query(
            "SELECT r.ruleId, r.position, r.action, r.enabled, c.slot, c.type, "
            "c.op, c.value, c.value2, c.text "
            "FROM character_loot_filter_rule AS r "
            "LEFT JOIN character_loot_filter_condition AS c "
            "ON c.ruleId = r.ruleId WHERE r.characterId = {} "
            "ORDER BY r.position, r.ruleId, c.slot", guid))
        {
            do
            {
                Field* f = result->Fetch();
                uint32 const ruleId = f[0].Get<uint32>();
                if (st.rules.empty() || st.rules.back().id != ruleId)
                {
                    LFR::Rule rule;
                    rule.id = ruleId;
                    rule.position = f[1].Get<uint8>();
                    rule.action = f[2].Get<uint8>();
                    rule.enabled = f[3].Get<uint8>() != 0;
                    st.rules.push_back(std::move(rule));
                }
                if (f[4].IsNull())
                    continue;
                LFR::Condition c;
                c.type = f[5].Get<uint8>();
                c.op = f[6].Get<uint8>();
                c.value = f[7].Get<uint32>();
                c.value2 = f[8].Get<uint32>();
                c.text = f[9].Get<std::string>();
                st.rules.back().conditions.push_back(std::move(c));
            } while (result->NextRow());
        }

        std::size_t const before = st.rules.size();
        st.rules.erase(std::remove_if(st.rules.begin(), st.rules.end(),
            [](LFR::Rule const& r) { return !LFR::ValidRule(r); }),
            st.rules.end());
        if (st.rules.size() != before)
            LOG_WARN("module", "mod-loot-filter: character {} has {} invalid "
                "rule(s) in the DB; they are ignored until the next save",
                guid, before - st.rules.size());
        LFR::SortByPosition(st.rules);
        return st;
    }

    // ------------------------------------------------------------
    // Startup: migrate the old one-condition table once
    // ------------------------------------------------------------

    bool TableExists(char const* table)
    {
        return CharacterDatabase.Query(
            "SELECT 1 FROM information_schema.TABLES WHERE TABLE_SCHEMA = "
            "DATABASE() AND TABLE_NAME = '{}'", table) != nullptr;
    }

    void MigrateLegacyTable()
    {
        if (!TableExists("character_loot_filter"))
            return;

        if (TableExists("character_loot_filter_legacy"))
        {
            LOG_ERROR("module", "mod-loot-filter: both character_loot_filter "
                "and character_loot_filter_legacy exist; nothing migrated - "
                "check and drop one of them by hand");
            return;
        }

        if (CharacterDatabase.Query(
            "SELECT 1 FROM character_loot_filter_rule LIMIT 1"))
        {
            LOG_WARN("module", "mod-loot-filter: character_loot_filter_rule "
                "already holds rules; the old table is only renamed");
            CharacterDatabase.DirectExecute("RENAME TABLE "
                "character_loot_filter TO character_loot_filter_legacy");
            return;
        }

        bool const hasOp = CharacterDatabase.Query(
            "SELECT 1 FROM information_schema.COLUMNS WHERE TABLE_SCHEMA = "
            "DATABASE() AND TABLE_NAME = 'character_loot_filter' "
            "AND COLUMN_NAME = 'conditionOp'") != nullptr;

        std::map<uint32, std::vector<LFR::LegacyRow>> perCharacter;
        if (QueryResult result = CharacterDatabase.Query(Acore::StringFormat(
            "SELECT characterId, ruleId, ruleGroup, conditionType, {}, "
            "conditionValue, conditionStr, action, priority, enabled "
            "FROM character_loot_filter ORDER BY characterId, ruleId",
            hasOp ? "conditionOp" : "0")))
        {
            do
            {
                Field* f = result->Fetch();
                LFR::LegacyRow row;
                row.characterId = f[0].Get<uint32>();
                row.ruleId = f[1].Get<uint32>();
                row.ruleGroup = f[2].Get<uint32>();
                row.type = f[3].Get<uint8>();
                row.op = f[4].Get<uint8>();
                row.value = f[5].Get<uint32>();
                row.text = f[6].Get<std::string>();
                row.action = f[7].Get<uint8>();
                row.priority = f[8].Get<uint8>();
                row.enabled = f[9].Get<uint8>() != 0;
                perCharacter[row.characterId].push_back(std::move(row));
            } while (result->NextRow());
        }

        uint32 nextId = 1;
        uint32 rules = 0;
        uint32 disabled = 0;
        uint32 dropped = 0;
        CharacterDatabaseTransaction trans = CharacterDatabase.BeginTransaction();
        for (auto const& [characterId, rows] : perCharacter)
        {
            LFR::MigrationResult migrated = LFR::MigrateCharacter(rows);
            disabled += migrated.disabled;
            dropped += migrated.dropped;
            for (LFR::Rule& rule : migrated.rules)
            {
                rule.id = nextId++;
                ++rules;
                trans->Append(
                    "INSERT INTO character_loot_filter_rule "
                    "(ruleId, characterId, position, action, enabled) "
                    "VALUES ({}, {}, {}, {}, {})",
                    rule.id, characterId, rule.position, rule.action,
                    rule.enabled ? 1 : 0);
                for (std::size_t i = 0; i < rule.conditions.size(); ++i)
                {
                    LFR::Condition const& c = rule.conditions[i];
                    std::string text = c.text;
                    CharacterDatabase.EscapeString(text);
                    trans->Append(
                        "INSERT INTO character_loot_filter_condition "
                        "(ruleId, slot, type, op, value, value2, text) "
                        "VALUES ({}, {}, {}, {}, {}, {}, '{}')",
                        rule.id, i, c.type, c.op, c.value, c.value2, text);
                }
            }
        }
        CharacterDatabase.DirectCommitTransaction(trans);
        CharacterDatabase.DirectExecute("RENAME TABLE character_loot_filter "
            "TO character_loot_filter_legacy");

        LOG_INFO("module", "mod-loot-filter: migrated {} rule(s) of {} "
            "character(s) to the new tables ({} switched off for review, {} "
            "dropped); the old table is now character_loot_filter_legacy",
            rules, perCharacter.size(), disabled, dropped);
    }

    // ------------------------------------------------------------
    // Actions
    // ------------------------------------------------------------

    std::vector<std::pair<uint32, uint32>> Disenchant(Player* player,
        ItemTemplate const* proto)
    {
        std::vector<std::pair<uint32, uint32>> mats;
        Loot loot;
        loot.FillLoot(proto->DisenchantID, LootTemplates_Disenchant, player,
            true);

        uint32 const guid = player->GetGUID().GetCounter();
        for (LootItem const& lootItem : loot.items)
        {
            ItemTemplate const* matProto =
                sObjectMgr->GetItemTemplate(lootItem.itemid);
            if (!matProto)
                continue;
            mats.emplace_back(lootItem.itemid, lootItem.count);
            if (IsStorageEligible(matProto))
            {
                DepositToStorage(guid, matProto, lootItem.count);
                continue;
            }
            ItemPosCountVec dest;
            if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT, dest,
                lootItem.itemid, lootItem.count) == EQUIP_ERR_OK)
            {
                if (Item* newItem = player->StoreNewItem(dest, lootItem.itemid,
                    true))
                    player->SendNewItem(newItem, lootItem.count, true, false);
            }
            else
                player->SendItemRetrievalMail(lootItem.itemid, lootItem.count);
        }
        return mats;
    }

    struct LootFilterSummaryEvent : public BasicEvent
    {
        explicit LootFilterSummaryEvent(ObjectGuid playerGuid)
            : _playerGuid(playerGuid) { }

        bool Execute(uint64 /*time*/, uint32 /*diff*/) override
        {
            Player* player = ObjectAccessor::FindPlayer(_playerGuid);
            if (!player)
                return true;
            uint32 const guid = player->GetGUID().GetCounter();

            FilterBatch b;
            uint8 mode = LFR::CHAT_NONE;
            {
                std::lock_guard<std::mutex> lock(s_mutex);
                auto it = s_states.find(guid);
                if (it == s_states.end())
                    return true;
                b = it->second.batch;
                it->second.batch = FilterBatch();
                mode = it->second.chatMode;
            }

            FlushBatch(guid, b);
            if (!conf_LogActions || mode != LFR::CHAT_SUMMARY || b.Empty())
                return true;

            std::vector<std::string> parts;
            if (b.soldItems)
                parts.push_back("sold " + std::to_string(b.soldItems)
                    + " for " + FormatMoney(b.money));
            if (b.disenchanted)
                parts.push_back("disenchanted "
                    + std::to_string(b.disenchanted));
            if (b.stored)
                parts.push_back("stored " + std::to_string(b.stored));
            if (b.deleted)
                parts.push_back("deleted " + std::to_string(b.deleted));
            std::string line;
            for (std::size_t i = 0; i < parts.size(); ++i)
                line += (i ? ", " : "") + parts[i];
            line[0] = static_cast<char>(line[0] - 'a' + 'A');
            ChatHandler(player->GetSession()).SendSysMessage(
                std::string(CHAT_TAG) + line + ".");
            return true;
        }

        ObjectGuid _playerGuid;
    };

    // Statistics, the batch (DB delta + summary), the window's log line and
    // the per-action chat line.
    void Record(Player* player, uint8 outcome, ItemTemplate const* proto,
        int32 suffix, uint32 count, uint64 money, uint8 position,
        std::vector<std::pair<uint32, uint32>> const& mats,
        std::string const& link, char const* why)
    {
        uint32 const guid = player->GetGUID().GetCounter();
        uint8 mode = LFR::CHAT_NONE;
        bool schedule = false;
        {
            std::lock_guard<std::mutex> lock(s_mutex);
            auto it = s_states.find(guid);
            if (it != s_states.end())
            {
                FilterState& st = it->second;
                FilterBatch& b = st.batch;
                switch (outcome)
                {
                    case LFR::ACTION_SELL:
                        st.totalSold += money;
                        b.soldItems += count;
                        b.money += money;
                        break;
                    case LFR::ACTION_DISENCHANT:
                        ++st.totalDisenchanted;
                        ++b.disenchanted;
                        break;
                    case LFR::ACTION_DELETE:
                        st.totalDeleted += count;
                        b.deleted += count;
                        break;
                    case LFR::ACTION_STORE:
                        st.totalStored += count;
                        b.stored += count;
                        break;
                    default:
                        break;
                }
                if (!b.Empty() && !b.pending)
                {
                    b.pending = true;
                    schedule = true;
                }
                mode = st.chatMode;
            }
        }
        if (schedule)
            player->m_Events.AddEvent(
                new LootFilterSummaryEvent(player->GetGUID()),
                player->m_Events.CalculateTime(1));

        std::string matList;
        for (std::size_t i = 0; i < mats.size(); ++i)
            matList += (i ? "," : "") + std::to_string(mats[i].first) + ":"
                + std::to_string(mats[i].second);
        SendAddon(player, Acore::StringFormat("L|{}|{}|{}|{}|{}|{}|{}",
            outcome, proto->ItemId, suffix, count, money, position, matList));

        if (!conf_LogActions || mode != LFR::CHAT_EVERY)
            return;

        std::string line;
        switch (outcome)
        {
            case LFR::ACTION_SELL:
                line = "Sold " + link + CountSuffix(count) + " for "
                    + FormatMoney(money) + ".";
                break;
            case LFR::ACTION_DISENCHANT:
            {
                line = "Disenchanted " + link;
                for (std::size_t i = 0; i < mats.size(); ++i)
                {
                    ItemTemplate const* matProto =
                        sObjectMgr->GetItemTemplate(mats[i].first);
                    if (!matProto)
                        continue;
                    line += (i ? ", " : ": ") + ItemLink(matProto, 0)
                        + CountSuffix(mats[i].second);
                }
                line += ".";
                break;
            }
            case LFR::ACTION_DELETE:
                line = "Deleted " + link + CountSuffix(count) + ".";
                break;
            case LFR::ACTION_STORE:
                line = "Stored " + link + CountSuffix(count) + ".";
                break;
            default:
                line = "Kept " + link + CountSuffix(count)
                    + (why ? std::string(" (") + why + ")" : std::string())
                    + ".";
                break;
        }
        ChatHandler(player->GetSession()).SendSysMessage(
            std::string(CHAT_TAG) + line);
    }

    void Act(Player* player, Item* item, ItemTemplate const* proto,
        uint8 action, uint8 position)
    {
        uint32 const guid = player->GetGUID().GetCounter();
        uint32 const count = item->GetCount();
        int32 const suffix = item->GetItemRandomPropertyId();
        std::string const link = ItemLink(proto, suffix);
        uint8 outcome = action;
        uint64 money = 0;
        char const* why = nullptr;
        std::vector<std::pair<uint32, uint32>> mats;

        switch (action)
        {
            case LFR::ACTION_STORE:
                if (IsStorageEligible(proto))
                {
                    DepositToStorage(guid, proto, count);
                    player->DestroyItem(item->GetBagSlot(), item->GetSlot(),
                        true);
                }
                else
                {
                    outcome = LFR::ACTION_KEEP;
                    why = "cannot be stored";
                }
                break;
            case LFR::ACTION_SELL:
                money = uint64(proto->SellPrice) * count;
                if (!money)
                {
                    outcome = LFR::ACTION_KEEP;
                    why = "no vendor price";
                }
                else if (uint64(player->GetMoney()) + money > MAX_MONEY_AMOUNT)
                {
                    outcome = LFR::ACTION_KEEP;
                    why = "gold limit";
                    money = 0;
                }
                else
                {
                    player->ModifyMoney(static_cast<int32>(money));
                    player->DestroyItem(item->GetBagSlot(), item->GetSlot(),
                        true);
                }
                break;
            case LFR::ACTION_DISENCHANT:
                if (!proto->DisenchantID)
                {
                    outcome = LFR::ACTION_KEEP;
                    why = "cannot be disenchanted";
                }
                else
                {
                    mats = Disenchant(player, proto);
                    player->DestroyItem(item->GetBagSlot(), item->GetSlot(),
                        true);
                }
                break;
            case LFR::ACTION_DELETE:
                player->DestroyItem(item->GetBagSlot(), item->GetSlot(), true);
                break;
            default:
                outcome = LFR::ACTION_KEEP;
                break;
        }

        Record(player, outcome, proto, suffix, count, money, position, mats,
            link, why);
    }

    // Runs one tick after the loot hook, so mod-paragon-itemgen has set the
    // slot 11 enchant the cursed check reads.
    struct LootFilterEvent : public BasicEvent
    {
        LootFilterEvent(ObjectGuid playerGuid, ObjectGuid itemGuid)
            : _playerGuid(playerGuid), _itemGuid(itemGuid) { }

        bool Execute(uint64 /*time*/, uint32 /*diff*/) override
        {
            Player* player = ObjectAccessor::FindPlayer(_playerGuid);
            if (!player)
                return true;
            Item* item = player->GetItemByGuid(_itemGuid);
            if (!item)
                return true;
            ItemTemplate const* proto = item->GetTemplate();
            if (!proto)
                return true;

            LFR::Verdict verdict;
            {
                std::lock_guard<std::mutex> lock(s_mutex);
                auto it = s_states.find(player->GetGUID().GetCounter());
                if (it == s_states.end() || !it->second.filterEnabled)
                    return true;
                verdict = LFR::Evaluate(it->second.rules, Facts(item, proto),
                    AllowedMask());
            }
            if (verdict.result < LFR::ACTION_COUNT)
                Act(player, item, proto, verdict.result, verdict.position);
            return true;
        }

        ObjectGuid _playerGuid;
        ObjectGuid _itemGuid;
    };

    // ------------------------------------------------------------
    // Window requests
    // ------------------------------------------------------------

    bool TakeToken(FilterState& st)
    {
        uint32 const now = getMSTime();
        uint32 const refill = getMSTimeDiff(st.lastRefill, now)
            / TOKEN_REFILL_MS;
        if (refill)
        {
            st.tokens = std::min<uint32>(TOKEN_BURST, st.tokens + refill);
            st.lastRefill = now;
        }
        if (!st.tokens)
            return false;
        --st.tokens;
        return true;
    }

    LFR::Rule* FindRule(FilterState& st, uint32 id)
    {
        auto it = std::find_if(st.rules.begin(), st.rules.end(),
            [id](LFR::Rule const& r) { return r.id == id; });
        return it == st.rules.end() ? nullptr : &*it;
    }

    std::string VerdictText(FilterState const& st, Item const* item)
    {
        ItemTemplate const* proto = item->GetTemplate();
        if (!proto)
            return std::to_string(LFR::RESULT_NO_RULE) + "|0";
        LFR::Verdict const v = LFR::Evaluate(st.rules, Facts(item, proto),
            AllowedMask());
        return std::to_string(v.result) + "|" + std::to_string(v.position);
    }

    void ScanBags(Reply const& out, Player* player, FilterState const& st)
    {
        uint32 count = 0;
        auto report = [&](uint8 bag, uint8 slot, Item const* item)
        {
            uint32 cbag = 0;
            uint32 cslot = 0;
            if (!item || !LFR::ServerToClient(bag, slot, cbag, cslot))
                return;
            out(Acore::StringFormat("S|{}|{}|{}", cbag, cslot,
                VerdictText(st, item)));
            ++count;
        };

        for (uint8 slot = INVENTORY_SLOT_ITEM_START;
            slot < INVENTORY_SLOT_ITEM_END; ++slot)
            report(INVENTORY_SLOT_BAG_0, slot,
                player->GetItemByPos(INVENTORY_SLOT_BAG_0, slot));

        for (uint8 bagSlot = INVENTORY_SLOT_BAG_START;
            bagSlot < INVENTORY_SLOT_BAG_END; ++bagSlot)
        {
            Bag* bag = player->GetBagByPos(bagSlot);
            if (!bag)
                continue;
            for (uint32 i = 0; i < bag->GetBagSize(); ++i)
                report(bagSlot, static_cast<uint8>(i),
                    bag->GetItemByPos(static_cast<uint8>(i)));
        }
        out("Z|" + std::to_string(count));
    }

    void HandleRequest(Player* player, std::string const& payload,
        ChatHandler* echo = nullptr)
    {
        Reply const out{ player, echo };
        if (!conf_Enable)
        {
            out("!|disabled");
            return;
        }

        std::vector<std::string> const f = LFR::Split(payload, '|');
        if (f[0].size() != 1)
            return;
        char const cmd = f[0][0];
        uint32 const guid = player->GetGUID().GetCounter();

        std::lock_guard<std::mutex> lock(s_mutex);
        auto it = s_states.find(guid);
        if (it == s_states.end())
            return;
        FilterState& st = it->second;
        if (!TakeToken(st))
        {
            out("!|busy");
            return;
        }

        uint32 a = 0;
        uint32 b = 0;
        switch (cmd)
        {
            case 'G':
                SendSettings(out, st);
                SendRules(out, st);
                break;
            case 'R':
            {
                LFR::Rule rule;
                if (f.size() != 6 || !LFR::DecodeRule(f, 1, rule))
                {
                    out("!|invalid");
                    break;
                }
                if (!(AllowedMask() & (1u << rule.action)))
                {
                    out("!|action");
                    break;
                }
                uint32 const pos = rule.position;
                if (rule.id == 0)
                {
                    if (st.rules.size() >= conf_MaxRulesPerChar)
                    {
                        out("!|limit");
                        break;
                    }
                    rule.id = s_nextRuleId++;
                    LFR::Insert(st.rules, std::move(rule), pos);
                }
                else
                {
                    LFR::Rule* existing = FindRule(st, rule.id);
                    if (!existing)
                    {
                        out("!|notfound");
                        break;
                    }
                    existing->action = rule.action;
                    existing->enabled = rule.enabled;
                    existing->conditions = std::move(rule.conditions);
                    if (pos && pos != existing->position)
                        LFR::Move(st.rules, rule.id, pos);
                }
                SaveRules(guid, st.rules);
                SendRules(out, st);
                break;
            }
            case 'D':
                if (f.size() != 2 || !LFR::ParseUInt(f[1], 0xFFFFFFFFu, a)
                    || !LFR::Remove(st.rules, a))
                {
                    out("!|notfound");
                    break;
                }
                SaveRules(guid, st.rules);
                SendRules(out, st);
                break;
            case 'M':
                if (f.size() != 3 || !LFR::ParseUInt(f[1], 0xFFFFFFFFu, a)
                    || !LFR::ParseUInt(f[2], 255, b) || !b
                    || !LFR::Move(st.rules, a, b))
                {
                    out("!|notfound");
                    break;
                }
                SaveRules(guid, st.rules);
                SendRules(out, st);
                break;
            case 'E':
            {
                LFR::Rule* rule = nullptr;
                if (f.size() != 3 || !LFR::ParseUInt(f[1], 0xFFFFFFFFu, a)
                    || !LFR::ParseUInt(f[2], 1, b)
                    || !(rule = FindRule(st, a)))
                {
                    out("!|notfound");
                    break;
                }
                rule->enabled = b != 0;
                SaveRules(guid, st.rules);
                SendRules(out, st);
                break;
            }
            case 'F':
                if (f.size() != 2 || !LFR::ParseUInt(f[1], 1, a))
                    break;
                st.filterEnabled = a != 0;
                SaveSettings(guid, st);
                out(std::string("F|") + (a ? "1" : "0"));
                break;
            case 'C':
                if (f.size() != 2
                    || !LFR::ParseUInt(f[1], LFR::CHAT_MODE_COUNT - 1, a))
                    break;
                st.chatMode = static_cast<uint8>(a);
                SaveSettings(guid, st);
                SendSettings(out, st);
                break;
            case 'X':
                st.rules.clear();
                SaveRules(guid, st.rules);
                SendRules(out, st);
                break;
            case 'T':
            {
                uint8 bag = 0;
                uint8 slot = 0;
                Item* item = nullptr;
                if (f.size() != 3 || !LFR::ParseUInt(f[1], 4, a)
                    || !LFR::ParseUInt(f[2], 255, b)
                    || !LFR::ClientToServer(a, b, bag, slot)
                    || !(item = player->GetItemByPos(bag, slot)))
                {
                    out("!|noitem");
                    break;
                }
                out(Acore::StringFormat("T|{}|{}|{}", a, b,
                    VerdictText(st, item)));
                break;
            }
            case 'S':
            {
                uint32 const now = getMSTime();
                if (st.scanned
                    && getMSTimeDiff(st.lastScan, now) < SCAN_INTERVAL_MS)
                {
                    out("!|busy");
                    break;
                }
                st.scanned = true;
                st.lastScan = now;
                ScanBags(out, player, st);
                break;
            }
            default:
                break;
        }
    }
}

// ============================================================
// WorldScript — configuration and the startup migration
// ============================================================

class LootFilter_World : public WorldScript
{
public:
    LootFilter_World() : WorldScript("LootFilter_World",
        {
            WORLDHOOK_ON_AFTER_CONFIG_LOAD,
            WORLDHOOK_ON_STARTUP
        }) { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        conf_Enable = sConfigMgr->GetOption<bool>("LootFilter.Enable", true);
        conf_AllowSell = sConfigMgr->GetOption<bool>(
            "LootFilter.AllowSell", true);
        conf_AllowDisenchant = sConfigMgr->GetOption<bool>(
            "LootFilter.AllowDisenchant", true);
        conf_AllowDelete = sConfigMgr->GetOption<bool>(
            "LootFilter.AllowDelete", true);
        conf_LogActions = sConfigMgr->GetOption<bool>(
            "LootFilter.LogActions", true);
        conf_MaxRulesPerChar = std::clamp<uint32>(sConfigMgr->GetOption<uint32>(
            "LootFilter.MaxRulesPerChar", 30), 1, 100);
    }

    void OnStartup() override
    {
        MigrateLegacyTable();
        if (QueryResult result = CharacterDatabase.Query(
            "SELECT COALESCE(MAX(ruleId), 0) AS lastId "
            "FROM character_loot_filter_rule"))
            s_nextRuleId = result->Fetch()[0].Get<uint32>() + 1;
    }
};

// ============================================================
// PlayerScript — state lifecycle, loot hook, window requests
// ============================================================

class LootFilter_Player : public PlayerScript
{
public:
    LootFilter_Player() : PlayerScript("LootFilter_Player",
        {
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_LOOT_ITEM,
            PLAYERHOOK_ON_BEFORE_SEND_CHAT_MESSAGE,
            PLAYERHOOK_ON_DELETE_FROM_DB
        }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (!conf_Enable)
            return;
        uint32 const guid = player->GetGUID().GetCounter();
        FilterState st = LoadState(guid);
        std::lock_guard<std::mutex> lock(s_mutex);
        s_states[guid] = std::move(st);
    }

    void OnPlayerLogout(Player* player) override
    {
        uint32 const guid = player->GetGUID().GetCounter();
        FilterBatch b;
        {
            std::lock_guard<std::mutex> lock(s_mutex);
            auto it = s_states.find(guid);
            if (it == s_states.end())
                return;
            b = it->second.batch;
            s_states.erase(it);
        }
        FlushBatch(guid, b);
    }

    void OnPlayerLootItem(Player* player, Item* item, uint32 /*count*/,
        ObjectGuid /*lootguid*/) override
    {
        if (!conf_Enable || !item)
            return;
        {
            std::lock_guard<std::mutex> lock(s_mutex);
            auto it = s_states.find(player->GetGUID().GetCounter());
            if (it == s_states.end() || !it->second.filterEnabled
                || it->second.rules.empty())
                return;
        }
        player->m_Events.AddEvent(
            new LootFilterEvent(player->GetGUID(), item->GetGUID()),
            player->m_Events.CalculateTime(1));
    }

    void OnPlayerBeforeSendChatMessage(Player* player, uint32& type,
        uint32& lang, std::string& message) override
    {
        if (type != CHAT_MSG_WHISPER || lang != LANG_ADDON
            || message.compare(0, PREFIX_IN_LEN, PREFIX_IN) != 0
            || message.size() > PREFIX_IN_LEN + LFR::MAX_MESSAGE)
            return;
        HandleRequest(player, message.substr(PREFIX_IN_LEN));
    }

    void OnPlayerDeleteFromDB(CharacterDatabaseTransaction trans,
        uint32 guid) override
    {
        trans->Append(
            "DELETE c FROM character_loot_filter_condition AS c "
            "INNER JOIN character_loot_filter_rule AS r ON r.ruleId = c.ruleId "
            "WHERE r.characterId = {}", guid);
        trans->Append(
            "DELETE FROM character_loot_filter_rule WHERE characterId = {}",
            guid);
        trans->Append(
            "DELETE FROM character_loot_filter_settings WHERE characterId = {}",
            guid);
    }
};

// ============================================================
// Commands
// ============================================================

class LootFilter_Command : public CommandScript
{
public:
    LootFilter_Command() : CommandScript("LootFilter_Command") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable lootFilterTable =
        {
            { "reload", HandleReloadCmd, SEC_PLAYER, Console::No },
            { "toggle", HandleToggleCmd, SEC_PLAYER, Console::No },
            { "stats",  HandleStatsCmd,  SEC_PLAYER, Console::No },
            { "request", HandleRequestCmd, SEC_PLAYER, Console::No },
        };
        static ChatCommandTable commandTable =
        {
            { "lootfilter", lootFilterTable },
        };
        return commandTable;
    }

    // Re-reads the character's rules and settings, e.g. after a manual SQL
    // edit (the core is otherwise the only writer).
    static bool HandleReloadCmd(ChatHandler* handler, Tail /*args*/)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;
        uint32 const guid = player->GetGUID().GetCounter();
        FilterState st = LoadState(guid);
        std::size_t rules = 0;
        {
            std::lock_guard<std::mutex> lock(s_mutex);
            FilterState& slot = s_states[guid];
            st.batch = slot.batch;
            slot = std::move(st);
            rules = slot.rules.size();
            Reply const out{ player, nullptr };
            SendSettings(out, slot);
            SendRules(out, slot);
        }
        handler->PSendSysMessage("{}Rules reloaded ({} rules).", CHAT_TAG,
            rules);
        return true;
    }

    static bool HandleToggleCmd(ChatHandler* handler, Tail /*args*/)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;
        uint32 const guid = player->GetGUID().GetCounter();
        bool enabled = false;
        {
            std::lock_guard<std::mutex> lock(s_mutex);
            auto it = s_states.find(guid);
            if (it == s_states.end())
                return true;
            it->second.filterEnabled = !it->second.filterEnabled;
            enabled = it->second.filterEnabled;
            SaveSettings(guid, it->second);
        }
        SendAddon(player, enabled ? "F|1" : "F|0");
        handler->PSendSysMessage("{}Filter {}.", CHAT_TAG,
            enabled ? "enabled" : "disabled");
        return true;
    }

    // The window's protocol as a chat command: the same handler, limits and
    // validation, with the answers also printed ("LFLS <message>"). For test
    // bots and debugging; a player gains nothing the window cannot do.
    static bool HandleRequestCmd(ChatHandler* handler, Tail payload)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;
        std::string const request(payload);
        if (request.empty() || request.size() > LFR::MAX_MESSAGE)
            return false;
        HandleRequest(player, request, handler);
        return true;
    }

    static bool HandleStatsCmd(ChatHandler* handler, Tail /*args*/)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;
        std::lock_guard<std::mutex> lock(s_mutex);
        auto it = s_states.find(player->GetGUID().GetCounter());
        if (it == s_states.end())
        {
            handler->PSendSysMessage("{}No stats available.", CHAT_TAG);
            return true;
        }
        FilterState const& st = it->second;
        handler->PSendSysMessage("{}Filter: {} | Rules: {}", CHAT_TAG,
            st.filterEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r",
            st.rules.size());
        handler->PSendSysMessage("  Gold earned: {}", FormatMoney(st.totalSold));
        handler->PSendSysMessage("  Disenchanted: {} | Stored: {} | Deleted: {}",
            st.totalDisenchanted, st.totalStored, st.totalDeleted);
        return true;
    }
};

void AddLootFilterScripts()
{
    new LootFilter_World();
    new LootFilter_Player();
    new LootFilter_Command();
}
