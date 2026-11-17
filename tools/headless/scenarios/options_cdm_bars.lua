-- Cooldown Manager > CDM Bars: the page for every bar, rebuilt fresh per
-- bar (page and header snapped), every inline cog clicked with the popup it
-- opens snapped; then on the first bar every toggle (a 40x20 button) and
-- colour swatch (a square 20 or 24 button) clicked, each on a fresh build,
-- with the bar written out; then every sync icon's All link clicked after
-- the first bar is given settings unlike the others, every bar written out.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUICooldownManager"]
local env = mod and mod._CDMO_OptEnv
if not (env and env.optState) then
    OUT:write("== no cdm options\n")
    return
end
-- Bars are stored per spec: give the fake client one (Holy, 65).
local spec = rawget(_G, "C_SpecializationInfo") or {}
_G.C_SpecializationInfo = spec
spec.GetSpecialization = function() return 1 end
spec.GetSpecializationInfo = function() return 65, "Holy" end
if mod.InvalidateSpecKey then mod.InvalidateSpecKey() end

local function Rebuild(index)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    env.optState.selectedCDMBarIndex = index
    CUI:SelectModule("CludesUICooldownManager")
    CUI:SelectPage("CDM Bars")
end
local function Hosts()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    return hosts
end
local function ShownTops()
    local set = {}
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() then set[c] = true end
        end
    end
    return set
end
local function Find(root, test)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if test(f) then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Dump(v, depth)
    if type(v) ~= "table" then
        if type(v) == "number" then return string.format("%.3f", v) end
        return tostring(v)
    end
    if depth > 4 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function Bars()
    local p = env.DB and env.DB()
    return p and p.cdmBars and p.cdmBars.bars or {}
end
local function DumpBars(only)
    for i, b in ipairs(Bars()) do
        if not only or i == only then OUT:write("   bar " .. i .. " " .. Dump(b, 0) .. "\n") end
    end
end
local function HideNew(before, label)
    local n = 0
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and not before[c] then
                n = n + 1
                if label then SNAP(label .. " popup " .. n, c) end
                c:Hide()
            end
        end
    end
    return n
end
local function Click(f, label)
    local fn = f["\0scripts"].OnClick
    if not fn then return end
    local ok, err = pcall(fn, f, "LeftButton")
    if not ok then OUT:write("== " .. label .. " ERR " .. tostring(err) .. "\n") end
end

local count = #Bars()
OUT:write("== bars " .. count .. "\n")
for i = 1, count do
    Rebuild(i)
    SNAP("page " .. i, CUI._scrollFrame)
    SNAP("header " .. i, CUI._contentHeader or CUI._headerFrame)
    local cogs = Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_cuiCogId") ~= nil and f:IsVisible()
    end)
    OUT:write("== cogs " .. i .. " " .. #cogs .. "\n")
    for j, cog in ipairs(cogs) do
        local before = ShownTops()
        Click(cog, "cog " .. i .. " " .. j)
        OUT:write("== cog " .. i .. " " .. j .. ": " .. HideNew(before, "cog " .. i .. " " .. j) .. "\n")
    end
end

local function Controls()
    return Find(CUI._scrollFrame, function(f)
        if f["\0kind"] ~= "Button" or not f:IsVisible() or not f["\0scripts"].OnClick then return false end
        local w, h = math.floor((f["\0w"] or 0) + 0.5), math.floor((f["\0h"] or 0) + 0.5)
        return (w == 40 and h == 20) or (w == h and (w == 20 or w == 24))
    end)
end
Rebuild(1)
local n = #Controls()
OUT:write("== controls " .. n .. "\n")
for i = 1, n do
    Rebuild(1)
    local c = Controls()[i]
    if c then
        local before = ShownTops()
        Click(c, "control " .. i)
        HARNESS_ADVANCE(0.2)
        HideNew(before)
        OUT:write("== control " .. i .. "\n")
        DumpBars(1)
    end
end

-- A link shows only while the bars differ; a hidden one still copies. Its
-- row is shown only on the page in view (the scroll frame keeps other
-- modules' cached pages too).
local function AllLinks()
    return Find(CUI._scrollFrame, function(f)
        if f["\0kind"] ~= "Button" or not f["\0scripts"].OnClick then return false end
        local row = f:GetParent()
        if not (row and row:IsVisible()) then return false end
        for _, r in ipairs(rawget(f, "\0regions") or {}) do
            local v = rawget(r, "\0v")
            if v and v.Text == "All" then return true end
        end
        return false
    end)
end
local first = Bars()[1]
if first then
    local distinct = {
        borderTexture = "glow", borderTextureOffset = 2, borderTextureOffsetY = 3, borderTextureShiftX = 1,
        borderTextureShiftY = -1, borderBehind = true, borderAboveEffects = true,
        borderColor = { r = 0.1, g = 0.2, b = 0.3, a = 0.9 }, borderClassColor = false,
        borderThickness = "thick", borderSize = 3, iconZoom = 7, iconSize = 41, spacing = 5,
        bgColor = { r = 0.3, g = 0.1, b = 0.2, a = 0.5 }, keybindFontSize = 15, keybindOffsetX = 2,
        keybindOffsetY = -3, stackFontSize = 13, cooldownFontSize = 17, showKeybind = true, showTooltip = true,
    }
    for k, v in pairs(distinct) do first[k] = v end
end
Rebuild(1)
local links = #AllLinks()
OUT:write("== sync links " .. links .. "\n")
for i = 1, links do
    Rebuild(1)
    local link = AllLinks()[i]
    if link then
        Click(link, "sync " .. i)
        OUT:write("== sync " .. i .. "\n")
        DumpBars()
    end
end
