-- Cooldown Manager > Tracking Bars: the page as built, then with three bars
-- (the first styled: texture, icon, timer, stack count, spark; the second
-- vertical; the last two in a group), each bar and the group selected in turn.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUICooldownManager"]
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUICooldownManager")
    CUI:SelectPage("Tracking Bars")
end
local function Snap(label)
    SNAP(label, CUI._scrollFrame)
    SNAP(label .. " header", CUI._contentHeader or CUI._headerFrame)
end
CUI:SelectModule("CludesUICooldownManager")
CUI:SelectPage("Tracking Bars")
Snap("as built")
if not (mod and mod.AddTrackedBuffBar and mod.GetTrackedBuffBars) then return end
-- Tracking bars live per spec: give the fake client one (Holy, 65).
local spec = rawget(_G, "C_SpecializationInfo") or {}
_G.C_SpecializationInfo = spec
spec.GetSpecialization = function() return 1 end
spec.GetSpecializationInfo = function() return 65, "Holy" end
if mod.InvalidateSpecKey then mod.InvalidateSpecKey() end
for _ = 1, 3 do mod.AddTrackedBuffBar() end
local bars = mod.GetTrackedBuffBars().bars
local b1, b2, b3 = bars[#bars - 2], bars[#bars - 1], bars[#bars]
OUT:write("== bars " .. #bars .. "\n")
if b1 then
    b1.spellID = 774; b1.texture = "flat"; b1.showIcon = true; b1.showTimer = true; b1.showStacks = true
    b1.showSpark = true; b1.width = 260; b1.height = 22
end
if b2 then b2.verticalOrientation = true; b2.spellID = 33763 end
if mod.TBBNextGroupID and mod.TBBSetBarGroup and b2 and b3 then
    local gid = mod.TBBNextGroupID()
    mod.TBBSetBarGroup(b2, gid); mod.TBBSetBarGroup(b3, gid)
    if mod.TBBSetGroupName then mod.TBBSetGroupName(gid, "Pair") end
    if mod.BuildTrackedBuffBars then mod.BuildTrackedBuffBars() end
end
for i = #bars - 2, #bars do
    if mod._TBBSelectBar then mod._TBBSelectBar(i) end
    Rebuild()
    Snap("bar " .. i)
end
