-- panels/BuffNudgeClassPanel.lua
-- Class panel: warlock-specific checks (soulstone, healthstone) and pet check.
local _, ns = ...

local ICON_STONE       = ns.ICON_STONE
local ICON_PET         = ns.ICON_PET
local ICON_HEALTHSTONE = ns.ICON_HEALTHSTONE
local ROW_H            = ns.ROW_H
local PANEL_EXTRA_H    = ns.PANEL_EXTRA_H
local PET_CLASSES      = ns.PET_CLASSES

local TEXT_NO_STONE       = ns.TEXT_NO_STONE
local TEXT_NO_PET         = ns.TEXT_NO_PET
local TEXT_NO_HEALTHSTONE = ns.TEXT_NO_HEALTHSTONE

local _, PLAYER_CLASS = UnitClass("player")

local classPanel = ns.CreateNudgePanel("BuffNudgeClassPanel", 180, 30, -130, 220, "classPanelX", "classPanelY")
ns.ClassPanel = classPanel

local pool = ns.CreateRowPool(classPanel, false)

function ns.RefreshClassPanel(auraSet, groupClasses, p)
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
    if p.checkPet and PET_CLASSES[PLAYER_CLASS] and not UnitExists("pet") then
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
