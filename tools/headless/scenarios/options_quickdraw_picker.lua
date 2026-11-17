-- Action Wheel options page, the entry picker (CUI_Quickdraw_Options.lua):
-- opened from the preview's "+" entry, its root list snapped, then every
-- row of it clicked on a fresh open (each category view snapped), and in
-- each view the first entries clicked in turn, with the module's settings
-- written out after. Then the picker in replace mode (right-click on an
-- entry), a middle-click removal, and the Add Action Menu chooser's rows.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS and CUI._ModuleNS.CludesUIQuickdraw
if not (mod and mod.Profile) then
    OUT:write("== no quickdraw\n")
    return
end
GetCursorPosition = function() return 900, 500 end
GetCursorInfo = function() return nil end

local function Copy(v)
    if type(v) ~= "table" then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = Copy(x) end
    return out
end
local base
do
    local p = mod.Profile()
    p.enabled = true
    p.paletteCount = 2
    if mod.EnsurePalette then
        mod.EnsurePalette(1)
        mod.EnsurePalette(2)
    end
    p.palettes[1].slots = {
        { kind = "spell", id = 133 },
        { kind = "item", id = 6948 },
        { kind = "macro", name = "Hello", body = "/wave" },
    }
    p.palettes[2].slots = { { kind = "spell", id = 116 } }
    base = Copy(p)
end
local function Rebuild()
    local p = mod.Profile()
    for k in pairs(p) do p[k] = nil end
    for k, v in pairs(Copy(base)) do p[k] = v end
    CUI:SelectModule("CludesUIFriends")
    CUI:InvalidatePageCache()
    CUI:SelectModule("CludesUIQuickdraw")
    CUI:SelectPage("Action Wheel")
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
local function NewTops(before)
    local out = {}
    for _, host in ipairs(Hosts()) do
        for _, c in ipairs({ host:GetChildren() }) do
            if c:IsShown() and not before[c] then out[#out + 1] = c end
        end
    end
    return out
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
local function DumpProfile()
    OUT:write("   profile " .. Dump(mod.Profile(), 0) .. "\n")
end
local function Clickable(f)
    return f["\0kind"] == "Button" and f:IsVisible() and f["\0scripts"].OnClick ~= nil
end
local function Click(b, label, button)
    local ok, err = pcall(b["\0scripts"].OnClick, b, button or "LeftButton")
    OUT:write("== " .. label .. (ok and "" or (" ERR " .. tostring(err))) .. "\n")
    HARNESS_ADVANCE(0.1)
end
local function HideAll(tops)
    for _, c in ipairs(tops) do c:Hide() end
end
local function SlotWidgets()
    return Find(CUI._scrollFrame, function(f)
        return f["\0kind"] == "Button" and rawget(f, "index") ~= nil and f:IsVisible() and f["\0scripts"].OnClick ~= nil
    end)
end
local function Placeholder()
    for _, w in ipairs(SlotWidgets()) do
        if rawget(w, "isPlaceholder") then return w end
    end
end
-- Opens the picker on a fresh build: from the "+" (left click) or in
-- replace mode from entry 1 (right click). Returns the picker frame and
-- the tops shown before it.
local function OpenPicker(replace)
    Rebuild()
    local w = replace and SlotWidgets()[1] or Placeholder()
    if not w then return nil end
    local before = ShownTops()
    pcall(w["\0scripts"].OnClick, w, replace and "RightButton" or "LeftButton")
    HARNESS_ADVANCE(0.1)
    return NewTops(before)[1], before
end

for _, replace in ipairs({ false, true }) do
    local tag = replace and "replace" or "append"
    local picker, before = OpenPicker(replace)
    if not picker then
        OUT:write("== " .. tag .. " no picker\n")
    else
        SNAP(tag .. " picker root", picker)
        local nRoot = #Find(picker, Clickable)
        HideAll(NewTops(before))
        OUT:write("== " .. tag .. " root rows " .. nRoot .. "\n")
        for i = 1, nRoot do
            local pk, b4 = OpenPicker(replace)
            local row = pk and Find(pk, Clickable)[i]
            if row then
                Click(row, tag .. " root " .. i)
                SNAP(tag .. " view " .. i, pk)
                DumpProfile()
                local nView = math.min(#Find(pk, Clickable), 6)
                HideAll(NewTops(b4))
                for j = 1, nView do
                    local pk2, b5 = OpenPicker(replace)
                    local row2 = pk2 and Find(pk2, Clickable)[i]
                    if row2 then
                        pcall(row2["\0scripts"].OnClick, row2, "LeftButton")
                        HARNESS_ADVANCE(0.1)
                        local entry = Find(pk2, Clickable)[j]
                        if entry then
                            local b6 = ShownTops()
                            Click(entry, tag .. " view " .. i .. " entry " .. j)
                            if pk2:IsShown() then SNAP(tag .. " view " .. i .. " after entry " .. j, pk2) end
                            for k, c in ipairs(NewTops(b6)) do
                                SNAP(tag .. " view " .. i .. " entry " .. j .. " popup " .. k, c)
                            end
                            DumpProfile()
                        end
                    end
                    HideAll(NewTops(b5))
                end
            end
        end
    end
end

-- A middle-click removes the entry it lands on.
Rebuild()
local first = SlotWidgets()[1]
if first then
    Click(first, "middle click", "MiddleButton")
    DumpProfile()
end
