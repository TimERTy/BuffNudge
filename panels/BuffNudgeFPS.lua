-- panels/BuffNudgeFPS.lua
-- FPS display widget.
local _, ns = ...

local GREEN  = ns.GREEN
local YELLOW = ns.YELLOW
local RED    = ns.RED
local RESET  = ns.RESET

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
-- FPS frame uses a different backdrop style so it is not created via CreateNudgePanel,
-- but we still register it for /bn move drag support.
ns.movableFrames[#ns.movableFrames + 1] = fpsFrame
ns.FpsFrame = fpsFrame

local fpsText = fpsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
fpsText:SetAllPoints()

local fpsTicker
local lastFpsValue = -1

local function FpsColor(fps)
    if fps >= 60 then return GREEN end
    if fps >= 30 then return YELLOW end
    return RED
end

function ns.StartFpsTicker()
    if fpsTicker then return end
    fpsTicker = C_Timer.NewTicker(1, function()
        local fps = math.floor(GetFramerate())
        if fps ~= lastFpsValue then
            lastFpsValue = fps
            fpsText:SetText(string.format("%s%d"..RESET.." fps", FpsColor(fps), fps))
        end
    end)
end

function ns.StopFpsTicker()
    if fpsTicker then
        fpsTicker:Cancel()
        fpsTicker = nil
        lastFpsValue = -1
    end
end
