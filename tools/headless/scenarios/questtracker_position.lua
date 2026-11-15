-- Quest Tracker > Position (retail, Blizzard's tracker): the Unlock Mode
-- element's callbacks against a stubbed Edit Mode layout store. Saves a
-- spot (CENTER becomes TOP), a height (rounded, clamped), a preset layout
-- (warns), an unlock session (waits, discard restores the height), a reset,
-- and prints the layout entry and every prompt after each step.
local CUI = rawget(_G, "CludesUI")
local mod = CUI._ModuleNS.CludesUIQuestTracker
local EQT = mod.EQT
local function Put(...)
    local t = { ... }
    for i = 1, select("#", ...) do t[i] = tostring(t[i]) end
    OUT:write("== ", table.concat(t, " "), "\n")
end
if mod.UseCustomTracker() then
    Put("custom tracker: position not used")
    return
end
Enum.EditModeSystem.ObjectiveTracker = 12
Enum.EditModeObjectiveTrackerSetting.Height = 0
local tracker = _G.ObjectiveTrackerFrame or CreateFrame("Frame", "ObjectiveTrackerFrame", UIParent)
_G.ObjectiveTrackerFrame = tracker
local inDefault, height = true, 800
tracker.IsInitialized = function() return true end
tracker.IsInDefaultPosition = function() return inDefault end
tracker.editModeHeight = height
tracker.Selection = tracker.Selection or CreateFrame("Frame", nil, tracker)
if not tracker.ApplySystemAnchor then tracker.ApplySystemAnchor = function() end end
local sys = { system = 12, isInDefaultPosition = true, settings = { { setting = 0, value = 40 } } }
local blob = { activeLayout = 3, layouts = { [3] = { systems = { sys } } } }
local presets = 2
CUI.EditModeLayoutsForSave = function() return blob, presets end
CUI.EditModeOpen = function() return false end
CUI.NoteEditModeAnchor = function() end
CUI.NoteEditModeSetting = function() end
CUI.SetEditModeChildInert = function(_, off) Put("selection inert", off) end
CUI.ReapplyUnlockAnchor = function(k) Put("reapply", k) end
EditModePresetLayoutManager = { GetDefaultSystemAnchorInfo = function() return { point = "TOPRIGHT", relativeTo = "UIParent", relativePoint = "TOPRIGHT", offsetX = -110, offsetY = -275 } end }
SAVES = 0
C_EditMode.SaveLayouts = function() SAVES = SAVES + 1 end
CUI.ShowConfirmPopup = function(_, o) Put("prompt", o.title) end
local element
local make = CUI.MakeUnlockElement
CUI.MakeUnlockElement = function(opts) if opts.key == "EQT_Tracker" then element = opts end return make(opts) end
local listener
local regL = CUI.RegisterUnlockModeListener
CUI.RegisterUnlockModeListener = function(self, k, fn) listener = fn return regL(self, k, fn) end
local function State(label)
    local a = sys.anchorInfo
    Put(label, "saves", SAVES, "default", sys.isInDefaultPosition, "anchor",
        a and (a.point .. "/" .. tostring(a.relativePoint) .. " " .. a.offsetX .. "," .. a.offsetY) or "-",
        "heightrow", sys.settings[1].value, "db", EQT.Cfg("position") and EQT.Cfg("position").point, EQT.Cfg("height"))
end
EQT.InitPosition()
State("start")
Put("key", element and element.key, element and element.label, element and element.order, element and element.noSpecLayout)
element.savePos(element, "CENTER", "CENTER", 100, -50)
State("saved center")
element.setHeight(element, 734)
State("height 734")
element.setHeight(element, 5000)
State("height 5000")
-- Edit Mode applied it after the reload.
inDefault, tracker.editModeHeight = false, 1000
EQT.SyncPosition()
State("after reload")
-- A preset layout.
blob.activeLayout = 1
blob.layouts[1] = { systems = { { system = 12, isInDefaultPosition = true, settings = {} } } }
element.savePos(element, "TOPLEFT", "TOPLEFT", 20, -30)
State("on preset")
blob.activeLayout = 3
-- An unlock session: changes wait; discard restores the height.
CUI._unlockActive = true
listener(true)
element.setHeight(element, 600)
element.savePos(element, "TOPLEFT", "TOPLEFT", 40, -60)
State("in session")
CUI._unlockActive = false
listener(false, "discard")
State("session discarded")
-- Reset.
element.clearPos(element)
State("reset")
Put("size", element.getSize(element))
Put("hidden", element.isHidden(element), "held", element.isPositionHeld(element))
