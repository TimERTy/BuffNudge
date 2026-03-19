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
local DEFAULT_RAID_BUFFS = {
    { name = "Arcane Intellect",      spellID = 1459   },  -- Mage
    { name = "Battle Shout",          spellID = 6673   },  -- Warrior
    { name = "Power Word: Fortitude", spellID = 21562  },  -- Priest
    { name = "Mark of the Wild",      spellID = 1126   },  -- Druid
    { name = "Source of Magic",       spellID = 369459 },  -- Augmentation Evoker
    { name = "Skyfury",               spellID = 462854 },  -- Shaman
    { name = "Symbiotic Relationship",spellID = 474754 },  -- Druid (new)
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

-- ============================================================
-- SAVED VARIABLES — populated by Setup panel (/bn setup)
-- ============================================================

-- BuffNudgeDB is declared in the TOC and initialised in ADDON_LOADED.
-- Shape: { foodIDs={}, flaskIDs={}, raidBuffs={ {name,spellID}, ... } }

local function DB()
    return BuffNudgeDB
end

-- Merge default IDs with any the player has captured.
local function GetFoodIDs()
    local ids = {}
    for _, v in ipairs(DEFAULT_FOOD_IDS)    do ids[v] = true end
    for _, v in ipairs(DB().foodIDs or {})  do ids[v] = true end
    local out = {}
    for id in pairs(ids) do table.insert(out, id) end
    return out
end

local function GetFlaskIDs()
    local ids = {}
    for _, v in ipairs(DEFAULT_FLASK_IDS)   do ids[v] = true end
    for _, v in ipairs(DB().flaskIDs or {}) do ids[v] = true end
    local out = {}
    for id in pairs(ids) do table.insert(out, id) end
    return out
end

local function GetRaidBuffList()
    local seen, out = {}, {}
    for _, e in ipairs(DEFAULT_RAID_BUFFS)       do seen[e.spellID] = true; table.insert(out, e) end
    for _, e in ipairs(DB().raidBuffs or {}) do
        if not seen[e.spellID] then
            seen[e.spellID] = true
            table.insert(out, e)
        end
    end
    return out
end

-- ============================================================
-- HELPERS
-- ============================================================

local function HasAuraByID(unit, spellID)
    for i = 1, 40 do
        local aura = C_UnitAuras.GetBuffDataByIndex(unit, i)
        if not aura then break end
        if aura.spellId == spellID then return true end
    end
    return false
end

local function HasAnyAura(unit, ids)
    for _, id in ipairs(ids) do
        if HasAuraByID(unit, id) then return true end
    end
    return false
end

local function HasFood()  return HasAnyAura("player", GetFoodIDs())  end
local function HasFlask() return HasAnyAura("player", GetFlaskIDs()) end

local function HasSoulstone()
    local SOULSTONE_ID = 20707
    if HasAuraByID("player", SOULSTONE_ID) then return true end
    for i = 1, GetNumGroupMembers() do
        local unit = IsInRaid() and ("raid"..i) or ("party"..i)
        if UnitExists(unit) and HasAuraByID(unit, SOULSTONE_ID) then return true end
    end
    return false
end

-- Blessing of the Bronze: one spell ID per class (381732–381758).
-- Present if player has any of them.
local function HasBlessingOfBronze()
    for id = 381732, 381758 do
        if HasAuraByID("player", id) then return true end
    end
    return false
end

local function MissingRaidBuffs()
    local missing = {}
    for _, entry in ipairs(GetRaidBuffList()) do
        if not HasAuraByID("player", entry.spellID) then
            table.insert(missing, entry.name)
        end
    end
    if not HasBlessingOfBronze() then
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
titleText:SetText("|cffff9900BuffNudge|r")

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

    local items = {}

    if not HasFood()  then table.insert(items, { text="|cffff4444No Food Buff|r",   icon=ICON_FOOD    }) end
    if not HasFlask() then table.insert(items, { text="|cffff4444No Flask/Phial|r", icon=ICON_FLASK   }) end
    if not HasSoulstone() then table.insert(items, { text="|cffff9900No Soulstone|r", icon=ICON_STONE }) end

    for _, slot in ipairs(MissingEnchants()) do
        table.insert(items, { text="|cffff4444Enchant: "..slot.."|r", icon=ICON_ENCHANT })
    end
    for _, buff in ipairs(MissingRaidBuffs()) do
        table.insert(items, { text="|cffffff00"..buff.."|r", icon=ICON_RAIDBUFF })
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
        if not panel:IsShown() then print("|cffff9900BuffNudge:|r All good!") end
    elseif msg == "setup" then
        BuffNudgeSetup_Open()
    elseif msg == "hide" then
        panel:Hide()
    elseif msg == "show" then
        panel:Show()
    else
        print("|cffff9900BuffNudge|r: /bn check | /bn setup | /bn hide | /bn show")
    end
end
