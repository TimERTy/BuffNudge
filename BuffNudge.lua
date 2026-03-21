-- BuffNudge.lua
-- Reminds you about missing food, flask/phial, soulstone, enchants,
-- and raid buffs when entering a dungeon or raid instance.
local _, ns = ...

local DEFAULT_FOOD_IDS            = ns.DEFAULT_FOOD_IDS
local DEFAULT_FLASK_IDS           = ns.DEFAULT_FLASK_IDS
local DEFAULT_HEALTHSTONE_ITEM_IDS = ns.DEFAULT_HEALTHSTONE_ITEM_IDS
local DEFAULT_RAID_BUFFS           = ns.DEFAULT_RAID_BUFFS
local ENCHANT_SLOTS                = ns.ENCHANT_SLOTS
local SOCKET_SLOTS                 = ns.SOCKET_SLOTS

local ICON_FOOD     = ns.ICON_FOOD
local ICON_FLASK    = ns.ICON_FLASK
local ICON_STONE    = ns.ICON_STONE
local ICON_ENCHANT  = ns.ICON_ENCHANT
local ICON_RAIDBUFF = ns.ICON_RAIDBUFF
local ICON_PET          = ns.ICON_PET
local ICON_SOCKET       = ns.ICON_SOCKET
local ICON_HEALTHSTONE  = ns.ICON_HEALTHSTONE

local RED    = ns.RED
local ORANGE = ns.ORANGE
local YELLOW = ns.YELLOW
local GREEN  = ns.GREEN
local RESET  = ns.RESET

local TEXT_NO_FOOD   = ns.TEXT_NO_FOOD
local TEXT_NO_FLASK  = ns.TEXT_NO_FLASK
local TEXT_NO_STONE       = ns.TEXT_NO_STONE
local TEXT_NO_BRONZE      = ns.TEXT_NO_BRONZE
local TEXT_NO_PET         = ns.TEXT_NO_PET
local TEXT_NO_HEALTHSTONE = ns.TEXT_NO_HEALTHSTONE

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

local cachedFoodSet, cachedFoodIcon, cachedFlaskSet, cachedRaidBuffs
local cachedGroupClasses    -- invalidated by GROUP_ROSTER_UPDATE
local cachedMissingEnchants -- invalidated by PLAYER_EQUIPMENT_CHANGED
local cachedMissingSockets  -- invalidated by PLAYER_EQUIPMENT_CHANGED
local cachedSoulstone       -- invalidated by GROUP_ROSTER_UPDATE
local cachedHasHealthstone  -- invalidated by BAG_UPDATE_DELAYED
local cachedProfile         -- invalidated by BuffNudge_InvalidateCache

function BuffNudge_InvalidateCache()
    cachedFoodSet         = nil
    cachedFoodIcon        = nil
    cachedFlaskSet        = nil
    cachedRaidBuffs       = nil
    cachedGroupClasses    = nil
    cachedMissingEnchants = nil
    cachedMissingSockets  = nil
    cachedSoulstone       = nil
    cachedHasHealthstone  = nil
    cachedProfile         = nil
end

-- Returns the currently active profile table from BuffNudgeDB.
-- Result is cached; invalidated by BuffNudge_InvalidateCache() on profile switch or save.
local function GetProfile()
    if cachedProfile then return cachedProfile end
    local name = BuffNudgeDB.activeProfile or "Default"
    local p = BuffNudgeDB.profiles and BuffNudgeDB.profiles[name]
    if not p then
        p = { foodIDs={}, flaskIDs={}, raidBuffs={},
              checkFood=true, checkFlask=true, checkSoulstone=true, checkHealthstone=true,
              checkPet=true, checkEnchant=true, checkSocket=true, checkRaidBuff=true }
        if BuffNudgeDB.profiles then BuffNudgeDB.profiles[name] = p end
    end
    cachedProfile = p
    return p
end
ns.GetProfile = GetProfile

local function GetFoodSet()
    if cachedFoodSet then return cachedFoodSet end
    cachedFoodSet = {}
    for _, v in ipairs(DEFAULT_FOOD_IDS)           do cachedFoodSet[v] = true end
    for _, v in ipairs(GetProfile().foodIDs or {}) do cachedFoodSet[v] = true end
    -- Icon cached separately so the hash set stays clean (no string key mixed with int keys).
    cachedFoodIcon = C_Spell.GetSpellTexture(DEFAULT_FOOD_IDS[1]) or ICON_FOOD
    return cachedFoodSet
end

local function GetFlaskSet()
    if cachedFlaskSet then return cachedFlaskSet end
    cachedFlaskSet = {}
    for _, v in ipairs(DEFAULT_FLASK_IDS)            do cachedFlaskSet[v] = true end
    for _, v in ipairs(GetProfile().flaskIDs or {})  do cachedFlaskSet[v] = true end
    return cachedFlaskSet
end

local function GetRaidBuffs()
    if cachedRaidBuffs then return cachedRaidBuffs end
    local seen, out = {}, {}
    for _, e in ipairs(DEFAULT_RAID_BUFFS) do
        seen[e.spellID] = true
        -- Cache texture at build time so Refresh never calls GetSpellTexture
        local entry = { name=e.name, spellID=e.spellID, class=e.class,
                        icon = e.icon or C_Spell.GetSpellTexture(e.spellID) or ICON_RAIDBUFF }
        table.insert(out, entry)
    end
    for _, e in ipairs(GetProfile().raidBuffs or {}) do
        if not seen[e.spellID] then
            seen[e.spellID] = true
            local entry = { name=e.name, spellID=e.spellID,
                            icon = e.icon or C_Spell.GetSpellTexture(e.spellID) or ICON_RAIDBUFF }
            table.insert(out, entry)
        end
    end
    cachedRaidBuffs = out
    return out
end

-- Group classes: rebuilt only when GROUP_ROSTER_UPDATE fires.
local function GetGroupClasses()
    if cachedGroupClasses then return cachedGroupClasses end
    local classes = {}
    classes[PLAYER_CLASS] = true
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

-- Socket results: rebuilt only when PLAYER_EQUIPMENT_CHANGED fires.
-- Uses pre-built slot.textBase strings from BuffNudgeConstants.lua; appends count suffix.
local function GetMissingSockets()
    if cachedMissingSockets then return cachedMissingSockets end
    local missing = {}
    for _, slot in ipairs(SOCKET_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local stats = C_Item.GetItemStats(link)
            if stats then
                local emptyCount = 0
                for stat, count in pairs(stats) do
                    if stat:find("EMPTY_SOCKET") then emptyCount = emptyCount + count end
                end
                if emptyCount > 0 then
                    local suffix = emptyCount > 1 and (" ("..emptyCount.."x)|r") or "|r"
                    table.insert(missing, slot.textBase..suffix)
                end
            end
        end
    end
    cachedMissingSockets = missing
    return missing
end

-- Enchant results: rebuilt only when PLAYER_EQUIPMENT_CHANGED fires.
-- Uses pre-built slot.textMissing strings from BuffNudgeConstants.lua.
local function GetMissingEnchants()
    if cachedMissingEnchants then return cachedMissingEnchants end
    local missing = {}
    for _, slot in ipairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local enchantID = link:match("|Hitem:%d+:(%d+):")
            if not enchantID or enchantID == "0" then
                table.insert(missing, slot.textMissing)
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

local function HasHealthstone()
    if cachedHasHealthstone ~= nil then return cachedHasHealthstone end
    local found = false
    for _, id in ipairs(DEFAULT_HEALTHSTONE_ITEM_IDS) do
        if C_Item.GetItemCount(id) > 0 then found = true; break end
    end
    -- Fallback: scan bags for any item whose name contains "healthstone"
    -- catches Demonic Healthstone and any future variants with unknown IDs.
    if not found then
        for bag = 0, 4 do
            for slot = 1, C_Container.GetContainerNumSlots(bag) do
                local info = C_Container.GetContainerItemInfo(bag, slot)
                if info and info.itemID then
                    local name = C_Item.GetItemNameByID(info.itemID)
                    if name and name:lower():find("healthstone", 1, true) then
                        found = true; break
                    end
                end
            end
            if found then break end
        end
    end
    cachedHasHealthstone = found
    return found
end

-- Blessing of the Bronze: one ID per class (381732–381758), O(27) hash lookups.
local function HasBlessingOfBronze(auraSet)
    for id = 381732, 381758 do
        if auraSet[id] then return true end
    end
    return false
end

-- Pre-allocated buffers — entries reused each Refresh, no table allocation in hot path.
-- Max items: food(1) + flask(1) + stone(1) + pet(1) + enchants(8) + sockets(14) + raid buffs(8) = 33.
local itemsBuf       = {}
local missingBuf        = {}
local missingIconBuf    = {}
local missingSpellIDBuf = {}
for i = 1, 40 do itemsBuf[i] = { text = "", icon = 0 } end

local function MissingRaidBuffs(auraSet, groupClasses)
    local n = 0
    for _, entry in ipairs(GetRaidBuffs()) do
        if (not entry.class or groupClasses[entry.class]) and not auraSet[entry.spellID] then
            n = n + 1
            missingBuf[n]        = YELLOW..entry.name..RESET
            missingIconBuf[n]    = entry.icon  -- pre-cached in GetRaidBuffs()
            missingSpellIDBuf[n] = entry.spellID
        end
    end
    if groupClasses["EVOKER"] and not HasBlessingOfBronze(auraSet) then
        n = n + 1
        missingBuf[n]        = TEXT_NO_BRONZE
        missingIconBuf[n]    = C_Spell.GetSpellTexture(381732) or ICON_RAIDBUFF
        missingSpellIDBuf[n] = 381732
    end
    missingBuf[n + 1]        = nil  -- trim any leftover from a prior longer run
    missingIconBuf[n + 1]    = nil
    missingSpellIDBuf[n + 1] = nil
    return missingBuf, missingIconBuf, missingSpellIDBuf, n
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

-- ============================================================
-- RAID BUFF PANEL
-- ============================================================

local raidBuffPanel = CreateFrame("Frame", "BuffNudgeRaidPanel", UIParent, "BackdropTemplate")
raidBuffPanel:SetSize(200, 30)
raidBuffPanel:SetPoint("CENTER", UIParent, "CENTER", 120, 220)
raidBuffPanel:SetMovable(false)
raidBuffPanel:EnableMouse(false)
raidBuffPanel:SetScript("OnDragStart", raidBuffPanel.StartMoving)
raidBuffPanel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    BuffNudgeDB.raidPanelX = self:GetLeft()
    BuffNudgeDB.raidPanelY = self:GetTop()
end)
raidBuffPanel:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
raidBuffPanel:SetBackdropColor(0, 0, 0, 0)
raidBuffPanel:SetBackdropBorderColor(0, 0, 0, 0)
raidBuffPanel._borderColor = { 0, 0, 0, 0 }
raidBuffPanel:Hide()

local raidRows = {}

local function GetRaidRow(i)
    if not raidRows[i] then
        local row = CreateFrame("Button", nil, raidBuffPanel, "SecureActionButtonTemplate")
        row:SetHeight(18)
        row:SetPoint("TOPLEFT",  raidBuffPanel, "TOPLEFT",   8, -4 - (i-1)*18)
        row:SetPoint("TOPRIGHT", raidBuffPanel, "TOPRIGHT", -8, -4 - (i-1)*18)
        row:EnableMouse(false)
        row:RegisterForClicks("LeftButtonUp")
        row:SetAttribute("type", "spell")
        row:SetNormalTexture("")
        row:SetHighlightTexture("")
        row:SetPushedTexture("")

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(1, 1, 1, 0.08)

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
        raidRows[i] = row
    end
    return raidRows[i]
end

local function HideRaidRowsFrom(from)
    for i = from, #raidRows do raidRows[i]:Hide() end
end

-- ============================================================
-- CLASS PANEL  (warlock-specific: soulstone / healthstone)
-- ============================================================

local classPanel = CreateFrame("Frame", "BuffNudgeClassPanel", UIParent, "BackdropTemplate")
classPanel:SetSize(180, 30)
classPanel:SetPoint("CENTER", UIParent, "CENTER", -130, 220)
classPanel:SetMovable(false)
classPanel:EnableMouse(false)
classPanel:SetScript("OnDragStart", classPanel.StartMoving)
classPanel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    BuffNudgeDB.classPanelX = self:GetLeft()
    BuffNudgeDB.classPanelY = self:GetTop()
end)
classPanel:SetBackdrop({
    bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets   = { left=3, right=3, top=3, bottom=3 },
})
classPanel:SetBackdropColor(0, 0, 0, 0)
classPanel:SetBackdropBorderColor(0, 0, 0, 0)
classPanel._borderColor = { 0, 0, 0, 0 }
classPanel:Hide()

local classRows = {}

local function GetClassRow(i)
    if not classRows[i] then
        local row = CreateFrame("Frame", nil, classPanel)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT",  classPanel, "TOPLEFT",   8, -4 - (i-1)*18)
        row:SetPoint("TOPRIGHT", classPanel, "TOPRIGHT", -8, -4 - (i-1)*18)

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
        classRows[i] = row
    end
    return classRows[i]
end

local function HideClassRowsFrom(from)
    for i = from, #classRows do classRows[i]:Hide() end
end

local function RefreshClassPanel(auraSet, groupClasses, p)
    local n = 0
    -- Soulstone: only the warlock needs to act on this
    if PLAYER_CLASS == "WARLOCK" and p.checkSoulstone and not HasSoulstone(auraSet, groupClasses) then
        n = n + 1
        local row = GetClassRow(n)
        row.icon:SetTexture(ICON_STONE)
        row.text:SetText(TEXT_NO_STONE)
        row:Show()
    end
    -- Pet: hunter/warlock needs a pet active
    if p.checkPet and PET_CLASSES[PLAYER_CLASS] and not UnitExists("pet") then
        n = n + 1
        local row = GetClassRow(n)
        row.icon:SetTexture(ICON_PET)
        row.text:SetText(TEXT_NO_PET)
        row:Show()
    end
    -- Healthstone: relevant to everyone when a warlock is in the group
    if groupClasses["WARLOCK"] and p.checkHealthstone and not HasHealthstone() then
        n = n + 1
        local row = GetClassRow(n)
        row.icon:SetTexture(ICON_HEALTHSTONE)
        row.text:SetText(TEXT_NO_HEALTHSTONE)
        row:Show()
    end
    if n == 0 then classPanel:Hide(); return end
    HideClassRowsFrom(n + 1)
    classPanel:SetHeight(8 + n * 18)
    classPanel:Show()
end

local debugMode = false
local inCombat   = UnitAffectingCombat("player")

local function RefreshRaidPanel(auraSet, groupClasses, p)
    if inCombat then return end  -- secure frame attributes/visibility cannot change during combat
    if not p.checkRaidBuff then raidBuffPanel:Hide(); return end
    local texts, icons, spellIDs, n = MissingRaidBuffs(auraSet, groupClasses)
    if n == 0 then raidBuffPanel:Hide(); return end
    raidBuffPanel:SetHeight(8 + n * 18)
    for i = 1, n do
        local row = GetRaidRow(i)
        row.icon:SetTexture(icons[i])
        local spellID = spellIDs[i]
        local known   = spellID and IsSpellKnown(spellID, false)
        if known then
            row.text:SetText(texts[i].." |cffaaaaaa[cast]|r")
            row:SetAttribute("spell", spellID)
            row:EnableMouse(true)
        else
            row.text:SetText(texts[i])
            row:SetAttribute("spell", nil)
            row:EnableMouse(false)
        end
        row:Show()
    end
    HideRaidRowsFrom(n + 1)
    raidBuffPanel:Show()
end

local function DebugPopulatePanels()
    -- Main panel: one row per check type so all panels are visible for repositioning
    local n = 0
    local function push(text, icon) n=n+1; itemsBuf[n].text=text; itemsBuf[n].icon=icon end
    push(TEXT_NO_FOOD,  ICON_FOOD)
    push(TEXT_NO_FLASK, ICON_FLASK)
    for _, slot in ipairs(ENCHANT_SLOTS) do push(RED.."Enchant: "..slot.name..RESET, ICON_ENCHANT) end
    for _, slot in ipairs(SOCKET_SLOTS)  do push(RED.."Socket: " ..slot.name..RESET, ICON_SOCKET)  end
    panel:SetHeight(8 + n * 18)
    for i = 1, n do
        local row = GetRow(i)
        row.text:SetText(itemsBuf[i].text)
        row.icon:SetTexture(itemsBuf[i].icon)
        row:Show()
    end
    HideRowsFrom(n + 1)
    panel:Show()

    -- Class panel: show all class-specific rows
    local cn = 0
    local function cpush(text, icon)
        cn = cn + 1
        local row = GetClassRow(cn)
        row.text:SetText(text)
        row.icon:SetTexture(icon)
        row:Show()
    end
    cpush(TEXT_NO_STONE,       ICON_STONE)
    cpush(TEXT_NO_HEALTHSTONE, ICON_HEALTHSTONE)
    cpush(TEXT_NO_PET,         ICON_PET)
    HideClassRowsFrom(cn + 1)
    classPanel:SetHeight(8 + cn * 18)
    classPanel:Show()

    -- Raid panel: show all buffs (skip secure-frame update if in combat)
    if not inCombat then
        local rn = 0
        for _, entry in ipairs(GetRaidBuffs()) do
            rn = rn + 1
            local row = GetRaidRow(rn)
            row.icon:SetTexture(entry.icon)
            local known = entry.spellID and IsSpellKnown(entry.spellID)
            if known then
                row.text:SetText(YELLOW..entry.name..RESET.." |cffaaaaaa[cast]|r")
                row:SetAttribute("spell", entry.spellID)
                row:EnableMouse(true)
            else
                row.text:SetText(YELLOW..entry.name..RESET)
                row:SetAttribute("spell", nil)
                row:EnableMouse(false)
            end
            row:Show()
        end
        rn = rn + 1
        local bronzeRow = GetRaidRow(rn)
        bronzeRow.icon:SetTexture(C_Spell.GetSpellTexture(381732) or ICON_RAIDBUFF)
        bronzeRow.text:SetText(TEXT_NO_BRONZE)
        bronzeRow:SetAttribute("spell", nil)
        bronzeRow:EnableMouse(false)
        bronzeRow:Show()
        HideRaidRowsFrom(rn + 1)
        raidBuffPanel:SetHeight(8 + rn * 18)
        raidBuffPanel:Show()
    end
end

function BuffNudge_Refresh()
    local _, instanceType = IsInInstance()
    local inInstance = instanceType == "raid" or instanceType == "party"
    if not debugMode and not inInstance and not BuffNudgeDB.showAlways then
        panel:Hide()
        raidBuffPanel:Hide()
        classPanel:Hide()
        return
    end
    if not debugMode and BuffNudgeDB.hideInCombat and inCombat then
        panel:Hide()
        raidBuffPanel:Hide()
        classPanel:Hide()
        return
    end

    if debugMode then
        DebugPopulatePanels()
        return
    end

    local auraSet      = GetPlayerAuraSet()
    local groupClasses = GetGroupClasses()
    local p            = GetProfile()

    -- Reuse itemsBuf; track count manually to avoid # on sparse table.
    local n = 0
    local function push(text, icon) n=n+1; itemsBuf[n].text=text; itemsBuf[n].icon=icon end

    if p.checkFood    and not inCombat and not HasFood(auraSet)                              then push(TEXT_NO_FOOD,  cachedFoodIcon or ICON_FOOD) end
    if p.checkFlask   and not HasFlask(auraSet)                                              then push(TEXT_NO_FLASK, ICON_FLASK) end
    if p.checkEnchant and not inCombat then
        for _, text in ipairs(GetMissingEnchants()) do push(text, ICON_ENCHANT) end
    end
    if p.checkSocket and not inCombat then
        for _, text in ipairs(GetMissingSockets()) do push(text, ICON_SOCKET) end
    end

    if n == 0 then
        panel:Hide()
    else
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

    RefreshRaidPanel(auraSet, groupClasses, p)
    RefreshClassPanel(auraSet, groupClasses, p)
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
movableFrames[3] = raidBuffPanel
movableFrames[4] = classPanel

local eventFrame     = CreateFrame("Frame")
local refreshPending = false

local function safeRegister(event)
    local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
    if not ok and debugMode then
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
safeRegister(EVENTS.BAG_UPDATE_DELAYED)

local lastFire = 0
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == EVENTS.EDIT_MODE_ENTER then OnEditModeEnter(); return end
    if event == EVENTS.EDIT_MODE_EXIT  then OnEditModeExit();  return end

    if event == EVENTS.ADDON_LOADED then
        if arg1 ~= "BuffNudge" then return end
        BuffNudgeDB = BuffNudgeDB or {}
        inCombat = UnitAffectingCombat("player")  -- sync in case addon loaded mid-combat
        if C_EditMode and C_EditMode.IsEditModeActive and C_EditMode.IsEditModeActive() then OnEditModeEnter() end
        -- Migrate old flat format to profiles structure.
        if BuffNudgeDB.foodIDs or BuffNudgeDB.flaskIDs or BuffNudgeDB.raidBuffs then
            BuffNudgeDB.profiles = BuffNudgeDB.profiles or {}
            BuffNudgeDB.profiles["Default"] = {
                foodIDs      = BuffNudgeDB.foodIDs   or {},
                flaskIDs     = BuffNudgeDB.flaskIDs  or {},
                raidBuffs    = BuffNudgeDB.raidBuffs or {},
                checkFood=true, checkFlask=true, checkSoulstone=true, checkHealthstone=true,
                checkPet=true, checkEnchant=true, checkSocket=true, checkRaidBuff=true,
            }
            BuffNudgeDB.foodIDs   = nil
            BuffNudgeDB.flaskIDs  = nil
            BuffNudgeDB.raidBuffs = nil
        end
        -- Initialise profiles table if completely empty.
        BuffNudgeDB.profiles = BuffNudgeDB.profiles or {}
        if not next(BuffNudgeDB.profiles) then
            BuffNudgeDB.profiles["Default"] = {
                foodIDs={}, flaskIDs={}, raidBuffs={},
                checkFood=true, checkFlask=true, checkSoulstone=true, checkHealthstone=true,
                checkPet=true, checkEnchant=true, checkSocket=true, checkRaidBuff=true,
            }
        end
        BuffNudgeDB.activeProfile = BuffNudgeDB.activeProfile or "Default"
        if not BuffNudgeDB.profiles[BuffNudgeDB.activeProfile] then
            BuffNudgeDB.activeProfile = next(BuffNudgeDB.profiles)
        end
        if BuffNudgeDB.showAlways   == nil then BuffNudgeDB.showAlways   = false end
        if BuffNudgeDB.hideInCombat == nil then BuffNudgeDB.hideInCombat = false end
        -- Backfill settings fields for profiles created before this version.
        for _, prof in pairs(BuffNudgeDB.profiles) do
            if prof.checkFood     == nil then prof.checkFood     = true end
            if prof.checkFlask    == nil then prof.checkFlask    = true end
            if prof.checkSoulstone    == nil then prof.checkSoulstone    = true end
            if prof.checkPet      == nil then prof.checkPet      = true end
            if prof.checkEnchant     == nil then prof.checkEnchant     = true end
            if prof.checkSocket      == nil then prof.checkSocket      = true end
            if prof.checkHealthstone == nil then prof.checkHealthstone = true end
            if prof.checkRaidBuff    == nil then prof.checkRaidBuff    = true end
        end
        if BuffNudgeDB.fpsHidden then
            StopFpsTicker()
            fpsFrame:Hide()
        else
            StartFpsTicker()
        end
        if BuffNudgeDB.panelScale      == nil then BuffNudgeDB.panelScale      = 1.0 end
        if BuffNudgeDB.raidPanelScale  == nil then BuffNudgeDB.raidPanelScale  = 1.0 end
        if BuffNudgeDB.classPanelScale == nil then BuffNudgeDB.classPanelScale = 1.0 end
        panel:SetScale(BuffNudgeDB.panelScale)
        raidBuffPanel:SetScale(BuffNudgeDB.raidPanelScale)
        classPanel:SetScale(BuffNudgeDB.classPanelScale)
        if BuffNudgeDB.panelX then
            panel:ClearAllPoints()
            panel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.panelX, BuffNudgeDB.panelY)
        end
        if BuffNudgeDB.fpsX then
            fpsFrame:ClearAllPoints()
            fpsFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.fpsX, BuffNudgeDB.fpsY)
        end
        if BuffNudgeDB.raidPanelX then
            raidBuffPanel:ClearAllPoints()
            raidBuffPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.raidPanelX, BuffNudgeDB.raidPanelY)
        end
        if BuffNudgeDB.classPanelX then
            classPanel:ClearAllPoints()
            classPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.classPanelX, BuffNudgeDB.classPanelY)
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
        cachedMissingSockets  = nil
    elseif event == EVENTS.BAG_UPDATE_DELAYED then
        cachedHasHealthstone = nil
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
