-- Forever: the BiS star on character sheet slots (CludesUIForeverEssentials_BiS.lua).
-- Your list holds item 16866 for the head; the head slot wears it, the chest
-- slot wears something else. After Blizzard's per-slot update the head shows
-- the star and the chest does not; taking it off the list hides the star.
local ns = CludesUI._ModuleNS and CludesUI._ModuleNS["CludesUIForeverEssentials"]
local Star = ns and ns.BisSlotStar
OUT:write("== star " .. tostring(Star ~= nil) .. "\n")
if not Star then return end

local worn = { [1] = 16866, [5] = 16865 }
rawset(_G, "GetInventoryItemID", function(unit, slot) return unit == "player" and worn[slot] or nil end)
local listed = { [16866] = 1 }
ns.BisSlotOf = function(id) return listed[id] end

local function Slot(id)
    local b = CreateFrame("Button", nil, UIParent)
    b:SetID(id)
    return b
end
local head, chest = Slot(1), Slot(5)
Star(head)
Star(chest)
local function Shown(b) return tostring(b._cuiBisStar ~= nil and b._cuiBisStar:IsShown()) end
OUT:write("== listed: head " .. Shown(head) .. " chest " .. Shown(chest) .. "\n")
listed[16866] = nil
Star(head)
OUT:write("== removed: head " .. Shown(head) .. "\n")
