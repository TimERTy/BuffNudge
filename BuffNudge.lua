-- BuffNudge.lua
-- Reminds you about missing food, flask/phial, soulstone, enchants,
-- and raid buffs when entering a dungeon or raid instance.

-- ============================================================
-- DEFAULTS — fallback IDs until you capture your own via /bn setup
-- ============================================================

-- NOTE: Midnight has 80+ Hearty Well Fed variants (IDs 454188–1285644+).
-- Use /bn setup to tag your specific food buff — defaults here cover common bases only.
local DEFAULT_FOOD_IDS = {
    462186,  -- Hearty Well Fed (base)
    57399,   -- Well Fed (older fallback)
}

-- All four Midnight stat flasks. Use /bn setup if you use a cauldron variant.
local DEFAULT_FLASK_IDS = {
    1235108,  -- Flask of the Magisters      (Mastery)
    1235110,  -- Flask of the Blood Knights  (Haste)
    1235057,  -- Flask of Thalassian Resistance (Versatility)
    1230878,  -- Flask of the Shattered Sun  (Critical Strike)
}

-- Confirmed Midnight raid buff spell IDs (flagged non-secret by Blizzard).
-- class: WoW class token from UnitClass() — warning skipped if class absent from group.
local DEFAULT_RAID_BUFFS = {
    { name = "Arcane Intellect",       spellID = 1459,   class = "MAGE"    },
    { name = "Battle Shout",           spellID = 6673,   class = "WARRIOR" },
    { name = "Power Word: Fortitude",  spellID = 21562,  class = "PRIEST"  },
    { name = "Mark of the Wild",       spellID = 1126,   class = "DRUID"   },
    { name = "Source of Magic",        spellID = 369459, class = "EVOKER"  },
    { name = "Skyfury",                spellID = 462854, class = "SHAMAN"  },
    { name = "Symbiotic Relationship", spellID = 474754, class = "DRUID"   },
}

-- Enchantable slots in Midnight: Helmet, Shoulder, Chest, Boots, Rings, Weapons.
-- Cloak and Bracers are NOT enchantable in Midnight.
local ENCHANT_SLOTS = {
    { id =  1, name = "Helmet"    },
    { id =  3, name = "Shoulder"  },
    { id =  5, name = "Chest"     },
    { id =  8, name = "Boots"     },
    { id = 11, name = "Ring 1"    },
    { id = 12, name = "Ring 2"    },
    { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand"  },
}

local ICON_FOOD     = 132950
local ICON_FLASK    = 134840
local ICON_STONE    = 136210
local ICON_ENCHANT  = 136243
local ICON_RAIDBUFF = 136116

local RED    = "|cffff4444"
local ORANGE = "|cffff9900"
local YELLOW = "|cffffff00"
local GREEN  = "|cff4dff4d"
local RESET  = "|r"

-- Pre-built constant item strings — no allocation per Refresh.
local TEXT_NO_FOOD    = RED.."No Food Buff"..RESET
local TEXT_NO_FLASK   = RED.."No Flask/Phial"..RESET
local TEXT_NO_STONE   = ORANGE.."No Soulstone"..RESET
local TEXT_NO_BRONZE  = YELLOW.."Blessing of the Bronze"..RESET

-- ============================================================
-- SAVED VARIABLES — populated by Setup panel (/bn setup)
-- ============================================================

-- BuffNudgeDB is declared in the TOC and initialised in ADDON_LOADED.
-- Shape: { foodIDs={}, flaskIDs={}, raidBuffs={ {name,spellID}, ... },
--          fpsHidden=bool, panelX=n, panelY=n, fpsX=n, fpsY=n }

-- ============================================================
-- CACHED ID SETS
-- Rebuilt once on load and when the Setup panel saves changes.
-- Hash sets (id → true) so membership checks are O(1).
-- ============================================================

local cachedFoodSet, cachedFlaskSet, cachedRaidBuffs
local cachedGroupClasses   -- invalidated by GROUP_ROSTER_UPDATE
local cachedMissingEnchants  -- invalidated by PLAYER_EQUIPMENT_CHANGED

function BuffNudge_InvalidateCache()
    cachedFoodSet       = nil
    cachedFlaskSet      = nil
    cachedRaidBuffs     = nil
    cachedGroupClasses  = nil
    cachedMissingEnchants = nil
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

-- Scan all player buffs once per Refresh; returns spellID → true set.
local function GetPlayerAuraSet()
    local set = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        set[aura.spellId] = true
    end
    return set
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
    if auraSet[20707] then return true end
    local inRaid = IsInRaid()  -- hoist out of loop
    for i = 1, GetNumGroupMembers() do
        local unit = inRaid and ("raid"..i) or ("party"..i)
        if UnitExists(unit) then
            for j = 1, 40 do
                local aura = C_UnitAuras.GetBuffDataByIndex(unit, j)
                if not aura then break end
                if aura.spellId == 20707 then return true end
            end
        end
    end
    return false
end

-- Blessing of the Bronze: one ID per class (381732–381758), O(27) hash lookups.
local function HasBlessingOfBronze(auraSet)
    for id = 381732, 381758 do
        if auraSet[id] then return true end
    end
    return false
end

-- Reusable tables to avoid per-Refresh allocation.
local itemsBuf   = {}
local missingBuf = {}

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
-- REMINDER PANEL
-- ============================================================

-- ============================================================
-- EDIT MODE — frames only draggable while Blizzard edit mode is active
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
panel:SetBackdropColor(0, 0, 0, 0.85)
panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
panel._borderColor = { 0.5, 0.5, 0.5, 1 }
panel:Hide()

local titleText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
titleText:SetPoint("TOP", panel, "TOP", 0, -6)
titleText:SetText(ORANGE.."BuffNudge"..RESET)

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function() panel:Hide() end)

local rows = {}

local function GetRow(i)
    if not rows[i] then
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT",  panel, "TOPLEFT",   8, -20 - (i - 1) * 18)
        row:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -8, -20 - (i - 1) * 18)

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

function BuffNudge_Refresh()
    local _, instanceType = IsInInstance()
    if instanceType ~= "raid" and instanceType ~= "party" then
        panel:Hide()
        return
    end

    local auraSet      = GetPlayerAuraSet()
    local groupClasses = GetGroupClasses()

    -- Reuse itemsBuf; track count manually to avoid # on sparse table.
    local n = 0

    if not HasFood(auraSet)                    then n=n+1; itemsBuf[n] = { text=TEXT_NO_FOOD,  icon=ICON_FOOD  } end
    if not HasFlask(auraSet)                   then n=n+1; itemsBuf[n] = { text=TEXT_NO_FLASK, icon=ICON_FLASK } end
    if not HasSoulstone(auraSet, groupClasses) then n=n+1; itemsBuf[n] = { text=TEXT_NO_STONE, icon=ICON_STONE } end

    for _, slot in ipairs(GetMissingEnchants()) do
        n = n + 1
        itemsBuf[n] = { text=RED.."Enchant: "..slot..RESET, icon=ICON_ENCHANT }
    end

    local raidMissing, rCount = MissingRaidBuffs(auraSet, groupClasses)
    for i = 1, rCount do
        n = n + 1
        itemsBuf[n] = { text=raidMissing[i], icon=ICON_RAIDBUFF }
    end

    itemsBuf[n + 1] = nil  -- trim leftovers

    if n == 0 then panel:Hide(); return end

    panel:SetHeight(26 + n * 18)
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

-- Register frames for edit mode drag handling.
movableFrames[1] = panel
movableFrames[2] = fpsFrame

local eventFrame     = CreateFrame("Frame")
local refreshPending = false

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("EDIT_MODE_ENTER")
eventFrame:RegisterEvent("EDIT_MODE_EXIT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")

local lastFire = 0
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "EDIT_MODE_ENTER" then OnEditModeEnter(); return end
    if event == "EDIT_MODE_EXIT"  then OnEditModeExit();  return end

    if event == "ADDON_LOADED" then
        if arg1 ~= "BuffNudge" then return end
        BuffNudgeDB = BuffNudgeDB or {}
        -- Sync with edit mode if already active when addon loads.
        if C_EditMode.IsEditModeActive() then OnEditModeEnter() end
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

    if event == "GROUP_ROSTER_UPDATE" then
        cachedGroupClasses = nil  -- only this cache needs clearing
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        cachedMissingEnchants = nil  -- only this cache needs clearing
    elseif event == "UNIT_AURA" and arg1 ~= "player" then
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
    if msg == "check" then
        BuffNudge_Refresh()
        if not panel:IsShown() then print(ORANGE.."BuffNudge:"..RESET.." All good!") end
    elseif msg == "setup" then
        BuffNudgeSetup_Open()
    elseif msg == "hide" then
        panel:Hide()
    elseif msg == "show" then
        panel:Show()
    elseif msg == "fps" then
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
        print(ORANGE.."BuffNudge"..RESET..": /bn check | /bn setup | /bn hide | /bn show | /bn fps")
    end
end
