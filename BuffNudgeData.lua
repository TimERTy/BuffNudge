-- BuffNudgeData.lua
-- Cache layer and buff/gear detection functions.
local _, ns = ...

local DEFAULT_FOOD_IDS             = ns.DEFAULT_FOOD_IDS
local DEFAULT_FLASK_IDS            = ns.DEFAULT_FLASK_IDS
local DEFAULT_HEALTHSTONE_ITEM_IDS = ns.DEFAULT_HEALTHSTONE_ITEM_IDS
local DEFAULT_RAID_BUFFS           = ns.DEFAULT_RAID_BUFFS
local ENCHANT_SLOTS                = ns.ENCHANT_SLOTS
local SOCKET_SLOTS                 = ns.SOCKET_SLOTS
local ITEM_CLASS_WEAPON            = ns.ITEM_CLASS_WEAPON
local SOULSTONE_SPELL_ID           = ns.SOULSTONE_SPELL_ID
local WELL_FED_BASE_SPELL_ID       = ns.WELL_FED_BASE_SPELL_ID

local ICON_FOOD     = ns.ICON_FOOD
local ICON_RAIDBUFF = ns.ICON_RAIDBUFF
local YELLOW        = ns.YELLOW
local RESET         = ns.RESET
local TEXT_NO_BRONZE = ns.TEXT_NO_BRONZE

local _, PLAYER_CLASS = UnitClass("player")

-- ============================================================
-- CACHES
-- Rebuilt on load and when the Setup panel saves changes.
-- foodSet/flaskSet are spellID → true hash sets for O(1) lookups.
-- ============================================================

local cachedFoodSet, cachedFoodIcon, cachedFlaskSet, cachedRaidBuffs
local cachedGroupClasses    -- invalidated by GROUP_ROSTER_UPDATE
local cachedMissingEnchants -- invalidated by PLAYER_EQUIPMENT_CHANGED
local cachedMissingSockets  -- invalidated by PLAYER_EQUIPMENT_CHANGED
local cachedSoulstone       -- invalidated by GROUP_ROSTER_UPDATE / group aura watcher
local cachedSoulstoneUnit   -- unit token holding it, so the watcher can track one unit
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
    cachedSoulstoneUnit   = nil
    cachedHasHealthstone  = nil
    cachedProfile         = nil
end
ns.InvalidateCache = BuffNudge_InvalidateCache

-- Returns a new profile table with all defaults set.
function ns.MakeDefaultProfile()
    return {
        foodIDs={}, flaskIDs={}, raidBuffs={},
        checkFood=true, checkFlask=true, checkSoulstone=true, checkHealthstone=true,
        checkPet=true, checkEnchant=true, checkSocket=true, checkRaidBuff=true,
    }
end

-- Fine-grained cache invalidation for specific event types.
function ns.InvalidateGroupCache()     cachedGroupClasses = nil; cachedSoulstone = nil; cachedSoulstoneUnit = nil end
function ns.InvalidateEquipmentCache() cachedMissingEnchants = nil; cachedMissingSockets = nil end
function ns.InvalidateBagCache()       cachedHasHealthstone = nil end
function ns.InvalidateSoulstoneCache() cachedSoulstone = nil; cachedSoulstoneUnit = nil end

-- Returns the currently active profile table from BuffNudgeDB.
-- Result is cached; invalidated by BuffNudge_InvalidateCache() on profile switch or save.
local function GetProfile()
    if cachedProfile then return cachedProfile end
    local name = BuffNudgeDB.activeProfile or "Default"
    local p = BuffNudgeDB.profiles and BuffNudgeDB.profiles[name]
    if not p then
        p = ns.MakeDefaultProfile()
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
    for _, v in ipairs(DEFAULT_FLASK_IDS)           do cachedFlaskSet[v] = true end
    for _, v in ipairs(GetProfile().flaskIDs or {}) do cachedFlaskSet[v] = true end
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
ns.GetRaidBuffs = GetRaidBuffs

-- Group classes: rebuilt only when GROUP_ROSTER_UPDATE fires.
local function GetGroupClasses()
    if cachedGroupClasses then return cachedGroupClasses end
    local classes = {}
    classes[PLAYER_CLASS] = true
    local inRaid = IsInRaid()
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
ns.GetGroupClasses = GetGroupClasses

-- Socket results: rebuilt only when PLAYER_EQUIPMENT_CHANGED fires.
local function GetMissingSockets()
    if cachedMissingSockets then return cachedMissingSockets end
    local missing = {}
    for _, slot in ipairs(SOCKET_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link then
            local stats = C_Item.GetItemStats(link)
            if stats then
                -- EMPTY_SOCKET_* in the stat table is the item's TOTAL socket count,
                -- not the unfilled ones -- it stays put after gemming. Subtract the
                -- gems actually present in the link to get the real empty count.
                local socketCount = 0
                for stat, count in pairs(stats) do
                    if stat:find("EMPTY_SOCKET") then socketCount = socketCount + count end
                end
                local gemCount = 0
                for i = 1, socketCount do
                    local _, gemLink = C_Item.GetItemGem(link, i)
                    if gemLink then gemCount = gemCount + 1 end
                end
                local emptyCount = socketCount - gemCount
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
ns.GetMissingSockets = GetMissingSockets

-- Shields and holdable off-hands sit in the off-hand slot but take no enchant.
local function IsWeaponLink(link)
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(link)
    return classID == ITEM_CLASS_WEAPON
end

-- Enchant results: rebuilt only when PLAYER_EQUIPMENT_CHANGED fires.
local function GetMissingEnchants()
    if cachedMissingEnchants then return cachedMissingEnchants end
    local missing = {}
    for _, slot in ipairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink("player", slot.id)
        if link and (not slot.weaponOnly or IsWeaponLink(link)) then
            local enchantID = link:match("|Hitem:%d+:(%d+):")
            if not enchantID or enchantID == "0" then
                table.insert(missing, slot.textMissing)
            end
        end
    end
    cachedMissingEnchants = missing
    return missing
end
ns.GetMissingEnchants = GetMissingEnchants

-- ============================================================
-- DETECTION HELPERS
-- ============================================================

-- Reused across Refresh calls to avoid per-call allocation.
local playerAuraSet = {}

-- Set during the aura sweep when a buff name matches the localised patterns below.
local playerHasFoodAura  = false
local playerHasFlaskAura = false

-- Both resolvers are lazy and retry on failure: spell data may not be cached at
-- file load, or on the first Refresh after login.

-- Food variants are all named "<something> Well Fed", so the base name works as
-- a substring match.
local wellFedName
local function GetWellFedName()
    if not wellFedName then
        wellFedName = C_Spell.GetSpellName(WELL_FED_BASE_SPELL_ID)
    end
    return wellFedName
end

-- Flasks share no single word, but they do share a prefix ("Flask of " in enUS).
-- Deriving it from the default flask names keeps the match correct in every
-- locale instead of hardcoding English.
-- Returns nil unless every id resolves: spell data loads asynchronously, and a
-- prefix computed from a partial set would be too long and reject real flasks.
local function CommonSpellNamePrefix(ids)
    local prefix
    for _, id in ipairs(ids) do
        local name = C_Spell.GetSpellName(id)
        if not name then return nil end
        if not prefix then
            prefix = name
        else
            local n, max = 0, math.min(#prefix, #name)
            while n < max and prefix:byte(n + 1) == name:byte(n + 1) do n = n + 1 end
            prefix = prefix:sub(1, n)
        end
    end
    return prefix
end

local flaskNamePrefix
local function GetFlaskNamePrefix()
    if not flaskNamePrefix then
        local prefix = CommonSpellNamePrefix(DEFAULT_FLASK_IDS)
        -- Trim back to a word boundary. Keeps the match meaningful and, since a
        -- space is single-byte, avoids slicing a multi-byte character in half.
        local lastSpace = prefix and prefix:match(".*() ")
        prefix = lastSpace and prefix:sub(1, lastSpace) or nil
        -- Too short to be distinctive: fall back to ID matching alone.
        if prefix and #prefix < 4 then prefix = nil end
        flaskNamePrefix = prefix
    end
    return flaskNamePrefix
end

-- Clears and repopulates playerAuraSet with current player buffs, and flags food
-- and flask buffs by name in the same pass.
local function GetPlayerAuraSet()
    for k in next, playerAuraSet do playerAuraSet[k] = nil end
    playerHasFoodAura  = false
    playerHasFlaskAura = false
    local wellFed     = GetWellFedName()
    local flaskPrefix = GetFlaskNamePrefix()
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 100)
    if auras then
        for _, aura in ipairs(auras) do
            local id = aura.spellId
            if id and not issecretvalue(id) then
                playerAuraSet[id] = true
            end
            if not (playerHasFoodAura and playerHasFlaskAura) then
                local name = aura.name
                if name and not issecretvalue(name) then
                    if wellFed and not playerHasFoodAura and name:find(wellFed, 1, true) then
                        playerHasFoodAura = true
                    end
                    -- Anchored at 1: a flask buff leads with the prefix.
                    if flaskPrefix and not playerHasFlaskAura and name:find(flaskPrefix, 1, true) == 1 then
                        playerHasFlaskAura = true
                    end
                end
            end
        end
    end
    return playerAuraSet
end
ns.GetPlayerAuraSet = GetPlayerAuraSet

-- Name match first: it covers every Well Fed variant, including the ones with no
-- entry in DEFAULT_FOOD_IDS. The ID set still applies for anything tagged through
-- /bn setup whose name does not follow that convention.
local function HasFood(auraSet)
    if playerHasFoodAura then return true end
    for id in pairs(GetFoodSet()) do
        if auraSet[id] then return true end
    end
    return false
end
ns.HasFood = HasFood

-- Diagnostic for /bn auras: lists the player's buffs so an untagged consumable
-- can be identified and added through /bn setup.
function ns.DumpPlayerAuras()
    local auras = C_UnitAuras.GetUnitAuras("player", "HELPFUL", 100)
    if not auras or #auras == 0 then
        print("BuffNudge: no buffs found.")
        return
    end
    for _, aura in ipairs(auras) do
        local id, name = aura.spellId, aura.name
        print("BuffNudge: "
            .. ((name and not issecretvalue(name)) and name or "<secret>")
            .. " = "
            .. ((id and not issecretvalue(id)) and tostring(id) or "<secret>"))
    end
end

-- Name match first, same rationale as HasFood: it covers cauldron and future
-- variants that have no entry in DEFAULT_FLASK_IDS.
local function HasFlask(auraSet)
    if playerHasFlaskAura then return true end
    for id in pairs(GetFlaskSet()) do
        if auraSet[id] then return true end
    end
    return false
end
ns.HasFlask = HasFlask

-- Returns the cached icon for the player's food buff (populated as a side effect of GetFoodSet).
function ns.GetFoodIcon()
    GetFoodSet()  -- ensures cachedFoodIcon is populated
    return cachedFoodIcon or ICON_FOOD
end

local function UnitHasSoulstone(unit)
    local auras = C_UnitAuras.GetUnitAuras(unit, "HELPFUL", 100)
    if not auras then return false end
    for _, aura in ipairs(auras) do
        local id = aura.spellId
        if id and not issecretvalue(id) and id == SOULSTONE_SPELL_ID then return true end
    end
    return false
end

local function HasSoulstone(auraSet, groupClasses)
    if not groupClasses["WARLOCK"] then return true end
    if auraSet[SOULSTONE_SPELL_ID] then return true end  -- player has it (fresh from auraSet each Refresh)
    if cachedSoulstone ~= nil then return cachedSoulstone end
    -- Full group scan. Only runs when the cache is cold; from then on the group
    -- aura watcher keeps it current one unit at a time (ns.UpdateSoulstoneForUnit).
    local inRaid = IsInRaid()
    for i = 1, GetNumGroupMembers() do
        local unit = inRaid and ("raid"..i) or ("party"..i)
        if UnitExists(unit) and UnitHasSoulstone(unit) then
            cachedSoulstone     = true
            cachedSoulstoneUnit = unit
            return true
        end
    end
    cachedSoulstone     = false
    cachedSoulstoneUnit = nil
    return false
end
ns.HasSoulstone = HasSoulstone

-- Incremental update driven by UNIT_AURA on group members. Costs one aura fetch
-- per event instead of rescanning the raid, by remembering which unit carries
-- the stone and ignoring aura churn on everyone else.
-- Returns true when the cached state changed and the panels need a refresh.
function ns.UpdateSoulstoneForUnit(unit)
    if cachedSoulstone and cachedSoulstoneUnit and not UnitIsUnit(unit, cachedSoulstoneUnit) then
        return false  -- someone else's aura churn; the tracked holder still has it
    end
    if UnitHasSoulstone(unit) then
        if cachedSoulstone and cachedSoulstoneUnit then return false end
        cachedSoulstone, cachedSoulstoneUnit = true, unit
        return true
    end
    if cachedSoulstone then
        -- Holder lost it. Drop to nil so the next Refresh does one full rescan
        -- (another member may still be stoned).
        cachedSoulstone, cachedSoulstoneUnit = nil, nil
        return true
    end
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
ns.HasHealthstone = HasHealthstone

-- Blessing of the Bronze: one ID per class (381732–381758), O(27) hash lookups.
local function HasBlessingOfBronze(auraSet)
    for id = 381732, 381758 do
        if auraSet[id] then return true end
    end
    return false
end

-- Pre-allocated buffers — entries reused each Refresh, no table allocation in hot path.
-- Max items: food(1) + flask(1) + stone(1) + pet(1) + enchants(8) + sockets(14) + raid buffs(8) = 33.
local missingBuf        = {}
local missingIconBuf    = {}
local missingSpellIDBuf = {}

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
ns.MissingRaidBuffs = MissingRaidBuffs
