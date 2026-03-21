-- BuffNudgeConstants.lua
-- All static constants shared across BuffNudge files via the addon namespace.
local _, ns = ...

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
-- textBase: pre-built prefix used by GetMissingSockets() — appends count suffix at runtime.
ns.SOCKET_SLOTS = {
    { id =  1, name = "Helmet",    textBase = "|cffff4444Socket: Helmet"    },
    { id =  2, name = "Neck",      textBase = "|cffff4444Socket: Neck"      },
    { id =  3, name = "Shoulder",  textBase = "|cffff4444Socket: Shoulder"  },
    { id =  5, name = "Chest",     textBase = "|cffff4444Socket: Chest"     },
    { id =  6, name = "Waist",     textBase = "|cffff4444Socket: Waist"     },
    { id =  7, name = "Legs",      textBase = "|cffff4444Socket: Legs"      },
    { id =  8, name = "Feet",      textBase = "|cffff4444Socket: Feet"      },
    { id =  9, name = "Wrist",     textBase = "|cffff4444Socket: Wrist"     },
    { id = 10, name = "Hands",     textBase = "|cffff4444Socket: Hands"     },
    { id = 11, name = "Ring 1",    textBase = "|cffff4444Socket: Ring 1"    },
    { id = 12, name = "Ring 2",    textBase = "|cffff4444Socket: Ring 2"    },
    { id = 15, name = "Back",      textBase = "|cffff4444Socket: Back"      },
    { id = 16, name = "Main Hand", textBase = "|cffff4444Socket: Main Hand" },
    { id = 17, name = "Off Hand",  textBase = "|cffff4444Socket: Off Hand"  },
}

-- Enchantable slots in Midnight: Helmet, Shoulder, Chest, Boots, Rings, Weapons.
-- Cloak and Bracers are NOT enchantable in Midnight.
-- textMissing: fully pre-built string used directly by GetMissingEnchants().
ns.ENCHANT_SLOTS = {
    { id =  1, name = "Helmet",    textMissing = "|cffff4444Enchant: Helmet|r"    },
    { id =  3, name = "Shoulder",  textMissing = "|cffff4444Enchant: Shoulder|r"  },
    { id =  5, name = "Chest",     textMissing = "|cffff4444Enchant: Chest|r"     },
    { id =  8, name = "Boots",     textMissing = "|cffff4444Enchant: Boots|r"     },
    { id = 11, name = "Ring 1",    textMissing = "|cffff4444Enchant: Ring 1|r"    },
    { id = 12, name = "Ring 2",    textMissing = "|cffff4444Enchant: Ring 2|r"    },
    { id = 16, name = "Main Hand", textMissing = "|cffff4444Enchant: Main Hand|r" },
    { id = 17, name = "Off Hand",  textMissing = "|cffff4444Enchant: Off Hand|r"  },
}

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
-- PRE-BUILT STRINGS
-- ============================================================
local R, O, Y, Z = ns.RED, ns.ORANGE, ns.YELLOW, ns.RESET
ns.TEXT_NO_FOOD   = R.."No Food Buff"..Z
ns.TEXT_NO_FLASK  = R.."No Flask/Phial"..Z
ns.TEXT_NO_STONE  = O.."No Soulstone"..Z
ns.TEXT_NO_BRONZE = Y.."Blessing of the Bronze"..Z
ns.TEXT_NO_PET          = R.."No Pet"..Z
ns.TEXT_NO_HEALTHSTONE  = R.."No Healthstone"..Z

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
