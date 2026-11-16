-- The dropdown menu's per-row options (CludesUI_Widgets' BuildDropdownMenu),
-- each on a dropdown built straight from CludesUI.Widgets:Dropdown on a test
-- frame: texture icons with colours and an icon tooltip, atlas icons on
-- clickable icon buttons (normal and native colours, a pressed atlas), label
-- colours, notes, an action row above a divider, row backgrounds (plain, a
-- layered base with a tint, tiled, a vertex colour), item height and text
-- width, hover callbacks, left- and right-anchored menus. For each:
-- the menu opened and snapped, every row and icon button hovered and left,
-- the icon buttons clicked, then every row (an action row among them)
-- clicked, with the value and the calls written out.
local CUI = rawget(_G, "CludesUI")
local W = CUI.Widgets
if not (W and W.Dropdown) then
    OUT:write("== no Widgets:Dropdown\n")
    return
end
local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(700, 600)
host:SetPoint("CENTER")
local function Log(text) OUT:write("   " .. text .. "\n") end
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
local function Call(f, script, ...)
    local fn = f and f["\0scripts"] and f["\0scripts"][script]
    if not fn then return end
    local ok, err = pcall(fn, f, ...)
    if not ok then Log("ERR " .. script .. " " .. tostring(err)) end
end

local cases = {}
local function Case(label, values, order)
    cases[#cases + 1] = { label = label, values = values, order = order }
end

Case("icons", {
    a = "Alpha", b = "Bravo", c = { text = "Charlie", note = "(old)" }, d = "Delta",
    _menuOpts = {
        icon = function(key)
            if key == "a" then return 134400 end
            if key == "b" then return "Interface\\Icons\\INV_Misc_QuestionMark", 0.1, 0.9, 0.1, 0.9 end
        end,
        iconSize = function(key) return key == "a" and 18 or nil end,
        iconColor = function(key) if key == "b" then return 1, 0.5, 0, 0.6 end end,
        iconInset = function(key) return key == "a" and 12 or nil end,
        iconWidth = function(key) return key == "b" and 30 or nil end,
        labelColor = function(key) if key == "d" then return 0.2, 0.8, 1 end end,
        onItemHover = function(key) Log("hover " .. tostring(key)) end,
        onItemLeave = function(key) Log("leave " .. tostring(key)) end,
    },
}, { "a", "b", "c", "d" })

Case("atlas buttons", {
    none = "None", s1 = "Sound One", s2 = "Sound Two", s3 = "Sound Three",
    _menuOpts = {
        itemHeight = 30,
        maxTextWidthPct = 0.7,
        iconAtlas = function(key) if key ~= "none" then return "common-icon-sound" end end,
        iconPressedAtlas = function(key) if key == "s1" then return "common-icon-sound-pressed" end end,
        iconColor = function(key) if key == "s2" then return 0.5, 1, 0.5, 0.8 end end,
        iconOnClick = function(key) Log("icon click " .. tostring(key)) end,
        iconTooltip = function(key) return "Preview " .. tostring(key) end,
    },
}, { "none", "s1", "s2", "s3" })

Case("native atlas, texture buttons", {
    x = "X-Ray", y = "Yankee", z = "Zulu",
    _menuOpts = {
        anchor = "RIGHT",
        iconNativeColor = true,
        iconAtlas = function(key) if key == "x" then return "common-icon-sound" end end,
        icon = function(key) if key == "y" then return 136243, 0, 1, 0, 1 end end,
        iconColor = function(key) if key == "y" then return 1, 1, 0, 0.5 end end,
        iconOnClick = function(key) Log("icon click " .. tostring(key)) end,
        labelFont = { "Fonts\\ARIALN.TTF", 14, "OUTLINE" },
    },
}, { "x", "y", "z" })

Case("backgrounds", {
    p = "Plain", l = "Layered", t = "Tiled", v = "Vertex", e = { text = "Edit Textures...", action = function() Log("action ran") end },
    ["---1"] = "",
    _menuOpts = {
        anchor = "LEFT",
        background = function(key)
            if key == "p" then return "Interface\\Buttons\\WHITE8x8" end
            if key == "l" then return "Interface\\Buttons\\WHITE8x8", { base = { 0.2, 0.3, 0.4 }, tint = { 1, 0, 0 } } end
            if key == "t" then return "Interface\\Buttons\\WHITE8x8", { tile = true } end
            if key == "v" then return "Interface\\Buttons\\WHITE8x8" end
        end,
        backgroundVertexColor = function() return 0.3, 0.6, 0.9 end,
    },
}, { "e", "---1", "p", "l", "t", "v" })

for _, c in ipairs(cases) do
    local value = c.order[#c.order]
    local row = W:Dropdown(host, c.label, -20, c.values, function() return value end, function(v)
        value = v
        Log("set " .. tostring(v))
    end, c.order)
    local dd = Find(row, function(f) return f["\0kind"] == "Button" and rawget(f, "_invalidateMenu") ~= nil end)[1]
    OUT:write("== " .. c.label .. " dropdown " .. tostring(dd ~= nil) .. "\n")
    if dd then
        Call(dd, "OnClick", "LeftButton")
        HARNESS_ADVANCE(0.05)
        local menu = rawget(dd, "_ddMenu")
        OUT:write("== " .. c.label .. " menu " .. tostring(menu ~= nil) .. "\n")
        if menu then
            SNAP(c.label .. " menu", menu)
            local rows = Find(menu, function(f) return f["\0kind"] == "Button" and rawget(f, "_key") ~= nil end)
            for i, r in ipairs(rows) do
                Call(r, "OnEnter")
                SNAP(c.label .. " row " .. i .. " lit", r)
                Call(r, "OnLeave")
                local ib = rawget(r, "_icon")
                if ib and ib["\0kind"] == "Button" then
                    Call(ib, "OnEnter")
                    SNAP(c.label .. " row " .. i .. " icon lit", ib)
                    Call(ib, "OnLeave")
                    Call(ib, "OnClick", "LeftButton")
                end
            end
            SNAP(c.label .. " menu after hover", menu)
            for _, r in ipairs(rows) do
                if not menu:IsShown() then
                    Call(dd, "OnClick", "LeftButton")
                    HARNESS_ADVANCE(0.05)
                end
                Call(r, "OnClick", "LeftButton")
                HARNESS_ADVANCE(0.05)
                Log("clicked " .. tostring(rawget(r, "_key")) .. " value " .. tostring(value) .. " shown " .. tostring(menu:IsShown()))
            end
            if menu:IsShown() then menu:Hide() end
        end
        SNAP(c.label .. " row after", row)
    end
end
