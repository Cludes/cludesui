if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_RaidFrames_ExtraFrames.lua
--
--  Extra Frames: duplicates of chosen raid members.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local UnitName = UnitName
local UnitClass = UnitClass
local UnitIsUnit = UnitIsUnit
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local C_Timer = C_Timer
local CreateFrame = CreateFrame

local allButtons, ApplyFont, GetFFD = Inner.allButtons, Inner.ApplyFont, Inner.GetFFD
local IsPowerBarEnabled, PixelSnap = Inner.IsPowerBarEnabled, Inner.PixelSnap
local unitToButton, StyleButton, UpdateButton = Inner.unitToButton, Inner.StyleButton, Inner.UpdateButton
local UpdateReadyCheck, LayoutTopNameBar = Inner.UpdateReadyCheck, Inner.LayoutTopNameBar

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end

-------------------------------------------------------------------------------
--  Extra Frames (raid only): 1:1 duplicates of chosen raid members (Show
--  Tanks + hotkey-toggled players, up to XF.CAP). Attached positions stack
--  group-sized runs of 5 like extra raid groups; Free Move uses its own
--  grow/wrap axes (XF.GrowInfo/XF.FreeAnchor) with a growth-corner pin. Each
--  duplicate runs the SAME StyleButton pipeline as real header children
--  (power/absorbs/auras/BM/icons/click-cast/ping) and joins allButtons.
--
--  Duplicates stay OUT of unitToButton (d._isExtra guards every rebuild);
--  each slot has its own tracker + RegisterUnitEvent and lives in
--  ns._xfUnitToButton, which the broadcast passes (target border, markers,
--  range, ghost-aura sweep) also iterate -- zero cost when inactive. Position
--  via shared FB.Anchor; unit assignment is OOC, dirty-deferred through
--  combat. Excluded from preview/unlock mode like FB.
-------------------------------------------------------------------------------
do
    local Extras = { buttons = {}, trackers = {} }
    mod._XF = Extras
    local FB = mod._FB

    Extras.Settings = function() return saved and saved.profile and saved.profile.extraFrames end

    Extras.ShouldBeActive = function()
        local set = Extras.Settings()
        if not set then return false end
        return set.showTanks or #(set.players or {}) > 0
    end

    -- Hard selection bound (internal, no user setting): a full mythic roster's
    -- worth of duplicates while keeping per-unit event mirroring bounded.
    Extras.CAP = 20

    -- Effective growth axes: primary run direction + perpendicular wrap.
    -- Attached modes stack group-sized runs of 5 like additional raid groups:
    -- units along the raid unit growth, each full run slotting further out along
    -- the group growth axis AWAY from the raid ("left" attaches before the first
    -- group, so runs extend against the group growth). Free Move reads Grow
    -- Direction (falling back to the legacy Horizontal toggle) and wraps along
    -- Wrap Direction. Wrap values not perpendicular to the primary run (stale
    -- after a direction change, or a parallel group growth) fall back to the default.
    Extras.GrowInfo = function(set, cfg)
        local grow, wrap
        if set and set.position == "free" then
            grow = set.growDirection or (set.freeHorizontal and "RIGHT" or "DOWN")
            wrap = set.wrapDirection
        else
            grow = (cfg and cfg.unitGrowth) or "DOWN"
            wrap = (cfg and cfg.groupGrowth) or "RIGHT"
            -- Attached runs wrap along the frames' group axis, and the grid flow's
            -- column advance runs right like a plain RIGHT run (FB.Anchor reads it
            -- the same way). Read raw it would miss every branch below: the left
            -- flip falls through to DOWN and the perpendicular check picks the
            -- RIGHT default by luck.
            if wrap == "DOWNRIGHT" then wrap = "RIGHT" end
            if set and set.position == "left" then
                wrap = (wrap == "RIGHT" and "LEFT")
                    or (wrap == "LEFT" and "RIGHT")
                    or (wrap == "DOWN" and "UP")
                    or "DOWN"
            end
        end
        local horizontal = (grow == "LEFT" or grow == "RIGHT")
        if horizontal then
            if wrap ~= "UP" and wrap ~= "DOWN" then wrap = "DOWN" end
        else
            if wrap ~= "LEFT" and wrap ~= "RIGHT" then wrap = "RIGHT" end
        end
        return grow, wrap, horizontal
    end

    -- Free Move anchoring: pin the grid's growth corner to the rect captured at
    -- the last mover drag so frame 1 never shifts as players enter/leave the
    -- selection (the container is sized to the live selection; a CENTER pin
    -- would drift). Falls back to the legacy CENTER anchor (freePos) until the
    -- user drags the mover once. Called by FB.Anchor through the owner hook.
    Extras.FreeAnchor = function(c, set)
        local region = set and set.freeRect
        if not region then return false end
        local grow, wrap, horizontal = Extras.GrowInfo(set, saved and saved.profile)
        local corner, posX, posY =
            FB.CornerPin(horizontal and grow or wrap, horizontal and wrap or grow, region)
        FB.FreePin(c, corner, posX, posY)
        return true
    end

    -- Called by the shared mover on drag stop: capture the dropped rect for the corner pin above.
    Extras.SaveFreeRect = function(mover) FB.SaveMoverRect(mover, Extras.Settings()) end

    -- Ordered raid units to duplicate (bounded by XF.CAP): tanks in roster order first
    -- (Show Tanks on), then manually added names currently in the raid. Names are stored
    -- AND matched in GetRaidRosterInfo's format so realm suffixes always agree; names not
    -- in the roster are skipped but kept (they reappear when that player rejoins).
    Extras.ResolveUnits = function()
        local set = Extras.Settings()
        local units = {}
        if not set or not IsInRaid() then return units end
        local cap = Extras.CAP
        local seen = {}
        local num = GetNumGroupMembers() or 0
        if set.showTanks then
            for i = 1, num do
                if #units >= cap then break end
                local name = GetRaidRosterInfo(i)
                if
                    name
                    and not seen[name]
                    and CUI.UnitEffectiveRole("raid" .. i) == "TANK"
                    -- Exclude Myself (Show Tanks cog): the tanks auto-include
                    -- skips the player's own frame; explicit hotkey picks below
                    -- still add it.
                    and not (set.excludeSelfTank and UnitIsUnit("raid" .. i, "player"))
                then
                    seen[name] = true
                    units[#units + 1] = "raid" .. i
                end
            end
        end
        for _, mname in ipairs(set.players or {}) do
            if #units >= cap then break end
            if not seen[mname] then
                for i = 1, num do
                    if (GetRaidRosterInfo(i)) == mname then
                        seen[mname] = true
                        units[#units + 1] = "raid" .. i
                        break
                    end
                end
            end
        end
        return units
    end

    -- The pitch between the duplicates. Attached beside Compact raid frames they take
    -- the groups' one pixel, so their rows stay level with the groups' (FB.Pitch: the
    -- boss group does the same).
    Extras.Pitch = function(set, cfg)
        if set and set.position ~= "free" and mod.RF_CompactOn(saved.profile, false) then
            return mod.RF_OnePixel(false)
        end
        -- Same grid as FB.FreePin: the extra container's own scale.
        return CUI.PP.SnapForES(cfg.cellSpacing or 2, Extras.container:GetEffectiveScale())
    end

    -- Geometry only: container size, button stacking, per-button size (Extra
    -- Width/Height offsets) and height-derived inner corrections (mirrors
    -- ns._ResizeButtons). All VISUALS come from the shared StyleButton /
    -- ReloadFrames pipeline (buttons are in allButtons); ReloadFrames tail-calls
    -- XF_Apply so this offset pass always runs after the bulk base-size pass.
    Extras.Layout = function()
        if not Extras.built then return end
        local cfg = mod._scaledProfile or saved.profile
        local set = Extras.Settings()
        local wid = PixelSnap(
            math.max(10, (mod._activeSizeW or cfg.frameWidth or 72) + ((set and set.extraWidth) or 0))
        )
        local hgt = PixelSnap(
            math.max(10, (mod._activeSizeH or cfg.frameHeight or 46) + ((set and set.extraHeight) or 0))
        )
        -- Indicator/aura/BM auto-resize: ratio of the custom size to what the
        -- real frames currently render at (clamped like the tier scales). The
        -- extra proxy and ns._xfBmScale pick this up everywhere a duplicate
        -- renders, composing with the raid tier scales.
        local aw = PixelSnap(mod._activeSizeW or cfg.frameWidth or 72)
        local ah = PixelSnap(mod._activeSizeH or cfg.frameHeight or 46)
        local ratio = 1
        -- Auto Resize Indicators cog toggle (nil = ON, additive key): off keeps
        -- indicators/auras/BM at the real frames' base scale regardless of the
        -- extra frames' custom size.
        if aw > 0 and ah > 0 and (not set or set.autoResizeIndicators ~= false) then
            ratio = math.max(math.min(math.min(wid / aw, hgt / ah), 1.3), 0.7)
        end
        mod._xfExtraRatio = ratio
        if mod._RefreshProxyModes then mod._RefreshProxyModes() end
        mod._xfBmScale = (mod._bmScale or 1) * ratio
        local sp = Extras.Pitch(set, cfg)
        Extras.pitch = sp
        -- Free Move lays out on its own axes; attached modes stack group-sized
        -- runs of 5 (unitGrowth within a run, group growth across).
        local grow, wrap, horizontal = Extras.GrowInfo(set, cfg)
        -- Grid size = the live selection; when the mover is shown outside a raid
        -- there is no selection yet, so estimate from the configuration.
        local total = Extras.activeCount or 0
        if total < 1 then
            total = ((set and set.showTanks) and 2 or 0) + ((set and set.players) and #set.players or 0)
            if total < 1 then total = 1 end
            if total > Extras.CAP then total = Extras.CAP end
        end
        -- Frames per run: attached always uses full group-sized runs of 5 (a
        -- partially filled run still spans 5, exactly like a real group); Free
        -- Move wraps at Wrap After (0/unset = one single run).
        local per
        if set and set.position == "free" then
            local wa = tonumber(set.wrapAfter) or 0
            per = (wa > 0) and wa or total
            if per > total then per = total end
        else
            per = 5
        end
        local lines = math.ceil(total / per)

        -- The container spans the occupied grid. Its anchor corner (FB.Anchor's
        -- attached slotting, XF.FreeAnchor's free pin) is the corner the grid
        -- grows away from, so frame 1 holds position as the selection changes.
        local runW, runH = wid * per + sp * (per - 1), hgt * per + sp * (per - 1)
        if horizontal then
            Extras.container:SetSize(runW, hgt * lines + sp * (lines - 1))
        else
            Extras.container:SetSize(wid * lines + sp * (lines - 1), runH)
        end

        local stepW, stepH = wid + sp, hgt + sp
        local powerH = IsPowerBarEnabled(cfg) and PixelSnap(cfg.powerHeight or 4) or 0
        local topBarH = (cfg.topNameBarEnabled and PixelSnap(cfg.topNameBarHeight or 20)) or 0
        for i, btn in ipairs(Extras.buttons) do
            btn:SetSize(wid, hgt)
            btn:ClearAllPoints()
            local off = i - 1
            local line = math.floor(off / per)
            local place = off - line * per
            -- Map the (run, wrap) grid coordinate onto screen axes: the primary
            -- run carries pos, the wrap axis carries line; the anchor corner is
            -- the one both directions grow away from (frame 1 sits there).
            local hUnits, vUnits, hDir, vDir
            if horizontal then
                hUnits, vUnits, hDir, vDir = place, line, grow, wrap
            else
                hUnits, vUnits, hDir, vDir = line, place, wrap, grow
            end
            local corner = (vDir == "UP" and "BOTTOM" or "TOP") .. (hDir == "LEFT" and "RIGHT" or "LEFT")
            btn:SetPoint(
                corner,
                Extras.container,
                corner,
                (hDir == "LEFT" and -hUnits or hUnits) * stepW,
                (vDir == "UP" and vUnits or -vUnits) * stepH
            )
            -- The bulk passes size inner elements for the BASE frame size;
            -- correct the height/width-derived pieces for the offset size.
            local skinData = GetFFD(btn)
            if skinData.health then
                skinData.health:SetHeight(
                    (
                        (skinData.power and skinData.power:IsShown())
                            and PixelSnap(hgt - mod.RF_HealthPowerInset(cfg, powerH))
                        or hgt
                    ) - topBarH
                )
            end

            -- Scaled visual pass: re-apply every ratio-affected element through
            -- the extra proxy (mirrors ReloadFrames per-button styling) so texts/
            -- indicators/auras/BM buffs auto-resize. Bounded to the built slots.
            local xs = mod._scaledExtraProxy
            if xs.topNameBarDivider == true or (skinData.topNameBar and skinData.topNameBar._divider) then
                LayoutTopNameBar(
                    xs,
                    hgt,
                    (skinData.power and skinData.power:IsShown()) and powerH or 0,
                    skinData.health,
                    skinData.topNameBar,
                    skinData.topNameBarBg,
                    skinData.topNameBarText,
                    skinData.power
                )
                if
                    xs.topNameBarDividerMatchColor == true
                    and skinData.topNameBar
                    and skinData.topNameBar._divider
                    and skinData.topNameBar._divider._powerArtMode == "divider"
                then
                    skinData.ApplyBorderColor()
                end
            end
            -- The texts through the extra proxy; the name width follows the offset
            -- width (the layout derives it from the BASE frame width).
            if skinData.AnchorTexts then
                skinData.AnchorTexts()
                mod.RF_TextNameWidth(skinData, wid)
            end
            if skinData.statusText then
                ApplyFont(skinData.statusText, xs.statusTextSize or 14)
                if skinData.AnchorStatusText then skinData.AnchorStatusText() end
            end
            if skinData.roleIcon then
                local riSz = PixelSnap(xs.roleIconSize or 14)
                skinData.roleIcon:SetSize(riSz, riSz)
                if skinData.AnchorRoleIcon then skinData.AnchorRoleIcon() end
            end
            if skinData.leaderIcon then
                local liSz = PixelSnap(xs.leaderIconSize or 14)
                skinData.leaderIcon:SetSize(liSz, liSz)
                skinData.leaderIcon:ClearAllPoints()
                local liPos = (xs.leaderIconPosition or "top"):upper()
                skinData.leaderIcon:SetPoint(
                    liPos,
                    mod.RF_AnchorHost(skinData.health, xs),
                    liPos,
                    xs.leaderIconOffsetX or 0,
                    xs.leaderIconOffsetY or 0
                )
            end
            if skinData.raidMarker then
                local rmSz = PixelSnap(xs.raidMarkerSize or 16)
                skinData.raidMarker:SetSize(rmSz, rmSz)
                if skinData.AnchorRaidMarker then skinData.AnchorRaidMarker() end
            end
            if skinData.readyCheck then
                local rcSz = PixelSnap(xs.readyCheckSize or 20)
                skinData.readyCheck:SetSize(rcSz, rcSz)
                if skinData.AnchorReadyCheck then skinData.AnchorReadyCheck() end
            end
            if skinData.combatIcon then
                local cciSz = PixelSnap(xs.combatIndicatorSize or 16)
                skinData.combatIcon:SetSize(cciSz, cciSz)
                if skinData.AnchorCombatIcon then skinData.AnchorCombatIcon() end
            end
            if skinData.pingFrame then mod._RFAnchorPing(skinData) end
            if mod.RF_FvMissingAnchor then mod.RF_FvMissingAnchor(btn, skinData) end
        end
    end

    -- Per-unit events mirrored from the central hub for one duplicate's unit.
    -- UNIT_* only (safe for RegisterUnitEvent's C-side filter); the two
    -- unit-payload broadcast events (READY_CHECK_CONFIRM, PLAYER_FLAGS_CHANGED)
    -- are plain registrations filtered in the handler.
    Extras.EVENTS = {
        -- UNIT_AURA deliberately absent (Blizzard parity: their CompactUnitFrame
        -- repaints prediction from health/absorb events only). The one gap -- an
        -- aura-granted shield expiring on its TIMER on an unhit, topped unit
        -- (field report: VDH Infernal Strike) fires NO event at all -- is covered
        -- by the armed-members belt next to the absorb coalescer.
        "UNIT_HEALTH",
        "UNIT_MAXHEALTH",
        "UNIT_POWER_UPDATE",
        "UNIT_DISPLAYPOWER",
        "UNIT_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_ABSORB_AMOUNT_CHANGED",
        "UNIT_HEAL_PREDICTION",
        "UNIT_MAX_HEALTH_MODIFIERS_CHANGED",
        "UNIT_THREAT_LIST_UPDATE",
        "UNIT_THREAT_SITUATION_UPDATE",
        "UNIT_NAME_UPDATE",
        "UNIT_CONNECTION",
        "UNIT_IN_RANGE_UPDATE",
    }

    -- Grow-on-demand construction: container + buttons through the full real-frame
    -- StyleButton pipeline. The base 5 slots build on first activation; slots above 5 build
    -- only when the selection reaches them (callers are all OOC). d._isExtra is set BEFORE
    -- StyleButton so the OnAttributeChanged hook it installs never writes the real routing
    -- maps. Buttons join allButtons so every bulk restyle/update pass covers them.
    Extras.EnsureBuilt = function(total)
        if not Extras.built then
            Extras.built = true
            local boxHolder = CreateFrame("Frame", "ERFExtraFramesContainer", UIParent)
            boxHolder:Hide()
            Extras.container = boxHolder
        end
        local wanted = total or 5
        if wanted < 5 then wanted = 5 end

        for i = #Extras.buttons + 1, wanted do
            local widget =
                CreateFrame("Button", "ERFExtraFrame" .. i, Extras.container, "SecureUnitButtonTemplate")
            widget:Hide()
            GetFFD(widget)._isExtra = true
            mod._StyleButtonSecure(widget)
            StyleButton(widget)
            allButtons[#allButtons + 1] = widget

            -- Per-slot tracker: (re)registered for the assigned unit in XF_Apply,
            -- mirroring the central hub's per-unit reactions for this duplicate.
            -- Bounded to the built slots; zero registrations while a slot is empty.
            local t = mod.TakeShell()
            t:SetScript("OnEvent", function(_, evt, unitToken, updateInfo)
                if not widget:IsVisible() then return end
                if evt == "UNIT_HEALTH" or evt == "UNIT_MAXHEALTH" then
                    mod._UpdateButtonHealth(widget, unitToken)
                    if evt == "UNIT_MAXHEALTH" then
                        mod._ResettleButtonHealth(widget)
                        -- Max moves the absorb bars' range; value-only health
                        -- changes touch nothing UpdateAbsorb paints (overlays are
                        -- clip-anchored; the missing-health clamp edge rides the
                        -- armed belt / next absorb event instead).
                        local skinData = GetFFD(widget)
                        if skinData._absActive then mod._MarkAbsorbDirty(widget, unitToken) end
                    end
                elseif evt == "UNIT_POWER_UPDATE" then
                    local skinData = GetFFD(widget)
                    if skinData.power and skinData.power:IsShown() then
                        -- Value only; type/color/bounds ride the UNIT_DISPLAYPOWER
                        -- edge (see the header dispatcher's branch).
                        local pType = skinData._pwType
                        if pType == nil then
                            mod._RFPowerTypeEdge(skinData, unitToken)
                            pType = skinData._pwType
                        end
                        local ppct = UnitPowerPercent(unitToken, pType, true, CurveConstants.ScaleTo100)
                        skinData.power:SetValue(ppct)
                        -- Power Texts ride the same value (one field test while off);
                        -- the Custom texts follow below, power bar or not.
                        if skinData._pwtOn then mod.RF_TextPower(skinData, unitToken, ppct, pType, true) end
                    end
                    local tp = skinData._txP
                    if tp and tp.reads and tp.reads.pp then
                        mod.RF_TextRepaintCustom(skinData, unitToken, "pp")
                    end
                elseif evt == "UNIT_DISPLAYPOWER" then
                    local skinData = GetFFD(widget)
                    if skinData.power and skinData.power:IsShown() then
                        mod._RFPowerTypeEdge(skinData, unitToken)
                        local ppct =
                            UnitPowerPercent(unitToken, skinData._pwType, true, CurveConstants.ScaleTo100)
                        skinData.power:SetValue(ppct)
                        if skinData._pwtOn then
                            mod.RF_TextPower(skinData, unitToken, ppct, skinData._pwType, true)
                        end
                    end
                    local tp = skinData._txP
                    if tp and tp.reads and tp.reads.pp then
                        mod.RF_TextRepaintCustom(skinData, unitToken, "pp")
                    end
                elseif
                    evt == "UNIT_ABSORB_AMOUNT_CHANGED"
                    or evt == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED"
                    or evt == "UNIT_HEAL_PREDICTION"
                    or evt == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED"
                then
                    -- The event IS the arm: plainly observable even while the
                    -- values are secret. Paint coalesces to once per render frame.
                    -- Prediction is view-gated: with the feature off for this
                    -- button's view the event changes no pixel and must not arm.
                    local dropdown = GetFFD(widget)
                    if evt == "UNIT_HEAL_PREDICTION" then
                        local savedVars = dropdown._isParty and mod._scaledPartyProxy
                            or (dropdown._isExtra and mod._scaledExtraProxy)
                            or mod._scaledProfile
                        if savedVars.healPrediction then
                            mod._AbArm(widget, unitToken, dropdown)
                            mod._MarkAbsorbDirty(widget, unitToken)
                        end
                    else
                        if evt ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                            mod._AbArm(widget, unitToken, dropdown)
                        end
                        mod._MarkAbsorbDirty(widget, unitToken)
                        if evt == "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" then
                            mod.UpdateHealAbsorbTextFor(widget, unitToken)
                        end
                        -- Custom texts showing the amount this event moved (two field reads while
                        -- none does); the max-health-modifier edge moves health only.
                        local tp = dropdown._txP
                        if tp and tp.reads and evt ~= "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                            mod.RF_TextRepaintCustom(
                                dropdown,
                                unitToken,
                                evt == "UNIT_ABSORB_AMOUNT_CHANGED" and "abs" or "habs"
                            )
                        end
                        if evt == "UNIT_MAX_HEALTH_MODIFIERS_CHANGED" then
                            dropdown._rmhPct = nil -- reduced-max cache: this is its only value edge
                            mod._UpdateButtonHealth(widget, unitToken)
                            mod._ResettleButtonHealth(widget)
                        end
                    end -- prediction view-gate else
                elseif evt == "UNIT_THREAT_LIST_UPDATE" or evt == "UNIT_THREAT_SITUATION_UPDATE" then
                    local skinData = GetFFD(widget)
                    mod.RF_PaintThreat(
                        skinData,
                        skinData._isExtra and mod._scaledExtraProxy or mod._scaledProfile,
                        unitToken
                    )
                elseif evt == "UNIT_IN_RANGE_UPDATE" then
                    mod._UpdateButtonRange(unitToken, widget)
                elseif evt == "UNIT_FLAGS" then
                    mod._UpdateCombatIconFor(unitToken, widget)
                elseif evt == "READY_CHECK_CONFIRM" then
                    -- Plain registration; filter to this slot's unit here
                    if unitToken and unitToken == widget:GetAttribute("unit") then
                        UpdateReadyCheck(widget, unitToken)
                    end
                elseif evt == "PLAYER_FLAGS_CHANGED" then
                    if unitToken and unitToken == widget:GetAttribute("unit") then UpdateButton(widget) end
                elseif evt == "UNIT_LEVEL" then
                    mod._RFRepaintLevel(widget)
                elseif evt == "UNIT_TARGET" then
                    mod.RF_TextRepaintCustom(GetFFD(widget), unitToken, "tgt")
                else -- UNIT_NAME_UPDATE / UNIT_CONNECTION
                    UpdateButton(widget)
                    if evt == "UNIT_CONNECTION" then mod._UpdateButtonRange(unitToken, widget) end
                end
            end)
            Extras.trackers[i] = t

            Extras.buttons[i] = widget
        end
    end

    -- Master apply: resolves the selection and assigns units to slots. OOC only
    -- (unit attributes and Show/Hide on protected buttons); combat callers land
    -- on the dirty flag and replay on regen. Called from OnEnable, options
    -- widgets, the hotkey toggle, roster/role events, ReloadFrames and profile
    -- swaps. The SetAttribute write triggers the StyleButton OnAttributeChanged
    -- hook, which repaints in full (UpdateButton + auras + dispel + BM), seeds
    -- range and re-registers private auras -- same path as a real header assignment.
    function mod.XF_Apply()
        if not saved or not saved.profile then return end
        local set = Extras.Settings()
        if not set then return end
        if InCombatLockdown() then
            Extras.applyDirty = true
            return
        end

        local units = Extras.ShouldBeActive() and Extras.ResolveUnits() or {}
        Extras.activeCount = #units
        if #units == 0 then
            if Extras.built then
                for _, btn in ipairs(Extras.buttons) do
                    btn:Hide()
                end
                Extras.container:Hide()
                for i = 1, #Extras.trackers do
                    Extras.trackers[i]:UnregisterAllEvents()
                end
            end
            if Extras.mover then Extras.mover:Hide() end
            wipe(mod._xfUnitToButton)
            -- The boss group may have been chained behind this container;
            -- re-anchor it back onto the raid (no-op when FB is not built).
            FB.Anchor()
            if mod._NotifyTrackerProviders then mod._NotifyTrackerProviders() end
            return
        end

        Extras.EnsureBuilt(#units)
        Extras.Layout()
        FB.Anchor(Extras)
        Extras.container:Show()
        wipe(mod._xfUnitToButton)
        for i = 1, #Extras.buttons do
            local widget = Extras.buttons[i]
            local unitToken = units[i]
            local t = Extras.trackers[i]
            t:UnregisterAllEvents()
            if unitToken then
                -- Class token cache for the power border (mirrors RebuildUnitMap)
                local skinData = GetFFD(widget)
                local _, classToken = UnitClass(unitToken)
                skinData.classToken = classToken
                widget:SetAttribute("unit", unitToken)
                mod._xfUnitToButton[unitToken] = widget
                -- Fail-open backstop for a mid-raid reconnect: the roster can still be
                -- streaming, so UnitName(unit) may be nil at this first paint and the
                -- slot commits a blank name (field report: blank until /reload even
                -- though UNIT_NAME_UPDATE and the roster re-apply are both wired).
                -- Re-arms until the name resolves, bounded, and only repaints while
                -- this slot still holds the same unit. No-op when the name is cached.
                if not UnitName(unitToken) then
                    local tries = 0
                    local function RetryName()
                        if widget:GetAttribute("unit") ~= unitToken then return end
                        if UnitName(unitToken) then
                            UpdateButton(widget)
                            return
                        end
                        tries = tries + 1
                        if tries < 5 then C_Timer.After(2, RetryName) end
                    end
                    C_Timer.After(2, RetryName)
                end
                for _, ev in ipairs(Extras.EVENTS) do
                    t:RegisterUnitEvent(ev, unitToken)
                end
                -- UNIT_FLAGS is opt-in: extra frames mirror the raid combat-icon toggle.
                if saved.profile.showCombatIndicator then t:RegisterUnitEvent("UNIT_FLAGS", unitToken) end
                -- UNIT_LEVEL is opt-in too: only while a view shows the level.
                if mod.RF_TextWanted("level") then t:RegisterUnitEvent("UNIT_LEVEL", unitToken) end
                -- UNIT_TARGET likewise: only while a view's Custom text shows [target].
                if mod.RF_TextWanted("tgt") then t:RegisterUnitEvent("UNIT_TARGET", unitToken) end
                t:RegisterEvent("READY_CHECK_CONFIRM")
                t:RegisterEvent("PLAYER_FLAGS_CHANGED")
                widget:Show()
            else
                widget:Hide()
            end
        end
        -- Re-evaluate the boss group's chain now that this container is shown
        -- and (re)positioned: same-side boss frames hop behind it.
        FB.Anchor()
        -- Extra frames are excluded from _CollectTrackerFrames (duplicates), but
        -- name-scanning trackers do index them, and PLAYER_ROLES_ASSIGNED reshuffles
        -- them with no event those trackers listen for.
        if mod._NotifyTrackerProviders then mod._NotifyTrackerProviders() end
    end

    function mod.XF_IsMoverShown() return Extras.mover and Extras.mover:IsShown() or false end

    function mod.XF_SetMoverShown(show) FB.SetMoverShown(Extras, show, "ERFExtraFramesMover", "Extra Frames") end

    -- Hidden bind target (pure Lua keybinding, no Bindings.xml; same pattern as
    -- the Party Mode toggle key). The options panel binds the saved key to click
    -- this button; the click toggles the hovered raid member in/out of the group.
    local bindBtn = CreateFrame("Button", "ERFExtraFramesBindBtn", UIParent)
    bindBtn:Hide()

    Extras.ToggleHovered = function()
        if not saved or not saved.profile then return end
        if not IsInRaid() then return end
        local set = Extras.Settings()
        if not set then return end
        -- The real raid frame under the mouse, or one of our own duplicates
        -- (pressing the hotkey on a duplicate removes that player too).
        local unitToken
        for u, button in pairs(unitToButton) do
            if button:IsShown() and button:IsMouseOver() then
                unitToken = u
                break
            end
        end
        if not unitToken then
            for _, btn in ipairs(Extras.buttons) do
                if btn:IsShown() and btn:IsMouseOver() then
                    unitToken = btn:GetAttribute("unit")
                    break
                end
            end
        end
        if not unitToken then return end
        local index = tonumber(unitToken:match("^raid(%d+)$"))
        local name = index and GetRaidRosterInfo(index)
        if not name then return end

        local players = set.players or {}
        set.players = players
        for key, val in ipairs(players) do
            if val == name then
                table.remove(players, key)
                mod.XF_Apply()
                return
            end
        end
        -- Already covered by Show Tanks: adding would be an invisible duplicate.
        -- An Exclude-Myself'd player tank is NOT covered, so their manual add
        -- stays legitimate.
        if
            set.showTanks
            and CUI.UnitEffectiveRole(unitToken) == "TANK"
            and not (set.excludeSelfTank and UnitIsUnit(unitToken, "player"))
        then
            return
        end
        if #Extras.ResolveUnits() >= Extras.CAP then return end
        players[#players + 1] = name
        mod.XF_Apply()
    end

    bindBtn:SetScript("OnClick", function() Extras.ToggleHovered() end)

    -- Standing event frame: exists even while inactive so the tanks toggle or a
    -- first hotkey add can activate the feature without a /reload, and so the
    -- saved hotkey is re-bound every login.
    do
        local ev = mod.TakeShell()
        ev:RegisterEvent("PLAYER_LOGIN")
        ev:RegisterEvent("GROUP_ROSTER_UPDATE")
        ev:RegisterEvent("PLAYER_ROLES_ASSIGNED")
        ev:RegisterEvent("PLAYER_REGEN_ENABLED")
        -- No PLAYER_TARGET_CHANGED / RAID_TARGET_UPDATE here: the duplicates ride
        -- the central broadcast closures via ns._xfUnitToButton.
        ev:SetScript("OnEvent", function(_, evt)
            if evt == "PLAYER_LOGIN" then
                local key = CludesUIDB and CludesUIDB.extraFramesKey
                if key then
                    ClearOverrideBindings(bindBtn)
                    SetOverrideBindingClick(bindBtn, true, key, "ERFExtraFramesBindBtn")
                end
                return
            end
            if not saved then return end
            if evt == "PLAYER_REGEN_ENABLED" then
                if Extras.applyDirty then
                    Extras.applyDirty = nil
                    mod.XF_Apply()
                end
                if Extras.anchorDirty then
                    Extras.anchorDirty = nil
                    FB.Anchor(Extras)
                end
            else -- GROUP_ROSTER_UPDATE / PLAYER_ROLES_ASSIGNED
                -- Raid indices and the tank set both shift with the roster
                if Extras.ShouldBeActive() or Extras.built then mod.XF_Apply() end
            end
        end)
        Extras.eventFrame = ev
    end
end -- XF scope block

Inner.broken = false
