-- Info Bar options: the page for each bar as the selected one (the first as
-- loaded; a bar holding one block of every type, so every block section is
-- built; a vertical bar; a fill-sized bar), its header, and every inline cog
-- on the page clicked with the popup it opens snapshotted.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIDataBars
BreakUpLargeNumbers = tostring
GetNetStats = function() return 0, 0, 42, 61 end
-- The Currency block's picker reads the character's currency list.
do
    local list = {
        { name = "Dungeon and Raid", isHeader = true, isHeaderExpanded = true },
        { name = "Valorstones", currencyID = 3008, iconFileID = 5868902, quantity = 1200 },
        { name = "Resonance Crystals", currencyID = 2815, iconFileID = 2967113, quantity = 85 },
    }
    local ci = rawget(_G, "C_CurrencyInfo") or {}
    _G.C_CurrencyInfo = ci
    ci.GetCurrencyListSize = function() return #list end
    ci.GetCurrencyListInfo = function(i) return list[i] end
    ci.ExpandCurrencyList = function() end
    ci.GetCurrencyListLink = function(i) return list[i] and ("currency:" .. tostring(list[i].currencyID)) end
end
if not mod then
    OUT:write("== no info bar module\n")
    return
end
local PAGE = "Info Bar"
local function Rebuild(barId)
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    local p = mod.GetProfile()
    if p and barId then p.selectedBarId = barId end
    CUI:SelectModule("CludesUIDataBars")
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
local function Page(label, barId)
    Rebuild(barId)
    SNAP("page " .. label, CUI._scrollFrame)
    SNAP("header " .. label, CUI._contentHeader or CUI._headerFrame)
    local cogs = Cogs(CUI._scrollFrame)
    OUT:write("== cogs " .. label .. " " .. #cogs .. "\n")
    for i, cog in ipairs(cogs) do
        local before = ShownTops()
        local click = cog["\0scripts"].OnClick
        if click then
            local ok, err = pcall(click, cog, "LeftButton")
            if not ok then OUT:write("== cog " .. label .. " " .. i .. " ERR " .. tostring(err) .. "\n") end
        end
        local n = 0
        for _, host in ipairs(Hosts()) do
            for _, c in ipairs({ host:GetChildren() }) do
                if c:IsShown() and not before[c] then
                    n = n + 1
                    SNAP("cog " .. label .. " " .. i .. " popup " .. n, c)
                    c:Hide()
                end
            end
        end
        OUT:write("== cog " .. label .. " " .. i .. ": " .. n .. "\n")
    end
end

local first = mod.BarsInOrder()[1]
Page("first", first and first.id)

local all = mod.CreateBar("empty")
if all then
    for _, t in ipairs(mod.BLOCK_TYPES) do
        mod.AddBlock(all.id, t.key)
    end
    OUT:write("== blocks " .. #all.blocks .. "\n")
    Page("every block", all.id)
end

local vert = mod.CreateBar("empty")
if vert then
    vert.orientation = "V"
    for _, k in ipairs({ "clock", "gold", "micromenu", "spacer" }) do
        mod.AddBlock(vert.id, k)
    end
    mod.ApplyBar(vert.id)
    Page("vertical", vert.id)
end

local fill = mod.CreateBar("empty")
if fill then
    fill.lengthMode = "fill"
    local loc = mod.AddBlock(fill.id, "location")
    mod.AddBlock(fill.id, "fps")
    if loc and mod.SetFillBlock then mod.SetFillBlock(fill.id, loc.id) end
    mod.ApplyBar(fill.id)
    Page("fill", fill.id)
end
