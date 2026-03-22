-- =============================================================
-- mod-loot-filter — Server-side AIO (Eluna)
--
-- Handles all DB operations for filter rules and sends data
-- to the client UI. Receives commands from the client to
-- add/edit/delete/toggle rules.
-- =============================================================

local AIO = AIO or require("AIO")

-- Client addon registration is handled by AIO.AddAddon() in
-- LootFilter_Client.lua (Eluna loads both files from the same
-- directory; the client file self-registers via debug.getinfo).

-- ============================================================
-- Handler table (global for AIO reload safety)
-- ============================================================

if not LootFilter_ServerHandlers then
	LootFilter_ServerHandlers = {}
end

-- ============================================================
-- Constants
-- ============================================================

local MAX_RULES = 30

local CONDITION_NAMES = {
	[0] = "Quality",
	[1] = "Item Level Below",
	[2] = "Sell Price Below",
	[3] = "Item Class",
	[4] = "Item Subclass",
	[5] = "Is Cursed",
	[6] = "Item ID",
	[7] = "Name Contains",
}

local ACTION_NAMES = {
	[0] = "Keep",
	[1] = "Sell",
	[2] = "Disenchant",
	[3] = "Delete",
}

-- ============================================================
-- Helper: send all rules + settings to a player's client UI
-- ============================================================

local function SendFilterData(player)
	local guid = player:GetGUIDLow()

	-- Load settings
	local settingsQ = CharDBQuery(string.format(
		"SELECT `filterEnabled`, `totalSold`, `totalDisenchanted`, `totalDeleted` "..
		"FROM `character_loot_filter_settings` WHERE `characterId` = %d", guid))

	local filterEnabled = 1
	local totalSold = 0
	local totalDE = 0
	local totalDel = 0

	if settingsQ then
		filterEnabled = settingsQ:GetUInt32(0)
		totalSold = settingsQ:GetUInt32(1)
		totalDE = settingsQ:GetUInt32(2)
		totalDel = settingsQ:GetUInt32(3)
	else
		-- Create default settings
		CharDBExecute(string.format(
			"INSERT INTO `character_loot_filter_settings` "..
			"(`characterId`, `filterEnabled`, `totalSold`, `totalDisenchanted`, `totalDeleted`) "..
			"VALUES (%d, 1, 0, 0, 0)", guid))
	end

	-- Send settings first
	local msg = AIO.Msg()
	msg:Add("LootFilter", "ReceiveSettings",
		filterEnabled, totalSold, totalDE, totalDel, MAX_RULES)

	-- Load rules
	local rulesQ = CharDBQuery(string.format(
		"SELECT `ruleId`, `conditionType`, `conditionValue`, `conditionStr`, "..
		"`action`, `priority`, `enabled` "..
		"FROM `character_loot_filter` WHERE `characterId` = %d "..
		"ORDER BY `priority` ASC", guid))

	-- Clear existing rules on client
	msg:Add("LootFilter", "ClearRules")

	if rulesQ then
		repeat
			local ruleId = rulesQ:GetUInt32(0)
			local condType = rulesQ:GetUInt32(1)
			local condValue = rulesQ:GetUInt32(2)
			local condStr = rulesQ:GetString(3)
			local action = rulesQ:GetUInt32(4)
			local priority = rulesQ:GetUInt32(5)
			local enabled = rulesQ:GetUInt32(6)

			msg:Add("LootFilter", "ReceiveRule",
				ruleId, condType, condValue, condStr,
				action, priority, enabled)
		until not rulesQ:NextRow()
	end

	msg:Add("LootFilter", "RefreshUI")
	msg:Send(player)
end

-- ============================================================
-- Handler: Client requests initial data on login / UI open
-- ============================================================

LootFilter_ServerHandlers.RequestData = function(player)
	SendFilterData(player)
end

-- ============================================================
-- Handler: Add a new rule
-- ============================================================

LootFilter_ServerHandlers.AddRule = function(player, condType, condValue, condStr, action, priority)
	local guid = player:GetGUIDLow()

	-- Validate inputs
	condType = tonumber(condType) or 0
	condValue = tonumber(condValue) or 0
	condStr = tostring(condStr or "")
	action = tonumber(action) or 1
	priority = tonumber(priority) or 100

	if condType < 0 or condType > 7 then return end
	if action < 0 or action > 3 then return end
	if priority < 0 or priority > 255 then priority = 100 end

	-- Sanitize string (escape single quotes)
	condStr = string.gsub(condStr, "'", "\\'")
	if #condStr > 128 then condStr = string.sub(condStr, 1, 128) end

	-- Check rule count limit
	local countQ = CharDBQuery(string.format(
		"SELECT COUNT(*) FROM `character_loot_filter` WHERE `characterId` = %d", guid))
	if countQ then
		local count = countQ:GetUInt32(0)
		if count >= MAX_RULES then
			player:SendBroadcastMessage("|cffff0000[Loot Filter]|r Maximum rules reached ("..MAX_RULES..").")
			return
		end
	end

	CharDBExecute(string.format(
		"INSERT INTO `character_loot_filter` "..
		"(`characterId`, `conditionType`, `conditionValue`, `conditionStr`, `action`, `priority`, `enabled`) "..
		"VALUES (%d, %d, %d, '%s', %d, %d, 1)",
		guid, condType, condValue, condStr, action, priority))

	-- Reload C++ cache
	player:SendBroadcastMessage("|cff00cc00[Loot Filter]|r Rule added.")

	-- Trigger C++ reload via chat command
	player:GetSession():SendAreaTriggerMessage("")

	-- Refresh client
	SendFilterData(player)
end

-- ============================================================
-- Handler: Delete a rule
-- ============================================================

LootFilter_ServerHandlers.DeleteRule = function(player, ruleId)
	local guid = player:GetGUIDLow()
	ruleId = tonumber(ruleId) or 0

	-- Verify rule belongs to player
	local checkQ = CharDBQuery(string.format(
		"SELECT `ruleId` FROM `character_loot_filter` "..
		"WHERE `ruleId` = %d AND `characterId` = %d", ruleId, guid))

	if not checkQ then
		player:SendBroadcastMessage("|cffff0000[Loot Filter]|r Rule not found.")
		return
	end

	CharDBExecute(string.format(
		"DELETE FROM `character_loot_filter` WHERE `ruleId` = %d AND `characterId` = %d",
		ruleId, guid))

	player:SendBroadcastMessage("|cff00cc00[Loot Filter]|r Rule deleted.")
	SendFilterData(player)
end

-- ============================================================
-- Handler: Toggle a rule on/off
-- ============================================================

LootFilter_ServerHandlers.ToggleRule = function(player, ruleId)
	local guid = player:GetGUIDLow()
	ruleId = tonumber(ruleId) or 0

	CharDBExecute(string.format(
		"UPDATE `character_loot_filter` SET `enabled` = IF(`enabled`=1, 0, 1) "..
		"WHERE `ruleId` = %d AND `characterId` = %d",
		ruleId, guid))

	SendFilterData(player)
end

-- ============================================================
-- Handler: Toggle master filter on/off
-- ============================================================

LootFilter_ServerHandlers.ToggleFilter = function(player)
	local guid = player:GetGUIDLow()

	CharDBExecute(string.format(
		"UPDATE `character_loot_filter_settings` "..
		"SET `filterEnabled` = IF(`filterEnabled`=1, 0, 1) "..
		"WHERE `characterId` = %d", guid))

	SendFilterData(player)
end

-- ============================================================
-- Handler: Update rule priority
-- ============================================================

LootFilter_ServerHandlers.UpdatePriority = function(player, ruleId, newPriority)
	local guid = player:GetGUIDLow()
	ruleId = tonumber(ruleId) or 0
	newPriority = tonumber(newPriority) or 100

	if newPriority < 0 or newPriority > 255 then newPriority = 100 end

	CharDBExecute(string.format(
		"UPDATE `character_loot_filter` SET `priority` = %d "..
		"WHERE `ruleId` = %d AND `characterId` = %d",
		newPriority, ruleId, guid))

	SendFilterData(player)
end

-- ============================================================
-- Handler: Delete all rules
-- ============================================================

LootFilter_ServerHandlers.DeleteAllRules = function(player)
	local guid = player:GetGUIDLow()

	CharDBExecute(string.format(
		"DELETE FROM `character_loot_filter` WHERE `characterId` = %d", guid))

	player:SendBroadcastMessage("|cff00cc00[Loot Filter]|r All rules deleted.")
	SendFilterData(player)
end

-- ============================================================
-- Register AIO handlers (once only)
-- ============================================================

if not LootFilter_HandlersRegistered then
	AIO.AddHandlers("LootFilter", LootFilter_ServerHandlers)
	LootFilter_HandlersRegistered = true
end

-- No AIO.AddOnInit here — the client requests data when the UI
-- is opened (/lf, minimap button), avoiding the race condition
-- where data arrives before the client addon has loaded.
