if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_UnlockMode.lua
--  Unlock Mode: animated transition, grid overlay, draggable movers, snap
--  guides, position memory, return-to-options flow. Elements from any addon
--  register via CludesUI:RegisterUnlockElements().
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
mod = mod.__cuiCoreNS or mod -- standalone builds: the core's own table (CludesUI.lua)
local ABAR = mod.EAB -- may be nil if loaded by a non-ActionBars addon

-------------------------------------------------------------------------------
--  Registration API -- on the CludesUI global so ALL addons share one
--  table regardless of which copy of this file runs.
-------------------------------------------------------------------------------
if not CUI._unlockRegisteredElements then
    CUI._unlockRegisteredElements = {}
    CUI._unlockRegisteredOrder = {}
    CUI._unlockRegistrationDirty = true
end

if not CUI.RegisterUnlockElements then
    -- Normalize short field aliases (savePos) to the long names used
    -- throughout unlock mode (savePosition).
    local FIELD_ALIASES = {
        savePos = "savePosition",
        loadPos = "loadPosition",
        clearPos = "clearPosition",
        applyPos = "applyPosition",
    }
    function CUI:RegisterUnlockElements(elements, folder)
        for _, elem in ipairs(elements) do
            for short, long in pairs(FIELD_ALIASES) do
                if elem[short] and not elem[long] then elem[long] = elem[short] end
            end
            -- Stamp the owning folder (per-element wins over call-site): export/import
            -- attributes the element and its anchor/match links to a module for per-module layout export.
            if folder and not elem.folder then elem.folder = folder end
            self._unlockRegisteredElements[elem.key] = elem
        end
        self._unlockRegistrationDirty = true
        -- Fresh registration flushes spec-override unlock layers' deferred writes
        -- for late/conditional registrants (party/raid containers, CDM bars).
        if CUI.SpecOverrides_UnlockPokeFlush then CUI.SpecOverrides_UnlockPokeFlush() end
    end
end

if not CUI.UnregisterUnlockElement then
    function CUI:UnregisterUnlockElement(key)
        self._unlockRegisteredElements[key] = nil
        self._unlockRegistrationDirty = true
    end
end

-- Cross-addon listeners fire on real session open/close only; close passes
-- "exit"/"save"/"discard" as arg 2. Combat suspension does not end the session.
if not CUI._unlockModeListeners then CUI._unlockModeListeners = {} end

if not CUI.RegisterUnlockModeListener then
    function CUI:RegisterUnlockModeListener(ownerFrame, listener)
        self._unlockModeListeners[ownerFrame] = listener
        if self._unlockModeSessionActive then pcall(listener, true) end
    end

    function CUI:UnregisterUnlockModeListener(ownerFrame) self._unlockModeListeners[ownerFrame] = nil end

    function CUI:IsUnlockModeActive() return self._unlockModeSessionActive == true end

    function CUI:_NotifyUnlockModeListeners(isActive, closeAction)
        self._unlockModeSessionActive = isActive == true
        for _, listener in pairs(self._unlockModeListeners) do
            pcall(listener, self._unlockModeSessionActive, closeAction)
        end
    end
end

-- Already loaded by another addon: bail (registration API above is idempotent;
-- state/frames/animations below must exist only once).
if CUI._unlockModeLoaded then return end
CUI._unlockModeLoaded = true

-- Overlap cycling in Unlock Mode: "disabled", or the wheel alone ("scroll",
-- the default) or with Shift / Ctrl / Alt held ("shiftscroll" /
-- "controlscroll" / "altscroll").
function CUI.GetUnlockOverlapMethod()
    local saved = CludesUIDB
    return (saved and saved.unlockOverlapMethod) or "scroll"
end
-- Each method's label: the Global Settings dropdown and the top bar's controls
-- help (CUI_UnlockMode_Session.lua) read it, each through L().
CUI.UNLOCK_OVERLAP_LABELS = {
    disabled = "Disabled",
    scroll = "Scroll",
    shiftscroll = "Shift + Scroll",
    controlscroll = "Ctrl + Scroll",
    altscroll = "Alt + Scroll",
}

-------------------------------------------------------------------------------
--  Anchor reapply stub (pre-EnsureLoaded): lets child addons (CDM) reposition
--  anchored elements at login before the full body loads; deferred block replaces it.
-------------------------------------------------------------------------------
if not CUI.ReapplyOwnAnchor then
    CUI.ReapplyOwnAnchor = function(key)
        if not CludesUIDB or not CludesUIDB.unlockAnchors then return end
        local details = CludesUIDB.unlockAnchors[key]
        if not details or not details.target then return end

        local elems = CUI._unlockRegisteredElements
        local childElem = elems and elems[key]
        if childElem and childElem.ownsPosition then return end
        local targetElem = elems and elems[details.target]
        local childBar = childElem and childElem.getFrame and childElem.getFrame(key)
        local targetBar = targetElem and targetElem.getFrame and targetElem.getFrame(details.target)
        if not childBar or not targetBar then return end
        if details.mode == "POINT" then
            mod.PointAnchors.EarlyApply(key, details, childBar, targetBar)
            return
        end
        if not targetBar:GetLeft() then return end

        local side = details.side
        local uiS = UIParent:GetEffectiveScale()
        local tS = targetBar:GetEffectiveScale()
        local cS = childBar:GetEffectiveScale()

        local tL = (targetBar:GetLeft() or 0) * tS / uiS
        local tR = (targetBar:GetRight() or 0) * tS / uiS
        local tT = (targetBar:GetTop() or 0) * tS / uiS
        local tB = (targetBar:GetBottom() or 0) * tS / uiS
        local tCX = (tL + tR) / 2
        local tCY = (tT + tB) / 2

        local cW = (childBar:GetWidth() or 50) * cS / uiS
        local cH = (childBar:GetHeight() or 50) * cS / uiS

        local cx, cy
        if details.offsetX and details.offsetY then
            if side == "LEFT" then
                cx = tL + details.offsetX - cW / 2
                cy = tCY + details.offsetY
            elseif side == "RIGHT" then
                cx = tR + details.offsetX + cW / 2
                cy = tCY + details.offsetY
            elseif side == "TOP" then
                cx = tCX + details.offsetX
                cy = tT + details.offsetY + cH / 2
            elseif side == "BOTTOM" then
                cx = tCX + details.offsetX
                cy = tB + details.offsetY - cH / 2
            else
                cx = tCX + details.offsetX
                cy = tCY + details.offsetY
            end
        else
            if side == "LEFT" then
                cx = tL - cW / 2
                cy = tCY
            elseif side == "RIGHT" then
                cx = tR + cW / 2
                cy = tCY
            elseif side == "TOP" then
                cx = tCX
                cy = tT + cH / 2
            elseif side == "BOTTOM" then
                cx = tCX
                cy = tB - cH / 2
            else
                cx = tCX
                cy = tCY
            end
        end

        local uiW, uiH = UIParent:GetSize()
        local centerX = cx - uiW / 2
        local centerY = cy - uiH / 2

        -- No explicit snap: center came from pixel-aligned target edges/dims; snapping here adds 1px drift from float dust.
        pcall(function()
            CUI.ClearFramePoints(childBar)
            CUI.SetFramePoint(childBar, "CENTER", UIParent, "CENTER", centerX, centerY)
        end)
    end
end

-------------------------------------------------------------------------------
--  Early stub: NotifyElementResized -- grow-direction-aware repositioning before
--  unlock mode fully loads; deferred block overwrites it.
-------------------------------------------------------------------------------
if not CUI.NotifyElementResized then
    CUI.NotifyElementResized = function(key)
        if not CludesUIDB then return end
        -- Skip if anchored (early ReapplyOwnAnchor handles those)
        local anchors = CludesUIDB.unlockAnchors
        if anchors and anchors[key] and anchors[key].target then return end

        local growDir
        if key == "EQT_Tracker" then
            local get = CUI.GetQuestTrackerGrowDir
            growDir = get and get() or "DOWN"
        elseif key:sub(1, 4) == "CDM_" then
            local rawKey = key:sub(5)
            local cdm = CUI.Lite
                and CUI.Lite.GetAddon
                and CUI.Lite.GetAddon("CludesUICooldownManager", true)
            local cdmBars = cdm and cdm.db and cdm.db.profile and cdm.db.profile.cdmBars
            if cdmBars and cdmBars.bars then
                for _, bar in ipairs(cdmBars.bars) do
                    if bar.key == rawKey then
                        local g = bar.growDirection
                        if g then growDir = g end
                        break
                    end
                end
            end
        else
            local eab = CUI.Lite
                and CUI.Lite.GetAddon
                and CUI.Lite.GetAddon("CludesUIActionBars", true)
            local cfg = eab and eab.db and eab.db.profile and eab.db.profile.bars and eab.db.profile.bars[key]
            if cfg then
                local g = (cfg.growDirection or "up"):upper()
                if g ~= "UP" then growDir = g end
            end
        end
        if not growDir or growDir == "CENTER" then return end

        local elems = CUI._unlockRegisteredElements
        local elem = elems and elems[key]
        local widget = elem and elem.getFrame and elem.getFrame(key)
        if not widget or not widget:GetCenter() then return end

        local place
        if elem and elem.loadPosition then
            place = elem.loadPosition(key)
        else
            local eab = CUI.Lite
                and CUI.Lite.GetAddon
                and CUI.Lite.GetAddon("CludesUIActionBars", true)
            local saved = eab and eab.db and eab.db.profile and eab.db.profile.barPositions
            place = saved and saved[key]
        end
        if not place or place.point ~= "CENTER" or place.relPoint ~= "CENTER" then return end

        local cx, cy = place.x or 0, place.y or 0
        local fw = widget:GetWidth() or 0
        local fh = widget:GetHeight() or 0
        -- Raw fw/2, fh/2 (not floor): odd-dimension frames with integer+0.5 centers
        -- reverse to exact pixel edges; floor() loses the .5 (1px drift).
        local anchor, adjX, adjY
        if growDir == "RIGHT" then
            anchor = "LEFT"
            adjX = cx - fw / 2
            adjY = cy
        elseif growDir == "LEFT" then
            anchor = "RIGHT"
            adjX = cx + fw / 2
            adjY = cy
        elseif growDir == "DOWN" then
            anchor = "TOP"
            adjX = cx
            adjY = cy + fh / 2
        elseif growDir == "UP" then
            anchor = "BOTTOM"
            adjX = cx
            adjY = cy - fh / 2
        else
            return
        end

        -- No explicit snap: cx +/- dim/2 reproduces the pixel-aligned edge within float epsilon; snapping can round the wrong way (1px drift/reload).
        pcall(function()
            CUI.ClearFramePoints(widget)
            CUI.SetFramePoint(widget, anchor, UIParent, "CENTER", adjX, adjY)
        end)
    end
end

-- Early stub: IsUnlockAnchored -- true if the key has an anchor target in the DB; deferred block overwrites it.
if not CUI.IsUnlockAnchored then
    CUI.IsUnlockAnchored = function(unlockKey)
        if not CludesUIDB or not CludesUIDB.unlockAnchors then return false end
        local ai = CludesUIDB.unlockAnchors[unlockKey]
        return ai and ai.target and true or false
    end
end

-- Authoritative position pass fallback: CDM owns this pass when loaded (fires from
-- CollectAndReanchor once async icon population settles). Without CDM nobody
-- triggers EnsureUnlockCore or the final layout pass, so fire it from here.
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        C_Timer.After(1.5, function()
            -- CDM already ran EnsureUnlockCore and fires the pass itself.
            if CUI._applySavedPositions then return end
            -- No CDM: run the deferred block and fire the same pass.
            CUI:EnsureUnlockCore()
            if CUI.ApplyAllWidthHeightMatches then CUI.ApplyAllWidthHeightMatches() end
            if CUI._applySavedPositions then CUI._applySavedPositions() end
            if CUI.ReapplyAllUnlockAnchorsForced then CUI.ReapplyAllUnlockAnchorsForced() end
        end)
    end)
end

-- Synchronous handler at PLAYER_LOGIN, never a timer: on a combat reload, lockdown
-- is not yet re-engaged during PLAYER_LOGIN dispatch, but a timer scheduled here
-- would fire after the loading screen with lockdown back on. Must live in this
-- non-deferred header -- the deferred body only runs via EnsureUnlockCore() during
-- this dispatch (CDM) or later (fallback above), so a handler inside it would miss
-- the in-flight event. Created after Lite's lifecycle frame so every module's
-- OnEnable already ran (bars positioned, frames spawned, elements registered),
-- letting protected children (oUF) anchor before lockdown re-engages; later
-- builders (CDM at PEW) fall through to the retry loop/regen park. The unlock-core
-- cost is paid at PEW anyway -- doing it here just hides it in the loading screen.
-- Deliberately NOT EnsureLoaded: that would pull the whole LoadOnDemand options
-- addon into every login.
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        CUI:EnsureUnlockCore()
        if CUI._applySavedPositions then CUI._applySavedPositions() end
    end)
end

-- Screen-edge anchor targets: invisible 1-unit strips just outside each of the
-- four screen edges, so their inner edge IS the screen edge and a link's
-- edge-to-edge offset counts from it. Registered in this non-deferred header so the
-- early ReapplyOwnAnchor stub resolves them at login. isHidden = no mover (never
-- dragged or picked); the no-op savePosition keeps SaveBarPosition's action bar
-- fallback from ever writing these keys.
do
    -- anchor, relative point, anchor, relative point, label, thin axis
    local EDGES = {
        SCREEN_LEFT = { "TOPRIGHT", "TOPLEFT", "BOTTOMRIGHT", "BOTTOMLEFT", "Left Screen Edge", "W" },
        SCREEN_RIGHT = { "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT", "Right Screen Edge", "W" },
        SCREEN_TOP = { "BOTTOMLEFT", "TOPLEFT", "BOTTOMRIGHT", "TOPRIGHT", "Top Screen Edge", "H" },
        SCREEN_BOTTOM = {
            "TOPLEFT",
            "BOTTOMLEFT",
            "TOPRIGHT",
            "BOTTOMRIGHT",
            "Bottom Screen Edge",
            "H",
        },
    }
    function CUI.IsScreenEdgeKey(key) return EDGES[key] ~= nil end

    local strips = {}
    local function GetStrip(key) return strips[key] end
    local function IsHidden() return true end
    local function NoSave() end

    local elements = {}
    for key, def in pairs(EDGES) do
        local frame = CreateFrame("Frame", nil, UIParent)
        if def[6] == "W" then
            frame:SetWidth(1)
        else
            frame:SetHeight(1)
        end
        frame:SetPoint(def[1], UIParent, def[2], 0, 0)
        frame:SetPoint(def[3], UIParent, def[4], 0, 0)
        strips[key] = frame
        elements[#elements + 1] = {
            key = key,
            label = def[5],
            getFrame = GetStrip,
            savePosition = NoSave,
            isHidden = IsHidden,
            noAnchorTo = true,
            noResize = true,
            noSizeMatchTarget = true,
        }
    end
    CUI:RegisterUnlockElements(elements)

    -- Linked children sit at absolute offsets from UIParent's center, so any change
    -- of UIParent's size in units (aspect ratio, window size, UI scale) leaves them
    -- stale. This frame follows UIParent's size and re-runs every edge's chain
    -- (batched into one pass per frame).
    local watch = CreateFrame("Frame", nil, UIParent)
    watch:SetAllPoints(UIParent)
    watch:SetScript("OnSizeChanged", function()
        local propagate = CUI.PropagateAnchorChain
        if not propagate then return end
        for key in pairs(EDGES) do
            propagate(key)
        end
    end)
end

-- DEFERRED: heavy body (4900+ lines) runs on first EnsureUnlockCore() call
-- (PLAYER_LOGIN / CDM setup / unlock-mode open / EnsureLoaded). Own slot, not
-- _deferredInits: login must run this WITHOUT loading the options addon.
CUI._unlockCoreInit = function()
    local LM = {} -- unlock state and late-bound functions shared across the unlock files
    local floor = math.floor
    local abs = math.abs
    local min = math.min
    local max = math.max
    local sqrt = math.sqrt
    local sin = math.sin

    -- IEEE 754 branchless round-to-nearest-even (avoids -0 from half-pixel centers)
    local function round(num) return num + (2 ^ 52 + 2 ^ 51) - (2 ^ 52 + 2 ^ 51) end

    -- Pixel-perfect snap: round a value to the nearest physical pixel boundary.
    local Pix = CUI and CUI.PP
    local function pxSnap(posX)
        if not Pix then return round(posX) end
        local m = Pix.mult or 1
        if m == 1 then return round(posX) end
        return round(posX / m) * m
    end

    -- WaitForSize: defer callback one frame so the layout engine has flushed.
    local function WaitForSize(widget, callback) C_Timer.After(0, callback) end

    -- Blank or restore a bar frame's alpha around a resize. Action Bars tracks the
    -- alpha of the bars it fades instead of reading it back, so it is told.
    function CUI._UnlockSetBarAlpha(widget, a)
        widget:SetAlpha(a)
        local note = CUI._EABNoteAlpha
        if note then note(widget, a) end
    end

    -- DeferMoverSync: sync now (no blink) and again next frame to catch layout-engine
    -- flush moves; hides the bar frame meanwhile to prevent a visual jump.
    local function DeferMoverSync(m, syncFn, barFrame)
        if not m then return end
        if barFrame then CUI._UnlockSetBarAlpha(barFrame, 0) end
        syncFn(m)
        C_Timer.After(0, function()
            if m then syncFn(m) end
            if barFrame then CUI._UnlockSetBarAlpha(barFrame, 1) end
        end)
    end

    -- After a setWidth/setHeight rebuild snaps the bar to its stored position mid-unlock,
    -- re-place it at the mover's current screen position (else resizing makes it jump).
    -- On CludesUI to avoid an upvalue in CreateMover (Lua 5.1 limit: 60).
    function CUI.RepositionBarToMover(barId)
        if not LM.isUnlocked then return end
        if CUI.IsPointAnchored(barId) then
            CUI.ReapplyOwnAnchor(barId)
            return
        end
        local m = LM.movers[barId]
        if not m then return end
        local bar = LM.GetBarFrame(barId)
        if not bar then return end
        local mX, mY = m:GetCenter()
        local barScale = bar:GetEffectiveScale()
        if not mX or not mY or not barScale or barScale <= 0 then return end
        -- Pin center to center: the mover still has the old size here, so a corner
        -- pin would shift the element by half the size change. The mover center is
        -- converted into the bar's own scale (SetPoint offsets use the bar's scale).
        local ratio = m:GetEffectiveScale() / barScale
        pcall(function()
            CUI.ClearFramePoints(bar)
            CUI.SetFramePoint(bar, "CENTER", UIParent, "BOTTOMLEFT", mX * ratio, mY * ratio)
        end)
    end

    -- RecenterBarAnchor is defined below, after its dependencies (isUnlocked, movers, registeredElements, GetBarFrame, GetBarGrowDirActual).

    -------------------------------------------------------------------------------
    --  Constants
    -------------------------------------------------------------------------------
    local FONT_PATH = (CUI.GetFontPath("extras"))
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

    -- At very low UI scale the overlays/top bar are hard to read, so they're nudged up.
    -- The `UIParent:GetEffectiveScale() < 0.6` test is inlined at each use site (not a
    -- helper) because overlay builders are already at Lua 5.1's 60-upvalue limit.
    local GRID_SPACING = 32 -- pixels between grid lines
    local SNAP_THRESH = 6 -- px distance to trigger snap-to-element
    local MOVER_ALPHA = 0.55 -- resting alpha for mover overlays
    local MOVER_HOVER = 0.85 -- hover alpha
    local MOVER_DRAG = 0.95 -- dragging alpha
    local TRANSITION_DUR = 0.35 -- seconds for the open/close fade-in

    -- Movable bar keys (action bars + stance + micro + bag); populated by EAB if loaded, else empty.
    local BAR_LOOKUP = mod.BAR_LOOKUP or {}
    local ALL_BAR_ORDER = mod.BAR_DROPDOWN_ORDER or {}
    local VISIBILITY_ONLY = mod.VISIBILITY_ONLY or {}

    local function GetVisibilityOnly()
        -- Read lazily so child addons have time to populate ns.VISIBILITY_ONLY
        return mod.VISIBILITY_ONLY or VISIBILITY_ONLY
    end

    -- Local aliases for the shared registration tables
    local registeredElements = CUI._unlockRegisteredElements
    local registeredOrder = CUI._unlockRegisteredOrder

    local function RebuildRegisteredOrder()
        if not CUI._unlockRegistrationDirty then return end
        wipe(registeredOrder)
        for key, _ in pairs(registeredElements) do
            registeredOrder[#registeredOrder + 1] = key
        end
        -- Sort by order field (lower first), then alphabetically
        table.sort(registeredOrder, function(lhs, rhs)
            local oa = registeredElements[lhs].order or 1000
            local ob = registeredElements[rhs].order or 1000
            if oa ~= ob then return oa < ob end
            return lhs < rhs
        end)
        CUI._unlockRegistrationDirty = false
    end

    -------------------------------------------------------------------------------
    --  State
    -------------------------------------------------------------------------------
    LM.unlockFrame = nil -- the full-screen overlay
    LM.gridFrame = nil -- grid line container
    local guidePool = {} -- reusable alignment guide lines
    local movers = {} -- { [barKey] = moverFrame }
    LM.isUnlocked = false
    function CUI.IsUnlockModeActive() return LM.isUnlocked end
    LM.gridMode = "dimmed" -- "disabled", "dimmed", "bright"
    LM.snapEnabled = true -- magnet/snap state (runtime); must precede SnapPosition
    local lockAnimFrame -- lock assembly animation (close)
    LM.openAnimFrame = nil -- lock animation frame (open)
    LM.logoFadeFrame = nil -- the 2s logo+title fade-out timer frame
    local pendingPositions = {} -- { [barKey] = {point,relPoint,x,y} } -- unsaved changes
    local snapshotPositions = {} -- original positions captured when unlock mode opens
    local snapshotAnchors = {} -- original anchor data captured when unlock mode opens
    local snapshotSizes = {} -- original sizes captured when unlock mode opens
    local snapshotWidthMatch = {} -- original width match DB captured when unlock mode opens
    local snapshotHeightMatch = {} -- original height match DB captured when unlock mode opens
    local snapshotGrowDirs = {} -- original growth directions captured when unlock mode opens
    -- Spec-override banner refresh = CludesUI._unlockRefreshSpecOvMarks (namespace
    -- field, not local: deferred-init function is at Lua 5.1's 200-local cap). Layer
    -- banking is a wholesale harvest at CommitPositions.
    LM.hasChanges = false -- true if user dragged anything this session
    LM.combatSuspended = false -- true if unlock mode was auto-closed by combat
    local preCombatChanges = false -- the session's change mark when combat hid it
    LM.objTrackerWasVisible = false -- track objective tracker state for restore

    -- Grid mode helpers
    local GRID_ALPHA_DIMMED = 0.15
    local GRID_ALPHA_BRIGHT = 0.30
    local GRID_CENTER_DIMMED = 0.25
    local GRID_CENTER_BRIGHT = 0.50
    local GRID_HUD_BRIGHT = 0.60 -- matches HUD_ON_ALPHA
    local GRID_HUD_DIMMED = 0.45
    local GRID_HUD_OFF = 0.30 -- matches HUD_OFF_ALPHA

    local function GridBaseAlpha() return LM.gridMode == "bright" and GRID_ALPHA_BRIGHT or GRID_ALPHA_DIMMED end
    local function GridCenterAlpha()
        return LM.gridMode == "bright" and GRID_CENTER_BRIGHT or GRID_CENTER_DIMMED
    end
    local function GridHudAlpha()
        if LM.gridMode == "bright" then return GRID_HUD_BRIGHT end
        if LM.gridMode == "dimmed" then return GRID_HUD_DIMMED end
        return GRID_HUD_OFF
    end
    local function GridLabelText()
        if LM.gridMode == "bright" then return "Grid Lines\nBright" end
        if LM.gridMode == "dimmed" then return "Grid Lines\nDimmed" end
        return "Grid Lines\nDisabled"
    end
    local function CycleGridMode()
        if LM.gridMode == "dimmed" then
            LM.gridMode = "bright"
        elseif LM.gridMode == "bright" then
            LM.gridMode = "disabled"
        else
            LM.gridMode = "dimmed"
        end
    end
    LM.flashlightEnabled = false -- cursor flashlight toggle
    LM.darkOverlaysEnabled = true -- dark overlay backgrounds on movers
    LM.coordsEnabled = false -- show coordinates for all elements at all times
    local _blizzOwnedOverlays = {} -- info overlays for Blizzard-controlled elements
    LM.unlockTipFrame = nil -- one-time "how to use" tip frame
    LM.selectedMover = nil -- currently selected mover frame (for arrow key nudging)
    LM.arrowKeyFrame = nil -- invisible frame that captures arrow key input
    LM.selectElementPicker = nil -- mover currently in "Select Element" pick mode (nil = off)
    local SELECT_ELEMENT_ALPHA = 0.50 -- overlay alpha during select-element pick mode
    local SELECT_ELEMENT_FADE = 0.50 -- seconds for the fade transition

    -- Maps barKey -> settings location for "Element Options" nav: module =
    -- RegisterModule folder; page = page tab (PAGE_* value); sectionName = string
    -- passed to SectionHeader(); preSelectFn = optional dropdown-setter run before
    -- the page builds. On CludesUI to dodge CreateMover's 60-upvalue cap.
    local function SelectActionBar(key)
        return function()
            -- Direct setter (if options module already built) + pending flag consumed
            -- at Bar Display page build. Mirrors the unit-frame path.
            if CUI._setActionBarKey then CUI._setActionBarKey(key) end
            CUI._pendingActionBarSelect = key
        end
    end
    local function SelectUnitFrame(unitToken)
        return function()
            -- Direct setter (if init already ran) + pending flag (consumed at page build)
            if CUI._setUnitFrameUnit then CUI._setUnitFrameUnit(unitToken) end
            CUI._pendingUnitSelect = unitToken
        end
    end
    -- Mini-frame pre-select factory (ToT/FoT/Pet/Boss live on "Mini Frames" with
    -- their own dropdown). On CludesUI, not file-local, to avoid a local in this limit-sensitive deferred function.
    CUI._SelectMiniUnit = function(unitToken)
        return function()
            if CUI._setMiniUnit then CUI._setMiniUnit(unitToken) end
            CUI._pendingMiniSelect = unitToken
        end
    end
    -- Capture entries registered before this deferred body runs (DataBars writes
    -- per-bar EDB_ keys at PLAYER_LOGIN, which fires first); merged back below so this
    -- assignment never wipes them. Namespace-stashed: function is at its local/upvalue cap.
    CUI._elemMapPre = CUI._ELEMENT_SETTINGS_MAP
    CUI._ELEMENT_SETTINGS_MAP = {
        -- Main frames: "Main Frames" page; dropdown pre-selected to the unit.
        ["player"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "HEALTH BAR",
            preSelectFn = SelectUnitFrame("player"),
            highlightText = "Bar Height",
        },
        ["target"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "HEALTH BAR",
            preSelectFn = SelectUnitFrame("target"),
            highlightText = "Bar Height",
        },
        ["focus"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "HEALTH BAR",
            preSelectFn = SelectUnitFrame("focus"),
            highlightText = "Bar Height",
        },
        -- Mini frames: "Mini Frames" page; mini dropdown pre-selected to the unit.
        ["pet"] = {
            module = "CludesUIUnitFrames",
            page = "Mini Frames",
            sectionName = "HEALTH BAR",
            preSelectFn = CUI._SelectMiniUnit("pet"),
            highlightText = "Bar Height",
        },
        ["targettarget"] = {
            module = "CludesUIUnitFrames",
            page = "Mini Frames",
            sectionName = "HEALTH BAR",
            preSelectFn = CUI._SelectMiniUnit("targettarget"),
            highlightText = "Bar Height",
        },
        ["focustarget"] = {
            module = "CludesUIUnitFrames",
            page = "Mini Frames",
            sectionName = "HEALTH BAR",
            preSelectFn = CUI._SelectMiniUnit("focustarget"),
            highlightText = "Bar Height",
        },
        -- Boss frames live on their own "Boss Frames" page (no unit dropdown).
        ["boss"] = {
            module = "CludesUIUnitFrames",
            page = "Boss Frames",
            sectionName = "HEALTH BAR",
            highlightText = "Bar Height",
        },
        ["classPower"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "CLASS RESOURCE",
            preSelectFn = SelectUnitFrame("player"),
            highlightText = "Enable Class Resource",
        },

        -- Unit-frame cast bars (configured on the Main Frames page, CAST BAR section, per selected unit)
        ["playerCastbar"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "CAST BAR",
            preSelectFn = SelectUnitFrame("player"),
            highlightText = "Show Cast Bar",
        },
        ["targetCastbar"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "CAST BAR",
            preSelectFn = SelectUnitFrame("target"),
            highlightText = "Show Cast Bar",
        },
        ["focusCastbar"] = {
            module = "CludesUIUnitFrames",
            page = "Main Frames",
            sectionName = "CAST BAR",
            preSelectFn = SelectUnitFrame("focus"),
            highlightText = "Show Cast Bar",
        },
        ["petCastbar"] = {
            module = "CludesUIUnitFrames",
            page = "Mini Frames",
            sectionName = "CAST BAR",
            preSelectFn = CUI._SelectMiniUnit("pet"),
            highlightText = "Show Cast Bar",
        },

        -- Resource Bars (no dropdown -- each bar has its own section)
        ["ERB_Health"] = {
            module = "CludesUIResourceBars",
            page = "Class, Power and Health Bars",
            sectionName = "HEALTH BAR",
            highlightText = "Bar Height",
        },
        ["ERB_Power"] = {
            module = "CludesUIResourceBars",
            page = "Class, Power and Health Bars",
            sectionName = "POWER BAR",
            highlightText = "Bar Height",
        },
        ["ERB_ClassResource"] = {
            module = "CludesUIResourceBars",
            page = "Class, Power and Health Bars",
            sectionName = "CLASS RESOURCE BAR",
            highlightText = "Bar Height",
        },
        ["ERB_CastBar"] = {
            module = "CludesUIResourceBars",
            page = "Cast Bar",
            sectionName = "BAR DISPLAY",
            highlightText = "Bar Height",
        },

        -- Action Bars (all share "Bar Display" page; dropdown pre-selected to correct bar)
        ["MainBar"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("MainBar"),
            highlightText = "Icon Size",
        },
        ["Bar2"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar2"),
            highlightText = "Icon Size",
        },
        ["Bar3"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar3"),
            highlightText = "Icon Size",
        },
        ["Bar4"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar4"),
            highlightText = "Icon Size",
        },
        ["Bar5"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar5"),
            highlightText = "Icon Size",
        },
        ["Bar6"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar6"),
            highlightText = "Icon Size",
        },
        ["Bar7"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar7"),
            highlightText = "Icon Size",
        },
        ["Bar8"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar8"),
            highlightText = "Icon Size",
        },
        ["Bar9"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar9"),
            highlightText = "Icon Size",
        },
        ["Bar10"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("Bar10"),
            highlightText = "Icon Size",
        },
        ["StanceBar"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("StanceBar"),
            highlightText = "Icon Size",
        },
        ["PetBar"] = {
            module = "CludesUIActionBars",
            page = "Bar Display",
            sectionName = "LAYOUT",
            preSelectFn = SelectActionBar("PetBar"),
            highlightText = "Icon Size",
        },

        -- Action Bars -- data bars, micro menu and bags (their own tabs, no bar dropdown)
        ["XPBar"] = {
            module = "CludesUIActionBars",
            page = "XP Bar",
            sectionName = "CORE",
            highlightText = "Width",
        },
        ["RepBar"] = {
            module = "CludesUIActionBars",
            page = "Menu, Bags & Rep Bars",
            sectionName = "REPUTATION BAR",
            highlightText = "Width",
        },
        ["FavorBar"] = {
            module = "CludesUIActionBars",
            page = "Menu, Bags & Rep Bars",
            sectionName = "HOUSE FAVOR BAR",
            highlightText = "Width",
        },
        ["MicroBar"] = {
            module = "CludesUIActionBars",
            page = "Menu, Bags & Rep Bars",
            sectionName = "MICRO MENU & BAGS",
        },
        ["BagBar"] = {
            module = "CludesUIActionBars",
            page = "Menu, Bags & Rep Bars",
            sectionName = "MICRO MENU & BAGS",
        },

        -- Aura Buff Reminders
        ["EABR_Reminders"] = {
            module = "CludesUIAuraBuffReminders",
            page = "Auras, Buffs & Consumables",
            sectionName = "DISPLAY",
        },

        -- Quality of Life (FPS + Secondary Stats live on the QoL page's EXTRAS section)
        ["CUI_FPS"] = {
            module = "CludesUIQoL",
            page = "QoL",
            sectionName = "EXTRAS",
            highlightText = "Show FPS Counter",
        },
        ["CUI_SecondaryStats"] = {
            module = "CludesUIQoL",
            page = "QoL",
            sectionName = "EXTRAS",
            highlightText = "Secondary Stat Display",
        },

        -- Battle Res + Bloodlust (bottom of the Quality of Life page)
        ["CUI_CombatAlert"] = {
            module = "CludesUIQoL",
            page = "QoL",
            sectionName = "ALERTS",
            highlightText = "Combat Alert",
        },
        ["CUI_BattleRes"] = {
            module = "CludesUIQoL",
            page = "QoL",
            sectionName = "BATTLE RES",
            highlightText = "Enable BattleRes Icon",
        },
        ["CUI_Bloodlust"] = {
            module = "CludesUIQoL",
            page = "QoL",
            sectionName = "BLOODLUST TRACKER",
            highlightText = "Enable Bloodlust Icon",
        },

        -- Forever Essentials (WoW Forever only): Junk Items sits on the General page
        ["CUI_JunkList"] = {
            module = "CludesUIForeverEssentials",
            page = "General",
            sectionName = "JUNK ITEMS",
            highlightText = "Enable Junk Items Window",
        },

        -- Mythic+ Tools
        ["EMT_MythicTimer"] = {
            module = "CludesUIMythicTimer",
            page = "Mythic+ Timer",
            sectionName = "DISPLAY",
            highlightText = "Scale",
        },
        ["EMT_TargetedSpellBars"] = {
            module = "CludesUIMythicTimer",
            page = "Targeted Spell Bars",
            sectionName = "CAST BARS",
            highlightText = "Enable Cast Bars",
        },
        ["EMT_TargetCastBar"] = {
            module = "CludesUIMythicTimer",
            page = "Target/Focus Bars",
            sectionName = "TARGET CAST BAR",
            highlightText = "Enable Target Cast Bar",
        },
        ["EMT_FocusCastBar"] = {
            module = "CludesUIMythicTimer",
            page = "Target/Focus Bars",
            sectionName = "FOCUS CAST BAR",
            highlightText = "Enable Focus Cast Bar",
        },
        ["EMT_KickBars"] = {
            module = "CludesUIMythicTimer",
            page = "Kick Tracker",
            sectionName = "BARS",
            highlightText = "Show Bars",
        },

        -- Dragon Riding HUD (Blizz UI Enhanced > Dragon Riding page)
        ["EDR_Cluster"] = {
            module = "CludesUIBlizzardSkin",
            page = "Dragon Riding",
            sectionName = "GENERAL",
            highlightText = "Enable Skyriding Bar",
        },

        -- Fixed-position tooltip anchor (Blizz UI Enhanced > Tooltips, Menus & Popups)
        ["CUI_TooltipAnchor"] = {
            module = "CludesUIBlizzardSkin",
            page = "Tooltips, Menus & Popups",
            sectionName = "BLIZZARD TOOLTIP",
            highlightText = "Anchor to Cursor",
        },

        -- Minimap
        ["EBS_Minimap"] = {
            module = "CludesUIMinimap",
            page = "Minimap",
            sectionName = "DISPLAY",
            highlightText = "Size",
        },

        -- Damage Meters: windows use dynamic "EDM_Win<i>" keys and resolve to the shared
        -- "EDM_Win" entry via the cog lookup's prefix fallback (top of the tab, like CDM_).
        ["EDM_Win"] = { module = "CludesUIDamageMeters", page = "Damage Meters" },
        ["EDM_CombatTimer"] = {
            module = "CludesUIDamageMeters",
            page = "Damage Meters",
            sectionName = "STANDALONE COMBAT TIMER",
            highlightText = "Standalone Combat Timer",
        },
        ["EDM_IconHistory"] = {
            module = "CludesUIDamageMeters",
            page = "Spell History",
            sectionName = "ICON HISTORY",
            highlightText = "Enable Icon History",
        },

        -- Raid + Party Frames (separate registered pages/tabs)
        ["RF_RaidFrames"] = {
            module = "CludesUIRaidFrames",
            page = "Raid",
            sectionName = "FRAME SIZES",
            highlightText = "20 Man Frame Width",
        },
        ["RF_PartyFrames"] = {
            module = "CludesUIRaidFrames",
            page = "Party",
            sectionName = "FRAMES",
            highlightText = "Frame Width",
        },

        -- CDM dynamic bars: "CDM_<key>"/"TBB_<idx>" resolve to these shared tab entries
        -- via the cog lookup's prefix fallback; no sectionName/preSelectFn so bars land
        -- at the top of the tab (deliberately undifferentiated).
        ["CDM_"] = { module = "CludesUICooldownManager", page = "CDM Bars" },
        ["TBB_"] = { module = "CludesUICooldownManager", page = "Tracking Bars" },
    }
    if CUI._elemMapPre then
        for key, val in pairs(CUI._elemMapPre) do
            if CUI._ELEMENT_SETTINGS_MAP[key] == nil then CUI._ELEMENT_SETTINGS_MAP[key] = val end
        end
        CUI._elemMapPre = nil
    end

    -- Width Match / Height Match / Anchor To pick modes: only one active at a time; picker mover stored here.
    LM.pickMode = nil -- nil, "widthMatch", "heightMatch", "anchorTo"
    LM.pickModeMover = nil -- the mover that initiated the pick mode
    LM.hoveredMover = nil -- the currently expanded mover (only one at a time)
    LM.anchorDropdownFrame = nil -- lazy-created dropdown for anchor direction selection
    LM.anchorDropdownCatcher = nil -- click-catcher behind anchor dropdown
    LM.growDropdownFrame = nil -- lazy-created dropdown for grow direction selection
    LM.growDropdownCatcher = nil -- click-catcher behind grow dropdown

    -- Cursor speed tracking for hover intent detection (stored on CludesUI to avoid upvalue pressure)
    CUI._unlockCursorX = 0
    CUI._unlockCursorY = 0
    CUI._unlockCursorSpeed = 0 -- pixels/sec at UIParent scale
    CUI._unlockHoverSpeedThresh = 80 * 80 -- squared px/sec threshold (avoids sqrt each frame)
    CUI._unlockHoverIntentDelay = 0.12 -- seconds to wait after settling before expanding

    -------------------------------------------------------------------------------
    --  Split parts (CUI_UnlockMode_*.lua): share the stable names above through
    --  UM, then run the parts here, in their original order. The parts sit in
    --  the addon's private namespace and take it from their own file, never
    --  through UM: a public slot would let another addon wrap a part and reach it.
    -------------------------------------------------------------------------------
    LM.EAB, LM.floor, LM.abs = ABAR, floor, abs
    LM.min, LM.max, LM.sqrt, LM.sin = min, max, sqrt, sin
    LM.round, LM.PP, LM.DeferMoverSync, LM.FONT_PATH = round, Pix, DeferMoverSync, FONT_PATH
    LM.GRID_SPACING = GRID_SPACING
    LM.SNAP_THRESH, LM.MOVER_ALPHA, LM.MOVER_HOVER, LM.MOVER_DRAG =
        SNAP_THRESH, MOVER_ALPHA, MOVER_HOVER, MOVER_DRAG
    LM.BAR_LOOKUP, LM.ALL_BAR_ORDER, LM.GetVisibilityOnly = BAR_LOOKUP, ALL_BAR_ORDER, GetVisibilityOnly
    LM.registeredElements, LM.registeredOrder, LM.RebuildRegisteredOrder, LM.guidePool =
        registeredElements, registeredOrder, RebuildRegisteredOrder, guidePool
    LM.movers, LM.lockAnimFrame, LM.pendingPositions, LM.snapshotPositions =
        movers, lockAnimFrame, pendingPositions, snapshotPositions
    LM.snapshotAnchors, LM.snapshotSizes, LM.snapshotWidthMatch, LM.snapshotHeightMatch =
        snapshotAnchors, snapshotSizes, snapshotWidthMatch, snapshotHeightMatch
    LM.snapshotGrowDirs, LM.GridBaseAlpha, LM.GridCenterAlpha, LM.GridHudAlpha =
        snapshotGrowDirs, GridBaseAlpha, GridCenterAlpha, GridHudAlpha
    LM.GridLabelText, LM.CycleGridMode, LM._blizzOwnedOverlays, LM.SELECT_ELEMENT_ALPHA =
        GridLabelText, CycleGridMode, _blizzOwnedOverlays, SELECT_ELEMENT_ALPHA
    LM.SELECT_ELEMENT_FADE = SELECT_ELEMENT_FADE
    mod.unlockParts.Anchors(LM)
    mod.unlockParts.Positions(LM)
    mod.unlockParts.Tools(LM)
    mod.unlockParts.PointPicker(LM)
    mod.unlockParts.Movers(LM)
    mod.unlockParts.Session(LM)
    mod.unlockParts.Filter(LM)
    mod.unlockParts.Bar(LM)
    local HideAllGuidesAndHighlight, DeselectMover = LM.HideAllGuidesAndHighlight, LM.DeselectMover
    local SortMoverFrameLevels, HideBlizzOwnedOverlays = LM.SortMoverFrameLevels, LM.HideBlizzOwnedOverlays

    -------------------------------------------------------------------------------
    --  Close Unlock Mode -- routes through save/discard logic
    -------------------------------------------------------------------------------
    function mod.CloseUnlockMode(afterFn)
        if not LM.isUnlocked then
            if afterFn then afterFn() end
            return
        end
        mod.RequestClose(false, afterFn) -- triggers popup if there are unsaved changes
    end

    -- Expose for the options page BuildUnlockPage
    -- ns.OpenUnlockMode and ns.CloseUnlockMode are already defined above as
    -- function ns.OpenUnlockMode() and function ns.CloseUnlockMode()
    mod.CloseUnlockMode = mod.CloseUnlockMode

    -- Expose on the global CludesUI so SelectPage can intercept "Unlock Mode"
    if CUI then
        CUI._openUnlockMode = mod.OpenUnlockMode
        function CUI:OpenUnlockMode() mod.OpenUnlockMode() end
    end

    -- Toggle helper + active flag alias used by options pages
    if CUI and not CUI.ToggleUnlockMode then
        function CUI:ToggleUnlockMode()
            if LM.isUnlocked then
                mod.CloseUnlockMode()
            else
                mod.OpenUnlockMode()
            end
        end
        -- Options pages read _unlockActive (set by Open/Close above) since isUnlocked is local.
    end

    -- When the options panel tries to show while unlock mode is active,
    -- close unlock mode first (with save flow), then re-show the panel after.
    if CUI and CUI.RegisterOnShow then
        CUI:RegisterOnShow(function()
            if LM.isUnlocked then
                -- Hide the panel immediately -- it shouldn't show during unlock mode
                local panelFrame = CUI._mainFrame
                if panelFrame then panelFrame:Hide() end
                -- Close unlock mode, then re-open the panel after
                mod.CloseUnlockMode(function() CUI:Toggle() end)
            end
        end)
    end

    -------------------------------------------------------------------------------
    --  Combat auto-suspend / resume: entering combat hides unlock mode UI but
    --  preserves all pending changes; leaving combat re-opens with the same state.
    -------------------------------------------------------------------------------
    local function SuspendForCombat()
        if not LM.isUnlocked then return end
        if LM.PointPicker.Active() then LM.CancelPickMode() end
        LM.combatSuspended = true
        preCombatChanges = LM.hasChanges and true or false
        if CUI._HideFallbackGhosts then CUI._HideFallbackGhosts() end
        if CUI._HideOverrideGhosts then CUI._HideOverrideGhosts() end

        -- Restore objective tracker
        if LM.objTrackerWasVisible then
            local objTracker = _G.ObjectiveTrackerFrame
            if objTracker then
                objTracker:SetAlpha(1)
                local wasEnabled = CUI._GetFFD(objTracker).unlockMouseWasEnabled
                if objTracker.EnableMouse then
                    pcall(objTracker.EnableMouse, objTracker, wasEnabled and true or false)
                end
            end
        end
        -- Re-apply user visibility setting (handles "never" mode for both tracker + bg)
        if _G.CludesUIQuestTracker and _G.CludesUIQuestTracker.UpdateVisibility then
            _G.CludesUIQuestTracker.UpdateVisibility()
        end

        -- Notify beacon reminders to restore
        if _G._CUABR_BeaconRefresh then pcall(_G._CUABR_BeaconRefresh) end

        -- Hide unlock UI without clearing state
        LM.isUnlocked = false
        CUI._unlockActive = false
        CUI._unlockModeActive = false

        -- Override anchors re-engage for the fight (isUnlocked is false now);
        -- ResumeAfterCombat's sweep releases them again for editing.
        if CUI._ReapplyOverrideAnchors then CUI._ReapplyOverrideAnchors() end

        -- Re-check Dragon Riding's real visibility (it force-shows while
        -- _unlockActive is true so it can be edited off-mount; must run AFTER
        -- _unlockActive is cleared above, or UpdateVisibility() still hits that
        -- force-show branch and this call is a no-op).
        if _G._CUDR_UpdateVisibility then pcall(_G._CUDR_UpdateVisibility) end

        if LM.unlockFrame then
            LM.unlockFrame:SetScript("OnUpdate", nil)
            LM.unlockFrame:Hide()
        end
        if LM.logoFadeFrame then
            LM.logoFadeFrame:SetScript("OnUpdate", nil)
            LM.logoFadeFrame:Hide()
        end
        if LM.openAnimFrame then LM.openAnimFrame:Hide() end
        if lockAnimFrame then lockAnimFrame:Hide() end
        if LM.gridFrame then LM.gridFrame:Hide() end
        if LM.hudFrame then LM.hudFrame:Hide() end
        if LM.unlockTipFrame then
            LM.unlockTipFrame:SetScript("OnUpdate", nil)
            LM.unlockTipFrame:Hide()
        end
        DeselectMover()
        for _, m in pairs(movers) do
            m:Hide()
        end
        HideAllGuidesAndHighlight()
        HideBlizzOwnedOverlays()
        if LM.arrowKeyFrame then LM.arrowKeyFrame:Hide() end
        LM.selectedMover = nil
        LM.selectElementPicker = nil

        -- Restore action bar alpha from saved settings (so bars are usable during combat)
        if ABAR and ABAR.RefreshMouseover then ABAR:RefreshMouseover() end
    end

    local function ResumeAfterCombat()
        if not LM.combatSuspended then return end
        -- A pull again inside the resume delay: stay suspended, so the end of that
        -- combat resumes the session (its own PLAYER_REGEN_ENABLED calls this again).
        if InCombatLockdown() then return end
        LM.combatSuspended = false

        -- Nothing can be edited while the session is hidden: whatever moved during
        -- the fight (bars rebuilding, anchored elements following them) is not a
        -- change of the user's, so the session keeps the mark it had before.
        LM.hasChanges = preCombatChanges

        -- Re-enter unlock mode but skip snapshot/reset since we preserved state
        LM.isUnlocked = true
        CUI._unlockActive = true
        CUI._unlockModeActive = true
        if CUI._RefreshFallbackGhosts then CUI._RefreshFallbackGhosts() end
        -- Release override anchors back to baseline for editing (isUnlocked true).
        if CUI._ReapplyOverrideAnchors then CUI._ReapplyOverrideAnchors() end
        if CUI._RefreshOverrideGhosts then CUI._RefreshOverrideGhosts() end

        -- Re-check Dragon Riding's visibility now that _unlockActive is true again:
        -- SuspendForCombat's re-check hid the HUD for a dismounted player, and without
        -- this mirror call the force-show branch never re-evaluates on resume -- the
        -- element would stay invisible (and uneditable) until a mount/dismount re-runs UpdateVisibility.
        if _G._CUDR_UpdateVisibility then pcall(_G._CUDR_UpdateVisibility) end

        -- Re-hide objective tracker
        local objTracker = _G.ObjectiveTrackerFrame
        if objTracker and objTracker:IsShown() then
            LM.objTrackerWasVisible = true
            objTracker:SetAlpha(0)
            if objTracker.EnableMouse then pcall(objTracker.EnableMouse, objTracker, false) end
        end
        local qtBg = _G.CludesUIQTBackground
        if qtBg then qtBg:SetAlpha(0) end

        -- Notify beacon reminders to hide
        if _G._CUABR_BeaconRefresh then pcall(_G._CUABR_BeaconRefresh) end

        -- Re-show unlock UI
        if LM.arrowKeyFrame then LM.arrowKeyFrame:Show() end
        if LM.unlockFrame then
            LM.unlockFrame:Show()
            LM.unlockFrame:SetAlpha(1)
        end
        if LM.gridFrame and LM.gridMode ~= "disabled" then LM.gridFrame:Show() end
        if LM.hudFrame then
            LM.hudFrame:Show()
            -- A combat cut mid-animation left the badge waiting for the emblem.
            if LM.hudFrame._badgeLogo then LM.hudFrame._badgeLogo:SetAlpha(1) end
        end

        -- Mirrors the OpenUnlockMode entry strip: provider enter hooks first (CDM's
        -- Additional Bar Offset may have re-applied to un-anchored bars during the
        -- combat-suspend window)...
        CUI.RunAnchorShiftEnters()
        -- ...then strip any temporary anchor-target shift (e.g. "Shift Elements if
        -- No Resource"/"...if No Bars") that may have re-applied while
        -- _unlockActive was false. _unlockActive is true again above, so the
        -- providers return 0 and this snaps shifted children back BEFORE the movers
        -- re-sync below capture their positions.
        if CUI.AnchorShiftWantsApply() and CUI.ReapplyAllUnlockAnchors then
            -- Force edge-preservation so custom-growth anchored bars snap to their fixed
            -- growth edge, not the center-offset position. Reset via pcall so it can't leak.
            CUI._reapplyForceEdgePreserve = true
            pcall(CUI.ReapplyAllUnlockAnchors)
            CUI._reapplyForceEdgePreserve = false
        end

        -- Re-sync all movers (Sync shows live ones and hides stale/hidden ones).
        for _, m in pairs(movers) do
            m:Sync()
            if m:IsShown() then m:SetAlpha(LM.darkOverlaysEnabled and 1 or MOVER_ALPHA) end
        end
        SortMoverFrameLevels()
        if LM.unlockFrame and LM.unlockFrame._anchorLineDriver then
            LM.unlockFrame._anchorLineDriver:Show()
        end
        if LM.unlockFrame and LM.unlockFrame._anchorLineFrame then LM.unlockFrame._anchorLineFrame:Show() end
        -- Deferred: re-apply CENTER anchor to all bar frames so resizes grow
        -- symmetrically from center rather than from whatever corner anchor
        -- was left by a previous drag or addon rebuild.
        C_Timer.After(0, function()
            for bk, m in pairs(movers) do
                if not m._dragging then CUI.RecenterBarAnchor(bk) end
            end
        end)
    end

    do
        local combatFrame = CreateFrame("Frame")
        combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        combatFrame:SetScript("OnEvent", function(_, evt)
            if evt == "PLAYER_REGEN_DISABLED" then
                SuspendForCombat()
            elseif evt == "PLAYER_REGEN_ENABLED" then
                -- Small delay to let combat lockdown fully clear
                C_Timer.After(0.5, ResumeAfterCombat)
            end
        end)
    end
end -- end deferred init
