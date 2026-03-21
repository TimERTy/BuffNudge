-- BuffNudgeConstants.lua
-- All static constants shared across BuffNudge files via the addon namespace.
local _, ns = ...

-- ============================================================
-- COLOURS
-- ============================================================
ns.RED    = "|cffff4444"
ns.ORANGE = "|cffff9900"
ns.YELLOW = "|cffffff00"
ns.GREEN  = "|cff4dff4d"
ns.BLUE   = "|cff4dc8ff"
ns.GREY   = "|cffaaaaaa"
ns.RESET  = "|r"

-- ============================================================
-- SPELL / ITEM IDs
-- ============================================================

-- NOTE: Midnight has 80+ Hearty Well Fed variants (IDs 454188–1285644+).
-- Use /bn setup to tag your specific food buff — defaults here cover common bases only.
ns.DEFAULT_FOOD_IDS = {
    462186,  -- Hearty Well Fed (base)
    57399,   -- Well Fed (older fallback)
}

-- All four Midnight stat flasks. Use /bn setup if you use a cauldron variant.
ns.DEFAULT_FLASK_IDS = {
    1235108,  -- Flask of the Magisters      (Mastery)
    1235110,  -- Flask of the Blood Knights  (Haste)
    1235057,  -- Flask of Thalassian Resistance (Versatility)
    1230878,  -- Flask of the Shattered Sun  (Critical Strike)
}

-- Healthstone item IDs checked via GetItemCount.
ns.DEFAULT_HEALTHSTONE_ITEM_IDS = { 5512 }  -- Healthstone (variants caught by name scan in HasHealthstone)

-- Confirmed Midnight raid buff spell IDs (flagged non-secret by Blizzard).
-- class: WoW class token from UnitClass() — warning skipped if class absent from group.
ns.DEFAULT_RAID_BUFFS = {
    { name = "Arcane Intellect",       spellID = 1459,   class = "MAGE"    },
    { name = "Battle Shout",           spellID = 6673,   class = "WARRIOR" },
    { name = "Power Word: Fortitude",  spellID = 21562,  class = "PRIEST"  },
    { name = "Mark of the Wild",       spellID = 1126,   class = "DRUID"   },
    { name = "Source of Magic",        spellID = 369459, class = "EVOKER"  },
    { name = "Skyfury",                spellID = 462854, class = "SHAMAN"  },
    { name = "Symbiotic Relationship", spellID = 474754, class = "DRUID"   },
}

-- All slots that can carry gem sockets. C_Item.GetItemStats returns EMPTY_SOCKET_* keys
-- only for slots that actually have sockets, so checking extras costs nothing.
-- textBase: built below from slot.name — GetMissingSockets() appends count suffix at runtime.
ns.SOCKET_SLOTS = {
    { id =  1, name = "Helmet"    },
    { id =  2, name = "Neck"      },
    { id =  3, name = "Shoulder"  },
    { id =  5, name = "Chest"     },
    { id =  6, name = "Waist"     },
    { id =  7, name = "Legs"      },
    { id =  8, name = "Feet"      },
    { id =  9, name = "Wrist"     },
    { id = 10, name = "Hands"     },
    { id = 11, name = "Ring 1"    },
    { id = 12, name = "Ring 2"    },
    { id = 15, name = "Back"      },
    { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand"  },
}

-- Enchantable slots in Midnight: Helmet, Shoulder, Chest, Boots, Rings, Weapons.
-- Cloak and Bracers are NOT enchantable in Midnight.
-- textMissing: built below from slot.name — used directly by GetMissingEnchants().
ns.ENCHANT_SLOTS = {
    { id =  1, name = "Helmet"    },
    { id =  3, name = "Shoulder"  },
    { id =  5, name = "Chest"     },
    { id =  8, name = "Boots"     },
    { id = 11, name = "Ring 1"    },
    { id = 12, name = "Ring 2"    },
    { id = 16, name = "Main Hand" },
    { id = 17, name = "Off Hand"  },
}

-- Build text fields from name + colour constants (avoids hardcoded escape sequences).
local R, Z = ns.RED, ns.RESET
for _, slot in ipairs(ns.SOCKET_SLOTS)  do slot.textBase    = R .. "Socket: "  .. slot.name        end
for _, slot in ipairs(ns.ENCHANT_SLOTS) do slot.textMissing = R .. "Enchant: " .. slot.name .. Z   end

-- ============================================================
-- ICONS
-- ============================================================
ns.ICON_FOOD     = 132950
ns.ICON_FLASK    = 134840
ns.ICON_STONE    = 136210
ns.ICON_ENCHANT  = 136243
ns.ICON_RAIDBUFF = 136116
ns.ICON_PET      = 132584
ns.ICON_SOCKET      = "Interface/ItemSocketingFrame/UI-EmptySocket-Prismatic"
ns.ICON_HEALTHSTONE = C_Item.GetItemIconByID(5512) or 460786  -- Healthstone item icon

-- ============================================================
-- PRE-BUILT STRINGS
-- ============================================================
local O, Y = ns.ORANGE, ns.YELLOW
ns.TEXT_NO_FOOD         = R .. "No Food Buff"              .. Z
ns.TEXT_NO_FLASK        = R .. "No Flask/Phial"            .. Z
ns.TEXT_NO_STONE        = O .. "No Soulstone"              .. Z
ns.TEXT_NO_BRONZE       = Y .. "Blessing of the Bronze"    .. Z
ns.TEXT_NO_PET          = R .. "No Pet"                    .. Z
ns.TEXT_NO_HEALTHSTONE  = R .. "No Healthstone"            .. Z

-- ============================================================
-- PLAYER
-- ============================================================
ns.PET_CLASSES = { HUNTER = true, WARLOCK = true }

-- ============================================================
-- SLASH COMMANDS
-- ============================================================
ns.CMD = {
    CHECK = "check",
    SETUP = "setup",
    HIDE  = "hide",
    SHOW  = "show",
    MOVE  = "move",
    DEBUG = "debug",
    FPS   = "fps",
}

-- ============================================================
-- LAYOUT
-- ============================================================
ns.ROW_H        = 18   -- height of each row in display panels
ns.ROW_PAD_TOP  = 4    -- top padding inside panels before first row
ns.ROW_PAD_SIDE = 8    -- left/right inset for rows
ns.PANEL_EXTRA_H = 8   -- panel height added on top of n * ROW_H

-- ============================================================
-- WOW EVENTS
-- ============================================================
ns.EVENTS = {
    ADDON_LOADED             = "ADDON_LOADED",
    PLAYER_ENTERING_WORLD    = "PLAYER_ENTERING_WORLD",
    ZONE_CHANGED_NEW_AREA    = "ZONE_CHANGED_NEW_AREA",
    GROUP_ROSTER_UPDATE      = "GROUP_ROSTER_UPDATE",
    PLAYER_EQUIPMENT_CHANGED = "PLAYER_EQUIPMENT_CHANGED",
    PLAYER_REGEN_ENABLED     = "PLAYER_REGEN_ENABLED",
    PLAYER_REGEN_DISABLED    = "PLAYER_REGEN_DISABLED",
    UNIT_AURA                = "UNIT_AURA",
    EDIT_MODE_ENTER          = "EDIT_MODE_ENTER",
    EDIT_MODE_EXIT           = "EDIT_MODE_EXIT",
    BAG_UPDATE_DELAYED       = "BAG_UPDATE_DELAYED",
}
