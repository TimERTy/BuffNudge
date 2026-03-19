-- BuffNudgeSetup.lua
-- Setup panel: scans your current buffs and lets you tag each one
-- as Food, Flask, or Raid Buff. Saved to BuffNudgeDB (SavedVariables).
-- Open with:  /bn setup

local PANEL_W   = 400
local ROW_H     = 22
local HEADER_H  = 60  -- title + counts + divider
local BTN_W     = 52
local BTN_H     = 18
local MAX_ROWS  = 14  -- scroll if more than this many buffs

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
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        table.insert(buffs, {
            name    = aura.name,
            icon    = aura.icon,
            spellID = aura.spellId,
        })
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
titleFs:SetText("|cffff9900BuffNudge|r — Setup")

-- Close button
local xBtn = CreateFrame("Button", nil, setup, "UIPanelCloseButton")
xBtn:SetPoint("TOPRIGHT", setup, "TOPRIGHT", -4, -4)
xBtn:SetScript("OnClick", function() setup:Hide() end)

-- Counts line
local countsFs = setup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
countsFs:SetPoint("TOP", titleFs, "BOTTOM", 0, -4)

-- Divider
local divider = setup:CreateTexture(nil, "ARTWORK")
divider:SetHeight(1)
divider:SetPoint("TOPLEFT",  setup, "TOPLEFT",  8, -HEADER_H + 10)
divider:SetPoint("TOPRIGHT", setup, "TOPRIGHT", -8, -HEADER_H + 10)
divider:SetColorTexture(0.4, 0.4, 0.4, 0.8)

-- Column headers
local function MakeHeader(text, anchor, xOff)
    local fs = setup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", setup, "TOPLEFT", xOff, -HEADER_H + 26)
    fs:SetText(text)
    return fs
end
MakeHeader("|cffaaaaааBuff|r",       nil, 34)
MakeHeader("|cff4dff4dFood|r",       nil, PANEL_W - BTN_W*3 - 24)
MakeHeader("|cff4dc8ffFlask|r",      nil, PANEL_W - BTN_W*2 - 16)
MakeHeader("|cffffff00Raid Buff|r",  nil, PANEL_W - BTN_W   -  8)

-- Refresh button (re-scan buffs)
local rescanBtn = CreateFrame("Button", nil, setup, "UIPanelButtonTemplate")
rescanBtn:SetSize(80, 20)
rescanBtn:SetPoint("BOTTOMRIGHT", setup, "BOTTOMRIGHT", -10, 8)
rescanBtn:SetText("Re-scan")

-- ============================================================
-- ROW POOL
-- ============================================================

local rowPool = {}
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
        row = CreateFrame("Frame", nil, setup)
        row:SetHeight(ROW_H)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(ROW_H - 4, ROW_H - 4)
        icon:SetPoint("LEFT", row, "LEFT", 4, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.icon = icon

        local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT",  icon,   "RIGHT", 4, 0)
        name:SetPoint("RIGHT", row, "RIGHT", BTN_W*3 + 24, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        row.nameFs = name

        local idFs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idFs:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 4, 0)
        idFs:SetTextColor(0.5, 0.5, 0.5)
        row.idFs = idFs

        -- Three tag buttons
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
-- SCROLL FRAME
-- ============================================================

local scrollFrame = CreateFrame("ScrollFrame", nil, setup, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT",     setup, "TOPLEFT",   8,  -(HEADER_H))
scrollFrame:SetPoint("BOTTOMRIGHT", setup, "BOTTOMRIGHT", -28, 36)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(PANEL_W - 36, 1)
scrollFrame:SetScrollChild(content)

-- ============================================================
-- POPULATE
-- ============================================================

local function UpdateCounts()
    local db = BuffNudgeDB
    countsFs:SetText(
        string.format("|cff4dff4dFood: %d|r   |cff4dc8ffFlask: %d|r   |cffffff00Raid: %d|r",
            #(db.foodIDs   or {}),
            #(db.flaskIDs  or {}),
            #(db.raidBuffs or {}))
    )
end

local function TagButton(btn, tagged)
    if tagged then
        btn:SetBackdropColor(0.05, 0.3, 0.05, 1)
        btn.label:SetText("✓")
    else
        btn:SetBackdropColor(0.1, 0.1, 0.1, 1)
        -- restore original label
        local orig = btn._origLabel
        if orig then btn.label:SetText(orig) end
    end
end

local function Populate()
    -- Release old rows
    for _, r in ipairs(activeRows) do ReleaseRow(r) end
    activeRows = {}

    local buffs = ScanBuffs()
    local totalH = 0

    for idx, buff in ipairs(buffs) do
        local row = AcquireRow()
        row:SetPoint("TOPLEFT",  content, "TOPLEFT",  0, -totalH)
        row:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, -totalH)
        totalH = totalH + ROW_H

        row.icon:SetTexture(buff.icon)
        row.nameFs:SetText(buff.name)
        row.idFs:SetText("["..buff.spellID.."]")

        local db = BuffNudgeDB
        local id = buff.spellID

        -- Store original labels for toggle
        row.btnFood._origLabel  = "+Food"
        row.btnFlask._origLabel = "+Flask"
        row.btnRaid._origLabel  = "+Raid"

        -- Set initial state
        TagButton(row.btnFood,  IdInList(db.foodIDs,  id))
        TagButton(row.btnFlask, IdInList(db.flaskIDs, id))
        TagButton(row.btnRaid,  IdInRaidList(db.raidBuffs, id))

        -- Food button
        row.btnFood:SetScript("OnClick", function(self)
            if IdInList(db.foodIDs, id) then
                RemoveFromList(db.foodIDs, id)
                TagButton(self, false)
            else
                -- Remove from other categories first
                RemoveFromList(db.flaskIDs, id)
                RemoveFromRaidList(db.raidBuffs, id)
                table.insert(db.foodIDs, id)
                TagButton(self, true)
                TagButton(row.btnFlask, false)
                TagButton(row.btnRaid,  false)
            end
            UpdateCounts()
        end)

        -- Flask button
        row.btnFlask:SetScript("OnClick", function(self)
            if IdInList(db.flaskIDs, id) then
                RemoveFromList(db.flaskIDs, id)
                TagButton(self, false)
            else
                RemoveFromList(db.foodIDs, id)
                RemoveFromRaidList(db.raidBuffs, id)
                table.insert(db.flaskIDs, id)
                TagButton(self, true)
                TagButton(row.btnFood, false)
                TagButton(row.btnRaid, false)
            end
            UpdateCounts()
        end)

        -- Raid buff button
        row.btnRaid:SetScript("OnClick", function(self)
            if IdInRaidList(db.raidBuffs, id) then
                RemoveFromRaidList(db.raidBuffs, id)
                TagButton(self, false)
            else
                RemoveFromList(db.foodIDs, id)
                RemoveFromList(db.flaskIDs, id)
                table.insert(db.raidBuffs, { name = buff.name, spellID = id })
                TagButton(self, true)
                TagButton(row.btnFood,  false)
                TagButton(row.btnFlask, false)
            end
            UpdateCounts()
        end)

        table.insert(activeRows, row)
    end

    content:SetHeight(math.max(totalH, 1))
    UpdateCounts()

    if #buffs == 0 then
        print("|cffff9900BuffNudge:|r No buffs found on your character right now.")
    end
end

rescanBtn:SetScript("OnClick", Populate)

-- ============================================================
-- PUBLIC OPEN FUNCTION (called from slash command)
-- ============================================================

function BuffNudgeSetup_Open()
    if setup:IsShown() then
        setup:Hide()
        return
    end
    -- Resize height to fit content (capped at MAX_ROWS)
    local buffs   = ScanBuffs()
    local rows    = math.min(#buffs, MAX_ROWS)
    local height  = HEADER_H + rows * ROW_H + 44
    setup:SetHeight(height)
    setup:Show()
    Populate()
end
