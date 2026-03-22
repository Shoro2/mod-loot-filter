-- =============================================================
-- mod-loot-filter — Client-side AIO UI
--
-- Full in-game UI for creating and managing loot filter rules.
-- Players can filter by quality, item level, vendor value,
-- cursed items, materials, item class, and more.
-- Rules can be AND-combined via groups.
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
local nextGroupId = 1

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

-- Group colors for visual distinction
local GROUP_COLORS = {
	[1] = {0.3, 0.6, 1.0},
	[2] = {1.0, 0.5, 0.2},
	[3] = {0.2, 0.9, 0.4},
	[4] = {0.9, 0.3, 0.8},
	[5] = {1.0, 0.9, 0.2},
	[6] = {0.4, 0.9, 0.9},
	[7] = {0.9, 0.4, 0.4},
	[8] = {0.6, 0.5, 1.0},
}

local function GetGroupColor(groupId)
	if groupId == 0 then return nil end
	return GROUP_COLORS[((groupId - 1) % #GROUP_COLORS) + 1]
end

-- ============================================================
-- UI Frame creation
-- ============================================================

local FRAME_WIDTH = 620
local FRAME_HEIGHT = 540
local ROW_HEIGHT = 22
local MAX_VISIBLE_RULES = 12
local HEADER_HEIGHT = 36
local FOOTER_HEIGHT = 110

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
	row.rowBg = rowBg

	-- Group color bar (left edge)
	local groupBar = row:CreateTexture(nil, "ARTWORK")
	groupBar:SetPoint("TOPLEFT", 0, 0)
	groupBar:SetPoint("BOTTOMLEFT", 0, 0)
	groupBar:SetWidth(3)
	groupBar:Hide()
	row.groupBar = groupBar

	-- Highlight on mouseover
	local highlight = row:CreateTexture(nil, "HIGHLIGHT")
	highlight:SetAllPoints()
	highlight:SetTexture(0.3, 0.3, 0.4, 0.3)

	-- Group label
	local grpText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	grpText:SetPoint("LEFT", 6, 0)
	grpText:SetWidth(30)
	grpText:SetJustifyH("CENTER")
	row.grpText = grpText

	-- Condition label
	local condText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	condText:SetPoint("LEFT", 40, 0)
	condText:SetWidth(230)
	condText:SetJustifyH("LEFT")
	row.condText = condText

	-- Action label
	local actText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	actText:SetPoint("LEFT", 276, 0)
	actText:SetWidth(55)
	actText:SetJustifyH("CENTER")
	row.actText = actText

	-- Enabled indicator
	local enText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	enText:SetPoint("LEFT", 336, 0)
	enText:SetWidth(26)
	enText:SetJustifyH("CENTER")
	row.enText = enText

	-- Toggle button
	local togBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	togBtn:SetSize(36, 18)
	togBtn:SetPoint("LEFT", 366, 0)
	togBtn:SetText("Tog")
	togBtn:SetNormalFontObject("GameFontNormalSmall")
	row.togBtn = togBtn

	-- Delete button
	local delBtn = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
	delBtn:SetSize(36, 18)
	delBtn:SetPoint("LEFT", 406, 0)
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

MakeColLabel(colHeader, "Grp", 6, 30)
MakeColLabel(colHeader, "Condition", 40, 230)
MakeColLabel(colHeader, "Action", 276, 55)
MakeColLabel(colHeader, "On", 336, 26)
MakeColLabel(colHeader, "", 366, 80)

-- ============================================================
-- Scroll handler + update
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

			-- Group display
			if rule.ruleGroup > 0 then
				local gc = GetGroupColor(rule.ruleGroup)
				row.grpText:SetText("|cff" .. string.format("%02x%02x%02x",
					gc[1]*255, gc[2]*255, gc[3]*255) ..
					"G" .. rule.ruleGroup .. "|r")
				row.groupBar:SetTexture(gc[1], gc[2], gc[3], 0.8)
				row.groupBar:Show()
			else
				row.grpText:SetText("|cff666666--|r")
				row.groupBar:Hide()
			end

			-- Build condition display text
			local condLabel = CONDITION_SHORT[rule.conditionType] or "?"
			local valueStr
			if rule.conditionType == 0 then
				valueStr = QUALITY_LABELS[rule.conditionValue] or tostring(rule.conditionValue)
			elseif rule.conditionType == 3 then
				valueStr = CLASS_LABELS[rule.conditionValue] or tostring(rule.conditionValue)
			elseif rule.conditionType == 5 then
				valueStr = rule.conditionValue == 1 and "Yes" or "No"
			elseif rule.conditionType == 7 then
				valueStr = '"' .. (rule.conditionStr or "") .. '"'
			elseif rule.conditionType == 2 then
				local g = math.floor(rule.conditionValue / 10000)
				local s = math.floor((rule.conditionValue % 10000) / 100)
				local c = rule.conditionValue % 100
				valueStr = string.format("%dg %ds %dc", g, s, c)
			else
				valueStr = tostring(rule.conditionValue)
			end

			-- AND indicator for grouped rules
			local prefix = ""
			if rule.ruleGroup > 0 then
				-- Check if previous rule in list has same group
				if ruleIdx > 1 and rules[ruleIdx - 1].ruleGroup == rule.ruleGroup then
					prefix = "|cffaaaaaa+ AND |r"
				end
			end
			row.condText:SetText(prefix .. condLabel .. ": " .. valueStr)

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

local condDropdown = CreateFrame("Frame", "LootFilterCondDropdown", footerFrame, "UIDropDownMenuTemplate")
condDropdown:SetPoint("LEFT", condTypeLabel, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(condDropdown, 130)

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

-- Value input
local valueLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
valueLabel:SetPoint("LEFT", condDropdown, "RIGHT", 4, 2)
valueLabel:SetText("Value:")

local valueInput = CreateFrame("EditBox", "LootFilterValueInput", footerFrame, "InputBoxTemplate")
valueInput:SetSize(80, 20)
valueInput:SetPoint("LEFT", valueLabel, "RIGHT", 6, 0)
valueInput:SetAutoFocus(false)
valueInput:SetMaxLetters(128)
valueInput:SetText("0")

-- Row 2: Action dropdown + Priority + Group
local actionLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
actionLabel:SetPoint("TOPLEFT", 6, -52)
actionLabel:SetText("Action:")

local actionDropdown = CreateFrame("Frame", "LootFilterActionDropdown", footerFrame, "UIDropDownMenuTemplate")
actionDropdown:SetPoint("LEFT", actionLabel, "RIGHT", -8, -2)
UIDropDownMenu_SetWidth(actionDropdown, 100)

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
priLabel:SetPoint("LEFT", actionDropdown, "RIGHT", 2, 2)
priLabel:SetText("Pri:")

local priInput = CreateFrame("EditBox", "LootFilterPriorityInput", footerFrame, "InputBoxTemplate")
priInput:SetSize(32, 20)
priInput:SetPoint("LEFT", priLabel, "RIGHT", 4, 0)
priInput:SetAutoFocus(false)
priInput:SetMaxLetters(3)
priInput:SetText("100")
priInput:SetNumeric(true)

-- Group input
local grpLabel = footerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
grpLabel:SetPoint("LEFT", priInput, "RIGHT", 8, 0)
grpLabel:SetText("Group:")

local grpInput = CreateFrame("EditBox", "LootFilterGroupInput", footerFrame, "InputBoxTemplate")
grpInput:SetSize(28, 20)
grpInput:SetPoint("LEFT", grpLabel, "RIGHT", 4, 0)
grpInput:SetAutoFocus(false)
grpInput:SetMaxLetters(3)
grpInput:SetText("0")
grpInput:SetNumeric(true)

-- Group help tooltip
grpInput:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:AddLine("|cff00cc66AND/OR Groups|r")
	GameTooltip:AddLine("0 = Standalone rule (OR)", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Same number = AND-combined", 0.8, 0.8, 0.8)
	GameTooltip:AddLine("Different groups = OR", 0.8, 0.8, 0.8)
	GameTooltip:AddLine(" ", 1, 1, 1)
	GameTooltip:AddLine("Example: Group 1 with Quality=Green", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("AND Group 1 with iLvl<100 = Sell", 0.6, 0.6, 0.6)
	GameTooltip:AddLine("-> Sells green items below iLvl 100", 0.3, 1, 0.3)
	GameTooltip:Show()
end)
grpInput:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- Row 3: Add button + New Group button
local addBtn = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
addBtn:SetSize(80, 22)
addBtn:SetPoint("TOPLEFT", 6, -78)
addBtn:SetText("Add Rule")
addBtn:SetScript("OnClick", function()
	local condValue = 0
	local condStr = ""
	local inputText = valueInput:GetText() or ""

	if selectedCondType == 7 then
		condStr = inputText
		condValue = 0
	else
		condValue = tonumber(inputText) or 0
	end

	local priority = tonumber(priInput:GetText()) or 100
	local ruleGroup = tonumber(grpInput:GetText()) or 0

	AIO.Handle("LootFilter", "AddRule",
		selectedCondType, condValue, condStr,
		selectedAction, priority, ruleGroup)
end)

-- New Group button (auto-fills next group ID)
local newGrpBtn = CreateFrame("Button", nil, footerFrame, "UIPanelButtonTemplate")
newGrpBtn:SetSize(80, 22)
newGrpBtn:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
newGrpBtn:SetText("New Group")
newGrpBtn:SetNormalFontObject("GameFontNormalSmall")
newGrpBtn:SetScript("OnClick", function()
	-- Calculate next group from existing rules
	local maxGroup = 0
	for _, r in ipairs(rules) do
		if r.ruleGroup > maxGroup then
			maxGroup = r.ruleGroup
		end
	end
	grpInput:SetText(tostring(maxGroup + 1))
end)
newGrpBtn:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	GameTooltip:SetText("Set group ID to next available number.\nAdd multiple rules with same group = AND logic.", 1, 1, 1, 1, true)
	GameTooltip:Show()
end)
newGrpBtn:SetScript("OnLeave", function()
	GameTooltip:Hide()
end)

-- Delete All button
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
			condType, condValue, condStr or "", action, priority, 0)
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

LootFilter_ClientHandlers.ReceiveRule = function(player, ruleId, ruleGroup, condType, condValue, condStr, action, priority, enabled)
	table.insert(rules, {
		ruleId = ruleId,
		ruleGroup = ruleGroup or 0,
		conditionType = condType,
		conditionValue = condValue,
		conditionStr = condStr or "",
		action = action,
		priority = priority,
		enabled = enabled,
	})
end

LootFilter_ClientHandlers.SetNextGroup = function(player, groupId)
	nextGroupId = groupId or 1
	grpInput:SetText(tostring(nextGroupId))
end

LootFilter_ClientHandlers.RefreshUI = function(player)
	-- Sort: grouped rules together, then by priority
	table.sort(rules, function(a, b)
		if a.ruleGroup ~= b.ruleGroup then
			-- Group 0 (standalone) goes first
			if a.ruleGroup == 0 then return true end
			if b.ruleGroup == 0 then return false end
			return a.ruleGroup < b.ruleGroup
		end
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

DEFAULT_CHAT_FRAME:AddMessage("|cff00cc66[Loot Filter]|r UI loaded. Type /lf to open.")
