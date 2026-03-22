/*
 * mod-loot-filter — Automatic loot filtering for AzerothCore
 *
 * Hooks into OnPlayerLootItem to intercept items acquired by
 * mod-auto-loot and applies per-character filter rules.
 */

#include "LootFilter.h"
#include "Chat.h"
#include "CommandScript.h"
#include "Config.h"
#include "DatabaseEnv.h"
#include "EventProcessor.h"
#include "Item.h"
#include "Log.h"
#include "ObjectAccessor.h"
#include "ObjectMgr.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

using namespace Acore::ChatCommands;

#include <mutex>
#include <unordered_map>
#include <vector>

// ============================================================
// Config values
// ============================================================

static bool  conf_Enable            = true;
static bool  conf_AllowSell         = true;
static bool  conf_AllowDisenchant   = true;
static bool  conf_AllowDelete       = true;
static bool  conf_LogActions        = true;
static uint32 conf_MaxRulesPerChar  = 30;

// ============================================================
// In-memory filter rule
// ============================================================

struct FilterRule
{
    uint32 ruleId;
    uint32 ruleGroup;       // 0 = standalone, >0 = AND group
    uint8  conditionType;   // LootFilterCondition
    uint32 conditionValue;  // numeric value for the condition
    std::string conditionStr; // string value (for name contains)
    uint8  action;          // LootFilterAction
    uint8  priority;        // lower = checked first
    bool   enabled;
};

struct PlayerFilterSettings
{
    bool   filterEnabled;
    uint32 totalSold;       // gold earned through auto-sell (copper)
    uint32 totalDisenchanted;
    uint32 totalDeleted;
};

// ============================================================
// In-memory cache: characterGuid -> rules
// ============================================================

static std::mutex s_filterMutex;
static std::unordered_map<uint32, std::vector<FilterRule>> s_filterRules;
static std::unordered_map<uint32, PlayerFilterSettings> s_filterSettings;

// ============================================================
// Database helpers
// ============================================================

static void LoadRulesForPlayer(uint32 guid)
{
    QueryResult result = CharacterDatabase.Query(
        "SELECT `ruleId`, `ruleGroup`, `conditionType`, "
        "`conditionValue`, `conditionStr`, `action`, "
        "`priority`, `enabled` "
        "FROM `character_loot_filter` WHERE `characterId` = {} "
        "ORDER BY `ruleGroup` ASC, `priority` ASC", guid);

    std::vector<FilterRule> rules;
    if (result)
    {
        do
        {
            Field* fields = result->Fetch();
            FilterRule r;
            r.ruleId        = fields[0].Get<uint32>();
            r.ruleGroup     = fields[1].Get<uint32>();
            r.conditionType = fields[2].Get<uint8>();
            r.conditionValue = fields[3].Get<uint32>();
            r.conditionStr  = fields[4].Get<std::string>();
            r.action        = fields[5].Get<uint8>();
            r.priority      = fields[6].Get<uint8>();
            r.enabled       = fields[7].Get<bool>();
            rules.push_back(r);
        } while (result->NextRow());
    }

    std::lock_guard<std::mutex> lock(s_filterMutex);
    s_filterRules[guid] = std::move(rules);
}

static void LoadSettingsForPlayer(uint32 guid)
{
    QueryResult result = CharacterDatabase.Query(
        "SELECT `filterEnabled`, `totalSold`, `totalDisenchanted`, "
        "`totalDeleted` FROM `character_loot_filter_settings` "
        "WHERE `characterId` = {}", guid);

    PlayerFilterSettings settings;
    if (result)
    {
        Field* fields = result->Fetch();
        settings.filterEnabled      = fields[0].Get<bool>();
        settings.totalSold          = fields[1].Get<uint32>();
        settings.totalDisenchanted  = fields[2].Get<uint32>();
        settings.totalDeleted       = fields[3].Get<uint32>();
    }
    else
    {
        settings.filterEnabled = true;
        settings.totalSold = 0;
        settings.totalDisenchanted = 0;
        settings.totalDeleted = 0;
        CharacterDatabase.Execute(
            "INSERT INTO `character_loot_filter_settings` "
            "(`characterId`, `filterEnabled`, `totalSold`, "
            "`totalDisenchanted`, `totalDeleted`) "
            "VALUES ({}, 1, 0, 0, 0)", guid);
    }

    std::lock_guard<std::mutex> lock(s_filterMutex);
    s_filterSettings[guid] = settings;
}

static void SaveStats(uint32 guid)
{
    std::lock_guard<std::mutex> lock(s_filterMutex);
    auto const& it = s_filterSettings.find(guid);
    if (it == s_filterSettings.end())
        return;

    auto const& s = it->second;
    CharacterDatabase.Execute(
        "UPDATE `character_loot_filter_settings` SET "
        "`totalSold` = {}, `totalDisenchanted` = {}, "
        "`totalDeleted` = {} WHERE `characterId` = {}",
        s.totalSold, s.totalDisenchanted, s.totalDeleted, guid);
}

// ============================================================
// Paragon cursed item detection (check slot 11 for enchant 920001)
// ============================================================

static bool IsParagonCursedItem(Item const* item)
{
    if (!item)
        return false;

    // Slot 11 = PROP_ENCHANTMENT_SLOT_4
    uint32 enchId = item->GetEnchantmentId(
        static_cast<EnchantmentSlot>(11));
    // 920001 = Cursed marker, 950001-950099 = passive spell enchants
    return enchId == 920001 || (enchId >= 950001 && enchId <= 950099);
}

// ============================================================
// Filter matching logic
// ============================================================

static bool MatchesCondition(FilterRule const& rule,
    Item const* item, ItemTemplate const* proto)
{
    switch (rule.conditionType)
    {
        case FILTER_COND_QUALITY:
            return proto->Quality == rule.conditionValue;

        case FILTER_COND_ILVL_BELOW:
            return proto->ItemLevel < rule.conditionValue;

        case FILTER_COND_SELL_PRICE_BELOW:
            return proto->SellPrice < rule.conditionValue;

        case FILTER_COND_ITEM_CLASS:
            return proto->Class == rule.conditionValue;

        case FILTER_COND_ITEM_SUBCLASS:
            return proto->SubClass == rule.conditionValue;

        case FILTER_COND_IS_CURSED:
            return IsParagonCursedItem(item)
                   == (rule.conditionValue != 0);

        case FILTER_COND_ITEM_ID:
            return proto->ItemId == rule.conditionValue;

        case FILTER_COND_NAME_CONTAINS:
        {
            if (rule.conditionStr.empty())
                return false;
            std::string name = proto->Name1;
            std::string search = rule.conditionStr;
            // case-insensitive search
            std::transform(name.begin(), name.end(),
                name.begin(), ::tolower);
            std::transform(search.begin(), search.end(),
                search.begin(), ::tolower);
            return name.find(search) != std::string::npos;
        }

        default:
            return false;
    }
}

static bool IsActionAllowed(uint8 action)
{
    if (action == FILTER_ACTION_SELL && !conf_AllowSell)
        return false;
    if (action == FILTER_ACTION_DISENCHANT && !conf_AllowDisenchant)
        return false;
    if (action == FILTER_ACTION_DELETE && !conf_AllowDelete)
        return false;
    return true;
}

static LootFilterAction EvaluateFilter(Player* player, Item* item)
{
    uint32 guid = player->GetGUID().GetCounter();
    ItemTemplate const* proto = item->GetTemplate();
    if (!proto)
        return FILTER_ACTION_KEEP;

    std::lock_guard<std::mutex> lock(s_filterMutex);

    auto settingsIt = s_filterSettings.find(guid);
    if (settingsIt == s_filterSettings.end()
        || !settingsIt->second.filterEnabled)
        return FILTER_ACTION_KEEP;

    auto rulesIt = s_filterRules.find(guid);
    if (rulesIt == s_filterRules.end() || rulesIt->second.empty())
        return FILTER_ACTION_KEEP;

    // Group rules: ruleGroup=0 are standalone (OR),
    // ruleGroup>0 are AND-combined within the same group.
    // Different groups are OR-combined.

    // Collect grouped rules
    std::unordered_map<uint32, std::vector<FilterRule const*>> groups;
    std::vector<FilterRule const*> standalone;

    for (auto const& rule : rulesIt->second)
    {
        if (!rule.enabled)
            continue;
        if (rule.ruleGroup == 0)
            standalone.push_back(&rule);
        else
            groups[rule.ruleGroup].push_back(&rule);
    }

    // Check standalone rules first (OR — first match wins)
    for (auto const* rule : standalone)
    {
        if (MatchesCondition(*rule, item, proto)
            && IsActionAllowed(rule->action))
            return static_cast<LootFilterAction>(rule->action);
    }

    // Check AND groups (all conditions in group must match)
    for (auto const& [groupId, groupRules] : groups)
    {
        bool allMatch = true;
        for (auto const* rule : groupRules)
        {
            if (!MatchesCondition(*rule, item, proto))
            {
                allMatch = false;
                break;
            }
        }

        if (allMatch && !groupRules.empty())
        {
            // Action comes from the first rule in the group
            uint8 action = groupRules.front()->action;
            if (IsActionAllowed(action))
                return static_cast<LootFilterAction>(action);
        }
    }

    return FILTER_ACTION_KEEP;
}

// ============================================================
// Action execution
// ============================================================

static void SellItem(Player* player, Item* item)
{
    ItemTemplate const* proto = item->GetTemplate();
    uint32 count = item->GetCount();
    uint32 sellPrice = proto->SellPrice * count;

    std::string itemName = proto->Name1;

    if (sellPrice > 0)
        player->ModifyMoney(sellPrice);

    player->DestroyItem(
        item->GetBagSlot(), item->GetSlot(), true);

    uint32 guid = player->GetGUID().GetCounter();
    {
        std::lock_guard<std::mutex> lock(s_filterMutex);
        s_filterSettings[guid].totalSold += sellPrice;
    }

    if (conf_LogActions)
    {
        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cff888888[Loot Filter]|r Sold {} for {} copper.",
            itemName, sellPrice);
    }
}

static void DisenchantItem(Player* player, Item* item)
{
    ItemTemplate const* proto = item->GetTemplate();
    std::string itemName = proto->Name1;

    // Check if player has enchanting skill
    if (!player->HasSkill(333)) // 333 = Enchanting
    {
        // Fallback: sell instead
        if (conf_AllowSell)
        {
            SellItem(player, item);
            return;
        }
        return;
    }

    // Check if item has a disenchant loot template
    if (proto->DisenchantID == 0)
    {
        // Not disenchantable, sell instead
        if (conf_AllowSell)
        {
            SellItem(player, item);
            return;
        }
        return;
    }

    // Generate disenchant loot and give materials to player
    Loot loot;
    loot.FillLoot(proto->DisenchantID,
        LootTemplates_Disenchant, player, true);

    for (uint32 i = 0; i < loot.items.size(); ++i)
    {
        LootItem const& lootItem = loot.items[i];
        ItemPosCountVec dest;
        if (player->CanStoreNewItem(NULL_BAG, NULL_SLOT,
            dest, lootItem.itemid, lootItem.count) == EQUIP_ERR_OK)
        {
            Item* newItem = player->StoreNewItem(
                dest, lootItem.itemid, true);
            if (newItem)
                player->SendNewItem(newItem, lootItem.count,
                    true, false);
        }
        else
        {
            // Mail overflow materials
            player->SendItemRetrievalMail(
                lootItem.itemid, lootItem.count);
        }
    }

    // Destroy the original item
    player->DestroyItem(
        item->GetBagSlot(), item->GetSlot(), true);

    uint32 guid = player->GetGUID().GetCounter();
    {
        std::lock_guard<std::mutex> lock(s_filterMutex);
        s_filterSettings[guid].totalDisenchanted++;
    }

    if (conf_LogActions)
    {
        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cff888888[Loot Filter]|r Disenchanted {}.",
            itemName);
    }
}

static void DeleteItem(Player* player, Item* item)
{
    ItemTemplate const* proto = item->GetTemplate();
    std::string itemName = proto->Name1;

    player->DestroyItem(
        item->GetBagSlot(), item->GetSlot(), true);

    uint32 guid = player->GetGUID().GetCounter();
    {
        std::lock_guard<std::mutex> lock(s_filterMutex);
        s_filterSettings[guid].totalDeleted++;
    }

    if (conf_LogActions)
    {
        ChatHandler(player->GetSession()).PSendSysMessage(
            "|cff888888[Loot Filter]|r Deleted {}.",
            itemName);
    }
}

// ============================================================
// Deferred filter event — runs action on next server tick
// ============================================================

struct LootFilterEvent : public BasicEvent
{
    LootFilterEvent(Player* p, ObjectGuid itemGuid, LootFilterAction a)
        : _playerGuid(p->GetGUID()), _itemGuid(itemGuid), _action(a) { }

    bool Execute(uint64 /*time*/, uint32 /*diff*/) override
    {
        Player* player = ObjectAccessor::FindPlayer(_playerGuid);
        if (!player)
            return true;

        Item* item = player->GetItemByGuid(_itemGuid);
        if (!item)
            return true;

        switch (_action)
        {
            case FILTER_ACTION_SELL:
                SellItem(player, item);
                break;
            case FILTER_ACTION_DISENCHANT:
                DisenchantItem(player, item);
                break;
            case FILTER_ACTION_DELETE:
                DeleteItem(player, item);
                break;
            default:
                break;
        }
        return true;
    }

    ObjectGuid _playerGuid;
    ObjectGuid _itemGuid;
    LootFilterAction _action;
};

// ============================================================
// WorldScript — config loading
// ============================================================

class LootFilter_World : public WorldScript
{
public:
    LootFilter_World() : WorldScript("LootFilter_World") { }

    void OnAfterConfigLoad(bool /*reload*/) override
    {
        conf_Enable = sConfigMgr->GetOption<bool>(
            "LootFilter.Enable", true);
        conf_AllowSell = sConfigMgr->GetOption<bool>(
            "LootFilter.AllowSell", true);
        conf_AllowDisenchant = sConfigMgr->GetOption<bool>(
            "LootFilter.AllowDisenchant", true);
        conf_AllowDelete = sConfigMgr->GetOption<bool>(
            "LootFilter.AllowDelete", true);
        conf_LogActions = sConfigMgr->GetOption<bool>(
            "LootFilter.LogActions", true);
        conf_MaxRulesPerChar = sConfigMgr->GetOption<uint32>(
            "LootFilter.MaxRulesPerChar", 30);
    }
};

// ============================================================
// PlayerScript — hooks for loot processing and data lifecycle
// ============================================================

class LootFilter_Player : public PlayerScript
{
public:
    LootFilter_Player() : PlayerScript("LootFilter_Player",
        {
            PLAYERHOOK_ON_LOGIN,
            PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_LOOT_ITEM
        }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (!conf_Enable)
            return;

        uint32 guid = player->GetGUID().GetCounter();
        LoadRulesForPlayer(guid);
        LoadSettingsForPlayer(guid);
    }

    void OnPlayerLogout(Player* player) override
    {
        uint32 guid = player->GetGUID().GetCounter();
        SaveStats(guid);

        std::lock_guard<std::mutex> lock(s_filterMutex);
        s_filterRules.erase(guid);
        s_filterSettings.erase(guid);
    }

    void OnPlayerLootItem(Player* player, Item* item,
        uint32 /*count*/, ObjectGuid /*lootguid*/) override
    {
        if (!conf_Enable || !item)
            return;

        // Always reload rules from DB before evaluating, since
        // rules may have been changed via AIO/Lua without C++
        // cache being notified.
        uint32 guid = player->GetGUID().GetCounter();
        LoadRulesForPlayer(guid);
        LoadSettingsForPlayer(guid);

        LootFilterAction action = EvaluateFilter(player, item);

        if (action != FILTER_ACTION_KEEP)
        {
            // Defer to next tick — item pointer is still in use by loot system
            player->m_Events.AddEvent(
                new LootFilterEvent(player, item->GetGUID(), action),
                player->m_Events.CalculateTime(1));
            return;
        }
    }
};

// ============================================================
// Eluna hooks for AIO communication (rule CRUD)
// ============================================================

// These are called from Lua via server-side AIO handlers.
// The C++ side exposes helper functions that the Lua layer calls
// through Eluna's direct DB access. All rule management is done
// in Lua/SQL, and the C++ side just needs to reload the cache.

// Provide a global function that Lua can trigger to reload cache
class LootFilter_Command : public CommandScript
{
public:
    LootFilter_Command()
        : CommandScript("LootFilter_Command") { }

    ChatCommandTable GetCommands() const override
    {
        static ChatCommandTable lootFilterTable =
        {
            { "reload",  HandleReloadCmd,
              SEC_PLAYER, Console::No },
            { "toggle",  HandleToggleCmd,
              SEC_PLAYER, Console::No },
            { "stats",   HandleStatsCmd,
              SEC_PLAYER, Console::No },
        };

        static ChatCommandTable commandTable =
        {
            { "lootfilter", lootFilterTable },
        };

        return commandTable;
    }

    static bool HandleReloadCmd(ChatHandler* handler,
        Tail /*args*/)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;

        uint32 guid = player->GetGUID().GetCounter();
        LoadRulesForPlayer(guid);
        LoadSettingsForPlayer(guid);

        std::lock_guard<std::mutex> lock(s_filterMutex);
        handler->PSendSysMessage(
            "|cff00cc00[Loot Filter]|r Rules reloaded ({} rules).",
            static_cast<uint32>(s_filterRules[guid].size()));
        return true;
    }

    static bool HandleToggleCmd(ChatHandler* handler,
        Tail /*args*/)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;

        uint32 guid = player->GetGUID().GetCounter();

        {
            std::lock_guard<std::mutex> lock(s_filterMutex);
            auto it = s_filterSettings.find(guid);
            if (it != s_filterSettings.end())
            {
                it->second.filterEnabled =
                    !it->second.filterEnabled;
                CharacterDatabase.Execute(
                    "UPDATE `character_loot_filter_settings` "
                    "SET `filterEnabled` = {} "
                    "WHERE `characterId` = {}",
                    it->second.filterEnabled ? 1 : 0, guid);
                handler->PSendSysMessage(
                    "|cff00cc00[Loot Filter]|r Filter {}.",
                    it->second.filterEnabled
                        ? "enabled" : "disabled");
            }
        }

        return true;
    }

    static bool HandleStatsCmd(ChatHandler* handler,
        Tail /*args*/)
    {
        Player* player = handler->GetPlayer();
        if (!player)
            return false;

        uint32 guid = player->GetGUID().GetCounter();

        std::lock_guard<std::mutex> lock(s_filterMutex);
        auto it = s_filterSettings.find(guid);
        if (it == s_filterSettings.end())
        {
            handler->PSendSysMessage(
                "|cff00cc00[Loot Filter]|r No stats available.");
            return true;
        }

        auto const& s = it->second;
        uint32 gold   = s.totalSold / 10000;
        uint32 silver = (s.totalSold % 10000) / 100;
        uint32 copper = s.totalSold % 100;

        handler->PSendSysMessage(
            "|cff00cc00[Loot Filter]|r Stats:");
        handler->PSendSysMessage(
            "  Filter: {} | Rules: {}",
            s.filterEnabled ? "|cff00ff00ON|r" : "|cffff0000OFF|r",
            static_cast<uint32>(s_filterRules.count(guid)
                ? s_filterRules[guid].size() : 0));
        handler->PSendSysMessage(
            "  Gold earned: {}g {}s {}c", gold, silver, copper);
        handler->PSendSysMessage(
            "  Disenchanted: {} | Deleted: {}",
            s.totalDisenchanted, s.totalDeleted);

        return true;
    }
};

void AddLootFilterScripts()
{
    new LootFilter_World();
    new LootFilter_Player();
    new LootFilter_Command();
}
