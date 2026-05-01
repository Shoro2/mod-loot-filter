-- =============================================================
-- mod-loot-filter — Server-side AIO (Eluna)
--
-- Handles all DB operations for filter rules and sends data
-- to the client UI. Receives commands from the client to
-- add/edit/delete/toggle rules.
-- =============================================================

local AIO = AIO or require("AIO")

-- Optional dependency: shared validation lib (share-public/AIO_Server/Dep_Validation/).
-- Eluna lädt scripts alphabetisch, `Dep_*` kommt vor `Loot_Filter_LUA/` →
-- Lib ist zur Loadzeit da. Ohne Lib läuft das Modul mit permissiveren Shims
-- weiter, gibt aber eine Warning aus.
local Validate = _G.Validate
if not Validate then
	print("[LootFilter] WARNING: Dep_Validation/validation.lua nicht geladen — input validation läuft permissiv. Bitte share-public/AIO_Server/Dep_Validation/ nach lua_scripts/ deployen.")
	Validate = {
		IsInt = function(v) return type(v) == "number" and v == math.floor(v) end,
		IsIntInRange = function(v, lo, hi) return type(v) == "number" and v == math.floor(v) and v >= lo and v <= hi end,
		IsNonNegativeInt = function(v, cap) return type(v) == "number" and v == math.floor(v) and v >= 0 and v <= (cap or 2147483647) end,
		IsStringMaxLen = function(s, n) return type(s) == "string" and #s <= n end,
		IsInWhitelist = function(v, set) return set[v] == true end,
		ToSet = function(list) local s = {} for _, v in ipairs(list) do s[v] = true end return s end,
		SqlEscape = function(s) if type(s) ~= "string" then return "" end return (s:gsub("'", "''"):gsub("\\", "\\\\")) end,
		Reject = function(player, handler, reason)
			print(string.format("[Validate] reject handler=%s reason=%s", tostring(handler), tostring(reason)))
			return false
		end,
	}
end

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
-- Constants & Whitelists
-- ============================================================

local MAX_RULES = 30
local MAX_COND_STR_LEN = 128
local MAX_PRIORITY = 255
local MAX_RULE_GROUP = 255

-- Wert-Ranges der drei Enums (mussten vorher als <0/>N abgefragt werden;
-- jetzt als Sets für klarere Whitelists). Müssen mit dem Client und
-- LootFilter.h übereinstimmen.
local COND_TYPES = Validate.ToSet({0, 1, 2, 3, 4, 5, 6, 7})
	-- 0=Quality, 1=ItemLevel, 2=SellPrice, 3=ItemClass, 4=ItemSubclass,
	-- 5=IsCursed, 6=ItemId, 7=NameContains
local COND_OPS = Validate.ToSet({0, 1, 2}) -- =, >, <
local ACTIONS = Validate.ToSet({0, 1, 2, 3}) -- Keep, Sell, Disenchant, Delete

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
		CharDBQuery(string.format(
			"INSERT INTO `character_loot_filter_settings` "..
			"(`characterId`, `filterEnabled`, `totalSold`, `totalDisenchanted`, `totalDeleted`) "..
			"VALUES (%d, 1, 0, 0, 0)", guid))
	end

	-- Send settings first
	local msg = AIO.Msg()
	msg:Add("LootFilter", "ReceiveSettings",
		filterEnabled, totalSold, totalDE, totalDel, MAX_RULES)

	-- Load rules (including ruleGroup and conditionOp)
	local rulesQ = CharDBQuery(string.format(
		"SELECT `ruleId`, `ruleGroup`, `conditionType`, `conditionOp`, `conditionValue`, `conditionStr`, "..
		"`action`, `priority`, `enabled` "..
		"FROM `character_loot_filter` WHERE `characterId` = %d "..
		"ORDER BY `ruleGroup` ASC, `priority` ASC", guid))

	-- Clear existing rules on client
	msg:Add("LootFilter", "ClearRules")

	if rulesQ then
		repeat
			local ruleId = rulesQ:GetUInt32(0)
			local ruleGroup = rulesQ:GetUInt32(1)
			local condType = rulesQ:GetUInt32(2)
			local condOp = rulesQ:GetUInt32(3)
			local condValue = rulesQ:GetUInt32(4)
			local condStr = rulesQ:GetString(5)
			local action = rulesQ:GetUInt32(6)
			local priority = rulesQ:GetUInt32(7)
			local enabled = rulesQ:GetUInt32(8)

			msg:Add("LootFilter", "ReceiveRule",
				ruleId, ruleGroup, condType, condOp, condValue, condStr,
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

LootFilter_ServerHandlers.AddRule = function(player, condType, condOp, condValue, condStr, action, priority, ruleGroup)
	local guid = player:GetGUIDLow()

	-- Whitelist-Validierung der Enum-Felder; Reject statt Default,
	-- damit fehlerhafte Aufrufe nicht stillschweigend zu willkürlichen Regeln werden.
	if not Validate.IsInWhitelist(condType, COND_TYPES) then
		return Validate.Reject(player, "AddRule", "condType out of whitelist")
	end
	if not Validate.IsInWhitelist(condOp, COND_OPS) then
		condOp = 0  -- "=" als sicherer Default für legacy-Clients
	end
	if not Validate.IsInWhitelist(action, ACTIONS) then
		return Validate.Reject(player, "AddRule", "action out of whitelist")
	end

	-- Numerische Felder
	if not Validate.IsNonNegativeInt(condValue, 4294967295) then
		return Validate.Reject(player, "AddRule", "condValue not a non-negative int")
	end
	if not Validate.IsIntInRange(priority, 0, MAX_PRIORITY) then
		priority = 100
	end
	if not Validate.IsIntInRange(ruleGroup, 0, MAX_RULE_GROUP) then
		ruleGroup = 0
	end

	-- String-Validierung + SQL-Escape (MySQL-konform: '' statt \').
	if condStr == nil then condStr = "" end
	if not Validate.IsStringMaxLen(condStr, MAX_COND_STR_LEN) then
		return Validate.Reject(player, "AddRule", "condStr too long")
	end
	condStr = Validate.SqlEscape(condStr)

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

	-- Use CharDBQuery (synchronous) so the subsequent SELECT sees the new row
	CharDBQuery(string.format(
		"INSERT INTO `character_loot_filter` "..
		"(`characterId`, `ruleGroup`, `conditionType`, `conditionOp`, `conditionValue`, `conditionStr`, `action`, `priority`, `enabled`) "..
		"VALUES (%d, %d, %d, %d, %d, '%s', %d, %d, 1)",
		guid, ruleGroup, condType, condOp, condValue, condStr, action, priority))

	player:SendBroadcastMessage("|cff00cc00[Loot Filter]|r Rule added.")

	-- Refresh client
	SendFilterData(player)
end

-- ============================================================
-- Handler: Get next available group ID
-- ============================================================

LootFilter_ServerHandlers.GetNextGroup = function(player)
	local guid = player:GetGUIDLow()
	local maxQ = CharDBQuery(string.format(
		"SELECT COALESCE(MAX(`ruleGroup`), 0) FROM `character_loot_filter` WHERE `characterId` = %d", guid))
	local nextGroup = 1
	if maxQ then
		nextGroup = maxQ:GetUInt32(0) + 1
	end
	local msg = AIO.Msg()
	msg:Add("LootFilter", "SetNextGroup", nextGroup)
	msg:Send(player)
end

-- ============================================================
-- Handler: Delete a rule
-- ============================================================

LootFilter_ServerHandlers.DeleteRule = function(player, ruleId)
	if not Validate.IsNonNegativeInt(ruleId, 4294967295) then
		return Validate.Reject(player, "DeleteRule", "ruleId not a non-negative int")
	end
	local guid = player:GetGUIDLow()

	local checkQ = CharDBQuery(string.format(
		"SELECT `ruleId` FROM `character_loot_filter` "..
		"WHERE `ruleId` = %d AND `characterId` = %d", ruleId, guid))

	if not checkQ then
		player:SendBroadcastMessage("|cffff0000[Loot Filter]|r Rule not found.")
		return
	end

	CharDBQuery(string.format(
		"DELETE FROM `character_loot_filter` WHERE `ruleId` = %d AND `characterId` = %d",
		ruleId, guid))

	player:SendBroadcastMessage("|cff00cc00[Loot Filter]|r Rule deleted.")
	SendFilterData(player)
end

-- ============================================================
-- Handler: Toggle a rule on/off
-- ============================================================

LootFilter_ServerHandlers.ToggleRule = function(player, ruleId)
	if not Validate.IsNonNegativeInt(ruleId, 4294967295) then
		return Validate.Reject(player, "ToggleRule", "ruleId not a non-negative int")
	end
	local guid = player:GetGUIDLow()

	CharDBQuery(string.format(
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

	CharDBQuery(string.format(
		"UPDATE `character_loot_filter_settings` "..
		"SET `filterEnabled` = IF(`filterEnabled`=1, 0, 1) "..
		"WHERE `characterId` = %d", guid))

	SendFilterData(player)
end

-- ============================================================
-- Handler: Update rule priority
-- ============================================================

LootFilter_ServerHandlers.UpdatePriority = function(player, ruleId, newPriority)
	if not Validate.IsNonNegativeInt(ruleId, 4294967295) then
		return Validate.Reject(player, "UpdatePriority", "ruleId not a non-negative int")
	end
	if not Validate.IsIntInRange(newPriority, 0, MAX_PRIORITY) then
		newPriority = 100
	end
	local guid = player:GetGUIDLow()

	CharDBQuery(string.format(
		"UPDATE `character_loot_filter` SET `priority` = %d "..
		"WHERE `ruleId` = %d AND `characterId` = %d",
		newPriority, ruleId, guid))

	SendFilterData(player)
end

-- ============================================================
-- Handler: Update rule (action, priority, group)
-- ============================================================

LootFilter_ServerHandlers.UpdateRule = function(player, ruleId, newAction, newPriority, newGroup)
	if not Validate.IsNonNegativeInt(ruleId, 4294967295) then
		return Validate.Reject(player, "UpdateRule", "ruleId not a non-negative int")
	end
	if not Validate.IsInWhitelist(newAction, ACTIONS) then
		newAction = 1
	end
	if not Validate.IsIntInRange(newPriority, 0, MAX_PRIORITY) then
		newPriority = 100
	end
	if not Validate.IsIntInRange(newGroup, 0, MAX_RULE_GROUP) then
		newGroup = 0
	end
	local guid = player:GetGUIDLow()

	CharDBQuery(string.format(
		"UPDATE `character_loot_filter` SET `action` = %d, `priority` = %d, `ruleGroup` = %d "..
		"WHERE `ruleId` = %d AND `characterId` = %d",
		newAction, newPriority, newGroup, ruleId, guid))

	SendFilterData(player)
end

-- ============================================================
-- Handler: Delete all rules
-- ============================================================

LootFilter_ServerHandlers.DeleteAllRules = function(player)
	local guid = player:GetGUIDLow()

	CharDBQuery(string.format(
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
