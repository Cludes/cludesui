-- Action Bars > Bar Display: the page for every bar the selector offers,
-- rebuilt fresh per bar (its page and header snapped), every inline cog
-- clicked with the popup it opens snapped; then on the Main Bar every
-- toggle (a 40x20 button) and every colour swatch (a square 20 or 24 button)
-- clicked, each on a fresh build, with the bar's settings written out.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIActionBars
if not (mod and mod.BAR_DROPDOWN_ORDER) then
    OUT:write("== no action bars\n")
    return
end
local function Rebuild(key)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    if CUI._setActionBarKey then CUI._setActionBarKey(key) end
    CUI:SelectModule("CludesUIActionBars")
    CUI:SelectPage("Bar Display")
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
local function BarSettings(key)
    local env = mod._ABO_OptEnv
    local db = env and env.EAB and env.EAB.db
    local bar = db and db.profile and db.profile.bars and db.profile.bars[key]
    OUT:write("   " .. key .. " " .. Dump(bar, 0) .. "\n")
end
local function NewPopups(before, label)
    local n = 0
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and not before[c] then
                n = n + 1
                SNAP(label .. " popup " .. n, c)
                c:Hide()
            end
        end
    end
    return n
end

for _, key in ipairs(mod.BAR_DROPDOWN_ORDER) do
    Rebuild(key)
    SNAP("page " .. key, CUI._scrollFrame)
    SNAP("header " .. key, CUI._contentHeader or CUI._headerFrame)
    local cogs = Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_cuiCogId") ~= nil and f:IsVisible()
    end)
    OUT:write("== cogs " .. key .. " " .. #cogs .. "\n")
    for i, cog in ipairs(cogs) do
        local before = ShownTops()
        local ok, err = pcall(cog["\0scripts"].OnClick, cog, "LeftButton")
        if not ok then OUT:write("== cog " .. key .. " " .. i .. " ERR " .. tostring(err) .. "\n") end
        OUT:write("== cog " .. key .. " " .. i .. ": " .. NewPopups(before, "cog " .. key .. " " .. i) .. "\n")
    end
end

local function Controls()
    return Find(CUI._scrollFrame, function(f)
        if f["\0kind"] ~= "Button" or not f:IsVisible() or not f["\0scripts"].OnClick then return false end
        local w, h = math.floor((f["\0w"] or 0) + 0.5), math.floor((f["\0h"] or 0) + 0.5)
        return (w == 40 and h == 20) or (w == h and (w == 20 or w == 24))
    end)
end
Rebuild("MainBar")
local count = #Controls()
OUT:write("== controls " .. count .. "\n")
for i = 1, count do
    Rebuild("MainBar")
    local c = Controls()[i]
    if c then
        local before = ShownTops()
        local ok, err = pcall(c["\0scripts"].OnClick, c, "LeftButton")
        OUT:write("== control " .. i .. " " .. math.floor(c["\0w"] + 0.5) .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
        HARNESS_ADVANCE(0.2)
        for _, host in ipairs(Hosts()) do
            for _, top in ipairs({ host:GetChildren() }) do
                if top:IsShown() and not before[top] then top:Hide() end
            end
        end
        BarSettings("MainBar")
    end
end
