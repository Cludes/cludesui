-- QoL Auto Select Single Gossip (CludesUIQoL.lua): the lone option picked;
-- Hold Shift to Skip with another key, and in Triggers mode; Only Service
-- NPCs picking a vendor's line but not a teleport.
local CUI = rawget(_G, "CludesUI")
OUT:write("== apply " .. tostring(CUI._applyAutoGossip ~= nil) .. "\n")
if not CUI._applyAutoGossip then return end

local VENDOR, PORTAL = 132060, 132061
local option = { name = "Let me browse your goods.", icon = VENDOR, orderIndex = 0, gossipOptionID = 1, status = Enum.GossipOptionStatus.Available }
C_GossipInfo.GetOptions = function() return { option } end
C_GossipInfo.GetText = function() return "Hello." end
C_GossipInfo.GetAvailableQuests = function() return {} end
C_GossipInfo.GetActiveQuests = function() return {} end
C_GossipInfo.GetNumAvailableQuests = function() return 0 end
local pickedCount = 0
C_GossipInfo.SelectOptionByIndex = function() pickedCount = pickedCount + 1 end
GetFileIDFromPath = function(path) return path:find("Vendor") and VENDOR or 1 end
IsInInstance = function() return false end
local keys = { shift = false, ctrl = false }
IsShiftKeyDown = function() return keys.shift end
IsControlKeyDown = function() return keys.ctrl end
IsAltKeyDown = function() return false end

CludesUIDB.autoGossip = true
CUI._applyAutoGossip()
local function Talk(tag)
    local before = pickedCount
    HARNESS_FIRE_EVENT("GOSSIP_SHOW")
    HARNESS_FIRE_EVENT("GOSSIP_CLOSED")
    OUT:write(("== %s: %s\n"):format(tag, pickedCount > before and "picked" or "not picked"))
end

Talk("vendor, no key")
keys.shift = true
Talk("holding Shift (default skip)")
keys.shift = false
CludesUIDB.autoGossipModifier = "CTRL"
keys.ctrl = true
Talk("Ctrl as the key, held")
keys.ctrl = false
Talk("Ctrl as the key, not held")
CludesUIDB.autoGossipModifierMode = "TRIGGER"
Talk("Triggers, not held")
keys.ctrl = true
Talk("Triggers, Ctrl held")
keys.ctrl = false
CludesUIDB.autoGossipModifier, CludesUIDB.autoGossipModifierMode = nil, nil
CludesUIDB.autoGossipShiftSkip = false
keys.shift = true
Talk("modifier off, Shift held")
keys.shift = false
CludesUIDB.autoGossipShiftSkip = nil
CludesUIDB.autoGossipServiceOnly = true
Talk("service only: vendor")
option.icon, option.name = PORTAL, "Teleport me to the Dalaran crater."
Talk("service only: teleport")
CludesUIDB.autoGossipServiceOnly = nil
Talk("any NPC: teleport")
