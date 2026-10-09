/*
 * mod-loot-filter — automatic loot filtering for AzerothCore
 *
 * Every looted item is checked against the character's rules (one action
 * plus up to four AND-ed conditions, in an explicit order) and kept,
 * stored in the Endless Storage, sold, disenchanted or deleted. The rule
 * model lives in LootFilterRules.h; this module's core glue is in
 * LootFilter.cpp. The window is AIO-shipped Lua (lua_scripts/) that talks
 * to the core with addon messages.
 */

#ifndef LOOT_FILTER_H
#define LOOT_FILTER_H

void AddLootFilterScripts();

#endif // LOOT_FILTER_H
