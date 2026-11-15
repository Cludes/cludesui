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

-- The Currently Editing menu: find the 350x34 dropdown button on the page or
-- its header, click it, and snapshot every popup it opens on UIParent.
local function Find(root, test)
    local stack, hits = { root }, {}
    while #stack > 0 do
        local f = table.remove(stack)
        if type(f) == "table" and rawget(f, "\0children") then
            if test(f) then hits[#hits + 1] = f end
            for _, c in ipairs(f["\0children"]) do stack[#stack + 1] = c end
        end
    end
    return hits
end
local function Popups(label)
    -- The bar menu and its kin sit at levels 300 and up, on UIParent or the overlay layer.
    local n = 0
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    for _, host in ipairs(hosts) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() >= 300 then
                n = n + 1
                SNAP(label .. " popup " .. n, c)
            end
        end
    end
    OUT:write("== " .. label .. ": " .. n .. " popups\n")
end
if mod._TBBSelectBar then mod._TBBSelectBar(#bars - 2) end
Rebuild()
local roots = { CUI._scrollFrame, CUI._contentHeader or CUI._headerFrame }
local menuBtn
for _, root in ipairs(roots) do
    for _, b in ipairs(Find(root, function(f)
        return f["\0kind"] == "Button" and f:IsVisible() and math.floor((f["\0w"] or 0) + 0.5) == 350
            and math.floor((f["\0h"] or 0) + 0.5) == 34 and f["\0scripts"].OnClick
    end)) do menuBtn = menuBtn or b end
end
OUT:write("== menu button " .. tostring(menuBtn ~= nil) .. "\n")
if menuBtn then
    menuBtn["\0scripts"].OnClick(menuBtn, "LeftButton")
    Popups("menu open")
end

-- The Preset Style menu, empty and then with two saved presets (the second
-- selected): its dropdown is the 30-tall button under "Preset Style".
local function OpenPresetMenu(label)
    if menuBtn then menuBtn["\0scripts"].OnClick(menuBtn, "LeftButton") end -- close the bar menu
    local found
    for _, root in ipairs(roots) do
        for _, b in ipairs(Find(root, function(f)
            if not (f["\0kind"] == "Button" and f["\0shown"] and math.floor((f["\0h"] or 0) + 0.5) == 30 and f["\0scripts"].OnClick) then return false end
            for _, r in ipairs(f["\0regions"] or {}) do
                local t = r["\0v"] and r["\0v"].Text
                if t == "No Saved Presets" or t == "Steady" or t == "Bright" then return true end
            end
            return false
        end)) do found = found or b end
    end
    OUT:write("== preset button " .. tostring(found ~= nil) .. "\n")
    if not found then return end
    found["\0scripts"].OnClick(found, "LeftButton")
    local n = 0
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 200 then
            n = n + 1
            SNAP(label .. " " .. n, c)
        end
    end
    found["\0scripts"].OnClick(found, "LeftButton")
end
OpenPresetMenu("presets empty")
if mod.SaveTBBStylePreset and b1 then
    mod.SaveTBBStylePreset("Steady", b1)
    mod.SaveTBBStylePreset("Bright", b2 or b1)
    Rebuild()
    OpenPresetMenu("presets saved")
end

-- Group mode: open the bar menu and click the "Pair" group's header row.
local function MenuHost()
    local hosts = { UIParent }
    if CUI.OverlayParent then hosts[2] = CUI.OverlayParent() end
    for _, host in ipairs(hosts) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() >= 300 then return c end
        end
    end
end
Rebuild()
if menuBtn then
    for _, root in ipairs(roots) do
        for _, b in ipairs(Find(root, function(f)
            return f["\0kind"] == "Button" and f:IsVisible() and math.floor((f["\0w"] or 0) + 0.5) == 350
                and math.floor((f["\0h"] or 0) + 0.5) == 34 and f["\0scripts"].OnClick
        end)) do menuBtn = b end
    end
    menuBtn["\0scripts"].OnClick(menuBtn, "LeftButton")
    local menu = MenuHost()
    local header
    for _, r in ipairs(menu and Find(menu, function(f)
        if f["\0kind"] ~= "Button" then return false end
        for _, reg in ipairs(f["\0regions"] or {}) do
            if reg["\0v"] and reg["\0v"].Text == "Pair" then return true end
        end
        return false
    end) or {}) do header = header or r end
    OUT:write("== group header " .. tostring(header ~= nil) .. " menu " .. tostring(menu ~= nil) .. "\n")
    if header then
        header["\0scripts"].OnClick(header, "LeftButton")
        Snap("group mode")
    end
end
