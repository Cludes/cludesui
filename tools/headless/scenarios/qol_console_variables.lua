-- QoL Console Variables (CludesUIQoL_ConsoleVariables.lua): the window's
-- Changed / All / Pinned tabs and search, setting and resetting a value,
-- a locked variable never listed, pins, export and import (only what
-- changes, machine-only names left out), Put Back Pinned at Login; and
-- Hide Zone Text (CludesUIQoL.lua).
local CUI = rawget(_G, "CludesUI")
OUT:write("== open " .. tostring(CUI.OpenConsoleVariables ~= nil) .. "\n")
if not CUI.OpenConsoleVariables then return end

local store = {
    cameraDistanceMaxZoomFactor = { "2.6", "1.9" },
    nameplateMaxDistance = { "41", "41" },
    autoLootDefault = { "1", "0" },
    gxAdapter = { "NVIDIA", "" },
    lockedThing = { "5", "5", locked = true },
    Sound_EnableMusic = { "1", "1" },
}
ConsoleGetAllCommands = function()
    local list = {}
    for name in pairs(store) do
        list[#list + 1] = { command = name, commandType = Enum.ConsoleCommandType.Cvar, help = "Help for " .. name }
    end
    list[#list + 1] = { command = "reloadui", commandType = Enum.ConsoleCommandType.Cvar + 1 }
    return list
end
C_CVar.GetCVarInfo = function(name)
    local e = store[name]
    if not e then return nil end
    return e[1], e[2], false, false, e.locked or false, false, false
end
C_CVar.SetCVar = function(name, value)
    local e = store[name]
    if not e or e.locked then return false end
    e[1] = tostring(value)
    return true
end
local copied, importFn
CUI.ShowInputPopup = function(_, o) o.onConfirm(o._answer or "3.4") end
CUI.ShowConfirmPopup = function(_, o) OUT:write("== confirm: " .. tostring(o.message):gsub("\n", " / ") .. "\n") o.onConfirm() end
CUI.ShowCopyPopup = function(_, title, _, text) copied = text OUT:write("== copy " .. title .. "\n") end
CUI.ShowImportPopup = function(_, fn) importFn = fn end

CUI.OpenConsoleVariables()
local win = _G.CludesUIConsoleVariables
-- The list's content frame: the scroll frame's one child.
local function Content()
    for _, ch in ipairs({ win:GetChildren() }) do
        if ch:GetObjectType() == "ScrollFrame" then return (ch:GetChildren()) end
    end
end
local function Rows(tag)
    local list = {}
    for _, r in ipairs({ Content():GetChildren() }) do
        if r:IsShown() and r.cvar then
            list[#list + 1] = r.cvar .. "=" .. r.valueText:GetText() .. "(" .. r.defaultText:GetText() .. ")"
                .. (r.reset:IsShown() and " R" or "") .. (r.pin:GetText() == "Pinned" and " P" or "")
        end
    end
    OUT:write("== " .. tag .. ": " .. table.concat(list, ", ") .. "\n")
end
local function Tab(key)
    for _, ch in ipairs({ win:GetChildren() }) do
        if ch.key == key then ch:GetScript("OnClick")(ch) end
    end
end
local function Find(name)
    for _, r in ipairs({ Content():GetChildren() }) do
        if r:IsShown() and r.cvar == name then return r end
    end
end

Rows("changed (default tab)")
Tab("all")
Rows("all")
local searchBox
for _, ch in ipairs({ win:GetChildren() }) do
    if ch:GetObjectType() == "EditBox" then searchBox = ch end
end
searchBox:SetText("name")
searchBox:GetScript("OnTextChanged")(searchBox)
Rows("search name")
searchBox:SetText("")
searchBox:GetScript("OnTextChanged")(searchBox)

-- Set a value (the input popup answers 3.4), then reset it.
local row = Find("cameraDistanceMaxZoomFactor")
row:GetScript("OnClick")(row)
Rows("zoom set to 3.4")
row = Find("cameraDistanceMaxZoomFactor")
row.reset:GetScript("OnClick")(row.reset)
Rows("zoom reset")

-- Pin autoLootDefault, see the Pinned tab.
row = Find("autoLootDefault")
row.pin:GetScript("OnClick")(row.pin)
Tab("pinned")
Rows("pinned")

-- Export the Changed tab: gxAdapter (machine-only) is left out.
Tab("changed")
for _, ch in ipairs({ win:GetChildren() }) do
    if ch.label and ch:GetText() == "Export" then ch:GetScript("OnClick")(ch) end
end
OUT:write("== exported: " .. tostring(copied):gsub("\n", " | ") .. "\n")

-- Import: one change, one unchanged, one unknown, one locked.
for _, ch in ipairs({ win:GetChildren() }) do
    if ch.label and ch:GetText() == "Import" then ch:GetScript("OnClick")(ch) end
end
importFn("nameplateMaxDistance=60\nautoLootDefault=1\nnoSuchCVar=3\nlockedThing=9")
Rows("after import")

-- Put Back Pinned at Login.
store.autoLootDefault[1] = "0"
CludesUIDB.cvarPinsOn = true
CUI._ConsoleVariablesPutBack()
OUT:write("== put back autoLootDefault=" .. store.autoLootDefault[1] .. "\n")

-- Hide Zone Text.
CludesUIDB.hideZoneText = true
CUI._applyHideZoneText()
ZoneTextFrame:Hide()
ZoneTextFrame:Show()
OUT:write("== zone text shown after Show: " .. tostring(ZoneTextFrame:IsShown()) .. "\n")
CludesUIDB.hideZoneText = false
ZoneTextFrame:Show()
OUT:write("== zone text shown with the option off: " .. tostring(ZoneTextFrame:IsShown()) .. "\n")
