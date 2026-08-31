-- BuffNudge.lua
-- Initialisation, event handler registration, slash commands, and main refresh orchestration.
local _, ns = ...

local ORANGE = ns.ORANGE
local GREEN  = ns.GREEN
local RED    = ns.RED
local RESET  = ns.RESET

local E   = ns.EVENTS
local CMD = ns.CMD

local inCombat = UnitAffectingCombat("player")

-- ============================================================
-- REFRESH
-- ============================================================

function BuffNudge_Refresh()
    local _, instanceType = IsInInstance()
    local inInstance = instanceType == "raid" or instanceType == "party"
    local debugMode  = ns.debugMode

    if not debugMode and ((not inInstance and not BuffNudgeDB.showAlways)
                       or (BuffNudgeDB.hideInCombat and inCombat)) then
        ns.ReminderPanel:Hide()
        ns.RaidPanel:Hide()
        ns.ClassPanel:Hide()
        -- Nothing reads these results while the panels are down.
        ns.SuspendClassEventSubscriptions()
        return
    end

    if debugMode then
        ns.DebugReminderPanel()
        ns.DebugRaidPanel()
        ns.DebugClassPanel()
        return
    end

    local auraSet      = ns.GetPlayerAuraSet()
    local groupClasses = ns.GetGroupClasses()
    local p            = ns.GetProfile()

    ns.RefreshReminderPanel(auraSet, groupClasses, p, inCombat)
    ns.RefreshRaidPanel(auraSet, groupClasses, p, inCombat)
    ns.RefreshClassPanel(auraSet, groupClasses, p)
end
ns.Refresh = BuffNudge_Refresh

-- ============================================================
-- EVENTS
-- Handlers are declared with the router in BuffNudgeEvents.lua. A truthy
-- return schedules a debounced refresh; handlers that only mutate state
-- (or refresh themselves) return nothing.
-- ============================================================

local function OnAddonLoaded(name)
    if name ~= "BuffNudge" then return end
    BuffNudgeDB = BuffNudgeDB or {}
    inCombat = UnitAffectingCombat("player")  -- sync in case addon loaded mid-combat
    if EditModeManagerFrame and EditModeManagerFrame.IsEditModeActive and EditModeManagerFrame:IsEditModeActive() then
        ns.OnEditModeEnter()
    end
    -- Migrate old flat format to profiles structure.
    if BuffNudgeDB.foodIDs or BuffNudgeDB.flaskIDs or BuffNudgeDB.raidBuffs then
        BuffNudgeDB.profiles = BuffNudgeDB.profiles or {}
        local p = ns.MakeDefaultProfile()
        p.foodIDs   = BuffNudgeDB.foodIDs   or {}
        p.flaskIDs  = BuffNudgeDB.flaskIDs  or {}
        p.raidBuffs = BuffNudgeDB.raidBuffs or {}
        BuffNudgeDB.profiles["Default"] = p
        BuffNudgeDB.foodIDs   = nil
        BuffNudgeDB.flaskIDs  = nil
        BuffNudgeDB.raidBuffs = nil
    end
    -- Initialise profiles table if completely empty.
    BuffNudgeDB.profiles = BuffNudgeDB.profiles or {}
    if not next(BuffNudgeDB.profiles) then
        BuffNudgeDB.profiles["Default"] = ns.MakeDefaultProfile()
    end
    BuffNudgeDB.activeProfile = BuffNudgeDB.activeProfile or "Default"
    if not BuffNudgeDB.profiles[BuffNudgeDB.activeProfile] then
        BuffNudgeDB.activeProfile = next(BuffNudgeDB.profiles)
    end
    if BuffNudgeDB.showAlways   == nil then BuffNudgeDB.showAlways   = false end
    if BuffNudgeDB.hideInCombat == nil then BuffNudgeDB.hideInCombat = false end
    -- Backfill check fields for profiles created before this version.
    local defaults = ns.MakeDefaultProfile()
    for _, prof in pairs(BuffNudgeDB.profiles) do
        for field, val in pairs(defaults) do
            if type(val) == "boolean" and prof[field] == nil then prof[field] = val end
        end
    end
    if BuffNudgeDB.fpsHidden then
        ns.StopFpsTicker()
        ns.FpsFrame:Hide()
    else
        ns.StartFpsTicker()
    end
    if BuffNudgeDB.panelScale      == nil then BuffNudgeDB.panelScale      = 1.0 end
    if BuffNudgeDB.raidPanelScale  == nil then BuffNudgeDB.raidPanelScale  = 1.0 end
    if BuffNudgeDB.classPanelScale == nil then BuffNudgeDB.classPanelScale = 1.0 end
    ns.ReminderPanel:SetScale(BuffNudgeDB.panelScale)
    ns.RaidPanel:SetScale(BuffNudgeDB.raidPanelScale)
    ns.ClassPanel:SetScale(BuffNudgeDB.classPanelScale)
    if BuffNudgeDB.panelX then
        ns.ReminderPanel:ClearAllPoints()
        ns.ReminderPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.panelX, BuffNudgeDB.panelY)
    end
    if BuffNudgeDB.fpsX then
        ns.FpsFrame:ClearAllPoints()
        ns.FpsFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.fpsX, BuffNudgeDB.fpsY)
    end
    if BuffNudgeDB.raidPanelX then
        ns.RaidPanel:ClearAllPoints()
        ns.RaidPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.raidPanelX, BuffNudgeDB.raidPanelY)
    end
    if BuffNudgeDB.classPanelX then
        ns.ClassPanel:ClearAllPoints()
        ns.ClassPanel:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", BuffNudgeDB.classPanelX, BuffNudgeDB.classPanelY)
    end
end

ns.OnEvent(E.ADDON_LOADED, OnAddonLoaded)

ns.OnEvent(E.PLAYER_ENTERING_WORLD, function()
    -- Loading screen: roster, gear and bags may all have moved underneath us.
    ns.InvalidateCache()
    return true
end)

ns.OnEvent(E.ZONE_CHANGED_NEW_AREA, function() return true end)

ns.OnEvent(E.GROUP_ROSTER_UPDATE, function()
    ns.InvalidateGroupCache()
    return true
end)

ns.OnEvent(E.PLAYER_EQUIPMENT_CHANGED, function()
    ns.InvalidateEquipmentCache()
    return true
end)

ns.OnEvent(E.PLAYER_REGEN_DISABLED, function()
    inCombat = true
    ns.RequestRefresh(true)  -- bypass debounce: hide out-of-combat rows immediately
end)

ns.OnEvent(E.PLAYER_REGEN_ENABLED, function()
    inCombat = false
    return true
end)

ns.OnEvent(E.BAG_UPDATE_DELAYED, function()
    ns.InvalidateBagCache()
    return true
end)

-- Unit-filtered: the client drops other units before Lua is entered, which
-- matters in a raid where every member's aura ticks would otherwise call in.
ns.OnEvent(E.UNIT_AURA, function() return true end, "player")
ns.OnEvent(E.UNIT_PET,  function() return true end, "player")

-- Always-on set. UNIT_PET and BAG_UPDATE_DELAYED are toggled at runtime by
-- ns.UpdateClassEventSubscriptions, since only the class panel reads them.
for _, event in ipairs({
    E.ADDON_LOADED,
    E.PLAYER_ENTERING_WORLD,
    E.ZONE_CHANGED_NEW_AREA,
    E.GROUP_ROSTER_UPDATE,
    E.PLAYER_EQUIPMENT_CHANGED,
    E.PLAYER_REGEN_ENABLED,
    E.PLAYER_REGEN_DISABLED,
    E.UNIT_AURA,
}) do
    ns.SetEventActive(event, true)
end

-- Edit mode is not an event; Blizzard broadcasts it through EventRegistry.
if EventRegistry then
    EventRegistry:RegisterCallback(ns.EDIT_MODE_CALLBACKS.ENTER, function() ns.OnEditModeEnter() end, ns.EventFrame)
    EventRegistry:RegisterCallback(ns.EDIT_MODE_CALLBACKS.EXIT,  function() ns.OnEditModeExit()  end, ns.EventFrame)
end

-- ============================================================
-- SLASH COMMANDS
-- ============================================================

SLASH_BUFFNUDGE1 = "/buffnudge"
SLASH_BUFFNUDGE2 = "/bn"

SlashCmdList["BUFFNUDGE"] = function(msg)
    msg = strtrim(msg:lower())
    if msg == CMD.CHECK then
        BuffNudge_Refresh()
        if not ns.ReminderPanel:IsShown() then print(ORANGE.."BuffNudge:"..RESET.." All good!") end
    elseif msg == CMD.SETUP then
        BuffNudgeSetup_Open()
    elseif msg == CMD.HIDE then
        ns.ReminderPanel:Hide()
    elseif msg == CMD.SHOW then
        ns.ReminderPanel:Show()
    elseif msg == CMD.MOVE then
        local moving = not ns.ReminderPanel:IsMovable()
        for _, f in ipairs(ns.movableFrames) do ns.SetFrameMovable(f, moving) end
        print(ORANGE.."BuffNudge:"..RESET.." Move mode "..(moving and GREEN.."ON"..RESET.." — drag frames to reposition" or RED.."OFF"..RESET))
    elseif msg == CMD.DEBUG then
        ns.debugMode = not ns.debugMode
        print(ORANGE.."BuffNudge:"..RESET.." Debug mode "..(ns.debugMode and GREEN.."ON"..RESET or RED.."OFF"..RESET))
        BuffNudge_Refresh()
    elseif msg == CMD.FPS then
        if ns.FpsFrame:IsShown() then
            ns.FpsFrame:Hide()
            ns.StopFpsTicker()
            BuffNudgeDB.fpsHidden = true
        else
            ns.FpsFrame:Show()
            ns.StartFpsTicker()
            BuffNudgeDB.fpsHidden = false
        end
    else
        local cmds = {}
        for _, v in pairs(CMD) do cmds[#cmds+1] = "/bn "..v end
        table.sort(cmds)
        print(ORANGE.."BuffNudge"..RESET..": "..table.concat(cmds, " | "))
    end
end
