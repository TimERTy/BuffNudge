-- BuffNudge.lua
-- Event handling, initialisation, slash commands, and main refresh orchestration.
local _, ns = ...

local ORANGE = ns.ORANGE
local GREEN  = ns.GREEN
local RED    = ns.RED
local RESET  = ns.RESET

local EVENTS = ns.EVENTS
local CMD    = ns.CMD

local debugMode = false
local inCombat  = UnitAffectingCombat("player")

-- ============================================================
-- REFRESH
-- ============================================================

function BuffNudge_Refresh()
    local _, instanceType = IsInInstance()
    local inInstance = instanceType == "raid" or instanceType == "party"
    if not debugMode and not inInstance and not BuffNudgeDB.showAlways then
        ns.ReminderPanel:Hide()
        ns.RaidPanel:Hide()
        ns.ClassPanel:Hide()
        return
    end
    if not debugMode and BuffNudgeDB.hideInCombat and inCombat then
        ns.ReminderPanel:Hide()
        ns.RaidPanel:Hide()
        ns.ClassPanel:Hide()
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
-- ============================================================

local eventFrame     = CreateFrame("Frame")
local refreshPending = false

local function safeRegister(event)
    local ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
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
    if event == EVENTS.EDIT_MODE_ENTER then ns.OnEditModeEnter(); return end
    if event == EVENTS.EDIT_MODE_EXIT  then ns.OnEditModeExit();  return end

    if event == EVENTS.ADDON_LOADED then
        if arg1 ~= "BuffNudge" then return end
        BuffNudgeDB = BuffNudgeDB or {}
        inCombat = UnitAffectingCombat("player")  -- sync in case addon loaded mid-combat
        if C_EditMode and C_EditMode.IsEditModeActive and C_EditMode.IsEditModeActive() then ns.OnEditModeEnter() end
        -- Migrate old flat format to profiles structure.
        if BuffNudgeDB.foodIDs or BuffNudgeDB.flaskIDs or BuffNudgeDB.raidBuffs then
            BuffNudgeDB.profiles = BuffNudgeDB.profiles or {}
            local p = ns.MakeDefaultProfile()
            p.foodIDs  = BuffNudgeDB.foodIDs   or {}
            p.flaskIDs = BuffNudgeDB.flaskIDs  or {}
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
        return
    end

    if event == EVENTS.PLAYER_REGEN_DISABLED then
        inCombat = true
        BuffNudge_Refresh()  -- bypass debounce: hide out-of-combat rows immediately
        return
    elseif event == EVENTS.PLAYER_REGEN_ENABLED then
        inCombat = false
    elseif event == EVENTS.GROUP_ROSTER_UPDATE then
        ns.InvalidateGroupCache()
    elseif event == EVENTS.PLAYER_EQUIPMENT_CHANGED then
        ns.InvalidateEquipmentCache()
    elseif event == EVENTS.BAG_UPDATE_DELAYED then
        ns.InvalidateBagCache()
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
        debugMode = not debugMode
        print(ORANGE.."BuffNudge:"..RESET.." Debug mode "..(debugMode and GREEN.."ON"..RESET or RED.."OFF"..RESET))
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
