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
    -- The preview popout docked to the panel (FULLSCREEN_DIALOG, level 10, on UIParent).
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 10 and rawget(c, "_title") then
            SNAP(label .. " popout", c)
        end
    end
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
    b1.showSpark = true; b1.width = 260; b1.height = 22; b1.borderTexture = "glow"; b1.borderTextureShiftX = 0
end
if b1 then b1.stackThresholdMaxEnabled = true; b1.stackThresholdEnabled = true; b1.stackThresholdTicks = "2,4" end
if b3 then b3.stackThresholdEnabled = true; b3.stackThresholdMulti = true end
if b2 then b2.verticalOrientation = true; b2.spellID = 33763; b2.trackType = "cooldown"; b2.fillUp = true end
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

-- The buff picker: the unassigned third bar's row in the bar menu opens it.
-- Its lists come from the module, stubbed here so every kind of row shows:
-- a tracked buff (selected on no bar), one used on another bar, one not
-- talented, and two cooldowns (one used elsewhere).
mod.GetTrackedBarSpells = function()
    return {
        { spellID = 774, name = "Rejuvenation", icon = 136081 },
        { spellID = 33763, name = "Lifebloom", icon = 134206 },
        { spellID = 8936, name = "Regrowth", icon = 136085, isKnown = false },
    }
end
mod.GetCDMSpellsForBar = function()
    return { { spellID = 18562, name = "Swiftmend", icon = 134914 }, { spellID = 740, name = "Tranquility", icon = 136107 } }
end
mod.SpellUsedOnAnyOtherTBB = function(id)
    if id == 33763 or id == 740 then return "Bar 2" end
end
local function RowWithText(root, text)
    for _, r in ipairs(root and Find(root, function(f)
        if f["\0kind"] ~= "Button" then return false end
        for _, reg in ipairs(f["\0regions"] or {}) do
            local t = reg["\0v"] and reg["\0v"].Text
            if t and t:find(text, 1, true) then return true end
        end
        return false
    end) or {}) do return r end
end
Rebuild()
for _, root in ipairs(roots) do
    for _, b in ipairs(Find(root, function(f)
        return f["\0kind"] == "Button" and f:IsVisible() and math.floor((f["\0w"] or 0) + 0.5) == 350
            and math.floor((f["\0h"] or 0) + 0.5) == 34 and f["\0scripts"].OnClick
    end)) do menuBtn = b end
end
if menuBtn then
    menuBtn["\0scripts"].OnClick(menuBtn, "LeftButton")
    local row = RowWithText(MenuHost(), "no buff assigned")
    OUT:write("== unassigned row " .. tostring(row ~= nil) .. "\n")
    if row then
        row["\0scripts"].OnClick(row, "LeftButton")
        HARNESS_ADVANCE(0.1)
        Popups("buff picker")
    end
end
-- From the picker, Custom Buff ID opens its popup.
do
    local picker
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 300 then picker = c end
    end
    local custom = RowWithText(picker, "Custom Buff ID")
    OUT:write("== custom row " .. tostring(custom ~= nil) .. "\n")
    if custom then
        custom["\0scripts"].OnClick(custom, "LeftButton")
        local popup = rawget(_G, "CUI_TBB_CustomBuffPopup")
        if popup then SNAP("custom buff popup", popup) end
    end
end

-- The stack threshold editor: the first bar's Enable Stack Threshold cog
-- (found by its tooltip), opened, and with several thresholds on.
local function OpenThresholdEditor(label)
    if mod._TBBSelectBar then mod._TBBSelectBar(#bars - 2) end
    Rebuild()
    -- The panel's tooltip frame (TOOLTIP strata, level 200, on UIParent) holds the shown text.
    local function TipText()
        for _, c in ipairs({ UIParent:GetChildren() }) do
            local text = rawget(c, "text")
            if c.GetFrameStrata and c:GetFrameStrata() == "TOOLTIP" and c:GetFrameLevel() == 200 and text then
                return text["\0v"] and text["\0v"].Text
            end
        end
    end
    local tipShown
    local cog
    for _, b in ipairs(Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnEnter and f["\0scripts"].OnClick
    end)) do
        tipShown = nil
        pcall(b["\0scripts"].OnEnter, b)
        tipShown = TipText()
        if type(tipShown) == "string" and tipShown:find("several stack counts", 1, true) then cog = cog or b end
        if b["\0scripts"].OnLeave then pcall(b["\0scripts"].OnLeave, b) end
    end
    OUT:write("== threshold cog " .. tostring(cog ~= nil) .. "\n")
    if not cog then return end
    cog["\0scripts"].OnClick(cog, "LeftButton")
    for _, c in ipairs({ UIParent:GetChildren() }) do
        if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" and c:GetFrameLevel() == 260 then
            SNAP(label, c)
        end
    end
end
OpenThresholdEditor("threshold editor")
if b1 then
    b1.stackThresholdMulti = true
    b1.stackThresholds = { { value = 2, r = 1, g = 0.5, b = 0, a = 1 }, { value = 4, r = 0, g = 1, b = 0, a = 1 } }
    OpenThresholdEditor("threshold editor multi")
end
