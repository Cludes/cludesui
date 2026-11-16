-- CludesUI.ShowPickMenu (CludesUI_Widgets): the shared pick-one menu opened
-- three ways (titled with icons and a disabled row; untitled and narrow;
-- a long list scrolling past a low maxHeight), each snapped with its click
-- catcher, every row hovered, a disabled and an enabled row clicked (the
-- picks written out), the long list wheeled, and the catcher clicked.
local CUI = rawget(_G, "CludesUI")
if not CUI.ShowPickMenu then
    OUT:write("== no ShowPickMenu\n")
    return
end
local cursorX, cursorY = 300, 400
GetCursorPosition = function() return cursorX, cursorY end
local anchor = CreateFrame("Button", nil, UIParent)
anchor:SetSize(40, 40)
local function Call(f, script, ...)
    local fn = f and f["\0scripts"] and f["\0scripts"][script]
    if not fn then return end
    local ok, err = pcall(fn, f, ...)
    if not ok then OUT:write("   ERR " .. script .. " " .. tostring(err) .. "\n") end
end
local function Open(label, opts)
    opts.onPick = function(key) OUT:write("   picked " .. tostring(key) .. "\n") end
    CUI.ShowPickMenu(anchor, opts)
    local menu = CUI._pickMenu
    OUT:write("== " .. label .. " shown " .. tostring(menu and menu:IsShown()) .. "\n")
    SNAP(label, menu)
    SNAP(label .. " catcher", menu._catcher)
    for i, row in ipairs(menu._rows) do
        if row:IsShown() then
            Call(row, "OnEnter")
            SNAP(label .. " row " .. i .. " hover", row)
            Call(row, "OnLeave")
        end
    end
    return menu
end

local m = Open("titled", {
    title = "Add To",
    items = {
        { key = "bar1", label = "Bar 1", icon = 134400 },
        { key = "bar2", label = "Bar 2", icon = 136243, disabled = true },
        { key = "bar3" },
        { key = 4, label = "Bar Four" },
    },
})
Call(m._rows[2], "OnClick", "LeftButton")
OUT:write("   after disabled click shown " .. tostring(m:IsShown()) .. "\n")
Call(m._rows[1], "OnClick", "LeftButton")
OUT:write("   after pick shown " .. tostring(m:IsShown()) .. " catcher " .. tostring(m._catcher:IsShown()) .. "\n")

m = Open("plain", { width = 180, fontPath = "Fonts\\ARIALN.TTF", items = { { key = "a", label = "Only" } } })
Call(m._catcher, "OnClick", "LeftButton")
OUT:write("   after catcher shown " .. tostring(m:IsShown()) .. "\n")

local many = {}
for i = 1, 30 do many[i] = { key = "k" .. i, label = "Entry " .. i, icon = (i % 3 == 0) and 134400 or nil, disabled = i % 7 == 0 } end
cursorX, cursorY = 900, 120
m = Open("long", { title = "Many", maxHeight = 100, items = many })
m._scroll.GetHeight = function() return 100 end
for _ = 1, 3 do Call(m._scroll, "OnMouseWheel", -1) end
OUT:write("   scroll " .. tostring(m._scroll:GetVerticalScroll()) .. "\n")
Call(m._scroll, "OnMouseWheel", 1)
OUT:write("   scroll " .. tostring(m._scroll:GetVerticalScroll()) .. "\n")
Call(m._rows[14], "OnClick", "LeftButton")
Call(m._rows[15], "OnClick", "LeftButton")
-- Reopened short: the extra rows hide.
m = Open("short again", { items = { { key = "x", label = "X" }, { key = "y", label = "Y", disabled = true } } })
local shown = 0
for _, row in ipairs(m._rows) do if row:IsShown() then shown = shown + 1 end end
OUT:write("   rows shown " .. shown .. " of " .. #m._rows .. "\n")
m:Hide()
