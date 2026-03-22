-- =============================================================
-- mod-loot-filter — Client-side AIO UI
--
-- Full in-game UI for creating and managing loot filter rules.
-- Players can filter by quality, item level, vendor value,
-- cursed items, materials, item class, and more.
-- =============================================================

local AIO = AIO or require("AIO")
if AIO.AddAddon() then return end

-- ============================================================
-- Data
-- ============================================================

local rules = {}
local settings = {
	filterEnabled = true,
	totalSold = 0,
	totalDisenchanted = 0,
	totalDeleted = 0,
	maxRules = 30,
}

-- ============================================================
-- Constants
-- ============================================================

local CONDITION_LABELS = {
	[0] = "Quality equals",
	[1] = "Item Level below",
	[2] = "Sell Price below (copper)",
	[3] = "Item Class",
	[4] = "Item Subclass",
	[5] = "Is Cursed Item",
	[6] = "Item ID",
	[7] = "Name contains",
}

local CONDITION_SHORT = {
	[0] = "Quality",
	[1] = "iLvl <",
	[2] = "Price <",
	[3] = "Class",
	[4] = "Subclass",
	[5] = "Cursed",
	[6] = "Item ID",
	[7] = "Name ~=",
}

local ACTION_LABELS = {
	[0] = "Keep (Whitelist)",
	[1] = "Auto-Sell",
	[2] = "Disenchant",
	[3] = "Delete",
}

local ACTION_SHORT = {
	[0] = "|cff00ff00Keep|r",
	[1] = "|cffffcc00Sell|r",
	[2] = "|cff9b59b6DE|r",
	[3] = "|cffff4444Delete|r",
}

local QUALITY_LABELS = {
	[0] = "|cff9d9d9dPoor (Grey)|r",
	[1] = "|cffffffffNormal (White)|r",
	[2] = "|cff1eff00Uncommon (Green)|r",
	[3] = "|cff0070ddRare (Blue)|r",
	[4] = "|cffa335eeEpic (Purple)|r",
	[5] = "|cffff8000Legendary (Orange)|r",
	[6] = "|cffe6cc80Heirloom|r",
}

local QUALITY_COLORS = {
	[0] = {0.62, 0.62, 0.62},
	[1] = {1, 1, 1},
	[2] = {0.12, 1, 0},
	[3] = {0, 0.44, 0.87},
	[4] = {0.64, 0.21, 0.93},
	[5] = {1, 0.5, 0},
	[6] = {0.9, 0.8, 0.5},
}

local CLASS_LABELS = {
	[0] = "Consumable",
	[1] = "Container",
	[2] = "Weapon",
	[3] = "Gem",
	[4] = "Armor",
	[5] = "Reagent",
	[6] = "Projectile",
	[7] = "Trade Goods",
	[9] = "Recipe",
	[12] = "Quest",
	[15] = "Miscellaneous",
}

-- ============================================================
-- UI Frame creation
-- ============================================================

local FRAME_WIDTH = 580
local FRAME_HEIGHT = 520
local ROW_HEIGHT = 22
local MAX_VISIBLE_RULES = 12
local HEADER_HEIGHT = 36
local FOOTER_HEIGHT = 90

-- Main frame
local mainFrame = CreateFrame("Frame", "LootFilterFrame", UIParent)
mainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
mainFrame:SetPoint("CENTER", 0, 0)
mainFrame:SetBackdrop({
	bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
	edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 24,
	insets = {left = 6, right = 6, top = 6, bottom = 6}
})
mainFrame:SetBackdropColor(0.05, 0.05, 0.1, 0.95)
mainFrame:EnableMouse(true)
mainFrame:SetMovable(true)
mainFrame:RegisterForDrag("LeftButton")
mainFrame:SetScript("OnDragStart", mainFrame.StartMoving)
mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
mainFrame:SetClampedToScreen(true)
mainFrame:Hide()

-- Title bar
local titleBg = mainFrame:CreateTexture(nil, "ARTWORK")
titleBg:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
titleBg:SetSize(280, 56)
titleBg:SetPoint("TOP", 0, 12)

local titleText = mainFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleText:SetPoint("TOP", 0, 2)
titleText:SetText("|cff00cc66Loot Filter|r")
titleText:SetFont("Fonts\\FRIZQT__.TTF", 14)

-- Close button
local closeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -4, -4)
closeBtn:SetScript("OnClick", function()
	mainFrame:Hide()
end)

-- ============================================================
-- Header: master toggle + stats
-- ============================================================

local headerFrame = CreateFrame("Frame", nil, mainFrame)
headerFrame:SetPoint("TOPLEFT", 14, -30)
headerFrame:SetPoint("TOPRIGHT", -14, -30)
headerFrame:SetHeight(HEADER_HEIGHT)

local toggleBtn = CreateFrame("Button", nil, headerFrame, "UIPanelButtonTemplate")
toggleBtn:SetSize(100, 22)
toggleBtn:SetPoint("LEFT", 0, 0)
toggleBtn:SetText("Filter: ON")
toggleBtn:SetScript("OnClick", function()
	AIO.Handle("LootFilter", "ToggleFilter")
end)

local statsText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
statsText:SetPoint("LEFT", toggleBtn, "RIGHT", 12, 0)
statsText:SetJustifyH("LEFT")
statsText:SetText("")

local ruleCountText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
ruleCountText:SetPoint("RIGHT", 0, 0)
ruleCountText:SetJustifyH("RIGHT")
ruleCountText:SetText("0/30 rules")

-- ============================================================
-- Rule list (scrollable)
-- ============================================================

local listFrame = CreateFrame("Frame", nil, mainFrame)
listFrame:SetPoint("TOPLEFT", 14, -(30 + HEADER_HEIGHT + 4))
listFrame:SetPoint("TOPRIGHT", -30, -(30 + HEADER_HEIGHT + 4))
listFrame:SetHeight(MAX_VISIBLE_RULES * ROW_HEIGHT + 4)

local listBg = listFrame:CreateTexture(nil, "BACKGROUND")
listBg:SetAllPoints()
listBg:SetTexture(0.05, 0.05, 0.08, 0.8)

-- Scroll frame
local scrollFrame = CreateFrame("ScrollFrame", "LootFilterScrollFrame", listFrame, "FauxScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 2, -2)
scrollFrame:SetPoint("BOTTOMRIGHT", -20, 2)

-- Row frames pool
local rowFrames = {}

for i = 1, MAX_VISIBLE_RULES do
	local row = CreateFrame("Button", nil, listFrame)
	row:SetHeight(ROW_HEIGHT)
	row:SetPoint("TOPLEFT", 2, -(2 + (i - 1) * ROW_HEIGHT))
	row:SetPoint("TOPRIGHT", -22, -(2 + (i - 1) * ROW_HEIGHT))

	-- Alternating row background
	local rowBg = row:CreateTexture(nil, "BACKGROUND")
	rowBg:SetAllPoints()
	if i % 2 == 0 then
		rowBg:SetTexture(0.12, 0.12, 0.16, 0.5)
	else
		rowBg:SetTexture(0.08, 0.08, 0.12, 0.5)
	end

	-- Highlight on mouseover
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(0.3, 0.3, 0.4, 0.3)

	-- Priority label
	local priText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	priText:SetPoint("LEFT", 4, 0)
	priText:SetWidth(24)
	priText:SetJustifyH("CENTER")
	row.priText = priText

	-- Condition label
	local condText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	condText:SetPoint("LEFT", 32, 0)
	condText:SetWidth(240)
	condText:SetJustifyH("LEFT")
	row.condText = condText

	-- Action label
	local actText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	actText:SetPoint("LEFT", 280, 0)
	actText:SetWidth(70)
	actText:SetJustifyH("CENTER")
	row.actText = actText

	-- Enabled indicator
	local enText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	enText:SetPoint("LEFT", 355, 0)
	enText:SetWidth(30)
	enText:SetJustifyH("CENTER")
	row.enText = enText

	-- Toggle button
	local togBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	togBtn:SetSize(40, 18)
	togBtn:SetPoint("LEFT", 388, 0)
	togBtn:SetText("Tog")
	togBtn:SetNormalFontObject("GameFontNormalSmall")
	row.togBtn = togBtn

	-- Delete button
	local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	delBtn:SetSize(40, 18)
	delBtn:SetPoint("LEFT", 432, 0)
	delBtn:SetText("Del")
	delBtn:SetNormalFontObject("GameFontNormalSmall")
	row.delBtn = delBtn

	row.ruleId = nil
	rowFrames[i] = row
end

-- ============================================================
-- Rule list column headers
-- ============================================================

local colHeader = CreateFrame("Frame", nil, mainFrame)
colHeader:SetPoint("BOTTOMLEFT", listFrame, "TOPLEFT", 0, 0)
colHeader:SetPoint("BOTTOMRIGHT", listFrame, "TOPRIGHT", 20, 0)
colHeader:SetHeight(18)

local colBg = colHeader:CreateTexture(nil, "BACKGROUND")
colBg:SetAllPoints()
colBg:SetTexture(0.15, 0.15, 0.2, 0.9)

local function MakeColLabel(parent, text, x, w)
	local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	fs:SetPoint("LEFT", x, 0)
	fs:SetWidth(w)
	fs:SetJustifyH("CENTER")
	fs:SetText("|cffcccccc"..text.."|r")
	return fs
end

MakeColLabel(colHeader, "#", 4, 24)
MakeColLabel(colHeader, "Condition", 32, 240)
MakeColLabel(colHeader, "Action", 280, 70)
MakeColLabel(colHeader, "On", 355, 30)
MakeColLabel(colHeader, "", 388, 80)

-- ============================================================
-- Scroll handler
-- ============================================================

local function UpdateRuleList()
	local numRules = #rules
	FauxScrollFrame_Update(scrollFrame, numRules, MAX_VISIBLE_RULES, ROW_HEIGHT)
	local offset = FauxScrollFrame_GetOffset(scrollFrame)

	for i = 1, MAX_VISIBLE_RULES do
		local row = rowFrames[i]
		local ruleIdx = offset + i
		if ruleIdx <= numRules then
			local rule = rules[ruleIdx]

			row.priText:SetText(tostring(rule.priority))

			-- Build condition display text
			local condLabel = CONDITION_SHORT[rule.conditionType] or "?"
			local valueStr
			if rule.conditionType == 0 then -- quality
				valueStr = QUALITY_LABELS[rule.conditionValue] or tostring(rule.conditionValue)
			elseif rule.conditionType == 3 then -- class
				valueStr = CLASS_LABELS[rule.conditionValue] or tostring(rule.conditionValue)
			elseif rule.conditionType == 5 then -- cursed
				valueStr = rule.conditionValue == 1 and "Yes" or "No"
			elseif rule.conditionType == 7 then -- name contains
				valueStr = '"' .. (rule.conditionStr or "") .. '"'
			elseif rule.conditionType == 2 then -- sell price
				local g = math.floor(rule.conditionValue / 10000)
				local s = math.floor((rule.conditionValue % 10000) / 100)
				local c = rule.conditionValue % 100
				valueStr = string.format("%dg %ds %dc", g, s, c)
			else
				valueStr = tostring(rule.conditionValue)
			end
			row.condText:SetText(condLabel .. ": " .. valueStr)

			row.actText:SetText(ACTION_SHORT[rule.action] or "?")

			if rule.enabled == 1 then
				row.enText:SetText("|cff00ff00On|r")
			else
				row.enText:SetText("|cffff0000Off|r")
			end

			row.ruleId = rule.ruleId
			row.togBtn:SetScript("OnClick", function()
				AIO.Handle("LootFilter", "ToggleRule", rule.ruleId)
			end)
			row.delBtn:SetScript("OnClick", function()
				-- Confirm delete
				StaticPopupDialogs["LOOTFILTER_DELETE_" .. rule.ruleId] = {
					text = "Delete this loot filter rule?",
					button1 = "Yes",
					button2 = "No",
					OnAccept = function()
						AIO.Handle("LootFilter", "DeleteRule", rule.ruleId)
					end,
					timeout = 0,
					whileDead = true,
					hideOnEscape = true,
				}
				StaticPopup_Show("LOOTFILTER_DELETE_" .. rule.ruleId)
			end)

			row:Show()
		else
			row:Hide()
		end
	end

	-- Update stats display
	local gold = math.floor(settings.totalSold / 10000)
	local silver = math.floor((settings.totalSold % 10000) / 100)
	local copper = settings.totalSold % 100
	statsText:SetText(string.format(
		"|cff888888Earned:|r %d|cffffcc00g|r %d|cffc0c0c0s|r %dc  |  "..
		"|cff9b59b6DE:|r %d  |  |cffff4444Del:|r %d",
		gold, silver, copper,
		settings.totalDisenchanted, settings.totalDeleted))

	ruleCountText:SetText(string.format("%d/%d rules", #rules, settings.maxRules))

	-- Update toggle button
	if settings.filterEnabled then
		toggleBtn:SetText("|cff00ff00Filter: ON|r")
	else
		toggleBtn:SetText("|cffff0000Filter: OFF|r")
	end
end

scrollFrame:SetScript("OnVerticalScroll", function(self, offset)
	FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, UpdateRuleList)
end)

-- ============================================================
-- Footer: "Add Rule" form
-- ============================================================

local footerFrame = CreateFrame("Frame", nil, mainFrame)
footerFrame:SetPoint("BOTTOMLEFT", 14, 12)
footerFrame:SetPoint("BOTTOMRIGHT", -14, 12)
footerFrame:SetHeight(FOOTER_HEIGHT)

local footerBg = footerFrame:CreateTexture(nil, "BACKGROUND")
footerBg:SetAllPoints()
footerBg:SetTexture(0.1, 0.1, 0.14, 0.8)

-- Separator line
local sepLine = footerFrame:CreateTexture(nil, "ARTWORK")
sepLine:SetPoint("TOPLEFT", 4, -1)
sepLine:SetPoint("TOPRIGHT", -4, -1)
sepLine:SetHeight(1)
sepLine:SetTexture(0.3, 0.3, 0.4, 0.8)

local addLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
addLabel:SetPoint("TOPLEFT", 6, -6)
addLabel:SetText("|cff00cc66Add New Rule|r")

-- Row 1: Condition Type dropdown + Value input
local condTypeLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
condTypeLabel:SetPoint("TOPLEFT", 6, -24)
condTypeLabel:SetText("Condition:")

-- Condition type dropdown
local condDropdown = CreateFrame("Frame", "LootFilterCondDropdown", footerFrame, "UIDropDownMenuTemplate")
condDropdown:SetPoint("LEFT", condTypeLabel, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(condDropdown, 140)

local selectedCondType = 0

local function CondDropdown_Init()
	for i = 0, 7 do
		local info = UIDropDownMenu_CreateInfo()
		info.text = CONDITION_LABELS[i]
		info.value = i
		info.func = function(self)
			selectedCondType = self.value
			UIDropDownMenu_SetSelectedValue(condDropdown, self.value)
			UIDropDownMenu_SetText(condDropdown, CONDITION_LABELS[self.value])
		end
		UIDropDownMenu_AddButton(info)
	end
end

UIDropDownMenu_Initialize(condDropdown, CondDropdown_Init)
UIDropDownMenu_SetSelectedValue(condDropdown, 0)
UIDropDownMenu_SetText(condDropdown, CONDITION_LABELS[0])

-- Value input (editbox)
local valueLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
valueLabel:SetPoint("LEFT", condDropdown, "RIGHT", 4, 2)
valueLabel:SetText("Value:")

local valueInput = CreateFrame("EditBox", "LootFilterValueInput", footerFrame, "InputBoxTemplate")
valueInput:SetSize(80, 20)
valueInput:SetPoint("LEFT", valueLabel, "RIGHT", 6, 0)
valueInput:SetAutoFocus(false)
valueInput:SetMaxLetters(128)
valueInput:SetText("0")

-- Row 2: Action dropdown + Priority + Add button
local actionLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
actionLabel:SetPoint("TOPLEFT", 6, -52)
actionLabel:SetText("Action:")

-- Action dropdown
local actionDropdown = CreateFrame("Frame", "LootFilterActionDropdown", footerFrame, "UIDropDownMenuTemplate")
actionDropdown:SetPoint("LEFT", actionLabel, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(actionDropdown, 110)

local selectedAction = 1

local function ActionDropdown_Init()
	for i = 0, 3 do
		local info = UIDropDownMenu_CreateInfo()
		info.text = ACTION_LABELS[i]
		info.value = i
		info.func = function(self)
			selectedAction = self.value
			UIDropDownMenu_SetSelectedValue(actionDropdown, self.value)
			UIDropDownMenu_SetText(actionDropdown, ACTION_LABELS[self.value])
		end
		UIDropDownMenu_AddButton(info)
	end
end

UIDropDownMenu_Initialize(actionDropdown, ActionDropdown_Init)
UIDropDownMenu_SetSelectedValue(actionDropdown, 1)
UIDropDownMenu_SetText(actionDropdown, ACTION_LABELS[1])

-- Priority input
local priLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
priLabel:SetPoint("LEFT", actionDropdown, "RIGHT", 4, 2)
priLabel:SetText("Priority:")

local priInput = CreateFrame("EditBox", "LootFilterPriorityInput", footerFrame, "InputBoxTemplate")
priInput:SetSize(40, 20)
priInput:SetPoint("LEFT", priLabel, "RIGHT", 6, 0)
priInput:SetAutoFocus(false)
priInput:SetMaxLetters(3)
priInput:SetText("100")
priInput:SetNumeric(true)

-- Add Rule button
local addBtn = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
addBtn:SetSize(80, 22)
addBtn:SetPoint("LEFT", priInput, "RIGHT", 12, 0)
addBtn:SetText("Add Rule")
addBtn:SetScript("OnClick", function()
	local condValue = 0
	local condStr = ""
	local inputText = valueInput:GetText() or ""

	if selectedCondType == 7 then -- name contains
		condStr = inputText
		condValue = 0
	else
		condValue = tonumber(inputText) or 0
	end

	local priority = tonumber(priInput:GetText()) or 100

	AIO.Handle("LootFilter", "AddRule",
		selectedCondType, condValue, condStr,
		selectedAction, priority)
end)

-- Delete All button (bottom right)
local deleteAllBtn = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
deleteAllBtn:SetSize(80, 22)
deleteAllBtn:SetPoint("BOTTOMRIGHT", -4, 4)
deleteAllBtn:SetText("|cffff4444Clear All|r")
deleteAllBtn:SetScript("OnClick", function()
	StaticPopupDialogs["LOOTFILTER_DELETE_ALL"] = {
		text = "Delete ALL loot filter rules?",
		button1 = "Yes",
		button2 = "No",
		OnAccept = function()
			AIO.Handle("LootFilter", "DeleteAllRules")
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
	StaticPopup_Show("LOOTFILTER_DELETE_ALL")
end)

-- ============================================================
-- Quick-add preset buttons
-- ============================================================

local presetFrame = CreateFrame("Frame", nil, mainFrame)
presetFrame:SetPoint("BOTTOMLEFT", footerFrame, "TOPLEFT", 0, 2)
presetFrame:SetPoint("BOTTOMRIGHT", footerFrame, "TOPRIGHT", 0, 2)
presetFrame:SetHeight(26)

local presetLabel = presetFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
presetLabel:SetPoint("LEFT", 4, 0)
presetLabel:SetText("|cffaaaaaaPresets:|r")

local function MakePresetBtn(parent, text, x, condType, condValue, condStr, action, priority, tooltip)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(90, 20)
	btn:SetPoint("LEFT", x, 0)
	btn:SetText(text)
	btn:SetNormalFontObject("GameFontNormalSmall")
	btn:SetScript("OnClick", function()
		AIO.Handle("LootFilter", "AddRule",
			condType, condValue, condStr or "", action, priority)
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	return btn
end

MakePresetBtn(presetFrame, "Sell Grey", 52, 0, 0, "", 1, 10,
	"Auto-sell all Poor (grey) quality items")
MakePresetBtn(presetFrame, "Sell White", 148, 0, 1, "", 1, 20,
	"Auto-sell all Normal (white) quality items")
MakePresetBtn(presetFrame, "DE Green", 244, 0, 2, "", 2, 30,
	"Auto-disenchant all Uncommon (green) items")
MakePresetBtn(presetFrame, "Del <iLvl50", 340, 1, 50, "", 3, 15,
	"Delete items with item level below 50")
MakePresetBtn(presetFrame, "Keep Cursed", 436, 5, 1, "", 0, 1,
	"Always keep Cursed items (whitelist)")

-- ============================================================
-- Toggle UI with slash command
-- ============================================================

SLASH_LOOTFILTER1 = "/lootfilter"
SLASH_LOOTFILTER2 = "/lf"
SlashCmdList["LOOTFILTER"] = function(msg)
	if msg == "reload" then
		AIO.Handle("LootFilter", "RequestData")
		return
	end
	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		mainFrame:Show()
		AIO.Handle("LootFilter", "RequestData")
	end
end

-- ESC to close
tinsert(UISpecialFrames, "LootFilterFrame")

-- ============================================================
-- AIO Handlers (Client side)
-- ============================================================

if not LootFilter_ClientHandlers then
	LootFilter_ClientHandlers = {}
end

LootFilter_ClientHandlers.ReceiveSettings = function(player, filterEnabled, totalSold, totalDE, totalDel, maxRules)
	settings.filterEnabled = (filterEnabled == 1)
	settings.totalSold = totalSold or 0
	settings.totalDisenchanted = totalDE or 0
	settings.totalDeleted = totalDel or 0
	settings.maxRules = maxRules or 30
end

LootFilter_ClientHandlers.ClearRules = function(player)
	rules = {}
end

LootFilter_ClientHandlers.ReceiveRule = function(player, ruleId, condType, condValue, condStr, action, priority, enabled)
	table.insert(rules, {
		ruleId = ruleId,
		conditionType = condType,
		conditionValue = condValue,
		conditionStr = condStr or "",
		action = action,
		priority = priority,
		enabled = enabled,
	})
end

LootFilter_ClientHandlers.RefreshUI = function(player)
	-- Sort by priority
	table.sort(rules, function(a, b)
		return a.priority < b.priority
	end)
	UpdateRuleList()
end

if not LootFilter_ClientHandlersRegistered then
	AIO.AddHandlers("LootFilter", LootFilter_ClientHandlers)
	LootFilter_ClientHandlersRegistered = true
end

-- ============================================================
-- Minimap button for quick access
-- ============================================================

local minimapBtn = CreateFrame("Button", "LootFilterMinimapBtn", Minimap)
minimapBtn:SetSize(28, 28)
minimapBtn:SetFrameStrata("MEDIUM")
minimapBtn:SetFrameLevel(8)
minimapBtn:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 6, -6)
minimapBtn:SetNormalTexture("Interface\\Icons\\INV_Misc_Bag_SatchelofCenarius")
minimapBtn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

local minimapBorder = minimapBtn:CreateTexture(nil, "OVERLAY")
minimapBorder:SetSize(52, 52)
minimapBorder:SetPoint("CENTER")
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

minimapBtn:SetScript("OnClick", function()
	if mainFrame:IsShown() then
		mainFrame:Hide()
	else
		mainFrame:Show()
		AIO.Handle("LootFilter", "RequestData")
	end
end)

minimapBtn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT")
	GameTooltip:AddLine("|cff00cc66Loot Filter|r")
	GameTooltip:AddLine("Click to open filter settings", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("/lf or /lootfilter", 0.5, 0.5, 0.5)
	GameTooltip:Show()
end)

minimapBtn:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- Debug
DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66[Loot Filter]|r UI loaded. Type /lf to open.")
