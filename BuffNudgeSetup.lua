-- BuffNudgeSetup.lua
local _, ns = ...
local ORANGE = ns.ORANGE
local GREEN  = ns.GREEN
local BLUE   = ns.BLUE
local YELLOW = ns.YELLOW
local GREY   = ns.GREY
local RESET  = ns.RESET

local PANEL_W  = 420
local ROW_H    = 22
local BTN_W    = 52
local BTN_H    = 18
local MAX_ROWS = 14
-- Height of the always-visible header: title + profile row + tab buttons + divider
local HEADER_H = 84

-- ============================================================
-- HELPERS
-- ============================================================

local function IdInList(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
end

local function IdInRaidList(list, id)
    for _, v in ipairs(list) do if v.spellID == id then return true end end
    return false
end

local function RemoveFromList(list, id)
    for i = #list, 1, -1 do if list[i] == id then table.remove(list, i) end end
end

local function RemoveFromRaidList(list, id)
    for i = #list, 1, -1 do if list[i].spellID == id then table.remove(list, i) end end
end

-- ============================================================
-- SCAN — read all current player buffs
-- ============================================================

local function ScanBuffs()
    local buffs = {}
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 100)
    if auras then
        for _, aura in ipairs(auras) do
            table.insert(buffs, {
                name    = aura.name,
                icon    = aura.icon,
                spellID = aura.spellId,
            })
        end
    end
    return buffs
end

-- ============================================================
-- SETUP PANEL
-- ============================================================

local setup = CreateFrame("Frame", "BuffNudgeSetup", UIParent, "BackdropTemplate")
setup:SetSize(PANEL_W, 300)
setup:SetPoint("CENTER")
setup:SetMovable(true)
setup:EnableMouse(true)
setup:RegisterForDrag("LeftButton")
setup:SetScript("OnDragStart", setup.StartMoving)
setup:SetScript("OnDragStop",  setup.StopMovingOrSizing)
setup:SetFrameStrata("DIALOG")
setup:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 14,
    insets   = { left=4, right=4, top=4, bottom=4 },
})
setup:SetBackdropColor(0.08, 0.08, 0.08, 0.95)
setup:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
setup:Hide()

-- Title
local titleFs = setup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
titleFs:SetPoint("TOP", setup, "TOP", 0, -10)
titleFs:SetText(ORANGE.."BuffNudge"..RESET.." — Setup")

-- Close button
local xBtn = CreateFrame("Button", nil, setup, "UIPanelCloseButton")
xBtn:SetPoint("TOPRIGHT", setup, "TOPRIGHT", -4, -4)
xBtn:SetScript("OnClick", function() setup:Hide() end)

-- ============================================================
-- TAB SYSTEM
-- ============================================================

local buffsTab, settingsTab  -- forward declarations; created below
local Populate                -- forward declaration; defined in POPULATE section
-- Settings tab controls — forward-declared so RefreshProfileControls (defined later) can capture them
local profDropdown, fpsCB, showAlwaysCB, hideInCombatCB
local stoneCB, healthstoneCB, petCB
local reminderScaleFS, raidScaleFS, classScaleFS

local function ShowTab(tab)
    buffsTab:SetShown(tab == "buffs")
    settingsTab:SetShown(tab == "settings")
    if tab == "settings" then
        setup:SetHeight(490)
    end
    -- Buffs tab height is set in BuffNudgeSetup_Open / Populate
end

local tabBufBtn = CreateFrame("Button", nil, setup, "UIPanelButtonTemplate")
tabBufBtn:SetSize(100, 22)
tabBufBtn:SetPoint("TOPLEFT", setup, "TOPLEFT", 8, -58)
tabBufBtn:SetText("Buffs")
tabBufBtn:SetScript("OnClick", function()
    ShowTab("buffs")
    Populate()
end)

local tabSetBtn = CreateFrame("Button", nil, setup, "UIPanelButtonTemplate")
tabSetBtn:SetSize(100, 22)
tabSetBtn:SetPoint("TOPLEFT", tabBufBtn, "TOPRIGHT", 4, 0)
tabSetBtn:SetText("Settings")
tabSetBtn:SetScript("OnClick", function() ShowTab("settings") end)

-- Header divider
local headerDiv = setup:CreateTexture(nil, "ARTWORK")
headerDiv:SetHeight(1)
headerDiv:SetPoint("TOPLEFT",  setup, "TOPLEFT",  8, -84)
headerDiv:SetPoint("TOPRIGHT", setup, "TOPRIGHT", -8, -84)
headerDiv:SetColorTexture(0.4, 0.4, 0.4, 0.8)

-- ============================================================
-- BUFFS TAB
-- ============================================================

buffsTab = CreateFrame("Frame", nil, setup)
buffsTab:SetPoint("TOPLEFT",     setup, "TOPLEFT",   0, -HEADER_H)
buffsTab:SetPoint("BOTTOMRIGHT", setup, "BOTTOMRIGHT", 0, 0)

-- Counts line
local countsFs = buffsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
countsFs:SetPoint("TOP", buffsTab, "TOP", 0, -6)

-- Column headers
local function MakeColHeader(text, xOff)
    local fs = buffsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", buffsTab, "TOPLEFT", xOff, -20)
    fs:SetText(text)
    return fs
end
MakeColHeader(GREY.."Buff"..RESET,          34)
MakeColHeader(GREEN.."Food"..RESET,         PANEL_W - BTN_W*3 - 24)
MakeColHeader(BLUE.."Flask"..RESET,         PANEL_W - BTN_W*2 - 16)
MakeColHeader(YELLOW.."Raid Buff"..RESET,   PANEL_W - BTN_W - 8)

-- Column divider
local colDiv = buffsTab:CreateTexture(nil, "ARTWORK")
colDiv:SetHeight(1)
colDiv:SetPoint("TOPLEFT",  buffsTab, "TOPLEFT",  8, -34)
colDiv:SetPoint("TOPRIGHT", buffsTab, "TOPRIGHT", -8, -34)
colDiv:SetColorTexture(0.4, 0.4, 0.4, 0.8)

-- Scroll frame
local scrollFrame = CreateFrame("ScrollFrame", nil, buffsTab, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     buffsTab, "TOPLEFT",   8,  -38)
scrollFrame:SetPoint("BOTTOMRIGHT", buffsTab, "BOTTOMRIGHT", -28, 36)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(PANEL_W - 36, 1)
scrollFrame:SetScrollChild(content)

-- Re-scan button
local rescanBtn = CreateFrame("Button", nil, buffsTab, "UIPanelButtonTemplate")
rescanBtn:SetSize(80, 20)
rescanBtn:SetPoint("BOTTOMRIGHT", buffsTab, "BOTTOMRIGHT", -10, 8)
rescanBtn:SetText("Re-scan")

-- ============================================================
-- SETTINGS TAB
-- ============================================================

settingsTab = CreateFrame("Frame", nil, setup)
settingsTab:SetPoint("TOPLEFT",     setup, "TOPLEFT",   0, -HEADER_H)
settingsTab:SetPoint("BOTTOMRIGHT", setup, "BOTTOMRIGHT", 0, 0)
settingsTab:Hide()

-- Section: Checks
local checksLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
checksLbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -10)
checksLbl:SetText(ORANGE.."Checks"..RESET)

-- Soulstone/Healthstone/Pet moved to Class Panel section below
local cbDefs = {
    { key="food",    field="checkFood",     label="Food"    },
    { key="flask",   field="checkFlask",    label="Flask"   },
    { key="enchant", field="checkEnchant",  label="Enchant" },
    { key="socket",  field="checkSocket",   label="Socket"  },
    { key="raid",    field="checkRaidBuff", label="Raid"    },
}

local settingsCBs = {}
local cbItemW = (PANEL_W - 24) / #cbDefs  -- ~66px each

for i, def in ipairs(cbDefs) do
    local xOff = 12 + (i - 1) * cbItemW
    local lbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", xOff, -26)
    lbl:SetText(def.label)

    local cb = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", xOff, -40)
    cb:SetScript("OnClick", function(self)
        ns.GetProfile()[def.field] = self:GetChecked()
        BuffNudge_Refresh()
    end)
    settingsCBs[def.key] = cb
end

local settingsDiv1 = settingsTab:CreateTexture(nil, "ARTWORK")
settingsDiv1:SetHeight(1)
settingsDiv1:SetPoint("TOPLEFT",  settingsTab, "TOPLEFT",  8, -66)
settingsDiv1:SetPoint("TOPRIGHT", settingsTab, "TOPRIGHT", -8, -66)
settingsDiv1:SetColorTexture(0.4, 0.4, 0.4, 0.8)

-- Section: Display
local displayLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
displayLbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -74)
displayLbl:SetText(ORANGE.."Display"..RESET)

fpsCB = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
fpsCB:SetSize(20, 20)
fpsCB:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -92)
fpsCB:SetScript("OnClick", function()
    SlashCmdList["BUFFNUDGE"]("fps")
    fpsCB:SetChecked(not BuffNudgeDB.fpsHidden)
end)
local fpsLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
fpsLbl:SetPoint("LEFT", fpsCB, "RIGHT", 4, 0)
fpsLbl:SetText("FPS Display")

showAlwaysCB = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
showAlwaysCB:SetSize(20, 20)
showAlwaysCB:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -114)
showAlwaysCB:SetScript("OnClick", function(self)
    BuffNudgeDB.showAlways = self:GetChecked()
    BuffNudge_Refresh()
end)
local showAlwaysLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
showAlwaysLbl:SetPoint("LEFT", showAlwaysCB, "RIGHT", 4, 0)
showAlwaysLbl:SetText("Show outside instances")

hideInCombatCB = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
hideInCombatCB:SetSize(20, 20)
hideInCombatCB:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -136)
hideInCombatCB:SetScript("OnClick", function(self)
    BuffNudgeDB.hideInCombat = self:GetChecked()
    BuffNudge_Refresh()
end)
local hideInCombatLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hideInCombatLbl:SetPoint("LEFT", hideInCombatCB, "RIGHT", 4, 0)
hideInCombatLbl:SetText("Hide in combat")

local settingsDiv2 = settingsTab:CreateTexture(nil, "ARTWORK")
settingsDiv2:SetHeight(1)
settingsDiv2:SetPoint("TOPLEFT",  settingsTab, "TOPLEFT",  8, -160)
settingsDiv2:SetPoint("TOPRIGHT", settingsTab, "TOPRIGHT", -8, -160)
settingsDiv2:SetColorTexture(0.4, 0.4, 0.4, 0.8)

-- Section: Frame Positions
local posLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
posLbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -168)
posLbl:SetText(ORANGE.."Frame Positions"..RESET)

local moveFramesBtn = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
moveFramesBtn:SetSize(120, 22)
moveFramesBtn:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -188)
moveFramesBtn:SetText("Move Frames")
moveFramesBtn:SetScript("OnClick", function()
    SlashCmdList["BUFFNUDGE"]("move")
end)

local resetPanelBtn = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
resetPanelBtn:SetSize(150, 22)
resetPanelBtn:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -216)
resetPanelBtn:SetText("Reset Reminder Panel")
resetPanelBtn:SetScript("OnClick", function()
    BuffNudgeDB.panelX = nil
    BuffNudgeDB.panelY = nil
    local f = _G["BuffNudgePanel"]
    if f then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
    end
    print(ORANGE.."BuffNudge:"..RESET.." Reminder panel position reset.")
end)

local resetFpsBtn = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
resetFpsBtn:SetSize(130, 22)
resetFpsBtn:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 168, -216)
resetFpsBtn:SetText("Reset FPS Frame")
resetFpsBtn:SetScript("OnClick", function()
    BuffNudgeDB.fpsX = nil
    BuffNudgeDB.fpsY = nil
    local f = _G["BuffNudgeFPS"]
    if f then
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -16)
    end
    print(ORANGE.."BuffNudge:"..RESET.." FPS frame position reset.")
end)

local resetRaidBtn = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
resetRaidBtn:SetSize(150, 22)
resetRaidBtn:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -244)
resetRaidBtn:SetText("Reset Raid Panel")
resetRaidBtn:SetScript("OnClick", function()
    BuffNudgeDB.raidPanelX = nil
    BuffNudgeDB.raidPanelY = nil
    local f = _G["BuffNudgeRaidPanel"]
    if f then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 120, 220)
    end
    print(ORANGE.."BuffNudge:"..RESET.." Raid buff panel position reset.")
end)

-- ── Scale controls ──────────────────────────────────────────

local scaleSectionDiv = settingsTab:CreateTexture(nil, "ARTWORK")
scaleSectionDiv:SetHeight(1)
scaleSectionDiv:SetPoint("TOPLEFT",  settingsTab, "TOPLEFT",  8, -262)
scaleSectionDiv:SetPoint("TOPRIGHT", settingsTab, "TOPRIGHT", -8, -262)
scaleSectionDiv:SetColorTexture(0.4, 0.4, 0.4, 0.8)

local scaleLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
scaleLbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -270)
scaleLbl:SetText(ORANGE.."Scale"..RESET)

local function MakeScaleControl(x, y, label, dbKey, frameName, posX, posY)
    local lbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", x, y)
    lbl:SetText(label)

    local minus = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
    minus:SetSize(20, 18)
    minus:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", x + 54, y)
    minus:SetText("-")

    local valFS = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    valFS:SetSize(30, 18)
    valFS:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", x + 76, y + 2)
    valFS:SetJustifyH("CENTER")
    valFS:SetText("1.0")

    local plus = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
    plus:SetSize(20, 18)
    plus:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", x + 108, y)
    plus:SetText("+")

    local function apply(delta)
        local cur = BuffNudgeDB[dbKey] or 1.0
        local new = math.max(0.5, math.min(2.0, math.floor((cur + delta) * 10 + 0.5) / 10))
        BuffNudgeDB[dbKey] = new
        valFS:SetText(string.format("%.1f", new))
        local f = _G[frameName]
        if f then
            -- Preserve visual centre: anchor is fixed, so frame grows from TOPLEFT.
            -- Compute visual centre with the CURRENT scale, then re-anchor after.
            local left = f:GetLeft() or 0
            local top  = f:GetTop()  or 0
            local w    = f:GetWidth()
            local h    = f:GetHeight()
            local cx   = left + w * cur * 0.5
            local cy   = top  - h * cur * 0.5
            f:SetScale(new)
            local nx = cx - w * new * 0.5
            local ny = cy + h * new * 0.5
            f:ClearAllPoints()
            f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", nx, ny)
            BuffNudgeDB[posX] = nx
            BuffNudgeDB[posY] = ny
        end
    end
    minus:SetScript("OnClick", function() apply(-0.1) end)
    plus:SetScript("OnClick",  function() apply( 0.1) end)
    return valFS
end

reminderScaleFS = MakeScaleControl(12,  -288, "Reminder", "panelScale",      "BuffNudgePanel",     "panelX",     "panelY")
raidScaleFS     = MakeScaleControl(152, -288, "Raid",     "raidPanelScale",  "BuffNudgeRaidPanel", "raidPanelX", "raidPanelY")
classScaleFS    = MakeScaleControl(288, -288, "Class",    "classPanelScale", "BuffNudgeClassPanel","classPanelX","classPanelY")

-- ── Class Panel section ──────────────────────────────────────

local classSectionDiv = settingsTab:CreateTexture(nil, "ARTWORK")
classSectionDiv:SetHeight(1)
classSectionDiv:SetPoint("TOPLEFT",  settingsTab, "TOPLEFT",  8, -316)
classSectionDiv:SetPoint("TOPRIGHT", settingsTab, "TOPRIGHT", -8, -316)
classSectionDiv:SetColorTexture(0.4, 0.4, 0.4, 0.8)

local classLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
classLbl:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -324)
classLbl:SetText(ORANGE.."Class Panel"..RESET)

stoneCB = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
stoneCB:SetSize(20, 20)
stoneCB:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -342)
stoneCB:SetScript("OnClick", function(self)
    ns.GetProfile().checkSoulstone = self:GetChecked()
    BuffNudge_Refresh()
end)
local stoneLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
stoneLbl:SetPoint("LEFT", stoneCB, "RIGHT", 2, 0)
stoneLbl:SetText("Soulstone")

healthstoneCB = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
healthstoneCB:SetSize(20, 20)
healthstoneCB:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 150, -342)
healthstoneCB:SetScript("OnClick", function(self)
    ns.GetProfile().checkHealthstone = self:GetChecked()
    BuffNudge_Refresh()
end)
local healthstoneLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
healthstoneLbl:SetPoint("LEFT", healthstoneCB, "RIGHT", 2, 0)
healthstoneLbl:SetText("Healthstone")

petCB = CreateFrame("CheckButton", nil, settingsTab, "UICheckButtonTemplate")
petCB:SetSize(20, 20)
petCB:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 288, -342)
petCB:SetScript("OnClick", function(self)
    ns.GetProfile().checkPet = self:GetChecked()
    BuffNudge_Refresh()
end)
local petLbl = settingsTab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
petLbl:SetPoint("LEFT", petCB, "RIGHT", 2, 0)
petLbl:SetText("Pet")

local resetClassBtn = CreateFrame("Button", nil, settingsTab, "UIPanelButtonTemplate")
resetClassBtn:SetSize(150, 22)
resetClassBtn:SetPoint("TOPLEFT", settingsTab, "TOPLEFT", 12, -368)
resetClassBtn:SetText("Reset Class Panel")
resetClassBtn:SetScript("OnClick", function()
    BuffNudgeDB.classPanelX = nil
    BuffNudgeDB.classPanelY = nil
    local f = _G["BuffNudgeClassPanel"]
    if f then
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", -130, 220)
    end
    print(ORANGE.."BuffNudge:"..RESET.." Class panel position reset.")
end)

-- ============================================================
-- ROW POOL  (rows parented to content so they hide with buffsTab)
-- ============================================================

local rowPool    = {}
local activeRows = {}

local function MakeButton(parent, label, color)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(BTN_W - 4, BTN_H)
    btn:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left=2, right=2, top=2, bottom=2 },
    })
    btn:SetBackdropColor(0.1, 0.1, 0.1, 1)
    btn:SetBackdropBorderColor(unpack(color))
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetAllPoints()
    fs:SetText(label)
    btn.label = fs
    btn:SetScript("OnEnter", function(self) self:SetBackdropColor(0.25, 0.25, 0.25, 1) end)
    btn:SetScript("OnLeave", function(self) self:SetBackdropColor(0.1,  0.1,  0.1,  1) end)
    return btn
end

local function AcquireRow()
    local row = table.remove(rowPool)
    if not row then
        row = CreateFrame("Frame", nil, content)
        row:SetHeight(ROW_H)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_H - 4, ROW_H - 4)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT",  icon, "RIGHT", 4, 0)
        name:SetPoint("RIGHT", row,  "RIGHT", BTN_W*3 + 24, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.nameFs = name

        local idFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idFs:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 4, 0)
        idFs:SetTextColor(0.5, 0.5, 0.5)
        row.idFs = idFs

        row.btnFood  = MakeButton(row, "+Food",  { 0.2, 0.8, 0.2, 1 })
        row.btnFlask = MakeButton(row, "+Flask", { 0.2, 0.6, 1.0, 1 })
        row.btnRaid  = MakeButton(row, "+Raid",  { 1.0, 0.8, 0.0, 1 })

        row.btnFood: SetPoint("RIGHT", row, "RIGHT", -BTN_W*2 - 8, 0)
        row.btnFlask:SetPoint("RIGHT", row, "RIGHT", -BTN_W   - 4, 0)
        row.btnRaid: SetPoint("RIGHT", row, "RIGHT",             0, 0)
    end
    row:Show()
    return row
end

local function ReleaseRow(row)
    row:Hide()
    row.btnFood: SetScript("OnClick", nil)
    row.btnFlask:SetScript("OnClick", nil)
    row.btnRaid: SetScript("OnClick", nil)
    table.insert(rowPool, row)
end

-- ============================================================
-- POPULATE
-- ============================================================

local function UpdateCounts()
    BuffNudge_InvalidateCache()
    local p = ns.GetProfile()
    countsFs:SetText(
        string.format(GREEN.."Food: %d"..RESET.."   "..BLUE.."Flask: %d"..RESET.."   "..YELLOW.."Raid: %d"..RESET,
            #(p.foodIDs   or {}),
            #(p.flaskIDs  or {}),
            #(p.raidBuffs or {}))
    )
end

local function TagButton(btn, tagged)
    if tagged then
        btn:SetBackdropColor(0.05, 0.3, 0.05, 1)
    else
        btn:SetBackdropColor(0.1, 0.1, 0.1, 1)
    end
end

Populate = function()
    for _, r in ipairs(activeRows) do ReleaseRow(r) end
    activeRows = {}

    local buffs  = ScanBuffs()
    -- Resize panel to fit content (capped at MAX_ROWS visible rows)
    if setup:IsShown() then
        local nRows = math.min(#buffs, MAX_ROWS)
        setup:SetHeight(HEADER_H + 44 + nRows * ROW_H + 36)
    end
    local totalH = 0

    for _, buff in ipairs(buffs) do
        local row = AcquireRow()
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -totalH)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -totalH)
        totalH = totalH + ROW_H

        row.icon:SetTexture(buff.icon)
        row.nameFs:SetText(buff.name)
        row.idFs:SetText("["..buff.spellID.."]")

        local db = ns.GetProfile()
        local id = buff.spellID

        TagButton(row.btnFood,  IdInList(db.foodIDs,      id))
        TagButton(row.btnFlask, IdInList(db.flaskIDs,     id))
        TagButton(row.btnRaid,  IdInRaidList(db.raidBuffs, id))

        row.btnFood:SetScript("OnClick", function(self)
            if IdInList(db.foodIDs, id) then
                RemoveFromList(db.foodIDs, id); TagButton(self, false)
            else
                RemoveFromList(db.flaskIDs, id); RemoveFromRaidList(db.raidBuffs, id)
                table.insert(db.foodIDs, id)
                TagButton(self, true); TagButton(row.btnFlask, false); TagButton(row.btnRaid, false)
            end
            UpdateCounts()
        end)

        row.btnFlask:SetScript("OnClick", function(self)
            if IdInList(db.flaskIDs, id) then
                RemoveFromList(db.flaskIDs, id); TagButton(self, false)
            else
                RemoveFromList(db.foodIDs, id); RemoveFromRaidList(db.raidBuffs, id)
                table.insert(db.flaskIDs, id)
                TagButton(self, true); TagButton(row.btnFood, false); TagButton(row.btnRaid, false)
            end
            UpdateCounts()
        end)

        row.btnRaid:SetScript("OnClick", function(self)
            if IdInRaidList(db.raidBuffs, id) then
                RemoveFromRaidList(db.raidBuffs, id); TagButton(self, false)
            else
                RemoveFromList(db.foodIDs, id); RemoveFromList(db.flaskIDs, id)
                table.insert(db.raidBuffs, { name = buff.name, spellID = id, icon = buff.icon })
                TagButton(self, true); TagButton(row.btnFood, false); TagButton(row.btnFlask, false)
            end
            UpdateCounts()
        end)

        table.insert(activeRows, row)
    end

    content:SetHeight(math.max(totalH, 1))
    UpdateCounts()

    if #buffs == 0 then
        print(ORANGE.."BuffNudge:"..RESET.." No buffs found on your character right now.")
    end
end

rescanBtn:SetScript("OnClick", Populate)

-- ============================================================
-- PROFILE CONTROLS  (always-visible header, y=-34 area)
-- ============================================================


local function GetSortedProfileNames()
    local names = {}
    for name in pairs(BuffNudgeDB.profiles) do names[#names+1] = name end
    table.sort(names)
    return names
end

local function RefreshProfileControls()
    local p = ns.GetProfile()
    UIDropDownMenu_SetText(profDropdown, BuffNudgeDB.activeProfile or "Default")
    settingsCBs.food:SetChecked(p.checkFood       ~= false)
    settingsCBs.flask:SetChecked(p.checkFlask     ~= false)
    settingsCBs.enchant:SetChecked(p.checkEnchant ~= false)
    settingsCBs.socket:SetChecked(p.checkSocket   ~= false)
    settingsCBs.raid:SetChecked(p.checkRaidBuff   ~= false)
    stoneCB:SetChecked(p.checkSoulstone           ~= false)
    healthstoneCB:SetChecked(p.checkHealthstone   ~= false)
    petCB:SetChecked(p.checkPet                   ~= false)
    reminderScaleFS:SetText(string.format("%.1f", BuffNudgeDB.panelScale      or 1.0))
    raidScaleFS:SetText(string.format("%.1f",     BuffNudgeDB.raidPanelScale  or 1.0))
    classScaleFS:SetText(string.format("%.1f",    BuffNudgeDB.classPanelScale or 1.0))
    fpsCB:SetChecked(not BuffNudgeDB.fpsHidden)
    showAlwaysCB:SetChecked(BuffNudgeDB.showAlways    == true)
    hideInCombatCB:SetChecked(BuffNudgeDB.hideInCombat == true)
end

local function SwitchToProfile(name)
    BuffNudgeDB.activeProfile = name
    BuffNudge_InvalidateCache()
    BuffNudge_Refresh()
    RefreshProfileControls()
    UpdateCounts()
    Populate()
end

-- "Profile:" label
local profLabel = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
profLabel:SetPoint("TOPLEFT", setup, "TOPLEFT", 12, -38)
profLabel:SetText(ORANGE.."Profile:"..RESET)

-- Dropdown (UIDropDownMenuTemplate has a ~16px internal left inset)
profDropdown = CreateFrame("Frame", "BuffNudgeProfileDropdown", setup, "UIDropDownMenuTemplate")  -- assigned to forward-decl above
profDropdown:SetPoint("TOPLEFT", setup, "TOPLEFT", 60, -32)
UIDropDownMenu_SetWidth(profDropdown, 180)

local function ProfileDropdown_Init(_, level)
    if level ~= 1 then return end
    local names = GetSortedProfileNames()
    for _, name in ipairs(names) do
        local info = UIDropDownMenu_CreateInfo()
        info.text    = name
        info.checked = (name == BuffNudgeDB.activeProfile)
        info.func    = function() SwitchToProfile(name) end
        UIDropDownMenu_AddButton(info, level)
    end
end
UIDropDownMenu_Initialize(profDropdown, ProfileDropdown_Init)

-- [New] button
local newProfBtn = CreateFrame("Button", nil, setup, "UIPanelButtonTemplate")
newProfBtn:SetSize(60, 20)
newProfBtn:SetPoint("TOPLEFT", setup, "TOPLEFT", 282, -36)
newProfBtn:SetText("New")
newProfBtn:SetScript("OnClick", function()
    local existing = GetSortedProfileNames()
    local n = 1
    local newName
    repeat
        newName = "Profile " .. n
        local found = false
        for _, v in ipairs(existing) do if v == newName then found = true; break end end
        if not found then break end
        n = n + 1
    until false
    local src = ns.GetProfile()
    local copy = {
        checkFood=src.checkFood, checkFlask=src.checkFlask,
        checkEnchant=src.checkEnchant, checkSocket=src.checkSocket, checkRaidBuff=src.checkRaidBuff,
        checkSoulstone=src.checkSoulstone, checkHealthstone=src.checkHealthstone, checkPet=src.checkPet,
        foodIDs={}, flaskIDs={}, raidBuffs={},
    }
    for _, v in ipairs(src.foodIDs)   do copy.foodIDs[#copy.foodIDs+1]     = v end
    for _, v in ipairs(src.flaskIDs)  do copy.flaskIDs[#copy.flaskIDs+1]   = v end
    for _, v in ipairs(src.raidBuffs) do copy.raidBuffs[#copy.raidBuffs+1] = { name=v.name, spellID=v.spellID } end
    BuffNudgeDB.profiles[newName] = copy
    SwitchToProfile(newName)
end)

-- [Del] button
local delProfBtn = CreateFrame("Button", nil, setup, "UIPanelButtonTemplate")
delProfBtn:SetSize(60, 20)
delProfBtn:SetPoint("TOPLEFT", setup, "TOPLEFT", 348, -36)
delProfBtn:SetText("Delete")
delProfBtn:SetScript("OnClick", function()
    local names = GetSortedProfileNames()
    if #names <= 1 then
        print(ORANGE.."BuffNudge:"..RESET.." Cannot delete the only profile.")
        return
    end
    local cur = BuffNudgeDB.activeProfile
    BuffNudgeDB.profiles[cur] = nil
    local newActive = (names[1] == cur) and names[2] or names[1]
    SwitchToProfile(newActive)
end)

-- ============================================================
-- PUBLIC OPEN FUNCTION (called from slash command)
-- ============================================================

function BuffNudgeSetup_Open()
    if setup:IsShown() then
        setup:Hide()
        return
    end
    ShowTab("settings")
    setup:Show()
    RefreshProfileControls()
end
