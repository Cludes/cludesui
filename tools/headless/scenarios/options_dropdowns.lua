-- Dropdown menus (CludesUI_Widgets' BuildDropdownMenu) on the Info Bar page
-- of a bar holding every block type: each dropdown opened and its menu
-- snapped; every row hovered and left (a flyout parent's flyout snapped and
-- its rows hovered); then, on a fresh build, the menu's second row (or the
-- first flyout row) clicked, with the bar's settings written out after.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIDataBars
BreakUpLargeNumbers = tostring
GetNetStats = function() return 0, 0, 42, 61 end
do
    local list = {
        { name = "Dungeon and Raid", isHeader = true, isHeaderExpanded = true },
        { name = "Valorstones", currencyID = 3008, iconFileID = 5868902, quantity = 1200 },
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
local bar = mod.CreateBar("empty")
for _, t in ipairs(mod.BLOCK_TYPES) do
    mod.AddBlock(bar.id, t.key)
end
local function Rebuild()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    mod.GetProfile().selectedBarId = bar.id
    CUI:SelectModule("CludesUIDataBars")
    CUI:SelectPage("Info Bar")
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
local function Dropdowns()
    return Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_invalidateMenu") ~= nil and f:IsVisible()
    end)
end
local function Rows(menu)
    return Find(menu, function(f)
        return f["\0kind"] == "Button" and rawget(f, "_key") ~= nil and f:IsVisible()
    end)
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
local function Settings()
    for i, b in ipairs(mod.GetBar(bar.id).blocks) do
        OUT:write("   block " .. i .. " " .. Dump(b, 0) .. "\n")
    end
end
local function Call(f, script, ...)
    local fn = f["\0scripts"][script]
    if not fn then return end
    local ok, err = pcall(fn, f, ...)
    if not ok then OUT:write("   ERR " .. script .. " " .. tostring(err) .. "\n") end
end
local function Open(dd)
    Call(dd, "OnClick", "LeftButton")
    HARNESS_ADVANCE(0.05)
    return rawget(dd, "_ddMenu")
end

-- One page: every dropdown opened and hovered; picks on every dropdown
-- (pickAll) or only those holding a flyout.
local function Page(label, rebuild, pickAll)
    rebuild()
    local count = #Dropdowns()
    OUT:write("== " .. label .. " dropdowns " .. count .. "\n")
    local withFlyout = {}
    for i = 1, count do
        local dd = Dropdowns()[i]
        local menu = dd and Open(dd)
        OUT:write("== " .. label .. " dropdown " .. i .. " menu " .. tostring(menu ~= nil) .. "\n")
        if menu then
            SNAP(label .. " menu " .. i, menu)
            for j, row in ipairs(Rows(menu)) do
                Call(row, "OnEnter")
                local fly = rawget(row, "_flyout")
                if fly then withFlyout[i] = true end
                if fly and fly:IsShown() then
                    SNAP(label .. " menu " .. i .. " row " .. j .. " flyout", fly)
                    for _, ci in ipairs(rawget(row, "_flyoutRows") or {}) do
                        Call(ci, "OnEnter")
                        Call(ci, "OnLeave")
                    end
                end
                Call(row, "OnLeave")
                HARNESS_ADVANCE(0.3)
            end
            SNAP(label .. " menu " .. i .. " after hover", menu)
            menu:Hide()
        end
    end
    for i = 1, count do
        if pickAll or withFlyout[i] then
            rebuild()
            local dd = Dropdowns()[i]
            local menu = dd and Open(dd)
            if menu then
                local rows = Rows(menu)
                local pick = rows[2] or rows[1]
                for _, row in ipairs(rows) do
                    if not pickAll and rawget(row, "_flyout") then pick = row end
                end
                if pick and rawget(pick, "_flyout") then
                    Call(pick, "OnEnter")
                    pick = (rawget(pick, "_flyoutRows") or {})[1]
                end
                if pick then
                    Call(pick, "OnClick", "LeftButton")
                    HARNESS_ADVANCE(0.1)
                    OUT:write("== " .. label .. " dropdown " .. i .. " picked " .. tostring(rawget(pick, "_key")) .. "\n")
                    if pickAll then Settings() end
                    -- The dropdown's own row (the page may have rebuilt: find it again).
                    local now = Dropdowns()[i]
                    if now and now:GetParent() then SNAP(label .. " after pick " .. i, now:GetParent()) end
                end
            end
        end
    end
end
Page("infobar", Rebuild, true)
Page("unitframes", function()
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    if CUI._setUnitFrameUnit then CUI._setUnitFrameUnit("player") end
    CUI:SelectModule("CludesUIUnitFrames")
    CUI:SelectPage("Main Frames")
end, false)
