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
-- class: WoW class name as returned by UnitClass() — used to skip the warning
--        when nobody in the group can provide the buff.
local DEFAULT_RAID_BUFFS = {
    { name = "Arcane Intellect",       spellID = 1459,   class = "MAGE"        },
    { name = "Battle Shout",           spellID = 6673,   class = "WARRIOR"     },
    { name = "Power Word: Fortitude",  spellID = 21562,  class = "PRIEST"      },
    { name = "Mark of the Wild",       spellID = 1126,   class = "DRUID"       },
    { name = "Source of Magic",        spellID = 369459, class = "EVOKER"      },
    { name = "Skyfury",                spellID = 462854, class = "SHAMAN"      },
    { name = "Symbiotic Relationship", spellID = 474754, class = "DRUID"       },
}

-- Enchantable slots in Midnight: Helmet, Shoulder, Chest, Boots, Rings, Weapons.
-- Cloak and Bracers are NOT enchantable in Midnight (removed from previous expansions).
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

local RED    = "|cffff4444"  -- missing / error
local ORANGE = "|cffff9900"  -- warning
local YELLOW = "|cffffff00"  -- raid buff missing
local RESET  = "|r"

-- ============================================================
-- SAVED VARIABLES — populated by Setup panel (/bn setup)
-- ============================================================

-- BuffNudgeDB is declared in the TOC and initialised in ADDON_LOADED.
-- Shape: { foodIDs={}, flaskIDs={}, raidBuffs={ {name,spellID}, ... } }

local function DB() return BuffNudgeDB end

-- ============================================================
-- CACHED ID SETS
-- Rebuilt once on load and when the Setup panel saves changes.
-- Using hash sets (id → true) so membership checks are O(1).
-- ============================================================

local cachedFoodSet, cachedFlaskSet, cachedRaidBuffList

function BuffNudge_InvalidateCache()
    cachedFoodSet     = nil
    cachedFlaskSet    = nil
    cachedRaidBuffList = nil
end

local function GetFoodSet()
    if cachedFoodSet then return cachedFoodSet end
    cachedFoodSet = {}
    for _, v in ipairs(DEFAULT_FOOD_IDS)   do cachedFoodSet[v] = true end
    for _, v in ipairs(DB().foodIDs or {}) do cachedFoodSet[v] = true end
    return cachedFoodSet
end

local function GetFlaskSet()
    if cachedFlaskSet then return cachedFlaskSet end
    cachedFlaskSet = {}
    for _, v in ipairs(DEFAULT_FLASK_IDS)   do cachedFlaskSet[v] = true end
    for _, v in ipairs(DB().flaskIDs or {}) do cachedFlaskSet[v] = true end
    return cachedFlaskSet
end

local function GetRaidBuffList()
    if cachedRaidBuffList then return cachedRaidBuffList end
    local seen, out = {}, {}
    for _, e in ipairs(DEFAULT_RAID_BUFFS)   do seen[e.spellID] = true; table.insert(out, e) end
    for _, e in ipairs(DB().raidBuffs or {}) do
        if not seen[e.spellID] then seen[e.spellID] = true; table.insert(out, e) end
    end
    cachedRaidBuffList = out
    return out
end

-- ============================================================
-- HELPERS
-- ============================================================

-- Scan all player buffs once per Refresh and return a spellID → true set.
-- Every subsequent check does a single O(1) table lookup instead of
-- re-iterating up to 40 aura slots per spell ID being tested.
local function GetPlayerAuraSet()
    local set = {}
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex("player", i)
        if not aura then break end
        set[aura.spellId] = true
    end
    return set
end

-- Returns a class-token → true set for everyone in the group.
local function GetGroupClasses()
    local classes = {}
    local _, playerClass = UnitClass("player")
    classes[playerClass] = true
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid"..i) or ("party"..i)
        if UnitExists(unit) then
            local _, class = UnitClass(unit)
            if class then classes[class] = true end
        end
    end
    return classes
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
    -- No Warlock in group = no soulstone possible, skip entirely.
    if not groupClasses["WARLOCK"] then return true end
    if auraSet[20707] then return true end
    -- Scan group members only when necessary.
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid"..i) or ("party"..i)
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

-- Blessing of the Bronze: one ID per class (381732–381758).
-- With auraSet this is 27 hash lookups instead of 27×40 iterations.
local function HasBlessingOfBronze(auraSet)
    for id = 381732, 381758 do
        if auraSet[id] then return true end
    end
    return false
end

local function MissingRaidBuffs(auraSet, groupClasses)
    local missing = {}
    for _, entry in ipairs(GetRaidBuffList()) do
        if not entry.class or groupClasses[entry.class] then
            if not auraSet[entry.spellID] then
                table.insert(missing, entry.name)
            end
        end
    end
    if groupClasses["EVOKER"] and not HasBlessingOfBronze(auraSet) then
        table.insert(missing, "Blessing of the Bronze")
    end
    return missing
end

local function SlotHasEnchant(slotID)
    local link = GetInventoryItemLink("player", slotID)
    if not link then return true end
    local enchantID = link:match("|Hitem:%d+:(%d+):")
    return enchantID ~= nil and enchantID ~= "0"
end

local function MissingEnchants()
    local missing = {}
    for _, slot in ipairs(ENCHANT_SLOTS) do
        if not SlotHasEnchant(slot.id) then
            table.insert(missing, slot.name)
        end
    end
    return missing
end

-- ============================================================
-- REMINDER PANEL
-- ============================================================

local panel = CreateFrame("Frame", "BuffNudgePanel", UIParent, "BackdropTemplate")
panel:SetSize(220, 30)
panel:SetPoint("CENTER", UIParent, "CENTER", 0, 220)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop",  panel.StopMovingOrSizing)
panel:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
panel:SetBackdropColor(0, 0, 0, 0.85)
panel:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
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
        row:SetPoint("TOPLEFT",  panel, "TOPLEFT",  8, -20 - (i - 1) * 18)
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
        rows[i] = row
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

    -- Scan player auras once; all checks below reuse this set.
    local auraSet     = GetPlayerAuraSet()
    local groupClasses = GetGroupClasses()
    local items = {}

    if not HasFood(auraSet)                    then table.insert(items, { text=RED..   "No Food Buff"  ..RESET, icon=ICON_FOOD    }) end
    if not HasFlask(auraSet)                   then table.insert(items, { text=RED..   "No Flask/Phial" ..RESET, icon=ICON_FLASK   }) end
    if not HasSoulstone(auraSet, groupClasses) then table.insert(items, { text=ORANGE.."No Soulstone"   ..RESET, icon=ICON_STONE   }) end

    for _, slot in ipairs(MissingEnchants()) do
        table.insert(items, { text=RED.."Enchant: "..slot..RESET, icon=ICON_ENCHANT })
    end
    for _, buff in ipairs(MissingRaidBuffs(auraSet, groupClasses)) do
        table.insert(items, { text=YELLOW..buff..RESET, icon=ICON_RAIDBUFF })
    end

    if #items == 0 then panel:Hide(); return end

    panel:SetHeight(26 + #items * 18)
    for i, item in ipairs(items) do
        local row = GetRow(i)
        row.text:SetText(item.text)
        row.icon:SetTexture(item.icon)
        row:Show()
    end
    HideRowsFrom(#items + 1)
    panel:Show()
end

-- ============================================================
-- EVENTS
-- ============================================================

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("UNIT_AURA")

local lastCheck = 0
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "BuffNudge" then return end
        -- Initialise SavedVariables
        BuffNudgeDB = BuffNudgeDB or {}
        BuffNudgeDB.foodIDs   = BuffNudgeDB.foodIDs   or {}
        BuffNudgeDB.flaskIDs  = BuffNudgeDB.flaskIDs  or {}
        BuffNudgeDB.raidBuffs = BuffNudgeDB.raidBuffs or {}
        return
    end
    if event == "UNIT_AURA" and arg1 ~= "player" then return end
    local now = GetTime()
    if now - lastCheck < 2 then return end
    lastCheck = now
    C_Timer.After(0.5, BuffNudge_Refresh)
end)

C_Timer.NewTicker(60, function()
    local _, instanceType = IsInInstance()
    if instanceType == "raid" or instanceType == "party" then BuffNudge_Refresh() end
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
    else
        print(ORANGE.."BuffNudge"..RESET..": /bn check | /bn setup | /bn hide | /bn show")
    end
end
