-- BuffNudge.lua
-- Reminds you about missing food, flask/phial, soulstone, enchants,
-- and raid buffs when entering a dungeon or raid instance.
local _, ns = ...

local DEFAULT_FOOD_IDS  = ns.DEFAULT_FOOD_IDS
local DEFAULT_FLASK_IDS = ns.DEFAULT_FLASK_IDS
local DEFAULT_RAID_BUFFS = ns.DEFAULT_RAID_BUFFS
local ENCHANT_SLOTS     = ns.ENCHANT_SLOTS

local ICON_FOOD     = ns.ICON_FOOD
local ICON_FLASK    = ns.ICON_FLASK
local ICON_STONE    = ns.ICON_STONE
local ICON_ENCHANT  = ns.ICON_ENCHANT
local ICON_RAIDBUFF = ns.ICON_RAIDBUFF
local ICON_PET      = ns.ICON_PET

local RED    = ns.RED
local ORANGE = ns.ORANGE
local YELLOW = ns.YELLOW
local GREEN  = ns.GREEN
local RESET  = ns.RESET

local TEXT_NO_FOOD   = ns.TEXT_NO_FOOD
local TEXT_NO_FLASK  = ns.TEXT_NO_FLASK
local TEXT_NO_STONE  = ns.TEXT_NO_STONE
local TEXT_NO_BRONZE = ns.TEXT_NO_BRONZE
local TEXT_NO_PET    = ns.TEXT_NO_PET

local PET_CLASSES = ns.PET_CLASSES
local _, PLAYER_CLASS = UnitClass("player")

local EVENTS = ns.EVENTS
local CMD    = ns.CMD

-- ============================================================
-- SAVED VARIABLES — populated by Setup panel (/bn setup)
-- ============================================================

-- BuffNudgeDB is declared in the TOC and initialised in ADDON_LOADED.
-- Shape: { foodIDs={}, flaskIDs={}, raidBuffs={ {name,spellID}, ... },
--          fpsHidden=bool, panelX=n, panelY=n, fpsX=n, fpsY=n }

-- ============================================================
-- CACHES
-- Rebuilt on load and when the Setup panel saves changes.
-- foodSet/flaskSet are spellID → true hash sets for O(1) lookups.
-- groupClasses, raidBuffs, and missingEnchants are arrays/sets rebuilt
-- only when their respective invalidation events fire.
-- ============================================================

local cachedFoodSet, cachedFlaskSet, cachedRaidBuffs
local cachedGroupClasses    -- invalidated by GROUP_ROSTER_UPDATE
local cachedMissingEnchants -- invalidated by PLAYER_EQUIPMENT_CHANGED
local cachedSoulstone       -- invalidated by GROUP_ROSTER_UPDATE

function BuffNudge_InvalidateCache()
    cachedFoodSet       = nil
    cachedFlaskSet      = nil
    cachedRaidBuffs     = nil
    cachedGroupClasses  = nil
    cachedMissingEnchants = nil
    cachedSoulstone     = nil
end

local function GetFoodSet()
    if cachedFoodSet then return cachedFoodSet end
    cachedFoodSet = {}
    for _, v in ipairs(DEFAULT_FOOD_IDS)          do cachedFoodSet[v] = true end
    for _, v in ipairs(BuffNudgeDB.foodIDs or {}) do cachedFoodSet[v] = true end
    return cachedFoodSet
end

local function GetFlaskSet()
    if cachedFlaskSet then return cachedFlaskSet end
    cachedFlaskSet = {}
    for _, v in ipairs(DEFAULT_FLASK_IDS)          do cachedFlaskSet[v] = true end
    for _, v in ipairs(BuffNudgeDB.flaskIDs or {}) do cachedFlaskSet[v] = true end
    return cachedFlaskSet
end

local function GetRaidBuffs()
    if cachedRaidBuffs then return cachedRaidBuffs end
    local seen, out = {}, {}
    for _, e in ipairs(DEFAULT_RAID_BUFFS)          do seen[e.spellID] = true; table.insert(out, e) end
    for _, e in ipairs(BuffNudgeDB.raidBuffs or {}) do
        if not seen[e.spellID] then seen[e.spellID] = true; table.insert(out, e) end
    end
    cachedRaidBuffs = out
    return out
end

-- Group classes: rebuilt only when GROUP_ROSTER_UPDATE fires.
local function GetGroupClasses()
    if cachedGroupClasses then return cachedGroupClasses end
    local classes = {}
    local _, playerClass = UnitClass("player")
    classes[playerClass] = true
    local inRaid = IsInRaid()  -- hoist out of loop
    for i = 1, GetNumGroupMembers() do
        local unit = inRaid and ("raid"..i) or ("party"..i)
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class then classes[class] = true end
        end
    end
    cachedGroupClasses = classes
    return classes
end

-- Enchant results: rebuilt only when PLAYER_EQUIPMENT_CHANGED fires.
local function GetMissingEnchants()
    if cachedMissingEnchants then return cachedMissingEnchants end
    local missing = {}
    for _, slot in ipairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local enchantID = link:match("|Hitem:%d+:(%d+):")
            if not enchantID or enchantID == "0" then
                table.insert(missing, slot.name)
            end
        end
    end
    cachedMissingEnchants = missing
    return missing
end

-- ============================================================
-- HELPERS
-- ============================================================

-- Reused across Refresh calls to avoid per-call allocation.
local playerAuraSet = {}

-- Clears and repopulates playerAuraSet with current player buffs.
local function GetPlayerAuraSet()
    for k in next, playerAuraSet do playerAuraSet[k] = nil end
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 100)
    if auras then
        for _, aura in ipairs(auras) do
            if aura.spellId and not issecretvalue(aura.spellId) then
                playerAuraSet[aura.spellId] = true
            end
        end
    end
    return playerAuraSet
end

local function HasFood(auraSet)
    for id in pairs(GetFoodSet()) do
        if auraSet[id] then return true end
    end
    return false
end

local function HasFlask(auraSet)
    for id in pairs(GetFlaskSet()) do
        if auraSet[id] then return true end
    end
    return false
end

local function HasSoulstone(auraSet, groupClasses)
    if not groupClasses["WARLOCK"] then return true end
    if auraSet[20707] then return true end  -- player has it (fresh from auraSet each Refresh)
    if cachedSoulstone ~= nil then return cachedSoulstone end
    -- Scan group members — result cached until GROUP_ROSTER_UPDATE.
    local inRaid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = inRaid and ("raid"..i) or ("party"..i)
        if UnitExists(unit) then
            local auras = C_UnitAuras.GetUnitAuras(unit, "HELPFUL", 100)
            if auras then
                for _, aura in ipairs(auras) do
                    if aura.spellId and not issecretvalue(aura.spellId) and aura.spellId == 20707 then
                        cachedSoulstone = true
                        return true
                    end
                end
            end
        end
    end
    cachedSoulstone = false
    return false
end

-- Blessing of the Bronze: one ID per class (381732–381758), O(27) hash lookups.
local function HasBlessingOfBronze(auraSet)
    for id = 381732, 381758 do
        if auraSet[id] then return true end
    end
    return false
end

-- Pre-allocated buffers — entries reused each Refresh, no table allocation in hot path.
-- Max items: food(1) + flask(1) + stone(1) + pet(1) + enchants(8) + raid buffs(8) = 20.
local itemsBuf   = {}
local missingBuf = {}
for i = 1, 20 do itemsBuf[i] = { text = "", icon = 0 } end

local function MissingRaidBuffs(auraSet, groupClasses)
    local n = 0
    for _, entry in ipairs(GetRaidBuffs()) do
        if (not entry.class or groupClasses[entry.class]) and not auraSet[entry.spellID] then
            n = n + 1
            missingBuf[n] = YELLOW..entry.name..RESET
        end
    end
    if groupClasses["EVOKER"] and not HasBlessingOfBronze(auraSet) then
        n = n + 1
        missingBuf[n] = TEXT_NO_BRONZE
    end
    missingBuf[n + 1] = nil  -- trim any leftover from a prior longer run
    return missingBuf, n
end

-- ============================================================
-- DRAG SUPPORT — frames movable via /bn move (edit mode events unavailable in 120001)
-- ============================================================

local movableFrames = {}  -- registered below after each frame is created

local function SetFrameMovable(frame, enabled)
    frame:SetMovable(enabled)
    frame:EnableMouse(enabled)
    if enabled then
        frame:RegisterForDrag("LeftButton")
        frame:SetBackdropBorderColor(1, 0.6, 0, 1)   -- orange highlight
    else
        frame:RegisterForDrag()
        frame:SetBackdropBorderColor(unpack(frame._borderColor))
    end
end

local function OnEditModeEnter()
    for _, f in ipairs(movableFrames) do SetFrameMovable(f, true) end
end

local function OnEditModeExit()
    for _, f in ipairs(movableFrames) do SetFrameMovable(f, false) end
end

-- ============================================================
-- REMINDER PANEL
-- ============================================================

local panel = CreateFrame("Frame", "BuffNudgePanel", UIParent, "BackdropTemplate")
panel:SetSize(220, 30)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
panel:SetMovable(false)
panel:EnableMouse(false)
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    BuffNudgeDB.panelX = self:GetLeft()
    BuffNudgeDB.panelY = self:GetTop()
end)
panel:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
panel:SetBackdropColor(0, 0, 0, 0)
panel:SetBackdropBorderColor(0, 0, 0, 0)
panel._borderColor = { 0, 0, 0, 0 }
panel:Hide()

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function() panel:Hide() end)
closeBtn:Hide()

local rows = {}

local function GetRow(i)
    if not rows[i] then
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT",  panel, "TOPLEFT",   8, -4 - (i - 1) * 18)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -4 - (i - 1) * 18)

        local icon = row:CreateTexture(nil, "ARTWORK")
        icon:SetSize(14, 14)
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        text:SetPoint("LEFT",  icon, "RIGHT", 4, 0)
        text:SetPoint("RIGHT", row,  "RIGHT", 0, 0)
        text:SetJustifyH("LEFT")

        row.icon = icon
        row.text = text
        rows[i]  = row
    end
    return rows[i]
end

local function HideRowsFrom(from)
    for i = from, #rows do rows[i]:Hide() end
end

local debugMode = false
local inCombat   = UnitAffectingCombat("player")

function BuffNudge_Refresh()
    local _, instanceType = IsInInstance()
    if not debugMode and instanceType ~= "raid" and instanceType ~= "party" then
        panel:Hide()
        return
    end

    local auraSet      = GetPlayerAuraSet()
    local groupClasses = GetGroupClasses()

    -- Reuse itemsBuf; track count manually to avoid # on sparse table.
    local n = 0

    local function push(text, icon) n=n+1; itemsBuf[n].text=text; itemsBuf[n].icon=icon end

    if not inCombat and not HasFood(auraSet)               then push(TEXT_NO_FOOD,  ICON_FOOD)  end
    if not HasFlask(auraSet)                               then push(TEXT_NO_FLASK, ICON_FLASK) end
    if not HasSoulstone(auraSet, groupClasses)             then push(TEXT_NO_STONE, ICON_STONE) end
    if PET_CLASSES[PLAYER_CLASS] and not UnitExists("pet") then push(TEXT_NO_PET,   ICON_PET)   end

    if not inCombat then
        for _, slot in ipairs(GetMissingEnchants()) do
            push(RED.."Enchant: "..slot..RESET, ICON_ENCHANT)
        end
    end

    local raidMissing, rCount = MissingRaidBuffs(auraSet, groupClasses)
    for i = 1, rCount do push(raidMissing[i], ICON_RAIDBUFF) end

    itemsBuf[n + 1] = nil  -- trim leftovers

    if n == 0 then panel:Hide(); return end

    panel:SetHeight(8 + n * 18)
    for i = 1, n do
        local row = GetRow(i)
        row.text:SetText(itemsBuf[i].text)
        row.icon:SetTexture(itemsBuf[i].icon)
        row:Show()
    end
    HideRowsFrom(n + 1)
    panel:Show()
end

-- ============================================================
-- FPS DISPLAY
-- ============================================================

local fpsFrame = CreateFrame("Frame", "BuffNudgeFPS", UIParent, "BackdropTemplate")
fpsFrame:SetSize(58, 20)
fpsFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -16, -16)
fpsFrame:SetMovable(false)
fpsFrame:EnableMouse(false)
fpsFrame:SetScript("OnDragStart", fpsFrame.StartMoving)
fpsFrame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    BuffNudgeDB.fpsX = self:GetLeft()
    BuffNudgeDB.fpsY = self:GetTop()
end)
fpsFrame:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 8,
    insets   = { left=2, right=2, top=2, bottom=2 },
})
fpsFrame:SetBackdropColor(0, 0, 0, 0.6)
fpsFrame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
fpsFrame._borderColor = { 0.3, 0.3, 0.3, 0.8 }

local fpsText = fpsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
fpsText:SetAllPoints()

local fpsTicker
local lastFpsValue = -1

local function FpsColor(fps)
    if fps >= 60 then return GREEN end
    if fps >= 30 then return YELLOW end
    return RED
end

local function StartFpsTicker()
    if fpsTicker then return end
    fpsTicker = C_Timer.NewTicker(1, function()
        local fps = math.floor(GetFramerate())
        if fps ~= lastFpsValue then
            lastFpsValue = fps
            fpsText:SetText(string.format("%s%d"..RESET.." fps", FpsColor(fps), fps))
        end
    end)
end

local function StopFpsTicker()
    if fpsTicker then
        fpsTicker:Cancel()
        fpsTicker = nil
        lastFpsValue = -1
    end
end

-- ============================================================
-- EVENTS
-- ============================================================

-- Frames registered for drag support (/bn move toggles movability).
movableFrames[1] = panel
movableFrames[2] = fpsFrame

local eventFrame     = CreateFrame("Frame")
local refreshPending = false

local function safeRegister(event)
    local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok then
        print("BuffNudge: skipping unknown event: " .. event)
    end
end

safeRegister(EVENTS.ADDON_LOADED)
safeRegister(EVENTS.EDIT_MODE_ENTER)
safeRegister(EVENTS.EDIT_MODE_EXIT)
safeRegister(EVENTS.PLAYER_ENTERING_WORLD)
safeRegister(EVENTS.ZONE_CHANGED_NEW_AREA)
safeRegister(EVENTS.GROUP_ROSTER_UPDATE)
safeRegister(EVENTS.PLAYER_EQUIPMENT_CHANGED)
safeRegister(EVENTS.PLAYER_REGEN_ENABLED)
safeRegister(EVENTS.PLAYER_REGEN_DISABLED)
safeRegister(EVENTS.UNIT_AURA)

local lastFire = 0
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == EVENTS.EDIT_MODE_ENTER then OnEditModeEnter(); return end
    if event == EVENTS.EDIT_MODE_EXIT  then OnEditModeExit();  return end

    if event == EVENTS.ADDON_LOADED then
        if arg1 ~= "BuffNudge" then return end
        BuffNudgeDB = BuffNudgeDB or {}
        inCombat = UnitAffectingCombat("player")  -- sync in case addon loaded mid-combat
        if C_EditMode and C_EditMode.IsEditModeActive and C_EditMode.IsEditModeActive() then OnEditModeEnter() end
        BuffNudgeDB.foodIDs   = BuffNudgeDB.foodIDs   or {}
        BuffNudgeDB.flaskIDs  = BuffNudgeDB.flaskIDs  or {}
        BuffNudgeDB.raidBuffs = BuffNudgeDB.raidBuffs or {}
        if BuffNudgeDB.fpsHidden then
            StopFpsTicker()
            fpsFrame:Hide()
        else
            StartFpsTicker()
        end
        if BuffNudgeDB.panelX then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.panelX, BuffNudgeDB.panelY)
        end
        if BuffNudgeDB.fpsX then
            fpsFrame:ClearAllPoints()
            fpsFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.fpsX, BuffNudgeDB.fpsY)
        end
        return
    end

    if event == EVENTS.PLAYER_REGEN_DISABLED then
        inCombat = true
        BuffNudge_Refresh()  -- bypass debounce: hide out-of-combat rows immediately
        return
    elseif event == EVENTS.PLAYER_REGEN_ENABLED then
        inCombat = false
    elseif event == EVENTS.GROUP_ROSTER_UPDATE then
        cachedGroupClasses = nil
        cachedSoulstone    = nil
    elseif event == EVENTS.PLAYER_EQUIPMENT_CHANGED then
        cachedMissingEnchants = nil
    elseif event == EVENTS.UNIT_AURA and arg1 ~= "player" then
        return
    end

    local now = GetTime()
    if now - lastFire < 2 then return end
    lastFire = now

    if not refreshPending then
        refreshPending = true
        C_Timer.After(0.5, function()
            refreshPending = false
            BuffNudge_Refresh()
        end)
    end
end)

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

SLASH_BUFFNUDGE1 = "/buffnudge"
SLASH_BUFFNUDGE2 = "/bn"

SlashCmdList["BUFFNUDGE"] = function(msg)
    msg = strtrim(msg:lower())
    if msg == CMD.CHECK then
        BuffNudge_Refresh()
        if not panel:IsShown() then print(ORANGE.."BuffNudge:"..RESET.." All good!") end
    elseif msg == CMD.SETUP then
        BuffNudgeSetup_Open()
    elseif msg == CMD.HIDE then
        panel:Hide()
    elseif msg == CMD.SHOW then
        panel:Show()
    elseif msg == CMD.MOVE then
        local moving = not panel:IsMovable()
        for _, f in ipairs(movableFrames) do SetFrameMovable(f, moving) end
        print(ORANGE.."BuffNudge:"..RESET.." Move mode "..(moving and GREEN.."ON"..RESET.." — drag frames to reposition" or RED.."OFF"..RESET))
    elseif msg == CMD.DEBUG then
        debugMode = not debugMode
        print(ORANGE.."BuffNudge:"..RESET.." Debug mode "..(debugMode and GREEN.."ON"..RESET or RED.."OFF"..RESET))
        BuffNudge_Refresh()
    elseif msg == CMD.FPS then
        if fpsFrame:IsShown() then
            fpsFrame:Hide()
            StopFpsTicker()
            BuffNudgeDB.fpsHidden = true
        else
            fpsFrame:Show()
            StartFpsTicker()
            BuffNudgeDB.fpsHidden = false
        end
    else
        local cmds = {}
        for _, v in pairs(CMD) do cmds[#cmds+1] = "/bn "..v end
        table.sort(cmds)
        print(ORANGE.."BuffNudge"..RESET..": "..table.concat(cmds, " | "))
    end
end
