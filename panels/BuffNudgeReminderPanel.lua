-- panels/BuffNudgeReminderPanel.lua
-- General reminder panel: food, flask, enchants, sockets.
local _, ns = ...

local ICON_FOOD     = ns.ICON_FOOD
local ICON_FLASK    = ns.ICON_FLASK
local ICON_ENCHANT  = ns.ICON_ENCHANT
local ICON_SOCKET   = ns.ICON_SOCKET
local ROW_H         = ns.ROW_H
local PANEL_EXTRA_H = ns.PANEL_EXTRA_H
local ENCHANT_SLOTS = ns.ENCHANT_SLOTS
local SOCKET_SLOTS  = ns.SOCKET_SLOTS

local TEXT_NO_FOOD  = ns.TEXT_NO_FOOD
local TEXT_NO_FLASK = ns.TEXT_NO_FLASK

local panel = ns.CreateNudgePanel("BuffNudgePanel", 220, 30, 0, 220, "panelX", "panelY")
ns.ReminderPanel = panel

local closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
closeBtn:SetSize(16, 16)
closeBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -2, -2)
closeBtn:SetScript("OnClick", function() panel:Hide() end)
closeBtn:Hide()

local pool = ns.CreateRowPool(panel, false)

-- Pre-allocated render buffer. Max rows: food(1)+flask(1)+enchants(8)+sockets(14) = 24.
local itemsBuf = {}
for i = 1, 30 do itemsBuf[i] = { text = "", icon = 0 } end

function ns.RefreshReminderPanel(auraSet, groupClasses, p, inCombat)
    local n = 0
    local function push(text, icon) n=n+1; itemsBuf[n].text=text; itemsBuf[n].icon=icon end

    if p.checkFood and not inCombat and not ns.HasFood(auraSet) then
        push(TEXT_NO_FOOD, ns.GetFoodIcon())
    end
    if p.checkFlask and not ns.HasFlask(auraSet) then
        push(TEXT_NO_FLASK, ICON_FLASK)
    end
    if p.checkEnchant and not inCombat then
        for _, text in ipairs(ns.GetMissingEnchants()) do push(text, ICON_ENCHANT) end
    end
    if p.checkSocket and not inCombat then
        for _, text in ipairs(ns.GetMissingSockets()) do push(text, ICON_SOCKET) end
    end

    if n == 0 then panel:Hide(); return end

    panel:SetHeight(PANEL_EXTRA_H + n * ROW_H)
    for i = 1, n do
        local row = pool.GetRow(i)
        row.text:SetText(itemsBuf[i].text)
        row.icon:SetTexture(itemsBuf[i].icon)
        row:Show()
    end
    pool.HideRowsFrom(n + 1)
    panel:Show()
end

function ns.DebugReminderPanel()
    local n = 0
    local function push(text, icon) n=n+1; itemsBuf[n].text=text; itemsBuf[n].icon=icon end

    push(TEXT_NO_FOOD,  ICON_FOOD)
    push(TEXT_NO_FLASK, ICON_FLASK)
    for _, slot in ipairs(ENCHANT_SLOTS) do push(slot.textMissing,          ICON_ENCHANT) end
    for _, slot in ipairs(SOCKET_SLOTS)  do push(slot.textBase.."|r",       ICON_SOCKET)  end

    panel:SetHeight(PANEL_EXTRA_H + n * ROW_H)
    for i = 1, n do
        local row = pool.GetRow(i)
        row.text:SetText(itemsBuf[i].text)
        row.icon:SetTexture(itemsBuf[i].icon)
        row:Show()
    end
    pool.HideRowsFrom(n + 1)
    panel:Show()
end
