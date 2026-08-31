-- panels/BuffNudgeClassPanel.lua
-- Class panel: warlock-specific checks (soulstone, healthstone) and pet check.
local _, ns = ...

local ICON_STONE       = ns.ICON_STONE
local ICON_PET         = ns.ICON_PET
local ICON_HEALTHSTONE = ns.ICON_HEALTHSTONE
local ROW_H            = ns.ROW_H
local PANEL_EXTRA_H    = ns.PANEL_EXTRA_H
local PET_CLASSES      = ns.PET_CLASSES
local EVENTS           = ns.EVENTS

local TEXT_NO_STONE       = ns.TEXT_NO_STONE
local TEXT_NO_PET         = ns.TEXT_NO_PET
local TEXT_NO_HEALTHSTONE = ns.TEXT_NO_HEALTHSTONE

local _, PLAYER_CLASS = UnitClass("player")

local classPanel = ns.CreateNudgePanel("BuffNudgeClassPanel", 180, 30, -130, 220, "classPanelX", "classPanelY")
ns.ClassPanel = classPanel

local pool = ns.CreateRowPool(classPanel, false)

-- ============================================================
-- GROUP SOULSTONE WATCHER
-- The main event frame filters UNIT_AURA to "player" in C, so tracking other
-- members' soulstones needs its own unfiltered subscription. It is only live
-- while the player is a warlock in a group with the check enabled, and each
-- event costs one UnitIsUnit call unless it concerns the tracked holder.
-- ============================================================

local GROUP_UNITS = {}
for i = 1, 40 do GROUP_UNITS["raid"..i]  = true end
for i = 1, 4  do GROUP_UNITS["party"..i] = true end

local soulstoneWatcher = CreateFrame("Frame")
soulstoneWatcher:SetScript("OnEvent", function(_, _, unit)
    if not GROUP_UNITS[unit] then return end
    if ns.UpdateSoulstoneForUnit(unit) then ns.RequestRefresh() end
end)

local watching = false
local function SetSoulstoneWatch(active)
    if active == watching then return end
    watching = active
    if active then
        -- Any stone applied or consumed while unsubscribed was missed.
        ns.InvalidateSoulstoneCache()
        soulstoneWatcher:RegisterEvent(EVENTS.UNIT_AURA)
    else
        soulstoneWatcher:UnregisterEvent(EVENTS.UNIT_AURA)
    end
end

-- Subscribe only to the events whose results a currently-enabled check reads.
function ns.UpdateClassEventSubscriptions(p, groupClasses)
    ns.SetEventActive(EVENTS.UNIT_PET, p.checkPet and PET_CLASSES[PLAYER_CLASS] or false)
    local bagWatch = p.checkHealthstone and groupClasses["WARLOCK"] or false
    -- Bag contents may have moved while BAG_UPDATE_DELAYED was unsubscribed.
    if ns.SetEventActive(EVENTS.BAG_UPDATE_DELAYED, bagWatch) and bagWatch then
        ns.InvalidateBagCache()
    end
    SetSoulstoneWatch(PLAYER_CLASS == "WARLOCK" and p.checkSoulstone and IsInGroup() or false)
end

-- Used when the panels are hidden entirely (out of instance, or hidden in combat).
function ns.SuspendClassEventSubscriptions()
    ns.SetEventActive(EVENTS.UNIT_PET, false)
    ns.SetEventActive(EVENTS.BAG_UPDATE_DELAYED, false)
    SetSoulstoneWatch(false)
end

function ns.RefreshClassPanel(auraSet, groupClasses, p)
    ns.UpdateClassEventSubscriptions(p, groupClasses)

    local n = 0
    -- Soulstone: only the warlock needs to act on this
    if PLAYER_CLASS == "WARLOCK" and p.checkSoulstone and not ns.HasSoulstone(auraSet, groupClasses) then
        n = n + 1
        local row = pool.GetRow(n)
        row.icon:SetTexture(ICON_STONE)
        row.text:SetText(TEXT_NO_STONE)
        row:Show()
    end
    -- Pet: hunter/warlock needs a pet active
    -- UnitExists stays true for a dead pet, so check liveness too.
    if p.checkPet and PET_CLASSES[PLAYER_CLASS] and (not UnitExists("pet") or UnitIsDead("pet")) then
        n = n + 1
        local row = pool.GetRow(n)
        row.icon:SetTexture(ICON_PET)
        row.text:SetText(TEXT_NO_PET)
        row:Show()
    end
    -- Healthstone: relevant to everyone when a warlock is in the group
    if groupClasses["WARLOCK"] and p.checkHealthstone and not ns.HasHealthstone() then
        n = n + 1
        local row = pool.GetRow(n)
        row.icon:SetTexture(ICON_HEALTHSTONE)
        row.text:SetText(TEXT_NO_HEALTHSTONE)
        row:Show()
    end
    if n == 0 then classPanel:Hide(); return end
    pool.HideRowsFrom(n + 1)
    classPanel:SetHeight(PANEL_EXTRA_H + n * ROW_H)
    classPanel:Show()
end

function ns.DebugClassPanel()
    local rows = {
        { text = TEXT_NO_STONE,       icon = ICON_STONE       },
        { text = TEXT_NO_HEALTHSTONE, icon = ICON_HEALTHSTONE },
        { text = TEXT_NO_PET,         icon = ICON_PET         },
    }
    for i, r in ipairs(rows) do
        local row = pool.GetRow(i)
        row.text:SetText(r.text)
        row.icon:SetTexture(r.icon)
        row:Show()
    end
    pool.HideRowsFrom(#rows + 1)
    classPanel:SetHeight(PANEL_EXTRA_H + #rows * ROW_H)
    classPanel:Show()
end
