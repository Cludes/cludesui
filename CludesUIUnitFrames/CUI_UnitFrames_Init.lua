if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Init.lua
--
--  InitializeFrames, published as I.InitializeFrames for EnableBody
--  (CUI_UnitFrames_Lifecycle.lua), which calls it once: spawns the unit frames,
--  takes over the Blizzard ones and builds the visibility pass. Reads the main
--  file and CUI_UnitFrames_Visibility.lua through ns and ns._internals; db is
--  set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue
local Pix = CludesUI.PP
local CLASS_FULL_COORDS = CludesUI.CLASS_ICON_SPRITE_COORDS

local Inner = mod._internals
local frameList, GetSettingsForUnit, UnsnapTex, SetFSFont =
    Inner.frames, Inner.GetSettingsForUnit, Inner.UnsnapTex, Inner.SetFSFont
local ApplyFramePosition, ReloadFrames, ApplyBlizzCastbarState =
    Inner.ApplyFramePosition, Inner.ReloadFrames, Inner.ApplyBlizzCastbarState
local ApplyAbsorbStyle, ApplyClassColor, ApplyDetachedPortraitShape =
    Inner.ApplyAbsorbStyle, Inner.ApplyClassColor, Inner.ApplyDetachedPortraitShape
local CreateCustomClassPower, DestroyCustomClassPower, IsKickCastbarUnit =
    Inner.CreateCustomClassPower, Inner.DestroyCustomClassPower, Inner.IsKickCastbarUnit
local StyleFullFrame, StyleFocusFrame, StyleSimpleFrame, StyleBossFrame =
    Inner.StyleFullFrame, Inner.StyleFocusFrame, Inner.StyleSimpleFrame, Inner.StyleBossFrame
local UnitFrame_OnEnter, UnitFrame_OnLeave = Inner.UnitFrame_OnEnter, Inner.UnitFrame_OnLeave
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

local function InitializeFrames()
    -- The engine's shared class and power colors from the suite palette, before any
    -- frame spawns. Only the sync: a full colors pass here would repaint every module
    -- at login while nothing changed.
    CludesUI.SyncUFColors()

    local classPowerStyle = saved.profile.player.classPowerStyle or "none"
    -- Forever has no Blizzard class resource bar to adopt (see the ComboFrame
    -- note below) and the options page greys that entry out there: a stored
    -- "blizzard" builds as the modern style (ns.UF_ForeverCPStyle), and the
    -- options page shows and gates it as Modern. Read-side only: the stored
    -- style is never rewritten, so a spec override or an import that carries
    -- it keeps it. The Forever defaults themselves (modern, shown, above, 16)
    -- are IS_FOREVER conditionals in DEFAULTS.player; nothing is seeded or
    -- migrated here. Under the WoW Forever style that entry is the combo
    -- point arc on our target or player frame (Combo Points;
    -- ns.UF_ApplyForeverComboArc) and stands.
    if mod.UF_ForeverCPStyle then
        classPowerStyle = mod.UF_ForeverCPStyle(classPowerStyle)
    end
    -- Per-unit frame source, resolved once for this build. When a unit is set to
    -- "blizzard" (leave Blizzard's default frame) or "hidden", the CludesUI frame is
    -- not spawned at all -- the ONLY way to keep Blizzard's own frame alive, since
    -- oUF:Spawn() permanently disables it.
    local playerFrameSource = mod.GetUnitFrameSource("player")
    -- Per-class Blizzard class power bar frame names
    local BLIZZARD_CP_FRAMES = {
        DEATHKNIGHT = "RuneFrame",
        DRUID = "DruidComboPointBarFrame",
        EVOKER = "EssencePlayerFrame",
        MAGE = "MageArcaneChargesFrame",
        MONK = "MonkHarmonyBarFrame",
        PALADIN = "PaladinPowerBarFrame",
        ROGUE = "RogueComboPointBarFrame",
        WARLOCK = "WarlockPowerFrame",
    }
    -- External state for Blizzard class power bars (never write onto
    -- Blizzard frames -- see CLAUDE.md _FFD rule).
    local _blizzCPState = {} -- { origParent, hooked }
    local storedClassPower = nil
    -- Only take over the Blizzard class power bar when the CUI player frame is
    -- actually being spawned; otherwise leave it to Blizzard's player frame.
    if classPowerStyle == "blizzard" and playerFrameSource == "cui" then
        local _, class = UnitClass("player")
        local frameName = BLIZZARD_CP_FRAMES[class]
        local classPowerFrame = frameName and _G[frameName]
        if classPowerFrame then
            storedClassPower = classPowerFrame
            -- A Blizzard parent only: another owner's frame (Resource Bars' Blizzard
            -- Class Resource Art host) must never become the hand-back target.
            local current = classPowerFrame:GetParent()
            _blizzCPState.origParent = (current == classPowerFrame.layoutParent or current == PlayerFrame) and current
                or (classPowerFrame.layoutParent or PlayerFrame)
            classPowerFrame:SetParent(UIParent)
        end
    end

    local enabled = saved.profile.enabledFrames

    local function SetupUnitMenu(widget, unitToken)
        -- Register ALL mouse buttons (matches raid/party's "AnyUp"), not just
        -- left/right. These frames bind nothing to middle/thumb themselves, so
        -- an unbound middle/thumb click still does nothing here -- but Blizzard's
        -- built-in click-casting (and Clique) sets its own type3/type4/type5
        -- attributes on frames registered in ClickCastFrames, and needs the
        -- click event to actually be delivered to fire. Left-button-only
        -- registration silently ate those clicks whenever CUI's own click-cast
        -- engine wasn't the one driving RegisterForClicks (i.e. CUI's engine
        -- disabled, native/Clique click-casting relied on instead).
        widget:RegisterForClicks("AnyUp")
        -- 12.0.7 gates SecureUnitButton's togglemenu; route right-click securely
        -- through a SecureActionButton proxy so the menu (and its protected items
        -- like Set Focus) work without taint.
        if CludesUI.AttachSecureUnitMenu then
            CludesUI.AttachSecureUnitMenu(widget)
        else
            widget:SetAttribute("*type2", "togglemenu")
        end
        widget:HookScript("OnEnter", UnitFrame_OnEnter)
        widget:HookScript("OnLeave", UnitFrame_OnLeave)
        -- Expose to click-casting via the standard global table. CUI unit frames
        -- replace the Blizzard ones, which the click-cast engine registers by name --
        -- but those are hidden, so the engine never reaches the visible frames.
        -- Registering ours here lets click-casting (CUI's engine when "All Unit
        -- Frames" is on, or Clique otherwise) apply the same bindings + unbound-click
        -- suppression it uses on raid/party. The engine captures/restores each
        -- frame's native click attrs, so these keep their own defaults (no forced
        -- left-click target) when click-cast is off.
        if type(ClickCastFrames) ~= "table" then
            ClickCastFrames = {}
        end
        ClickCastFrames[widget] = true
        -- NO ping mixin here, deliberately (three field rounds, 2026-08-24):
        -- an addon-installed PingableType mixin CANNOT serve secret-content
        -- units. Reading our tainted GetIsPingable inside PingManager's
        -- securecalled helper taints that execution, every unit value
        -- Blizzard's own mixin then fetches comes back tainted-restricted,
        -- and the secure caller's securecopy of the GetTargetInfo table
        -- hard-errors ("inaccessible secret") -- even with our getter
        -- returning nil. The reported enemy-target-frame ping error also
        -- reproduces with NO CUI receiver in the path (pre-mixin trace, No
        -- Lua Taint) and is upstream. Do not re-attempt.
    end

    -- Spawn each unit's CludesUI frame only when its source is "cui". A unit set to
    -- "blizzard" keeps Blizzard's own frame (we never spawn or suppress for it);
    -- "hidden" removes Blizzard's frame too.
    if playerFrameSource == "cui" then
        -- Spawning enables the Castbar element, which silences Blizzard's
        -- player/pet cast bars. Keep whatever a standalone cast bar addon set.
        CludesUI.CaptureBlizzCastBarEvents()
        frameList.player = mod.Engine.SpawnUnitFrame("player", "CludesUIUnitFrames_Player")
        StyleFullFrame(frameList.player, "player")
        mod.UF_AttachEngineFrame(frameList.player, "player")
        CludesUI.RestoreBlizzCastBarEvents()
    elseif playerFrameSource == "hidden" then
        -- Wrapped for the same reason as the spawn above: the suppression
        -- unregisters PlayerFrame's cast bar child, and an unregister seen
        -- outside a capture window reads as a third-party addon claiming the
        -- frame -- CUI would mark its own silence as somebody else's and
        -- never hand the bar back.
        CludesUI.CaptureBlizzCastBarEvents()
        mod.Engine.HideBlizzardUnitFrame("player")
        CludesUI.RestoreBlizzCastBarEvents()
    end

    -- Visibility wrapper for the player frame only. Parent the player frame to a
    -- non-secure wrapper and drive visibility via the wrapper's alpha instead of the
    -- frame's own: alpha inherits multiplicatively down the parent chain, so the
    -- wrapper's alpha wins regardless of anything touching the inner frame's alpha
    -- directly (oUF elements, combat transitions, etc.). Target/focus/pet don't need
    -- this since RegisterUnitWatch already handles their visibility via unit
    -- existence. The wrapper is inserted between the player frame and whatever parent
    -- oUF originally gave it (PetBattleFrameHider), so the pet-battle state driver
    -- chain continues to work.
    if frameList.player then
        local origParent = frameList.player:GetParent() or UIParent
        local playerVisWrap = CreateFrame("Frame", nil, origParent)
        playerVisWrap:SetAllPoints(origParent)
        playerVisWrap:SetFrameStrata(frameList.player:GetFrameStrata())
        frameList.player:SetParent(playerVisWrap)
        frameList.player._visWrap = playerVisWrap

        ApplyFramePosition(frameList.player, "player")
        SetupUnitMenu(frameList.player, "player")

        if enabled.player == false then
            frameList.player:Hide()
            frameList.player:SetAttribute("unit", nil)
        end
    end

    -- (Combat indicator overlay moved below the target/focus spawns -- the
    -- target frame does not exist yet at this point in the setup.)

    -- Rested indicator on player health bar top-left: "ZZZ" text, or
    -- Blizzard's animated player frame rest icon when Animated is on.
    do
        local popFrame = frameList.player
        if popFrame and popFrame.Health then
            if not popFrame._restHolder then
                popFrame._restHolder = CreateFrame("Frame", nil, popFrame.Health)
                local restText = popFrame._restHolder:CreateFontString(nil, "OVERLAY")
                SetFSFont(restText, 9)
                restText:SetTextColor(1, 1, 1)
                restText:SetText("ZZZ")
                restText:Hide()
                popFrame._restText = restText

                local function PlaceRest(regionFrame)
                    local rx = (CludesUIDB and CludesUIDB.restedIndicatorXOffset) or 0
                    local ry = (CludesUIDB and CludesUIDB.restedIndicatorYOffset) or 0
                    regionFrame:ClearAllPoints()
                    regionFrame:SetPoint("TOPLEFT", popFrame.Health, "TOPLEFT", 3 + rx, -2 + ry)
                end
                -- Places the text, and the animated icon once built, at the cog's X/Y
                -- offsets (and the icon at its Size).
                popFrame._restPlace = function()
                    PlaceRest(popFrame._restText)
                    local a = popFrame._restAnim
                    if a then
                        local size = (CludesUIDB and CludesUIDB.restedIndicatorAnimatedSize) or 24
                        a:SetSize(size, size)
                        PlaceRest(a)
                    end
                end

                -- Shows the style the settings pick (or neither) and hides the other.
                -- The animated icon is built the first time it is needed.
                popFrame._restUpdate = function()
                    local saved = CludesUIDB
                    local enabled = saved and saved.showRestedIndicator == true or false
                    -- Rest changes are listened to only while the indicator is on.
                    if enabled ~= popFrame._restListening then
                        popFrame._restListening = enabled
                        local ef = popFrame._restEventFrame
                        if enabled then
                            ef:RegisterEvent("PLAYER_UPDATE_RESTING")
                            ef:RegisterEvent("PLAYER_ENTERING_WORLD")
                        else
                            ef:UnregisterAllEvents()
                        end
                    end
                    local enabled = enabled and IsResting() or false
                    local animated = saved and saved.restedIndicatorAnimated == true or false
                    if enabled and animated and not popFrame._restAnim then
                        -- On the unit frame, not the health bar: the bar sits in the frame's
                        -- bar clip, which would cut off the z's as they float up past its edge.
                        -- Its level keeps it above that clip, which draws as one group.
                        local restAnim = CreateFrame("Frame", nil, popFrame)
                        restAnim:SetFrameLevel(((popFrame._barClip or popFrame):GetFrameLevel()) + 10)
                        restAnim:Hide()
                        local restTex = restAnim:CreateTexture(nil, "OVERLAY")
                        restTex:SetAllPoints(restAnim)
                        CludesUI.AddRestFlipbook(restAnim, restTex)
                        popFrame._restAnim = restAnim
                        popFrame._restPlace()
                    end
                    popFrame._restText:SetShown(enabled and not animated)
                    if popFrame._restAnim then
                        popFrame._restAnim:SetShown(enabled and animated)
                    end
                end

                -- Its events are registered by _restUpdate while the indicator is on.
                popFrame._restEventFrame = CreateFrame("Frame", nil, popFrame)
                popFrame._restEventFrame:SetScript("OnEvent", function()
                    popFrame._restUpdate()
                end)
            end
            popFrame._restHolder:SetAllPoints(popFrame.Health)
            popFrame._restHolder:SetFrameLevel(popFrame.Health:GetFrameLevel() + 5)
            popFrame._restPlace()
            popFrame._restUpdate()
        end
    end

    -- Castbar state is managed by ApplyBlizzCastbarState (called here and also
    -- from ReloadFrames so toggling the setting works without a /reload).
    ApplyBlizzCastbarState()

    -- Re-apply after zone changes and after Edit Mode closes, both of which
    -- can cause Blizzard to reparent or re-hide the cast bar.
    if not frameList._cbSuppressFrame then
        frameList._cbSuppressFrame = CreateFrame("Frame")
        frameList._cbSuppressFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frameList._cbSuppressFrame:RegisterEvent("EDIT_MODE_LAYOUTS_UPDATED")
        frameList._cbSuppressFrame:SetScript("OnEvent", function()
            -- Deferred: EDIT_MODE_LAYOUTS_UPDATED dispatches from inside Edit Mode's own
            -- operations; applying suppression state there writes cast bar state
            -- mid-pass (same taint mechanism as the DisableBlizzard override above).
            C_Timer.After(0, ApplyBlizzCastbarState)
        end)
        -- Edit Mode exit reparents the cast bar back into its layout frame
        -- (which gets hidden), so re-apply our state when the panel closes.
        if EditModeManagerFrame and not CludesUI._GetFFD(EditModeManagerFrame).castbarHooked then
            CludesUI._GetFFD(EditModeManagerFrame).castbarHooked = true
            hooksecurefunc(EditModeManagerFrame, "Hide", function()
                C_Timer.After(0, ApplyBlizzCastbarState)
                -- WoW Forever: Blizzard's own combo points stay up while Edit
                -- Mode is open; a Combo Points spot picked meanwhile takes
                -- them down once it closes.
                if mod._ufComboFrameKept and mod.UF_ComboLocation() ~= "target" then
                    C_Timer.After(0, mod.UF_ApplyForeverComboArc)
                end
            end)
        end
    end

    -- Resize frame and portrait to account for class power pips above health bar
    local function ResizeFrameForClassPower(cpAboveH)
        local widget = frameList.player
        if not widget then
            return
        end
        -- A stock style's kit owns the frame size, the portrait and the health
        -- offsets (ns.UF_ApplyBlizzardLayout). In combat this would park the
        -- CludesUI size for regen with no stock pass after it.
        if mod.UF_Blizz() then
            return
        end
        local prefs = GetSettingsForUnit("player")
        local powerPos = prefs.powerPosition or "below"
        local ppIsAtt = (powerPos == "below" or powerPos == "above")
        local ppExtra = ppIsAtt and prefs.powerHeight or 0
        local baseH = prefs.healthHeight + ppExtra
        local btbPos2 = prefs.btbPosition or "bottom"
        local btbIsAtt = (btbPos2 == "top" or btbPos2 == "bottom")
        local btbExtra = (prefs.bottomTextBar and btbIsAtt) and (prefs.bottomTextBarHeight or 16) or 0
        local totalH = baseH + cpAboveH + btbExtra

        local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
        local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
        local isAttached = pStyle == "attached"
        local pSizeAdj = prefs.portraitSize or 0
        if not isAttached then
            pSizeAdj = pSizeAdj + 10
        end
        local adjPortraitH = baseH + cpAboveH + pSizeAdj
        if adjPortraitH < 8 then
            adjPortraitH = 8
        end

        local pSide = prefs.portraitSide or "left"
        local effectiveSide = pSide
        if isAttached and pSide == "top" then
            effectiveSide = "left"
        end

        local totalWidth
        local portraitW = 0
        if not showPortrait then
            totalWidth = prefs.frameWidth
        elseif isAttached then
            totalWidth = adjPortraitH + prefs.frameWidth
            portraitW = adjPortraitH
        else
            totalWidth = prefs.frameWidth
        end

        if not InCombatLockdown() then
            Pix.Size(widget, totalWidth, totalH)
        else
            widget._pendingSize = { totalWidth, totalH }
            mod.CombatQueue.Defer("PlayerClassPowerSize", function()
                if widget._pendingSize and not InCombatLockdown() then
                    Pix.Size(widget, widget._pendingSize[1], widget._pendingSize[2])
                end
                widget._pendingSize = nil
            end)
        end

        -- Update health bar xOffset when portrait width changes
        if widget.Health then
            local newXOff = (showPortrait and isAttached and effectiveSide == "left") and portraitW or 0
            local newRightInset = (showPortrait and isAttached and effectiveSide == "right") and portraitW
                or 0
            widget.Health._xOffset = newXOff
            widget.Health._rightInset = newRightInset
        end

        if
            widget.Portrait
            and widget.Portrait.backdrop
            and showPortrait
            and not widget.Portrait.backdrop._isInside
        then
            Pix.Size(widget.Portrait.backdrop, adjPortraitH, adjPortraitH)
            -- The same anchors the reload pass gives the backdrop (a top text bar
            -- pushes an attached one down; a detached one floats off the health
            -- bar's edge): a backdrop cleared and left with no anchor renders
            -- nowhere until the next reload pass.
            widget.Portrait.backdrop:ClearAllPoints()
            local pBtbTopOff = (btbPos2 == "top" and prefs.bottomTextBar)
                    and (prefs.bottomTextBarHeight or 16)
                or 0
            if isAttached then
                if effectiveSide == "left" then
                    Pix.Point(widget.Portrait.backdrop, "TOPLEFT", widget, "TOPLEFT", 0, -pBtbTopOff)
                else
                    Pix.Point(widget.Portrait.backdrop, "TOPRIGHT", widget, "TOPRIGHT", 0, -pBtbTopOff)
                end
            else
                local pXOff = prefs.portraitX or 0
                local pYOff = (prefs.portraitY or 0) + 5
                if effectiveSide == "top" then
                    widget.Portrait.backdrop:SetPoint(
                        "BOTTOM",
                        widget.Health or widget,
                        "TOP",
                        pXOff,
                        15 + pYOff
                    )
                elseif effectiveSide == "left" then
                    widget.Portrait.backdrop:SetPoint(
                        "TOPRIGHT",
                        widget.Health or widget,
                        "TOPLEFT",
                        -15 + pXOff,
                        pYOff
                    )
                else
                    widget.Portrait.backdrop:SetPoint(
                        "TOPLEFT",
                        widget.Health or widget,
                        "TOPRIGHT",
                        15 + pXOff,
                        pYOff
                    )
                end
            end
            if widget.Portrait.backdrop._2d then
                UnsnapTex(widget.Portrait.backdrop._2d)
            end
            if widget:IsElementEnabled("Portrait") and widget.Portrait.ForceUpdate then
                widget.Portrait:ForceUpdate()
            end
            -- The detached portrait moved: move its click overlay with it.
            mod.UF_SyncPortraitClick(widget)
        end
    end

    -- The expected parent for the Blizzard class power bar after positioning, set by
    -- PositionClassPowerBar so the SetParent hook knows what's correct. MUST be
    -- declared before PositionClassPowerBar, or the function assigns a global while
    -- the hook reads this always-nil local (falling back to frames.player even for
    -- UIParent-parented bars).
    local _cpExpectedParent = nil

    local function PositionClassPowerBar(barFrame)
        if not barFrame or not frameList.player then
            return
        end
        barFrame:ClearAllPoints()
        -- Stock styles: the health bar keeps the kit's spot (the stock pass
        -- places it, and skips in combat), so only the pips move here.
        local stock = mod.UF_Blizz()
        local look = saved.profile.player.classPowerStyle or "none"
        if mod.UF_ForeverCPStyle then
            look = mod.UF_ForeverCPStyle(look)
        end
        local position = saved.profile.player.classPowerPosition or "top"
        local offsetX = saved.profile.player.classPowerBarX or 0
        local offsetY = saved.profile.player.classPowerBarY or 0

        -- Stop castbar watcher by default; only re-enabled in the "bottom" branch
        mod._cpWatchFn = nil
        mod._cpWatchTick.Stop()
        mod._cpCastWatcher:Hide()

        if look == "modern" and position == "above" then
            -- Above health bar, inside the frame -- pips stretch to fill health bar width
            -- Bottom of pips flush with top of health bar, top of pips flush with top of border
            _cpExpectedParent = frameList.player
            barFrame:SetParent(frameList.player)
            local anchorFrame = frameList.player.Health
            local pipH = barFrame._pipH or 3
            -- Resize frame/portrait BEFORE anchoring health bar so _xOffset is correct
            ResizeFrameForClassPower(pipH)
            local btbDisabled = 0
            local btbPos2 = saved.profile.player.btbPosition or "bottom"
            if btbPos2 == "top" and saved.profile.player.bottomTextBar then
                btbDisabled = saved.profile.player.bottomTextBarHeight or 16
            end
            local cpPush = pipH + btbDisabled
            if not stock then
                anchorFrame:ClearAllPoints()
                anchorFrame:SetPoint(
                    "TOPLEFT",
                    frameList.player,
                    "TOPLEFT",
                    anchorFrame._xOffset or 0,
                    Pix.Scale(-cpPush)
                )
                anchorFrame:SetPoint("RIGHT", frameList.player, "RIGHT", -(anchorFrame._rightInset or 0), 0)
            end
            Pix.Point(barFrame, "BOTTOMLEFT", anchorFrame, "TOPLEFT", 0, 0)
            Pix.Point(barFrame, "BOTTOMRIGHT", anchorFrame, "TOPRIGHT", 0, 0)
            local fw = saved.profile.player.frameWidth or 181
            if barFrame._repositionForWidth then
                barFrame._repositionForWidth(fw)
            end
            -- Show 1px bottom border matching frame border color
            if barFrame._bottomBdrFrame then
                local bdrC = saved.profile.player.borderColor or { r = 0, g = 0, b = 0 }
                barFrame._bottomBdr:SetColorTexture(bdrC.r, bdrC.g, bdrC.b, 1)
                barFrame._bottomBdrFrame:Show()
            end
            if mod.UF_Blizz() then
                mod.UF_ApplyBlizzardLayout(frameList.player, "player")
            end
        elseif look == "modern" and position == "top" then
            -- "top" floats above the frame (like "bottom" floats below) -- does NOT become part of the frame
            _cpExpectedParent = frameList.player
            barFrame:SetParent(frameList.player)
            ResizeFrameForClassPower(0)
            -- Reset health bar to normal position
            if frameList.player.Health and not stock then
                local btbDisabled = 0
                local btbPos2 = saved.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and saved.profile.player.bottomTextBar then
                    btbDisabled = saved.profile.player.bottomTextBarHeight or 16
                end
                frameList.player.Health:ClearAllPoints()
                frameList.player.Health:SetPoint(
                    "TOPLEFT",
                    frameList.player,
                    "TOPLEFT",
                    frameList.player.Health._xOffset or 0,
                    Pix.Scale(-btbDisabled)
                )
                frameList.player.Health:SetPoint(
                    "RIGHT",
                    frameList.player,
                    "RIGHT",
                    -(frameList.player.Health._rightInset or 0),
                    0
                )
            end
            -- Center on health bar (ignores portrait)
            Pix.Point(barFrame, "BOTTOM", frameList.player.Health, "TOP", offsetX, offsetY)
            if barFrame._bottomBdrFrame then
                barFrame._bottomBdrFrame:Hide()
            end
            if mod.UF_Blizz() then
                mod.UF_ApplyBlizzardLayout(frameList.player, "player")
            end
        elseif not saved.profile.player.lockClassPowerToFrame then
            -- Reset health bar to normal position
            if frameList.player.Health and not stock then
                local btbDisabled = 0
                local btbPos2 = saved.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and saved.profile.player.bottomTextBar then
                    btbDisabled = saved.profile.player.bottomTextBarHeight or 16
                end
                frameList.player.Health:ClearAllPoints()
                frameList.player.Health:SetPoint(
                    "TOPLEFT",
                    frameList.player,
                    "TOPLEFT",
                    frameList.player.Health._xOffset or 0,
                    Pix.Scale(-btbDisabled)
                )
                frameList.player.Health:SetPoint(
                    "RIGHT",
                    frameList.player,
                    "RIGHT",
                    -(frameList.player.Health._rightInset or 0),
                    0
                )
            end
            _cpExpectedParent = UIParent
            barFrame:SetParent(UIParent)
            local place = saved.profile.positions.classPower
            if place then
                Pix.Point(barFrame, place.point, UIParent, place.point, place.x, place.y)
            else
                Pix.Point(barFrame, "CENTER", UIParent, "CENTER", 0, -220)
            end
            ResizeFrameForClassPower(0)
            if barFrame._bottomBdrFrame then
                barFrame._bottomBdrFrame:Hide()
            end
            if mod.UF_Blizz() then
                mod.UF_ApplyBlizzardLayout(frameList.player, "player")
            end
        else
            -- Reset health bar to normal position
            if frameList.player.Health and not stock then
                local btbDisabled = 0
                local btbPos2 = saved.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and saved.profile.player.bottomTextBar then
                    btbDisabled = saved.profile.player.bottomTextBarHeight or 16
                end
                frameList.player.Health:ClearAllPoints()
                frameList.player.Health:SetPoint(
                    "TOPLEFT",
                    frameList.player,
                    "TOPLEFT",
                    frameList.player.Health._xOffset or 0,
                    Pix.Scale(-btbDisabled)
                )
                frameList.player.Health:SetPoint(
                    "RIGHT",
                    frameList.player,
                    "RIGHT",
                    -(frameList.player.Health._rightInset or 0),
                    0
                )
            end
            -- "bottom" position -- flush with bottom of frame; shifts below castbar when visible (unless user set Y offset)
            _cpExpectedParent = frameList.player
            barFrame:SetParent(frameList.player)
            if barFrame._bottomBdrFrame then
                barFrame._bottomBdrFrame:Hide()
            end
            local function AnchorBottom()
                barFrame:ClearAllPoints()
                local baseY = -1 + offsetY
                if offsetY == 0 then
                    local castbarBg = frameList.player.Castbar and frameList.player.Castbar:GetParent()
                    local castVisible = castbarBg
                        and castbarBg:IsShown()
                        and saved.profile.player.showPlayerCastbar
                    if castVisible then
                        local ch = castbarBg:GetHeight()
                        -- Secret while the holder rides the Blizzard Style aura block.
                        if issecretvalue(ch) then
                            ch = saved.profile.player.playerCastbarHeight or 14
                        end
                        baseY = -1 - ch
                    end
                end
                Pix.Point(barFrame, "TOP", frameList.player, "BOTTOM", offsetX, baseY)
            end
            AnchorBottom()
            -- Stock styles: the stock pass re-seats the kit.
            if mod.UF_Blizz() then
                mod.UF_ApplyBlizzardLayout(frameList.player, "player")
            end
            -- Only run the castbar watcher if the player castbar is enabled
            if saved.profile.player.showPlayerCastbar then
                -- Shared child-born shell (see ns._cpCastWatcher): a frame created
                -- here would be born in whatever context triggered this rebuild and
                -- could bill the parent for the 10 Hz poll below. It rides the bar,
                -- so its ticker pauses while the bar is hidden; its state lives in
                -- this closure, never on the bar (Blizzard's own frame under the
                -- Blizzard style).
                local watcher = mod._cpCastWatcher
                if watcher:GetParent() ~= barFrame then
                    watcher:SetParent(barFrame)
                end
                local playerFrame = frameList.player
                local lastCastVis
                -- 10 Hz body on the shared anim ticker (see ns._cpWatchTick).
                mod._cpWatchFn = function()
                    local callback = playerFrame and playerFrame.Castbar
                    local castbarBg = callback and callback:GetParent()
                    local nowVis = castbarBg
                        and castbarBg:IsShown()
                        and saved.profile.player.showPlayerCastbar
                    if nowVis ~= lastCastVis then
                        lastCastVis = nowVis
                        AnchorBottom()
                    end
                end
                watcher:Show()
                mod._cpWatchTick.Start()
            end
            ResizeFrameForClassPower(0)
        end
        barFrame:SetFrameStrata(frameList.player:GetFrameStrata())
        barFrame:SetFrameLevel(frameList.player:GetFrameLevel() + 5)
        barFrame:Show()
    end

    -- Hook Blizzard class power bar so form/spec changes can't steal it back. Hooks
    -- SetParent to re-assert our parent, Show/Hide to keep it visible, and
    -- ClearAllPoints to catch anchors getting stripped without a reparent (seen
    -- during in-engine cutscenes/UI transitions -- parent and IsShown() stay
    -- correct, but GetNumPoints() drops to 0 and the frame renders nowhere).
    -- Only active while classPowerStyle == "blizzard".
    local _blizzCPHooked = false
    local _blizzCPActive = false -- true while we own the bar

    local function HookBlizzardClassPower(classPowerFrame)
        if _blizzCPHooked then
            return
        end
        _blizzCPHooked = true
        local _cpSetParentGuard = false
        -- All hooks defer their re-assert work: they can fire inside Blizzard's
        -- secure Edit Mode layout pass (same taint mechanism as the DisableBlizzard
        -- override above), and wait for the manager to close before re-asserting.
        local _cpReassertQueued = false
        local ReassertClassPower
        ReassertClassPower = function(self)
            _cpReassertQueued = false
            if not _blizzCPActive then
                return
            end
            if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
                _cpReassertQueued = true
                C_Timer.After(0.25, function()
                    ReassertClassPower(self)
                end)
                return
            end
            local wanted = _cpExpectedParent or frameList.player or UIParent
            if self:GetParent() ~= wanted or (self:GetNumPoints() or 0) == 0 then
                _cpSetParentGuard = true
                PositionClassPowerBar(self)
                -- Blizzard may have re-stolen during PositionClassPowerBar.
                -- The anchor is already correct, so just fix the parent directly.
                if self:GetParent() ~= wanted then
                    self:SetParent(wanted)
                end
                _cpSetParentGuard = false
            end
            if not self:IsShown() and not InCombatLockdown() then
                self:Show()
            end
        end
        -- Re-assert position when Blizzard reparents (form/spec changes).
        hooksecurefunc(classPowerFrame, "SetParent", function(self, newParent)
            if not _blizzCPActive or _cpSetParentGuard or _cpReassertQueued then
                return
            end
            local wanted = _cpExpectedParent or frameList.player or UIParent
            if newParent ~= wanted then
                _cpReassertQueued = true
                C_Timer.After(0, function()
                    ReassertClassPower(self)
                end)
            end
        end)
        hooksecurefunc(classPowerFrame, "Hide", function(self)
            if not _blizzCPActive or _cpReassertQueued then
                return
            end
            _cpReassertQueued = true
            C_Timer.After(0, function()
                ReassertClassPower(self)
            end)
        end)
        -- Re-assert anchors when something strips them without a reparent (the
        -- cutscene case above). Guarded by _cpSetParentGuard the same way as
        -- SetParent so our own PositionClassPowerBar's internal ClearAllPoints
        -- doesn't recurse back into itself.
        hooksecurefunc(classPowerFrame, "ClearAllPoints", function(self)
            if not _blizzCPActive or _cpSetParentGuard or _cpReassertQueued then
                return
            end
            _cpReassertQueued = true
            C_Timer.After(0, function()
                ReassertClassPower(self)
            end)
        end)
    end

    -- Seed the built-style marker so the first reload does not mistake a nil
    -- marker for a change. Written ONLY at build sites (here and the toggle):
    -- PositionClassPowerBar is repositioning, called by ReassertClassPower from
    -- Blizzard's SetParent/Hide hooks with no rebuild behind it, and stamping
    -- there would suppress the rebuild this exists to trigger. frames.player
    -- guard matches _toggleClassPower.
    if frameList.player then
        frameList._classPowerBuiltStyle = classPowerStyle
    end
    if classPowerStyle ~= "none" and frameList.player then
        if classPowerStyle == "blizzard" then
            if storedClassPower then
                _blizzCPActive = true
                -- Runtime ownership mirrored on ns for Resource Bars (ns.UF_OwnsBlizzClassPower).
                mod._ufBlizzCPHeld = true
                storedClassPower.ignoreFramePositionManager = true
                HookBlizzardClassPower(storedClassPower)
                PositionClassPowerBar(storedClassPower)
                frameList._classPowerBar = storedClassPower
            end
        else
            -- Modern custom style
            DestroyCustomClassPower()
            local custom = CreateCustomClassPower(frameList.player, classPowerStyle)
            if custom then
                frameList._customClassPower = custom
                frameList._classPowerBar = custom
                PositionClassPowerBar(custom)
                if mod._WCUF_Sync then
                    mod._WCUF_Sync(custom)
                end
            else
                -- Spec has no class resource: reset frame sizing
                ResizeFrameForClassPower(0)
            end
        end
    end

    -- Live toggle for class power bar (no reload needed)
    -- Called with the style string: "none", "modern", or "blizzard"
    frameList._toggleClassPower = function(look)
        -- Class power is a player-frame feature; if the player is on Blizzard's
        -- default frame (or hidden), there is no CUI frame to attach it to.
        if not frameList.player then
            return
        end
        look = look or saved.profile.player.classPowerStyle or "none"
        -- What is actually BUILT right now. Read by the reload pass below to
        -- notice a style that changed through a path which never calls this
        -- function (see the reload hook).
        -- Resource Bars' Blizzard Class Resource Art defers to this style for
        -- Blizzard's class resource frame; it re-judges when the built style
        -- crosses "blizzard" (below) instead of waiting for its next rebuild.
        local wasBlizz = frameList._classPowerBuiltStyle == "blizzard"
        frameList._classPowerBuiltStyle = look
        -- Keep showClassPowerBar in sync with style
        saved.profile.player.showClassPowerBar = (look ~= "none")
        saved.profile.player.classPowerStyle = look
        -- WoW Forever: the saved style stays as given; its effective style
        -- (ns.UF_ForeverCPStyle) is what builds and what the marker records.
        if mod.UF_ForeverCPStyle then
            look = mod.UF_ForeverCPStyle(look)
            frameList._classPowerBuiltStyle = look
        end
        -- WoW Forever: the "Blizzard" entry is the combo point arc on the
        -- frame Combo Points names (returns at once everywhere else).
        mod.UF_ApplyForeverComboArc()

        -- Clean up existing
        _blizzCPActive = false
        mod._ufBlizzCPHeld = false
        if frameList._customClassPower then
            DestroyCustomClassPower()
            frameList._classPowerBar = nil
        elseif frameList._classPowerBar then
            -- The cast bar watcher may ride this bar: stop it before the bar goes
            -- back, so it never re-anchors a frame we no longer own.
            mod._cpWatchFn = nil
            mod._cpWatchTick.Stop()
            mod._cpCastWatcher:Hide()
            -- Handed on to Resource Bars' Blizzard Class Resource Art: left shown, so
            -- it appears there at once (Blizzard only re-shows it from its own Setup).
            if not (look ~= "blizzard" and _G._CURB_BlizzArtWanted and _G._CURB_BlizzArtWanted()) then
                frameList._classPowerBar:Hide()
            end
            frameList._classPowerBar:ClearAllPoints()
            frameList._classPowerBar.ignoreFramePositionManager = nil
            local origParent = _blizzCPState.origParent or PlayerFrame or UIParent
            frameList._classPowerBar:SetParent(origParent)
            frameList._classPowerBar = nil
        end
        -- Handed Blizzard's class resource frame back: Resource Bars' Blizzard
        -- Class Resource Art (if on) claims it now rather than at its next rebuild.
        if
            wasBlizz
            and look ~= "blizzard"
            and _G._CURB_BlizzArtWanted
            and _G._CURB_BlizzArtWanted()
            and _G._CURB_Apply
        then
            _G._CURB_Apply()
        end

        if look == "none" then
            -- Reset health bar to normal position (a stock style's kit owns it)
            if frameList.player and frameList.player.Health and not mod.UF_Blizz() then
                local btbDisabled = 0
                local btbPos2 = saved.profile.player.btbPosition or "bottom"
                if btbPos2 == "top" and saved.profile.player.bottomTextBar then
                    btbDisabled = saved.profile.player.bottomTextBarHeight or 16
                end
                frameList.player.Health:ClearAllPoints()
                frameList.player.Health:SetPoint(
                    "TOPLEFT",
                    frameList.player,
                    "TOPLEFT",
                    frameList.player.Health._xOffset or 0,
                    Pix.Scale(-btbDisabled)
                )
                frameList.player.Health:SetPoint(
                    "RIGHT",
                    frameList.player,
                    "RIGHT",
                    -(frameList.player.Health._rightInset or 0),
                    0
                )
            end
            ResizeFrameForClassPower(0)
            return
        end

        if look == "blizzard" then
            local _, class = UnitClass("player")
            local frameName = BLIZZARD_CP_FRAMES[class]
            local classPowerFrame = frameName and _G[frameName]
            if classPowerFrame then
                -- A Blizzard parent only (see the login takeover above).
                local current = classPowerFrame:GetParent()
                _blizzCPState.origParent = (current == classPowerFrame.layoutParent or current == PlayerFrame)
                        and current
                    or (classPowerFrame.layoutParent or PlayerFrame)
                _blizzCPActive = true
                mod._ufBlizzCPHeld = true
                classPowerFrame.ignoreFramePositionManager = true
                HookBlizzardClassPower(classPowerFrame)
                classPowerFrame:SetParent(UIParent)
                frameList._classPowerBar = classPowerFrame
            end
            if frameList._classPowerBar and frameList.player then
                PositionClassPowerBar(frameList._classPowerBar)
            end
            -- Took Blizzard's class resource frame: Resource Bars' Blizzard Class
            -- Resource Art stands down now rather than at its next rebuild.
            if not wasBlizz and _G._CURB_BlizzArtHeld and _G._CURB_BlizzArtHeld() and _G._CURB_Apply then
                _G._CURB_Apply()
            end
        else
            -- Modern
            local custom = CreateCustomClassPower(frameList.player, look)
            if custom then
                frameList._customClassPower = custom
                frameList._classPowerBar = custom
                PositionClassPowerBar(custom)
                if mod._WCUF_Sync then
                    mod._WCUF_Sync(custom)
                end
            else
                -- Spec has no class resource: reset frame sizing
                ResizeFrameForClassPower(0)
            end
        end
    end

    -- Persistent spec-change watcher for class power rebuild.
    -- Lives outside the class power container so it survives DestroyCustomClassPower.
    local cpSpecWatcher = CreateFrame("Frame")
    local cpSpecInitDone = false
    -- WoW Forever keys the class resource by class alone (ClassPowerEntry), so
    -- a spec event there can never change the bar: no teardown on it.
    if CludesUI.IS_FOREVER ~= true then
        cpSpecWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        cpSpecWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    end
    cpSpecWatcher:SetScript("OnEvent", function(_, evt, unitToken)
        if evt == "PLAYER_ENTERING_WORLD" then
            cpSpecInitDone = true
            cpSpecWatcher:UnregisterEvent("PLAYER_ENTERING_WORLD")
            return
        end
        if unitToken ~= "player" then
            return
        end
        if not cpSpecInitDone then
            return
        end
        DestroyCustomClassPower()
        if frameList._classPowerBar then
            frameList._classPowerBar.ignoreFramePositionManager = nil
        end
        frameList._classPowerBar = nil
        C_Timer.After(0.1, function()
            if mod.ReloadFrames then
                mod.ReloadFrames()
            end
            if frameList._toggleClassPower then
                frameList._toggleClassPower()
            end
        end)
    end)

    -- Durably suppress a live Blizzard child frame (target-of-target/focus-target).
    -- These are PROTECTED CHILDREN of TargetFrame/FocusFrame: when the parent uses
    -- Blizzard's source it stays alive and re-drives the child (TargetOfTargetMixin:
    -- Update) on every target change, undoing a one-shot Hide. We unregister its
    -- events and re-hide on OnShow.
    --
    -- KNOWN LIMITATION (in-combat double frame): the child is protected, so Hide() is
    -- blocked in combat. If the player changes target mid-combat, Blizzard (secure)
    -- re-Shows the native child and our OnShow re-hide can't fire until
    -- PLAYER_REGEN_ENABLED -- so with the parent on Blizzard Default and this mini
    -- frame on CludesUI/Hidden, the native child stays visible for the WHOLE combat
    -- (not just a flash), sitting alongside the CludesUI frame (or showing despite
    -- "Hidden"). Not fixable without reparenting/overriding a secure frame in combat,
    -- so it's surfaced in the mini-frame "Frame Source" tooltip (BuildFoTToTOptions),
    -- which recommends matching the parent's source instead of mixing them.
    local _suppressedChildren, _rehidePending
    local function RehideSuppressedChildren()
        if InCombatLockdown() then
            return
        end
        for frame in pairs(_suppressedChildren) do
            frame:Hide()
        end
    end
    -- Deferred re-hide: OnShow fires inside whatever secure execution showed the parent
    -- (target swaps, Edit Mode's preview pass on a Blizzard-source TargetFrame/
    -- FocusFrame); hiding inline there taints the rest of that execution (same
    -- mechanism as the DisableBlizzard override above). While Edit Mode is open the
    -- re-hide waits for it to close.
    local _DeferredRehide
    _DeferredRehide = function(widget)
        _rehidePending[widget] = nil
        if not widget:IsShown() then
            return
        end
        if EditModeManagerFrame and EditModeManagerFrame:IsShown() then
            _rehidePending[widget] = true
            C_Timer.After(0.25, function()
                _DeferredRehide(widget)
            end)
        elseif InCombatLockdown() then
            mod.CombatQueue.Defer("SuppressedChildRehide", RehideSuppressedChildren)
        else
            widget:Hide()
        end
    end
    local function SuppressBlizzardChildFrame(widget)
        if not widget then
            return
        end
        widget:UnregisterAllEvents()
        if not InCombatLockdown() then
            widget:Hide()
        end
        _suppressedChildren = _suppressedChildren or {}
        _rehidePending = _rehidePending or {}
        if not _suppressedChildren[widget] then
            _suppressedChildren[widget] = true
            widget:HookScript("OnShow", function(self)
                if not _rehidePending[self] then
                    _rehidePending[self] = true
                    C_Timer.After(0, function()
                        _DeferredRehide(self)
                    end)
                end
            end)
        end
    end

    local targetFrameSource = mod.GetUnitFrameSource("target")
    if targetFrameSource == "cui" then
        frameList.target = mod.Engine.SpawnUnitFrame("target", "CludesUIUnitFrames_Target")
        StyleFullFrame(frameList.target, "target")
        mod.UF_AttachEngineFrame(frameList.target, "target")
        ApplyFramePosition(frameList.target, "target")
        SetupUnitMenu(frameList.target, "target")
    elseif targetFrameSource == "hidden" then
        mod.Engine.HideBlizzardUnitFrame("target")
    end

    -- Forever combo points belong to the target, and Blizzard draws them with the
    -- classic ComboFrame, which ComboFrame_Update re-anchors to TargetFrame on
    -- every change, so it cannot be re-homed onto ours. No BLIZZARD_CP_FRAMES
    -- global exists here, so the takeover above never reaches it. Our display
    -- (the pips, or the WoW Forever style's arc) replaces it: the classic frame
    -- goes to the hidden parent the way TargetFrame itself does, events
    -- unregistered, so it costs nothing. It is left alone only where Blizzard's
    -- own target frame is kept AND the class resource is off or is the WoW
    -- Forever style's "Blizzard" one showing on the target frame (Combo Points
    -- reads Target Frame without our player frame, and moves combo points for
    -- rogues and druids only), the cases in which nothing else of ours draws
    -- there; ns._ufComboFrameKept lets a later Combo Points change take it
    -- down (ns.UF_ApplyForeverComboArc). The hidden parent is pinned for the
    -- session, like every frame HandleFrame takes.
    if CludesUI.IS_FOREVER == true and _G.ComboFrame then
        if
            targetFrameSource ~= "blizzard"
            or (classPowerStyle ~= "none" and classPowerStyle ~= "blizzard")
        then
            mod.UF_HideBlizzardFrame(_G.ComboFrame)
        elseif
            classPowerStyle == "blizzard"
            and playerFrameSource == "cui"
            and mod.UF_ComboClass()
            and mod.UF_ComboLocation() ~= "target"
        then
            mod.UF_HideBlizzardFrame(_G.ComboFrame)
            mod._ufComboFrameByLoc = true
        else
            mod._ufComboFrameKept = true
        end
    end

    local focusFrameSource = mod.GetUnitFrameSource("focus")
    if focusFrameSource == "cui" then
        frameList.focus = mod.Engine.SpawnUnitFrame("focus", "CludesUIUnitFrames_Focus")
        StyleFocusFrame(frameList.focus, "focus")
        mod.UF_AttachEngineFrame(frameList.focus, "focus")
        ApplyFramePosition(frameList.focus, "focus")
        SetupUnitMenu(frameList.focus, "focus")
    elseif focusFrameSource == "hidden" then
        mod.Engine.HideBlizzardUnitFrame("focus")
    end

    -- Combat indicator overlay on the player + target frames. Each shows its OWN
    -- unit's combat state: player via the exact regen events, target via UNIT_FLAGS
    -- (combat flag changes) + PLAYER_TARGET_CHANGED re-evaluation. Target defaults to
    -- "none" (opt-in); player keeps its legacy default. Must run after the target
    -- frame is spawned (right above).
    for _, ciDef in ipairs({
        { unit = "player", defStyle = "standard" },
        { unit = "target", defStyle = "none" },
    }) do
        local popFrame = frameList[ciDef.unit]
        if popFrame then
            local ciUnit = ciDef.unit
            local ciDefStyle = ciDef.defStyle
            local powerSettings = saved.profile[ciUnit]
            local COMBAT_MEDIA = "Interface\\AddOns\\CludesUI\\media\\combat\\"

            -- Create holder + texture ONCE, reuse on subsequent calls
            if not popFrame._combatHolder then
                popFrame._combatHolder = CreateFrame("Frame", nil, popFrame)
                popFrame._combatHolder:SetAllPoints(popFrame)
                popFrame._combatIndicator = popFrame._combatHolder:CreateTexture(nil, "OVERLAY", nil, 7)
                popFrame._combatIndicator:Hide()
            end
            popFrame._combatHolder:SetFrameLevel(popFrame:GetFrameLevel() + 20)
            local combatIcon = popFrame._combatIndicator

            -- Helper: resolve which texture file + coords to use
            local function ApplyCombatTexture()
                local look = powerSettings.combatIndicatorStyle or ciDefStyle
                if look == "none" then
                    combatIcon:Hide()
                    return
                end

                local colorMode = powerSettings.combatIndicatorColor or "custom"
                local sz = powerSettings.combatIndicatorSize or 22
                local ox = powerSettings.combatIndicatorX or 0
                local oy = powerSettings.combatIndicatorY or 0
                local place = powerSettings.combatIndicatorPosition or "healthbar"

                combatIcon:SetSize(sz, sz)
                combatIcon:ClearAllPoints()

                -- "healthbar" is the stored value shown as "Center" in the dropdown;
                -- "center" is a render alias for it. Portrait with no portrait shown
                -- takes the health bar's top-left corner (ns.UF_PortraitShown).
                local edge = popFrame.Portrait and popFrame.Portrait.backdrop
                if place == "portrait" and edge and mod.UF_PortraitShown(powerSettings) then
                    combatIcon:SetPoint("CENTER", edge, "CENTER", ox, oy)
                elseif place == "textbar" then
                    combatIcon:SetPoint("CENTER", popFrame._btb or popFrame, "CENTER", ox, oy)
                elseif place == "healthbar" or place == "center" then
                    combatIcon:SetPoint("CENTER", popFrame.Health or popFrame, "CENTER", ox, oy)
                else
                    local anchor = (place == "topright" and "TOPRIGHT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    combatIcon:SetPoint(anchor, popFrame.Health or popFrame, anchor, ox, oy)
                end

                -- Determine texture file (always use -custom / white base).
                -- Class theming resolves the FRAME's unit (player class on the
                -- player frame, current target's class on the target frame).
                local _, classToken = UnitClass(ciUnit)
                if issecretvalue(classToken) then
                    classToken = nil
                end
                -- All custom combat icons (Arcade/Dungeoneer/Classic/Cross/Circle/Square =
                -- combat0..5) are shown exactly as authored: no class theming, no tint, no
                -- desaturation. Standard/Class Theme below are tinted by the colour mode.
                if look:find("^combat%d") then
                    combatIcon:SetTexture(COMBAT_MEDIA .. look .. ".tga")
                    combatIcon:SetTexCoord(0, 1, 0, 1)
                    if combatIcon.SetDesaturated then
                        combatIcon:SetDesaturated(false)
                    end
                    combatIcon:SetVertexColor(1, 1, 1, 1)
                else
                    if look == "class" then
                        combatIcon:SetTexture(COMBAT_MEDIA .. "combat-indicator-class-custom.png")
                        local texCoords = classToken and CLASS_FULL_COORDS[classToken]
                        if texCoords then
                            combatIcon:SetTexCoord(texCoords[1], texCoords[2], texCoords[3], texCoords[4])
                        else
                            combatIcon:SetTexCoord(0, 1, 0, 1)
                        end
                    else
                        combatIcon:SetTexture(COMBAT_MEDIA .. "combat-indicator-custom.png")
                        combatIcon:SetTexCoord(0, 1, 0, 1)
                    end

                    -- Apply color tint
                    if colorMode == "classcolor" then
                        local classColor = (classToken and CludesUI.GetClassColor(classToken))
                            or { r = 1, g = 1, b = 1 }
                        combatIcon:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
                    elseif colorMode == "custom" then
                        local classColor = powerSettings.combatIndicatorCustomColor or { r = 1, g = 1, b = 1 }
                        combatIcon:SetVertexColor(classColor.r, classColor.g, classColor.b, 1)
                    else
                        combatIcon:SetVertexColor(1, 1, 1, 1)
                    end
                end
            end
            popFrame._applyCombatTexture = ApplyCombatTexture

            -- Event frame for combat state changes (reuse existing)
            if not popFrame._combatEventFrame then
                popFrame._combatEventFrame = CreateFrame("Frame", nil, popFrame)
                if ciUnit == "player" then
                    popFrame._combatEventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
                    popFrame._combatEventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
                else
                    -- UNIT_FLAGS fires on the unit's combat flag flips; target
                    -- change re-evaluates for the new unit.
                    popFrame._combatEventFrame:RegisterUnitEvent("UNIT_FLAGS", ciUnit)
                    popFrame._combatEventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
                end
            end
            local combatFrame = popFrame._combatEventFrame
            combatFrame:SetScript("OnEvent", function()
                local look = powerSettings.combatIndicatorStyle or ciDefStyle
                if look ~= "none" and UnitAffectingCombat(ciUnit) then
                    ApplyCombatTexture()
                    combatIcon:Show()
                else
                    combatIcon:Hide()
                end
            end)

            -- Set correct initial state
            local look = powerSettings.combatIndicatorStyle or ciDefStyle
            if look ~= "none" and UnitAffectingCombat(ciUnit) then
                ApplyCombatTexture()
                combatIcon:Show()
            end
        end
    end

    -- Leader indicator (crown when unit is group/raid leader). oUF doesn't attach
    -- LeaderIndicator dynamically after Spawn(), so we drive the texture ourselves: own
    -- events, own UnitIsGroupLeader check, own show/hide. Must run after the target
    -- frame is spawned (above) so the texture can be parented to it.
    do
        local _leaderUnits = {}

        local function _leaderRefresh(ufStore)
            local cfg = ufStore and ufStore._leaderSettings
            if not (ufStore and ufStore._leaderIndicator and cfg) then
                return
            end
            local texture = ufStore._leaderIndicator
            if cfg.leaderIndicatorEnabled == false then
                texture:Hide()
                return
            end
            -- The oUF unit token can still be unassigned when the setup-time
            -- refresh runs (login/reload timing), and the API rejects a nil
            -- unit outright. Hide and stand down: the leader/roster/target
            -- events below re-run this refresh once the unit exists.
            local unitToken = ufStore._cuiUnit
            if not unitToken or (issecretvalue and issecretvalue(unitToken)) then
                texture:Hide()
                return
            end
            local isLeader = UnitIsGroupLeader(unitToken)
            local isAssist = UnitIsGroupAssistant(unitToken)
            -- Icon Style: Blizzard's crown/assistant art or the Pixels pair.
            local art = mod.UF_LEADER_ART[cfg.leaderIndicatorStyle] or mod.UF_LEADER_ART.blizzard
            -- Secrecy check MUST run before any truthiness test: boolean-testing
            -- a secret errors, so "value and not issecretvalue(value)" crashes.
            if not issecretvalue(isLeader) and isLeader then
                texture:SetTexture(art.leader)
                texture:Show()
            elseif not issecretvalue(isAssist) and isAssist then
                texture:SetTexture(art.assist)
                texture:Show()
            else
                texture:Hide()
            end
        end

        local function _setupLeaderIndicator(ufStore, prefs)
            if not (ufStore and ufStore.Health and prefs) then
                return
            end
            if not ufStore._leaderIndicator then
                -- Parent to the health-bar text overlay (same frame level as the
                -- health text) on a higher OVERLAY sublevel than the text strings
                -- (which are sublevel 0), so the crown draws just above the text
                -- instead of beneath it. Falls back to the frame if the text
                -- overlay isn't present.
                local leaderParent = ufStore._textOverlay or ufStore
                local leaderTex = leaderParent:CreateTexture(nil, "OVERLAY", nil, 7)
                leaderTex:Hide()
                ufStore._leaderIndicator = leaderTex
                _leaderUnits[#_leaderUnits + 1] = ufStore
            end
            ufStore._leaderSettings = prefs

            local function ApplyLeaderIndicator()
                local sz = prefs.leaderIndicatorSize or 16
                local place = prefs.leaderIndicatorPosition or "topleft"
                local ox = prefs.leaderIndicatorX or 0
                local oy = prefs.leaderIndicatorY or 0
                local leader = ufStore._leaderIndicator
                leader:SetSize(sz, sz)
                leader:ClearAllPoints()
                if
                    place == "portrait"
                    and ufStore.Portrait
                    and ufStore.Portrait.backdrop
                    and mod.UF_PortraitShown(prefs)
                then
                    leader:SetPoint("CENTER", ufStore.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor = (place == "topright" and "TOPRIGHT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    leader:SetPoint(anchor, ufStore.Health or ufStore, anchor, ox, oy)
                end
                _leaderRefresh(ufStore)
            end
            ufStore._applyLeaderIndicator = ApplyLeaderIndicator
            ApplyLeaderIndicator()
        end

        _setupLeaderIndicator(frameList.player, saved.profile.player)
        _setupLeaderIndicator(frameList.target, saved.profile.target)

        if #_leaderUnits > 0 then
            local leaderWatch = CreateFrame("Frame")
            leaderWatch:RegisterEvent("PARTY_LEADER_CHANGED")
            leaderWatch:RegisterEvent("GROUP_ROSTER_UPDATE")
            leaderWatch:RegisterEvent("PLAYER_TARGET_CHANGED")
            leaderWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
            leaderWatch:SetScript("OnEvent", function()
                for index = 1, #_leaderUnits do
                    _leaderRefresh(_leaderUnits[index])
                end
            end)
        end
    end

    -- Elite/Rare indicator (classification badge on the target frame), driven like the
    -- leader indicator above: own events, own refresh, own show/hide. Atlas mapping
    -- matches the nameplates classification badges exactly, so the two features read
    -- as one system. Show in Instances (default off) keeps it quiet in dungeons/raids, where most enemies are elite.
    -- A "wingless" style reads as off here: the Portrait Dragon draws that
    -- one (ns.UF_DragonLegacy).
    do
        local function _eliteAtlas(c)
            if c == "elite" or c == "worldboss" then
                return "nameplates-icon-elite-gold"
            elseif c == "rareelite" then
                return "nameplates-icon-elite-silver"
            elseif c == "rare" then
                return "nameplates-icon-rareelite"
            end
        end

        local _eliteFrames = {}
        local eliteWatch

        local function _eliteRefresh(ufStore)
            local cfg = ufStore and ufStore._eliteSettings
            if not (ufStore and ufStore._eliteIndicator and cfg) then
                return
            end
            local texture = ufStore._eliteIndicator
            -- Dragon texture: exists only once its style was first used.
            local eliteDragon = ufStore._eliteDragon
            if
                cfg.eliteIndicatorEnabled ~= true
                or mod.UF_DragonLegacy(cfg)
                or (not cfg.eliteIndicatorShowInInstances and IsInInstance())
            then
                texture:Hide()
                if eliteDragon then
                    eliteDragon:Hide()
                end
                return
            end
            local c = UnitClassification(ufStore._cuiUnit)
            if ufStore._eliteDragonOn then
                -- Classification art, or the Player art on a player target;
                -- both probes are secrecy-checked before any use.
                texture:Hide()
                local file = (not issecretvalue(c)) and mod.UF_ELITE_DRAGON_ART[c] or nil
                if not file then
                    local isPlayer = UnitIsPlayer(ufStore._cuiUnit)
                    if not issecretvalue(isPlayer) and isPlayer then
                        file = mod.UF_ELITE_DRAGON_ART.player
                    end
                end
                if file then
                    eliteDragon:SetTexture(file)
                    eliteDragon:Show()
                else
                    eliteDragon:Hide()
                end
                return
            end
            if eliteDragon then
                eliteDragon:Hide()
            end
            -- Secrecy check MUST run before any comparison, same rule as the
            -- leader checks above.
            local atlasName = (not issecretvalue(c)) and _eliteAtlas(c) or nil
            if atlasName then
                texture:SetAtlas(atlasName)
                texture:Show()
            else
                texture:Hide()
            end
        end

        -- Events are registered only while the feature is enabled somewhere
        -- (zero cost while off) and re-armed from every settings apply.
        local function _eliteArmEvents()
            local enabled = false
            for index = 1, #_eliteFrames do
                local cfg = _eliteFrames[index]._eliteSettings
                if cfg and cfg.eliteIndicatorEnabled == true and not mod.UF_DragonLegacy(cfg) then
                    enabled = true
                    break
                end
            end
            if enabled then
                if not eliteWatch then
                    eliteWatch = CreateFrame("Frame")
                    eliteWatch:SetScript("OnEvent", function()
                        for index = 1, #_eliteFrames do
                            _eliteRefresh(_eliteFrames[index])
                        end
                    end)
                end
                eliteWatch:RegisterEvent("PLAYER_TARGET_CHANGED")
                eliteWatch:RegisterUnitEvent("UNIT_CLASSIFICATION_CHANGED", "target")
                eliteWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
            elseif eliteWatch then
                eliteWatch:UnregisterAllEvents()
            end
        end

        local function _setupEliteIndicator(ufStore, prefs)
            if not (ufStore and ufStore.Health and prefs) then
                return
            end
            if not ufStore._eliteIndicator then
                -- Same parent and layer choice as the leader crown above.
                local par = ufStore._textOverlay or ufStore
                local texture = par:CreateTexture(nil, "OVERLAY", nil, 7)
                texture:Hide()
                ufStore._eliteIndicator = texture
                _eliteFrames[#_eliteFrames + 1] = ufStore
            end
            ufStore._eliteSettings = prefs

            local function ApplyEliteIndicator()
                local sz = prefs.eliteIndicatorSize or 16
                local place = prefs.eliteIndicatorPosition or "topleft"
                local ox = prefs.eliteIndicatorX or 0
                local oy = prefs.eliteIndicatorY or 0
                local texture = ufStore._eliteIndicator
                texture:SetSize(sz, sz)
                texture:ClearAllPoints()
                if
                    place == "portrait"
                    and ufStore.Portrait
                    and ufStore.Portrait.backdrop
                    and mod.UF_PortraitShown(prefs)
                then
                    texture:SetPoint("CENTER", ufStore.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor = (place == "topright" and "TOPRIGHT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPLEFT"
                    texture:SetPoint(anchor, ufStore.Health or ufStore, anchor, ox, oy)
                end
                -- Style "pixelsDragon": its own texture on a holder one level
                -- above the portrait backdrop (under the text layer), centred on
                -- and sized from the portrait. Needs a shown portrait; without
                -- one, and under a stock style, the badge above stands in.
                -- Built on first use.
                local edge = ufStore.Portrait and ufStore.Portrait.backdrop
                local onPortrait = prefs.eliteIndicatorEnabled == true
                    and not mod.UF_Blizz()
                    and edge
                    and edge:IsShown()
                local useDragon = onPortrait and prefs.eliteIndicatorStyle == "pixelsDragon"
                if useDragon then
                    local holderFrame = ufStore._eliteDragonHolder
                    if not holderFrame then
                        holderFrame = CreateFrame("Frame", nil, edge)
                        holderFrame:SetAllPoints(edge)
                        ufStore._eliteDragonHolder = holderFrame
                    end
                    mod.UF_LiftDragonHolder(holderFrame, edge)
                    local eliteDragon = ufStore._eliteDragon
                    if not eliteDragon then
                        eliteDragon = holderFrame:CreateTexture(nil, "OVERLAY")
                        eliteDragon:SetPoint("CENTER", edge, "CENTER", 0, 0)
                        eliteDragon:Hide()
                        ufStore._eliteDragon = eliteDragon
                    end
                    local skinData = edge:GetHeight() * mod.UF_ELITE_DRAGON_SCALE
                    eliteDragon:SetSize(skinData, skinData)
                end
                ufStore._eliteDragonOn = useDragon and true or false
                _eliteArmEvents()
                _eliteRefresh(ufStore)
            end
            ufStore._applyEliteIndicator = ApplyEliteIndicator
            ApplyEliteIndicator()
        end

        _setupEliteIndicator(frameList.target, saved.profile.target)
    end

    -- Portrait Dragon (Player Frame Dragon, Elite Enemy Dragon): nothing is
    -- built, and no event registered, while every frame's is off.
    mod.UF_ApplyPortraitDragons()

    -- Faction indicator (Horde/Alliance badge on the target and player frames), driven
    -- like the elite badge above. Mode "always" shows any Horde/Alliance unit;
    -- "opposite" (target) only one whose faction differs from the player's. Faction
    -- NPCs count unless Players Only is on. Neutral units and unreadable (secret)
    -- factions show nothing. PvP flag: "dim" greys the badge on unflagged units,
    -- "only" hides it on them (Blizzard's own rule; the player frame's default, which
    -- makes it a PvP-flagged indicator there), "ignore" draws both alike.
    -- UNIT_FACTION also fires on PvP flag changes. Art: the Icon Style setting, drawn
    -- by CludesUI.SetFactionArt (shared with the nameplates).
    do
        local _factionFrames = {}
        local factionWatch

        local function _factionRefresh(ufStore)
            local cfg = ufStore and ufStore._factionSettings
            if not (ufStore and ufStore._factionIndicator and cfg) then
                return
            end
            local texture = ufStore._factionIndicator
            local mode = cfg.factionIndicatorMode or "off"
            -- The frame's base unit, not its live token: the player frame swaps to
            -- "vehicle" on a ride, but this badge (like Blizzard's PvP icon) and
            -- the UNIT_FACTION registration below are about the player.
            local unitToken = ufStore._cuiBaseUnit
            if mode == "off" or not unitToken or issecretvalue(unitToken) or not UnitExists(unitToken) then
                texture:Hide()
                return
            end
            if cfg.factionIndicatorPlayersOnly then
                local isPlayer = UnitIsPlayer(unitToken)
                if issecretvalue(isPlayer) or not isPlayer then
                    texture:Hide()
                    return
                end
            end
            -- Secrecy check MUST run before the lookup and comparisons, same rule
            -- as the leader checks above.
            local fac = UnitFactionGroup(unitToken)
            local atlasName = (not issecretvalue(fac)) and (fac == "Horde" or fac == "Alliance")
            -- Mercenary mode: the player fights for the other faction, so the
            -- player's own badge shows that side (as Blizzard's player frame
            -- does) and "opposite" compares against it.
            if atlasName and unitToken == "player" and UnitIsMercenary("player") then
                fac = (fac == "Horde") and "Alliance" or "Horde"
            end
            if atlasName and mode == "opposite" and unitToken ~= "player" then
                local mine = UnitFactionGroup("player")
                if issecretvalue(mine) then
                    atlasName = nil
                else
                    if UnitIsMercenary("player") then
                        if mine == "Horde" then
                            mine = "Alliance"
                        elseif mine == "Alliance" then
                            mine = "Horde"
                        end
                    end
                    if mine == fac then
                        atlasName = nil
                    end
                end
            end
            local dim = false
            if atlasName then
                local pvpMode = cfg.factionIndicatorPvP or "dim"
                if pvpMode ~= "ignore" then
                    -- Unreadable counts as flagged: never hide or grey on a guess.
                    local pvp = UnitIsPVP(unitToken)
                    local unflagged = not issecretvalue(pvp) and not pvp
                    if unflagged and pvpMode == "only" then
                        atlasName = nil
                    end
                    dim = unflagged and pvpMode == "dim"
                end
            end
            if atlasName then
                -- Paint only on a real change: faction, style, dim and the honor
                -- badge are the paint's only inputs (the texture is ours, so the
                -- memo lives on it).
                local look = cfg.factionIndicatorStyle or "pvp"
                local badge = CludesUI.FactionBadgeFor(look, unitToken)
                if
                    texture._facFac ~= fac
                    or texture._facStyle ~= look
                    or texture._facDim ~= dim
                    or texture._facBadge ~= badge
                then
                    texture._facFac, texture._facStyle, texture._facDim, texture._facBadge =
                        fac, look, dim, badge
                    CludesUI.SetFactionArt(texture, look, fac, badge)
                    texture:SetDesaturated(dim)
                    texture:SetAlpha(dim and 0.6 or 1)
                end
                texture:Show()
            else
                texture:Hide()
            end
        end

        -- Events are registered only while the feature is on somewhere (zero cost
        -- while off) and re-armed from every settings apply.
        local function _factionArmEvents()
            local enabled, targetOn = false, false
            for index = 1, #_factionFrames do
                local ufStore = _factionFrames[index]
                local cfg = ufStore._factionSettings
                if cfg and (cfg.factionIndicatorMode or "off") ~= "off" then
                    enabled = true
                    if ufStore._cuiBaseUnit == "target" then
                        targetOn = true
                    end
                end
            end
            if enabled then
                if not factionWatch then
                    factionWatch = CreateFrame("Frame")
                    -- Routed by event: a target change or a target flip touches only
                    -- the target badge; the player's own flip and a world load touch
                    -- both (Opposite compares against the player's faction).
                    factionWatch:SetScript("OnEvent", function(_, evt, unitToken)
                        local all = evt == "PLAYER_ENTERING_WORLD" or unitToken == "player"
                        for index = 1, #_factionFrames do
                            local ufStore = _factionFrames[index]
                            if all or ufStore._cuiBaseUnit == "target" then
                                _factionRefresh(ufStore)
                            end
                        end
                    end)
                end
                if targetOn then
                    factionWatch:RegisterEvent("PLAYER_TARGET_CHANGED")
                else
                    factionWatch:UnregisterEvent("PLAYER_TARGET_CHANGED")
                end
                -- The target's flips only matter while its badge is on.
                if targetOn then
                    factionWatch:RegisterUnitEvent("UNIT_FACTION", "target", "player")
                else
                    factionWatch:RegisterUnitEvent("UNIT_FACTION", "player")
                end
                factionWatch:RegisterEvent("PLAYER_ENTERING_WORLD")
            elseif factionWatch then
                factionWatch:UnregisterAllEvents()
            end
        end

        local function _setupFactionIndicator(ufStore, prefs)
            if not (ufStore and ufStore.Health and prefs) then
                return
            end
            if not ufStore._factionIndicator then
                -- Same parent and layer choice as the leader crown above.
                local par = ufStore._textOverlay or ufStore
                local texture = par:CreateTexture(nil, "OVERLAY", nil, 7)
                texture:Hide()
                ufStore._factionIndicator = texture
                _factionFrames[#_factionFrames + 1] = ufStore
            end
            ufStore._factionSettings = prefs

            local function ApplyFactionIndicator()
                -- Re-read by unit key: a profile switch (RepointAllDBs) swaps
                -- db.profile, so the table captured at setup would go stale.
                prefs = saved.profile[ufStore._cuiBaseUnit] or prefs
                ufStore._factionSettings = prefs
                local sz = prefs.factionIndicatorSize or 18
                local place = prefs.factionIndicatorPosition or "topright"
                local ox = prefs.factionIndicatorX or 0
                local oy = prefs.factionIndicatorY or 0
                local texture = ufStore._factionIndicator
                texture:SetSize(sz, sz)
                texture:ClearAllPoints()
                -- Never centred on a hidden backdrop (ns.UF_PortraitShown).
                if
                    place == "portrait"
                    and mod.UF_PortraitShown(prefs)
                    and ufStore.Portrait
                    and ufStore.Portrait.backdrop
                then
                    texture:SetPoint("CENTER", ufStore.Portrait.backdrop, "CENTER", ox, oy)
                else
                    local anchor = (place == "topleft" and "TOPLEFT")
                        or (place == "bottomleft" and "BOTTOMLEFT")
                        or (place == "bottomright" and "BOTTOMRIGHT")
                        or "TOPRIGHT"
                    -- Corners of the whole frame (portrait included), so "Top Left"
                    -- is the frame's top-left whichever side the portrait is on.
                    texture:SetPoint(anchor, ufStore, anchor, ox, oy)
                end
                _factionArmEvents()
                _factionRefresh(ufStore)
            end
            ufStore._applyFactionIndicator = ApplyFactionIndicator
            ApplyFactionIndicator()
        end

        _setupFactionIndicator(frameList.player, saved.profile.player)
        _setupFactionIndicator(frameList.target, saved.profile.target)
    end

    local petFrameSource = mod.GetUnitFrameSource("pet")
    if petFrameSource == "cui" then
        frameList.pet = mod.Engine.SpawnUnitFrame("pet", "CludesUIUnitFrames_Pet")
        StyleSimpleFrame(frameList.pet, "pet")
        mod.UF_AttachEngineFrame(frameList.pet, "pet")
        ApplyFramePosition(frameList.pet, "pet")
        SetupUnitMenu(frameList.pet, "pet")
    elseif petFrameSource == "hidden" then
        mod.Engine.HideBlizzardUnitFrame("pet")
    end

    local totFrameSource = mod.GetUnitFrameSource("targettarget")
    if totFrameSource == "cui" then
        frameList.targettarget = mod.Engine.SpawnUnitFrame("targettarget", "CludesUIUnitFrames_TargetTarget")
        StyleSimpleFrame(frameList.targettarget, "targettarget")
        mod.UF_AttachEngineFrame(frameList.targettarget, "targettarget", true)
        ApplyFramePosition(frameList.targettarget, "targettarget")
        SetupUnitMenu(frameList.targettarget, "targettarget")
    end
    -- Blizzard's target-of-target is a child of TargetFrame. When the target frame
    -- itself is CUI or hidden, TargetFrame is already disabled so the child is gone
    -- with it. Only needs suppressing when the target uses Blizzard's live frame but
    -- the user does NOT want Blizzard's ToT (CUI or hidden) -- else both would show,
    -- or while TargetFrame is kept shown for the WoW Forever gamepad target menu
    -- (ns.UF_TargetMenuOwner): the child, a clickable unit button, would take clicks.
    if (totFrameSource ~= "blizzard" and targetFrameSource == "blizzard") or mod.UF_TargetMenuOwner then
        SuppressBlizzardChildFrame(TargetFrame and TargetFrame.totFrame)
    end

    local ftFrameSource = mod.GetUnitFrameSource("focustarget")
    if ftFrameSource == "cui" then
        frameList.focustarget = mod.Engine.SpawnUnitFrame("focustarget", "CludesUIUnitFrames_FocusTarget")
        StyleSimpleFrame(frameList.focustarget, "focustarget")
        mod.UF_AttachEngineFrame(frameList.focustarget, "focustarget", true)
        ApplyFramePosition(frameList.focustarget, "focustarget")
        SetupUnitMenu(frameList.focustarget, "focustarget")
    end
    -- Same as target-of-target: FocusFrame's native focus-target is a child of
    -- FocusFrame, so it only needs suppressing when focus uses Blizzard's live frame
    -- and the user does not want the native focus-target.
    if ftFrameSource ~= "blizzard" and focusFrameSource == "blizzard" then
        SuppressBlizzardChildFrame(FocusFrame and FocusFrame.totFrame)
    end

    local bossFrameSource = mod.GetUnitFrameSource("boss")
    if bossFrameSource == "cui" then
        local bossPos = saved.profile.positions.boss

        local spacing = mod.UF_BossSpacing()
        local bossStackDir = saved.profile.boss and saved.profile.boss.bossStackDirection or "down"
        for index = 1, 5 do
            local bossUnit = "boss" .. index
            local bossFrame = mod.Engine.SpawnUnitFrame(bossUnit, "CludesUIUnitFrames_Boss" .. index)
            StyleBossFrame(bossFrame, bossUnit)
            mod.UF_AttachEngineFrame(bossFrame, bossUnit)
            frameList[bossUnit] = bossFrame

            -- boss1 anchors to UIParent; boss2..5 chain off boss1 with spacing.
            -- This keeps the whole stack moving together when unlock mode drags
            -- boss1 -- the only draggable boss frame.
            if index == 1 then
                if bossPos then
                    bossFrame:ClearAllPoints()
                    bossFrame:SetPoint(
                        bossPos.point,
                        UIParent,
                        bossPos.relPoint or bossPos.point,
                        bossPos.x,
                        bossPos.y
                    )
                end
            else
                local previous = frameList["boss" .. (index - 1)]
                if previous then
                    bossFrame:ClearAllPoints()
                    if bossStackDir == "up" then
                        bossFrame:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, spacing)
                    else
                        bossFrame:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, -spacing)
                    end
                end
            end

            SetupUnitMenu(bossFrame, bossUnit)
        end
    elseif bossFrameSource == "hidden" then
        -- Suppressing boss1 takes the whole BossTargetFrameContainer with it
        -- (and all five Boss*TargetFrame children).
        mod.Engine.HideBlizzardUnitFrame("boss1")
    end

    -- Kill Blizzard's boss frames for every source except "blizzard" (where the
    -- user wants them). For "cui" oUF already disabled them at spawn; this pass
    -- is belt-and-suspenders and also runs for "hidden".
    if bossFrameSource ~= "blizzard" then
        for index = 1, 5 do
            local blizzBoss = _G["Boss" .. index .. "TargetFrame"]
            if blizzBoss then
                blizzBoss:UnregisterAllEvents()
                blizzBoss:Hide()
            end
        end
    end

    -- Apply user-selected frame strata to all unit frames
    local ufStrata = saved.profile.frameStrata or "MEDIUM"
    for unitName, widget in pairs(frameList) do
        if type(widget) == "table" and widget.SetFrameStrata then
            -- Any unit with its own settings table can override the global
            -- strata; nil (the default) means "follow the global value". See
            -- the matching comment in the other frameStrata-apply pass for why
            -- this resolves through GetSettingsForUnit.
            local strata = ufStrata
            local us = GetSettingsForUnit(unitName)
            if us and us.frameStrata then
                strata = us.frameStrata
            end
            widget:SetFrameStrata(strata)
            if widget.BottomTextBar and widget.BottomTextBar._isDetached then
                if saved.profile.enableCustomBarStratas then
                    widget.BottomTextBar:SetFrameStrata(saved.profile.detachedTextBarStrata or "DIALOG")
                else
                    widget.BottomTextBar:SetFrameStrata(strata)
                end
            end
            -- Same re-lift for a detached power bar -- see the matching comment
            -- in the other frameStrata-apply pass above for why this is needed.
            if widget.Power then
                local us2 = GetSettingsForUnit(unitName)
                local powerPos = mod.UF_PowerPos(us2)
                if powerPos == "detached_top" or powerPos == "detached_bottom" then
                    if saved.profile.enableCustomBarStratas then
                        widget.Power:SetFrameStrata(saved.profile.detachedPowerStrata or "HIGH")
                    else
                        widget.Power:SetFrameStrata("MEDIUM")
                    end
                end
            end
            -- The cast bar is a child of the frame, so SetFrameStrata above reset it to
            -- the frame's strata. Lift to HIGH so it never hides behind other MEDIUM-
            -- strata frames, unless "Raise Cast Bar Strata (All)" is off, in which case
            -- it's explicitly left at the frame's strata.
            if widget.Castbar and (unitName == "player" or IsKickCastbarUnit(unitName)) then
                local cbg = widget.Castbar:GetParent()
                if cbg then
                    if saved.profile.raiseCastbarStrata ~= false then
                        cbg:SetFrameStrata("HIGH")
                    else
                        cbg:SetFrameStrata(strata)
                    end
                end
            end
            -- SetFrameStrata re-stacks children; lift the raid marker holder back
            -- above the text overlay so the marker is never hidden behind name/health text.
            if widget._raidMarkerHolder and widget._textOverlay then
                widget._raidMarkerHolder:SetFrameLevel(widget._textOverlay:GetFrameLevel() + 5)
            end
            -- Same for the dragon holders: the Portrait Dragon's carries its own
            -- strata and level (kept by its apply), the Pixels Dragon's rides
            -- one level over the portrait.
            local edge = widget.Portrait and widget.Portrait.backdrop
            local wh = edge and edge._winglessHolder
            if wh and wh._on then
                mod.UF_LiftDragonHolder(wh, edge, wh._strata, wh._level)
            end
            if edge and widget._eliteDragonHolder and widget._eliteDragonOn then
                mod.UF_LiftDragonHolder(widget._eliteDragonHolder, edge)
            end
        end
    end

    -- Disable oUF elements for frames where features are initially off.
    -- Portrait backdrop is already hidden by style functions, but oUF
    -- auto-enables the element at spawn time since frame.Portrait is always set.
    for unitToken, widget in pairs(frameList) do
        if type(widget) ~= "table" or not widget.Portrait then -- skip non-frame entries
        elseif widget.Portrait.backdrop then
            local prefs = GetSettingsForUnit(unitToken)
            if
                prefs.showPortrait == false
                or (prefs.portraitStyle or saved.profile.portraitStyle or "attached") == "none"
            then
                if widget:IsElementEnabled("Portrait") then
                    widget:DisableElement("Portrait")
                end
            end
        end
    end

    -- Absorbs: apply style and hide if "none" for player, target, focus.
    -- Leave the oUF HealthPrediction element enabled so events keep flowing
    -- and the calculator stays in sync.
    for _, uKey in ipairs({ "player", "target", "focus" }) do
        local frame = frameList[uKey]
        if frame and frame.HealthPrediction and frame.HealthPrediction.damageAbsorb then
            local absStyle = saved.profile[uKey] and saved.profile[uKey].showPlayerAbsorb
            if absStyle and absStyle ~= "none" then
                ApplyAbsorbStyle(frame.HealthPrediction.damageAbsorb, absStyle, saved.profile[uKey])
                frame.HealthPrediction.damageAbsorb:Show()
                if frame.HealthPrediction.damageAbsorb._forward then
                    frame.HealthPrediction.damageAbsorb._forward:Show()
                end
            else
                frame.HealthPrediction.damageAbsorb:Hide()
                if frame.HealthPrediction.damageAbsorb._forward then
                    frame.HealthPrediction.damageAbsorb._forward:Hide()
                end
            end
            -- Force oUF to re-run the HealthPrediction element so the new
            -- texture is visible immediately without waiting for a health event
            if frame.HealthPrediction and frame.HealthPrediction.ForceUpdate then
                frame.HealthPrediction:ForceUpdate()
            end
        end
    end

    -- Boss frames: same absorb refresh, styled from the TARGET donor block
    -- and gated by the "Show on Boss Frames" toggle (nil = enabled).
    do
        local bossOff = saved.profile.boss and saved.profile.boss.showAbsorbs == false
        local donor = saved.profile.target
        for index = 1, 5 do
            local frame = frameList["boss" .. index]
            if frame and frame.HealthPrediction and frame.HealthPrediction.damageAbsorb then
                local absStyle
                if not bossOff and donor then
                    absStyle = donor.showPlayerAbsorb
                end
                if absStyle and absStyle ~= "none" then
                    ApplyAbsorbStyle(frame.HealthPrediction.damageAbsorb, absStyle, donor)
                    frame.HealthPrediction.damageAbsorb:Show()
                    if frame.HealthPrediction.damageAbsorb._forward then
                        frame.HealthPrediction.damageAbsorb._forward:Show()
                    end
                else
                    frame.HealthPrediction.damageAbsorb:Hide()
                    if frame.HealthPrediction.damageAbsorb._forward then
                        frame.HealthPrediction.damageAbsorb._forward:Hide()
                    end
                end
                if frame.HealthPrediction.ForceUpdate then
                    frame.HealthPrediction:ForceUpdate()
                end
            end
        end
    end

    -- Player castbar: disable oUF element if not wanted (always created now)
    if frameList.player and frameList.player.Castbar then
        if not saved.profile.player.showPlayerCastbar then
            mod.SetCastbarElement(frameList.player, false)
            frameList.player.Castbar:Hide()
            local castbarBg = frameList.player.Castbar:GetParent()
            if castbarBg then
                castbarBg:Hide()
            end
        elseif saved.profile.player.showPlayerCastIcon == false and frameList.player.Castbar._iconFrame then
            frameList.player.Castbar._iconFrame:Hide()
        end
    end
    -- Hide While Using Gamepad: settle the flag and the pad watch.
    mod.UF_ApplyGamepadCastbar()

    -- Target castbar: disable oUF element if not wanted
    if frameList.target and frameList.target.Castbar then
        if saved.profile.target.showCastbar == false then
            if frameList.target:IsElementEnabled("Castbar") then
                frameList.target:DisableElement("Castbar")
            end
            frameList.target.Castbar:Hide()
            local castbarBg = frameList.target.Castbar:GetParent()
            if castbarBg then
                castbarBg:Hide()
            end
        elseif saved.profile.target.showCastIcon == false and frameList.target.Castbar._iconFrame then
            frameList.target.Castbar._iconFrame:Hide()
        end
    end

    -- Focus castbar: disable oUF element if not wanted
    if frameList.focus and frameList.focus.Castbar then
        if saved.profile.focus.showCastbar == false then
            if frameList.focus:IsElementEnabled("Castbar") then
                frameList.focus:DisableElement("Castbar")
            end
            frameList.focus.Castbar:Hide()
            local castbarBg = frameList.focus.Castbar:GetParent()
            if castbarBg then
                castbarBg:Hide()
            end
        elseif saved.profile.focus.showCastIcon == false and frameList.focus.Castbar._iconFrame then
            frameList.focus.Castbar._iconFrame:Hide()
        end
    end

    ---------------------------------------------------------------------------
    --  Group visibility: show/hide player/target/focus based on group state
    ---------------------------------------------------------------------------
    -- Companion mini frame for each main frame: the mini inherits its parent's FULL
    -- effective visibility (modes, multi-selections, hide options, fade, mouseover
    -- reveals, Never/disabled).
    mod.UF_MINI_OF = { player = "pet", target = "targettarget", focus = "focustarget" }

    local _ufInCombat = InCombatLockdown()
    local function UpdateFrameVisibility()
        -- Do NOT return early during combat lockdown. Alpha operations
        -- (SetAlpha) are not restricted and must run on combat transitions.
        -- Show/Hide and SetAttribute ARE restricted; those are guarded below.
        local isLocked = InCombatLockdown()
        local raidNow = IsInRaid()
        local inParty = not raidNow and IsInGroup()
        local solo = not raidNow and not inParty
        -- One state table per pass for the multi-select visibility engine
        local visState = { inCombat = _ufInCombat, inRaid = raidNow, inParty = inParty }
        for _, unitName in ipairs({ "player", "target", "focus" }) do
            local cfg = saved.profile[unitName]
            local widget = frameList[unitName]
            -- Visibility "never" no longer clears enabledFrames, so a frame hidden that
            -- way stays on this path and is hidden below, reversibly.
            if widget and not mod.VisUnitDisabled(saved.profile, unitName) and cfg then
                local hiddenByOpts = CludesUI.CheckVisibilityOptions(cfg)
                local visible = cfg.barVisibility or "always"

                -- Multi-select / dragonriding path: non-nil = engine-owned.
                -- nil = legacy single mode, untouched.
                local ext =
                    CludesUI.EvalVisibilityExtended(cfg, "barVisibility", visState, CludesUI.VIS_CAPS_DEFAULT)

                -- Secure condition driver: an engine-owned selection compiles into a
                -- state-visibility driver (the action bar mechanism), replacing the
                -- frame's unit watch. A driver-hidden frame is TRULY hidden -- absorbs
                -- no clicks -- and the secure engine flips it mid-combat natively.
                -- Mouseover sets keep the frame shown while conditions pass (compiler
                -- ignores the mouseover key); the alpha bucket + hover handlers do the
                -- revealing. Registration is out-of-combat only; a selection changed
                -- during combat rides on alpha until the regen pass registers the driver.
                local drvSet = CludesUI.GetActiveVisibilityModes(cfg, "barVisibility")
                -- Condition scalars ride the driver too: dragonriding (engine owns it
                -- everywhere) and the combat pair, whose legacy alpha-hide left an
                -- invisible click-absorbing frame out of combat. Visibility is
                -- unchanged; the driver just hides for real and flips exactly at the combat edge.
                if
                    not drvSet
                    and (
                        visible == "show_dragonriding"
                        or visible == "show_not_dragonriding"
                        or visible == "in_combat"
                        or visible == "out_of_combat"
                    )
                then
                    drvSet = { [visible] = true }
                end
                -- Tail built once and reused by the mini frame below (both compilers only
                -- PREPEND their prefix).
                local visTail
                -- An applied Visibility override replaces the whole setting, so the tail
                -- is a constant and the shared selection never reaches the driver.
                local visOv = CludesUI.VisOverrideValue(cfg)
                if visOv then
                    visTail = (visOv == "never") and "hide" or "show"
                elseif cfg.visibilityMatch == "any" and CludesUI.BuildAnyMatchTail then
                    local tail, _, liveAxes = CludesUI.BuildAnyMatchTail(cfg, "barVisibility", drvSet)
                    -- Gated on liveAxes: with no soft-target edge here, target/enemy axes
                    -- resolve in Lua, and a driver compiled from those alone would be a
                    -- frozen constant. Zero live axes keeps the frame on the live ext/alpha path.
                    if liveAxes > 0 then
                        visTail = tail
                    end
                elseif drvSet and CludesUI.BuildVisibilityDriverString then
                    visTail = CludesUI.BuildVisibilityDriverString("", drvSet)
                end
                -- Off the override, never the stored scalar: an override REPLACES the
                -- shared setting, so a profile-level "never" under an override of Always
                -- must not pin anything, and an override of "never" must pin even though
                -- the stored scalar says otherwise.
                local visNever = (visOv or visible) == "never"
                -- Health cannot be a secure macro condition. Keep the unit watch
                -- active and let the secret-safe alpha curve reveal injured units.
                if mod.HealthVisibilityEnabled(cfg, widget) then
                    visTail = nil
                end
                local wantDriver
                if visNever then
                    -- Never is terminal, so it pins the secure driver instead of
                    -- riding the Show/Hide bucket below: that bucket is lockdown-
                    -- gated, and acquiring a target in combat would otherwise let
                    -- the unit watch show an alpha-0 click blocker until regen.
                    wantDriver = "hide"
                elseif visTail then
                    wantDriver = "[@" .. unitName .. ",noexists] hide; " .. visTail
                end
                if widget._cuiVisDriver ~= wantDriver and not isLocked then
                    if wantDriver then
                        UnregisterUnitWatch(widget)
                        RegisterAttributeDriver(widget, "state-visibility", wantDriver)
                    else
                        UnregisterAttributeDriver(widget, "state-visibility")
                        RegisterUnitWatch(widget)
                    end
                    widget._cuiVisDriver = wantDriver
                end

                -- Combat-sensitive and mouseover modes use SetAlpha to show/hide
                -- (not a restricted API); the frame stays technically shown so it can
                -- transition instantly, alpha controls visibility. For the player frame
                -- we drive alpha on a non-secure wrapper (_visWrap) so nothing touching
                -- the inner frame's alpha (oUF updates, secure templates) can fight us --
                -- alpha inherits down the parent chain so wrapper alpha 0 always wins.
                local alphaTarget = widget._visWrap or widget
                -- Shared with both hover handlers. Forces 0 for the visHide* overrides too,
                -- so the frame looks hidden while the secure bucket below stays untouched:
                -- a dismount inside a lockdown would otherwise hide it permanently.
                -- _ufInCombat leads InCombatLockdown() on regen, so the ooc fade is instant.
                local bodyAlpha, hoverGated = mod.ResolveVisResting(cfg, widget, ext, hiddenByOpts, _ufInCombat)
                if cfg.showWhenHealthMissing and not hiddenByOpts then
                    bodyAlpha = mod.HealthVisibilityAlpha(cfg, widget, bodyAlpha, hoverGated, _ufInCombat)
                else
                    -- Off, or a Visibility Option hides it: health ticks must not reveal.
                    widget._healthVisLive = nil
                end
                alphaTarget:SetAlpha(bodyAlpha)

                -- 3D PlayerModel frames don't inherit parent alpha, so the model must
                -- mirror the EXACT body alpha computed above -- every alpha-hidden state
                -- (engine-owned, in_combat, out_of_combat, mouseover, hide-opts) would
                -- otherwise leave a floating portrait over an invisible frame. Hover
                -- handlers mirror it too when they reveal a mouseover frame.
                local bd3d = widget.Portrait and widget.Portrait.backdrop and widget.Portrait.backdrop._3d
                if bd3d then
                    mod.UF_SetModelAlpha(bd3d, bodyAlpha)
                end

                -- A class resource bar unlocked from the frame is parented to UIParent
                -- and so survives its owner being hidden. Only Never takes it along:
                -- that used to leave the player frame unspawned and the bar with it,
                -- and the other hiding modes have always kept their own bar visible.
                -- Written only when it moves: this pass runs on every target change,
                -- and for the "blizzard" style the bar is Blizzard's own frame. A bar
                -- locked to the frame is its child, so the Show When Health Missing
                -- reveal makes its alpha read secret: it is written blind then.
                if unitName == "player" and frameList._classPowerBar then
                    local cpWant = visNever and 0 or 1
                    local cpHave = frameList._classPowerBar:GetAlpha()
                    if issecretvalue(cpHave) or cpHave ~= cpWant then
                        frameList._classPowerBar:SetAlpha(cpWant)
                    end
                end

                -- Show/Hide and SetAttribute are restricted during lockdown.
                -- When a condition driver is registered it owns Show/Hide
                -- entirely -- a manual toggle would de-sync it until its
                -- next re-evaluation -- so this whole bucket steps aside.
                if not isLocked and not widget._cuiVisDriver then
                    local showIt
                    if visNever then
                        -- Ahead of the engine verdict: Never is exclusive, but under
                        -- a leftover Any match the engine evaluates the scalar and
                        -- answers false rather than nil, which would keep the frame
                        -- secure-Shown at alpha 0 and still eating clicks.
                        showIt = false
                    elseif mod.HealthVisibilityEnabled(cfg, widget) then
                        showIt = true
                    elseif ext ~= nil then
                        -- Engine-owned: frame stays secure-Shown; the alpha
                        -- bucket above drives visibility.
                        showIt = true
                    elseif visible == "in_combat" or visible == "out_of_combat" or visible == "mouseover" then
                        -- Frame is kept shown; alpha (above) drives visibility.
                        showIt = true
                    elseif visible == "in_raid" then
                        showIt = raidNow
                    elseif visible == "in_party" then
                        showIt = inParty
                    elseif visible == "solo" then
                        showIt = solo
                    else
                        -- "always" is the default -- always Shown at secure
                        -- level; alpha controls actual visibility.
                        showIt = true
                    end

                    if showIt then
                        if not widget:IsShown() and UnitExists(unitName) then
                            widget:SetAttribute("unit", unitName)
                            -- Re-enable the engine elements that were disabled on hide.
                            -- Castbar is handled separately below to respect the
                            -- user's show/hide setting -- never blindly re-enable it.
                            for _, elem in ipairs({ "Health", "Power", "Portrait", "HealthPrediction" }) do
                                if widget[elem] and not widget:IsElementEnabled(elem) then
                                    widget:EnableElement(elem)
                                end
                            end
                            -- Restore castbar state based on saved setting
                            if widget.Castbar then
                                local wantsCastbar
                                if unitName == "player" then
                                    -- Hide While Using Gamepad keeps it off (ns.UF_ApplyGamepadCastbar).
                                    wantsCastbar = cfg.showPlayerCastbar and not mod._ufCastPadHidden
                                else
                                    wantsCastbar = cfg.showCastbar ~= false
                                end
                                if wantsCastbar then
                                    mod.SetCastbarElement(widget, true)
                                else
                                    mod.SetCastbarElement(widget, false)
                                    widget.Castbar:Hide()
                                    local castbarBg = widget.Castbar:GetParent()
                                    if castbarBg then
                                        castbarBg:Hide()
                                    end
                                end
                            end
                            widget:Show()
                            -- Full engine repaint: the SetAttribute above reuses
                            -- the same unit token, so the attribute hook sees no
                            -- change and never repaints on its own.
                            mod.Engine.RepaintAll(widget, "GroupVisibility")
                        end
                    else
                        if widget:IsShown() then
                            -- Disable the engine elements before hiding to prevent a
                            -- single-frame flash when the unit attribute is cleared
                            for _, elem in ipairs({ "Health", "Power", "Portrait", "HealthPrediction" }) do
                                if widget[elem] and widget:IsElementEnabled(elem) then
                                    widget:DisableElement(elem)
                                end
                            end
                            mod.SetCastbarElement(widget, false)
                            widget:Hide()
                            widget:SetAttribute("unit", nil)
                        end
                    end
                end

                local miniFrame = frameList[mod.UF_MINI_OF[unitName]]
                -- Always Show Pet Frame: the pet opts out of every parent
                -- visibility inheritance in this pass -- its own unit watch
                -- alone owns Show/Hide (visible whenever a pet exists).
                local miniAlways = (unitName == "player")
                    and saved.profile.pet
                    and saved.profile.pet.alwaysShow

                -- The companion mini frame gets its own condition driver
                -- (parent conditions + its own unit existence), so a
                -- condition-hidden mini absorbs no clicks either.
                if miniFrame then
                    local miniWant
                    if (not miniAlways) and visNever then
                        -- The parent is hidden outright, so alpha 0 alone would leave
                        -- the mini an invisible click blocker; pin it like the
                        -- disabled-parent branch below does.
                        miniWant = "hide"
                    elseif (not miniAlways) and visTail then
                        miniWant = "[@" .. mod.UF_MINI_OF[unitName] .. ",noexists] hide; " .. visTail
                    end
                    if miniFrame._cuiVisDriver ~= miniWant and not isLocked then
                        if miniWant then
                            UnregisterUnitWatch(miniFrame)
                            RegisterAttributeDriver(miniFrame, "state-visibility", miniWant)
                        else
                            UnregisterAttributeDriver(miniFrame, "state-visibility")
                            RegisterUnitWatch(miniFrame)
                        end
                        miniFrame._cuiVisDriver = miniWant
                    end
                end

                -- Mini-frame visibility inheritance: pet follows player, target-of-target
                -- follows target, focus-target follows focus. The mini mirrors the
                -- parent's effective state -- body alpha computed above (modes, multi-
                -- selections, hide options, ooc fade, mouseover default) plus the secure
                -- Show/Hide bucket via IsShown() -- so every way the parent hides takes
                -- its mini along. RegisterUnitWatch keeps owning the mini's own Show/Hide
                -- (unit existence); alpha never conflicts with it. Hover reveals mirror
                -- in the OnEnter/OnLeave handlers.
                if miniFrame then
                    if miniAlways then
                        miniFrame:SetAlpha(1)
                    elseif widget:IsShown() then
                        miniFrame:SetAlpha(bodyAlpha)
                    else
                        miniFrame:SetAlpha(0)
                    end
                end
            elseif widget then
                -- Parent disabled (the "Enable X Frame" toggles): a leftover condition
                -- driver must not keep re-showing the frame, so pin it to a constant
                -- hide. Frames that never had a driver keep the legacy disabled path
                -- untouched. The mini inherits both.
                if not isLocked and widget._cuiVisDriver and widget._cuiVisDriver ~= "hide" then
                    RegisterAttributeDriver(widget, "state-visibility", "hide")
                    widget._cuiVisDriver = "hide"
                end
                local miniFrame = frameList[mod.UF_MINI_OF[unitName]]
                if miniFrame then
                    local miniAlways = (unitName == "player")
                        and saved.profile.pet
                        and saved.profile.pet.alwaysShow
                    if miniAlways then
                        -- Always Show Pet Frame survives a disabled player
                        -- frame: unpin any driver so the pet's own unit
                        -- watch shows it whenever a pet exists.
                        if not isLocked and miniFrame._cuiVisDriver then
                            UnregisterAttributeDriver(miniFrame, "state-visibility")
                            RegisterUnitWatch(miniFrame)
                            miniFrame._cuiVisDriver = nil
                        end
                        miniFrame:SetAlpha(1)
                    else
                        if not isLocked and miniFrame._cuiVisDriver and miniFrame._cuiVisDriver ~= "hide" then
                            RegisterAttributeDriver(miniFrame, "state-visibility", "hide")
                            miniFrame._cuiVisDriver = "hide"
                        end
                        miniFrame:SetAlpha(0)
                    end
                end
            end
        end
        mod.SyncHealthVisibilityEvents()
    end
    mod.UpdateFrameVisibility = UpdateFrameVisibility

    if not frameList._visFrame then
        frameList._visFrame = CreateFrame("Frame")
        frameList._visFrame:RegisterEvent("GROUP_ROSTER_UPDATE")
        frameList._visFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
        frameList._visFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
        frameList._visFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
        frameList._visFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
        frameList._visFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
        -- Resting: IsResting() has no dedicated poll, so without this the Resting
        -- axis only re-evaluated when some unrelated event above happened to fire.
        frameList._visFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
        -- Vehicle edges for the In Vehicle axis (player-filtered; same reasoning).
        frameList._visFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        frameList._visFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
        frameList._visFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        frameList._visFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
        -- The focus-target mini mirrors the focus frame's alpha below, so a
        -- focus set while the pass last saw that frame hidden left the mini at
        -- alpha 0 until some other trigger ran. Same deferral as target changes.
        frameList._visFrame:RegisterEvent("PLAYER_FOCUS_CHANGED")
        -- Dragonriding visibility modes: capability edge plus the airborne
        -- edge (probed at load in CludesUI_Visibility.lua)
        frameList._visFrame:RegisterEvent("PLAYER_CAN_GLIDE_CHANGED")
        if CludesUI._hasGlidingEvent then
            frameList._visFrame:RegisterEvent("PLAYER_IS_GLIDING_CHANGED")
        end
    end
    frameList._visFrame:SetScript("OnEvent", function(_, evt)
        if evt == "PLAYER_REGEN_DISABLED" then
            _ufInCombat = true
            -- Alpha-only update (SetAlpha is not restricted during lockdown).
            -- Show/Hide paths inside UpdateFrameVisibility are guarded by isLocked.
            UpdateFrameVisibility()
        elseif evt == "PLAYER_REGEN_ENABLED" then
            _ufInCombat = false
            UpdateFrameVisibility()
        else
            -- Defer to next frame to avoid taint from secure execution paths
            C_Timer.After(0, UpdateFrameVisibility)
        end
    end)
    UpdateFrameVisibility()

    ---------------------------------------------------------------------------
    --  Portrait border color: update when target/focus unit changes
    --  so "class color" mode reflects the new unit's color.
    ---------------------------------------------------------------------------
    if not frameList._portraitBorderUpdater then
        frameList._portraitBorderUpdater = CreateFrame("Frame")
        frameList._portraitBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frameList._portraitBorderUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
    end
    frameList._portraitBorderUpdater:SetScript("OnEvent", function(_, evt)
        local unitName = (evt == "PLAYER_TARGET_CHANGED") and "target" or "focus"
        local widget = frameList[unitName]
        if widget and (unitName == "target" or unitName == "focus") then
            mod.UF_RecolorTexts(widget, unitName, saved.profile[unitName])
        end
        if not widget or not widget.Portrait then
            return
        end
        local backdrop = widget.Portrait.backdrop
        if not backdrop then
            return
        end
        local uSettings = saved.profile[unitName]
        -- Refresh detached portrait border class color
        if uSettings and uSettings.detachedPortraitClassColor then
            ApplyDetachedPortraitShape(backdrop, uSettings, unitName)
        end
    end)

    ---------------------------------------------------------------------------
    --  Portrait art readiness for the OnUpdate-polled frames (Target of Target
    --  / Focus Target). PORTRAITS_UPDATED is how the client says portrait art
    --  finished loading, and PortraitOverride acts on it -- but the event is
    --  never registered on these frames: once __eventless is set, the unit
    --  frame library's RegisterEvent drops everything except
    --  UNIT_PORTRAIT_UPDATE and UNIT_MODEL_CHANGED. PLAYER_ENTERING_WORLD
    --  still reaches them (UpdateAllElements pushes it to every element), so
    --  they take the mid-loading blank paint with nothing to heal it: the poll
    --  just re-runs the same guid-gated Override. ForceUpdate is the trigger
    --  that gate always honors. 2D only -- a PlayerModel does not read portrait
    --  art, and repainting one costs a ClearModel + SetUnit reload.
    ---------------------------------------------------------------------------
    if not frameList._portraitArtUpdater then
        frameList._portraitArtUpdater = CreateFrame("Frame")
        frameList._portraitArtUpdater:RegisterEvent("PORTRAITS_UPDATED")
    end
    frameList._portraitArtUpdater:SetScript("OnEvent", function()
        for _, widget in pairs(frameList) do
            if type(widget) == "table" and widget.__eventless and widget.IsElementEnabled then
                local p = widget.Portrait
                if
                    p
                    and p.ForceUpdate
                    and not p:IsObjectType("PlayerModel")
                    and widget:IsElementEnabled("Portrait")
                then
                    p:ForceUpdate()
                end
            end
        end
    end)

    -- Target-of-target/focus-target/pet text class colors must re-apply when their unit
    -- changes or first becomes available (login/reload). Unlike target/focus, mini
    -- frames have no PLAYER_*_CHANGED of their own, so a class color set at style
    -- time -- when "targettarget"/"focustarget"/"pet" was not yet a resolvable unit --
    -- falls back to white/reaction-nil and never recovers. Re-apply on the parent's
    -- target change and on its UNIT_TARGET, and on UNIT_PET for the pet frame.
    local function ReapplyFrameTextClassColors(unitName)
        local widget = frameList[unitName]
        local cfg = widget and saved.profile[unitName]
        if not cfg then
            return
        end
        if widget.LeftText and cfg.leftTextClassColor ~= nil then
            ApplyClassColor(
                widget.LeftText,
                unitName,
                cfg.leftTextClassColor,
                cfg.leftTextColorR,
                cfg.leftTextColorG,
                cfg.leftTextColorB
            )
        end
        if widget.RightText and cfg.rightTextClassColor ~= nil then
            ApplyClassColor(
                widget.RightText,
                unitName,
                cfg.rightTextClassColor,
                cfg.rightTextColorR,
                cfg.rightTextColorG,
                cfg.rightTextColorB
            )
        end
        if widget.CenterText and cfg.centerTextClassColor ~= nil then
            ApplyClassColor(
                widget.CenterText,
                unitName,
                cfg.centerTextClassColor,
                cfg.centerTextColorR,
                cfg.centerTextColorG,
                cfg.centerTextColorB
            )
        end
    end
    if not frameList._miniTextClassUpdater then
        frameList._miniTextClassUpdater = CreateFrame("Frame")
        frameList._miniTextClassUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frameList._miniTextClassUpdater:RegisterEvent("PLAYER_FOCUS_CHANGED")
        frameList._miniTextClassUpdater:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
        frameList._miniTextClassUpdater:RegisterUnitEvent("UNIT_PET", "player")
    end
    frameList._miniTextClassUpdater:SetScript("OnEvent", function(_, evt, arg1)
        if evt == "PLAYER_TARGET_CHANGED" then
            ReapplyFrameTextClassColors("targettarget")
        elseif evt == "PLAYER_FOCUS_CHANGED" then
            ReapplyFrameTextClassColors("focustarget")
        elseif evt == "UNIT_PET" then
            ReapplyFrameTextClassColors("pet")
        elseif arg1 == "target" then
            ReapplyFrameTextClassColors("targettarget")
        elseif arg1 == "focus" then
            ReapplyFrameTextClassColors("focustarget")
        end
    end)

    -- Boss Hover/Target border: refresh each boss frame's target state when the
    -- player's target changes or boss units (dis)appear. Hover is handled by the
    -- OnEnter/OnLeave hooks; this only tracks target. Both borders default off, so
    -- this is a cheap no-op unless the user enabled one. On ns for the 200-local cap.
    mod.UpdateBossTargetBorders = function()
        local cfg = saved.profile.boss
        for index = 1, 5 do
            local bUnit = "boss" .. index
            local frame = frameList[bUnit]
            if frame then
                if frame.unifiedBorder then
                    local isT = UnitIsUnit(bUnit, "target")
                    frame._isTarget = (not issecretvalue(isT) and isT) and true or false
                    mod.ApplyBossBorderState(frame)
                end
                if cfg then
                    if frame.LeftText and cfg.leftTextClassColor ~= nil then
                        ApplyClassColor(
                            frame.LeftText,
                            bUnit,
                            cfg.leftTextClassColor,
                            cfg.leftTextColorR,
                            cfg.leftTextColorG,
                            cfg.leftTextColorB
                        )
                    end
                    if frame.RightText and cfg.rightTextClassColor ~= nil then
                        ApplyClassColor(
                            frame.RightText,
                            bUnit,
                            cfg.rightTextClassColor,
                            cfg.rightTextColorR,
                            cfg.rightTextColorG,
                            cfg.rightTextColorB
                        )
                    end
                    if frame.CenterText and cfg.centerTextClassColor ~= nil then
                        ApplyClassColor(
                            frame.CenterText,
                            bUnit,
                            cfg.centerTextClassColor,
                            cfg.centerTextColorR,
                            cfg.centerTextColorG,
                            cfg.centerTextColorB
                        )
                    end
                end
            end
        end
    end
    if not frameList._bossTargetBorderUpdater then
        frameList._bossTargetBorderUpdater = CreateFrame("Frame")
        frameList._bossTargetBorderUpdater:RegisterEvent("PLAYER_TARGET_CHANGED")
        frameList._bossTargetBorderUpdater:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT")
        frameList._bossTargetBorderUpdater:RegisterEvent("UNIT_TARGETABLE_CHANGED")
        frameList._bossTargetBorderUpdater:RegisterEvent("PLAYER_ENTERING_WORLD")
    end
    frameList._bossTargetBorderUpdater:SetScript("OnEvent", mod.UpdateBossTargetBorders)
    mod.UpdateBossTargetBorders()

    -- Deferred normalization: some late-login updates can re-anchor power bars
    -- after frame construction. Re-apply two-point attached anchors once more.
    -- Not under Blizzard Style: its layout pass owns the power bar geometry
    -- (a health-width re-anchor here would undo the stock bar placement).
    C_Timer.After(0, function()
        if mod.UF_Blizz() then
            return
        end
        for _, unitName in ipairs({ "player", "target", "focus", "pet" }) do
            local widget = frameList[unitName]
            if widget and widget.Power and widget.Health then
                local cfg = GetSettingsForUnit(unitName)
                if cfg then
                    local powerPos = cfg.powerPosition or "below"
                    if powerPos == "below" or powerPos == "above" then
                        widget.Power:ClearAllPoints()
                        if powerPos == "above" then
                            Pix.Point(widget.Power, "BOTTOMLEFT", widget.Health, "TOPLEFT", 0, 0)
                            Pix.Point(widget.Power, "BOTTOMRIGHT", widget.Health, "TOPRIGHT", 0, 0)
                        else
                            Pix.Point(widget.Power, "TOPLEFT", widget.Health, "BOTTOMLEFT", 0, 0)
                            Pix.Point(widget.Power, "TOPRIGHT", widget.Health, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
            end
        end
        for index = 1, 5 do
            local bf = frameList["boss" .. index]
            if bf and bf.Power and bf.Health then
                local cfg = GetSettingsForUnit("boss")
                if cfg then
                    local powerPos = cfg.powerPosition or "below"
                    if powerPos == "below" or powerPos == "above" then
                        bf.Power:ClearAllPoints()
                        if powerPos == "above" then
                            Pix.Point(bf.Power, "BOTTOMLEFT", bf.Health, "TOPLEFT", 0, 0)
                            Pix.Point(bf.Power, "BOTTOMRIGHT", bf.Health, "TOPRIGHT", 0, 0)
                        else
                            Pix.Point(bf.Power, "TOPLEFT", bf.Health, "BOTTOMLEFT", 0, 0)
                            Pix.Point(bf.Power, "TOPRIGHT", bf.Health, "BOTTOMRIGHT", 0, 0)
                        end
                    end
                end
            end
        end
    end)

    -- Apply all settings (cast bar colors, text, sizes, etc.) now that
    -- frames are spawned and anchored.
    ReloadFrames()
    -- A /reload in combat lands here under lockdown, where ReloadFrames holds
    -- back its frame work: the throttle pass at combat end applies it
    -- (ns.ReloadFrames exists by then, set a frame later by SetupOptionsPanel).
    if InCombatLockdown() then
        mod.CombatQueue.Defer("ReloadFrames", function()
            mod.ReloadFrames()
        end)
    end
end

Inner.InitializeFrames = InitializeFrames
