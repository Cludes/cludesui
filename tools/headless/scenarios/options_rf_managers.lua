-- Raid & Party Frames > Buff Manager and Debuff Manager (CUI_RaidFrames_
-- ManagerPages.lua): each page snapped with its header, then every visible
-- button on it clicked, each on a fresh build, with what the click opened
-- snapped and closed and the managers' settings written out (the profile
-- keys starting dm or bm, and buff/debuff tables).
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUIRaidFrames"]
if not (mod and mod.db) then
    OUT:write("== no raid frames\n")
    return
end
local function Rebuild(page)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIRaidFrames")
    CUI:SelectPage(page)
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
    if depth > 5 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function DumpManagers()
    local p = mod.db.profile
    local keys = {}
    for k in pairs(p) do
        if type(k) == "string" and (k:find("^dm") or k:find("^bm") or k:lower():find("buff") or k:lower():find("debuff")) then
            keys[#keys + 1] = k
        end
    end
    table.sort(keys)
    for _, k in ipairs(keys) do OUT:write("   " .. k .. " " .. Dump(p[k], 0) .. "\n") end
end
local function Buttons()
    local roots = { CUI._scrollFrame, CUI._contentHeader or CUI._headerFrame }
    local out = {}
    for _, root in ipairs(roots) do
        for _, b in ipairs(Find(root, function(f)
            return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick ~= nil
        end)) do out[#out + 1] = b end
    end
    return out
end

for _, page in ipairs({ "Buff Manager", "Debuff Manager" }) do
    Rebuild(page)
    SNAP(page .. " page", CUI._scrollFrame)
    SNAP(page .. " header", CUI._contentHeader or CUI._headerFrame)
    local n = #Buttons()
    OUT:write("== " .. page .. " buttons " .. n .. "\n")
    for i = 1, n do
        Rebuild(page)
        local b = Buttons()[i]
        if b then
            local before = ShownTops()
            local ok, err = pcall(b["\0scripts"].OnClick, b, "LeftButton")
            OUT:write("== " .. page .. " click " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
            HARNESS_ADVANCE(0.1)
            local k = 0
            for _, host in ipairs(Hosts()) do
                for _, c in ipairs({ host:GetChildren() }) do
                    if c:IsShown() and not before[c] then
                        k = k + 1
                        SNAP(page .. " click " .. i .. " popup " .. k, c)
                        c:Hide()
                    end
                end
            end
            DumpManagers()
        end
    end
end
