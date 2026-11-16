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

-- The header of the every-block bar: each of its buttons clicked (left, then
-- right: a segment's right-click opens its block menu), each popup snapped,
-- the page rebuilt between clicks so one click's result does not feed the next.
local function HeaderButtons()
    local out, stack = {}, { CUI._contentHeader or CUI._headerFrame }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
if all then
    for _, which in ipairs({ "LeftButton", "RightButton" }) do
        Rebuild(all.id)
        local count = #HeaderButtons()
        OUT:write("== header buttons " .. which .. " " .. count .. "\n")
        for i = 1, count do
            Rebuild(all.id)
            local btn = HeaderButtons()[i]
            local before = ShownTops()
            local ok, err = pcall(btn["\0scripts"].OnClick, btn, which)
            if not ok then OUT:write("== hdr " .. which .. " " .. i .. " ERR " .. tostring(err) .. "\n") end
            local n = 0
            for _, host in ipairs(Hosts()) do
                for _, c in ipairs({ host:GetChildren() }) do
                    if c:IsShown() and not before[c] then
                        n = n + 1
                        SNAP("hdr " .. which .. " " .. i .. " popup " .. n, c)
                        c:Hide()
                    end
                end
            end
            OUT:write("== hdr " .. which .. " " .. i .. ": " .. n .. " bars " .. #mod.BarsInOrder() .. "\n")
        end
    end
end

-- Every colour swatch on the every-block page clicked in turn (the ones that
-- keep their stock click as _eabOrigClick), on a fresh build each time, with
-- each block's colour choice written out after the click.
local function Swatches()
    local out, stack = {}, { CUI._scrollFrame }
    while #stack > 0 do
        local f = table.remove(stack, 1)
        if type(f) == "table" and rawget(f, "\0children") then
            if rawget(f, "_eabOrigClick") ~= nil and f:IsVisible() and f["\0scripts"].OnClick then out[#out + 1] = f end
            for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
        end
    end
    return out
end
local COLOUR_KEYS = { "useClassColor", "useAccentColor", "useCoinColor", "useCrestColor", "useDynamicColor" }
local function Colours(bar)
    for _, b in ipairs(bar.blocks) do
        local bits = { b.type }
        for _, k in ipairs(COLOUR_KEYS) do
            if b[k] ~= nil then bits[#bits + 1] = k .. "=" .. tostring(b[k]) end
        end
        if b.color then bits[#bits + 1] = string.format("color=%.3f,%.3f,%.3f", b.color.r or -1, b.color.g or -1, b.color.b or -1) end
        OUT:write("   " .. table.concat(bits, " ") .. "\n")
    end
end
if all then
    Rebuild(all.id)
    local n = #Swatches()
    OUT:write("== swatches " .. n .. "\n")
    for i = 1, n do
        Rebuild(all.id)
        local sw = Swatches()[i]
        if sw then
            local ok, err = pcall(sw["\0scripts"].OnClick, sw, "LeftButton")
            OUT:write("== swatch " .. i .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
            for _, c in ipairs({ UIParent:GetChildren() }) do
                if c:IsShown() and c.GetFrameStrata and c:GetFrameStrata() == "FULLSCREEN_DIALOG" then c:Hide() end
            end
            Colours(all)
        end
    end
    Rebuild(all.id)
    SNAP("page after swatches", CUI._scrollFrame)
end

-- Drag-to-reorder on the every-block bar's preview: press a segment, move the
-- cursor past the 3px threshold to a strip position (the fake client puts
-- every frame's left edge at 100), tick so the drag starts and follows, snap
-- the header mid-drag, release, tick, and write out the block order.
if all then
    local cursorX, buttonDown = 0, false
    GetCursorPosition = function() return cursorX, 0 end
    IsMouseButtonDown = function() return buttonDown end
    local function Segments()
        local out, stack = {}, { CUI._contentHeader or CUI._headerFrame }
        while #stack > 0 do
            local f = table.remove(stack, 1)
            if type(f) == "table" and rawget(f, "\0children") then
                if f["\0kind"] == "Button" and rawget(f, "_brd") and rawget(f, "_editHL") and f:IsVisible() then out[#out + 1] = f end
                for _, ch in ipairs(f["\0children"]) do stack[#stack + 1] = ch end
            end
        end
        return out
    end
    local function Order()
        local t = {}
        for _, b in ipairs(all.blocks) do t[#t + 1] = b.type end
        OUT:write("   order " .. table.concat(t, ",") .. "\n")
    end
    -- { segment, strip position to drop at }
    for n, drag in ipairs({ { 1, 600 }, { 6, 10 }, { 3, 0 }, { 2, 2 }, { 10, 300 } }) do
        Rebuild(all.id)
        local seg = Segments()[drag[1]]
        OUT:write("== drag " .. n .. " seg " .. tostring(seg ~= nil) .. "\n")
        if seg then
            cursorX, buttonDown = 100, true
            local ok, err = pcall(seg["\0scripts"].OnMouseDown, seg, "LeftButton")
            if not ok then OUT:write("   ERR " .. tostring(err) .. "\n") end
            cursorX = 100 + drag[2]
            HARNESS_TICK(0.02, 3)
            SNAP("drag " .. n .. " mid", CUI._contentHeader or CUI._headerFrame)
            buttonDown = false
            HARNESS_TICK(0.02, 3)
            HARNESS_ADVANCE(0.5)
            Order()
        end
    end
    GetCursorPosition = function() return 0, 0 end
end
