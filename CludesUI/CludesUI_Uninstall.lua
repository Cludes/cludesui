if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Uninstall.lua
--  The game settings CludesUI changes that outlive it, and what puts them
--  back: the login pass that puts back the CVars of a module turned off, and
--  the Uninstall CUI action (Global Settings > General) for everything.
--
--  Every such change goes through the setters here: CVars (whole values and
--  single bits), Edit Mode layout settings, chat window font sizes and the
--  keys CludesUI takes for its own commands. The first change of a setting
--  records the value it had before (its snapshot); every change records the
--  value CludesUI left. A setting goes back only while it still holds
--  CludesUI's value: one the player changed since is theirs and stays.
--
--  A CVar writer names its module (owner: the addon folder; nil for the
--  parent). At login the CVars of a module that did not load go back and their
--  records are dropped, so its first writes once it is back record the values
--  found then: this character's own CVars when the module is off for this
--  character, the CVars every character shares only once it is off for all of
--  them (or gone). Uninstall puts back everything, drops what it put back,
--  runs the steps modules registered with OnUninstall, turns CludesUI off
--  for every character and reloads.
--
--  A CVar CludesUI only borrows (a sort's muted sound, chat bubbles in an
--  instance, friendly plates in a follower dungeon) goes through HoldCVar and
--  ReleaseCVar: once the release puts back the value from before the hold, the
--  record goes back as it was then, so the value the player gets back is never
--  mistaken for one of CludesUI's.
--
--  The settings Optimize My FPS and Graphics changes stay out of all of this:
--  it keeps its own backup (gfxBackup), which its card restores.
--
--  Snapshots are kept only on an account that started on this build or later,
--  or since Uninstall CUI ran (fresh), and only for the Edit Mode layouts
--  there were at CludesUI's first Edit Mode note (a layout made or renamed
--  since may be a copy of one it had changed). Elsewhere CludesUI may have
--  changed a setting before its first record here, so Uninstall puts a CVar
--  back to the game's default and an Edit Mode setting to the fallback its
--  writer named (or leaves it), and a module turned off leaves its CVars as
--  they are, their records kept for Uninstall while they still hold
--  CludesUI's values. Fresh is judged from the saved data alone: a value
--  CludesUI set before its saved data was deleted reads as the player's own.
--
--  Record: CludesUIDB.restoreOnUninstall (never exported or imported, kept
--  by Reset ALL Settings)
--    fresh    snapshots are kept
--    cvar     [lowercase name] = { b = before, a = CludesUI's last value, o = owner }
--    held     [lowercase name] = { e = the cvar entry before the hold (false: none),
--             v = the value then, o = owner }
--    bits     [lowercase name] = { [bit index] = { b, a, o } }
--    em       [layout name] = { [system * 1000 + index] = { [setting] =
--             { b, a, f = fallback, p = the setting it goes back with },
--             anchor = { b, a } } } (b: a position, { i = anchorInfo,
--             i2 = anchorInfo2, d = isInDefaultPosition }; a = CludesUI's
--             anchorInfo)
--    emKnown  [layout name] = true: the layouts there were at CludesUI's
--             first Edit Mode note (listed on a fresh account only)
--    bind     [key] = the action it had before CludesUI took it (false: none)
--    chars    [player GUID] = the same for per-character state: cvar, held, bits,
--             em and emKnown (Character layouts), bind (character binding set)
--             and chatFont = { [window] = { b, a } }
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local KEY = "restoreOnUninstall"
-- A standalone build is one addon: no part of it can be off while it runs
-- (the Lite lifecycle's folder-name test, which the build never renames).
local IS_STANDALONE = ADDON_NAME:find("Standalone") ~= nil
local _fresh -- nil until this addon's saved data has loaded
local _uninstalled -- set once Uninstall ran: nothing re-applies before the reload
local _putBack = {} -- lowercase CVar names written back this session

-- The account started fresh: no saved data, or no profile holding any
-- module's settings yet (the first-install picker's own test).
local function IsFreshAccount(saved)
    if type(saved) ~= "table" then
        return true
    end
    if type(saved.profiles) == "table" then
        for _, prof in pairs(saved.profiles) do
            if type(prof) == "table" and type(prof.addons) == "table" and next(prof.addons) then
                return false
            end
        end
    end
    return true
end

local function Record()
    local saved = CludesUIDB
    if type(saved) ~= "table" then
        saved = {}
        CludesUIDB = saved
    end
    local r = saved[KEY]
    if type(r) ~= "table" then
        r = { fresh = _fresh or nil }
        saved[KEY] = r
    end
    return r
end

-- This character's part of the record (nil while its GUID is unknown, and
-- with peek while it holds nothing).
local function CharRecord(peek)
    local unitGuid = UnitGUID("player")
    if not unitGuid then
        return nil
    end
    local r = Record()
    local chars = r.chars
    if not chars then
        if peek then
            return nil
        end
        chars = {}
        r.chars = chars
    end
    local c = chars[unitGuid]
    if not c and not peek then
        c = {}
        chars[unitGuid] = c
    end
    return c
end

local function Sub(t, key)
    local s = t[key]
    if not s then
        s = {}
        t[key] = s
    end
    return s
end

local CheckModules -- the login pass, below

CludesUI.Lite.OnSavedVariablesLoaded(function()
    local r = type(CludesUIDB) == "table" and CludesUIDB[KEY]
    if type(r) == "table" then
        _fresh = r.fresh == true
    else
        -- A standalone may have built the store before any saved data loaded:
        -- when no saved data replaced it, that is a fresh account too.
        _fresh = CludesUI.Lite.StoreFromBeforeLoad() or IsFreshAccount(CludesUIDB)
    end
    -- The record is written at login, so a fresh account keeps its mark even
    -- when this session changes nothing.
    local f = CreateFrame("Frame")
    f:RegisterEvent("PLAYER_LOGIN")
    f:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        Record()
        if IS_STANDALONE then
            return
        end
        -- After a reload in combat the module pass waits for it to end: some
        -- CVars cannot change in combat.
        if InCombatLockdown() then
            CludesUI.CombatQueue.Defer("UninstallModulePass", CheckModules)
            return
        end
        CheckModules()
    end)
end)

-------------------------------------------------------------------------------
--  CVars
-------------------------------------------------------------------------------
local GetCVar, GetCVarBitfield = C_CVar.GetCVar, C_CVar.GetCVarBitfield

-- The part of the record a CVar belongs to: this character's for a
-- per-character one (nil while the character is unknown).
local function CVarRoot(name)
    local _, _, _, perChar = C_CVar.GetCVarInfo(name)
    if perChar then
        return CharRecord()
    end
    return Record()
end

-- What the game's own SetCVar passes on: true/false as "1"/"0", the rest as text.
local function CVarString(value)
    if type(value) == "boolean" then
        return value and "1" or "0"
    end
    if value ~= nil then
        return tostring(value)
    end
    return nil
end

-- Keyed in lower case: CVar names are case-insensitive, and CludesUI
-- spells some two ways.
local function Note(name, before, ownerFrame)
    -- Nothing to record into before this addon's saved data loads, and an
    -- unknown CVar is nothing to put back.
    if _fresh == nil or before == nil then
        return
    end
    local root = CVarRoot(name)
    if not root then
        return
    end
    local t = Sub(root, "cvar")
    local key = name:lower()
    local e = t[key]
    if not e then
        e = {}
        t[key] = e
        if Record().fresh then
            e.b = before
        end
    end
    e.a = GetCVar(name)
    e.o = ownerFrame
end

--- SetCVar for every value CludesUI sets on its own. owner is the module
--- that sets it (its addon folder name, also from its options page; nil for
--- the parent): turning that module off puts the value back.
function CludesUI.SetCVar(name, value, ownerFrame)
    if _uninstalled then
        return false
    end
    local before = GetCVar(name)
    local success = C_CVar.SetCVar(name, CVarString(value))
    -- A refused write (a locked or protected CVar) changed nothing.
    if success then
        Note(name, before, ownerFrame)
    end
    return success
end

--- For a CVar CludesUI holds only for a while: SetCVar, keeping what the
--- record held before, which ReleaseCVar puts back.
function CludesUI.HoldCVar(name, value, ownerFrame)
    if _uninstalled then
        return false
    end
    local current = GetCVar(name)
    local root = _fresh ~= nil and current ~= nil and CVarRoot(name)
    local key = name:lower()
    local snap
    if root and not (root.held and root.held[key]) then
        local e = root.cvar and root.cvar[key]
        snap = { e = e and { b = e.b, a = e.a, o = e.o } or false, v = current, o = ownerFrame }
    end
    local success = CludesUI.SetCVar(name, value, ownerFrame)
    if success and snap then
        Sub(root, "held")[key] = snap
    end
    return success
end

--- Ends a hold: writes value (what the CVar was when the hold began; nil
--- writes nothing). Once the CVar is back at the value from before the hold,
--- the record goes back as it was then. owner is the module, as for HoldCVar.
function CludesUI.ReleaseCVar(name, value, ownerFrame)
    local key = name:lower()
    -- After Uninstall the record is final, and what Uninstall put back stays.
    if _uninstalled then
        if value == nil or _putBack[key] then
            return false
        end
        return C_CVar.SetCVar(name, CVarString(value))
    end
    local prior = GetCVar(name)
    local success
    if value ~= nil then
        success = C_CVar.SetCVar(name, CVarString(value))
        -- Refused: the hold stands (Uninstall or the module pass releases it).
        if not success then
            return success
        end
    end
    local current = GetCVar(name)
    if _fresh == nil or current == nil then
        return success
    end
    local root = CVarRoot(name)
    if not root then
        return success
    end
    local hgt = root.held and root.held[key]
    if hgt and current == hgt.v then
        root.held[key] = nil
        if hgt.e then
            Sub(root, "cvar")[key] = hgt.e
        elseif root.cvar then
            root.cvar[key] = nil
        end
    else
        local e = root.cvar and root.cvar[key]
        if e then
            -- Anything else is still CludesUI's doing (a module that lost
            -- track of the value it borrowed): the hold stands, with this as
            -- its value.
            e.a = current
        elseif not hgt and prior ~= current then
            -- A hand-back with no hold on file (one another character left,
            -- or one the module pass already ended) is a change of its own.
            Note(name, prior, ownerFrame)
        end
    end
    return success
end

--- SetCVarBitfield likewise. Recorded per bit, so only the bits CludesUI
--- set go back, never one the game set since.
function CludesUI.SetCVarBitfield(name, index, value, ownerFrame)
    if _uninstalled then
        return false
    end
    local before = GetCVarBitfield(name, index)
    local success = C_CVar.SetCVarBitfield(name, index, value)
    local root = success and _fresh ~= nil and before ~= nil and CVarRoot(name)
    if root then
        local t = Sub(Sub(root, "bits"), name:lower())
        local e = t[index]
        if not e then
            e = {}
            t[index] = e
            if Record().fresh then
                e.b = before
            end
        end
        e.a = GetCVarBitfield(name, index)
        e.o = ownerFrame
    end
    return success
end

-- A hold its module never ended (a reload in the middle of it, or the module
-- turned off since): the value from before the hold goes back while the CVar
-- still holds CludesUI's, and the record goes back as the release leaves it.
local function ReleaseHold(root, key, hgt)
    local e = root.cvar and root.cvar[key]
    if hgt.v ~= nil and e and GetCVar(key) == e.a then
        pcall(C_CVar.SetCVar, key, hgt.v)
        _putBack[key] = true
    end
    if hgt.e then
        Sub(root, "cvar")[key] = hgt.e
    elseif root.cvar then
        root.cvar[key] = nil
    end
    root.held[key] = nil
end

local function ReleaseHolds(root)
    local held = root and root.held
    if not held then
        return
    end
    for key, hgt in pairs(held) do
        ReleaseHold(root, key, hgt)
    end
end

--- The player changed a CVar while owner held it: the hold ends with no write,
--- and the record goes back as it was before the hold, so neither Uninstall
--- nor a later login puts the held value back over the player's.
function CludesUI.DropHold(name, ownerFrame)
    if _fresh == nil then
        return
    end
    local root = CVarRoot(name)
    local key = name:lower()
    local hgt = root and root.held and root.held[key]
    if not (hgt and hgt.o == ownerFrame) then
        return
    end
    root.held[key] = nil
    if hgt.e then
        Sub(root, "cvar")[key] = hgt.e
    elseif root.cvar then
        root.cvar[key] = nil
    end
end

--- A hold owner left open in an earlier session (a reload in the middle of
--- it), for owner to call at login, when it cannot still be running: put back
--- as the module pass does, the value from before the hold only while the CVar
--- still reads CludesUI's.
function CludesUI.ReleaseStaleHold(name, ownerFrame)
    if _uninstalled or _fresh == nil then
        return
    end
    local root = CVarRoot(name)
    local key = name:lower()
    local hgt = root and root.held and root.held[key]
    if hgt and hgt.o == ownerFrame then
        ReleaseHold(root, key, hgt)
    end
end

-- Puts back every recorded CVar that still holds CludesUI's value: to its
-- snapshot, else the game's default.
local function RestoreCVars(t)
    if not t then
        return
    end
    for name, entry in pairs(t) do
        local current = GetCVar(name)
        if current ~= nil and current == entry.a then
            local wanted = entry.b or C_CVar.GetCVarDefault(name)
            if wanted ~= nil and wanted ~= current then
                pcall(C_CVar.SetCVar, name, wanted)
                _putBack[name] = true
            end
        end
    end
end

-- A bitfield CVar is a version character followed by characters carrying six
-- bits each (the game's own reader, CVarCallbackRegistry:GetCVarBitfieldIndex):
-- the bit of index in the CVar's default.
local function DefaultBit(name, index)
    local def = C_CVar.GetCVarDefault(name)
    if type(def) ~= "string" then
        return nil
    end
    local idx = index - 1
    local byte = def:byte(2 + math.floor(idx / 6))
    if not byte then
        return false
    end
    return math.floor(byte / 2 ^ (idx % 6)) % 2 == 1
end

local function RestoreBits(t)
    if not t then
        return
    end
    for name, bits in pairs(t) do
        for index, entry in pairs(bits) do
            local current = GetCVarBitfield(name, index)
            if current ~= nil and current == entry.a then
                local wanted = entry.b
                if wanted == nil then
                    wanted = DefaultBit(name, index)
                end
                if wanted ~= nil and wanted ~= current then
                    pcall(C_CVar.SetCVarBitfield, name, index, wanted)
                end
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Modules turned off
-------------------------------------------------------------------------------

-- The module that owns a record is off: it did not load this session and,
-- for a record of the account's (acct), which every character shares, it is
-- off for every character too, or gone.
local function ModuleOff(ownerFrame, acct)
    if ownerFrame == nil or ownerFrame == ADDON_NAME or C_AddOns.IsAddOnLoaded(ownerFrame) then
        return false
    end
    return not acct
        or not C_AddOns.DoesAddOnExist(ownerFrame)
        or C_AddOns.GetAddOnEnableState(ownerFrame) == Enum.AddOnEnableState.None
end

-- One part of the record (the account's, acct, or this character's): each
-- record of a module that is off goes back to its snapshot while it still
-- holds CludesUI's value, and is dropped. One with no snapshot stays while
-- the CVar holds CludesUI's value, so Uninstall can still put it back to
-- the game's default. A hold such a module left open is released.
local function RevertOffModules(root, acct)
    if not root then
        return
    end
    local held = root.held
    if held then
        for key, hgt in pairs(held) do
            if ModuleOff(hgt.o) then
                ReleaseHold(root, key, hgt)
            end
        end
        if next(held) == nil then
            root.held = nil
        end
    end
    local t = root.cvar
    if t then
        for key, entry in pairs(t) do
            if ModuleOff(entry.o, acct) then
                local current = GetCVar(key)
                if entry.b ~= nil and entry.b ~= entry.a and current == entry.a then
                    pcall(C_CVar.SetCVar, key, entry.b)
                    _putBack[key] = true
                end
                if entry.b ~= nil or current ~= entry.a then
                    t[key] = nil
                end
            end
        end
        if next(t) == nil then
            root.cvar = nil
        end
    end
    local bits = root.bits
    if bits then
        for name, byIndex in pairs(bits) do
            for index, entry in pairs(byIndex) do
                if ModuleOff(entry.o, acct) then
                    local current = GetCVarBitfield(name, index)
                    if entry.b ~= nil and entry.b ~= entry.a and current == entry.a then
                        pcall(C_CVar.SetCVarBitfield, name, index, entry.b)
                    end
                    if entry.b ~= nil or current ~= entry.a then
                        byIndex[index] = nil
                    end
                end
            end
            if next(byIndex) == nil then
                bits[name] = nil
            end
        end
        if next(bits) == nil then
            root.bits = nil
        end
    end
end

-- At login (out of combat): the parent, which loads whenever any module does,
-- puts back what a module that is off left behind.
CheckModules = function()
    RevertOffModules(Record(), true)
    local c = CharRecord(true)
    if not c then
        return
    end
    RevertOffModules(c, false)
    if next(c) == nil then
        Record().chars[UnitGUID("player")] = nil
    end
end

-------------------------------------------------------------------------------
--  Edit Mode layouts
-------------------------------------------------------------------------------
local CHAR_LAYOUT = Enum and Enum.EditModeLayoutType and Enum.EditModeLayoutType.Character

--- Blizzard's Edit Mode is open: it saves its own copy of the layouts on
--- exit, over anything written meanwhile.
function CludesUI.EditModeOpen()
    local emf = _G.EditModeManagerFrame
    if not emf then
        return false
    end
    return (emf.editModeActive or (emf.IsShown and emf:IsShown())) and true or false
end
local EditModeOpen = CludesUI.EditModeOpen

--- The saved layouts with the presets first, as SaveLayouts takes them: it
--- replaces the whole set, and activeLayout indexes that merged list, while
--- C_EditMode.GetLayouts returns only the saved half. Returns the layout info
--- and the number of presets, or nil when that cannot be built (never save a
--- short list).
function CludesUI.EditModeLayoutsForSave()
    local success, details = pcall(C_EditMode.GetLayouts)
    if not success or type(details) ~= "table" or type(details.layouts) ~= "table" then
        return nil
    end
    local mgr = EditModePresetLayoutManager
    local presets = mgr and mgr.GetCopyOfPresetLayouts and mgr:GetCopyOfPresetLayouts()
    if type(presets) ~= "table" or #presets == 0 then
        return nil
    end
    local numPresets = #presets
    for idx = 1, #details.layouts do
        presets[numPresets + idx] = details.layouts[idx]
    end
    details.layouts = presets
    return details, numPresets
end
local LayoutsForSave = CludesUI.EditModeLayoutsForSave

-- On a fresh account, the layouts there are when CludesUI first notes one:
-- listed once for the account, and once for each character (its own
-- Character layouts) at its first note, which the Action Bars sync makes at
-- every login.
local function ListLayouts(acct, mine)
    local newA, newM = not acct.emKnown, mine ~= nil and not mine.emKnown
    if not (newA or newM) then
        return
    end
    local success, details = pcall(C_EditMode.GetLayouts)
    if not success or type(details) ~= "table" or type(details.layouts) ~= "table" then
        return
    end
    local a, m = newA and {} or nil, newM and {} or nil
    for _, layout in ipairs(details.layouts) do
        if type(layout) == "table" and type(layout.layoutName) == "string" then
            if layout.layoutType == CHAR_LAYOUT then
                if m then
                    m[layout.layoutName] = true
                end
            elseif a then
                a[layout.layoutName] = true
            end
        end
    end
    if a then
        acct.emKnown = a
    end
    if m then
        mine.emKnown = m
    end
end

-- The record of key (a setting, or "anchor") of sysInfo in layout, made on
-- the first note with the value from before (fresh, a layout there was at
-- the first note) or else fallback. nil while the character is unknown.
local function EditModeEntry(layout, sysInfo, key, before, fallback)
    local r = Record()
    local isChar = layout.layoutType == CHAR_LAYOUT
    local mine
    if r.fresh or isChar then
        mine = CharRecord()
    end
    if r.fresh then
        ListLayouts(r, mine)
    end
    local root
    if isChar then
        root = mine
    else
        root = r
    end
    if not root then
        return nil
    end
    local t = Sub(Sub(Sub(root, "em"), layout.layoutName), sysInfo.system * 1000 + (sysInfo.systemIndex or 0))
    local e = t[key]
    if not e then
        e = {}
        t[key] = e
        local known = root.emKnown
        if r.fresh and (known == nil or known[layout.layoutName]) then
            e.b = before
        else
            e.f = fallback
        end
    end
    return e
end

--- Before CludesUI writes value into setting of sysInfo (a system entry of
--- layout, a saved layout from C_EditMode.GetLayouts): records the row's
--- value then (before) and value. fallback is what Uninstall puts back when
--- the value from before CludesUI is unknown (an older account, or a
--- layout made or renamed since CludesUI first changed one, which may be a
--- copy of one it had changed); nil leaves that row as it is. pair names a
--- setting that only means something together with this one (a size's
--- hundreds and the rest): the two go back together or not at all.
function CludesUI.NoteEditModeSetting(layout, sysInfo, setting, before, value, fallback, pair)
    if _fresh == nil or before == nil then
        return
    end
    if type(layout) ~= "table" or type(layout.layoutName) ~= "string" then
        return
    end
    local e = EditModeEntry(layout, sysInfo, setting, before, fallback)
    if not e then
        return
    end
    e.a = value
    e.p = pair
end

local function AnchorCopy(details)
    if type(details) ~= "table" then
        return nil
    end
    return {
        point = details.point,
        relativeTo = details.relativeTo,
        relativePoint = details.relativePoint,
        offsetX = details.offsetX,
        offsetY = details.offsetY,
    }
end

-- A system's position: its anchors and whether Edit Mode counts it as the
-- default one.
local function Position(sys)
    return {
        i = AnchorCopy(sys.anchorInfo),
        i2 = AnchorCopy(sys.anchorInfo2),
        d = sys.isInDefaultPosition == true,
    }
end

--- Before CludesUI moves sysInfo (a system entry of layout, as for
--- NoteEditModeSetting) to anchor, its only anchor from then on: records the
--- system's position then and anchor. Where the position from before is
--- unknown, Uninstall leaves the system where it is.
function CludesUI.NoteEditModeAnchor(layout, sysInfo, anchor)
    if _fresh == nil or type(anchor) ~= "table" then
        return
    end
    if type(sysInfo) ~= "table" or type(sysInfo.anchorInfo) ~= "table" then
        return
    end
    if type(layout) ~= "table" or type(layout.layoutName) ~= "string" then
        return
    end
    local e = EditModeEntry(layout, sysInfo, "anchor", Position(sysInfo))
    if not e then
        return
    end
    e.a = AnchorCopy(anchor)
end

-- The rows of one system that go back, as row -> value (nil: none).
local function SystemRestores(sys, bySys)
    local rowList = {}
    for _, row in ipairs(sys.settings) do
        rowList[row.setting] = row
    end
    local function Ours(setting)
        local e, row = bySys[setting], rowList[setting]
        return e ~= nil and row ~= nil and row.value == e.a
    end
    local result
    for setting, entry in pairs(bySys) do
        if Ours(setting) and (entry.p == nil or Ours(entry.p)) then
            local wanted = entry.b
            if wanted == nil then
                wanted = entry.f
            end
            if wanted ~= nil and wanted ~= rowList[setting].value then
                result = result or {}
                result[rowList[setting]] = wanted
            end
        end
    end
    return result
end

-- Within Edit Mode's own tolerance for anchors (0.1).
local function SameAnchor(a, b)
    return type(a) == "table"
        and type(b) == "table"
        and a.point == b.point
        and a.relativeTo == b.relativeTo
        and a.relativePoint == b.relativePoint
        and type(a.offsetX) == "number"
        and type(b.offsetX) == "number"
        and type(a.offsetY) == "number"
        and type(b.offsetY) == "number"
        and math.abs(a.offsetX - b.offsetX) < 0.1
        and math.abs(a.offsetY - b.offsetY) < 0.1
end

-- Puts the system's position back while it is still CludesUI's (its only
-- anchor); true when it changed.
local function RestoreAnchor(sys, e)
    if type(e) ~= "table" or sys.anchorInfo2 ~= nil or not SameAnchor(sys.anchorInfo, e.a) then
        return false
    end
    local wanted = e.b
    if type(wanted) ~= "table" or not wanted.i then
        return false
    end
    if wanted.i2 == nil and SameAnchor(sys.anchorInfo, wanted.i) then
        return false
    end
    sys.anchorInfo = AnchorCopy(wanted.i)
    sys.anchorInfo2 = AnchorCopy(wanted.i2)
    sys.isInDefaultPosition = wanted.d == true
    return true
end

-- True once the layouts were gone through (false: they could not be read).
local function RestoreEditMode(acct, mine)
    if not (acct or mine) then
        return true
    end
    local details, numPresets = LayoutsForSave()
    if not details then
        return false
    end
    local changed = false
    for idx = numPresets + 1, #details.layouts do
        local layout = details.layouts[idx]
        local source
        if layout.layoutType == CHAR_LAYOUT then
            source = mine
        else
            source = acct
        end
        local byLayout = source and source[layout.layoutName]
        if byLayout and type(layout.systems) == "table" then
            for _, sys in ipairs(layout.systems) do
                local bySys = byLayout[sys.system * 1000 + (sys.systemIndex or 0)]
                local result = bySys and type(sys.settings) == "table" and SystemRestores(sys, bySys)
                if result then
                    for row, wanted in pairs(result) do
                        row.value = wanted
                    end
                    changed = true
                end
                if bySys and RestoreAnchor(sys, bySys.anchor) then
                    changed = true
                end
            end
        end
    end
    if changed then
        C_EditMode.SaveLayouts(details)
    end
    return true
end

-------------------------------------------------------------------------------
--  Chat windows
-------------------------------------------------------------------------------

--- SetChatWindowSize for a font size CludesUI applies on its own (stored
--- per character, like the window itself).
function CludesUI.SetChatWindowSize(index, size)
    if _uninstalled then
        return
    end
    local _, before = GetChatWindowInfo(index)
    SetChatWindowSize(index, size)
    if _fresh == nil or before == nil then
        return
    end
    local c = CharRecord()
    if not c then
        return
    end
    local t = Sub(c, "chatFont")
    local e = t[index]
    if not e then
        e = {}
        t[index] = e
        if Record().fresh then
            e.b = before
        end
    end
    local _, after = GetChatWindowInfo(index)
    e.a = after
end

local function RestoreChatFonts(t)
    if not t then
        return
    end
    for index, entry in pairs(t) do
        local _, current = GetChatWindowInfo(index)
        if current ~= nil and current == entry.a and entry.b ~= nil and entry.b ~= current then
            SetChatWindowSize(index, entry.b)
        end
    end
end

-------------------------------------------------------------------------------
--  Key bindings
-------------------------------------------------------------------------------

--- Before CludesUI binds key to one of its own commands (CUI_*): records
--- the action the key had then, so Uninstall can hand it back. The latest
--- action the player gave the key counts; an empty key or one of
--- CludesUI's own commands never replaces it.
function CludesUI.NoteBinding(key, before)
    if _fresh == nil or not key then
        return
    end
    local root
    if GetCurrentBindingSet() == 2 then
        root = CharRecord()
    else
        root = Record()
    end
    if not root then
        return
    end
    local t = Sub(root, "bind")
    local action = type(before) == "string" and before ~= "" and not before:find("^CUI_") and before or false
    if t[key] == nil or action then
        t[key] = action
    end
end

-- A key CludesUI took from another action goes back to it while the key
-- is still on one of CludesUI's commands, or empty (CludesUI moves and
-- clears the keys it took). Other keys on its commands stay: they do nothing
-- while it is off and work again if it comes back. Only the binding set in
-- use can be saved; returns that set.
local function RestoreBindings(acct, mine)
    local set = GetCurrentBindingSet()
    local rec
    if set == 2 then
        rec = mine.bind
    else
        rec = acct.bind
    end
    if rec then
        local changed = false
        for key, before in pairs(rec) do
            local action = GetBindingAction(key)
            if before and type(action) == "string" and (action == "" or action:find("^CUI_")) then
                SetBinding(key, before)
                changed = true
            end
        end
        if changed then
            SaveBindings(set)
        end
    end
    return set
end

-------------------------------------------------------------------------------
--  Uninstall CUI
-------------------------------------------------------------------------------
local _steps = {}

--- Adds a step Uninstall runs before CludesUI turns off: for changes only
--- its module knows how to undo.
function CludesUI.OnUninstall(func)
    _steps[#_steps + 1] = func
end

--- True when the record holds the settings from before CludesUI (false:
--- they go back to the game's defaults instead).
function CludesUI.UninstallKnowsOriginals()
    local r = type(CludesUIDB) == "table" and CludesUIDB[KEY]
    return type(r) == "table" and r.fresh == true
end

-- Every installed CludesUI addon: this one (the suite's parent or a
-- standalone) and each CludesUI module.
local function OwnAddOns()
    local entries = { ADDON_NAME }
    for idx = 1, C_AddOns.GetNumAddOns() do
        local name = C_AddOns.GetAddOnInfo(idx)
        if name and name ~= ADDON_NAME and name:find("^CludesUI") then
            entries[#entries + 1] = name
        end
    end
    return entries
end

--- Puts back the settings CludesUI changed and turns it off for every
--- character; the caller reloads (CludesUI.RequestReload). Refused, with
--- nothing changed, in combat (key bindings and protected CVars cannot change
--- then) and while Edit Mode is open. Returns true when it ran.
function CludesUI.Uninstall()
    if _uninstalled or InCombatLockdown() or EditModeOpen() then
        return false
    end
    -- From here on nothing re-applies a setting, not even a handler the
    -- writes below wake.
    _uninstalled = true
    local r = Record()
    local mine = CharRecord(true) or {}
    -- Each part in a pcall: one that fails never keeps CludesUI from turning
    -- off. What a part put back is dropped, so the next time CludesUI is
    -- turned on its first writes record the values found then; a part that
    -- failed keeps its records for a later Uninstall.
    pcall(ReleaseHolds, r)
    pcall(ReleaseHolds, mine)
    if pcall(RestoreCVars, r.cvar) then
        r.cvar = nil
    end
    if pcall(RestoreCVars, mine.cvar) then
        mine.cvar = nil
    end
    if pcall(RestoreBits, r.bits) then
        r.bits = nil
    end
    if pcall(RestoreBits, mine.bits) then
        mine.bits = nil
    end
    local okEM, emDone = pcall(RestoreEditMode, r.em, mine.em)
    if okEM and emDone then
        r.em, mine.em = nil, nil
        r.emKnown, mine.emKnown = nil, nil
    end
    if pcall(RestoreChatFonts, mine.chatFont) then
        mine.chatFont = nil
    end
    local okBind, set = pcall(RestoreBindings, r, mine)
    if okBind then
        if set == 2 then
            mine.bind = nil
        else
            r.bind = nil
        end
    end
    for idx = 1, #_steps do
        pcall(_steps[idx])
    end
    -- Everything CludesUI changed is back, so from here on every snapshot
    -- holds the player's own values.
    r.fresh = true
    for _, name in ipairs(OwnAddOns()) do
        C_AddOns.DisableAddOn(name)
    end
    C_AddOns.SaveAddOns()
    return true
end
