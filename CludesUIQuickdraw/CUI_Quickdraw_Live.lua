if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Quickdraw_Live.lua - the palette the player actually opens.
--
--  Holds the live view, the secure header the snippets run under, the
--  full-screen wheel catcher for the fan layouts, the per-frame update while
--  a palette is up, and mod.Open / mod.Close.
--
--  Everything it needs from the files before it arrives through
--  mod._qdInternals ("Inner"); setters registered there hand it the frames
--  other files create.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._qdInternals
-- An earlier Quickdraw file failed to load: stay out of the way.
if not Inner or Inner.broken then return end
Inner.broken = true -- cleared at the end, once this file has fully loaded

local GetCursorPosition, InCombatLockdown, GetTime = GetCursorPosition, InCombatLockdown, GetTime

local P = Inner.P
local LIVE_STRATA, liveFrame = Inner.LIVE_STRATA, Inner.liveFrame
local LATCH_TIMEOUT, OPEN_TIMEOUT = Inner.LATCH_TIMEOUT, Inner.OPEN_TIMEOUT
local secureButtons = Inner.secureButtons

-- Frames other files own, kept current through their setter lists.
local liveView, scrollCatcher, cancelButton
table.insert(Inner.liveViewSetters, function(v) liveView = v end)
table.insert(Inner.scrollCatcherSetters, function(v) scrollCatcher = v end)
table.insert(Inner.cancelButtonSetters, function(v) cancelButton = v end)

local secureHeader
local openedAt = 0 -- GetTime() of the current open

local function CreateLiveView()
    if not liveView then
        Inner.SetLiveView(mod.CreatePaletteView(UIParent, { frame = liveFrame, live = true }))
        local frame = liveView:GetFrame()
        frame:SetFrameStrata(LIVE_STRATA)
        frame:Hide()
    end
    return liveView
end

-- The handler every secure snippet here is wrapped under.
local function EnsureSecureHeader()
    secureHeader = secureHeader
        or CreateFrame("Frame", "CUIQuickdrawSecureHeader", UIParent, "SecureHandlerBaseTemplate")
    return secureHeader
end

-------------------------------------------------------------------------------
--  The wheel
--
--  The fan layouts are stepped with the mouse wheel, which is otherwise
--  camera zoom. A frame only hears the wheel while the cursor is over it, and
--  a pinned (Fixed Position) strip can sit anywhere, so the catcher covers
--  the whole screen. It takes the WHEEL only, never mouse clicks: a
--  full-screen click target would block the world and the very presses the
--  secure path relies on. (An override binding on MOUSEWHEELUP/DOWN cannot
--  work: claiming those is protected, and palettes are opened in combat.)
--
--  A live strip's position may only be written from secure code in combat,
--  so this snippet is the one place a wheel tick moves it. The options
--  preview steps its own insecure view instead.
-------------------------------------------------------------------------------
local WHEEL_SNIPPET = [==[
    if not self:GetAttribute("eqdOpen") then
        -- Nothing is open (a zone change or a taxi swallowed the key release):
        -- stop eating zoom. Costs the player this one tick.
        self:Hide()
        return false
    end
    local n = tonumber(self:GetAttribute("eqdShown")) or 0
    if n < 1 then return false end

    -- Up goes towards earlier entries: up the screen for a vertical strip,
    -- reading order for a horizontal one.
    local delta = offset
    if self:GetAttribute("eqdInvert") then delta = -delta end
    local step = (delta <= 0) and 1 or -1

    -- The press starts this at 1 (the entry the strip opens on); a tick with
    -- no press behind it starts from 1 too.
    local t = (tonumber(self:GetAttribute("eqdFanTarget")) or 1) + step
    self:SetAttribute("eqdFanTarget", t)

    -- With hover selection on, a tick slides a different entry under a still
    -- pointer, and no motion event will report it. So the armed entry is
    -- worked out again from the pointer's lattice cell, as the gates' OnEnter
    -- does. A pointer off the strip leaves the arming as it was (sticky reach).
    local oi = self:GetAttribute("eqdOwnerIdx")
    local btn = oi and self:GetFrameRef("btn" .. oi)
    if not (btn and btn:GetAttribute("eqdFanMouse")) then return false end
    local ui = self:GetFrameRef("ui")
    local x, y
    if ui then x, y = ui:GetMousePosition() end
    if not x then return false end

    local cx, cy = x * ui:GetWidth(), y * ui:GetHeight()
    local s = tonumber(btn:GetAttribute("eqdScale")) or 1
    if s <= 0 then s = 1 end
    -- The strip's centre: the fixed position, or where it opened (the cursor).
    local hx, hy
    if btn:GetAttribute("eqdFixed") then
        hx = ui:GetWidth() * 0.5 + (tonumber(btn:GetAttribute("eqdPosX")) or 0)
        hy = ui:GetHeight() * 0.5 + (tonumber(btn:GetAttribute("eqdPosY")) or 0)
    else
        hx = tonumber(btn:GetAttribute("eqdGX"))
        hy = tonumber(btn:GetAttribute("eqdGY"))
    end
    local pitch = tonumber(btn:GetAttribute("eqdPitch")) or 0
    if not hx or pitch <= 0 then return false end

    -- Along and across the strip, in strip units.
    local along, across = (cx - hx) / s, (cy - hy) / s
    if not btn:GetAttribute("eqdFanHoriz") then
        along, across = -across, along
    end
    local band = tonumber(btn:GetAttribute("eqdFanBand")) or 0
    local win = tonumber(btn:GetAttribute("eqdFanWin")) or 0
    local d = floor(along / pitch + 0.5) -- slots from the centre
    if abs(across) <= band and abs(along - d * pitch) <= band
       and abs(d) <= win + 0.5 and d * 2 <= n and -d * 2 < n then
        btn:SetAttribute("eqdArmed",
            tonumber(btn:GetAttribute("eqdClaimAt" .. (((t - 1 + d) % n) + 1))))
    end
    return false
]==]

local function EnsureScrollCatcher()
    if scrollCatcher then return scrollCatcher end
    local catcher = CreateFrame("Frame", "CUIQuickdrawScrollCatcher", UIParent, "SecureHandlerBaseTemplate")
    catcher:SetAllPoints(UIParent)
    catcher:SetFrameStrata(LIVE_STRATA)
    catcher:SetFrameLevel(1)
    catcher:EnableMouseWheel(true)
    -- The snippet reads the cursor through UIParent, as every snippet does.
    SecureHandlerSetFrameRef(catcher, "ui", UIParent)
    SecureHandlerWrapScript(catcher, "OnMouseWheel", EnsureSecureHeader(), WHEEL_SNIPPET)
    catcher:Hide()
    Inner.SetScrollCatcher(catcher)
    return catcher
end

-------------------------------------------------------------------------------
--  Each frame while open
-------------------------------------------------------------------------------
-- Flick-ahead, for the arc: the palette can stay invisible for `delay`
-- seconds after the press and fade in over `fade`, so a quick flick never
-- shows a menu at all. Only the DRAWING waits; selection runs from the first
-- frame. Both are 0 now: the slam-open is the arc's reveal and has to show
-- from the press. Fans always draw at once (they must be seen to be steered).
local FLICK_DELAY, FLICK_FADE = 0, 0

local function FlickAlpha()
    if liveView:IsFan() then return 1 end
    local t = GetTime() - openedAt
    if t <= FLICK_DELAY then return 0 end
    if FLICK_FADE <= 0 or t >= FLICK_DELAY + FLICK_FADE then return 1 end
    return (t - FLICK_DELAY) / FLICK_FADE
end

-- Nothing else sets the palette's alpha, so the same value is never set
-- twice (past the fade, every frame would). Moving the pointer away never
-- dims it: the selection clearing says so instead.
local shownAlpha
local function UpdateAlpha()
    local a = FlickAlpha()
    if a ~= shownAlpha then
        shownAlpha = a
        liveView:GetFrame():SetAlpha(a)
    end
end

-- A palette left open closes itself after a while (a lost key release).
-- A latched one (opened with no key held) gets longer, and none closes in
-- combat: closing a latched menu has to release bindings and gates, all of
-- them protected, so it waits for the fight to end (this keeps ticking to
-- notice). The latch is read off the button, which is the snippet's answer;
-- reading an attribute is allowed in combat.
local function TimedOut(now)
    local button = secureButtons[liveView:GetPaletteIndex()]
    local latched = button and button:GetAttribute("eqdLatched")
    if latched and InCombatLockdown() then return false end
    return now - openedAt > (latched and LATCH_TIMEOUT or OPEN_TIMEOUT)
end

local function OnUpdate(_, elapsed)
    local now = GetTime()
    if TimedOut(now) then
        mod.Close()
        return
    end
    if not liveView:SteerUnchanged() then
        if liveView:IsPointerLayout() then
            liveView:AdvanceGrid()
        elseif liveView:IsFan() then
            liveView:AdvanceFan(elapsed)
        else
            liveView:AdvanceArc()
        end
    end
    -- These run every frame, steered or not: the alpha is time-based, a
    -- modifier can go down without the pointer moving, pending icons load
    -- in, and the connector line grows and sweeps under a still pointer.
    UpdateAlpha()
    liveView:AdvanceLiveIcons()
    liveView:AdvancePendingIcons()
    liveView:AdvanceNeedle(now)
    -- Last: steering repaints alphas flat, and the slam owns the final word while it runs.
    liveView:AdvanceSlam(now)
end

-- The mount tint's events (PaletteView:RefreshMountTints): mount usability,
-- the minimap's indoor/outdoor zoom switch (a doorway) and combat. Listened
-- to only while a live menu with a mount entry is up.
local MOUNT_EVENTS = {
    "MOUNT_JOURNAL_USABILITY_CHANGED",
    "MINIMAP_UPDATE_ZOOM",
    "PLAYER_REGEN_DISABLED",
    "PLAYER_REGEN_ENABLED",
}
local mountWatch
local function WatchMounts(on)
    if on and not mountWatch then
        mountWatch = CreateFrame("Frame")
        mountWatch:SetScript("OnEvent", function()
            if liveView and liveView:GetFrame():IsShown() then liveView:RefreshMountTints() end
        end)
    end
    if mountWatch then
        for _, event in ipairs(MOUNT_EVENTS) do
            if on then
                mountWatch:RegisterEvent(event)
            else
                mountWatch:UnregisterEvent(event)
            end
        end
    end
end

-- At the palette's fixed position (Fixed Position mode, or forceFixed), or
-- at the cursor. The view has already been laid out for this palette, so a
-- pinned palette and a cursor one can share a profile. forceFixed has no
-- caller now; on-screen drag positioning will need it.
local function Place(forceFixed)
    local p = liveView:P()
    local frame = liveView:GetFrame()
    frame:ClearAllPoints()
    if forceFixed or p.centerMode == "SCREEN" then
        local s = p.scale or 1
        if s == 0 then s = 1 end
        frame:SetPoint("CENTER", UIParent, "CENTER", (p.posX or 0) / s, (p.posY or 0) / s)
    else
        local scale = frame:GetEffectiveScale()
        local x, y = GetCursorPosition()
        frame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / scale, y / scale)
    end
end

-- The first selection for each layout.
local function StartSelection()
    liveView:ArmMovementGate()
    if liveView:IsPointerLayout() then
        -- Grid: nothing until the pointer moves; straying a cell from every
        -- entry deselects again.
        liveView:AdvanceGrid(true)
        liveView:SetSelection(nil)
    elseif liveView:IsFan() then
        -- Fan: opens centred on entry 1, already selected, so the first tick
        -- moves by one and entry 1 needs no scrolling. Not when the palette
        -- is empty, and not when hover selection (Select Action with Mouse)
        -- meets a pinned strip, which may open nowhere near the pointer: the
        -- first hover test decides there.
        liveView.fanTarget, liveView.fanVisual = 1, 1
        liveView:ApplyFanGeometry()
        local p = liveView:P()
        local hoverOnly = (p and p.fanMouseSelect) ~= false
        local pinned = p and p.centerMode == "SCREEN"
        local first = liveView:ShownCount() > 0 and not (hoverOnly and pinned)
        liveView:SetSelection(first and 1 or nil)
    else
        -- Arc: drawn through the same pass as every later frame (even, with
        -- nothing selected), and the slam-open starts now, so this very
        -- frame shows the launch positions.
        liveView:AdvanceArc()
        liveView._slamT0 = openedAt
        liveView:AdvanceSlam(openedAt)
    end
end

function mod.Open(paletteIndex)
    local profile = P()
    if not profile or not profile.enabled then return end
    CreateLiveView()
    liveView:Layout(paletteIndex)
    Place()
    -- After placing: which side the caption hangs on depends on where the
    -- palette landed, which at the cursor differs every time.
    liveView:PlaceHubText()
    openedAt = GetTime()
    StartSelection()
    -- The alpha before the first frame, or the last open's would flash.
    UpdateAlpha()
    local frame = liveView:GetFrame()
    frame:SetScript("OnUpdate", OnUpdate)
    frame:Show()
    WatchMounts(liveView:HasMountCells())
end

-------------------------------------------------------------------------------
--  Closing
-------------------------------------------------------------------------------
-- Gives ESCAPE back to the game menu. The release snippet does this on an
-- ordinary close; this covers closes with no release (the timeout, a zone
-- change), open or not. Protected in combat, so PLAYER_REGEN_ENABLED tries
-- again: an ESCAPE left bound to a closed palette is a dead key.
local function ReleaseEscape()
    if cancelButton and not InCombatLockdown() then ClearOverrideBindings(cancelButton) end
end

-- Puts away the rest a release would (the scroll catcher, the ownership
-- stamp, the arming gates). Set by CUI_Quickdraw_Runtime.lua, which also
-- remembers a close combat refused for PLAYER_REGEN_ENABLED.
local ReleaseSecureState

function mod.Close()
    if not liveView then return end
    local frame = liveView:GetFrame()
    if not frame:IsShown() then
        ReleaseEscape()
        return
    end
    frame:SetScript("OnUpdate", nil)
    frame:Hide()
    WatchMounts(false)
    ReleaseSecureState(liveView:GetPaletteIndex())
    ReleaseEscape()
    -- Both together: a fan centre left behind with no target reads as a
    -- settle that never ends, and SteerUnchanged would then deny every later
    -- open (any layout) its per-frame skip. The next fan open seeds both.
    liveView.fanTarget, liveView.fanVisual = nil, nil
    liveView:SetSelection(nil)
end

Inner.CreateLiveView, Inner.EnsureScrollCatcher = CreateLiveView, EnsureScrollCatcher
Inner.EnsureSecureHeader, Inner.ReleaseEscape = EnsureSecureHeader, ReleaseEscape
Inner.SetReleaseSecureState = function(frame) ReleaseSecureState = frame end
Inner.broken = false
