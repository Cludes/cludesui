-- Unit Frames > Player Aura Bars (CUI_PlayerAuraBars_ManagerPages.lua): the
-- page under its activation cover, then switched on, snapped with its header,
-- and every visible button on it clicked, each on a fresh build, with what
-- the click opened snapped and closed and the playerAuraBars settings
-- written out.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS["CludesUIUnitFrames"]
if not (mod and mod.db) then
    OUT:write("== no unit frames\n")
    return
end
local PAGE = "Player Aura Bars"
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIUnitFrames")
    CUI:SelectPage(PAGE)
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
    if depth > 6 then return "{...}" end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = k end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = tostring(k) .. "=" .. Dump(v[k], depth + 1) end
    return "{" .. table.concat(parts, ",") .. "}"
end
local function DumpPab()
    OUT:write("   pab " .. Dump(mod.db.profile.playerAuraBars, 0) .. "\n")
end
local function Buttons()
    local out = {}
    for _, root in ipairs({ CUI._scrollFrame, CUI._contentHeader or CUI._headerFrame }) do
        for _, b in ipairs(Find(root, function(f)
            return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick ~= nil
        end)) do out[#out + 1] = b end
    end
    return out
end

Rebuild()
SNAP("covered page", CUI._scrollFrame)
-- Switching on also builds the live bars, which needs aura methods the fake
-- client lacks: the setting is what matters here.
if mod.PAB_SetEnabled then pcall(mod.PAB_SetEnabled, true) end
OUT:write("== enabled " .. tostring(mod.PAB_Enabled and mod.PAB_Enabled()) .. "\n")
Rebuild()
SNAP("page", CUI._scrollFrame)
SNAP("header", CUI._contentHeader or CUI._headerFrame)
DumpPab()
local n = #Buttons()
OUT:write("== buttons " .. n .. "\n")
for i = 1, n do
    Rebuild()
    local b = Buttons()[i]
    if b then
        local before = ShownTops()
        local ok, err = pcall(b["\0scripts"].OnClick, b, "LeftButton")
        OUT:write("== click " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
        HARNESS_ADVANCE(0.1)
        local k = 0
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do
                if c:IsShown() and not before[c] then
                    k = k + 1
                    SNAP("click " .. i .. " popup " .. k, c)
                    c:Hide()
                end
            end
        end
        DumpPab()
    end
end
