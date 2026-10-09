-- =============================================================
-- mod-loot-filter — window (client code shipped by AIO)
--
-- Rules tab: the rules in evaluation order and the editor. Test tab:
-- one item or the whole bags, evaluated by the server without acting.
-- Log tab: this session's actions, lifetime totals, the chat mode.
--
-- The core owns the rules. This window whispers itself addon messages
-- with prefix "LFLT" and reads the answers with prefix "LFLS"; the
-- formats are documented in src/LootFilterRules.h and the design spec
-- (docs/superpowers/specs/2026-10-09-loot-filter-ui-rework-design.md).
-- =============================================================

local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

local LF = {}
LootFilterUI = LF -- global: the command hub and the offline test use it

-- ============================================================
-- Constants
-- ============================================================

local PREFIX_OUT = "LFLT"
local PREFIX_IN = "LFLS"
local MAX_CONDITIONS = 4
local MAX_TEXT = 40
local MAX_LOG = 100
local ANY_SUBCLASS = 255

local ACTIONS = {
	[0] = { label = "Keep", badge = "KEEP", color = "4ce04c", border = { 0.17, 0.43, 0.17 },
		help = "Stays in your bags. Use it to protect items from the rules below." },
	[1] = { label = "Sell", badge = "SELL", color = "ffcc33", border = { 0.48, 0.39, 0.09 },
		help = "You get the vendor price at once." },
	[2] = { label = "Disenchant", badge = "DISENCHANT", color = "c79bff", border = { 0.36, 0.25, 0.53 },
		help = "Materials go to your Endless Storage. Items that cannot be disenchanted are kept." },
	[3] = { label = "Delete", badge = "DELETE", color = "ff5a5a", border = { 0.49, 0.15, 0.15 },
		help = "Destroyed. This cannot be undone." },
	[4] = { label = "To storage", badge = "TO STORAGE", color = "4fd6d6", border = { 0.16, 0.42, 0.42 },
		help = "Trade goods, gems, recipes and stackable food go to the Endless Storage; anything else stays in your bags." },
	[5] = { label = "No rule", badge = "NO RULE", color = "9a9ab0", border = { 0.23, 0.24, 0.33 } },
	[6] = { label = "Protected", badge = "PROTECTED", color = "9a9ab0", border = { 0.23, 0.24, 0.33 } },
}
local ACTION_ORDER = { 0, 4, 1, 2, 3 } -- safe to destructive
local RESULT_NO_RULE = 5
local RESULT_PROTECTED = 6

local COND_QUALITY, COND_ITEM_LEVEL, COND_SELL_PRICE, COND_ITEM_TYPE = 0, 1, 2, 3
local COND_CURSED, COND_ITEM, COND_NAME = 5, 6, 7
local COND_TYPES = {
	{ id = COND_QUALITY, label = "Quality" },
	{ id = COND_ITEM_LEVEL, label = "Item level" },
	{ id = COND_SELL_PRICE, label = "Sell price" },
	{ id = COND_ITEM_TYPE, label = "Type" },
	{ id = COND_CURSED, label = "Cursed" },
	{ id = COND_ITEM, label = "Item" },
	{ id = COND_NAME, label = "Name contains" },
}
local COND_LABEL = {}
for _, t in ipairs(COND_TYPES) do COND_LABEL[t.id] = t.label end

local OP_WORDS = { [0] = "is", [1] = "at least", [2] = "at most" }
local function HasOperator(condType)
	return condType == COND_QUALITY or condType == COND_ITEM_LEVEL or condType == COND_SELL_PRICE
end

local QUALITY_NAMES = { [0] = "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary", "Artifact", "Heirloom" }
local QUALITY_HEX = { [0] = "9d9d9d", "ffffff", "1eff00", "0070dd", "a335ee", "ff8000", "e6cc80", "e6cc80" }

-- Item classes and subclasses of 3.3.5a, in menu order. Quest items are
-- never touched, so class 12 is not offered.
local ITEM_CLASSES = {
	{ id = 2, name = "Weapon", subs = { { 0, "One-Handed Axes" }, { 1, "Two-Handed Axes" }, { 2, "Bows" },
		{ 3, "Guns" }, { 4, "One-Handed Maces" }, { 5, "Two-Handed Maces" }, { 6, "Polearms" },
		{ 7, "One-Handed Swords" }, { 8, "Two-Handed Swords" }, { 10, "Staves" }, { 13, "Fist Weapons" },
		{ 14, "Miscellaneous" }, { 15, "Daggers" }, { 16, "Thrown" }, { 18, "Crossbows" }, { 19, "Wands" },
		{ 20, "Fishing Poles" } } },
	{ id = 4, name = "Armor", subs = { { 0, "Miscellaneous" }, { 1, "Cloth" }, { 2, "Leather" }, { 3, "Mail" },
		{ 4, "Plate" }, { 6, "Shields" }, { 7, "Librams" }, { 8, "Idols" }, { 9, "Totems" }, { 10, "Sigils" } } },
	{ id = 0, name = "Consumable", subs = { { 0, "Consumable" }, { 1, "Potion" }, { 2, "Elixir" }, { 3, "Flask" },
		{ 4, "Scroll" }, { 5, "Food & Drink" }, { 6, "Item Enhancement" }, { 7, "Bandage" }, { 8, "Other" } } },
	{ id = 7, name = "Trade Goods", subs = { { 0, "Trade Goods" }, { 1, "Parts" }, { 2, "Explosives" },
		{ 3, "Devices" }, { 4, "Jewelcrafting" }, { 5, "Cloth" }, { 6, "Leather" }, { 7, "Metal & Stone" },
		{ 8, "Meat" }, { 9, "Herb" }, { 10, "Elemental" }, { 11, "Other" }, { 12, "Enchanting" },
		{ 13, "Materials" }, { 14, "Armor Enchantment" }, { 15, "Weapon Enchantment" } } },
	{ id = 3, name = "Gem", subs = { { 0, "Red" }, { 1, "Blue" }, { 2, "Yellow" }, { 3, "Purple" }, { 4, "Green" },
		{ 5, "Orange" }, { 6, "Meta" }, { 7, "Simple" }, { 8, "Prismatic" } } },
	{ id = 9, name = "Recipe", subs = { { 0, "Book" }, { 1, "Leatherworking" }, { 2, "Tailoring" },
		{ 3, "Engineering" }, { 4, "Blacksmithing" }, { 5, "Cooking" }, { 6, "Alchemy" }, { 7, "First Aid" },
		{ 8, "Enchanting" }, { 9, "Fishing" }, { 10, "Jewelcrafting" }, { 11, "Inscription" } } },
	{ id = 1, name = "Container", subs = { { 0, "Bag" }, { 1, "Soul Bag" }, { 2, "Herb Bag" },
		{ 3, "Enchanting Bag" }, { 4, "Engineering Bag" }, { 5, "Gem Bag" }, { 6, "Mining Bag" },
		{ 7, "Leatherworking Bag" }, { 8, "Inscription Bag" } } },
	{ id = 5, name = "Reagent", subs = {} },
	{ id = 6, name = "Projectile", subs = { { 2, "Arrow" }, { 3, "Bullet" } } },
	{ id = 11, name = "Quiver", subs = { { 2, "Quiver" }, { 3, "Ammo Pouch" } } },
	{ id = 13, name = "Key", subs = {} },
	{ id = 15, name = "Miscellaneous", subs = { { 0, "Junk" }, { 1, "Reagent" }, { 2, "Pet" }, { 3, "Holiday" },
		{ 4, "Other" }, { 5, "Mount" } } },
	{ id = 16, name = "Glyph", subs = {} },
}
local CLASS_NAME, SUB_NAME = {}, {}
for _, c in ipairs(ITEM_CLASSES) do
	CLASS_NAME[c.id] = c.name
	SUB_NAME[c.id] = {}
	for _, s in ipairs(c.subs) do SUB_NAME[c.id][s[1]] = s[2] end
end

local TEMPLATES = {
	{ text = "Sell grey items", action = 1, conds = { { type = COND_QUALITY, op = 0, value = 0 } } },
	{ text = "Sell white armor", action = 1, conds = { { type = COND_QUALITY, op = 0, value = 1 },
		{ type = COND_ITEM_TYPE, op = 0, value = 4, value2 = ANY_SUBCLASS } } },
	{ text = "Sell white weapons", action = 1, conds = { { type = COND_QUALITY, op = 0, value = 1 },
		{ type = COND_ITEM_TYPE, op = 0, value = 2, value2 = ANY_SUBCLASS } } },
	{ text = "Disenchant green items", action = 2, conds = { { type = COND_QUALITY, op = 0, value = 2 } } },
	{ text = "Keep cursed items", action = 0, conds = { { type = COND_CURSED, op = 0, value = 1 } } },
	{ text = "Keep rare and better", action = 0, conds = { { type = COND_QUALITY, op = 1, value = 3 } } },
	{ text = "Store trade goods", action = 4, conds = { { type = COND_ITEM_TYPE, op = 0, value = 7,
		value2 = ANY_SUBCLASS } } },
}

local ERRORS = {
	limit = "You have reached the rule limit.",
	invalid = "The server rejected the rule.",
	action = "That action is switched off on this server.",
	notfound = "That rule no longer exists.",
	busy = "Too many requests at once, wait a moment.",
	noitem = "That bag slot is empty.",
	disabled = "The loot filter is switched off on this server.",
}

-- ============================================================
-- Model
-- ============================================================

local M = {
	enabled = true,
	chatMode = 1,
	maxRules = 30,
	allow = { [0] = true, [1] = true, [2] = true, [3] = true, [4] = true },
	totals = { sold = 0, de = 0, del = 0, stored = 0 },
	session = { soldItems = 0, money = 0, de = 0, stored = 0, del = 0 },
	rules = {},
	incoming = nil,
	log = {},
	test = nil,
	scan = { items = {}, counts = {}, done = false, running = false },
	status = nil,
}
LF.M = M

-- ============================================================
-- Text helpers
-- ============================================================

local function Split(s, sep)
	local parts, start = {}, 1
	while true do
		local i = string.find(s, sep, start, true)
		if not i then
			parts[#parts + 1] = string.sub(s, start)
			return parts
		end
		parts[#parts + 1] = string.sub(s, start, i - 1)
		start = i + 1
	end
end
LF.Split = Split

local function ToUInt(s, max)
	if type(s) ~= "string" or not string.find(s, "^%d+$") or #s > 10 then return nil end
	local v = tonumber(s)
	if not v or v > (max or 4294967295) then return nil end
	return v
end
LF.ToUInt = ToUInt

local function Colored(hex, text)
	return "|cff" .. hex .. text .. "|r"
end

local function QualityText(q)
	return Colored(QUALITY_HEX[q] or "ffffff", QUALITY_NAMES[q] or tostring(q))
end

local function MoneyText(copper)
	copper = math.floor(copper or 0)
	local g = math.floor(copper / 10000)
	local s = math.floor(copper / 100) % 100
	local c = copper % 100
	local parts = {}
	if g > 0 then parts[#parts + 1] = g .. "|cffffd700g|r" end
	if s > 0 then parts[#parts + 1] = s .. "|cffc7c7cfs|r" end
	if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|cffeda55fc|r" end
	return table.concat(parts, " ")
end
LF.MoneyText = MoneyText

local function TypeText(class, sub)
	local name = CLASS_NAME[class] or ("class " .. tostring(class))
	if sub == nil or sub == ANY_SUBCLASS then return name end
	local subName = SUB_NAME[class] and SUB_NAME[class][sub] or ("#" .. tostring(sub))
	return name .. " » " .. subName
end
LF.TypeText = TypeText

local function ItemString(entry, suffix)
	return "item:" .. entry .. ":0:0:0:0:0:" .. (suffix or 0) .. ":0:0"
end

local function ItemText(entry, suffix)
	local _, link = GetItemInfo(ItemString(entry, suffix))
	if link then return link end
	return "item #" .. tostring(entry)
end
LF.ItemText = ItemText

function LF.CondText(c)
	local t = c.type
	if t == COND_QUALITY then
		return "Quality " .. OP_WORDS[c.op] .. " " .. QualityText(c.value)
	elseif t == COND_ITEM_LEVEL then
		return "Item level " .. OP_WORDS[c.op] .. " " .. c.value
	elseif t == COND_SELL_PRICE then
		return "Sell price " .. OP_WORDS[c.op] .. " " .. MoneyText(c.value)
	elseif t == COND_ITEM_TYPE then
		return "Type is " .. TypeText(c.value, c.value2)
	elseif t == COND_CURSED then
		return c.value == 1 and ("Item is " .. Colored("c79bff", "cursed")) or "Item is not cursed"
	elseif t == COND_ITEM then
		return "Item is " .. ItemText(c.value)
	elseif t == COND_NAME then
		return 'Name contains "' .. (c.text or "") .. '"'
	end
	return "?"
end

function LF.RuleText(rule)
	local parts = {}
	for i, c in ipairs(rule.conds) do parts[i] = LF.CondText(c) end
	return table.concat(parts, " " .. Colored("8c8ca8", "and") .. " ")
end

function LF.Badge(code)
	local a = ACTIONS[code]
	if not a then return "?" end
	return Colored(a.color, a.badge)
end

-- ============================================================
-- Codec (mirror of LootFilterRules.h)
-- ============================================================

function LF.EncodeCond(c)
	return c.type .. ":" .. c.op .. ":" .. (c.value or 0) .. ":" .. (c.value2 or 0) .. ":" .. (c.text or "")
end

function LF.EncodeRule(r)
	local conds = {}
	for i, c in ipairs(r.conds) do conds[i] = LF.EncodeCond(c) end
	return r.id .. "|" .. (r.position or 0) .. "|" .. r.action .. "|" .. (r.enabled and 1 or 0) .. "|"
		.. table.concat(conds, ";")
end

function LF.DecodeCond(s)
	local f = Split(s, ":")
	if #f ~= 5 then return nil end
	local c = { type = ToUInt(f[1], 255), op = ToUInt(f[2], 255), value = ToUInt(f[3]),
		value2 = ToUInt(f[4]), text = f[5] }
	if not (c.type and c.op and c.value and c.value2) then return nil end
	return c
end

-- f = the message split by "|"; the five rule fields start at f[i].
function LF.DecodeRule(f, i)
	if #f < i + 4 then return nil end
	local r = { id = ToUInt(f[i]), position = ToUInt(f[i + 1], 255), action = ToUInt(f[i + 2], 255),
		enabled = f[i + 3] == "1", conds = {} }
	if not (r.id and r.position and r.action) or (f[i + 3] ~= "0" and f[i + 3] ~= "1") then return nil end
	if f[i + 4] == "" then return nil end
	for _, part in ipairs(Split(f[i + 4], ";")) do
		local c = LF.DecodeCond(part)
		if not c then return nil end
		r.conds[#r.conds + 1] = c
	end
	if #r.conds > MAX_CONDITIONS then return nil end
	return r
end

-- ============================================================
-- Validation (the server checks again)
-- ============================================================

local function ValidText(s)
	return type(s) == "string" and #s >= 1 and #s <= MAX_TEXT and string.find(s, "^[%w '%-%.,]+$") ~= nil
end
LF.ValidText = ValidText

function LF.CondProblem(c)
	local t = c.type
	if t == COND_QUALITY then
		if c.value < 0 or c.value > 7 then return "Pick a quality." end
	elseif t == COND_ITEM_LEVEL then
		if not c.value or c.value < 0 or c.value > 65535 then return "Item level must be a number from 0 to 65535." end
	elseif t == COND_SELL_PRICE then
		if not c.value or c.value < 0 then return "Enter a sell price." end
		if c.value > 4294967295 then return "That sell price is too high." end
	elseif t == COND_ITEM_TYPE then
		if not CLASS_NAME[c.value] then return "Pick a type." end
	elseif t == COND_CURSED then
		if c.value ~= 0 and c.value ~= 1 then return "Pick cursed or not cursed." end
	elseif t == COND_ITEM then
		if not c.value or c.value < 1 then return "Pick an item: Shift-click it or drop it on the box." end
	elseif t == COND_NAME then
		local s = c.text or ""
		if s == "" then return "Enter part of a name." end
		if #s > MAX_TEXT then return "A name part has at most 40 characters." end
		if not ValidText(s) then return "Names may use letters, digits, spaces and ' - . , only." end
	else
		return "Pick a condition."
	end
	return nil
end

function LF.RuleProblem(rule)
	if #rule.conds < 1 then return "Add at least one condition." end
	if #rule.conds > MAX_CONDITIONS then return "A rule has at most four conditions." end
	for _, c in ipairs(rule.conds) do
		local problem = LF.CondProblem(c)
		if problem then return problem end
	end
	if not ACTIONS[rule.action] or rule.action > 4 then return "Pick what happens." end
	if not M.allow[rule.action] then return ERRORS.action end
	return nil
end

-- ============================================================
-- Transport
-- ============================================================

function LF.Send(payload)
	SendAddonMessage(PREFIX_OUT, payload, "WHISPER", UnitName("player"))
end

local Refresh -- forward: redraws whatever is visible

local function SetStatus(text)
	M.status = text
	M.statusTime = GetTime and GetTime() or 0
	if Refresh then Refresh() end
end
LF.SetStatus = SetStatus

local function AddLog(entry)
	table.insert(M.log, 1, entry)
	while #M.log > MAX_LOG do table.remove(M.log) end
end

function LF.OnMessage(msg)
	local f = Split(msg, "|")
	local kind = f[1]
	if kind == "I" and #f == 11 then
		M.enabled = f[2] == "1"
		M.chatMode = ToUInt(f[3], 2) or 1
		M.maxRules = ToUInt(f[4], 255) or 30
		M.allow[1] = f[5] == "1"
		M.allow[2] = f[6] == "1"
		M.allow[3] = f[7] == "1"
		M.totals.sold = tonumber(f[8]) or 0
		M.totals.de = tonumber(f[9]) or 0
		M.totals.del = tonumber(f[10]) or 0
		M.totals.stored = tonumber(f[11]) or 0
	elseif kind == "R" then
		local rule = LF.DecodeRule(f, 2)
		if rule then
			M.incoming = M.incoming or {}
			M.incoming[#M.incoming + 1] = rule
		end
	elseif kind == "N" then
		M.rules = M.incoming or {}
		M.incoming = nil
		table.sort(M.rules, function(a, b) return a.position < b.position end)
	elseif kind == "T" and #f == 5 then
		M.test = { bag = tonumber(f[2]), slot = tonumber(f[3]), result = tonumber(f[4]),
			position = tonumber(f[5]) }
	elseif kind == "S" and #f == 5 then
		local result = tonumber(f[4])
		M.scan.items[#M.scan.items + 1] = { bag = tonumber(f[2]), slot = tonumber(f[3]), result = result,
			position = tonumber(f[5]) }
		M.scan.counts[result] = (M.scan.counts[result] or 0) + 1
	elseif kind == "Z" then
		M.scan.done = true
		M.scan.running = false
	elseif kind == "L" and #f == 8 then
		local entry = { time = date("%H:%M:%S"), action = tonumber(f[2]), entry = tonumber(f[3]),
			suffix = tonumber(f[4]) or 0, count = tonumber(f[5]) or 1, money = tonumber(f[6]) or 0,
			position = tonumber(f[7]) or 0, mats = {} }
		if f[8] ~= "" then
			for _, m in ipairs(Split(f[8], ",")) do
				local mf = Split(m, ":")
				entry.mats[#entry.mats + 1] = { tonumber(mf[1]), tonumber(mf[2]) or 1 }
			end
		end
		AddLog(entry)
		local s, t = M.session, M.totals
		if entry.action == 1 then
			s.soldItems = s.soldItems + entry.count
			s.money = s.money + entry.money
			t.sold = t.sold + entry.money
		elseif entry.action == 2 then
			s.de = s.de + 1
			t.de = t.de + 1
		elseif entry.action == 3 then
			s.del = s.del + entry.count
			t.del = t.del + entry.count
		elseif entry.action == 4 then
			s.stored = s.stored + entry.count
			t.stored = t.stored + entry.count
		end
	elseif kind == "F" then
		M.enabled = f[2] == "1"
	elseif kind == "!" then
		local code = f[2] or ""
		SetStatus(ERRORS[code] or ("Error: " .. code))
		if code == "notfound" then LF.Send("G") end
		return
	end
	if Refresh then Refresh() end
end

-- ============================================================
-- Frame helpers
-- ============================================================

local BACKDROP = {
	bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
	edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
	tile = true, tileSize = 16, edgeSize = 16,
	insets = { left = 4, right = 4, top = 4, bottom = 4 },
}
local PANEL_BACKDROP = {
	bgFile = "Interface\\Buttons\\WHITE8x8",
	edgeFile = "Interface\\Buttons\\WHITE8x8",
	edgeSize = 1,
	insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local function Panel(parent)
	local f = CreateFrame("Frame", nil, parent)
	f:SetBackdrop(PANEL_BACKDROP)
	f:SetBackdropColor(0.04, 0.04, 0.09, 0.9)
	f:SetBackdropBorderColor(0.18, 0.2, 0.38, 1)
	return f
end

local function Text(parent, font, justify)
	local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
	fs:SetJustifyH(justify or "LEFT")
	return fs
end

local function Button(parent, label, width, height)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width or 90, height or 22)
	b:SetText(label)
	return b
end

local function Tooltip(frame, title, line)
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(title, 1, 0.82, 0)
		if line then GameTooltip:AddLine(line, 0.8, 0.8, 0.8, true) end
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function IconButton(parent, texture, tip)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(20, 20)
	b:SetNormalTexture(texture .. "-Up")
	b:SetPushedTexture(texture .. "-Down")
	b:SetDisabledTexture(texture .. "-Disabled")
	b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	Tooltip(b, tip)
	return b
end

local function BadgeFrame(parent, width)
	local f = CreateFrame("Frame", nil, parent)
	f:SetSize(width or 84, 18)
	f:SetBackdrop(PANEL_BACKDROP)
	f:SetBackdropColor(0, 0, 0, 0)
	f.text = Text(f, "GameFontNormalSmall", "CENTER")
	f.text:SetPoint("CENTER", 0, 0)
	function f:SetCode(code)
		local a = ACTIONS[code] or ACTIONS[RESULT_NO_RULE]
		self.text:SetText(Colored(a.color, a.badge))
		self:SetBackdropBorderColor(a.border[1], a.border[2], a.border[3], 1)
	end
	return f
end

local function Dropdown(name, parent, width)
	local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
	UIDropDownMenu_SetWidth(dd, width)
	return dd
end

-- ============================================================
-- Main window
-- ============================================================

local FRAME_W, FRAME_H = 640, 520

local main = CreateFrame("Frame", "LootFilterFrame", UIParent)
main:SetSize(FRAME_W, FRAME_H)
main:SetPoint("CENTER", 0, 40)
main:SetBackdrop(BACKDROP)
main:SetBackdropColor(0.05, 0.05, 0.11, 0.97)
main:SetBackdropBorderColor(0.33, 0.35, 0.54, 1)
main:SetFrameStrata("HIGH")
main:SetToplevel(true)
main:EnableMouse(true)
main:SetMovable(true)
main:SetClampedToScreen(true)
main:RegisterForDrag("LeftButton")
main:SetScript("OnDragStart", main.StartMoving)
main:SetScript("OnDragStop", main.StopMovingOrSizing)
main:Hide()
tinsert(UISpecialFrames, "LootFilterFrame")
LF.frame = main
if AIO.SavePosition then AIO.SavePosition(main, true) end

local icon = main:CreateTexture(nil, "ARTWORK")
icon:SetSize(24, 24)
icon:SetPoint("TOPLEFT", 14, -10)
icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_SatchelofCenarius")

local title = Text(main, "GameFontNormalLarge")
title:SetPoint("LEFT", icon, "RIGHT", 8, 0)
title:SetText("Loot Filter")

local closeBtn = CreateFrame("Button", nil, main, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)

local filterBox = CreateFrame("CheckButton", "LootFilterEnabledBox", main, "UICheckButtonTemplate")
filterBox:SetSize(24, 24)
filterBox:SetPoint("RIGHT", closeBtn, "LEFT", -76, 0)
local filterText = Text(main, "GameFontHighlight")
filterText:SetPoint("LEFT", filterBox, "RIGHT", 2, 1)
filterText:SetText("Filter on")
filterBox:SetScript("OnClick", function(self)
	local on = self:GetChecked() and true or false
	M.enabled = on
	LF.Send(on and "F|1" or "F|0")
	Refresh()
end)
Tooltip(filterBox, "Filter on", "When off, looted items are left alone.")

-- Tabs
local TAB_NAMES = { "Rules", "Test", "Log" }
local tabs, panels = {}, {}
LF.tabs, LF.panels = tabs, panels
local activeTab = 1

local function SelectTab(index)
	activeTab = index
	for i, p in ipairs(panels) do
		if i == index then p:Show() else p:Hide() end
	end
	for i, t in ipairs(tabs) do
		if i == index then t:LockHighlight() else t:UnlockHighlight() end
	end
	Refresh()
end
LF.SelectTab = SelectTab

for i, name in ipairs(TAB_NAMES) do
	local t = Button(main, name, 90, 24)
	t:SetPoint("TOPLEFT", 14 + (i - 1) * 94, -42)
	t:SetScript("OnClick", function() SelectTab(i) end)
	tabs[i] = t
	local p = CreateFrame("Frame", nil, main)
	p:SetPoint("TOPLEFT", 12, -70)
	p:SetPoint("BOTTOMRIGHT", -12, 12)
	p:Hide()
	panels[i] = p
end

local countText = Text(main, "GameFontDisableSmall", "RIGHT")
countText:SetPoint("TOPRIGHT", -18, -50)

local statusText = Text(main, "GameFontRedSmall", "RIGHT")
statusText:SetPoint("BOTTOMRIGHT", -18, 16)
statusText:SetWidth(330)

-- ============================================================
-- Rules tab
-- ============================================================

local rulesPanel = panels[1]
local ROW_H, VISIBLE_RULES = 34, 8

local rulesHint = Text(rulesPanel, "GameFontDisableSmall")
rulesHint:SetPoint("TOPLEFT", 2, -2)
rulesHint:SetText("Checked from top to bottom. The first rule that matches decides. Quest items are never touched.")

local listBox = Panel(rulesPanel)
listBox:SetPoint("TOPLEFT", 0, -18)
listBox:SetPoint("TOPRIGHT", 0, -18)
listBox:SetHeight(VISIBLE_RULES * ROW_H + 30)

local ruleScroll = CreateFrame("ScrollFrame", "LootFilterRuleScroll", listBox, "FauxScrollFrameTemplate")
ruleScroll:SetPoint("TOPLEFT", 2, -2)
ruleScroll:SetPoint("BOTTOMRIGHT", -24, 28)

local emptyText = Text(listBox, "GameFontDisable", "CENTER")
emptyText:SetPoint("CENTER", 0, 10)
emptyText:SetText("No rules yet. Start with \"New rule\" or a template.")

local endText = Text(listBox, "GameFontDisableSmall", "CENTER")
endText:SetPoint("BOTTOM", 0, 8)
endText:SetText("No rule matches: the item stays in your bags.")

local ruleRows = {}
LF.ruleRows = ruleRows

local function ConfirmDelete(rule)
	StaticPopupDialogs["LOOTFILTER_DELETE_RULE"] = {
		text = "Delete rule %s?",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function(self, data) LF.Send("D|" .. data) end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	local dialog = StaticPopup_Show("LOOTFILTER_DELETE_RULE", tostring(rule.position))
	if dialog then dialog.data = rule.id end
end

for i = 1, VISIBLE_RULES do
	local row = CreateFrame("Button", nil, listBox)
	row:SetHeight(ROW_H)
	row:SetPoint("TOPLEFT", 2, -2 - (i - 1) * ROW_H)
	row:SetPoint("TOPRIGHT", -24, -2 - (i - 1) * ROW_H)
	local bg = row:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0.0)
	local hl = row:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetTexture(0.3, 0.35, 0.7, 0.18)

	row.num = Text(row, "GameFontNormal", "RIGHT")
	row.num:SetPoint("LEFT", 2, 0)
	row.num:SetWidth(18)

	row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
	row.check:SetSize(22, 22)
	row.check:SetPoint("LEFT", 22, 0)
	Tooltip(row.check, "On / off", "An unchecked rule is skipped.")

	row.cond = Text(row, "GameFontHighlightSmall")
	row.cond:SetPoint("LEFT", 48, 0)
	row.cond:SetWidth(312)
	row.cond:SetHeight(ROW_H - 4)
	row.cond:SetJustifyV("MIDDLE")

	row.badge = BadgeFrame(row, 84)
	row.badge:SetPoint("LEFT", 364, 0)

	row.up = IconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton", "Move up")
	row.up:SetPoint("LEFT", 452, 0)
	row.down = IconButton(row, "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton", "Move down")
	row.down:SetPoint("LEFT", row.up, "RIGHT", 0, 0)
	row.edit = IconButton(row, "Interface\\Buttons\\UI-GuildButton-PublicNote", "Edit")
	row.edit:SetPoint("LEFT", row.down, "RIGHT", 4, 0)
	row.del = IconButton(row, "Interface\\Buttons\\UI-GroupLoot-Pass", "Delete")
	row.del:SetPoint("LEFT", row.edit, "RIGHT", 4, 0)

	row.check:SetScript("OnClick", function(self)
		if row.rule then
			LF.Send("E|" .. row.rule.id .. "|" .. (self:GetChecked() and "1" or "0"))
		end
	end)
	row.up:SetScript("OnClick", function()
		if row.rule and row.rule.position > 1 then
			LF.Send("M|" .. row.rule.id .. "|" .. (row.rule.position - 1))
		end
	end)
	row.down:SetScript("OnClick", function()
		if row.rule and row.rule.position < #M.rules then
			LF.Send("M|" .. row.rule.id .. "|" .. (row.rule.position + 1))
		end
	end)
	row.edit:SetScript("OnClick", function()
		if row.rule then LF.OpenEditor(row.rule) end
	end)
	row:SetScript("OnDoubleClick", function()
		if row.rule then LF.OpenEditor(row.rule) end
	end)
	row:SetScript("OnEnter", function(self)
		if not self.rule then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOPLEFT")
		GameTooltip:AddLine("Rule " .. self.rule.position .. ": " .. LF.Badge(self.rule.action), 1, 0.82, 0)
		GameTooltip:AddLine(LF.RuleText(self.rule), 1, 1, 1, true)
		GameTooltip:AddLine("Double-click to edit.", 0.5, 0.5, 0.5)
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", function() GameTooltip:Hide() end)
	row.del:SetScript("OnClick", function()
		if row.rule then ConfirmDelete(row.rule) end
	end)
	ruleRows[i] = row
end

local newBtn = Button(rulesPanel, "+ New rule", 100, 24)
newBtn:SetPoint("TOPLEFT", listBox, "BOTTOMLEFT", 0, -8)
newBtn:SetScript("OnClick", function() LF.OpenEditor(nil) end)

local templateMenu = CreateFrame("Frame", "LootFilterTemplateMenu", main, "UIDropDownMenuTemplate")
local templateBtn = Button(rulesPanel, "Templates", 100, 24)
templateBtn:SetPoint("LEFT", newBtn, "RIGHT", 6, 0)
templateBtn:SetScript("OnClick", function(self)
	local menu = { { text = "Start a rule from a template", isTitle = true, notCheckable = true } }
	for i, t in ipairs(TEMPLATES) do
		menu[#menu + 1] = { text = t.text, notCheckable = true, func = function() LF.OpenTemplate(i) end }
	end
	EasyMenu(menu, templateMenu, self, 0, 0, "MENU")
end)

local clearBtn = Button(rulesPanel, "Clear all", 90, 24)
clearBtn:SetPoint("TOPRIGHT", listBox, "BOTTOMRIGHT", 0, -8)
clearBtn:SetScript("OnClick", function()
	StaticPopupDialogs["LOOTFILTER_CLEAR"] = {
		text = "Delete ALL loot filter rules?",
		button1 = YES or "Yes",
		button2 = NO or "No",
		OnAccept = function() LF.Send("X") end,
		timeout = 0, whileDead = true, hideOnEscape = true,
	}
	StaticPopup_Show("LOOTFILTER_CLEAR")
end)

local sessionText = Text(rulesPanel, "GameFontDisableSmall")
sessionText:SetPoint("TOPLEFT", newBtn, "BOTTOMLEFT", 2, -8)
sessionText:SetWidth(600)

local function UpdateRuleList()
	local n = #M.rules
	FauxScrollFrame_Update(ruleScroll, n, VISIBLE_RULES, ROW_H)
	local offset = FauxScrollFrame_GetOffset(ruleScroll)
	for i, row in ipairs(ruleRows) do
		local rule = M.rules[offset + i]
		row.rule = rule
		if rule then
			row.num:SetText(rule.position)
			row.check:SetChecked(rule.enabled and 1 or nil)
			row.cond:SetText(LF.RuleText(rule))
			row.cond:SetAlpha(rule.enabled and 1 or 0.45)
			row.badge:SetCode(rule.action)
			row.badge:SetAlpha(rule.enabled and 1 or 0.45)
			if rule.position > 1 then row.up:Enable() else row.up:Disable() end
			if rule.position < n then row.down:Enable() else row.down:Disable() end
			row:Show()
		else
			row:Hide()
		end
	end
	if n == 0 then emptyText:Show() else emptyText:Hide() end
	local s = M.session
	sessionText:SetText(string.format("This session: %d sold for %s  ·  %d disenchanted  ·  %d stored  ·  %d deleted",
		s.soldItems, MoneyText(s.money), s.de, s.stored, s.del))
	if n >= M.maxRules then newBtn:Disable() else newBtn:Enable() end
end

ruleScroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, UpdateRuleList)
end)

-- ============================================================
-- Editor (replaces the list in the Rules tab)
-- ============================================================

local editor = Panel(rulesPanel)
editor:SetPoint("TOPLEFT", 0, 0)
editor:SetPoint("BOTTOMRIGHT", 0, 0)
editor:SetBackdropColor(0.04, 0.04, 0.09, 1)
editor:SetFrameLevel(rulesPanel:GetFrameLevel() + 10)
editor:EnableMouse(true)
editor:Hide()
LF.editorFrame = editor

local E = { rule = nil } -- the rule being edited
LF.E = E

local editorTitle = Text(editor, "GameFontNormalLarge")
editorTitle:SetPoint("TOPLEFT", 12, -12)

local posLabel = Text(editor, "GameFontDisableSmall")
local posDropdown = Dropdown("LootFilterPositionDropdown", editor, 50)
posDropdown:SetPoint("TOPRIGHT", -40, -6)
posLabel:SetPoint("RIGHT", posDropdown, "LEFT", 12, 2)
posLabel:SetText("Position")
local posOf = Text(editor, "GameFontDisableSmall")
posOf:SetPoint("LEFT", posDropdown, "RIGHT", -12, 2)

local whenText = Text(editor, "GameFontNormal")
whenText:SetPoint("TOPLEFT", 12, -44)
whenText:SetText("When an item matches all of these:")

local condRows = {}
LF.condRows = condRows

local function DefaultCond(condType)
	if condType == COND_QUALITY then return { type = condType, op = 0, value = 2, value2 = 0, text = "" } end
	if condType == COND_ITEM_LEVEL then return { type = condType, op = 2, value = 100, value2 = 0, text = "" } end
	if condType == COND_SELL_PRICE then return { type = condType, op = 2, value = 100, value2 = 0, text = "" } end
	if condType == COND_ITEM_TYPE then
		return { type = condType, op = 0, value = 4, value2 = ANY_SUBCLASS, text = "" }
	end
	if condType == COND_CURSED then return { type = condType, op = 0, value = 1, value2 = 0, text = "" } end
	if condType == COND_ITEM then return { type = condType, op = 0, value = 0, value2 = 0, text = "" } end
	return { type = COND_NAME, op = 0, value = 0, value2 = 0, text = "" }
end
LF.DefaultCond = DefaultCond

local RenderEditor -- forward

local function ItemIdFromLink(link)
	if type(link) ~= "string" then return nil end
	local id = string.match(link, "item:(%d+)")
	return id and tonumber(id) or nil
end
LF.ItemIdFromLink = ItemIdFromLink

for i = 1, MAX_CONDITIONS do
	local row = CreateFrame("Frame", nil, editor)
	row:SetSize(590, 28)
	row:SetPoint("TOPLEFT", 4, -60 - (i - 1) * 30)
	row.index = i

	row.typeDD = Dropdown("LootFilterCondType" .. i, row, 110)
	row.typeDD:SetPoint("LEFT", -8, 0)
	row.opDD = Dropdown("LootFilterCondOp" .. i, row, 80)
	row.opDD:SetPoint("LEFT", row.typeDD, "RIGHT", -26, 0)
	row.valueDD = Dropdown("LootFilterCondValue" .. i, row, 160)
	row.valueDD:SetPoint("LEFT", row.opDD, "RIGHT", -26, 0)

	row.number = CreateFrame("EditBox", "LootFilterCondNumber" .. i, row, "InputBoxTemplate")
	row.number:SetSize(70, 20)
	row.number:SetPoint("LEFT", row.opDD, "RIGHT", -6, 2)
	row.number:SetAutoFocus(false)
	row.number:SetNumeric(true)
	row.number:SetMaxLetters(5)

	row.gold = CreateFrame("EditBox", "LootFilterCondGold" .. i, row, "InputBoxTemplate")
	row.gold:SetSize(44, 20)
	row.gold:SetPoint("LEFT", row.opDD, "RIGHT", -6, 2)
	row.gold:SetAutoFocus(false)
	row.gold:SetNumeric(true)
	row.gold:SetMaxLetters(6)
	row.goldLabel = Text(row, "GameFontHighlightSmall")
	row.goldLabel:SetPoint("LEFT", row.gold, "RIGHT", 2, 0)
	row.goldLabel:SetText("|cffffd700g|r")
	row.silver = CreateFrame("EditBox", "LootFilterCondSilver" .. i, row, "InputBoxTemplate")
	row.silver:SetSize(26, 20)
	row.silver:SetPoint("LEFT", row.goldLabel, "RIGHT", 8, 0)
	row.silver:SetAutoFocus(false)
	row.silver:SetNumeric(true)
	row.silver:SetMaxLetters(2)
	row.silverLabel = Text(row, "GameFontHighlightSmall")
	row.silverLabel:SetPoint("LEFT", row.silver, "RIGHT", 2, 0)
	row.silverLabel:SetText("|cffc7c7cfs|r")
	row.copper = CreateFrame("EditBox", "LootFilterCondCopper" .. i, row, "InputBoxTemplate")
	row.copper:SetSize(26, 20)
	row.copper:SetPoint("LEFT", row.silverLabel, "RIGHT", 8, 0)
	row.copper:SetAutoFocus(false)
	row.copper:SetNumeric(true)
	row.copper:SetMaxLetters(2)
	row.copperLabel = Text(row, "GameFontHighlightSmall")
	row.copperLabel:SetPoint("LEFT", row.copper, "RIGHT", 2, 0)
	row.copperLabel:SetText("|cffeda55fc|r")

	row.textBox = CreateFrame("EditBox", "LootFilterCondText" .. i, row, "InputBoxTemplate")
	row.textBox:SetSize(220, 20)
	row.textBox:SetPoint("LEFT", row.typeDD, "RIGHT", -6, 2)
	row.textBox:SetAutoFocus(false)
	row.textBox:SetMaxLetters(MAX_TEXT)

	row.itemBox = CreateFrame("EditBox", "LootFilterCondItem" .. i, row, "InputBoxTemplate")
	row.itemBox:SetSize(220, 20)
	row.itemBox:SetPoint("LEFT", row.typeDD, "RIGHT", -6, 2)
	row.itemBox:SetAutoFocus(false)
	row.itemBox:SetScript("OnChar", function(self)
		-- The box only shows the picked item; typing is not supported.
		local c = E.rule and E.rule.conds[i]
		self:SetText(c and c.value > 0 and ItemText(c.value) or "")
	end)
	row.itemBox:SetScript("OnReceiveDrag", function(self)
		local kind, id = GetCursorInfo()
		if kind == "item" and E.rule and E.rule.conds[i] then
			E.rule.conds[i].value = tonumber(id) or 0
			ClearCursor()
			RenderEditor()
		end
	end)
	row.itemBox:SetScript("OnMouseDown", function(self)
		local kind, id = GetCursorInfo()
		if kind == "item" and E.rule and E.rule.conds[i] then
			E.rule.conds[i].value = tonumber(id) or 0
			ClearCursor()
			RenderEditor()
		end
	end)
	Tooltip(row.itemBox, "Item", "Click into the box and Shift-click an item, or drop an item on it.")

	row.remove = IconButton(row, "Interface\\Buttons\\UI-GroupLoot-Pass", "Remove condition")
	row.remove:SetPoint("RIGHT", -8, 0)
	row.remove:SetScript("OnClick", function()
		if E.rule and #E.rule.conds > 1 then
			table.remove(E.rule.conds, i)
			RenderEditor()
		end
	end)

	-- Inputs write straight into the edited condition.
	row.number:SetScript("OnTextChanged", function(self, user)
		local c = E.rule and E.rule.conds[i]
		if user and c and c.type == COND_ITEM_LEVEL then c.value = tonumber(self:GetText()) or -1 end
	end)
	local function PriceChanged(_, user)
		local c = E.rule and E.rule.conds[i]
		if user and c and c.type == COND_SELL_PRICE then
			c.value = (tonumber(row.gold:GetText()) or 0) * 10000 + (tonumber(row.silver:GetText()) or 0) * 100
				+ (tonumber(row.copper:GetText()) or 0)
		end
	end
	row.gold:SetScript("OnTextChanged", PriceChanged)
	row.silver:SetScript("OnTextChanged", PriceChanged)
	row.copper:SetScript("OnTextChanged", PriceChanged)
	row.textBox:SetScript("OnTextChanged", function(self, user)
		local c = E.rule and E.rule.conds[i]
		if user and c and c.type == COND_NAME then c.text = self:GetText() end
	end)
	for _, box in ipairs({ row.number, row.gold, row.silver, row.copper, row.textBox, row.itemBox }) do
		box:SetScript("OnEscapePressed", box.ClearFocus)
		box:SetScript("OnEnterPressed", box.ClearFocus)
	end

	condRows[i] = row
end

-- Dropdown contents, built on open from the row's current condition.
local function InitTypeDropdown(dd, i)
	UIDropDownMenu_Initialize(dd, function()
		for _, t in ipairs(COND_TYPES) do
			local info = UIDropDownMenu_CreateInfo()
			info.text = t.label
			info.checked = E.rule and E.rule.conds[i] and E.rule.conds[i].type == t.id
			info.func = function()
				E.rule.conds[i] = DefaultCond(t.id)
				RenderEditor()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
end

local function InitOpDropdown(dd, i)
	UIDropDownMenu_Initialize(dd, function()
		local c = E.rule and E.rule.conds[i]
		if not c then return end
		for op = 0, 2 do
			local info = UIDropDownMenu_CreateInfo()
			info.text = OP_WORDS[op]
			info.checked = c.op == op
			info.func = function()
				c.op = op
				RenderEditor()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)
end

local function InitValueDropdown(dd, i)
	UIDropDownMenu_Initialize(dd, function()
		local c = E.rule and E.rule.conds[i]
		if not c then return end
		local level = UIDROPDOWNMENU_MENU_LEVEL or 1
		if c.type == COND_QUALITY then
			for q = 0, 7 do
				local info = UIDropDownMenu_CreateInfo()
				info.text = QualityText(q)
				info.checked = c.value == q
				info.func = function()
					c.value = q
					RenderEditor()
				end
				UIDropDownMenu_AddButton(info)
			end
		elseif c.type == COND_CURSED then
			for _, v in ipairs({ { 1, "Cursed" }, { 0, "Not cursed" } }) do
				local info = UIDropDownMenu_CreateInfo()
				info.text = v[2]
				info.checked = c.value == v[1]
				info.func = function()
					c.value = v[1]
					RenderEditor()
				end
				UIDropDownMenu_AddButton(info)
			end
		elseif c.type == COND_ITEM_TYPE then
			if level == 1 then
				for _, class in ipairs(ITEM_CLASSES) do
					local info = UIDropDownMenu_CreateInfo()
					info.text = class.name
					info.checked = c.value == class.id
					info.hasArrow = #class.subs > 0
					info.value = class.id
					info.func = function()
						c.value = class.id
						c.value2 = ANY_SUBCLASS
						CloseDropDownMenus()
						RenderEditor()
					end
					UIDropDownMenu_AddButton(info, 1)
				end
			else
				local classId = UIDROPDOWNMENU_MENU_VALUE
				local any = UIDropDownMenu_CreateInfo()
				any.text = "Any " .. (CLASS_NAME[classId] or "")
				any.checked = c.value == classId and c.value2 == ANY_SUBCLASS
				any.func = function()
					c.value = classId
					c.value2 = ANY_SUBCLASS
					CloseDropDownMenus()
					RenderEditor()
				end
				UIDropDownMenu_AddButton(any, 2)
				for _, class in ipairs(ITEM_CLASSES) do
					if class.id == classId then
						for _, s in ipairs(class.subs) do
							local info = UIDropDownMenu_CreateInfo()
							info.text = s[2]
							info.checked = c.value == classId and c.value2 == s[1]
							info.func = function()
								c.value = classId
								c.value2 = s[1]
								CloseDropDownMenus()
								RenderEditor()
							end
							UIDropDownMenu_AddButton(info, 2)
						end
					end
				end
			end
		end
	end)
end

for i, row in ipairs(condRows) do
	InitTypeDropdown(row.typeDD, i)
	InitOpDropdown(row.opDD, i)
	InitValueDropdown(row.valueDD, i)
end

local addCondBtn = Button(editor, "+ Add condition", 120, 20)
addCondBtn:SetPoint("TOPLEFT", 14, -60 - MAX_CONDITIONS * 30 - 2)
addCondBtn:SetScript("OnClick", function()
	if E.rule and #E.rule.conds < MAX_CONDITIONS then
		E.rule.conds[#E.rule.conds + 1] = DefaultCond(COND_QUALITY)
		RenderEditor()
	end
end)
local addCondHint = Text(editor, "GameFontDisableSmall")
addCondHint:SetPoint("LEFT", addCondBtn, "RIGHT", 8, 0)
addCondHint:SetText("up to 4, all must match")

local thenText = Text(editor, "GameFontNormal")
thenText:SetPoint("TOPLEFT", 12, -60 - MAX_CONDITIONS * 30 - 32)
thenText:SetText("Then:")

local actionRadios = {}
LF.actionRadios = actionRadios
for i, code in ipairs(ACTION_ORDER) do
	local a = ACTIONS[code]
	local radio = CreateFrame("CheckButton", "LootFilterAction" .. code, editor, "UIRadioButtonTemplate")
	radio:SetPoint("TOPLEFT", 18, -60 - MAX_CONDITIONS * 30 - 50 - (i - 1) * 20)
	radio.code = code
	radio.label = Text(editor, "GameFontHighlight")
	radio.label:SetPoint("LEFT", radio, "RIGHT", 4, 0)
	radio.label:SetWidth(84)
	radio.help = Text(editor, "GameFontDisableSmall")
	radio.help:SetPoint("LEFT", radio.label, "RIGHT", 4, 0)
	radio.help:SetWidth(470)
	radio.help:SetText(a.help)
	radio:SetScript("OnClick", function()
		if E.rule then E.rule.action = code end
		RenderEditor()
	end)
	actionRadios[code] = radio
end

local editorError = Text(editor, "GameFontRedSmall")
editorError:SetPoint("BOTTOMLEFT", 14, 14)
editorError:SetWidth(380)

local saveBtn = Button(editor, "Save rule", 100, 24)
saveBtn:SetPoint("BOTTOMRIGHT", -12, 10)
local cancelBtn = Button(editor, "Cancel", 90, 24)
cancelBtn:SetPoint("RIGHT", saveBtn, "LEFT", -6, 0)
cancelBtn:SetScript("OnClick", function() LF.CloseEditor() end)
saveBtn:SetScript("OnClick", function() LF.SaveEditor() end)

local function ShowOnly(row, widgets)
	for _, w in ipairs({ row.opDD, row.valueDD, row.number, row.gold, row.goldLabel, row.silver,
		row.silverLabel, row.copper, row.copperLabel, row.textBox, row.itemBox }) do
		w:Hide()
	end
	for _, w in ipairs(widgets) do w:Show() end
end

RenderEditor = function()
	local rule = E.rule
	if not rule then return end
	local n = #M.rules
	local last = rule.id == 0 and (n + 1) or n
	editorTitle:SetText(rule.id == 0 and "New rule" or ("Edit rule " .. rule.position))
	UIDropDownMenu_SetText(posDropdown, tostring(rule.position))
	posOf:SetText("of " .. last)
	UIDropDownMenu_Initialize(posDropdown, function()
		for p = 1, last do
			local info = UIDropDownMenu_CreateInfo()
			info.text = tostring(p)
			info.checked = rule.position == p
			info.func = function()
				rule.position = p
				RenderEditor()
			end
			UIDropDownMenu_AddButton(info)
		end
	end)

	for i, row in ipairs(condRows) do
		local c = rule.conds[i]
		if c then
			row:Show()
			UIDropDownMenu_SetText(row.typeDD, COND_LABEL[c.type] or "?")
			UIDropDownMenu_SetText(row.opDD, c.type == COND_NAME and "contains" or OP_WORDS[c.op])
			if c.type == COND_QUALITY then
				ShowOnly(row, { row.opDD, row.valueDD })
				UIDropDownMenu_SetText(row.valueDD, QualityText(c.value))
			elseif c.type == COND_ITEM_LEVEL then
				ShowOnly(row, { row.opDD, row.number })
				row.number:SetText(c.value >= 0 and tostring(c.value) or "")
			elseif c.type == COND_SELL_PRICE then
				ShowOnly(row, { row.opDD, row.gold, row.goldLabel, row.silver, row.silverLabel, row.copper,
					row.copperLabel })
				row.gold:SetText(tostring(math.floor(c.value / 10000)))
				row.silver:SetText(tostring(math.floor(c.value / 100) % 100))
				row.copper:SetText(tostring(c.value % 100))
			elseif c.type == COND_ITEM_TYPE then
				ShowOnly(row, { row.opDD, row.valueDD })
				UIDropDownMenu_SetText(row.valueDD, TypeText(c.value, c.value2))
			elseif c.type == COND_CURSED then
				ShowOnly(row, { row.opDD, row.valueDD })
				UIDropDownMenu_SetText(row.valueDD, c.value == 1 and "Cursed" or "Not cursed")
			elseif c.type == COND_ITEM then
				ShowOnly(row, { row.itemBox })
				row.itemBox:SetText(c.value > 0 and ItemText(c.value) or "")
			else
				ShowOnly(row, { row.textBox })
				row.textBox:SetText(c.text or "")
			end
			-- Only quality, item level and sell price have a choice of operator.
			if HasOperator(c.type) then
				UIDropDownMenu_EnableDropDown(row.opDD)
			else
				UIDropDownMenu_DisableDropDown(row.opDD)
			end
			if #rule.conds > 1 then row.remove:Enable() else row.remove:Disable() end
		else
			row:Hide()
		end
	end
	if #rule.conds < MAX_CONDITIONS then addCondBtn:Enable() else addCondBtn:Disable() end

	for code, radio in pairs(actionRadios) do
		local a = ACTIONS[code]
		radio:SetChecked(rule.action == code and 1 or nil)
		if M.allow[code] then
			radio:Enable()
			radio.label:SetText(Colored(a.color, a.label))
		else
			radio:Disable()
			radio.label:SetText(Colored("666666", a.label))
		end
	end
	editorError:SetText(E.error or "")
end
LF.RenderEditor = RenderEditor

local function CopyRule(rule)
	local copy = { id = rule.id or 0, position = rule.position or 0, action = rule.action or 1,
		enabled = rule.enabled ~= false, conds = {} }
	for i, c in ipairs(rule.conds) do
		copy.conds[i] = { type = c.type, op = c.op or 0, value = c.value or 0, value2 = c.value2 or 0,
			text = c.text or "" }
	end
	return copy
end

function LF.OpenEditor(rule)
	SelectTab(1)
	if rule then
		E.rule = CopyRule(rule)
	else
		E.rule = { id = 0, position = #M.rules + 1, action = 1, enabled = true,
			conds = { DefaultCond(COND_QUALITY) } }
	end
	E.error = nil
	editor:Show()
	RenderEditor()
end

function LF.OpenTemplate(index)
	local t = TEMPLATES[index]
	if not t then return end
	local rule = CopyRule({ id = 0, action = t.action, conds = t.conds })
	-- Keep rules belong on top, where they protect items from the others.
	rule.position = t.action == 0 and 1 or (#M.rules + 1)
	LF.OpenEditor(nil)
	E.rule = rule
	RenderEditor()
end

function LF.CloseEditor()
	E.rule = nil
	E.error = nil
	editor:Hide()
	Refresh()
end

function LF.SaveEditor()
	local rule = E.rule
	if not rule then return false end
	for _, c in ipairs(rule.conds) do
		if c.type == COND_NAME then c.text = (c.text or ""):gsub("^%s+", ""):gsub("%s+$", "") end
	end
	local problem = LF.RuleProblem(rule)
	if not problem and rule.id == 0 and #M.rules >= M.maxRules then problem = ERRORS.limit end
	if problem then
		E.error = problem
		RenderEditor()
		return false
	end
	LF.Send("R|" .. LF.EncodeRule(rule))
	LF.CloseEditor()
	return true
end

-- ============================================================
-- Test tab
-- ============================================================

local testPanel = panels[2]

local testBox = Panel(testPanel)
testBox:SetPoint("TOPLEFT", 0, 0)
testBox:SetPoint("TOPRIGHT", 0, 0)
testBox:SetHeight(120)

local testTitle = Text(testBox, "GameFontNormal")
testTitle:SetPoint("TOPLEFT", 10, -10)
testTitle:SetText("Test one item")
local testHint = Text(testBox, "GameFontDisableSmall")
testHint:SetPoint("LEFT", testTitle, "RIGHT", 10, 0)
testHint:SetText("Drop an item on the slot or Shift-click it in your bags.")

local testSlot = CreateFrame("Button", "LootFilterTestSlot", testBox, "ItemButtonTemplate")
testSlot:SetPoint("TOPLEFT", 12, -34)
testSlot:RegisterForDrag("LeftButton")
LF.testSlot = testSlot

local testItemText = Text(testBox, "GameFontHighlight")
testItemText:SetPoint("TOPLEFT", testSlot, "TOPRIGHT", 10, -2)
testItemText:SetWidth(520)
local testInfoText = Text(testBox, "GameFontDisableSmall")
testInfoText:SetPoint("TOPLEFT", testItemText, "BOTTOMLEFT", 0, -3)
testInfoText:SetWidth(520)
local testResultText = Text(testBox, "GameFontHighlight")
testResultText:SetPoint("TOPLEFT", testInfoText, "BOTTOMLEFT", 0, -8)
testResultText:SetWidth(520)
local testRuleText = Text(testBox, "GameFontDisableSmall")
testRuleText:SetPoint("TOPLEFT", testResultText, "BOTTOMLEFT", 0, -3)
testRuleText:SetWidth(520)

local lastPick -- bag and slot of the last item picked up from the bags
if not LootFilterUI_PickHooked then
	hooksecurefunc("PickupContainerItem", function(bag, slot)
		if LootFilterUI and LootFilterUI.OnPickup then LootFilterUI.OnPickup(bag, slot) end
	end)
	LootFilterUI_PickHooked = true
end
function LF.OnPickup(bag, slot)
	lastPick = { bag = bag, slot = slot }
end

-- Finds the bag slot that holds this exact link.
function LF.FindBagSlot(link)
	if lastPick and GetContainerItemLink(lastPick.bag, lastPick.slot) == link then
		return lastPick.bag, lastPick.slot
	end
	for bag = 0, 4 do
		for slot = 1, (GetContainerNumSlots(bag) or 0) do
			if GetContainerItemLink(bag, slot) == link then return bag, slot end
		end
	end
	return nil
end

function LF.TestBagSlot(bag, slot)
	if bag == nil or slot == nil then
		SetStatus(ERRORS.noitem)
		return
	end
	M.testLink = GetContainerItemLink(bag, slot)
	M.test = nil
	LF.Send("T|" .. bag .. "|" .. slot)
	Refresh()
end

local function TestFromCursor()
	local kind, _, link = GetCursorInfo()
	if kind ~= "item" then return end
	local bag, slot = LF.FindBagSlot(link)
	ClearCursor()
	LF.TestBagSlot(bag, slot)
end
testSlot:SetScript("OnReceiveDrag", TestFromCursor)
testSlot:SetScript("OnClick", TestFromCursor)
testSlot:SetScript("OnEnter", function(self)
	if M.testLink then
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetHyperlink(M.testLink)
		GameTooltip:Show()
	end
end)
testSlot:SetScript("OnLeave", function() GameTooltip:Hide() end)

local scanBox = Panel(testPanel)
scanBox:SetPoint("TOPLEFT", testBox, "BOTTOMLEFT", 0, -8)
scanBox:SetPoint("BOTTOMRIGHT", 0, 0)

local scanTitle = Text(scanBox, "GameFontNormal")
scanTitle:SetPoint("TOPLEFT", 10, -10)
scanTitle:SetText("What would happen to my bags?")
local scanBtn = Button(scanBox, "Check my bags", 120, 22)
scanBtn:SetPoint("TOPRIGHT", -10, -6)
local scanHint = Text(scanBox, "GameFontDisableSmall")
scanHint:SetPoint("TOPLEFT", scanTitle, "BOTTOMLEFT", 0, -6)
scanHint:SetText("Nothing is changed. This only shows what the filter would do if you looted these items now.")
local scanCounts = Text(scanBox, "GameFontHighlightSmall")
scanCounts:SetPoint("TOPLEFT", scanHint, "BOTTOMLEFT", 0, -6)
scanCounts:SetWidth(590)

local SCAN_ROW_H, VISIBLE_SCAN = 20, 9
local scanScroll = CreateFrame("ScrollFrame", "LootFilterScanScroll", scanBox, "FauxScrollFrameTemplate")
scanScroll:SetPoint("TOPLEFT", 8, -74)
scanScroll:SetPoint("BOTTOMRIGHT", -28, 8)
local scanRows = {}
LF.scanRows = scanRows
for i = 1, VISIBLE_SCAN do
	local row = CreateFrame("Frame", nil, scanBox)
	row:SetHeight(SCAN_ROW_H)
	row:SetPoint("TOPLEFT", 8, -74 - (i - 1) * SCAN_ROW_H)
	row:SetPoint("TOPRIGHT", -28, -74 - (i - 1) * SCAN_ROW_H)
	row.item = Text(row, "GameFontHighlightSmall")
	row.item:SetPoint("LEFT", 4, 0)
	row.item:SetWidth(380)
	row.badge = BadgeFrame(row, 84)
	row.badge:SetPoint("LEFT", 392, 0)
	row.rule = Text(row, "GameFontDisableSmall", "RIGHT")
	row.rule:SetPoint("LEFT", row.badge, "RIGHT", 4, 0)
	row.rule:SetWidth(70)
	scanRows[i] = row
end

LF.scanButton = scanBtn
scanBtn:SetScript("OnClick", function()
	M.scan = { items = {}, counts = {}, done = false, running = true }
	LF.Send("S")
	Refresh()
end)

local function ResultNote(result, position)
	if result == RESULT_PROTECTED then return "quest" end
	if result == RESULT_NO_RULE then return "stays" end
	return "rule " .. tostring(position)
end

local function UpdateScanList()
	local items = M.scan.items
	FauxScrollFrame_Update(scanScroll, #items, VISIBLE_SCAN, SCAN_ROW_H)
	local offset = FauxScrollFrame_GetOffset(scanScroll)
	for i, row in ipairs(scanRows) do
		local it = items[offset + i]
		if it then
			local link = GetContainerItemLink(it.bag, it.slot) or "?"
			local _, count = GetContainerItemInfo(it.bag, it.slot)
			row.item:SetText(link .. ((count and count > 1) and (" x" .. count) or ""))
			row.badge:SetCode(it.result)
			row.rule:SetText(ResultNote(it.result, it.position))
			row:Show()
		else
			row:Hide()
		end
	end
	if M.scan.running then
		scanCounts:SetText("Checking ...")
	elseif M.scan.done then
		local parts = {}
		for _, code in ipairs({ 1, 2, 4, 0, 3, RESULT_PROTECTED, RESULT_NO_RULE }) do
			local n = M.scan.counts[code]
			if n and n > 0 then
				parts[#parts + 1] = Colored(ACTIONS[code].color, ACTIONS[code].label .. " " .. n)
			end
		end
		scanCounts:SetText(#parts > 0 and table.concat(parts, "   ") or "Your bags are empty.")
	else
		scanCounts:SetText("")
	end
end
scanScroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, SCAN_ROW_H, UpdateScanList)
end)

local function UpdateTest()
	local link = M.testLink
	if not link then
		SetItemButtonTexture(testSlot, nil)
		testItemText:SetText("|cff8c8ca8No item yet.|r")
		testInfoText:SetText("")
		testResultText:SetText("")
		testRuleText:SetText("")
	else
		local name, _, quality, level, _, class, subclass, _, _, texture, price = GetItemInfo(link)
		SetItemButtonTexture(testSlot, texture)
		testItemText:SetText(link)
		local info = {}
		if quality then info[#info + 1] = QUALITY_NAMES[quality] end
		if class then info[#info + 1] = subclass and (class .. " » " .. subclass) or class end
		if level then info[#info + 1] = "Item level " .. level end
		if price and price > 0 then info[#info + 1] = "sells for " .. MoneyText(price) end
		testInfoText:SetText(table.concat(info, "  ·  "))
		local t = M.test
		if not t then
			testResultText:SetText("|cff8c8ca8Asking the server ...|r")
			testRuleText:SetText("")
		elseif t.result == RESULT_PROTECTED then
			testResultText:SetText("Protected: quest items are never touched.")
			testRuleText:SetText("")
		elseif t.result == RESULT_NO_RULE then
			testResultText:SetText("No rule matches: the item stays in your bags.")
			testRuleText:SetText("")
		else
			testResultText:SetText("Rule " .. t.position .. " matches: " .. LF.Badge(t.result))
			local rule
			for _, r in ipairs(M.rules) do
				if r.position == t.position then rule = r end
			end
			local before = t.position > 1 and (" · rules 1 to " .. (t.position - 1) .. " did not match") or ""
			testRuleText:SetText((rule and LF.RuleText(rule) or "") .. before)
		end
		if not M.enabled then
			testRuleText:SetText(testRuleText:GetText() .. "  |cffff5a5a(the filter is off)|r")
		end
	end
end

-- ============================================================
-- Log tab
-- ============================================================

local logPanel = panels[3]

local logTitle = Text(logPanel, "GameFontNormal")
logTitle:SetPoint("TOPLEFT", 2, -4)
logTitle:SetText("This session")
local logHint = Text(logPanel, "GameFontDisableSmall")
logHint:SetPoint("LEFT", logTitle, "RIGHT", 10, 0)
logHint:SetText("newest first, last 100")
local logClear = Button(logPanel, "Clear", 70, 20)
logClear:SetPoint("TOPRIGHT", 0, 0)
logClear:SetScript("OnClick", function()
	M.log = {}
	Refresh()
end)

local LOG_ROW_H, VISIBLE_LOG = 22, 10
local logBox = Panel(logPanel)
logBox:SetPoint("TOPLEFT", 0, -24)
logBox:SetPoint("TOPRIGHT", 0, -24)
logBox:SetHeight(VISIBLE_LOG * LOG_ROW_H + 8)
local logScroll = CreateFrame("ScrollFrame", "LootFilterLogScroll", logBox, "FauxScrollFrameTemplate")
logScroll:SetPoint("TOPLEFT", 4, -4)
logScroll:SetPoint("BOTTOMRIGHT", -26, 4)
local logEmpty = Text(logBox, "GameFontDisable", "CENTER")
logEmpty:SetPoint("CENTER")
logEmpty:SetText("No filter activity this session.")

local logRows = {}
LF.logRows = logRows
for i = 1, VISIBLE_LOG do
	local row = CreateFrame("Frame", nil, logBox)
	row:SetHeight(LOG_ROW_H)
	row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * LOG_ROW_H)
	row:SetPoint("TOPRIGHT", -26, -4 - (i - 1) * LOG_ROW_H)
	row.time = Text(row, "GameFontDisableSmall")
	row.time:SetPoint("LEFT", 2, 0)
	row.time:SetWidth(56)
	row.badge = BadgeFrame(row, 80)
	row.badge:SetPoint("LEFT", 60, 0)
	row.item = Text(row, "GameFontHighlightSmall")
	row.item:SetPoint("LEFT", 146, 0)
	row.item:SetWidth(230)
	row.detail = Text(row, "GameFontHighlightSmall")
	row.detail:SetPoint("LEFT", 380, 0)
	row.detail:SetWidth(150)
	row.rule = Text(row, "GameFontDisableSmall", "RIGHT")
	row.rule:SetPoint("RIGHT", -2, 0)
	row.rule:SetWidth(46)
	logRows[i] = row
end

local totalsTitle = Text(logPanel, "GameFontNormal")
totalsTitle:SetPoint("TOPLEFT", logBox, "BOTTOMLEFT", 2, -10)
totalsTitle:SetText("Totals since you started")
local totalsText = Text(logPanel, "GameFontHighlightSmall")
totalsText:SetPoint("TOPLEFT", totalsTitle, "BOTTOMLEFT", 0, -4)
totalsText:SetWidth(600)

local chatTitle = Text(logPanel, "GameFontNormal")
chatTitle:SetPoint("TOPLEFT", totalsText, "BOTTOMLEFT", 0, -12)
chatTitle:SetText("Chat messages")
local CHAT_MODES = { { 0, "Every action" }, { 1, "One summary per loot" }, { 2, "None" } }
local chatRadios = {}
LF.chatRadios = chatRadios
local prevLabel
for i, mode in ipairs(CHAT_MODES) do
	local radio = CreateFrame("CheckButton", "LootFilterChatMode" .. mode[1], logPanel, "UIRadioButtonTemplate")
	if prevLabel then
		radio:SetPoint("LEFT", prevLabel, "RIGHT", 16, 0)
	else
		radio:SetPoint("TOPLEFT", chatTitle, "BOTTOMLEFT", 2, -6)
	end
	radio.label = Text(logPanel, "GameFontHighlightSmall")
	radio.label:SetPoint("LEFT", radio, "RIGHT", 2, 0)
	radio.label:SetText(mode[2])
	radio:SetScript("OnClick", function()
		M.chatMode = mode[1]
		LF.Send("C|" .. mode[1])
		Refresh()
	end)
	prevLabel = radio.label
	chatRadios[mode[1]] = radio
end
local chatExample = Text(logPanel, "GameFontDisableSmall")
chatExample:SetPoint("TOPLEFT", chatTitle, "BOTTOMLEFT", 0, -30)
chatExample:SetWidth(600)

local CHAT_EXAMPLES = {
	[0] = "|cff888888[Loot Filter]|r Sold [Broken Fang] x4 for 1s 60c.",
	[1] = "|cff888888[Loot Filter]|r Sold 5 for 2s 40c, disenchanted 1, stored 6, deleted 1.",
	[2] = "No chat lines. The log above still records every action.",
}

local function LogDetail(e)
	if e.action == 1 then return "+" .. MoneyText(e.money) end
	if e.action == 2 and #e.mats > 0 then
		local parts = {}
		for _, m in ipairs(e.mats) do
			parts[#parts + 1] = ItemText(m[1]) .. ((m[2] or 1) > 1 and (" x" .. m[2]) or "")
		end
		return "> " .. table.concat(parts, ", ")
	end
	return ""
end

local function UpdateLog()
	FauxScrollFrame_Update(logScroll, #M.log, VISIBLE_LOG, LOG_ROW_H)
	local offset = FauxScrollFrame_GetOffset(logScroll)
	for i, row in ipairs(logRows) do
		local e = M.log[offset + i]
		if e then
			row.time:SetText(e.time)
			row.badge:SetCode(e.action)
			row.item:SetText(ItemText(e.entry, e.suffix) .. (e.count > 1 and (" x" .. e.count) or ""))
			row.detail:SetText(LogDetail(e))
			row.rule:SetText(e.position > 0 and ("rule " .. e.position) or "")
			row:Show()
		else
			row:Hide()
		end
	end
	if #M.log == 0 then logEmpty:Show() else logEmpty:Hide() end
	local t = M.totals
	totalsText:SetText(string.format("%s earned  ·  %d disenchanted  ·  %d stored  ·  %d deleted",
		MoneyText(t.sold), t.de, t.stored, t.del))
	for mode, radio in pairs(chatRadios) do radio:SetChecked(M.chatMode == mode and 1 or nil) end
	chatExample:SetText("Example: " .. (CHAT_EXAMPLES[M.chatMode] or ""))
end
logScroll:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, LOG_ROW_H, UpdateLog)
end)

-- ============================================================
-- Refresh
-- ============================================================

Refresh = function()
	filterBox:SetChecked(M.enabled and 1 or nil)
	filterText:SetText(M.enabled and "|cff3fdd3fFilter on|r" or "|cffff5a5aFilter off|r")
	countText:SetText(activeTab == 1 and (#M.rules .. " / " .. M.maxRules .. " rules") or "")
	statusText:SetText(M.status or "")
	if not main:IsShown() then return end
	if activeTab == 1 then
		if E.rule then RenderEditor() else UpdateRuleList() end
	elseif activeTab == 2 then
		UpdateTest()
		UpdateScanList()
	else
		UpdateLog()
	end
end
LF.Refresh = Refresh

main:SetScript("OnUpdate", function()
	if M.status and GetTime() - (M.statusTime or 0) > 6 then
		M.status = nil
		statusText:SetText("")
	end
end)

main:SetScript("OnShow", function()
	LF.Send("G")
	SelectTab(activeTab)
end)
main:SetScript("OnHide", function()
	CloseDropDownMenus()
end)

-- ============================================================
-- Links: Shift-click into the editor's item box or onto the Test tab
-- ============================================================

-- Takes an item link while the window wants one; true = handled.
function LF.ConsumeLink(link)
	if not main:IsShown() or type(link) ~= "string" or not string.find(link, "|Hitem:") then return false end
	if activeTab == 1 and E.rule then
		for i, row in ipairs(condRows) do
			local c = E.rule.conds[i]
			if c and c.type == COND_ITEM and row.itemBox:HasFocus() then
				c.value = ItemIdFromLink(link) or 0
				row.itemBox:ClearFocus()
				RenderEditor()
				return true
			end
		end
		return false
	end
	if activeTab == 2 then
		local bag, slot = LF.FindBagSlot(link)
		if bag then
			LF.TestBagSlot(bag, slot)
			return true
		end
	end
	return false
end

if not LootFilterUI_LinkHooked then
	local original = ChatEdit_InsertLink
	ChatEdit_InsertLink = function(text)
		if LootFilterUI and LootFilterUI.ConsumeLink and LootFilterUI.ConsumeLink(text) then return true end
		return original(text)
	end
	LootFilterUI_LinkHooked = true
end

-- ============================================================
-- Incoming messages
-- ============================================================

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
	if event == "CHAT_MSG_ADDON" and prefix == PREFIX_IN and sender == UnitName("player") then
		LF.OnMessage(message)
	end
end)
LF.events = events

-- ============================================================
-- Minimap button (drag it around the rim; the angle is saved)
-- ============================================================

LootFilterUI_Prefs = LootFilterUI_Prefs or {}
if AIO.AddSavedVarChar then AIO.AddSavedVarChar("LootFilterUI_Prefs") end

local mini = CreateFrame("Button", "LootFilterMinimapButton", Minimap)
mini:SetSize(31, 31)
mini:SetFrameStrata("MEDIUM")
mini:SetFrameLevel(8)
mini:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp")
mini:RegisterForDrag("LeftButton")
local miniIcon = mini:CreateTexture(nil, "BACKGROUND")
miniIcon:SetSize(20, 20)
miniIcon:SetPoint("CENTER", 0, 1)
miniIcon:SetTexture("Interface\\Icons\\INV_Misc_Bag_SatchelofCenarius")
local miniBorder = mini:CreateTexture(nil, "OVERLAY")
miniBorder:SetSize(53, 53)
miniBorder:SetPoint("TOPLEFT")
miniBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
LF.minimapButton = mini

local function PlaceMinimapButton()
	local angle = math.rad(LootFilterUI_Prefs.minimapAngle or 200)
	mini:ClearAllPoints()
	mini:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end
PlaceMinimapButton()

mini:SetScript("OnDragStart", function(self)
	self:SetScript("OnUpdate", function()
		local mx, my = Minimap:GetCenter()
		local px, py = GetCursorPosition()
		local scale = Minimap:GetEffectiveScale()
		px, py = px / scale, py / scale
		LootFilterUI_Prefs.minimapAngle = math.deg(math.atan2(py - my, px - mx))
		PlaceMinimapButton()
	end)
end)
mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mini:SetScript("OnClick", function() LootFilter_Toggle() end)
mini:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("Loot Filter", 1, 0.82, 0)
	GameTooltip:AddLine("Click: open or close", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Drag: move this button", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("/lf or /lootfilter", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)
if LootFilterUI_Prefs.minimapHidden then mini:Hide() end

-- ============================================================
-- Entry points
-- ============================================================

function LootFilter_Toggle()
	if main:IsShown() then main:Hide() else main:Show() end
end

SLASH_LOOTFILTER1 = "/lootfilter"
SLASH_LOOTFILTER2 = "/lf"
SlashCmdList["LOOTFILTER"] = function(msg)
	msg = string.lower(msg or "")
	if msg == "reload" then
		LF.Send("G")
	elseif msg == "minimap" then
		LootFilterUI_Prefs.minimapHidden = not LootFilterUI_Prefs.minimapHidden
		if LootFilterUI_Prefs.minimapHidden then mini:Hide() else mini:Show() end
	else
		LootFilter_Toggle()
	end
end
