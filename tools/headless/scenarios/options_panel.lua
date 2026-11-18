-- The options window itself (CludesUI_Panel.lua): built and snapshotted;
-- every sidebar button hovered and left, every group header clicked twice
-- (collapse, expand); a few modules opened with each of their tabs; inline
-- search for a few queries, then cleared; the content scrolled; the panel
-- scale stepped up and back; every footer button hovered and left. The
-- window is snapshotted after each step.
local CUI = rawget(_G, "CludesUI")
if not (CUI and CUI._mainFrame) then
    CUI:SelectModule("CludesUIActionBars")
end
local main = CUI._mainFrame
if not main then
    OUT:write("== no panel\n")
    return
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
local function Fire(f, script, ...)
    local fn = f["\0scripts"] and f["\0scripts"][script]
    if not fn then return "none" end
    local ok, err = pcall(fn, f, ...)
    return ok and "ok" or ("ERR " .. tostring(err))
end

SNAP("panel", main)

-- Sidebar: buttons are the visible Buttons left of the content (x < 260).
local sidebar = Find(main, function(f)
    return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"] and f["\0scripts"].OnEnter ~= nil
        and f["\0scripts"].OnClick ~= nil
end)
OUT:write("== hoverable buttons " .. #sidebar .. "\n")
for i, b in ipairs(sidebar) do
    local r1 = Fire(b, "OnEnter")
    SNAP("hover " .. i, b)
    local r2 = Fire(b, "OnLeave")
    if r1 ~= "ok" or r2 ~= "ok" then OUT:write("== hover " .. i .. " " .. r1 .. " " .. r2 .. "\n") end
end

-- Modules and their tabs.
for _, mod in ipairs({ "CludesUIActionBars", "CludesUIMinimap", "CludesUIChat", "CludesUIFriends" }) do
    if CUI._ModuleNS and CUI._ModuleNS[mod] then
        local ok, err = pcall(CUI.SelectModule, CUI, mod)
        OUT:write("== module " .. mod .. " " .. tostring(ok) .. (ok and "" or (" " .. tostring(err))) .. "\n")
        local tabs = CUI._tabBar and CUI._tabBar._tabButtons or {}
        for t, tab in ipairs(tabs) do
            if tab:IsShown() then
                Fire(tab, "OnClick", "LeftButton")
                OUT:write("== " .. mod .. " tab " .. t .. " page " .. tostring(CUI:GetActivePage()) .. "\n")
            end
        end
        SNAP("module " .. mod .. " tabs", CUI._tabBar)
        if CUI._contentHeader then SNAP("module " .. mod .. " header", CUI._contentHeader) end
    end
end

-- Inline search.
for _, q in ipairs({ "scale", "border", "zzzz", "" }) do
    local ok, err = pcall(CUI.ApplyInlineSearch, CUI, q)
    OUT:write("== search '" .. q .. "' " .. tostring(ok) .. (ok and "" or (" " .. tostring(err))) .. "\n")
    HARNESS_ADVANCE(0.3)
    if q == "scale" then SNAP("search " .. q, CUI._scrollFrame) end
end

-- Scrolling.
local sf = CUI._scrollFrame
for _, d in ipairs({ -1, -1, -1, 1, 1, 1 }) do
    Fire(sf, "OnMouseWheel", d)
    HARNESS_ADVANCE(0.5)
    OUT:write("== scroll " .. d .. " -> " .. string.format("%.1f", CUI.GetContentScroll and CUI.GetContentScroll() or -1) .. "\n")
end
pcall(CUI.ScrollToTop, CUI)
HARNESS_ADVANCE(0.5)

-- Scale.
if CUI.StepPanelScale then
    for _, d in ipairs({ 1, 1, -1, -1 }) do
        local ok, err = pcall(CUI.StepPanelScale, CUI, d)
        HARNESS_ADVANCE(0.5)
        OUT:write("== scale " .. d .. " " .. tostring(ok) .. (ok and "" or (" " .. tostring(err))) .. " -> " .. string.format("%.3f", main:GetScale()) .. "\n")
    end
end

SNAP("panel after", main)
