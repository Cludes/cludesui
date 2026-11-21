if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Visibility.lua
--
--  The fade: the alpha cache, mouse passthrough at full hide, the fade
--  driver and the visibility rules.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIChat.lua or an earlier CUI_Chat_*.lua file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local CUI = _G.CludesUI
local CHAT = mod.ECHAT
local min, upper = min, max

local _chatFadeFrame, CFD, FADE_IN_DURATION = Inner._chatFadeFrame, Inner.CFD, Inner.FADE_IN_DURATION
local FADE_OUT_DURATION, GetIdleFadeAlpha = Inner.FADE_OUT_DURATION, Inner.GetIdleFadeAlpha
local IDLE_FADE_OUT_DURATION = Inner.IDLE_FADE_OUT_DURATION
local SetChatAlphaCurrent, SetVisChatVisible = Inner.SetChatAlphaCurrent, Inner.SetVisChatVisible

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local _sidebarFadeAlpha = Inner._sidebarFadeAlpha
Inner.sidebarFadeAlphaSetters[#Inner.sidebarFadeAlphaSetters + 1] = function(val) _sidebarFadeAlpha = val end
local _chatAlphaCurrent = Inner._chatAlphaCurrent
Inner.chatAlphaCurrentSetters[#Inner.chatAlphaCurrentSetters + 1] = function(val) _chatAlphaCurrent = val end

-- Unified fade system: all alpha changes go through a target + lerp.
local _visChatVisible = true
Inner.visChatVisibleSetters[#Inner.visChatVisibleSetters + 1] = function(val) _visChatVisible = val end
local _idleFadeActive = false
Inner.idleFadeActiveSetters[#Inner.idleFadeActiveSetters + 1] = function(val) _idleFadeActive = val end
local _chatAlphaTarget = 1
local _visAlpha = 1

-- Frame cache for _ApplyAlpha, so the fade loop does no repeated _G lookups.
local _alphaFrames
-- CUI_Chat_Skin.lua drops the cache through this when it skins a frame.
local function SetAlphaFrames(val) _alphaFrames = val end
-- A live sidebar visibility change must refresh the cached sidebar mode, or
-- the fade keeps writing the old mode's alpha (a painted sidebar comes back).
-- Updated in place: this runs on every passthrough exit, and nothing else in
-- the cache depends on the mode.
function CHAT.InvalidateAlphaCache()
    if not _alphaFrames then return end
    local conf = CHAT.DB()
    _alphaFrames._sidebarMode = conf and conf.sidebarVisibility or "always"
end
local function _BuildAlphaCache()
    _alphaFrames = {}
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        local cfd = castFrame and CFD(castFrame)
        if castFrame and cfd.bg then
            _alphaFrames[#_alphaFrames + 1] = {
                cf = castFrame,
                eb = _G["ChatFrame" .. index .. "EditBox"],
                bg = cfd.bg,
                resizeGrip = cfd.resizeGrip,
            }
        end
    end
    local cf1 = _G.ChatFrame1
    _alphaFrames._sidebar = cf1 and CFD(cf1).sidebar
    local conf = CHAT.DB()
    _alphaFrames._sidebarMode = conf and conf.sidebarVisibility or "always"
    -- A chat-anchored scroll button does not inherit the sidebar alpha.
    if conf and conf.scrollButtonOnChat and cf1 then _alphaFrames._chatScrollBtn = CFD(cf1).scrollBtn end
end

-- Full-hide mouse passthrough. At effective alpha 0 every mouse surface over the panel
-- is released so clicks and camera drags reach the world. Two regimes: idle fade at
-- strength 100 keeps frames shown (a fade must render) and disables both mouse channels
-- on chat frames 1-10 plus their edit boxes, scroll bars, static tabs,
-- FontStringContainers and line-pool children (temp windows/dynamic tabs untouched),
-- plus our grips/sidebar/overlay -- hover- wake comes from the geometric poll below.
-- Visibility-hidden (never/combat rules) also Hide()s the stack via SetChatStackShown,
-- the only state the engine cannot route input to. Original states are captured in the
-- CFD side table and restored exactly the moment any fade-in begins (new message,
-- Enter, visibility change).
local _chatPassthrough = false

-- Capture-then-disable / exact-restore for BOTH mouse channels: clicks (EnableMouse)
-- and motion (EnableMouseMotion -- blocks camera right-drag). States live in the CFD
-- side table under `key` and `key .. "M"`, so we only ever re-enable what we ourselves
-- disabled. Channels are read/written SEPARATELY: EnableMouse/IsMouseEnabled are
-- COMBINED-channel APIs, chat widgets run split states (click-only line frames,
-- motion-only containers), and a combined restore flips the wrong channel -- e.g.
-- re-arming clicks on a natively motion-only frame after one passthrough cycle.
local function GetMouseChannels(frame)
    local click
    if frame.IsMouseClickEnabled then
        click = frame:IsMouseClickEnabled()
    else
        click = frame:IsMouseEnabled()
    end
    if issecretvalue and issecretvalue(click) then click = false end
    local motion = frame.IsMouseMotionEnabled and frame:IsMouseMotionEnabled()
    if issecretvalue and issecretvalue(motion) then motion = false end
    return click and true or false, motion and true or false
end
-- Forward declaration: the write helpers below arm it when a lockdown-
-- blocked write is skipped; defined after SetChatStackShown.
local ArmChatPMRegen

-- Delta-gated and lockdown-contained. Reads first and writes only real
-- changes, so the assert-every-sweep passes cost no protected calls while
-- the state already matches (a REAL drift -- Blizzard re-arming click on
-- its widgets -- is still a delta and still writes). Chat frames turn
-- PROTECTED while a temporary whisper window exists, and a blocked mouse
-- write used to throw out of the middle of a passthrough transition,
-- stranding the state machine half-engaged (field: chat frozen / tabs dead
-- after combat with Out of Combat visibility). Protection is not reliably
-- queryable up front, so under lockdown each remaining write runs through
-- pcall -- the refusal itself is the detection -- and the function returns
-- false so the caller arms the regen re-apply. Out of combat every write
-- is direct, exactly as before.
local function SetMouseChannels(frame, click, motion)
    click = click and true or false
    motion = motion and true or false
    local curClick, curMotion = GetMouseChannels(frame)
    local success = true
    if curClick ~= click then
        local func = frame.SetMouseClickEnabled or frame.EnableMouse
        if InCombatLockdown() then
            if not pcall(func, frame, click) then success = false end
        else
            func(frame, click)
        end
    end
    if curMotion ~= motion then
        local func = frame.SetMouseMotionEnabled or frame.EnableMouseMotion
        if func then
            if InCombatLockdown() then
                if not pcall(func, frame, motion) then success = false end
            else
                func(frame, motion)
            end
        end
    end
    return success
end

local function PMOff(skinData, key, frame)
    if not frame then return end
    -- Capture on first sight only, but ASSERT the disable every sweep:
    -- Blizzard's message pipeline re-enables click on chat widgets while we
    -- are engaged, and a skipped re-disable leaves an invisible click zombie.
    if skinData[key] == nil then
        local click, motion = GetMouseChannels(frame)
        skinData[key] = click
        skinData[key .. "M"] = motion
    end
    if not SetMouseChannels(frame, false, false) then ArmChatPMRegen() end
end
local function PMOn(skinData, key, frame)
    if frame and skinData[key] ~= nil then
        if not SetMouseChannels(frame, skinData[key], skinData[key .. "M"]) then
            -- Keep the capture: the regen re-apply restores from it.
            ArmChatPMRegen()
            return
        end
    end
    skinData[key] = nil
    skinData[key .. "M"] = nil
end

-- The SMF's per-line hit-test frames are children of FontStringContainer
-- (Blizzard's line pool) and each carries its own mouse state, so toggling
-- the container alone does not release them. ONE bounded generation -- direct
-- children only, NEVER recursive -- with per-child state captured on first
-- sight in a weak side store and restored exactly from it.
local function PMOffChildren(skinData, key, hostFrame)
    if not hostFrame then return end
    local storage = skinData[key]
    if not storage then
        storage = setmetatable({}, { __mode = "k" })
        skinData[key] = storage
    end
    local kids = { hostFrame:GetChildren() }
    for index = 1, #kids do
        local c = kids[index]
        -- Capture first sight only; assert the disable every sweep -- the SMF
        -- re-enables click on its line frames as messages render, and these
        -- shape the dead zone.
        if not storage[c] then
            local click, motion = GetMouseChannels(c)
            storage[c] = { click, motion }
        end
        if not SetMouseChannels(c, false, false) then ArmChatPMRegen() end
    end
end
local function PMOnChildren(skinData, key, hostFrame)
    local storage = skinData[key]
    if not storage or not hostFrame then return end
    local kids = { hostFrame:GetChildren() }
    for index = 1, #kids do
        local c = kids[index]
        local st = storage[c]
        if st then
            if SetMouseChannels(c, st[1], st[2]) then
                storage[c] = nil
            else
                -- Keep the capture for the regen re-apply.
                ArmChatPMRegen()
            end
        end
    end
end

-- Frame-level portion of the full-hide passthrough. OUR message frames are
-- simply hidden for the duration (a hidden frame cannot receive input); the
-- live Blizzard mouse surfaces over the panel -- the edit boxes, the skinned
-- permanent tabs, the dock overflow button, the invisible hyperlink
-- hit-zones in each FontStringContainer, and the chat frame itself -- get
-- the capture-exact PMOff/PMOn treatment.
local function PassthroughFrames(enabled)
    for index = 1, 10 do
        local castFrame = _G["ChatFrame" .. index]
        local skinData = castFrame and CFD(castFrame)
        if skinData and skinData.bg then
            local eb = _G["ChatFrame" .. index .. "EditBox"]
            if enabled then
                PMOff(skinData, "pmCf", castFrame)
                -- FontStringContainer is a separate mouse surface (hyperlink
                -- hit-testing) not covered by the chat frame's own state; its
                -- line-pool children each carry their own too.
                PMOff(skinData, "pmFsc", castFrame.FontStringContainer)
                PMOffChildren(skinData, "pmFscKids", castFrame.FontStringContainer)
                PMOff(skinData, "pmEb", eb)
                PMOff(skinData, "pmGrip", skinData.resizeGrip)
            else
                PMOn(skinData, "pmCf", castFrame)
                PMOn(skinData, "pmFsc", castFrame.FontStringContainer)
                PMOnChildren(skinData, "pmFscKids", castFrame.FontStringContainer)
                PMOn(skinData, "pmEb", eb)
                PMOn(skinData, "pmGrip", skinData.resizeGrip)
            end
        end
    end
    -- Blizzard's tabs and dock overflow are hidden wholesale now (owned tab
    -- strip); hidden frames cannot receive input, so no mouse work for them.
    -- Our own surfaces hide outright while passthrough is engaged.
    if CHAT.EngineSetPassthrough then CHAT.EngineSetPassthrough(enabled) end
    if CHAT.TabsSetPassthrough then CHAT.TabsSetPassthrough(enabled) end
end

-- Hover-wake while fully hidden: a passthrough panel cannot receive mouse
-- events, so mouseover reveal at fade strength 100 needs a geometric poll --
-- IsMouseOver() is a pure rect test needing no mouse state. Runs ONLY while
-- idle-fade passthrough is engaged (never for the "never" hard hide, never
-- while visible): one rect test 5x/sec, cancelled the moment chat reveals.
local _ptWakeTicker
local function CancelWakeTicker()
    if _ptWakeTicker then
        _ptWakeTicker:Cancel()
        _ptWakeTicker = nil
    end
end
local function StartPTWake()
    CancelWakeTicker()
    _ptWakeTicker = C_Timer.NewTicker(0.2, function()
        if not _chatPassthrough or not _idleFadeActive or not _visChatVisible then
            CancelWakeTicker()
            return
        end
        local shade = mod._chatHoverOverlay
        if shade and shade:IsMouseOver() then
            CancelWakeTicker()
            if CHAT.ResetIdleTimer then CHAT.ResetIdleTimer() end
        end
    end)
end

-- Hard-hidden visibility states (visibility "never", combat-only modes while
-- out of combat) hide the chat stack OUTRIGHT. Blizzard's chat frames are
-- never touched here: their shown state belongs to FCF (OnShow/OnHide write
-- SetChatWindowShown into config storage), and their visuals are parked in
-- the engine's hidden container regardless. What hides is OUR stack: the
-- panels (our message frames and scrollbars are their children), the dock
-- manager (single remember; nothing of Blizzard's re-shows it), and the
-- module chrome. Shown-state is captured per frame and restored exactly on
-- reveal. Idle fade still uses alpha (a fade must render); this applies only
-- when visibility says hidden.
local _chromeWasShown = setmetatable({}, { __mode = "k" })
local _chromeList = {}

local function ShowChatStack(isShown)
    -- Gate for SyncChatFrameState: the panels' shown-follow must not undo
    -- this hide (the Blizzard frames stay shown, so the follow would).
    mod._chatStackHidden = not isShown
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        local skinData = castFrame and CFD(castFrame)
        if skinData and skinData.bg then
            if not isShown then
                if skinData.bg:IsShown() then
                    skinData.pmWasShown = true
                    skinData.bg:Hide()
                end
            elseif skinData.pmWasShown then
                skinData.pmWasShown = nil
                skinData.bg:Show()
            end
        end
    end
    local gdm = _G.GeneralDockManager
    if gdm then
        -- Show/Hide of an ancestor of a PROTECTED child (a docked temporary
        -- whisper tab in lockdown) is blocked: contain the write and let the
        -- regen re-apply land it. The remember records only what actually
        -- happened.
        if not isShown then
            if gdm:IsShown() then
                if not InCombatLockdown() then
                    mod._gdmWasShown = true
                    gdm:Hide()
                elseif pcall(gdm.Hide, gdm) then
                    mod._gdmWasShown = true
                else
                    ArmChatPMRegen()
                end
            end
        elseif mod._gdmWasShown then
            if not InCombatLockdown() then
                mod._gdmWasShown = nil
                gdm:Show()
            elseif pcall(gdm.Show, gdm) then
                mod._gdmWasShown = nil
            else
                ArmChatPMRegen()
            end
        end
    end
    -- Our own chrome hides outright too; the per-frame remember preserves each
    -- applier's shown/hidden decision for the reveal.
    local cf1 = _G.ChatFrame1
    _chromeList[1] = mod._chatPanelBorder
    _chromeList[2] = mod._sidebarSeparateBorder
    _chromeList[3] = mod._chatBgExt
    _chromeList[4] = mod._chatTabStrip
    _chromeList[5] = mod._chatHoverOverlay
    _chromeList[6] = cf1 and CFD(cf1).sidebar or nil
    for index = 1, 6 do
        local frame = _chromeList[index]
        if frame then
            if not isShown then
                if frame:IsShown() then
                    _chromeWasShown[frame] = true
                    frame:Hide()
                end
            elseif _chromeWasShown[frame] then
                _chromeWasShown[frame] = nil
                frame:Show()
            end
        end
        _chromeList[index] = nil
    end
end

-- One-shot regen re-apply for lockdown-blocked writes. Re-asserts the
-- CURRENT intended passthrough state whole; the delta gate makes the pass
-- idempotent (everything that already landed is skipped, only the refused
-- writes replay). Fires before the visibility dispatcher's deferred
-- refresh, so a post-combat reveal starts from a clean slate. Runs through
-- the module combat queue: zero idle cost.
local function ChatPMRegenReapply()
    PassthroughFrames(_chatPassthrough)
    if _chatPassthrough and not _visChatVisible then ShowChatStack(false) end
end
ArmChatPMRegen = function() mod.CombatQueue.Defer("ChatPassthroughReapply", ChatPMRegenReapply) end

local function SetChatMousePassthrough(enabled)
    if _chatPassthrough == enabled then return end
    _chatPassthrough = enabled
    mod._chatPassthrough = enabled
    -- Reveal BEFORE the restore pass: TabsSweepBlizzard (run by the tab
    -- restore inside PassthroughFrames) derives its click state from
    -- ns._chatPassthrough OR ns._chatStackHidden. With the stack still
    -- remembered hidden, the restore sweep re-disables the very tabs it is
    -- meant to re-enable, and nothing later re-runs it (field: tabs dead
    -- after combat with in-combat hide once the engage completes cleanly).
    -- The engage direction keeps the reverse order: sweep first (its
    -- passthrough flag alone forces click-off), stack-hide after.
    if not enabled then ShowChatStack(true) end
    PassthroughFrames(enabled)
    if enabled then
        if not _visChatVisible then
            ShowChatStack(false)
            -- A visibility hide counts as idle: the reveal then finds the chat
            -- already faded instead of showing it until the leftover idle delay
            -- runs out. Here, not at the flip, so the hide keeps its own fade speed.
            if CHAT.StartIdleFadeNow then CHAT.StartIdleFadeNow() end
        end
        local cf1 = _G.ChatFrame1
        local scrollBar = cf1 and CFD(cf1).sidebar
        if scrollBar then
            scrollBar:EnableMouse(false)
            if scrollBar.EnableMouseMotion then scrollBar:EnableMouseMotion(false) end
        end
        if CHAT.ApplySidebarIcons then CHAT.ApplySidebarIcons() end
        -- _visChatVisible excludes the visibility-hidden regimes, where
        -- hover-wake must not exist.
        if _idleFadeActive and _visChatVisible and CHAT.DB().idleFadeEnabled ~= false then StartPTWake() end
    else
        CancelWakeTicker()
        -- Our sidebar always runs with motion on (hover fade/reveal); the
        -- mode-specific click state is re-derived by ApplySidebarVisibility.
        local cf1 = _G.ChatFrame1
        local scrollBar = cf1 and CFD(cf1).sidebar
        if scrollBar and scrollBar.EnableMouseMotion then scrollBar:EnableMouseMotion(true) end
        if CHAT.ApplySidebarVisibility then CHAT.ApplySidebarVisibility() end
    end
    if CHAT.ApplyIdleFadeHoverMotion then CHAT.ApplyIdleFadeHoverMotion() end
end

-- Late joiners while engaged: a frame skinned or integrated during a
-- full-hide (temp whisper window opening mid-hide) must join the passthrough
-- set. One deferred catch-up covers it; nothing re-arms already-treated
-- widgets, so no recurring sweeps exist.
local _ptSweepQueued = false
local function RequestPassthroughSweep()
    if not _chatPassthrough or _ptSweepQueued then return end
    _ptSweepQueued = true
    C_Timer.After(0, function()
        _ptSweepQueued = false
        if not _chatPassthrough then return end
        PassthroughFrames(true)
        if not _visChatVisible then ShowChatStack(false) end
    end)
end

local function _ApplyAlpha(alpha)
    SetChatAlphaCurrent(alpha)
    SetChatMousePassthrough(alpha <= 0)
    if not _alphaFrames then _BuildAlphaCache() end
    -- Our tab strip (UIParent-parented) fades directly; its buttons inherit.
    if mod._chatTabStrip then mod._chatTabStrip:SetAlpha(alpha) end
    -- Blizzard Style shows Blizzard's real docked tabs: they fade at DOCK
    -- level, the same container-alpha write the tab sweep makes for the
    -- CludesUI look (never the per-tab alphas or their globals).
    if mod.ChatBlizzTabs() then
        local gdm = _G.GeneralDockManager
        if gdm then gdm:SetAlpha(alpha) end
    end
    for index = 1, #_alphaFrames do
        local af = _alphaFrames[index]
        local castFrame = af.cf
        if castFrame:IsShown() or af.bg:IsShown() then
            castFrame:SetAlpha(alpha)
            -- The panel is a UIParent child (taint fix) and does not inherit
            -- the chat frame's alpha -- fade it directly.
            af.bg:SetAlpha(alpha)
            local eb = af.eb
            if eb then
                local focused = eb:HasFocus()
                if issecretvalue and issecretvalue(focused) then focused = false end
                if castFrame.isTemporary or not focused then eb:SetAlpha(alpha) end
            end
            if af.resizeGrip then af.resizeGrip:SetAlpha(alpha * 0.4) end
        end
    end
    -- Behind-tabs extension is UIParent-parented: fade it directly.
    if mod._chatBgExt then mod._chatBgExt:SetAlpha(alpha) end
    if mod._chatPanelBorder then mod._chatPanelBorder:SetAlpha(alpha) end
    if mod._sidebarSeparateBorder then mod._sidebarSeparateBorder:SetAlpha(min(alpha, _sidebarFadeAlpha)) end
    -- The panel bottom separator is a texture on bg and inherits the chat frame's alpha
    -- automatically -- no explicit write needed. Sidebar (mode cached at build time)
    local scrollBar = _alphaFrames._sidebar
    if scrollBar then
        local sbMode = _alphaFrames._sidebarMode
        if sbMode == "mouseover" then
            scrollBar:SetAlpha(min(alpha, _sidebarFadeAlpha))
        elseif sbMode ~= "never" then
            scrollBar:SetAlpha(alpha)
        end
    end
    -- Chat-anchored scroll button (UIParent-parented, fades with the panel)
    if _alphaFrames._chatScrollBtn then _alphaFrames._chatScrollBtn:SetAlpha(alpha) end
end

-- Scroll-to-bottom button seat: sidebar bottom (default) or the chat panel's
-- bottom-right corner. The button is ours, so reparenting is safe.
function CHAT.ApplyScrollButtonPosition()
    local cf1 = _G.ChatFrame1
    local skinData = cf1 and CFD(cf1)
    local button = skinData and skinData.scrollBtn
    if not button then return end
    local conf = CHAT.DB()
    -- Seat memo: this runs on every icon-layout pass (including sidebar hover
    -- edges); an unchanged seat needs no re-anchor and no alpha invalidation.
    local seat = conf.scrollButtonOnChat and "chat" or "sidebar"
    if skinData.scrollSeat == seat then return end
    skinData.scrollSeat = seat
    local scrollBar = skinData.sidebar
    button:ClearAllPoints()
    if conf.scrollButtonOnChat and skinData.bg then
        button:SetParent(UIParent)
        -- Stock styles: the panel's strata, above Blizzard's revealed chat
        -- background (see SyncChatFrameState).
        button:SetFrameStrata(mod.ChatStock() and "MEDIUM" or cf1:GetFrameStrata())
        button:SetFrameLevel(cf1:GetFrameLevel() + 5)
        -- Anchor to the message frame, not bg: the unified bg panel includes the
        -- edit box, so bg's corner sits in the input row. Stock styles: just
        -- inside the revealed art's border (its background corner is +8,-6).
        if mod.ChatStock() then
            button:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMRIGHT", 4, -2)
        else
            button:SetPoint("BOTTOMRIGHT", cf1, "BOTTOMRIGHT", 8, -6)
        end
    elseif scrollBar then
        button:SetParent(scrollBar)
        button:SetFrameStrata(scrollBar:GetFrameStrata())
        button:SetFrameLevel(scrollBar:GetFrameLevel() + 1)
        button:SetPoint("BOTTOM", scrollBar, "BOTTOM", 0, CHAT.SB_KIT and 0 or 10)
    end
    -- Stock kits: each seat wears the art the stock UI shows there.
    if CHAT.SB_KIT then
        CHAT.SB_DressScroll(button, seat)
        CHAT.SB_ApplyScale(skinData, CHAT.DB().sidebarIconScale or 1, true)
    end
    -- Parent changed: the alpha cache decides whether to fade it directly.
    _alphaFrames = nil
end

-- Animate alpha toward target
local function _SetAlphaTarget(target)
    _chatAlphaTarget = target
    _chatFadeFrame:Show()
end

local _fadeApplyAccum = 0
_chatFadeFrame:SetScript("OnUpdate", function(self, elapsed)
    if _chatAlphaCurrent == _chatAlphaTarget then
        self:Hide()
        _fadeApplyAccum = 0
        -- The throttle below can swallow the last step of a fade; push the
        -- final value so completion states (especially 0) always land.
        _ApplyAlpha(_chatAlphaCurrent)
        return
    end
    local fadingIn = _chatAlphaTarget > _chatAlphaCurrent
    local duration = fadingIn and FADE_IN_DURATION
        or (_idleFadeActive and IDLE_FADE_OUT_DURATION or FADE_OUT_DURATION)
    local speed = elapsed / duration
    if fadingIn then
        SetChatAlphaCurrent(min(_chatAlphaTarget, _chatAlphaCurrent + speed))
    else
        SetChatAlphaCurrent(upper(_chatAlphaTarget, _chatAlphaCurrent - speed))
    end
    -- The alpha step accumulates every frame but is only pushed to widgets on a
    -- throttle. Still smooth; saves ~75% of SetAlpha calls at 120fps.
    _fadeApplyAccum = _fadeApplyAccum + elapsed
    if _fadeApplyAccum < 0.016 then return end
    _fadeApplyAccum = 0
    _ApplyAlpha(_chatAlphaCurrent)
    if _chatAlphaCurrent == _chatAlphaTarget then self:Hide() end
end)

-- Animated alpha for the visibility/mouseover system. Top-level authority:
-- idle fade cannot exceed this.
function CHAT.SetChatAlpha(alpha)
    local wasVisible = _visChatVisible
    _visAlpha = alpha
    SetVisChatVisible(alpha >= 1)
    -- Already fully hidden (idle fade at strength 100): the alpha stays 0 across a
    -- visibility flip, so SetChatMousePassthrough never sees an edge and the
    -- hover-wake poll / stack hide are never switched. Switch them here.
    if _chatPassthrough and wasVisible ~= _visChatVisible then
        if _visChatVisible then
            ShowChatStack(true)
            if _idleFadeActive and CHAT.DB().idleFadeEnabled ~= false then StartPTWake() end
        else
            CancelWakeTicker()
            ShowChatStack(false)
        end
    end
    _SetAlphaTarget(alpha)
end

-- Animated idle-fade alpha, clamped to the visibility alpha
function CHAT.SetIdleFadeAlpha(alpha) _SetAlphaTarget(min(alpha, _visAlpha)) end

-- Re-derive visibility from DB settings (combat, mouseover, always, ...)
function CHAT.RefreshVisibility()
    local conf = CHAT.DB()

    local vis = true
    if CUI and CUI.EvalVisibility then vis = CUI.EvalVisibility(conf) end

    local alpha
    if vis == false then
        alpha = 0
    else
        alpha = 1
    end

    if alpha == 1 and _idleFadeActive then
        CHAT.SetChatAlpha(1)
        CHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
    else
        CHAT.SetChatAlpha(alpha)
    end
end

Inner._idleFadeActive, Inner._visChatVisible = _idleFadeActive, _visChatVisible
Inner.RequestPassthroughSweep, Inner.SetAlphaFrames = RequestPassthroughSweep, SetAlphaFrames
Inner.broken = false
