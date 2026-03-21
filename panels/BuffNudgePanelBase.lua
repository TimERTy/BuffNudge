-- panels/BuffNudgePanelBase.lua
-- Shared helpers for creating and managing BuffNudge display panels.
local _, ns = ...

local ROW_H        = ns.ROW_H
local ROW_PAD_TOP  = ns.ROW_PAD_TOP
local ROW_PAD_SIDE = ns.ROW_PAD_SIDE

-- ============================================================
-- DRAG SUPPORT
-- ============================================================

-- Frames registered for /bn move drag support.
local movableFrames = {}
ns.movableFrames = movableFrames

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
ns.SetFrameMovable = SetFrameMovable

function ns.OnEditModeEnter()
    for _, f in ipairs(movableFrames) do SetFrameMovable(f, true) end
end

function ns.OnEditModeExit()
    for _, f in ipairs(movableFrames) do SetFrameMovable(f, false) end
end

-- ============================================================
-- PANEL FACTORY
-- ============================================================

-- Creates a standard nudge panel: transparent backdrop, drag support, hidden by default.
-- dbXKey/dbYKey: SavedVariable keys for persisted position.
-- The created frame is automatically added to movableFrames.
function ns.CreateNudgePanel(name, w, h, defaultX, defaultY, dbXKey, dbYKey)
    local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetPoint("CENTER", UIParent, "CENTER", defaultX, defaultY)
    f:SetMovable(false)
    f:EnableMouse(false)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        BuffNudgeDB[dbXKey] = self:GetLeft()
        BuffNudgeDB[dbYKey] = self:GetTop()
    end)
    f:SetBackdrop({
        bgFile   = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        edgeSize = 12,
        insets   = { left=3, right=3, top=3, bottom=3 },
    })
    f:SetBackdropColor(0, 0, 0, 0)
    f:SetBackdropBorderColor(0, 0, 0, 0)
    f._borderColor = { 0, 0, 0, 0 }
    f:Hide()
    movableFrames[#movableFrames + 1] = f
    return f
end

-- ============================================================
-- ROW POOL FACTORY
-- ============================================================

-- Creates a row pool for a panel. Returns { GetRow(i), HideRowsFrom(n) }.
-- useSecureButton: rows use SecureActionButtonTemplate (needed for spell-cast rows).
function ns.CreateRowPool(parent, useSecureButton)
    local rows = {}
    local pool = {}

    function pool.GetRow(i)
        if not rows[i] then
            local row
            if useSecureButton then
                row = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
                row:EnableMouse(false)
                row:RegisterForClicks("LeftButtonUp")
                row:SetAttribute("type", "spell")
                row:SetNormalTexture("")
                row:SetHighlightTexture("")
                row:SetPushedTexture("")
                local hl = row:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)
            else
                row = CreateFrame("Frame", nil, parent)
            end
            row:SetHeight(ROW_H)
            row:SetPoint("TOPLEFT",  parent, "TOPLEFT",   ROW_PAD_SIDE, -ROW_PAD_TOP - (i-1)*ROW_H)
            row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -ROW_PAD_SIDE, -ROW_PAD_TOP - (i-1)*ROW_H)

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

    function pool.HideRowsFrom(from)
        for i = from, #rows do rows[i]:Hide() end
    end

    return pool
end
