-- Damage Meters options (CUI_DamageMeters_Options.lua): each page snapshotted; then on each page
-- every colour swatch (a square 20 or 24 button) and toggle (40x20)
-- clicked on a fresh build and each inline cog opened, with the
-- module's saved settings written out after each.
local CUI = rawget(_G, "CludesUI")
if not (CUI._ModuleNS and CUI._ModuleNS["CludesUIDamageMeters"]) then
    OUT:write("== no damage meters module\n")
    return
end
local function Rebuild(page)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIDamageMeters")
    CUI:SelectPage(page)
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
local function DumpChat()
    local db = rawget(_G, "_CUDM_DB")
    OUT:write("   db " .. Dump(db and db.profile, 0) .. "\n")
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
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and not before[c] then
                if label then SNAP(label, c) end
                c:Hide()
            end
        end
    end
end
local function Click(f, label, ...)
    local fn = f["\0scripts"].OnClick
    if not fn then return end
    local ok, err = pcall(fn, f, ...)
    if not ok then OUT:write("== " .. label .. " ERR " .. tostring(err) .. "\n") end
end
local function Controls()
    return Find(CUI._scrollFrame, function(f)
        if f["\0kind"] ~= "Button" or not f:IsVisible() or not f["\0scripts"].OnClick then return false end
        local w, h = math.floor((f["\0w"] or 0) + 0.5), math.floor((f["\0h"] or 0) + 0.5)
        return (w == 40 and h == 20) or (w == h and (w == 20 or w == 24))
    end)
end
local function Cogs()
    return Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_cuiCogId") ~= nil and f:IsVisible()
    end)
end

for _, page in ipairs({ "Damage Meters", "Spell History" }) do
    Rebuild(page)
    SNAP(page .. " page", CUI._scrollFrame)
    DumpChat()
    local n = #Controls()
    OUT:write("== " .. page .. " controls " .. n .. "\n")
    for i = 1, n do
        Rebuild(page)
        local c = Controls()[i]
        if c then
            local before = ShownTops()
            Click(c, page .. " control " .. i, "LeftButton")
            HARNESS_ADVANCE(0.2)
            HideNew(before)
            OUT:write("== " .. page .. " control " .. i .. "\n")
            DumpChat()
        end
    end
    local nc = #Cogs()
    OUT:write("== " .. page .. " cogs " .. nc .. "\n")
    for i = 1, nc do
        Rebuild(page)
        local cog = Cogs()[i]
        if cog then
            local before = ShownTops()
            Click(cog, page .. " cog " .. i, "LeftButton")
            HideNew(before, page .. " cog " .. i)
        end
    end
end
