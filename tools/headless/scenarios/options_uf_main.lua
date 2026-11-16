-- Unit Frames > Main Frames: the whole page for every unit the selector
-- offers (each section of SharedAppearance, SharedBars and SharedCastAuras),
-- rebuilt fresh per unit, every inline cog on it clicked with the popup it
-- opens snapshotted, then the player page again from the page cache.
local CUI = rawget(_G, "CludesUI")
local units = { "player", "target", "focus", "targettarget", "focustarget", "pet", "boss" }
local function Rebuild(unit)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    if CUI._setUnitFrameUnit then CUI._setUnitFrameUnit(unit) end
    CUI:SelectModule("CludesUIUnitFrames")
    CUI:SelectPage("Main Frames")
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
local function Cogs(root)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and rawget(f, "_cuiCogId") and f:IsVisible() then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
for _, unit in ipairs(units) do
    Rebuild(unit)
    SNAP("page " .. unit, CUI._scrollFrame)
    SNAP("header " .. unit, CUI._contentHeader or CUI._headerFrame)
    local cogs = Cogs(CUI._scrollFrame)
    OUT:write("== cogs " .. unit .. " " .. #cogs .. "\n")
    for i, cog in ipairs(cogs) do
        local before = ShownTops()
        local click = cog["\0scripts"].OnClick
        if click then
            local ok, err = pcall(click, cog, "LeftButton")
            if not ok then OUT:write("== cog " .. unit .. " " .. i .. " ERR " .. tostring(err) .. "\n") end
        end
        local n = 0
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do
                if c:IsShown() and not before[c] then
                    n = n + 1
                    SNAP("cog " .. unit .. " " .. i .. " popup " .. n, c)
                    c:Hide()
                end
            end
        end
        OUT:write("== cog " .. unit .. " " .. i .. ": " .. n .. "\n")
    end
end
-- Each sync icon's "All" link clicked in turn on the player and target pages
-- (the page repaints after each), every unit's settings written out after
-- each click: the copy paths, not just the look.
local function AllLinks(root)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick then
                for _, r in ipairs(rawget(f, "\0regions") or {}) do
                    local v = rawget(r, "\0v")
                    if v and v.Text == "All" then
                        out[#out + 1] = f
                        break
                    end
                end
            end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Dump(t, depth)
    if type(t) ~= "table" then return tostring(t) end
    if depth > 4 then return "{...}" end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(t[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local env = CUI._ModuleNS and CUI._ModuleNS["CludesUIUnitFrames"] and CUI._ModuleNS["CludesUIUnitFrames"]._UFO_OptEnv
for _, unit in ipairs({ "player", "target" }) do
    -- With the Text Bar on, so its rows (and their sync icons) show too.
    if env and env.UNIT_DB_MAP and env.UNIT_DB_MAP[unit] then env.UNIT_DB_MAP[unit]().bottomTextBar = true end
    Rebuild(unit)
    local n = #AllLinks(CUI._scrollFrame)
    OUT:write("== sync links " .. unit .. " " .. n .. "\n")
    for i = 1, n do
        local link = AllLinks(CUI._scrollFrame)[i]
        if link then
            local ok, err = pcall(link["\0scripts"].OnClick, link, "LeftButton")
            OUT:write("== sync " .. unit .. " " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
            if env and env.UNIT_DB_MAP then
                for _, u in ipairs(units) do
                    local get = env.UNIT_DB_MAP[u]
                    if get then OUT:write("   " .. u .. " " .. Dump(get(), 0) .. "\n") end
                end
            end
        end
    end
end
if CUI._setUnitFrameUnit then CUI._setUnitFrameUnit("player") end
CUI:SelectPage("Boss Frames")
CUI:SelectPage("Main Frames")
SNAP("again", CUI._scrollFrame)
