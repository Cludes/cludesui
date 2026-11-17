-- Minimap options (CUI_Minimap_Options.lua): the page and header snapped,
-- every inline cog clicked with its popup snapped; then, each on a fresh
-- build, every toggle (a 40x20 button) and colour swatch (a square 20 or 24
-- button) clicked, and every dropdown opened with its second row picked,
-- the minimap settings written out after each.
local CUI = rawget(_G, "CludesUI")
if not (CUI._ModuleNS and CUI._ModuleNS["CludesUIMinimap"]) then
    OUT:write("== no minimap module\n")
    return
end
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIMinimap")
    CUI:SelectPage("Minimap")
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
    if depth > 5 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function DumpMinimap()
    local db = rawget(_G, "_CUMM_DB")
    local p = db and db.profile
    OUT:write("   minimap " .. Dump(p and p.minimap, 0) .. "\n")
end
local function Click(f, label, ...)
    local fn = f["\0scripts"].OnClick
    if not fn then return end
    local ok, err = pcall(fn, f, ...)
    if not ok then OUT:write("== " .. label .. " ERR " .. tostring(err) .. "\n") end
end

Rebuild()
SNAP("page", CUI._scrollFrame)
SNAP("header", CUI._contentHeader or CUI._headerFrame)
DumpMinimap()

local function Cogs()
    return Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_cuiCogId") ~= nil and f:IsVisible()
    end)
end
local cogCount = #Cogs()
OUT:write("== cogs " .. cogCount .. "\n")
for i = 1, cogCount do
    Rebuild()
    local cog = Cogs()[i]
    if cog then
        local before = ShownTops()
        Click(cog, "cog " .. i, "LeftButton")
        OUT:write("== cog " .. i .. ": " .. HideNew(before, "cog " .. i) .. "\n")
    end
end

local function Controls()
    return Find(CUI._scrollFrame, function(f)
        if f["\0kind"] ~= "Button" or not f:IsVisible() or not f["\0scripts"].OnClick then return false end
        local w, h = math.floor((f["\0w"] or 0) + 0.5), math.floor((f["\0h"] or 0) + 0.5)
        return (w == 40 and h == 20) or (w == h and (w == 20 or w == 24))
    end)
end
Rebuild()
local n = #Controls()
OUT:write("== controls " .. n .. "\n")
for i = 1, n do
    Rebuild()
    local c = Controls()[i]
    if c then
        local before = ShownTops()
        Click(c, "control " .. i, "LeftButton")
        HARNESS_ADVANCE(0.2)
        HideNew(before)
        OUT:write("== control " .. i .. "\n")
        DumpMinimap()
    end
end

local function Dropdowns()
    return Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_invalidateMenu") ~= nil and f:IsVisible()
    end)
end
Rebuild()
local d = #Dropdowns()
OUT:write("== dropdowns " .. d .. "\n")
for i = 1, d do
    Rebuild()
    local dd = Dropdowns()[i]
    if dd then
        Click(dd, "dropdown " .. i, "LeftButton")
        HARNESS_ADVANCE(0.05)
        local menu = rawget(dd, "_ddMenu")
        if menu then
            SNAP("dropdown " .. i .. " menu", menu)
            local rows = Find(menu, function(f)
                return f["\0kind"] == "Button" and rawget(f, "_key") ~= nil and f:IsVisible()
            end)
            local pick = rows[2] or rows[1]
            if pick and not rawget(pick, "_flyout") then
                Click(pick, "dropdown " .. i .. " pick", "LeftButton")
                HARNESS_ADVANCE(0.1)
                OUT:write("== dropdown " .. i .. " picked " .. tostring(rawget(pick, "_key")) .. "\n")
            end
            if menu:IsShown() then menu:Hide() end
        end
        DumpMinimap()
    end
end
Rebuild()
SNAP("page after", CUI._scrollFrame)
