-- Unit Frames > Boss Frames and Mini Frames: each page built fresh, every
-- inline cog on it clicked with the popup it opens snapshotted, then the
-- swatch pairs' clicks (each swatch of each pair, settings written out after).
local CUI = rawget(_G, "CludesUI")
local function Rebuild(page)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIUnitFrames")
    CUI:SelectPage(page)
end
local function Hosts()
    local hosts = { UIParent }
    if CUI.OverlayParent and CUI.OverlayParent() ~= UIParent then hosts[2] = CUI.OverlayParent() end
    return hosts
end
local function Walk(root, pred)
    local out, stack = {}, { root }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f:IsVisible() and pred(f) then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local function Dump(t, depth)
    if type(t) ~= "table" then return tostring(t) end
    if depth > 3 then return "{...}" end
    local keys = {}
    for k in pairs(t) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(t[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local db = CUI._ModuleNS and CUI._ModuleNS["CludesUIUnitFrames"] and CUI._ModuleNS["CludesUIUnitFrames"]._UFO_OptEnv
for _, page in ipairs({ "Boss Frames", "Mini Frames", "Main Frames" }) do
    Rebuild(page)
    SNAP("page " .. page, CUI._scrollFrame)
    local cogs = Walk(CUI._scrollFrame, function(f) return rawget(f, "_cuiCogId") ~= nil end)
    OUT:write("== cogs " .. page .. " " .. #cogs .. "\n")
    for i, cog in ipairs(cogs) do
        local before = {}
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do if c:IsShown() then before[c] = true end end
        end
        local click = cog["\0scripts"].OnClick
        if click then pcall(click, cog, "LeftButton") end
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do
                if c:IsShown() and not before[c] then
                    SNAP("cog " .. page .. " " .. i, c)
                    c:Hide()
                end
            end
        end
    end
    -- Swatch pair buttons: the ones that keep their stock click as _eabOrigClick.
    local n = #Walk(CUI._scrollFrame, function(f) return rawget(f, "_eabOrigClick") ~= nil end)
    OUT:write("== swatches " .. page .. " " .. n .. "\n")
    for i = 1, n do
        local sw = Walk(CUI._scrollFrame, function(f) return rawget(f, "_eabOrigClick") ~= nil end)[i]
        if sw then
            local ok, err = pcall(sw["\0scripts"].OnClick, sw, "LeftButton")
            OUT:write("== swatch " .. page .. " " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
            for _, c in ipairs({ UIParent:GetChildren() }) do
                if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" then c:Hide() end
            end
            if db and db.db then
                local prof = db.db.profile
                for _, k in ipairs({ "player", "target", "boss", "pet", "targettarget", "focustarget", "focus" }) do
                    if type(prof[k]) == "table" then OUT:write("   " .. k .. " " .. Dump(prof[k], 0) .. "\n") end
                end
            end
        end
    end
end
