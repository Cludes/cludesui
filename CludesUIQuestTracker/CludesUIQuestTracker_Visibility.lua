if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIQuestTracker_Visibility.lua - when Blizzard's tracker shows, and
--  our background behind it.
--
--  Rules that hold throughout (each was learned from a taint report):
--    1. Never SetScript on ObjectiveTrackerFrame: HookScript only.
--    2. Never walk its children to EnableMouse, and never SetParent,
--       SetPoint or Hide this Edit Mode frame from our code in a way that
--       taints its container (its show and size handlers mark the container
--       dirty under our taint). Hidden means alpha on the frame, plus mouse
--       off on the NAMED click catchers Blizzard hangs off each block
--       (EQT.ApplyTrackerMouse, in the Skin file), and only those we switched
--       off are switched back on.
--    3. Edit Mode owns the position.
-------------------------------------------------------------------------------
local _, mod = ...
local EQT = mod.EQT

local suppressed = false -- another module hides the tracker (_CUQT_SetSuppressed)
local background -- our frame behind the tracker (made in InitVisibility)

local function Tracker()
    return _G.ObjectiveTrackerFrame
end

-- Blizzard's quest icons stick out 13px left of the tracker: the background
-- covers them, keeping its 6px of room where they are off.
local function BackgroundLeft()
    return EQT.Cfg("showQuestIcons") and -19 or -6
end

-- Where the background's top edge goes. With "Hide All Objectives" on, the
-- tracker's header is faded out but Blizzard still keeps its room above the
-- first module (the tracker's top does not move up), so the background
-- starts at the header's bottom instead of leaving that gap. Returns the
-- frame and "TOP" or "BOTTOM" (the caller adds LEFT or RIGHT).
local function BackgroundTop()
    local otf = Tracker()
    if not otf then
        return nil, "TOP"
    end
    if EQT.ShouldHideMasterHeader and EQT.ShouldHideMasterHeader() then
        local header = otf.HeaderMenu or otf.Header
        if header then
            return header, "BOTTOM"
        end
    end
    return otf, "TOP"
end

-------------------------------------------------------------------------------
--  Hidden by place: always in arenas; in raids by "Hide When In Raid":
--  "always", "never", or "boss" (the default: during encounters only).
-------------------------------------------------------------------------------
local inEncounter = false
-- The instance type, kept from the zone events: reading it every time showed
-- in idle profiles (the shared mouseover check asks about 7 times a second).
local instanceType = select(2, GetInstanceInfo()) or "none"

local function HiddenByPlace()
    if instanceType == "arena" then
        return true
    end
    if instanceType ~= "raid" then
        return false
    end
    local mode = EQT.DB() and EQT.DB().hideInRaidMode
    if mode == "always" then
        return true
    elseif mode == "never" then
        return false
    end
    return inEncounter
end

-- Whether the tracker is really on screen now. IsShown alone is not enough:
-- in combat HardHide can only fade it (Show and Hide are protected on this
-- Edit Mode frame), so it stays "shown" while invisible. Everything that
-- decides about our background asks this; separate partial checks once let
-- the background flicker back in during combat.
local function TrackerIsVisible(otf)
    return otf ~= nil and otf:IsShown() and otf:GetAlpha() > 0 and not HiddenByPlace()
end
EQT.TrackerIsVisible = TrackerIsVisible

-- While the tracker is hidden (raids, arenas, M+, suppression) the module's
-- event frames stop listening, so quest events cause no skin or layout work.
-- They listen again when it shows, and catch up through their
-- PLAYER_ENTERING_WORLD handler. Every frame joins EQT._eventFrames at load
-- or in the login set-up, before the first visibility pass.
local eventsStopped = false
local function StopEvents()
    if eventsStopped then
        return
    end
    eventsStopped = true
    for _, frame in ipairs(EQT._eventFrames or {}) do
        frame:UnregisterAllEvents()
    end
end
local function ResumeEvents()
    if not eventsStopped then
        return
    end
    eventsStopped = false
    if not (EQT._eventFrames and EQT._eventRegistrations) then
        return
    end
    for i, frame in ipairs(EQT._eventFrames) do
        local events = EQT._eventRegistrations[i]
        if events then
            local catchUp
            for _, event in ipairs(events) do
                frame:RegisterEvent(event)
                catchUp = catchUp or event == "PLAYER_ENTERING_WORLD"
            end
            local onEvent = catchUp and frame:GetScript("OnEvent")
            if onEvent then
                onEvent(frame, "PLAYER_ENTERING_WORLD")
            end
        end
    end
end

-- Other modules' hide, through the normal visibility pass so it combines
-- with the player's own visibility settings.
function EQT.ApplySuppression(on)
    suppressed = on and true or false
    if EQT.UpdateVisibility then
        EQT.UpdateVisibility()
    end
end

-- Show and Hide on this Edit Mode frame go through protected functions, so
-- in combat they are blocked, and the raid auto-hide fires right at combat
-- start (vehicle bosses). In combat it is faded instead, with the block
-- click catchers switched off by name (fading alone left them clickable);
-- the shared visibility pass at combat end does the real Hide.
local function HardHide(otf)
    if InCombatLockdown() then
        otf:SetAlpha(0)
        if EQT.ApplyTrackerMouse then
            EQT.ApplyTrackerMouse(false)
        end
    else
        otf:SetAlpha(1) -- undo a combat fade before hiding
        otf:Hide()
    end
end

local hooksSet = false
local function HookShow()
    if hooksSet then
        return
    end
    local otf = Tracker()
    if not otf then
        return
    end
    hooksSet = true
    -- Hidden by place: hidden again whenever Blizzard shows it. Runs before
    -- other Show hooks (they stack); the M+ Timer has a similar one for keys.
    hooksecurefunc(otf, "Show", function(self)
        if not suppressed and HiddenByPlace() then
            HardHide(self)
        end
    end)
    -- The background follows the tracker, whoever hides it (us, the M+ Timer,
    -- Blizzard). OnShow can come after the M+ Timer's hook already hid it
    -- again, so the resize checks visibility itself.
    otf:HookScript("OnHide", function()
        if background then
            background:Hide()
        end
    end)
    otf:HookScript("OnShow", function()
        if suppressed then
            return
        end
        if EQT.ResizeBGToContent then
            EQT.ResizeBGToContent()
        end
        if EQT.QueueResize then
            EQT.QueueResize()
        end
    end)
end

local function UpdateVisibility()
    HookShow()
    local byPlace = HiddenByPlace()
    if suppressed or byPlace then
        StopEvents()
    else
        ResumeEvents()
    end
    local otf = Tracker()
    if not otf then
        return
    end
    -- Hidden by place: a real Hide, and the Show hook keeps it hidden.
    if byPlace then
        HardHide(otf)
        if background then
            background:Hide()
        end
        return
    end
    -- Show is protected in combat like Hide; the end-of-combat pass shows it.
    if not otf:IsShown() and not InCombatLockdown() then
        otf:Show()
    end

    -- The player's settings: enabled, the visibility mode and the hide
    -- options, as true / false / "mouseover" (the hover check raises it).
    local vis = true
    if CludesUI and CludesUI.EvalVisibility then
        vis = CludesUI.EvalVisibility(EQT.DB())
    end
    local alpha = (suppressed or vis == false or vis == "mouseover") and 0 or 1
    otf:SetAlpha(alpha)
    if background then
        background:SetAlpha(alpha)
    end
    -- Alpha does not stop clicks: an invisible tracker's blocks would take
    -- clicks meant for the world.
    if EQT.ApplyTrackerMouse then
        EQT.ApplyTrackerMouse(alpha > 0)
    end
    -- The resize decides whether the background shows (by real content);
    -- showing it here would bring back an empty one.
    if EQT.ResizeBGToContent then
        EQT.ResizeBGToContent()
    end
end
EQT.UpdateVisibility = UpdateVisibility

-- The options once rebuilt a state driver through this; it stays for them.
function EQT.RefreshStateDriver()
    UpdateVisibility()
end

-------------------------------------------------------------------------------
--  The background: our own frame under UIParent, on the tracker's bounds.
--  Never a child of ObjectiveTrackerFrame, which keeps us off its secure
--  tree. Colour and alpha from bgR/G/B/Alpha; a 1px accent line on top.
-------------------------------------------------------------------------------
-- Anchors f's top-left and top-right to the tracker's top (see BackgroundTop).
local function PinTop(frame, anchor, side)
    frame:SetPoint("TOPLEFT", anchor, side .. "LEFT", BackgroundLeft(), 0)
    frame:SetPoint("TOPRIGHT", anchor, side .. "RIGHT", 11, 0)
end

local function MakeBackground()
    if background then
        return background
    end
    -- The stock styles keep Blizzard's own panel: no background of ours.
    if EQT.Blizz() then
        return nil
    end
    local otf = Tracker()
    if not otf then
        return nil
    end
    background = CreateFrame("Frame", "CludesUIQTBackground", UIParent)
    background:SetFrameStrata(otf:GetFrameStrata() or "MEDIUM")
    background:SetFrameLevel(math.max(0, otf:GetFrameLevel() - 1))
    local anchor, side = BackgroundTop()
    anchor = anchor or otf
    -- 30px tall until there is content; the resize anchors the bottom.
    background:SetPoint("TOPLEFT", anchor, side .. "LEFT", BackgroundLeft(), 0)
    background:SetPoint("BOTTOMRIGHT", anchor, side .. "RIGHT", 11, -30)
    local fillTex = background:CreateTexture(nil, "BACKGROUND")
    fillTex:SetAllPoints()
    background._tex = fillTex
    -- The top line spans the tracker's width whatever the background's padding.
    local line = background:CreateTexture(nil, "OVERLAY")
    PinTop(line, anchor, side)
    background._divider = line
    return background
end

-- The top line: one physical pixel tall, in the accent colour.
local function PaintTopLine()
    local line = background and background._divider
    if not line then
        return
    end
    if EQT.Cfg("showTopLine") == false then
        line:Hide()
        return
    end
    local core = CludesUI and CludesUI.PP
    local panel = CludesUI and CludesUI.PanelPP
    if panel and panel.DisablePixelSnap then
        panel.DisablePixelSnap(line)
    end
    local perfect = (core and core.perfect) or (panel and panel.mult) or 1
    local otf = Tracker()
    local scale = (otf and otf.GetEffectiveScale and otf:GetEffectiveScale()) or 1
    line:SetHeight((scale and scale > 0) and (perfect / scale) or (panel and panel.mult) or 1)
    local accent = CludesUI and CludesUI.CLUDES_GREEN
    line:SetColorTexture(
        (accent and accent.r) or 0.298,
        (accent and accent.g) or 0.788,
        (accent and accent.b) or 0.9414,
        1
    )
    line:Show()
end

-- The module at the bottom of the tracker, for the background's bottom.
-- References only, no coordinates: Blizzard's block geometry is a secret
-- value once our code is tainted, and comparing one errors. The container
-- stacks the shown modules in order, so the last shown one is lowest (the
-- frame Blizzard anchors its own background to).
local function LowestModule()
    local otf = Tracker()
    local modules = otf and (otf.modules or otf.MODULES)
    if not modules then
        return nil
    end
    local widgets = _G.UIWidgetObjectiveTracker
    local lowest
    for _, module in ipairs(modules) do
        -- Not the widget tracker: its blocks share Blizzard's widget pool
        -- with tooltips and area POIs, and ANY call on them (GetBottom,
        -- IsShown, GetObjectType) taints that pool ("attempt to compare a
        -- secret number value" later in LayoutFrame.lua). The Skin file's
        -- HookTracker refuses them for the same reason. The scenario tracker
        -- counts (zone events, delves, dungeons: content the background
        -- belongs behind; a fixed frame, not pooled); a key's blocks are kept
        -- bare by the M+ check in the resize. A module that has nothing to
        -- show is hidden, so IsShown is the content check. The module, not
        -- its last block: blocks return to the pool on collapse, which clears
        -- their points and would drag the background along.
        if
            module ~= widgets
            and type(module) == "table"
            and module.IsShown
            and module.GetObjectType
            and module:IsShown()
        then
            lowest = module
        end
    end
    return lowest
end

-- Layout events come in bursts: all of one tick become one resize. If the
-- lowest module keeps moving (Blizzard's collapse animation), each move
-- queues one more, never a continuous OnUpdate.
local resizeQueued = false
local function QueueResize()
    -- No background (not made yet, or a stock style): nothing to resize.
    if resizeQueued or not background then
        return
    end
    resizeQueued = true
    C_Timer.After(0.05, function()
        resizeQueued = false
        if EQT.ResizeBGToContent then
            EQT.ResizeBGToContent()
        end
    end)
end
EQT.QueueResize = QueueResize

local function HideBackground()
    if background:IsShown() then
        background:Hide()
    end
end

local function ResizeBGToContent()
    local otf = Tracker()
    if not background or not otf then
        return
    end
    -- The tracker is hidden (by place, by Blizzard, faded in combat).
    if not TrackerIsVisible(otf) then
        HideBackground()
        return
    end
    -- In a running key the tracker shows Blizzard's scenario blocks (the
    -- objectives, the trash count), not quests to dress; this also stops the
    -- background flashing as the key starts.
    if
        C_ChallengeMode
        and C_ChallengeMode.IsChallengeModeActive
        and C_ChallengeMode.IsChallengeModeActive()
    then
        HideBackground()
        return
    end
    local lowest = LowestModule()
    if not lowest then
        -- For a frame while blocks are recycled (track, untrack, collapse)
        -- nothing shows: keep the last size, and look again shortly instead
        -- of blinking. With no content ever, hide.
        if not background._lastLowest then
            HideBackground()
        elseif not background._hideCheck then
            background._hideCheck = true
            C_Timer.After(0.2, function()
                background._hideCheck = nil
                if EQT.ResizeBGToContent then
                    EQT.ResizeBGToContent()
                end
            end)
        end
        return
    end
    background._hideCheck = nil
    if not background:IsShown() then
        background:Show()
    end
    local anchor, side = BackgroundTop()
    anchor = anchor or otf
    if background._divider then
        background._divider:ClearAllPoints()
        PinTop(background._divider, anchor, side)
    end
    -- A module is as tall as its blocks plus bottomSpacing, so its bottom is
    -- that far below the last block: adding it back keeps the 15px margin
    -- without reading a coordinate.
    local spacing = lowest.bottomSpacing
    if (issecretvalue and issecretvalue(spacing)) or type(spacing) ~= "number" then
        spacing = 0
    end
    background:ClearAllPoints()
    PinTop(background, anchor, side)
    background:SetPoint("BOTTOM", lowest, "BOTTOM", 0, spacing - 15)
    background._lastLowest = lowest
end
EQT.ResizeBGToContent = ResizeBGToContent

function EQT.ApplyBackground()
    if not MakeBackground() then
        return
    end
    local conf = EQT.DB()
    background._tex:SetColorTexture(conf.bgR or 0, conf.bgG or 0, conf.bgB or 0, conf.bgAlpha or 0.5)
    ResizeBGToContent()
    PaintTopLine()
end

-- Force Quest Tracker on Screen: keeps the tracker inside the screen when
-- on, lets it be dragged off when off.
function EQT.ApplyForceOnScreen()
    local otf = Tracker()
    if otf then
        local conf = EQT.DB()
        otf:SetClampedToScreen(conf and conf.forceOnScreen == true or false)
    end
end

-- The mouseover check's target: the tracker and our background as one, so
-- hovering either fades both in.
local function MouseoverTarget(otf)
    local function Mouse(on)
        if EQT.ApplyTrackerMouse then
            EQT.ApplyTrackerMouse(on)
        end
    end
    return {
        IsShown = function()
            return TrackerIsVisible(otf)
        end,
        IsMouseOver = function()
            return (otf and otf:IsMouseOver())
                or (background and background:IsShown() and background:IsMouseOver())
                or false
        end,
        GetRect = function()
            if background and background:IsShown() then
                return background:GetRect()
            end
            if otf then
                return otf:GetRect()
            end
        end,
        GetEffectiveScale = function()
            return otf and otf:GetEffectiveScale() or 1
        end,
        SetAlpha = function(_, a)
            if otf then
                otf:SetAlpha(a)
            end
            if background then
                background:SetAlpha(a)
            end
            Mouse((a or 0) > 0)
        end,
        -- The check reveals with SetAlpha(1) and Show(). A resize may have
        -- hidden the background while it idled at alpha 0 (that reads as not
        -- visible, as a combat fade does), so Show brings it back. Hide stays
        -- alpha only; the next resize hides the frame properly.
        Show = function()
            if background then
                background:Show()
            end
            Mouse(true)
        end,
        Hide = function()
            if otf then
                otf:SetAlpha(0)
            end
            if background then
                background:SetAlpha(0)
            end
            Mouse(false)
        end,
        EnableMouse = function() end,
    }
end

function EQT.InitVisibility()
    local otf = Tracker()
    if not otf then
        return
    end
    MakeBackground()
    EQT.ApplyBackground()
    EQT.ApplyForceOnScreen()
    HookShow()

    -- The top line follows the UI accent colour (not under the stock styles,
    -- which have no background).
    if not EQT.Blizz() and CludesUI and CludesUI.RegAccent then
        CludesUI.RegAccent({ type = "callback", fn = PaintTopLine })
    end

    -- A /reload inside a key or a raid can find the tracker already hidden,
    -- with no OnHide to come: match the background to it now and twice more.
    local function MatchBackground()
        if background then
            background:SetShown(TrackerIsVisible(otf))
        end
    end
    MatchBackground()
    C_Timer.After(0.1, MatchBackground)
    C_Timer.After(0.5, MatchBackground)

    local listener = CreateFrame("Frame")
    listener:RegisterEvent("PLAYER_ENTERING_WORLD")
    listener:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    listener:RegisterEvent("ENCOUNTER_START")
    listener:RegisterEvent("ENCOUNTER_END")
    listener:SetScript("OnEvent", function(_, event)
        if event == "ENCOUNTER_START" then
            inEncounter = true
        else
            -- ENCOUNTER_END, or a new world (which also clears an ending missed).
            if event ~= "ZONE_CHANGED_NEW_AREA" then
                inEncounter = false
            end
        end
        instanceType = select(2, GetInstanceInfo()) or "none"
        UpdateVisibility()
        MatchBackground()
    end)

    -- The shared visibility pass (combat, mounted and the other modes).
    CludesUI.RegisterVisibilityUpdater(function()
        if not suppressed then
            UpdateVisibility()
        end
    end)

    if CludesUI.RegisterMouseoverTarget then
        CludesUI.RegisterMouseoverTarget(MouseoverTarget(otf), function()
            if HiddenByPlace() or suppressed then
                return false
            end
            -- Hover-gated sets reveal only while their conditions pass; a
            -- plain "mouseover" behaves as it always did.
            return CludesUI.VisWantsMouseover(EQT.DB(), "visibility")
        end)
    end

    C_Timer.After(0.5, UpdateVisibility)
end
