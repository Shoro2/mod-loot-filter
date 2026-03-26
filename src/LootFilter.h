/*
 * mod-loot-filter — Automatic loot filtering for AzerothCore
 *
 * Works in tandem with mod-auto-loot: items picked up by auto-loot
 * are checked against per-character filter rules and automatically
 * sold (vendor), disenchanted, or destroyed.
 *
 * Filter criteria: item quality, item level, vendor sell price,
 * item class/subclass, cursed status, specific item IDs.
 *
 * Configuration is done via an AIO in-game UI.
 */

#ifndef LOOT_FILTER_H
#define LOOT_FILTER_H

#include "Define.h"

// ============================================================
// Filter action — what to do with a matched item
// ============================================================
enum LootFilterAction : uint8
{
    FILTER_ACTION_KEEP          = 0,  // do nothing (whitelist)
    FILTER_ACTION_SELL          = 1,  // auto-vendor for gold
    FILTER_ACTION_DISENCHANT    = 2,  // disenchant (if player has skill)
    FILTER_ACTION_DELETE        = 3,  // destroy immediately
    FILTER_ACTION_MAX
};

// ============================================================
// Filter condition type — what property to check
// ============================================================
enum LootFilterCondition : uint8
{
    FILTER_COND_QUALITY         = 0,  // item quality (0-7)
    FILTER_COND_ILVL            = 1,  // item level
    FILTER_COND_SELL_PRICE      = 2,  // vendor price (copper)
    FILTER_COND_ITEM_CLASS      = 3,  // item class (0=consumable, 2=weapon, 4=armor, ...)
    FILTER_COND_ITEM_SUBCLASS   = 4,  // item subclass (weapon/armor subtype)
    FILTER_COND_IS_CURSED       = 5,  // cursed paragon item (slot 11 marker)
    FILTER_COND_ITEM_ID         = 6,  // specific item entry
    FILTER_COND_NAME_CONTAINS   = 7,  // item name contains string
    FILTER_COND_MAX
};

// ============================================================
// Filter comparison operator
// ============================================================
enum LootFilterOp : uint8
{
    FILTER_OP_EQUAL     = 0,  // ==
    FILTER_OP_GREATER   = 1,  // >
    FILTER_OP_LESS      = 2,  // <
    FILTER_OP_MAX
};

// ============================================================
// WoW item quality values
// ============================================================
enum ItemQualityFilter : uint8
{
    QUALITY_POOR        = 0,  // grey
    QUALITY_NORMAL      = 1,  // white
    QUALITY_UNCOMMON    = 2,  // green
    QUALITY_RARE        = 3,  // blue
    QUALITY_EPIC        = 4,  // purple
    QUALITY_LEGENDARY   = 5,  // orange
    QUALITY_ARTIFACT    = 6,  // red
    QUALITY_HEIRLOOM    = 7   // gold
};

// ============================================================
// WoW item class values (most common)
// ============================================================
enum ItemClassFilter : uint8
{
    ICLASS_CONSUMABLE   = 0,
    ICLASS_CONTAINER    = 1,
    ICLASS_WEAPON       = 2,
    ICLASS_GEM          = 3,
    ICLASS_ARMOR        = 4,
    ICLASS_REAGENT      = 5,
    ICLASS_PROJECTILE   = 6,
    ICLASS_TRADE_GOODS  = 7,
    ICLASS_RECIPE       = 9,
    ICLASS_QUIVER       = 11,
    ICLASS_QUEST        = 12,
    ICLASS_KEY          = 13,
    ICLASS_MISC         = 15,
    ICLASS_GLYPH        = 16
};

// Max filter rules per character
constexpr uint32 LOOT_FILTER_MAX_RULES = 30;

// Prepared statement indices
enum LootFilterDatabaseStatements : uint32
{
    LOOF_SEL_RULES          = 0,
    LOOF_INS_RULE           = 1,
    LOOF_DEL_RULE           = 2,
    LOOF_DEL_ALL_RULES      = 3,
    LOOF_UPD_ENABLED        = 4,
    LOOF_SEL_SETTINGS       = 5,
    LOOF_INS_SETTINGS       = 6,
    LOOF_SEL_STATS          = 7,
    LOOF_UPD_STATS          = 8,
    LOOF_INS_STATS          = 9,
    LOOF_MAX
};

void AddLootFilterScripts();

#endif // LOOT_FILTER_H
