-- BuffNudgeEvents.lua
-- Event router and refresh scheduler.
--
-- Registration is table-driven and dynamic: ns.SetEventActive() lets panels
-- subscribe only while a check is actually relevant (e.g. BAG_UPDATE_DELAYED
-- only when a warlock is in the group), so we are not paying for events whose
-- results nothing reads.
local _, ns = ...

local eventFrame = CreateFrame("Frame")
ns.EventFrame = eventFrame

local handlers   = {}  -- event -> handler(arg1, ...); truthy return requests a refresh
local unitFilter = {}  -- event -> { unit1, unit2 } for C-side RegisterUnitEvent filtering
local registered = {}  -- event -> true while subscribed

ns.debugMode = false

local function Log(msg)
    if ns.debugMode then print("BuffNudge: " .. msg) end
end
ns.Log = Log

-- ============================================================
-- REFRESH SCHEDULER
-- Trailing-edge debounce with a minimum interval. Requests arriving during
-- the cooldown are coalesced into the pending run rather than dropped.
-- ============================================================

local DEBOUNCE     = 0.25  -- collect a burst of events before refreshing
local MIN_INTERVAL = 1.0   -- floor between two refreshes

local pending, lastRun, schedGen = false, 0, 0

local function Run()
    pending = false
    lastRun = GetTime()
    ns.Refresh()
end

-- immediate=true bypasses the debounce (used when combat starts and rows must
-- disappear on the same frame). It supersedes any in-flight timer.
function ns.RequestRefresh(immediate)
    if immediate then
        schedGen = schedGen + 1
        pending  = false
        Run()
        return
    end
    if pending then return end
    pending  = true
    schedGen = schedGen + 1
    local gen  = schedGen
    local wait = math.max(DEBOUNCE, MIN_INTERVAL - (GetTime() - lastRun))
    C_Timer.After(wait, function()
        if gen ~= schedGen then return end  -- superseded by an immediate refresh
        Run()
    end)
end

-- ============================================================
-- ROUTER
-- ============================================================

-- Declares a handler. unit1/unit2 opt into RegisterUnitEvent so the client
-- filters by unit in C instead of us discarding in Lua.
function ns.OnEvent(event, handler, unit1, unit2)
    handlers[event] = handler
    if unit1 then unitFilter[event] = { unit1, unit2 } end
end

-- Returns true when the subscription state actually changed, so callers can
-- refill any cache that went stale while the event was unsubscribed.
function ns.SetEventActive(event, active)
    active = active and true or false
    if active == (registered[event] or false) then return false end
    if active then
        local u, ok = unitFilter[event]
        if u then
            ok = pcall(eventFrame.RegisterUnitEvent, eventFrame, event, u[1], u[2])
        else
            ok = pcall(eventFrame.RegisterEvent, eventFrame, event)
        end
        if not ok then Log("skipping unknown event: " .. event) return false end
        registered[event] = true
    else
        eventFrame:UnregisterEvent(event)
        registered[event] = nil
    end
    return true
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local handler = handlers[event]
    if not handler then return end
    if handler(...) then ns.RequestRefresh() end
end)
