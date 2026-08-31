-- panels/BuffNudgeRaidPanel.lua
-- Raid buff panel: shows missing raid buffs with clickable spell-cast buttons.
-- Uses SecureActionButtonTemplate rows so clicking casts the spell.
local _, ns = ...

local ICON_RAIDBUFF = ns.ICON_RAIDBUFF
local ROW_H         = ns.ROW_H
local PANEL_EXTRA_H = ns.PANEL_EXTRA_H
local YELLOW        = ns.YELLOW
local RESET         = ns.RESET
local TEXT_NO_BRONZE = ns.TEXT_NO_BRONZE

local raidBuffPanel = ns.CreateNudgePanel("BuffNudgeRaidPanel", 200, 30, 120, 220, "raidPanelX", "raidPanelY")
ns.RaidPanel = raidBuffPanel

local pool = ns.CreateRowPool(raidBuffPanel, true)

function ns.RefreshRaidPanel(auraSet, groupClasses, p, inCombat)
    if inCombat then return end  -- secure frame attributes/visibility cannot change during combat
    if not p.checkRaidBuff then raidBuffPanel:Hide(); return end
    local texts, icons, spellIDs, n = ns.MissingRaidBuffs(auraSet, groupClasses)
    if n == 0 then raidBuffPanel:Hide(); return end
    raidBuffPanel:SetHeight(PANEL_EXTRA_H + n * ROW_H)
    for i = 1, n do
        local row = pool.GetRow(i)
        row.icon:SetTexture(icons[i])
        local spellID = spellIDs[i]
        local known   = spellID and C_SpellBook.IsSpellKnown(spellID)
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
    pool.HideRowsFrom(n + 1)
    raidBuffPanel:Show()
end

function ns.DebugRaidPanel()
    local rn = 0
    for _, entry in ipairs(ns.GetRaidBuffs()) do
        rn = rn + 1
        local row = pool.GetRow(rn)
        row.icon:SetTexture(entry.icon)
        local known = entry.spellID and C_SpellBook.IsSpellKnown(entry.spellID)
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
    local bronzeRow = pool.GetRow(rn)
    bronzeRow.icon:SetTexture(C_Spell.GetSpellTexture(381732) or ICON_RAIDBUFF)
    bronzeRow.text:SetText(TEXT_NO_BRONZE)
    bronzeRow:SetAttribute("spell", nil)
    bronzeRow:EnableMouse(false)
    bronzeRow:Show()
    pool.HideRowsFrom(rn + 1)
    raidBuffPanel:SetHeight(PANEL_EXTRA_H + rn * ROW_H)
    raidBuffPanel:Show()
end
