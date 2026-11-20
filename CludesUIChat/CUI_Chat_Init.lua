if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Chat_Init.lua
--
--  The tab refresh shim and the PLAYER_LOGIN pass that skins the frames and
--  starts the watchers.
--  Reads the earlier Chat files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIChat.lua or an earlier CUI_Chat_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local CUI = _G.CludesUI
local CHAT = mod.ECHAT
local upper = max

local CFD, EnsureDB, GetFont = Inner.CFD, Inner.EnsureDB, Inner.GetFont
local GetFrameFontSize, GetIdleFadeAlpha = Inner.GetFrameFontSize, Inner.GetIdleFadeAlpha
local GetOutlineFlag, RequestPassthroughSweep = Inner.GetOutlineFlag, Inner.RequestPassthroughSweep
local ContainsURL, WrapURLs, _skinned = Inner.ContainsURL, Inner.WrapURLs, Inner._skinned
local CHAT_MSG_EVENTS, SkinChatFrame = Inner.CHAT_MSG_EVENTS, Inner.SkinChatFrame
local SetBgR, SetBgG, SetBgB, SetBgA = Inner.SetBgR, Inner.SetBgG, Inner.SetBgB, Inner.SetBgA
local SetIdleFadeActive = Inner.SetIdleFadeActive

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local BG_R = Inner.BG_R
Inner.bgRSetters[#Inner.bgRSetters + 1] = function(val)
    BG_R = val
end
local BG_G = Inner.BG_G
Inner.bgGSetters[#Inner.bgGSetters + 1] = function(val)
    BG_G = val
end
local BG_B = Inner.BG_B
Inner.bgBSetters[#Inner.bgBSetters + 1] = function(val)
    BG_B = val
end
local BG_A = Inner.BG_A
Inner.bgASetters[#Inner.bgASetters + 1] = function(val)
    BG_A = val
end
local _visChatVisible = Inner._visChatVisible
Inner.visChatVisibleSetters[#Inner.visChatVisibleSetters + 1] = function(val)
    _visChatVisible = val
end
local _idleFadeActive = Inner._idleFadeActive
Inner.idleFadeActiveSetters[#Inner.idleFadeActiveSetters + 1] = function(val)
    _idleFadeActive = val
end

-------------------------------------------------------------------------------
--  Tab refresh shim: the owned strip (CludesUIChat_Tabs.lua) redraws from
--  a coalesced deferred pass; this also re-hides anything of Blizzard's tab
--  plane that its own event passes re-showed.
-------------------------------------------------------------------------------
local function PaintTabs()
    if CHAT.TabsSweepBlizzard then
        CHAT.TabsSweepBlizzard()
    end
    if CHAT.TabsRefresh then
        CHAT.TabsRefresh()
    end
end

-------------------------------------------------------------------------------
--  Initialization (PLAYER_LOGIN)
-------------------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    EnsureDB()

    ---------------------------------------------------------------------------
    --  1. Load saved background color/opacity before skinning any frames
    ---------------------------------------------------------------------------
    local p = CHAT.DB()
    SetBgR(p.bgR or BG_R)
    SetBgG(p.bgG or BG_G)
    SetBgB(p.bgB or BG_B)
    SetBgA(p.bgAlpha or BG_A)

    ---------------------------------------------------------------------------
    --  2. Skin all 20 chat frames (bg, tabs, edit box, etc.), then bring them
    --     under the display engine: font providers first, then integration
    --     (Blizzard text suppressed, AddMessage bridge installed, our windows
    --     built and backfilled with everything already in Blizzard's buffers).
    ---------------------------------------------------------------------------
    for index = 1, 20 do
        local castFrame = _G["ChatFrame" .. index]
        if castFrame then
            SkinChatFrame(castFrame)
        end
    end
    CHAT.EngineFontProvider = GetFont
    CHAT.EngineFontSizeProvider = GetFrameFontSize
    CHAT.EngineOutlineProvider = GetOutlineFlag
    -- Seed the display-transform switches BEFORE integration: the install
    -- backfill renders through the same transforms as live lines.
    if CHAT.EngineSetChannelAbbrev then
        CHAT.EngineSetChannelAbbrev(p.abbreviateChannels == true)
    end
    if CHAT.EngineSetChannelAbbrevLetters then
        CHAT.EngineSetChannelAbbrevLetters(p.abbreviateChannelLetters == true)
    end
    if p.classColorNames == true then
        CHAT.ApplyClassColorNames(true)
    end
    if CHAT.EngineIntegrateAll then
        CHAT.EngineIntegrateAll()
    end
    -- Owned tab strip: hides Blizzard's strip, builds ours from the same
    -- window storage, and starts mirroring selection/flash from the engine.
    if CHAT.TabsInit then
        CHAT.TabsInit()
    end
    -- Re-run the background pass so a saved Background Texture applies at login
    -- (the skin loop creates the bg textures with the solid color).
    CHAT.ApplyBackground()
    ---------------------------------------------------------------------------
    --  2b. NEVER replace the global CHAT_FONT_HEIGHTS to expand font sizes:
    --      every read becomes tainted, and Blizzard's tab context menu
    --      iterates it mid-build, so the whole menu -- every click handler
    --      wired after that read -- runs tainted, and any item touching a
    --      whisper window's secret-keyed tables errors
    --      (FCF_RestoreChatsToFrame forbidden-table iteration). CUI font size
    --      is applied at skin time instead.
    ---------------------------------------------------------------------------

    ---------------------------------------------------------------------------
    --  2c. Clickable URLs via message event filters
    ---------------------------------------------------------------------------
    local URL_EVENTS = {
        "CHAT_MSG_SAY",
        "CHAT_MSG_YELL",
        "CHAT_MSG_GUILD",
        "CHAT_MSG_OFFICER",
        "CHAT_MSG_PARTY",
        "CHAT_MSG_PARTY_LEADER",
        "CHAT_MSG_RAID",
        "CHAT_MSG_RAID_LEADER",
        "CHAT_MSG_INSTANCE_CHAT",
        "CHAT_MSG_INSTANCE_CHAT_LEADER",
        "CHAT_MSG_WHISPER",
        "CHAT_MSG_WHISPER_INFORM",
        "CHAT_MSG_BN_WHISPER",
        "CHAT_MSG_BN_WHISPER_INFORM",
        "CHAT_MSG_CHANNEL",
    }
    local function UrlFilter(self, evt, message, ...)
        if not message or not ContainsURL(message) then
            return false
        end
        return false, WrapURLs(message), ...
    end
    for _, ev in ipairs(URL_EVENTS) do
        ChatFrame_AddMessageEventFilter(ev, UrlFilter)
    end

    ---------------------------------------------------------------------------
    --  3. Temporary window (whisper) detection.
    ---------------------------------------------------------------------------
    -- Shared skin pass: skins unskinned frames, re-strips tabs, re-applies font,
    -- hides Blizzard chrome. Driven by whisper events and the state watcher --
    -- never by a hooksecurefunc on FCF_OpenTemporaryWindow, which taints edit
    -- box header arithmetic during window creation.
    local function SkinPass()
        local wantFont = GetFont()
        local wantOutline = GetOutlineFlag()
        for index = 1, 20 do
            local castFrame = _G["ChatFrame" .. index]
            -- New frames (SkinChatFrame handles the panel + edit box)
            if castFrame and not _skinned[castFrame] then
                SkinChatFrame(castFrame)
            end
            -- Re-apply font if Blizzard reset it (e.g. font size change).
            -- Family form, not raw SetFont: a raw write here would detach
            -- the CJK font family the skin pass attached.
            if castFrame and _skinned[castFrame] then
                local curFont = castFrame:GetFont()
                if curFont and curFont ~= wantFont then
                    -- Size from Blizzard's stored per-window setting, NEVER read
                    -- back off the widget: under a font family cf:GetFont()
                    -- answers for the ACTIVE alphabet, so on a CJK client it
                    -- returns the CJK member -- a file that never equals
                    -- wantFont, at that member's own height. Feeding it back in
                    -- re-seeded the family from its own output, and this pass
                    -- runs on UPDATE_(FLOATING_)CHAT_WINDOWS, so chat text grew
                    -- on every login, reload and tab switch.
                    local sz = GetFrameFontSize(castFrame:GetID())
                    local fam = CHAT.EngineFontFamily
                        and CHAT.EngineFontFamily(castFrame:GetID(), wantFont, sz, wantOutline)
                    if fam then
                        castFrame:SetFontObject(fam)
                    else
                        castFrame:SetFont(wantFont, sz, wantOutline)
                    end
                end
                -- Blizzard resets this alongside the font/dock passes above;
                -- re-assert every pass rather than gating on a changed-check
                -- (a plain boolean set costs nothing). See SkinChatFrame for
                -- why this must stay congruent with win.smf's own setting.
                castFrame:SetIndentedWordWrap(true)
            end
        end
        PaintTabs()
        CHAT.ApplyTabLayout()
        if CHAT.ApplyInputPosition then
            CHAT.ApplyInputPosition()
        end
    end

    ---------------------------------------------------------------------------
    --  4. Chat-frame state watcher, in place of FCF_* hooksecurefunc hooks.
    --  NEVER hooksecurefunc FCFDock_SelectWindow / FCF_Close /
    --  FCF_OpenNewWindow -- deferring the body to C_Timer.After(0) does not
    --  help, since the hook WRAPPER still executes inside the caller's own
    --  execution and taints the rest of that caller. Measured chain: an
    --  FCF_Close hook taints the caller -> a later FCF_DockFrame (or
    --  FCF_CopyChatSettings) reaches FCF_SetLocked, whose `chatFrame.isLocked
    --  = isLocked` write lands under that taint -> the FIELD stays tainted
    --  through every later secure pass (so watching only GLOBALS reads
    --  clean) -> FCF_Tab_SetupMenu reads tabChatFrame.isLocked building the
    --  tab menu, so its closures (incl. "Close Whisper Window") die
    --  iterating the forbidden privateMessageList -> the same field is read
    --  by FCF_UpdateResizeButton during the temp-window OPEN, tainting its
    --  secret whisper-name math too. One field, both error classes. These
    --  hooks only did cosmetic re-assertion, so the same state is watched
    --  instead -- from the interaction follower (armed only while chat is
    --  hovered or Edit Mode is open) and the deferred event passes below:
    --  outside Blizzard's dispatch, zero idle cost, up to one tick latency.
    ---------------------------------------------------------------------------
    -- Likewise NEVER hook FCFTab_UpdateColors or FCFDock_UpdateTabs synchronously:
    -- FCF_OpenTemporaryWindow -> FCF_SetTemporaryWindowType calls FCFTab_UpdateColors
    -- directly and ends with a synchronous FCFDock_UpdateTabs call, so both hook bodies
    -- would execute inside the temp-whisper creation chain, deactivating the new
    -- editBox and running UpdateHeader's width math on the SECRET whisper-name geometry
    -- -- no body shape is safe here. Recolor + layout run DEFERRED from our own
    -- triggers below; the cost is a possible 1-frame Blizzard-styled flash.
    local _tabPassQueued = false
    local function QueueTabPass()
        if _tabPassQueued then
            return
        end
        _tabPassQueued = true
        C_Timer.After(0, function()
            _tabPassQueued = false
            PaintTabs()
            CHAT.ApplyTabLayout()
            -- Every restyle trigger is also a moment panel geometry can
            -- shift or the dock selection can have changed; all calls
            -- early-out on clean state, and this deferred body is our own
            -- execution.
            if CHAT.SyncChatFrameState then
                CHAT.SyncChatFrameState()
            end
            if CHAT.PositionChatPanelsNow then
                CHAT.PositionChatPanelsNow()
            end
            if CHAT.EngineUpdateCombatLogHost then
                CHAT.EngineUpdateCombatLogHost()
            end
        end)
    end
    CHAT.QueueTabPass = QueueTabPass
    -- Full pass: skin new frames, then restyle + state sync. SkinPass ends with
    -- UpdateTabColors/ApplyTabLayout/ApplyInputPosition, so this is the one-stop
    -- deferred handler for anything that can create a chat frame.
    local _fullPassQueued = false
    local function QueueFullPass()
        if _fullPassQueued then
            return
        end
        _fullPassQueued = true
        C_Timer.After(0, function()
            _fullPassQueued = false
            SkinPass()
            -- New frames (temp whisper windows, user-created windows) join
            -- the engine here: visual children parked, bridge installed, our
            -- window built and backfilled. Idempotent for known frames.
            if CHAT.EngineIntegrateAll then
                CHAT.EngineIntegrateAll()
            end
            if CHAT.SyncChatFrameState then
                CHAT.SyncChatFrameState()
            end
            if CHAT.PositionChatPanelsNow then
                CHAT.PositionChatPanelsNow()
            end
            -- A re-skin resets the resize button's base alpha; re-assert the
            -- lock state over it.
            if CHAT.ApplyLockChatSize then
                CHAT.ApplyLockChatSize()
            end
            -- A frame integrated while the panel is fully hidden must join
            -- the passthrough set.
            RequestPassthroughSweep()
            -- A window created while the house editor is open is born on the
            -- hidden UIParent; seat it with the rest of the panel.
            CHAT.ApplyPanelHost()
        end)
    end
    CHAT.QueueFullPass = QueueFullPass
    -- Every moment Blizzard resets our styling (login passes, zone transitions, dock
    -- config loads) coincides with these events on our own frame -- outside Blizzard's
    -- dispatch, deferred one tick. Also covers user-created permanent windows
    -- (UPDATE_CHAT_WINDOWS) and repositions panels after scale changes.
    local tabPass = CreateFrame("Frame")
    tabPass:RegisterEvent("PLAYER_ENTERING_WORLD")
    tabPass:RegisterEvent("UPDATE_CHAT_WINDOWS")
    tabPass:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
    tabPass:RegisterEvent("UI_SCALE_CHANGED")
    tabPass:RegisterEvent("DISPLAY_SIZE_CHANGED")
    tabPass:SetScript("OnEvent", QueueFullPass)
    -- Edit Mode can rebuild the chat dock and tab geometry after a panel resize.
    -- Re-assert tab appearance only once that update has left Blizzard's
    -- event/script stack; the short second pass covers the final size commit
    -- performed while Edit Mode closes.
    do
        local editStyleGen = 0
        local function QueueEditModeTabStyle()
            editStyleGen = editStyleGen + 1
            local generation = editStyleGen
            QueueTabPass()
            C_Timer.After(0.10, function()
                if generation == editStyleGen then
                    QueueTabPass()
                end
            end)
        end
        local editModeStyleFrame = CreateFrame("Frame")
        editModeStyleFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        editModeStyleFrame:SetScript("OnEvent", function()
            C_Timer.After(0, QueueEditModeTabStyle)
        end)
        if EditModeManagerFrame then
            -- Arm the follower for the whole Edit Mode session: chat can be
            -- dragged/resized with the mouse nowhere near our hover widgets
            -- (the Selection overlay occludes them).
            EditModeManagerFrame:HookScript("OnShow", function()
                if CHAT.FollowArmEditMode then
                    CHAT.FollowArmEditMode(true)
                end
            end)
            EditModeManagerFrame:HookScript("OnHide", function()
                if CHAT.FollowArmEditMode then
                    CHAT.FollowArmEditMode(false)
                end
                C_Timer.After(0, QueueEditModeTabStyle)
            end)
        end
    end

    -- House editor open/close: reseat the panel onto Blizzard's full-screen host
    -- (see ApplyPanelHost). Our own event frame, deferred a tick so the reseat
    -- runs after HouseEditorFrame's show/hide has set the full-screen frame --
    -- never an EventRegistry callback or a hook, both of which would run our
    -- body inside Blizzard's own execution.
    if C_HouseEditor and C_HouseEditor.IsHouseEditorActive then
        local houseEditorFrame = CreateFrame("Frame")
        houseEditorFrame:RegisterEvent("HOUSE_EDITOR_MODE_CHANGED")
        houseEditorFrame:SetScript("OnEvent", function()
            C_Timer.After(0, CHAT.ApplyPanelHost)
        end)
    end
    -- Tab close is covered by the state watcher above. NEVER hook FCF_Close:
    -- "top-level user action" is the wrong test -- it is also reached from
    -- FCF_PopInWindow (the tab menu's own Close button) and dock teardown, and even
    -- a genuine top-level click's hook taints the REST of the caller, which is what
    -- poisons ChatFrame*.isLocked. Temp window creation: NEVER
    -- hooksecurefunc("FCF_OpenTemporaryWindow") either -- the secure whisper router
    -- calls it mid-function and continues to DeactivateChat -> UpdateHeader, whose
    -- width math runs on the SECRET whisper name geometry; our hook in the chain
    -- taints the remainder of the caller and blocks that arithmetic. Instead the
    -- same whisper events are registered on our own frame (standalone C-side
    -- dispatch, outside Blizzard's execution, taint-free) and the skin is deferred.
    -- That covers every temp-window trigger: incoming whisper and outgoing /w in
    -- popout mode (WHISPER_INFORM).
    do
        local tempWindow = CreateFrame("Frame")
        tempWindow:RegisterEvent("CHAT_MSG_WHISPER")
        tempWindow:RegisterEvent("CHAT_MSG_WHISPER_INFORM")
        tempWindow:RegisterEvent("CHAT_MSG_BN_WHISPER")
        tempWindow:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM")
        tempWindow:SetScript("OnEvent", QueueFullPass)
    end
    -- User-created permanent chat windows are covered by the full pass on
    -- UPDATE_CHAT_WINDOWS -- NO hooksecurefunc on FCF_OpenNewWindow: it is
    -- created from the same tab menu whose closures must stay untainted.

    -- One extra strip pass once the loading screen drops: Blizzard's final
    -- login dock update can re-show pieces of its (hidden) tab plane.
    do
        local pinFrame = CreateFrame("Frame")
        pinFrame:RegisterEvent("LOADING_SCREEN_DISABLED")
        pinFrame:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            PaintTabs()
            CHAT.ApplyTabLayout()
            -- Chat position ownership begins at the first settled sight:
            -- capture Edit Mode's placement as ours if unsaved, arm the
            -- anchor guard, kill the Edit Mode selection overlay, apply.
            if mod._CaptureChatPositionGenesis then
                mod._CaptureChatPositionGenesis()
            end
            if mod._GenesisSettle then
                mod._GenesisSettle()
            end
            if mod._InstallChatAnchorGuard then
                mod._InstallChatAnchorGuard()
            end
            if CHAT.SuppressChatEditModeSelection then
                CHAT.SuppressChatEditModeSelection()
            end
            if CHAT.ApplyChatPosition then
                CHAT.ApplyChatPosition()
            end
            -- Font size follows the profile: capture on first sight,
            -- re-assert on every later login.
            if CHAT.SyncChatFontSize then
                CHAT.SyncChatFontSize()
            end
            -- (ApplyChatPosition self-resyncs panels+strip one tick later,
            -- and the EDIT_MODE_LAYOUTS_UPDATED watcher re-asserts if Edit
            -- Mode's late layout apply lands after this.)
            -- Post-login heal window: Edit Mode's last write can land through
            -- paths none of the event answers see, leaving chat at EM's rect
            -- (short by the tab area) until the first hover armed the
            -- follower's drift heal. Run the state sync -- which carries that
            -- heal -- on a short bounded cadence instead, then self-destruct.
            local healTicks = 0
            local healFrame = CreateFrame("Frame")
            local healAccum = 0
            healFrame:SetScript("OnUpdate", function(wid, elapsed)
                healAccum = healAccum + elapsed
                if healAccum < 0.1 then
                    return
                end
                healAccum = 0
                healTicks = healTicks + 1
                if CHAT.SyncChatFrameState then
                    CHAT.SyncChatFrameState()
                end
                if healTicks >= 40 then
                    wid:SetScript("OnUpdate", nil)
                end
            end)
        end)
    end

    ---------------------------------------------------------------------------
    --  5. Tab color management. The deferred update batches multiple tab
    --     changes into one pass.
    ---------------------------------------------------------------------------
    -- Blizzard performs additional dock sizing after the initial chat setup, so
    -- text-derived widths are re-applied across a few deferred passes and saved
    -- Inner Padding X is correct without requiring a tab click.
    local function ApplyInitialTabLayout()
        PaintTabs()
        CHAT.ApplyTabLayout()
    end
    C_Timer.After(0, ApplyInitialTabLayout)
    C_Timer.After(0.10, ApplyInitialTabLayout)
    C_Timer.After(0.50, ApplyInitialTabLayout)
    local _tabColorTimer
    local function DeferredTabColorUpdate()
        if _tabColorTimer then
            return
        end
        _tabColorTimer = true
        C_Timer.After(0, function()
            _tabColorTimer = nil
            PaintTabs()
            CHAT.ApplyTabLayout()
        end)
    end
    CHAT._deferredTabColorUpdate = DeferredTabColorUpdate

    ---------------------------------------------------------------------------
    --  6. Idle fade: dims chat after N seconds of inactivity. Resets on player
    --     chat in a shown window (the selected tab or an undocked window), an
    --     incoming whisper, edit box focus/typing, or the cursor entering the
    --     chat area (event-driven, no polling).
    ---------------------------------------------------------------------------
    do
        local idleTicker = nil
        -- Hover state (UpdateHoverState below); read by OnActiveMessage.
        local _idleMouseOver = false
        local SetMessageWake -- with OnActiveMessage below

        local function IsIdleApplicable()
            local conf = CHAT.DB()
            local vis = conf.visibility or "always"
            return vis ~= "never"
        end

        local function StartIdleFade()
            if CHAT.DB().idleFadeEnabled == false then
                return
            end
            if _idleFadeActive then
                return
            end
            SetIdleFadeActive(true)
            CHAT.SetIdleFadeAlpha(GetIdleFadeAlpha())
            -- Faded: arm the hover-reveal motion overlay.

            if CHAT.ApplyIdleFadeHoverMotion then
                CHAT.ApplyIdleFadeHoverMotion()
            end
        end

        local function CancelIdleFade()
            local wasActive = _idleFadeActive
            SetIdleFadeActive(false)
            if idleTicker then
                idleTicker:Cancel()
                idleTicker = nil
            end
            if _visChatVisible then
                CHAT.SetIdleFadeAlpha(1)
            end
            -- Visible again: the overlay goes inert so the panel area is
            -- click- and camera-transparent like the default UI.
            if wasActive and CHAT.ApplyIdleFadeHoverMotion then
                CHAT.ApplyIdleFadeHoverMotion()
            end
        end

        function CHAT.ResetIdleTimer()
            CancelIdleFade()
            local conf = CHAT.DB()
            local enabled = IsIdleApplicable() and conf.idleFadeEnabled ~= false
            -- Chat lines wake the fade only while it can run: nothing per line otherwise.
            SetMessageWake(enabled)
            if not enabled then
                return
            end
            local delay = conf.idleFadeDelay or 15
            idleTicker = C_Timer.NewTimer(delay, StartIdleFade)
        end

        -- Visibility fully hid the chat: fade now and drop the leftover delay.
        function CHAT.StartIdleFadeNow()
            if not IsIdleApplicable() then
                return
            end
            if idleTicker then
                idleTicker:Cancel()
                idleTicker = nil
            end
            StartIdleFade()
        end

        -- Idle reset throttle: max once per second.
        local _lastIdleReset = 0
        local function OnNewMessage()
            -- (No passthrough sweep needed on messages anymore: Blizzard's
            -- line pool is parked in the engine's hidden container, and OUR
            -- message frames are hidden outright while passthrough is
            -- engaged -- a hidden frame arms nothing.)
            if not IsIdleApplicable() then
                return
            end
            -- Hidden by visibility: lines and whispers land unseen, so they must
            -- not wake the fade (StartIdleFadeNow) and flash the chat on reveal.
            if not _visChatVisible then
                return
            end
            local nowTime = GetTime()
            if nowTime - _lastIdleReset < 1 then
                return
            end
            _lastIdleReset = nowTime
            if _idleMouseOver then
                CancelIdleFade()
            else
                CHAT.ResetIdleTimer()
            end
        end

        -- Chat lines: the display engine's tail sees each line in the window
        -- Blizzard put it in, after its own channel, message-group and filter
        -- checks, so player chat (CHAT_MSG_EVENTS) wakes the fade only when
        -- that window is shown. Inside Blizzard's chat handler the observer
        -- only reads and shows a frame of ours; the reset runs on its next
        -- OnUpdate, outside that handler.
        local wakeFrame = CreateFrame("Frame")
        wakeFrame:Hide()
        wakeFrame:SetScript("OnUpdate", function(self)
            self:Hide()
            OnNewMessage()
        end)
        local function WakeOnChat(castFrame, evt)
            if evt == nil or wakeFrame:IsShown() then
                return
            end
            if issecretvalue and issecretvalue(evt) then
                return
            end
            if CHAT_MSG_EVENTS[evt] and castFrame:IsShown() then
                wakeFrame:Show()
            end
        end
        SetMessageWake = function(enabled)
            if CHAT.EngineSetIdleObserver then
                CHAT.EngineSetIdleObserver(enabled and WakeOnChat or nil)
            end
        end

        -- Permanent docked frames only (1-10): hooking a temp whisper edit box
        -- (11+) taints its execution context and poisons HistoryKeeper on
        -- BN_WHISPER. OnChar, not OnTextChanged: OnChar means "the user typed",
        -- and the engine never dispatches it from SetText, including the
        -- SetText("") inside Deactivate that writes chatType in the same
        -- execution. The trade is that OnChar misses backspace, paste and some
        -- IME paths, so composing by paste then pausing can fade chat mid-edit;
        -- any committed character un-fades it.
        CHAT._RegisterEditBoxFocusGained("CUI_Chat_IdleFade", function()
            OnNewMessage()
        end)
        for index = 1, 10 do
            local eb = _G["ChatFrame" .. index .. "EditBox"]
            if eb then
                eb:HookScript("OnChar", function(...)
                    OnNewMessage(...)
                end)
            end
        end

        ---------------------------------------------------------------------------
        --  7. Whisper sound alert (also resets idle fade for incoming
        --     whispers). Driven by a standalone EVENT FRAME, not a message
        --     filter: Blizzard wraps every filter in
        --     `if canaccessvalue(...) then callback(...) end`
        --     (ChatFrameFilters.lua), so a message carrying ANY value the
        --     addon cannot access -- the secret sender on every BN whisper --
        --     skips the filter entirely, even one that reads no arguments.
        --     Event registration on our own frame is outside Blizzard's
        --     dispatch and carries no taint.
        ---------------------------------------------------------------------------
        do
            local WHISPER_SOUND_PATHS, WHISPER_SOUND_NAMES, WHISPER_SOUND_ORDER =
                CludesUI.BuildAlertSoundTables()
            CHAT.WHISPER_SOUND_PATHS = WHISPER_SOUND_PATHS
            CHAT.WHISPER_SOUND_NAMES = WHISPER_SOUND_NAMES
            CHAT.WHISPER_SOUND_ORDER = WHISPER_SOUND_ORDER

            -- "none" (the stored default) keeps Blizzard's own whisper sound;
            -- "mute" silences it and plays nothing; any sound replaces it.
            WHISPER_SOUND_NAMES.none = "Blizzard Default"
            WHISPER_SOUND_NAMES.mute = "None"
            table.insert(WHISPER_SOUND_ORDER, 2, "mute")

            -- Append SharedMedia sounds
            CludesUI.AppendSharedMediaSounds(WHISPER_SOUND_PATHS, WHISPER_SOUND_NAMES, WHISPER_SOUND_ORDER)

            -- Blizzard's whisper sound (SOUNDKIT.TELL_MESSAGE plays this one
            -- file), muted while a non-default choice is set. A mute outlives
            -- /reload and relog (not a client restart), so the account-wide
            -- chatTellMuted flag remembers that the mute is ours: a character
            -- on Blizzard Default unmutes only a mute we made, never another
            -- addon's. Runs at init, from the setting and from
            -- _CUCHAT_RefreshAll (profile swaps, imports, spec overrides).
            local TELL_SOUND_FILE = 567421
            local _tellMuted = false
            function CHAT.ApplyWhisperMute()
                if not MuteSoundFile then
                    return
                end
                local conf = CHAT.DB()
                local key = conf and conf.whisperSoundKey
                local wanted = key ~= nil and key ~= "none"
                local saved = CludesUIDB
                if wanted then
                    if not _tellMuted then
                        MuteSoundFile(TELL_SOUND_FILE)
                        _tellMuted = true
                        if saved then
                            saved.chatTellMuted = true
                        end
                    end
                elseif _tellMuted or (saved and saved.chatTellMuted) then
                    UnmuteSoundFile(TELL_SOUND_FILE)
                    _tellMuted = false
                    if saved then
                        saved.chatTellMuted = nil
                    end
                end
            end
            CHAT.ApplyWhisperMute()
            -- Uninstall CUI: a mute of ours would outlive the reload.
            CludesUI.OnUninstall(function()
                if _tellMuted or (CludesUIDB and CludesUIDB.chatTellMuted) then
                    UnmuteSoundFile(TELL_SOUND_FILE)
                    _tellMuted = false
                    if CludesUIDB then
                        CludesUIDB.chatTellMuted = nil
                    end
                end
            end)

            local _whisperThrottle = 0
            local whisperWindow = CreateFrame("Frame")
            whisperWindow:RegisterEvent("CHAT_MSG_WHISPER")
            whisperWindow:RegisterEvent("CHAT_MSG_BN_WHISPER")
            whisperWindow:SetScript("OnEvent", function()
                OnNewMessage()
                local conf = CHAT.DB()
                local key = conf and conf.whisperSoundKey
                if not key or key == "none" or key == "mute" then
                    return
                end
                local nowTime = GetTime()
                if nowTime - _whisperThrottle < 5 then
                    return
                end
                _whisperThrottle = nowTime
                local filePath = WHISPER_SOUND_PATHS[key]
                if filePath then
                    PlaySoundFile(filePath, "Master")
                end
            end)
        end

        -- Event-driven hover detection: zero CPU when idle. Uses
        -- EnableMouseMotion on our bg frames + HookScript on tabs.
        -- EnableMouseMotion captures hover without blocking clicks but does
        -- block camera turning -- accepted trade-off for zero-poll.
        local _hoverCount = 0
        local _editFocusCount = 0

        local function SyncHover()
            local over = (_hoverCount > 0) or (_editFocusCount > 0)
            if not IsIdleApplicable() then
                return
            end
            if over and not _idleMouseOver then
                _idleMouseOver = true
                CancelIdleFade()
            elseif not over and (_idleMouseOver or not (idleTicker or _idleFadeActive)) then
                -- Also re-arm when nothing is armed: a hover that began while
                -- faded is cleared by the reveal (ApplyIdleFadeHoverMotion),
                -- so its leave would otherwise find no edge and no timer.
                _idleMouseOver = false
                CHAT.ResetIdleTimer()
            end
        end

        -- Single invisible overlay covering tabs + bg + sidebar, at BACKGROUND strata.
        -- Its mouse motion is conditional -- see ApplyIdleFadeHoverMotion below.
        do
            local generalFrame = _G.ChatFrame1
            local gdm = _G.GeneralDockManager
            local bg1 = CFD(generalFrame).bg
            local scrollBar = CFD(generalFrame).sidebar
            if bg1 and gdm then
                local overlayFrame = CreateFrame("Frame", nil, UIParent)
                mod._chatHoverOverlay = overlayFrame
                overlayFrame:SetPoint("TOPLEFT", gdm, "TOPLEFT", scrollBar and -40 or 0, 0)
                overlayFrame:SetPoint("BOTTOMRIGHT", bg1, "BOTTOMRIGHT", 0, 0)
                overlayFrame:SetFrameStrata("BACKGROUND")
                overlayFrame:EnableMouse(false)
                -- Peek reveal: motion is live ONLY while idle-faded (see
                -- ApplyIdleFadeHoverMotion), so an enter here can only mean
                -- the user moused over the faded chat. No OnLeave needed --
                -- the reveal itself turns motion back off.
                overlayFrame:SetScript("OnEnter", function()
                    if _idleFadeActive and CHAT.ResetIdleTimer then
                        CHAT.ResetIdleTimer()
                    end
                end)
                -- Motion capture is needed ONLY while the chat is idle-faded (to catch
                -- the reveal hover). While visible the overlay must be inert so clicks
                -- AND camera drags over the panel reach the world exactly like the
                -- default UI (EnableMouseMotion intercepts right-drag camera input even
                -- though it passes clicks). Passthrough (full hide) keeps it inert too.
                function CHAT.ApplyIdleFadeHoverMotion()
                    local conf = CHAT.DB()
                    local enabled = conf.idleFadeEnabled ~= false
                        and (conf.visibility or "always") ~= "never"
                        and mod._chatPassthrough ~= true
                        and _idleFadeActive
                    -- Per-channel setters, and click pinned OFF every pass:
                    -- EnableMouseMotion toggling alone leaves the click
                    -- channel armed, which made this overlay an invisible
                    -- click-catcher over the VISIBLE chat -- clicks and
                    -- camera dead, undetectable by motion-based probes.
                    if overlayFrame.SetMouseClickEnabled then
                        overlayFrame:SetMouseClickEnabled(false)
                    end
                    if overlayFrame.SetMouseMotionEnabled then
                        overlayFrame:SetMouseMotionEnabled(enabled)
                    else
                        overlayFrame:EnableMouseMotion(enabled)
                    end
                    if not enabled then
                        _hoverCount = 0
                        _idleMouseOver = false
                    end
                end
                CHAT.ApplyIdleFadeHoverMotion()
            end
        end

        -- Sidebar has EnableMouse(true) which blocks the overlay beneath it.
        -- HookScript on our own frame -- safe, no taint.
        local sideBar = CFD(ChatFrame1).sidebar
        if sideBar then
            sideBar:HookScript("OnEnter", function()
                _hoverCount = _hoverCount + 1
                SyncHover()
                if CHAT.FollowArm then
                    CHAT.FollowArm()
                end
            end)
            sideBar:HookScript("OnLeave", function()
                _hoverCount = upper(0, _hoverCount - 1)
                SyncHover()
                if CHAT.FollowRelease then
                    CHAT.FollowRelease()
                end
            end)
        end

        -- Edit box focus tracking -- only ChatFrame1 (permanent, no secret
        -- values). Hooking temp whisper edit boxes (11+) taints their
        -- execution context, causing secret value errors on BN_WHISPER tellTarget.
        local eb1 = _G["ChatFrame1EditBox"]
        if eb1 then
            -- Neither side can be a HookScript: GAINED is dispatched by the
            -- SetFocus() inside ChatFrameUtil.ActivateChat, which then writes
            -- chatType in UpdateHeader(), and LOST runs on into DeactivateChat
            -- -> Deactivate, which writes it after its own dispatches. Blizzard
            -- triggers both callbacks from the first line of the matching
            -- handler, so the timing is unchanged and the counter still pairs
            -- exactly.
            CHAT._RegisterEditBoxFocusGained("CUI_Chat_HoverEditFocus", function(eb)
                if eb ~= eb1 then
                    return
                end
                _editFocusCount = _editFocusCount + 1
                SyncHover()
            end)
            if EventRegistry and EventRegistry.RegisterCallback then
                EventRegistry:RegisterCallback("ChatFrame.OnEditBoxFocusLost", function(_, eb)
                    if eb ~= eb1 then
                        return
                    end
                    _editFocusCount = upper(0, _editFocusCount - 1)
                    SyncHover()
                end, "CUI_Chat_HoverEditFocus")
            end
        end

        -- Start the initial timer
        CHAT.ResetIdleTimer()
    end

    ---------------------------------------------------------------------------
    --  7. Accent color + timestamps
    ---------------------------------------------------------------------------
    CUI.RegAccent({ type = "callback", fn = PaintTabs })

    -- Enable scroll-to-scroll chat (Blizzard disables by default)
    CludesUI.SetCVar("chatMouseScroll", 1, "CludesUIChat")

    -- Seed the engine's stamp-all transform with the RESOLVED format:
    -- explicit formats pass through, "__blizzard" resolves to Blizzard's own
    -- setting, "none" (either source) disarms it.
    local function ApplyStampAll()
        if not CHAT.EngineSetStampAll then
            return
        end
        local conf = CHAT.DB()
        local formatStr = conf.timestampFormat or "%I:%M "
        if formatStr == "none" then
            formatStr = nil
        elseif formatStr == "__blizzard" then
            local success, frame = pcall(function()
                return ChatFrameUtil
                    and ChatFrameUtil.GetTimestampFormat
                    and ChatFrameUtil.GetTimestampFormat()
            end)
            formatStr = (success and type(frame) == "string" and frame ~= "" and frame ~= "none") and frame or nil
        end
        CHAT.EngineSetStampAll(conf.timestampAll == true and formatStr ~= nil, formatStr)
    end
    CHAT.ApplyStampAll = ApplyStampAll

    local function ApplyTimestampCVar()
        ApplyStampAll()
        local conf = CHAT.DB()
        local formatStr = conf.timestampFormat or "%I:%M "
        if formatStr == "__blizzard" then
            return
        end
        CludesUI.SetCVar("showTimestamps", formatStr, "CludesUIChat")
    end
    ApplyTimestampCVar()
    C_Timer.After(2, ApplyTimestampCVar)
    CHAT.ApplyTimestampCVar = ApplyTimestampCVar

    ---------------------------------------------------------------------------
    --  8. Apply all visual settings from DB
    ---------------------------------------------------------------------------
    CHAT.ApplySidebarVisibility()
    -- ApplyBorders is DEFERRED out of the PLAYER_LOGIN execution: running it
    -- synchronously here chains into ApplyExtendedBackground, which plants the panel
    -- border's anchors in ChatFrame1's rect web WHILE Blizzard's login dock pass is
    -- still resolving layout -- that pass then reads our insecure anchors, runs
    -- tainted, and its persistent dock state poisons every later temp-whisper open
    -- (FCFManager_GetChatTarget/ GetDecoratedSenderName secret errors). The deferred
    -- tab passes (PEW + C_Timer) are the proven-clean home for this work instead.
    do
        local bordersDefer = CreateFrame("Frame")
        bordersDefer:RegisterEvent("PLAYER_ENTERING_WORLD")
        bordersDefer:SetScript("OnEvent", function(self)
            self:UnregisterAllEvents()
            C_Timer.After(0, function()
                CHAT.ApplyBorders()
                -- Stock styles: the Blizzard chat art re-seat rides the same
                -- deferred cadence (see SeatStockBackground); later windows
                -- are seated by the state sync. Not under WoW Forever: its
                -- input box is placed like the CludesUI look's.
                if mod.ChatStockArt() then
                    CHAT._stockSeatArmed = true
                    for index = 1, 20 do
                        local castFrame = _G["ChatFrame" .. index]
                        if castFrame then
                            CHAT.SeatStockBackground(castFrame)
                        end
                    end
                end
                -- The stored window colour, re-read once settled.
                if CHAT.SB_SyncBackdrop then
                    CHAT.SB_SyncBackdrop(true)
                end
            end)
        end)
    end
    -- ECHAT.ApplySidebarIcons() -- causes taint (full layout chain)
    -- Apply individual icon visibility from DB without the layout chain.
    do
        local _cfg = CHAT.DB()
        local _cf1 = _G.ChatFrame1
        if _cfg and _cf1 then
            local _sbd = CFD(_cf1)
            if _sbd.scrollBtn then
                _sbd.scrollBtn:SetShown(_cfg.showScroll ~= false)
            end
            if _sbd.friendsBtn then
                _sbd.friendsBtn:SetShown(_cfg.showFriends ~= false)
            end
            if _sbd.durabilityBtn then
                _sbd.durabilityBtn:SetShown(_cfg.showDurability ~= false)
            end
            if _sbd.copyBtn then
                _sbd.copyBtn:SetShown(_cfg.showCopy ~= false)
            end
            if _sbd.portalBtn then
                _sbd.portalBtn:SetShown(_cfg.showPortals ~= false)
            end
            if _sbd.voiceBtn then
                _sbd.voiceBtn:SetShown(_cfg.showVoice ~= false)
            end
            if _sbd.chatMenuBtn then
                _sbd.chatMenuBtn:SetShown(_cfg.showChatMenu ~= false)
            end
            if _sbd.settingsBtn then
                _sbd.settingsBtn:SetShown(_cfg.showSettings ~= false)
            end
        end
    end
    CHAT.ApplySidebarWidth()
    CHAT.ApplySidebarPosition()
    CHAT.ApplyIconColor()
    CHAT.ApplyInputPosition()
    CHAT.ApplySidebarBackground()
    CHAT.ApplySidebarIconScale()
    CHAT.ApplyIconFreeMove()
    CHAT.ApplyLockChatSize()

    -- Profile-swap refresh: re-apply all chat visuals from the (already- swapped) DB --
    -- ECHAT.DB() reads the live profile dynamically, so re-running the Apply functions
    -- pulls the new profile's settings. ApplySidebarIcons() is deliberately NOT called
    -- here -- its full ClearAllPoints/SetPoint layout chain is taint-risky (skipped at
    -- init too); icon visibility uses the same minimal SetShown block as init, and
    -- position/scale/free-move are covered by the Apply* calls below.
    _G._CUCHAT_RefreshAll = function()
        CHAT.ApplySidebarVisibility()
        CHAT.ApplyBorders()
        do
            local _cfg = CHAT.DB()
            local _cf1 = _G.ChatFrame1
            if _cfg and _cf1 then
                local _sbd = CFD(_cf1)
                if _sbd.scrollBtn then
                    _sbd.scrollBtn:SetShown(_cfg.showScroll ~= false)
                end
                if _sbd.friendsBtn then
                    _sbd.friendsBtn:SetShown(_cfg.showFriends ~= false)
                end
                if _sbd.durabilityBtn then
                    _sbd.durabilityBtn:SetShown(_cfg.showDurability ~= false)
                end
                if _sbd.copyBtn then
                    _sbd.copyBtn:SetShown(_cfg.showCopy ~= false)
                end
                if _sbd.portalBtn then
                    _sbd.portalBtn:SetShown(_cfg.showPortals ~= false)
                end
                if _sbd.voiceBtn then
                    _sbd.voiceBtn:SetShown(_cfg.showVoice ~= false)
                end
                if _sbd.chatMenuBtn then
                    _sbd.chatMenuBtn:SetShown(_cfg.showChatMenu ~= false)
                end
                if _sbd.settingsBtn then
                    _sbd.settingsBtn:SetShown(_cfg.showSettings ~= false)
                end
            end
        end
        CHAT.ApplySidebarWidth()
        CHAT.ApplySidebarPosition()
        CHAT.ApplyIconColor()
        CHAT.ApplyInputPosition()
        CHAT.ApplySidebarBackground()
        CHAT.ApplySidebarIconScale()
        CHAT.ApplyIconFreeMove()
        CHAT.ApplyLockChatSize()
        CHAT.ApplyBackground()
        CHAT.ApplyFonts()
        if CHAT.RefreshVisibility then
            CHAT.RefreshVisibility()
        end
        -- The new profile's idle fade settings (and whether chat lines wake it).
        if CHAT.ResetIdleTimer then
            CHAT.ResetIdleTimer()
        end
        -- The passes above can build panel chrome (borders, the tab-band
        -- extension) that did not exist when the house editor opened.
        CHAT.ApplyPanelHost()
        CHAT.ApplyWhisperMute()
    end

    ---------------------------------------------------------------------------
    --  9-12. Chat positioning: OURS via the unlock element.
    ---------------------------------------------------------------------------
    --[[ Chat position is OURS (unlock element + genesis capture + anchor
    -- guard). HARD CONSTRAINTS from the failed first attempt, still binding:
    -- ChatFrame1 is NEVER reparented (Edit Mode's UpdateSystemAnchorInfo
    -- assumes a UIParent child; a reparented chat came back with NO anchors
    -- -- unmovable, unresizable) and its SetPoint is NEVER hooked. Position
    -- enforcement is ONLY the deferred ApplySystemAnchor post-hook; the Edit
    -- Mode Selection overlay is suppressed IN PLACE (alpha + mouse), never
    -- reparented -- Edit Mode still drives that region. Chat SIZE stays
    -- Blizzard's (the resize grip). ]]

    ---------------------------------------------------------------------------
    --  12b. BNet Toast notification -- position via unlock mode
    ---------------------------------------------------------------------------
    do
        local toastFrame = _G.BNToastFrame
        if toastFrame then
            -- Apply saved position or default to bottom-right of chat bg
            local function PlaceToast()
                local conf = CHAT.DB()
                if not conf or not conf.toastPosition then
                    return
                end
                local place = conf.toastPosition
                if not place.point then
                    return
                end
                local px, py = place.x or 0, place.y or 0
                local PPa = CUI and CUI.PP
                if PPa and PPa.SnapForES then
                    local effScale = toastFrame:GetEffectiveScale()
                    px = PPa.SnapForES(px, effScale)
                    py = PPa.SnapForES(py, effScale)
                end
                toastFrame:ClearAllPoints()
                toastFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, px, py)
            end

            -- Enforce saved position when Blizzard tries to reposition; skip
            -- during unlock mode so the user can drag freely. NOT
            -- hooksecurefunc(toast, "SetPoint", ...): that form assigns
            -- toast.SetPoint = wrapper, a FIELD WRITE onto BNToastFrame's
            -- table (same hazard as the edit box in SkinEditBox). Blizzard reads that
            -- field whenever it anchors the toast, so the tainted read lands inside the
            -- Battle.net toast chain -- the same chain that opens a BN whisper and puts
            -- a SECRET target name into ChatFrame1EditBox.text. OnShow is a script hook
            -- (C-side, no field write) and fires on every toast, the only moment the
            -- position matters; the deferred call lets Blizzard finish its own
            -- anchoring first. Same shape as the FCFDock_SelectWindow hook this module
            -- already replaced for taint reasons.
            toastFrame:HookScript("OnShow", function()
                if CUI._unlockActive then
                    return
                end
                local conf = CHAT.DB()
                if not (conf and conf.toastPosition) then
                    return
                end
                C_Timer.After(0, function()
                    if CUI._unlockActive then
                        return
                    end
                    local c = CHAT.DB()
                    if c and c.toastPosition then
                        PlaceToast()
                    end
                end)
            end)

            -- Apply saved position or set default (above chat frame)
            C_Timer.After(0, function()
                local conf = CHAT.DB()
                if conf and not conf.toastPosition then
                    -- Default: anchor to top of chat bg
                    local cf1bg = _G.ChatFrame1 and CFD(_G.ChatFrame1).bg
                    if cf1bg then
                        toastFrame:ClearAllPoints()
                        toastFrame:SetPoint("BOTTOMLEFT", cf1bg, "TOPLEFT", 0, 30)
                        -- Snapshot the absolute position
                        local effScale = toastFrame:GetEffectiveScale()
                        local uiScale = UIParent:GetEffectiveScale()
                        local cx, cy = toastFrame:GetCenter()
                        local uCX, uCY = UIParent:GetCenter()
                        if cx and uCX then
                            conf.toastPosition = {
                                point = "CENTER",
                                relPoint = "CENTER",
                                x = (cx * effScale - uCX * uiScale) / uiScale,
                                y = (cy * effScale - uCY * uiScale) / uiScale,
                            }
                        end
                    end
                end
                PlaceToast()
            end)

            -- Register with unlock mode
            if CUI.RegisterUnlockElements then
                local MK = CUI.MakeUnlockElement
                CUI:RegisterUnlockElements({
                    MK({
                        key = "ECHAT_BNToast",
                        label = "BNet Toast",
                        group = "Chat",
                        order = 601,
                        noAnchorTo = true,
                        noResize = true,
                        getFrame = function()
                            return toastFrame
                        end,
                        getSize = function()
                            return toastFrame:GetWidth(), toastFrame:GetHeight()
                        end,
                        isHidden = function()
                            return false
                        end,
                        savePos = function(_, anchorPoint, relPoint, posX, posY)
                            local conf = CHAT.DB()
                            if not conf then
                                return
                            end
                            conf.toastPosition = {
                                point = anchorPoint,
                                relPoint = relPoint or anchorPoint,
                                x = posX,
                                y = posY,
                            }
                            if not CUI._unlockActive then
                                PlaceToast()
                            end
                        end,
                        loadPos = function()
                            local conf = CHAT.DB()
                            if not conf then
                                return nil
                            end
                            return conf.toastPosition
                        end,
                        clearPos = function()
                            local conf = CHAT.DB()
                            if not conf then
                                return
                            end
                            conf.toastPosition = nil
                        end,
                        applyPos = function()
                            PlaceToast()
                        end,
                    }),
                })
            end
        end
    end

    ---------------------------------------------------------------------------
    --  12c. Main chat: a REAL unlock element. Drag saves cfg.chatPosition;
    --       everything downstream (panels, our text, the ghost tab strip)
    --       follows ChatFrame1 through the existing numeric machinery.
    ---------------------------------------------------------------------------
    if CUI.RegisterUnlockElements then
        local MK = CUI.MakeUnlockElement
        CUI:RegisterUnlockElements({
            MK({
                key = "ECHAT_MainChat",
                label = "Chat",
                group = "Chat",
                order = 600,
                noResize = true,
                -- Chat alone places ChatFrame1 from its saved spot (Edit Mode
                -- applies its own on every layout apply): an anchor link would be
                -- a third owner, and a link saved before (the old WoW Forever base
                -- layout made one) kept dragging chat back to its stale spot.
                ownsPosition = true,
                -- Relative to Screen (the cog) names the screen point chat's
                -- saved spot is measured from; chat keeps it, no link.
                getScreenPoint = function()
                    return mod.GetChatScreenPoint()
                end,
                setScreenPoint = function(_, anchorPoint)
                    mod.SetChatScreenPoint(anchorPoint)
                end,
                getFrame = function()
                    return _G.ChatFrame1
                end,
                getSize = function()
                    local generalFrame = _G.ChatFrame1
                    return generalFrame:GetWidth(), generalFrame:GetHeight()
                end,
                isHidden = function()
                    return false
                end,
                -- The mover places ChatFrame1 with one anchor per drag tick /
                -- nudge; our size rides a second corner (SetSize is banned on
                -- the main window), so restore it after every placement.
                onLiveMove = function()
                    if mod._KeepMainChatSizeCorner then
                        mod._KeepMainChatSizeCorner()
                    end
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    local conf = CHAT.DB()
                    if not conf then
                        return
                    end
                    conf.chatPosition =
                        { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
                    if not CUI._unlockActive then
                        CHAT.ApplyChatPosition()
                    end
                end,
                loadPos = function()
                    local conf = CHAT.DB()
                    return conf and conf.chatPosition or nil
                end,
                clearPos = function()
                    -- Back to Edit Mode's default spot and size (the store
                    -- holds ours until reset); the next settled sight
                    -- re-captures that as the new genesis.
                    local conf = CHAT.DB()
                    if conf then
                        conf.chatPosition = nil
                        conf.chatSize = nil
                    end
                    if CUI._unlockActive then
                        mod._chatUnlockReset = true
                    else
                        mod.EMChatResetStore()
                    end
                end,
                applyPos = function()
                    CHAT.ApplyChatPosition()
                end,
            }),
        })
    end
    -- The geometry follower runs for the whole unlock session so the panel
    -- and text track the Chat mover per-frame instead of snapping after.
    -- Both session edges re-assert the saved rect from the DB: on open, so
    -- the mover measures the true (size-composed) rect even if a one-anchor
    -- placement elsewhere left the frame on its explicit size; on close, so
    -- the committed or reverted position lands composed in the same
    -- execution (the drift heal is suspended for the session and would
    -- otherwise be the first thing to notice, one tick later). The close's
    -- apply hands a committed move to the Edit Mode store (its store pass);
    -- a committed Reset puts Edit Mode's default back (the commit runs
    -- before this edge).
    CUI:RegisterUnlockModeListener("CludesUIChat", function(isActive)
        if CHAT.FollowArmUnlock then
            CHAT.FollowArmUnlock(isActive)
        end
        if CHAT.ApplyChatPosition then
            CHAT.ApplyChatPosition()
        end
        if not isActive and mod._chatUnlockReset then
            mod._chatUnlockReset = nil
            mod.EMChatResetStore()
        end
    end)

    ---------------------------------------------------------------------------
    --  13. Visibility system registration
    ---------------------------------------------------------------------------
    CHAT.RefreshVisibility()
    CUI.RegisterVisibilityUpdater(CHAT.RefreshVisibility)

    ---------------------------------------------------------------------------
    --  14. Hide Blizzard social buttons (quick join, menu, channel, voice)
    ---------------------------------------------------------------------------
    for _, frameName in ipairs({
        "QuickJoinToastButton",
        "ChatFrameMenuButton",
        "ChatFrameChannelButton",
        "ChatFrameToggleVoiceDeafenButton",
        "ChatFrameToggleVoiceMuteButton",
    }) do
        local frame = _G[frameName]
        if frame then
            frame:SetAlpha(0)
            frame:EnableMouse(false)
        end
    end
    -- Chat Menu: the menu button back over its icon, mouse on while shown.
    CHAT.SeatChatMenu()
end)

Inner.broken = false
