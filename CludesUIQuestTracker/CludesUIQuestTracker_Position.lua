if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_Position.lua - moving Blizzard's tracker in Unlock Mode.
--
--  The spot and height are written into the tracker's entry of the active
--  Edit Mode layout, so Blizzard's own layout apply places the tracker and
--  takes it out of the right-side container it otherwise sits in. Edit Mode
--  applies a saved layout only on reload, so a move away from the default
--  spot, or a new height, asks for one.
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT

-- Edit Mode's Height slider stores (height - min) / step.
local HEIGHT_MIN, HEIGHT_MAX, HEIGHT_STEP = 400, 1000, 10

local function Tracker()
    return _G.ObjectiveTrackerFrame
end

local wanted = { relativeTo = "UIParent" } -- the anchor the layout should hold
local hooked -- the layout-apply hook is set
local changedInSession -- the player moved or resized it this unlock session
local reloadAsked -- the reload prompt has been shown this session
local resetWaiting -- a reset waits for the unlock session to close
local syncQueued
local standIn, standInPlaced -- what an unlock session moves while the tracker is held
local heightAtOpen -- the height when the unlock session opened
local selectionTakenAway -- we made Edit Mode's selection box inert

-- Until its Edit Mode layout applies, the right-side container places it.
local function Held()
    local f = Tracker()
    return not f:IsInitialized() or f:IsInDefaultPosition()
end

-- The container puts a held tracker back in its slot on every update, so an
-- unlock session moves a stand-in of the tracker's size instead.
local function UnlockFrame()
    local f = Tracker()
    if not (CludesUI._unlockActive and Held()) then
        return f
    end
    if not standInPlaced then
        standInPlaced = true
        local conf = EQT.DB()
        standIn = standIn or CreateFrame("Frame", nil, UIParent)
        standIn:SetSize(f:GetWidth(), conf.height or f.editModeHeight or 800)
        standIn:ClearAllPoints()
        local spot = conf.position
        if spot then
            standIn:SetPoint(spot.point, UIParent, spot.relPoint or spot.point, spot.x, spot.y)
        elseif f:GetLeft() then
            standIn:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", f:GetLeft(), f:GetTop())
        end
    end
    return standIn
end

-- The layout list, the active layout, its tracker entry, and whether that
-- layout is one of Blizzard's read-only presets. Nothing while Edit Mode is
-- open or before its layouts have applied.
local function ActiveEntry()
    local f = Tracker()
    if not (f and f:IsInitialized()) or CludesUI.EditModeOpen() then
        return nil
    end
    local layouts, presetCount = CludesUI.EditModeLayoutsForSave()
    if not layouts or type(layouts.activeLayout) ~= "number" then
        return nil
    end
    local layout = layouts.layouts[layouts.activeLayout]
    if type(layout) ~= "table" or type(layout.systems) ~= "table" then
        return nil
    end
    for _, entry in ipairs(layout.systems) do
        if entry.system == Enum.EditModeSystem.ObjectiveTracker then
            return layouts, layout, entry, layouts.activeLayout <= presetCount
        end
    end
end

local function HeightSetting(entry)
    for _, row in ipairs(entry.settings) do
        if row.setting == Enum.EditModeObjectiveTrackerSetting.Height then
            return row
        end
    end
end

-- Whether the entry already holds the wanted anchor.
local function HoldsWanted(entry)
    local a = entry.anchorInfo
    return not entry.isInDefaultPosition
        and entry.anchorInfo2 == nil
        and type(a) == "table"
        and a.point == wanted.point
        and a.relativeTo == wanted.relativeTo
        and a.relativePoint == wanted.relativePoint
        and math.abs((a.offsetX or 0) - wanted.offsetX) < 0.1
        and math.abs((a.offsetY or 0) - wanted.offsetY) < 0.1
end

-- Writes the saved spot and height into the active layout where it differs.
-- Returns true when written, "preset" when that layout cannot be changed.
local function WriteLayout(conf)
    local layouts, layout, entry, isPreset = ActiveEntry()
    if not entry then
        return
    end
    local spot = conf.position
    local scale = Tracker():GetScale()
    wanted.point, wanted.relativePoint = spot.point, spot.relPoint or spot.point
    wanted.offsetX, wanted.offsetY = spot.x * scale, spot.y * scale
    local row = HeightSetting(entry)
    local value = conf.height and (conf.height - HEIGHT_MIN) / HEIGHT_STEP
    local anchorRight = HoldsWanted(entry)
    local heightRight = not value or (row and row.value == value)
    if anchorRight and heightRight then
        return
    end
    if isPreset then
        return "preset"
    end
    if not anchorRight then
        CludesUI.NoteEditModeAnchor(layout, entry, wanted)
        entry.anchorInfo = {
            point = wanted.point,
            relativeTo = wanted.relativeTo,
            relativePoint = wanted.relativePoint,
            offsetX = wanted.offsetX,
            offsetY = wanted.offsetY,
        }
        entry.anchorInfo2 = nil
        entry.isInDefaultPosition = false
    end
    if not heightRight then
        if row then
            CludesUI.NoteEditModeSetting(layout, entry, row.setting, row.value, value)
            row.value = value
        else
            entry.settings[#entry.settings + 1] =
                { setting = Enum.EditModeObjectiveTrackerSetting.Height, value = value }
        end
    end
    C_EditMode.SaveLayouts(layouts)
    return true
end

-- Back to Edit Mode's default spot, as its own Reset To Default Position.
local function ResetLayout()
    local layouts, layout, entry, isPreset = ActiveEntry()
    if not entry or isPreset or entry.isInDefaultPosition then
        return false
    end
    local default =
        EditModePresetLayoutManager:GetDefaultSystemAnchorInfo(Enum.EditModeSystem.ObjectiveTracker)
    CludesUI.NoteEditModeAnchor(layout, entry, default)
    entry.anchorInfo = default
    entry.anchorInfo2 = nil
    entry.isInDefaultPosition = true
    C_EditMode.SaveLayouts(layouts)
    return true
end

-- While we hold the spot, Edit Mode's selection box cannot pick the tracker
-- up (a drag there would be undone by the next sync). Only a box we made
-- inert is made live again.
local function EditModeCanSelect(on)
    if on and not selectionTakenAway then
        return
    end
    selectionTakenAway = not on
    CludesUI.SetEditModeChildInert(Tracker().Selection, not on)
end

local function AskReload()
    if reloadAsked then
        return
    end
    reloadAsked = true
    CludesUI:ShowConfirmPopup({
        title = "Reload to Move the Quest Tracker",
        message = "The quest tracker's new position and height are saved to your Edit Mode layout. Blizzard applies them after a reload.",
        confirmText = "Reload",
        cancelText = "Not Now",
        reload = true,
    })
end

local function WarnPreset()
    CludesUI:ShowConfirmPopup({
        title = "Copy Your Edit Mode Layout",
        message = "Your active Edit Mode layout is one of Blizzard's presets, which cannot be changed. Copy it in Edit Mode, then move the quest tracker again.",
        confirmText = "Okay",
        hideCancel = true,
    })
end

function EQT.SyncPosition()
    syncQueued = nil
    local conf = EQT.DB()
    if CludesUI._unlockActive then
        return
    end
    -- No spot of ours in this profile: Edit Mode may move it again.
    if not conf.position then
        EditModeCanSelect(true)
        return
    end
    if InCombatLockdown() then
        mod.CombatQueue.Defer("QTPosition", EQT.SyncPosition)
        return
    end
    if not hooked then
        hooked = true
        -- Every layout apply (login, a layout or spec switch, leaving Edit
        -- Mode) checks the active layout against the saved spot again.
        hooksecurefunc(Tracker(), "ApplySystemAnchor", function()
            if syncQueued or not EQT.DB().position then
                return
            end
            syncQueued = true
            C_Timer.After(0, EQT.SyncPosition)
        end)
    end
    -- Leaving Edit Mode applies the layout, which syncs again.
    if CludesUI.EditModeOpen() then
        return
    end
    local byPlayer = changedInSession
    changedInSession = nil
    if WriteLayout(conf) == "preset" then
        if byPlayer then
            WarnPreset()
        end
        return
    end
    local f = Tracker()
    if not f:IsInitialized() then
        return
    end
    EditModeCanSelect(false)
    -- Edit Mode has not applied the written spot or height yet.
    if f:IsInDefaultPosition() or (conf.height and f.editModeHeight ~= conf.height) then
        AskReload()
        return
    end
    local spot = conf.position
    CludesUI.ClearFramePoints(f)
    CludesUI.SetFramePoint(f, spot.point, UIParent, spot.relPoint or spot.point, spot.x, spot.y)
    -- The login anchor pass may have run while the tracker was still held.
    CludesUI.ReapplyUnlockAnchor("EQT_Tracker")
end

local function ApplyReset()
    resetWaiting = nil
    if InCombatLockdown() then
        mod.CombatQueue.Defer("QTPositionReset", ApplyReset)
        return
    end
    if EQT.DB().position then
        return
    end
    EditModeCanSelect(true)
    if ResetLayout() then
        AskReload()
    end
end

-- In an unlock session a change waits for the session to close; otherwise
-- it applies now.
local function Changed()
    if CludesUI._unlockActive then
        changedInSession = true
    else
        EQT.SyncPosition()
    end
end

function EQT.InitPosition()
    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "EQT_Tracker",
            label = "Quest Tracker",
            group = "Quest Tracker",
            order = 560,
            getFrame = UnlockFrame,
            getSize = function()
                local f = UnlockFrame()
                return f:GetWidth(), EQT.DB().height or f:GetHeight()
            end,
            isHidden = function()
                return not EQT.Cfg("enabled")
            end,
            isPositionHeld = Held,
            -- The Edit Mode layout holds the spot and a change takes a reload,
            -- so it is one spot for every spec.
            noSpecLayout = true,
            setHeight = function(_, height)
                height = math.floor(height / HEIGHT_STEP + 0.5) * HEIGHT_STEP
                height = math.max(HEIGHT_MIN, math.min(HEIGHT_MAX, height))
                EQT.Set("height", height)
                if standInPlaced then
                    standIn:SetHeight(height)
                end
                Changed()
            end,
            -- Kept by the top edge: the tracker grows downwards, and a moved
            -- tracker takes its Height setting.
            savePos = function(_, point, relPoint, x, y)
                if point == "CENTER" then
                    point, relPoint, y = "TOP", "CENTER", y + UnlockFrame():GetHeight() / 2
                end
                EQT.Set("position", { point = point, relPoint = relPoint or point, x = x, y = y })
                Changed()
            end,
            loadPos = function()
                return EQT.Cfg("position")
            end,
            clearPos = function()
                EQT.Set("position", nil)
                EQT.Set("height", nil)
                if CludesUI._unlockActive then
                    resetWaiting = true
                else
                    ApplyReset()
                end
            end,
            applyPos = function()
                EQT.SyncPosition()
            end,
        }),
    }, "CludesUIQuestTracker")

    -- Layout writes and reload prompts wait for the session to close.
    CludesUI:RegisterUnlockModeListener("CludesUIQuestTracker", function(isActive, closeAction)
        if isActive then
            heightAtOpen = EQT.DB().height
            return
        end
        standInPlaced = nil
        -- Discarding restores the height (even to none).
        if closeAction ~= "save" then
            EQT.Set("height", heightAtOpen)
        end
        if closeAction ~= "save" or not EQT.DB().position then
            changedInSession = nil
        end
        if resetWaiting then
            ApplyReset()
        end
        EQT.SyncPosition()
    end)

    EQT.SyncPosition()
end
