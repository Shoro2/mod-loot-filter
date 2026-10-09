-- Offline test of lua_scripts/LootFilter_Client.lua against a mocked
-- FrameXML API: behaviour and the exact messages on the wire, not real
-- rendering. Run: build\lua.exe tests\client_test.lua lua_scripts\LootFilter_Client.lua

local checks, failures = 0, 0
local function check(ok, what)
	checks = checks + 1
	if not ok then
		failures = failures + 1
		print("FAIL: " .. what)
	end
end
local function has(s, part) return type(s) == "string" and string.find(s, part, 1, true) ~= nil end

-- ------------------------------------------------------------
-- Mock world
-- ------------------------------------------------------------

local wire = {}
local popups = {}
local hooks = {}
local menuItems = {}
local lastMenu
local lastDialog
local chatInserted
local cursor
local now = 100
local PLAYER = "Crtest"

local items = {
	[1001] = { "Vrykul Silk Hood of the Owl", 2, 142, "Armor", "Cloth", "IconHood", 9840 },
	[1002] = { "Spiked Ice Gauntlets", 2, 150, "Armor", "Plate", "IconGloves", 12000 },
	[34054] = { "Infinite Dust", 1, 80, "Trade Goods", "Enchanting", "IconDust", 0 },
	[34052] = { "Dream Shard", 3, 80, "Trade Goods", "Enchanting", "IconShard", 0 },
}
local function Link(id) return "|cff1eff00|Hitem:" .. id .. ":0:0:0:0:0:0:0:0|h[" .. items[id][1] .. "]|h|r" end
local bags = { [0] = {} }

local methods = {}
local frameMeta = {
	__index = function(_, key)
		return methods[key] or function() end
	end,
}
local function NewObject(kind, name, parent)
	local o = setmetatable({ kind = kind, scripts = {}, shown = true, enabled = true, parent = parent,
		name = name }, frameMeta)
	if name then _G[name] = o end
	return o
end
function methods:SetScript(key, f) self.scripts[key] = f end
function methods:GetScript(key) return self.scripts[key] end
function methods:Show()
	local was = self.shown
	self.shown = true
	if not was and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
	local was = self.shown
	self.shown = false
	if was and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:IsShown() return self.shown end
function methods:IsVisible() return self.shown end
function methods:SetText(text)
	self.text = text ~= nil and tostring(text) or nil
	if self.scripts.OnTextChanged then self.scripts.OnTextChanged(self, false) end
end
function methods:GetText() return rawget(self, "text") or "" end
function methods:SetChecked(v) self.checked = v end
function methods:GetChecked() return rawget(self, "checked") end
function methods:Enable() self.enabled = true end
function methods:Disable() self.enabled = false end
function methods:IsEnabled() return rawget(self, "enabled") end
function methods:SetID(id) self.id = id end
function methods:GetID() return rawget(self, "id") or 0 end
function methods:GetParent() return self.parent end
function methods:GetName() return self.name end
function methods:SetFocus() self.focus = true end
function methods:ClearFocus() self.focus = false end
function methods:HasFocus() return rawget(self, "focus") end
function methods:Insert(text) self.text = (rawget(self, "text") or "") .. text end
function methods:GetFrameLevel() return 1 end
function methods:GetCenter() return 0, 0 end
function methods:GetEffectiveScale() return 1 end
function methods:SetAlpha(a) self.alpha = a end
function methods:CreateTexture() return NewObject("Texture", nil, self) end
function methods:CreateFontString() return NewObject("FontString", nil, self) end
function methods:AddLine(text) self.lines = self.lines or {}; self.lines[#self.lines + 1] = text end
function methods:SetHyperlink(link) self.hyperlink = link end

function CreateFrame(kind, name, parent)
	local f = NewObject(kind, name, parent)
	if kind == "Frame" and name == "LootFilterFrame" then f.shown = true end
	return f
end

UIParent = NewObject("Frame", "UIParent")
Minimap = NewObject("Frame", "Minimap")
GameTooltip = NewObject("GameTooltip", "GameTooltip")
DEFAULT_CHAT_FRAME = NewObject("Frame")
UIErrorsFrame = NewObject("Frame")
UISpecialFrames = {}
SlashCmdList = {}
StaticPopupDialogs = {}
YES, NO = "Yes", "No"
tinsert = table.insert
UIDROPDOWNMENU_MENU_LEVEL = 1
UIDROPDOWNMENU_MENU_VALUE = nil

function UIDropDownMenu_SetWidth() end
function UIDropDownMenu_JustifyText() end
local initCalls = 0
function UIDropDownMenu_Initialize(dd, fn) dd.init = fn; initCalls = initCalls + 1 end
function UIDropDownMenu_SetText(dd, text) dd.ddtext = text end
function UIDropDownMenu_CreateInfo() return {} end
function UIDropDownMenu_AddButton(info) menuItems[#menuItems + 1] = info end
function UIDropDownMenu_EnableDropDown(dd) dd.ddEnabled = true end
function UIDropDownMenu_DisableDropDown(dd) dd.ddEnabled = false end
function CloseDropDownMenus() end
function EasyMenu(menu) lastMenu = menu end
function StaticPopup_Show(name)
	popups[#popups + 1] = name
	lastDialog = {}
	return lastDialog
end
function FauxScrollFrame_Update() end
function FauxScrollFrame_GetOffset() return 0 end
function FauxScrollFrame_OnVerticalScroll() end
function SetItemButtonTexture(button, texture) button.texture = texture end
function hooksecurefunc(name, fn) hooks[name] = fn end
function ChatEdit_InsertLink(text) chatInserted = text; return false end
function SendAddonMessage(prefix, message, channel, target)
	assert(prefix == "LFLT", "prefix")
	assert(channel == "WHISPER" and target == PLAYER, "channel")
	assert(#prefix + #message + 1 <= 255, "message too long: " .. #message)
	wire[#wire + 1] = message
end
function UnitName() return PLAYER end
function GetTime() return now end
date = function() return "12:00:00" end
function GetItemInfo(x)
	local id = type(x) == "number" and x or tonumber(string.match(tostring(x), "item:(%d+)"))
	local it = id and items[id]
	if not it then return nil end
	return it[1], Link(id), it[2], it[3], 1, it[4], it[5], 20, "", it[6], it[7]
end
function GetContainerItemLink(bag, slot) return bags[bag] and bags[bag][slot] end
function GetContainerNumSlots(bag) return bag == 0 and 16 or 0 end
function GetContainerItemInfo(bag, slot)
	if bags[bag] and bags[bag][slot] then return "tex", 1 end
end
function GetCursorInfo()
	if cursor then return cursor[1], cursor[2], cursor[3] end
end
function ClearCursor() cursor = nil end

AIO = {
	AddAddon = function() return false end,
	SavePosition = function() end,
	AddSavedVarChar = function() end,
}

local function last() return wire[#wire] end
local function openMenu(dd, level, value)
	menuItems = {}
	UIDROPDOWNMENU_MENU_LEVEL = level or 1
	UIDROPDOWNMENU_MENU_VALUE = value
	dd.init()
	UIDROPDOWNMENU_MENU_LEVEL = 1
	return menuItems
end
local function pick(list, text)
	for _, info in ipairs(list) do
		if info.text == text then return info end
	end
	for _, info in ipairs(list) do
		if has(info.text, text) then return info end
	end
end

-- ------------------------------------------------------------
-- Load the window
-- ------------------------------------------------------------

assert(loadfile(arg[1]))()
local LF = LootFilterUI
local M = LF.M
check(type(LF) == "table", "LootFilterUI global")
check(type(LootFilter_Toggle) == "function", "LootFilter_Toggle global")
check(type(SlashCmdList.LOOTFILTER) == "function", "slash command")
check(hooks.PickupContainerItem ~= nil, "pickup hook")

-- ------------------------------------------------------------
-- Sentences
-- ------------------------------------------------------------

local function C(t, op, v, v2, text) return { type = t, op = op, value = v, value2 = v2 or 0, text = text or "" } end

check(has(LF.CondText(C(0, 0, 2)), "Quality is") and has(LF.CondText(C(0, 0, 2)), "Uncommon"), "quality sentence")
check(LF.CondText(C(1, 2, 150)) == "Item level at most 150", "item level sentence")
check(has(LF.CondText(C(2, 1, 9840)), "Sell price at least 98"), "price sentence")
check(LF.CondText(C(3, 0, 4, 1)) == "Type is Armor » Cloth", "type sentence")
check(LF.CondText(C(3, 0, 4, 255)) == "Type is Armor", "type any sentence")
check(has(LF.CondText(C(5, 0, 1)), "cursed") and LF.CondText(C(5, 0, 0)) == "Item is not cursed", "cursed sentence")
check(has(LF.CondText(C(6, 0, 1001)), "Vrykul Silk Hood"), "item sentence")
check(LF.CondText(C(6, 0, 999)) == "Item is item #999", "uncached item sentence")
check(LF.CondText(C(7, 0, 0, 0, "silk")) == 'Name contains "silk"', "name sentence")
check(has(LF.RuleText({ conds = { C(0, 0, 2), C(1, 2, 150) } }), "and|r Item level at most 150"), "rule sentence")
check(LF.MoneyText(10000) == "1|cffffd700g|r" and has(LF.MoneyText(9840), "98"), "money text")
check(LF.MoneyText(0) == "0|cffeda55fc|r", "zero money")

-- ------------------------------------------------------------
-- Codec (same strings as tests/rules_test.cpp)
-- ------------------------------------------------------------

local sample = { id = 7, position = 3, action = 2, enabled = true, conds = { C(0, 2, 2), C(1, 2, 150) } }
check(LF.EncodeRule(sample) == "7|3|2|1|0:2:2:0:;1:2:150:0:", "encode rule")
local back = LF.DecodeRule(LF.Split("R|" .. LF.EncodeRule(sample), "|"), 2)
check(back and back.id == 7 and back.position == 3 and back.action == 2 and back.enabled, "decode rule")
check(back and #back.conds == 2 and back.conds[2].value == 150, "decode conditions")
check(LF.DecodeRule(LF.Split("R|7|3|2|2|0:2:2:0:", "|"), 2) == nil, "reject enabled 2")
check(LF.DecodeRule(LF.Split("R|7|3|2|1|", "|"), 2) == nil, "reject no conditions")
check(LF.DecodeRule(LF.Split("R|7|3|2|1|0:2:a:0:", "|"), 2) == nil, "reject bad number")
check(LF.DecodeRule(LF.Split("R|7|3|2|1|0:0:1:0:;0:0:1:0:;0:0:1:0:;0:0:1:0:;0:0:1:0:", "|"), 2) == nil,
	"reject five conditions")
local named = LF.DecodeRule(LF.Split("R|9|1|0|1|7:0:0:0:Frozen Orb's", "|"), 2)
check(named and named.conds[1].text == "Frozen Orb's", "decode name")
check(LF.ToUInt("4294967296") == nil and LF.ToUInt("12") == 12 and LF.ToUInt("-1") == nil, "ToUInt")

-- ------------------------------------------------------------
-- Validation
-- ------------------------------------------------------------

check(LF.RuleProblem({ action = 1, conds = {} }) ~= nil, "no conditions")
check(has(LF.RuleProblem({ action = 1, conds = { C(7, 0, 0, 0, "") } }), "name"), "empty name")
check(has(LF.RuleProblem({ action = 1, conds = { C(7, 0, 0, 0, "Tome: Fire") } }), "letters"), "bad name")
check(LF.RuleProblem({ action = 1, conds = { C(7, 0, 0, 0, string.rep("a", 41)) } }) ~= nil, "long name")
check(LF.RuleProblem({ action = 1, conds = { C(1, 2, -1) } }) ~= nil, "empty item level")
check(has(LF.RuleProblem({ action = 1, conds = { C(6, 0, 0) } }), "Shift-click"), "item not picked")
check(LF.RuleProblem({ action = 1, conds = { C(0, 0, 2) } }) == nil, "valid rule")
M.allow[3] = false
check(has(LF.RuleProblem({ action = 3, conds = { C(0, 0, 2) } }), "switched off"), "disabled action")
M.allow[3] = true

-- ------------------------------------------------------------
-- Window and messages
-- ------------------------------------------------------------

LF.frame:Hide()
wire = {}
LootFilter_Toggle()
check(LF.frame:IsShown() and last() == "G", "opening asks for the data")

LF.OnMessage("I|1|1|30|1|1|1|123456|5|2|7")
check(M.enabled and M.chatMode == 1 and M.maxRules == 30 and M.totals.sold == 123456, "settings message")
LF.OnMessage("R|11|1|1|1|0:0:0:0:")
LF.OnMessage("R|12|2|2|1|0:0:2:0:;1:2:150:0:")
check(#M.rules == 0, "rules wait for the end marker")
LF.OnMessage("N|2")
check(#M.rules == 2 and M.rules[2].id == 12, "rule list")
local rows = LF.ruleRows
check(rows[1].num:GetText() == "1" and has(rows[1].cond:GetText(), "Quality is"), "row 1 text")
check(has(rows[1].badge.text:GetText(), "SELL") and has(rows[2].badge.text:GetText(), "DISENCHANT"), "badges")
check(rows[1].up:IsEnabled() == false and rows[2].down:IsEnabled() == false, "edge arrows disabled")
check(rows[3]:IsShown() == false, "empty rows hidden")

rows[2].up.scripts.OnClick()
check(last() == "M|12|1", "move up")
local before = #wire
rows[2].down.scripts.OnClick()
check(#wire == before, "no move past the end")
rows[1].check.checked = nil
rows[1].check.scripts.OnClick(rows[1].check)
check(last() == "E|11|0", "switch a rule off")
rows[1].del.scripts.OnClick()
check(popups[#popups] == "LOOTFILTER_DELETE_RULE" and lastDialog.data == 11, "delete asks first")
StaticPopupDialogs.LOOTFILTER_DELETE_RULE.OnAccept(nil, lastDialog.data)
check(last() == "D|11", "delete")

LF.OnMessage("F|0")
check(M.enabled == false and LootFilterEnabledBox:GetChecked() == nil, "filter off message")
LootFilterEnabledBox.checked = 1
LootFilterEnabledBox.scripts.OnClick(LootFilterEnabledBox)
check(last() == "F|1" and M.enabled, "filter on box")
LF.OnMessage("!|limit")
check(has(M.status, "rule limit"), "error message")

-- ------------------------------------------------------------
-- Editor
-- ------------------------------------------------------------

LF.OpenEditor(nil)
local E = LF.E
check(E.rule and E.rule.id == 0 and #E.rule.conds == 1 and E.rule.position == 3, "new rule")
check(LF.editorFrame:IsShown(), "editor shown")
local callsBefore = initCalls
E.rule.conds[1].value = 4
LF.OnMessage("L|1|1001|0|1|40|1|")
check(initCalls == callsBefore and E.rule.conds[1].value == 4, "incoming messages leave the editor alone")
E.rule.conds[1].value = 2
M.log, M.session.soldItems, M.session.money, M.totals.sold = {}, 0, 0, 123456
LF.actionRadios[1].scripts.OnClick()
check(E.rule.action == 1, "pick sell")
check(LF.actionRadios[1]:GetChecked() == 1 and LF.actionRadios[0]:GetChecked() == nil, "radio state")

local crow = LF.condRows
-- second condition: item level at most 150
E.rule.conds[2] = LF.DefaultCond(0)
LF.RenderEditor()
pick(openMenu(crow[2].typeDD), "Item level").func()
check(E.rule.conds[2].type == 1 and E.rule.conds[2].op == 2, "type menu")
check(crow[2].number:IsShown() and not crow[2].valueDD:IsShown(), "number box for item level")
crow[2].number.text = "150"
crow[2].number.scripts.OnTextChanged(crow[2].number, true)
check(E.rule.conds[2].value == 150, "typed item level")
check(LF.SaveEditor() and last() == "R|0|3|1|1|0:0:2:0:;1:2:150:0:", "save new rule")
check(not LF.editorFrame:IsShown(), "editor closed after save")

LF.OpenEditor(M.rules[1])
check(E.rule.id == 11 and E.rule ~= M.rules[1], "edit works on a copy")
pick(openMenu(LootFilterPositionDropdown), "2").func()
check(E.rule.position == 2, "position menu")
check(LF.SaveEditor() and last() == "R|11|2|1|1|0:0:0:0:", "save edited rule")

LF.OpenEditor(nil)
pick(openMenu(crow[1].typeDD), "Name contains").func()
check(crow[1].textBox:IsShown(), "name box")
check(LF.SaveEditor() == false and has(E.error, "name"), "empty name refused")
crow[1].textBox.text = "  Frozen Orb  "
crow[1].textBox.scripts.OnTextChanged(crow[1].textBox, true)
check(LF.SaveEditor() and last() == "R|0|3|1|1|7:0:0:0:Frozen Orb", "name trimmed and saved")

LF.OpenEditor(nil)
pick(openMenu(crow[1].typeDD), "Type").func()
local classes = openMenu(crow[1].valueDD, 1)
check(pick(classes, "Armor") and pick(classes, "Armor").hasArrow, "class menu")
local subs = openMenu(crow[1].valueDD, 2, 4)
check(pick(subs, "Any Armor") ~= nil, "any subclass entry")
pick(subs, "Cloth").func()
check(E.rule.conds[1].value == 4 and E.rule.conds[1].value2 == 1, "subclass picked")
check(crow[1].valueDD.ddtext == "Armor » Cloth", "type shown")
check(crow[1].opDD.ddEnabled == false, "no operator for type")
LF.CloseEditor()

LF.OpenTemplate(5)
check(E.rule.action == 0 and E.rule.position == 1 and E.rule.conds[1].type == 5, "keep template goes on top")
LF.OpenTemplate(1)
check(E.rule.action == 1 and E.rule.position == 3, "sell template goes last")
LF.CloseEditor()

-- Item condition: Shift-click a link into the focused box.
LF.OpenEditor(nil)
pick(openMenu(crow[1].typeDD), "Item").func()
crow[1].itemBox:SetFocus()
check(ChatEdit_InsertLink(Link(1001)) == true and E.rule.conds[1].value == 1001, "shift-click into item box")
check(has(crow[1].itemBox:GetText(), "Vrykul"), "item box shows the item")
check(LF.SaveEditor() and last() == "R|0|3|1|1|6:0:1001:0:", "save item rule")

-- Drop an item on the box.
LF.OpenEditor(nil)
pick(openMenu(crow[1].typeDD), "Item").func()
cursor = { "item", 1002, Link(1002) }
crow[1].itemBox.scripts.OnReceiveDrag(crow[1].itemBox)
check(E.rule.conds[1].value == 1002 and cursor == nil, "drop into item box")
LF.CloseEditor()

-- ------------------------------------------------------------
-- Test tab
-- ------------------------------------------------------------

LF.SelectTab(2)
bags[0][3] = Link(1001)
check(LF.ConsumeLink(Link(1001)) and last() == "T|0|3", "shift-click tests the item")
check(M.testLink == Link(1001), "test link kept")
LF.OnMessage("T|0|3|2|2")
check(M.test.result == 2 and M.test.position == 2, "test result stored")
hooks.PickupContainerItem(0, 3)
cursor = { "item", 1001, Link(1001) }
LF.testSlot.scripts.OnReceiveDrag()
check(last() == "T|0|3" and cursor == nil, "drop tests the item")
LF.OnMessage("T|0|3|6|0")
check(M.test.result == 6, "protected result")

LF.scanButton.scripts.OnClick()
check(last() == "S" and M.scan.running, "check my bags")
LF.OnMessage("S|0|3|2|1|1001")
LF.OnMessage("S|0|4|5|0|1002")
LF.OnMessage("Z|2")
check(M.scan.done and M.scan.counts[2] == 1 and M.scan.counts[5] == 1, "scan results")
check(M.scan.items[1].entry == 1001, "scan rows carry the item")
LF.scanButton.scripts.OnClick()
LF.OnMessage("!|busy")
check(not M.scan.running and #M.scan.items == 2, "a refused scan keeps the last results")
LF.scanButton.scripts.OnClick()
LF.OnMessage("Z|0")
check(M.scan.done and #M.scan.items == 0, "empty bags clear the list")
LF.TestBagSlot(0, 9)
check(last() == "T|0|9" and M.testPending, "test request pending")
LF.OnMessage("!|noitem")
check(not M.testPending and M.testLink == nil and has(M.status, "empty"), "a refused test ends the wait")
hooks.PickupContainerItem(-1, 3)
bags[0][5] = Link(1002)
check(select(1, LF.FindBagSlot(Link(1002))) == 0, "bank pickups are not remembered")

-- ------------------------------------------------------------
-- Log tab
-- ------------------------------------------------------------

LF.OnMessage("L|1|1001|0|4|160|2|")
LF.OnMessage("L|2|1002|-12|1|0|5|34054:2,34052:1")
check(#M.log == 2 and M.log[1].action == 2 and M.log[2].count == 4, "log entries, newest first")
check(#M.log[1].mats == 2 and M.log[1].mats[1][2] == 2, "materials")
check(M.session.soldItems == 4 and M.session.money == 160 and M.session.de == 1, "session counters")
check(M.totals.de == 6 and M.totals.sold == 123616, "totals follow the log")
LF.SelectTab(3)
check(has(LF.logRows[1].badge.text:GetText(), "DISENCHANT"), "log row badge")
check(has(LF.logRows[1].detail:GetText(), "Infinite Dust"), "log row materials")
check(has(LF.logRows[2].detail:GetText(), "+1"), "log row money")
LF.chatRadios[0].scripts.OnClick()
check(last() == "C|0" and M.chatMode == 0, "chat mode")

-- ------------------------------------------------------------
-- Limits and entry points
-- ------------------------------------------------------------

local longest = { id = 4294967295, position = 255, action = 4, enabled = true, conds = {} }
for i = 1, 4 do longest.conds[i] = C(7, 0, 0, 0, string.rep("w", 40)) end
LF.Send("R|" .. LF.EncodeRule(longest)) -- the mock asserts the 255-byte limit
check(true, "longest rule fits")

LF.frame:Hide()
check(ChatEdit_InsertLink(Link(1001)) == false and chatInserted == Link(1001), "links go to chat when closed")
SlashCmdList.LOOTFILTER("reload")
check(last() == "G", "/lf reload")

if failures > 0 then
	print(string.format("client_test: %d of %d checks FAILED", failures, checks))
	os.exit(1)
end
print(string.format("client_test: all %d checks passed", checks))
