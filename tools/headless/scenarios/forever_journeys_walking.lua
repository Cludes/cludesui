-- Journeys on the real walking maps (CludesUIForeverEssentials_Walking.lua,
-- CludesUIJourneysData): the maps load on demand; a walk across Westfall
-- and Duskwood costs more than the straight line and has corners; the sea
-- between Auberdine and Teldrassil cannot be walked, so the boat is taken
-- without the island rule; the arrow aims at the first corner.
-- C_EncodingUtil is the harness's stand-in (tools/headless/encoding_util.lua).
local CUI = rawget(_G, "CludesUI")
local JY = CUI._Journeys
if not JY then
    OUT:write("== no Journeys on this client\n")
    return
end
C_EncodingUtil = dofile("tools/headless/encoding_util.lua")
Enum.CompressionMethod = Enum.CompressionMethod or {}
Enum.CompressionMethod.Deflate = 1

local here = { x = -10640, y = 1050, c = 0 }
local pin = { c = 0, x = -10560, y = -1180 }
local facing = 0
UnitPosition = function() return here.x, here.y, 0, here.c end
GetPlayerFacing = function() return facing end
UnitName = function(u) return u == "player" and "Me" or nil end
GetRealmName = function() return "Lightbane" end
UnitFactionGroup = function() return "Alliance" end
UnitOnTaxi = function() return false end
IsInInstance = function() return false end
InCombatLockdown = function() return false end
C_Map.HasUserWaypoint = function() return pin ~= nil end
C_Map.GetUserWaypoint = function() return pin and { uiMapID = 1431, position = { x = 0.5, y = 0.5 } } end
C_Map.GetWorldPosFromMapPos = function() return pin.c, { x = pin.x, y = pin.y } end
C_Map.GetMapInfo = function() return { name = "the pin" } end
C_Item.GetItemCount = function() return 0 end

local W = rawget(_G, "CludesUI") and nil
local function Report(label)
    local t0 = os.clock()
    JY.Replan()
    for _ = 1, 50 do
        local _, _, _, _, busy = JY.Plan()
        if not busy then break end
        HARNESS_ADVANCE(0.02)
    end
    local plan, _, arrived, corners = JY.Plan()
    OUT:write(("== %s: %s (%.2fs to plan)\n"):format(label, arrived and "arrived" or plan and ("%d legs, %ds"):format(#plan.legs, plan.seconds) or "no plan",
        os.clock() - t0))
    for i, leg in ipairs(plan and plan.legs or {}) do
        OUT:write(("   %d. %s (%s, %ds)\n"):format(i, JY.StepText(leg), leg.mode, leg.seconds))
    end
    if corners then
        OUT:write(("   corners %d, first (%.0f, %.0f)\n"):format(#corners / 2, corners[3] or 0, corners[4] or 0))
    end
end

CludesUIDB.journeys = { enabled = true, chars = { ["Me-Lightbane"] = { flights = {}, landings = {} } } }
JY.Apply()
OUT:write("== data addon loaded " .. tostring(C_AddOns.IsAddOnLoaded("CludesUIJourneysData")) .. "\n")
local straight = math.sqrt((pin.x - here.x) ^ 2 + (pin.y - here.y) ^ 2)
OUT:write(("== straight line Sentinel Hill to Duskwood %.0f yd, %ds at run speed\n"):format(straight, straight / 7))
Report("Westfall to Duskwood on foot")

-- The arrow aims at the first corner: face it and the arrow points up the screen.
local plan, _, _, corners = JY.Plan()
if corners then
    local dx, dy = corners[3] - here.x, corners[4] - here.y
    facing = math.atan2(dy, dx)
    HARNESS_ADVANCE(0.2)
    local card = rawget(_G, "CludesUIJourney")
    OUT:write("== card shown " .. tostring(card and card:IsShown()) .. "\n")
end

-- The minimap route: dots along the walk within the minimap's circle.
C_Minimap = C_Minimap or {}
C_Minimap.GetViewRadius = function() return 233 end
local mm = rawget(_G, "Minimap")
if mm then
    mm.GetWidth = function() return 140 end
    mm.IsVisible = function() return true end
    HARNESS_ADVANCE(0.2)
    local dotCount = 0
    for _, child in ipairs({ mm:GetChildren() }) do
        for _, region in ipairs({ child:GetRegions() }) do
            if region.IsShown and region:IsShown() then dotCount = dotCount + 1 end
        end
    end
    OUT:write(("== minimap route dots %d (233 yd view, one every 12 yd)\n"):format(dotCount))
else
    OUT:write("== no Minimap frame in the fake client\n")
end

-- Standing still: no new plan is started.
local before = select(1, JY.Plan())
HARNESS_ADVANCE(4)
OUT:write("== standing still keeps the plan " .. tostring(select(1, JY.Plan()) == before) .. "\n")

-- Auberdine to Darnassus: the sea cannot be walked.
here = { x = 6420, y = 600, c = 1 }
pin = { c = 1, x = 9947, y = 2630 }
Report("Auberdine to Darnassus")

-- Elwynn: Goldshire to Stormwind's gate, a short walk.
here = { x = -9460, y = 60, c = 0 }
pin = { c = 0, x = -9060, y = 430 }
Report("Goldshire to Stormwind gate")

-- Ride a mount for a moment: walks are then timed at its speed (60% mount: 11.2 yd/s).
IsMounted = function() return true end
IsSwimming = function() return false end
IsFlying = function() return false end
GetUnitSpeed = function() return 11.2, 11.2, 0, 0 end
HARNESS_ADVANCE(0.6)
IsMounted = function() return false end
here = { x = -10640, y = 1050, c = 0 }
pin = { c = 0, x = -10560, y = -1180 }
Report("Westfall to Duskwood after riding a mount")
