if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_OptionsSetup.lua
--
--  SetupOptionsPanel, run one frame after the frames build: publishes the ns
--  fields the options pages read (ns.db, ns.frames, ns.ReloadFrames, ...) and
--  builds the boss frame preview. Published as I.SetupOptionsPanel for
--  CUI_UnitFrames_Lifecycle.lua (EnableBody schedules it). Reads the main file
--  through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local Pix = CludesUI.PP

local Inner = mod._internals
local frameList, ApplyFramePosition, GetFrameDimensions =
    Inner.frames, Inner.ApplyFramePosition, Inner.GetFrameDimensions
local ReloadFrames, ResolveFontPath, ApplyDarkTheme =
    Inner.ReloadFrames, Inner.ResolveFontPath, Inner.ApplyDarkTheme
local ApplyBlizzCastbarState, ApplyUnitFrameCastColor =
    Inner.ApplyBlizzCastbarState, Inner.ApplyUnitFrameCastColor
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end

local function SetupOptionsPanel()
    mod.db = saved
    mod.frames = frameList

    -- Live Enable Boss Frames for the CUI source. The boss frames spawn at login
    -- only, so the enable toggle used to be a silent no-op in the ON->OFF
    -- direction: PromptReloadIfUnspawned only prompts when frames are MISSING,
    -- and nothing hid the live frames -- they kept showing on every boss for the
    -- rest of the session (field report 2026-08-13; Blizzard source toggled live,
    -- hence "only works on Blizzard default"). The unit watch is the show/hide
    -- authority (RegisterUnitWatch at spawn), so toggling it IS the live enable/
    -- disable; frames never spawned this session still fall through to the
    -- reload prompt in the options setter. Watch/Hide writes on these secure
    -- frames are lockdown-blocked: in combat, park a one-shot that re-applies
    -- the CURRENT setting at regen (reads the profile at fire time, so the last
    -- click wins and stacked toggles collapse to one apply).
    function mod.UF_SetBossFramesActive(on)
        if InCombatLockdown() then
            mod.CombatQueue.Defer(
                "BossFramesActive",
                function() mod.UF_SetBossFramesActive(saved.profile.enabledFrames.boss ~= false) end
            )
            return
        end
        for i = 1, 5 do
            local frame = frameList["boss" .. i]
            if frame then
                if on then
                    RegisterUnitWatch(frame)
                else
                    UnregisterUnitWatch(frame)
                    frame:Hide()
                end
            end
        end
    end
    mod.ApplyFramePosition = ApplyFramePosition
    mod.GetFrameDimensions = GetFrameDimensions
    local reloadPending = false
    local reloadThrottle = CreateFrame("Frame")
    reloadThrottle:Hide()
    -- Realise a classPowerStyle that changed through a path which never calls
    -- _toggleClassPower (a Spec Override applying at login, a profile switch, an
    -- import). Gated on an actual change because the toggle is a full teardown
    -- and rebuild; running it every reload would thrash the bar.
    local RealiseClassPowerStyle
    RealiseClassPowerStyle = function()
        if not frameList._toggleClassPower then return end
        local wantCP = saved.profile.player.classPowerStyle or "none"
        -- WoW Forever: compare the style that builds, not the saved one (the
        -- toggle keeps the saved style and builds its effective style).
        local builtCP = wantCP
        if mod.UF_ForeverCPStyle then builtCP = mod.UF_ForeverCPStyle(wantCP) end
        if builtCP == frameList._classPowerBuiltStyle then return end
        -- The toggle reparents Blizzard's class power frame and re-anchors the
        -- health bar. The throttle body keeps running after ReloadFrames()'s
        -- lockdown return (same shape as the UpdateFrameVisibility note in InitializeFrames),
        -- so this needs its own guard plus a regen re-run to re-arm the pass.
        if InCombatLockdown() then
            mod.CombatQueue.Defer("RealiseClassPowerStyle", RealiseClassPowerStyle)
            return
        end
        frameList._toggleClassPower(wantCP)
    end
    -- One reload pass. ReloadFrames returns under combat lockdown right after
    -- its tag-global refresh (every frame write it holds is protected), while
    -- the rest of this body runs as it always did; a pass that lands in combat
    -- therefore asks for a whole new pass at combat end (one per combat: the
    -- queue keys it), instead of dropping the frame work as it used to.
    local function RunReload()
        ReloadFrames()
        if InCombatLockdown() then mod.CombatQueue.Defer("ReloadFrames", mod.ReloadFrames) end
        ApplyBlizzCastbarState()
        -- Hide While Using Gamepad: a profile switch or spec override changes
        -- the saved toggles without calling the options setter.
        mod.UF_ApplyGamepadCastbar()
        -- A reload restyles the boss frames and re-colors their health to the
        -- player's class color (preview rides on unit="player") + re-tags the name.
        -- Re-assert the preview (red color + fake name) so a settings change doesn't
        -- revert it. Secret-safe: no health values are read.
        if mod._bossPreviewActive and mod.SetBossPreview then mod.SetBossPreview(true) end
        -- ReloadFrames rebuilds frames but never touches the top-level wrapper/3D-
        -- portrait alpha, so recompute the out-of-combat fade here. Without this, a
        -- profile/spec swap (or first switch to a 3D portrait, whose PlayerModel is
        -- created at alpha 1) leaves player/target/focus stuck at the old opacity
        -- until the next combat/target/zone event. Safe from the throttle:
        -- UpdateFrameVisibility guards its restricted Show/Hide behind
        -- InCombatLockdown, and SetAlpha is unrestricted.
        if mod.UpdateFrameVisibility then mod.UpdateFrameVisibility() end
        -- The pet's containers are built only once its Buffs or Debuffs is on,
        -- and every path that can turn one on (the options, a profile switch,
        -- a Spec or Conditional Override) lands here: ask for them before the
        -- pass below (the build reloads the pet itself when it finishes).
        mod.UF_EnsurePetAuras(frameList.pet)
        -- 12.1 aura containers reload with every real pass (direct call --
        -- ns.ReloadFrames is just the throttle-arming stub, so wrapping it
        -- from the container file is timing-unreliable).
        if mod.UF_ReloadAllAuraContainers then mod.UF_ReloadAllAuraContainers() end
        -- Class power: _toggleClassPower is the only thing that honours a
        -- classPowerStyle change, and options + the spec watcher are its only
        -- other callers -- styles changed by overrides, profile switch, or
        -- import land here.
        RealiseClassPowerStyle()
        -- Threat watchers and the targeting sounds: a profile switch or spec
        -- override changes the saved toggles without calling their setters.
        mod.SyncPlayerThreat()
        if mod.SyncThreatPct then mod.SyncThreatPct() end
        mod.UF_SyncTargetSounds()
    end
    reloadThrottle:SetScript("OnUpdate", function(self)
        self:Hide()
        reloadPending = false
        RunReload()
    end)
    mod.ReloadFrames = function()
        if not reloadPending then
            reloadPending = true
            reloadThrottle:Show()
        end
    end
    _G._CUUF_ReloadFrames = mod.ReloadFrames

    -- Fake debuff icons for the boss preview. Three square icons anchored where the
    -- real Debuffs frame would live, sized to match the Simple Debuff Display layout
    -- (frame bar height, growing right-to-left off the frame's left edge). Built on
    -- first use per boss frame, refreshed in place on every call, hidden on preview
    -- disable.
    local FAKE_DEBUFF_SPELLS = { 122, 172, 1714 } -- Frost Nova, Corruption, Curse of Tongues
    local FAKE_DEBUFF_STACKS = { [2] = 3 } -- one fake stack (icon 2 only)
    local FAKE_DEBUFF_FRACS = { 0.35, 0.62, 0.88 } -- static fake swipe fraction remaining
    local FAKE_DEBUFF_SECS = { 8, 15, 23 } -- static fake duration-text seconds
    -- Preview-only: a fake aura icon wears the boss aura border settings (the ring
    -- the live buttons' style builds, drawn through the same eight-slice path;
    -- the owned border frame doubles as its texture cache). Blizzard Style keeps
    -- the plain 1 px ring the preview always drew. On ns: this function sits at
    -- the Lua 5.1 local ceiling.
    mod.BossPreviewAuraBorder = function(border, prefs)
        if mod.UF_Blizz and mod.UF_Blizz() then
            if Pix and Pix.CreateBorder then Pix.CreateBorder(border, 0, 0, 0, 1) end
        else
            local size = prefs.auraBorderSize or 1
            local texture = prefs.auraBorderTexture or "solid"
            if mod.UF_BossAuraBorderAboveEffects(prefs) then
                border:SetFrameLevel(border:GetParent():GetFrameLevel() + 20)
            end
            CludesUI.ApplySecretSafeBorderStyle(
                border,
                border,
                size,
                prefs.auraBorderR or 0,
                prefs.auraBorderG or 0,
                prefs.auraBorderB or 0,
                prefs.auraBorderA or 1,
                texture,
                prefs.auraBorderTextureOffset,
                prefs.auraBorderTextureOffsetY,
                prefs.auraBorderTextureShiftX,
                prefs.auraBorderTextureShiftY,
                "unitframes",
                size,
                nil,
                CludesUI.BorderPx(prefs.auraBorderSizePx, size, texture)
            )
        end
        -- The border frame is reused across refreshes and its level is set on
        -- each one: keep its solid strips one level over it, as when built.
        local strips = Pix.GetBorders(border)
        if strips then strips:SetFrameLevel(border:GetFrameLevel() + 1) end
    end
    local function AttachFakeDebuffs(widget)
        -- Hide the holder until it is laid out again below, so size, anchor and
        -- style follow the current settings on every call.
        local holderFrame = widget._previewDebuffs
        if holderFrame then holderFrame:Hide() end
        -- Suppress the real (player-unit) debuffs while the fake overlay is up so
        -- the preview shows exactly the fake set. Restored by ReloadFrames when
        -- the preview is disabled.
        if mod.UF_HideAuraContainers then mod.UF_HideAuraContainers(widget) end
        local prefs = saved.profile.boss or {}
        local simpleMode = mod.GetBossSimpleDebuffMode(prefs)
        local simple = simpleMode ~= "none"
        -- No debuffs shown at all (Simple Debuff Display None + Debuffs Location
        -- None): the holder stays hidden, so bail without drawing any fake
        -- debuffs (mirrors AttachFakeBuffs' none guard).
        if not simple and (prefs.debuffAnchor or "bottomleft") == "none" then return end
        local dOffX = prefs.debuffOffsetX or 0
        local dOffY = prefs.debuffOffsetY or 0
        -- Simple mode uses its own X/Y offsets (falling back to the regular
        -- debuff offsets for existing users) so the preview matches live.
        if simple then
            dOffX, dOffY = mod.GetBossSimpleDebuffOffset(prefs)
        end
        local powerPos = prefs.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (prefs.powerHeight or 0) or 0
        local iconSize
        if simple then
            -- Pixel-snap so the preview icon matches the frame's snapped height
            -- exactly (== frame:GetHeight()), same as the live boss debuffs.
            iconSize = Pix.Scale((prefs.healthHeight or 34) + powerH)
        else
            iconSize = prefs.debuffSize or 22
        end
        local total = #FAKE_DEBUFF_SPELLS
        local gap = 1
        -- Inter-icon spacing from the configured slider (physical pixels). `gap`
        -- stays at 1 for the holder-to-frame edge offset (matches the runtime).
        local iconGap = Pix.FromPixels(mod.GetBossDebuffSpacing(prefs, simple))
        if not holderFrame then
            holderFrame = CreateFrame("Frame", nil, widget)
            holderFrame._icons = {}
            widget._previewDebuffs = holderFrame
        end
        holderFrame:SetSize(iconSize * total + iconGap * (total - 1), iconSize)
        -- Above the unified border so it sits BEHIND the preview debuffs, matching
        -- the live boss aura layering. The border FRAME is frame+10 but its solid
        -- PP border textures live on a sub-container at frame+11, so clear that
        -- (frame+13 also clears the class-icon holder at frame+12).
        holderFrame:SetFrameLevel(widget:GetFrameLevel() + 13)
        holderFrame:ClearAllPoints()
        -- The boss cast bar lives as a sibling parented to the frame but
        -- anchored BELOW frame bottom, so frame:GetHeight() excludes it.
        -- Mirror the live runtime behavior where bottom-anchored debuffs
        -- push down by the cast bar height to avoid overlap.
        local castBg = widget.Castbar and widget.Castbar:GetParent()
        local castbarH = (prefs.showCastbar ~= false and castBg) and castBg:GetHeight() or 0
        if simple then
            -- Simple mode: align debuff stack with the health bar top so
            -- they never encroach on the cast bar area. Left grows off the
            -- frame's left edge; Right grows off the right edge.
            if simpleMode == "right" then
                holderFrame:SetPoint("TOPLEFT", widget, "TOPRIGHT", 1 + dOffX, dOffY)
            else
                holderFrame:SetPoint("TOPRIGHT", widget, "TOPLEFT", -1 + dOffX, dOffY)
            end
        else
            local dAnc = prefs.debuffAnchor or "bottomleft"
            if dAnc == "topleft" then
                holderFrame:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0 + dOffX, gap + dOffY)
            elseif dAnc == "topright" then
                holderFrame:SetPoint("BOTTOMRIGHT", widget, "TOPRIGHT", 0 + dOffX, gap + dOffY)
            elseif dAnc == "bottomleft" then
                holderFrame:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0 + dOffX, -gap - castbarH + dOffY)
            elseif dAnc == "bottomright" then
                holderFrame:SetPoint("TOPRIGHT", widget, "BOTTOMRIGHT", 0 + dOffX, -gap - castbarH + dOffY)
            elseif dAnc == "right" then
                holderFrame:SetPoint("LEFT", widget, "RIGHT", gap + dOffX, 0 + dOffY)
            else -- "left" or fallback
                holderFrame:SetPoint("RIGHT", widget, "LEFT", -gap + dOffX, 0 + dOffY)
            end
        end
        -- Cooldown-text + stack settings, mode-aware so the preview mirrors the
        -- live boss aura buttons (simple keys in Simple Debuff Display, regular
        -- debuff keys otherwise).
        local showCD, cdSize, cdOffX, cdOffY
        if simple then
            showCD = prefs.simpleDebuffShowCooldownText
            cdSize = prefs.simpleDebuffCooldownTextSize or 14
            cdOffX = prefs.simpleDebuffCooldownTextOffsetX or 0
            cdOffY = prefs.simpleDebuffCooldownTextOffsetY or 0
        else
            showCD = prefs.debuffShowCooldownText
            cdSize = prefs.debuffCooldownTextSize or 10
            cdOffX = prefs.debuffCooldownTextOffsetX or 0
            cdOffY = prefs.debuffCooldownTextOffsetY or 0
        end
        local stackSize = prefs.debuffStackTextSize or 14
        local stackOffX = prefs.debuffStackTextOffsetX or 0
        local stackOffY = prefs.debuffStackTextOffsetY or 0
        local stackPos = prefs.debuffStackTextPosition
        local cdTextColor = prefs.debuffCooldownTextColor or { r = 1, g = 1, b = 1 }
        local stackTextColor = prefs.debuffStackTextColor or { r = 1, g = 1, b = 1 }
        local fontFile = (CludesUI.GetFontPath("unitFrames")) or "Fonts\\FRIZQT__.TTF"
        local nowTime = GetTime()
        local icons = holderFrame._icons
        for position, spellId in ipairs(FAKE_DEBUFF_SPELLS) do
            local iconFrame = icons[position]
            if not iconFrame then
                iconFrame = CreateFrame("Frame", nil, holderFrame)
                local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                iconFrame._icon = iconTex
                -- Static fake cooldown swipe: a huge duration parked at a fixed fraction so
                -- the wedge never visibly moves. Native countdown numbers stay hidden; the
                -- duration text below is a manual static FontString instead.
                local cd = CreateFrame("Cooldown", nil, iconFrame, "CooldownFrameTemplate")
                cd:SetAllPoints(iconFrame)
                cd:SetDrawEdge(false)
                cd:SetDrawBling(false)
                cd:SetReverse(false)
                cd:SetDrawSwipe(true)
                cd:SetSwipeColor(0, 0, 0, 0.6)
                cd:SetHideCountdownNumbers(true)
                iconFrame._cd = cd
                -- Text host above the swipe AND the border container so the
                -- duration/stack text renders over the icon border, not under it.
                local textHost = CreateFrame("Frame", nil, iconFrame)
                textHost:SetAllPoints(iconFrame)
                iconFrame._textHost = textHost
                local durText = textHost:CreateFontString(nil, "OVERLAY")
                durText:SetDrawLayer("OVERLAY", 7)
                iconFrame._durText = durText
                -- Stack text on a single icon only (looks natural; most debuffs are
                -- unstacked). Driven by the Stack Size / Stack X / Stack Y controls.
                if FAKE_DEBUFF_STACKS[position] then
                    local stack = textHost:CreateFontString(nil, "OVERLAY")
                    stack:SetDrawLayer("OVERLAY", 7)
                    iconFrame._stack = stack
                end
                -- Border just above the icon; its PP container renders at border+1
                -- (iconFrame+2), below the swipe and text host so both stay on top.
                local border = CreateFrame("Frame", nil, iconFrame)
                border:SetAllPoints(iconTex)
                iconFrame._border = border
                icons[position] = iconFrame
            end
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:ClearAllPoints()
            if simpleMode == "right" then
                iconFrame:SetPoint("LEFT", holderFrame, "LEFT", (position - 1) * (iconSize + iconGap), 0)
            else
                iconFrame:SetPoint("RIGHT", holderFrame, "RIGHT", -(position - 1) * (iconSize + iconGap), 0)
            end
            iconFrame:SetFrameLevel(holderFrame:GetFrameLevel())
            local iconTex = iconFrame._icon
            local texture = GetSpellTexture and GetSpellTexture(spellId)
                or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId))
            iconTex:SetTexture(texture)
            local z = prefs.debuffIconZoom or 0.07
            iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
            -- Swipe sits above the border (border at +1, PP container at +2) so
            -- the layering matches the live boss aura buttons.
            local cd = iconFrame._cd
            cd:SetFrameLevel(iconFrame:GetFrameLevel() + 3)
            local frac = FAKE_DEBUFF_FRACS[position] or 0.6
            cd:Show()
            cd:SetCooldown(nowTime - 3600 * (1 - frac), 3600)
            iconFrame._textHost:SetFrameLevel(
                iconFrame:GetFrameLevel() + (mod.UF_BossAuraBorderAboveEffects(prefs) and 25 or 4)
            )
            local durText = iconFrame._durText
            CludesUI.ApplyIconTextFont(durText, fontFile, cdSize, "unitFrames")
            durText:ClearAllPoints()
            durText:SetPoint("CENTER", iconFrame, "CENTER", cdOffX, cdOffY)
            durText:SetTextColor(cdTextColor.r, cdTextColor.g, cdTextColor.b)
            durText:SetText(FAKE_DEBUFF_SECS[position] or 10)
            if showCD then
                durText:Show()
            else
                durText:Hide()
            end
            local stack = iconFrame._stack
            if stack then
                CludesUI.ApplyIconTextFont(stack, fontFile, stackSize, "unitFrames")
                mod.ApplyStackAnchor(stack, iconFrame, stackPos, stackOffX, stackOffY)
                stack:SetTextColor(stackTextColor.r, stackTextColor.g, stackTextColor.b)
                stack:SetText(FAKE_DEBUFF_STACKS[position])
            end
            local border = iconFrame._border
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            mod.BossPreviewAuraBorder(border, prefs)
        end
        holderFrame:Show()
    end
    local function DetachFakeDebuffs(widget)
        if widget._previewDebuffs then widget._previewDebuffs:Hide() end
    end

    -- Fake buff icons for the boss preview. Two square icons anchored where the
    -- real Buffs frame would live, sized to the buff size. Built on first use per
    -- boss frame, refreshed in place on every call, hidden on preview disable.
    -- Capped at 2 regardless of Max Count.
    local FAKE_BUFF_SPELLS = { 21562, 1459 } -- Power Word: Fortitude, Arcane Intellect
    local function AttachFakeBuffs(widget)
        local holderFrame = widget._previewBuffs
        if holderFrame then holderFrame:Hide() end
        -- Suppress the real (player-unit) buffs while preview is up. Restored by
        -- ReloadFrames when the preview is disabled.
        if mod.UF_HideAuraContainers then mod.UF_HideAuraContainers(widget) end
        local prefs = saved.profile.boss or {}
        local simpleMode = mod.GetBossSimpleBuffMode(prefs)
        local simple = simpleMode ~= "none"
        -- Simple Buff Display overrides Buffs Location, so only bail on the
        -- location/visibility guards when simple mode is off.
        if not simple and (prefs.showBuffs == false or (prefs.buffAnchor or "topleft") == "none") then
            return
        end
        local anchor = prefs.buffAnchor or "topleft"
        local bOffX = prefs.buffOffsetX or 0
        local bOffY = prefs.buffOffsetY or 0
        -- Simple mode uses its own X/Y offsets (falling back to the regular buff
        -- offsets for existing users) so the preview matches live.
        if simple then
            bOffX, bOffY = mod.GetBossSimpleBuffOffset(prefs)
        end
        local powerPos = prefs.powerPosition or "below"
        local powerIsAtt = (powerPos == "below" or powerPos == "above")
        local powerH = powerIsAtt and (prefs.powerHeight or 0) or 0
        local iconSize
        if simple then
            -- Pixel-snap so the preview icon matches the frame's snapped height
            -- exactly (== frame:GetHeight()), same as the live boss buffs.
            iconSize = Pix.Scale((prefs.healthHeight or 34) + powerH)
        else
            iconSize = prefs.buffSize or 22
        end
        local total = #FAKE_BUFF_SPELLS
        local gap = 1
        -- Inter-icon spacing from the configured slider (physical pixels). `gap`
        -- stays at 1 for the holder-to-frame edge offset (matches the runtime).
        local iconGap = Pix.FromPixels(mod.GetBossBuffSpacing(prefs, simple))
        if not holderFrame then
            holderFrame = CreateFrame("Frame", nil, widget)
            holderFrame._icons = {}
            widget._previewBuffs = holderFrame
        end
        holderFrame:SetSize(iconSize * total + iconGap * (total - 1), iconSize)
        -- Above the unified border so it sits BEHIND the preview buffs, matching
        -- the live boss aura layering. The border FRAME is frame+10 but its solid
        -- PP border textures live on a sub-container at frame+11, so clear that
        -- (frame+13 also clears the class-icon holder at frame+12).
        holderFrame:SetFrameLevel(widget:GetFrameLevel() + 13)
        holderFrame:ClearAllPoints()
        local castBg = widget.Castbar and widget.Castbar:GetParent()
        local castbarH = (prefs.showCastbar ~= false and castBg) and castBg:GetHeight() or 0
        if simple then
            -- Align the column with the health bar top, side-based (matches the
            -- live runtime + Simple Debuff Display).
            if simpleMode == "right" then
                holderFrame:SetPoint("TOPLEFT", widget, "TOPRIGHT", 1 + bOffX, bOffY)
            else
                holderFrame:SetPoint("TOPRIGHT", widget, "TOPLEFT", -1 + bOffX, bOffY)
            end
        elseif anchor == "topleft" then
            holderFrame:SetPoint("BOTTOMLEFT", widget, "TOPLEFT", 0 + bOffX, gap + bOffY)
        elseif anchor == "topright" then
            holderFrame:SetPoint("BOTTOMRIGHT", widget, "TOPRIGHT", 0 + bOffX, gap + bOffY)
        elseif anchor == "bottomleft" then
            holderFrame:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0 + bOffX, -gap - castbarH + bOffY)
        elseif anchor == "bottomright" then
            holderFrame:SetPoint("TOPRIGHT", widget, "BOTTOMRIGHT", 0 + bOffX, -gap - castbarH + bOffY)
        elseif anchor == "right" then
            holderFrame:SetPoint("LEFT", widget, "RIGHT", gap + bOffX, 0 + bOffY)
        else -- "left" or fallback
            holderFrame:SetPoint("RIGHT", widget, "LEFT", -gap + bOffX, 0 + bOffY)
        end
        local icons = holderFrame._icons
        for position, spellId in ipairs(FAKE_BUFF_SPELLS) do
            local iconFrame = icons[position]
            if not iconFrame then
                iconFrame = CreateFrame("Frame", nil, holderFrame)
                local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
                iconTex:SetAllPoints()
                iconFrame._icon = iconTex
                local border = CreateFrame("Frame", nil, iconFrame)
                border:SetAllPoints(iconTex)
                iconFrame._border = border
                icons[position] = iconFrame
            end
            iconFrame:SetSize(iconSize, iconSize)
            iconFrame:ClearAllPoints()
            if simple and simpleMode == "left" then
                -- Left mode grows leftward from the right edge of the holder.
                iconFrame:SetPoint("RIGHT", holderFrame, "RIGHT", -(position - 1) * (iconSize + iconGap), 0)
            else
                iconFrame:SetPoint("LEFT", holderFrame, "LEFT", (position - 1) * (iconSize + iconGap), 0)
            end
            iconFrame:SetFrameLevel(holderFrame:GetFrameLevel())
            local iconTex = iconFrame._icon
            local texture = GetSpellTexture and GetSpellTexture(spellId)
                or (C_Spell and C_Spell.GetSpellTexture and C_Spell.GetSpellTexture(spellId))
            iconTex:SetTexture(texture)
            local z = prefs.buffIconZoom or 0.07
            iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
            local border = iconFrame._border
            border:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
            mod.BossPreviewAuraBorder(border, prefs)
        end
        holderFrame:Show()
    end
    local function DetachFakeBuffs(widget)
        if widget._previewBuffs then widget._previewBuffs:Hide() end
    end

    -- Fake static cast bar for the boss preview (boss2 only). This drives the
    -- REAL cast bar so it is 100% identical to a live cast: it disables the oUF
    -- Castbar element (so oUF never resets our frozen state), then shows the bar
    -- with a fixed mid-cast fill + spell name / timer / icon and the active-cast
    -- tint -- the same state OnCastbarCastActive produces during a real cast.
    local FAKE_CAST_SPELL_NAME = "Shadow Bolt"
    local FAKE_CAST_SPELL_ICON = 136197
    local function DetachFakeCastBar(widget)
        if not widget._fakeCastActive then return end
        widget._fakeCastActive = nil
        local castBar = widget.Castbar
        local castbarBg = castBar and castBar:GetParent()
        if castBar then
            if castBar.castTintLayer then
                castBar.castTintLayer:SetAlpha(0)
                castBar._castTintOn = nil
            end
            castBar:Hide()
        end
        if castbarBg then castbarBg:Hide() end
        -- The real Castbar element is re-enabled by ReloadFrames when the preview
        -- is turned off, so no manual re-enable is needed here.
    end
    local function AttachFakeCastBar(widget)
        local castBar = widget.Castbar
        local castbarBg = castBar and castBar:GetParent()
        if not castBar or not castbarBg then return end
        local prefs = saved.profile.boss or {}
        if prefs.showCastbar == false then
            castbarBg:Hide()
            return
        end
        -- Suppress the real Castbar element so oUF can't reset the frozen cast.
        if widget:IsElementEnabled("Castbar") then widget:DisableElement("Castbar") end
        castBar._eufSettings = prefs
        -- Frozen mid-cast fill (respects the configured reverse-fill direction).
        castBar:SetMinMaxValues(0, 1)
        castBar:SetValue(0.65)
        if castBar.Text then castBar.Text:SetText(FAKE_CAST_SPELL_NAME) end
        if castBar.Time then
            if prefs.showCastDuration == false then
                castBar.Time:SetText("")
                castBar.Time:Hide()
            else
                castBar.Time:Show()
                castBar.Time:SetText("1.8")
            end
        end
        if castBar.Icon then
            castBar.Icon:SetTexture(FAKE_CAST_SPELL_ICON)
            -- SetTexture resets the crop; re-apply the cast icon's fixed zoom.
            castBar.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        -- Active-cast tint -- same path a real cast uses.
        if castBar.castTintLayer then
            castBar.castTintLayer:SetAlpha(castBar._fillOp or 1)
            castBar._castTintOn = true
            ApplyUnitFrameCastColor(castBar)
        end
        castbarBg:Show()
        castBar:Show()
        if castBar._iconFrame then
            if prefs.showCastIcon == false then
                castBar._iconFrame:Hide()
            else
                castBar._iconFrame:Show()
            end
        end
        if castBar._layoutTextZones then castBar:_layoutTextZones() end
        widget._fakeCastActive = true
    end

    -- Refresh the in-game boss preview's fake auras when boss settings that affect them
    -- (simpleDebuffs, debuffAnchor, debuffSize, buffAnchor, etc.) change.
    mod.RefreshBossPreviewDebuffs = function()
        if not mod._bossPreviewActive then return end
        for i = 1, 3 do
            local frame = frameList["boss" .. i]
            if frame then
                AttachFakeDebuffs(frame)
                AttachFakeBuffs(frame)
                -- Only the 2nd boss frame shows a sample cast bar.
                if i == 2 then AttachFakeCastBar(frame) end
            end
        end
    end

    -- Apply / clear a hostile-red health bar override on a boss frame while
    -- preview is active. Real boss frames never class-color (no player class),
    -- so piggybacking on unit="player" would otherwise paint the bar in the
    -- user's class color -- wrong for a preview.
    local PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B = 0.8, 0.2, 0.2

    -- Fake boss names for the preview. Generated once per activation (stable
    -- across reloads), regenerated on a fresh activation. Health is intentionally
    -- NOT faked: the health max is a secret value in Midnight and cannot be read
    -- or compared, so the bar keeps the player's real (filled) health.
    local PREVIEW_BOSS_NAMES = {
        "The Lich King",
        "Ragnaros",
        "Kel'Thuzad",
        "Archimonde",
        "Kil'jaeden",
        "Deathwing",
        "Yogg-Saron",
        "C'Thun",
        "Cenarius",
        "Varimathras",
    }
    local function GenBossPreviewNames()
        local pool = {}
        for i = 1, #PREVIEW_BOSS_NAMES do
            pool[i] = PREVIEW_BOSS_NAMES[i]
        end
        for i = #pool, 2, -1 do
            local jdx = math.random(i)
            pool[i], pool[jdx] = pool[jdx], pool[i]
        end
        return { pool[1], pool[2], pool[3] }
    end

    -- Override the name fontstring with a fake boss name. Its text zone is
    -- parked so the engine's text painter stops overwriting it; SetText with a
    -- literal string is secret-safe. Restored on clear.
    local function BossPreviewNameFS(frame)
        local cfg = saved.profile.boss
        local lc = (cfg and cfg.leftTextContent) or "name"
        local rc = (cfg and cfg.rightTextContent) or "perhp"
        local cc = (cfg and cfg.centerTextContent) or "none"
        if lc == "name" then return frame.LeftText end
        if rc == "name" then return frame.RightText end
        if cc == "name" then return frame.CenterText end
        return nil
    end
    local function ApplyBossPreviewName(frame, name)
        local fontStr = BossPreviewNameFS(frame)
        if not fontStr then return end
        frame._previewNameFS = fontStr
        local zones = frame._cuiTextZones
        if zones and not fontStr._previewSavedZone then
            for i = #zones, 1, -1 do
                if zones[i].fs == fontStr then
                    fontStr._previewSavedZone = table.remove(zones, i)
                    break
                end
            end
        end
        fontStr:SetText(name)
    end
    local function ClearBossPreviewName(frame)
        local fontStr = frame._previewNameFS
        if not fontStr then return end
        if fontStr._previewSavedZone then
            local zones = frame._cuiTextZones
            if not zones then
                zones = {}
                frame._cuiTextZones = zones
            end
            zones[#zones + 1] = fontStr._previewSavedZone
            fontStr._previewSavedZone = nil
        end
        frame._previewNameFS = nil
        if mod.UF_PaintText then mod.UF_PaintText(frame, frame._cuiUnit) end
    end

    local function ApplyBossPreviewColor(frame)
        local hgt = frame.Health
        if not hgt then return end
        frame._previewColorSaved = frame._previewColorSaved
            or {
                colorClass = hgt.colorClass,
                colorReaction = hgt.colorReaction,
                colorTapped = hgt.colorTapped,
                colorDisconnected = hgt.colorDisconnected,
            }
        -- Color the fake boss frames exactly as a real boss frame would: Dark Mode
        -- dark fill/bg, or a Custom Colored Fill, via ApplyDarkTheme (both leave
        -- colorClass off). The ONE exception: where a real frame would show the live
        -- unit's class/reaction color (ApplyDarkTheme leaves colorClass ON), our fake
        -- unit is the player with no boss classification -- substitute the red
        -- preview color instead of the player's class color.
        ApplyDarkTheme(hgt)
        if hgt.colorClass then
            hgt.colorClass = false
            hgt.colorReaction = false
            hgt.colorTapped = false
            hgt.colorDisconnected = false
            hgt:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B)
            -- oUF's own update may re-color on the next tick; this PostUpdate keeps
            -- the override sticky for the duration of the preview.
            hgt.PostUpdateColor = function(self)
                self:SetStatusBarColor(PREVIEW_HEALTH_RED_R, PREVIEW_HEALTH_RED_G, PREVIEW_HEALTH_RED_B)
            end
        end
    end
    local function ClearBossPreviewColor(frame)
        local hgt = frame.Health
        if not hgt then return end
        local cfg = frame._previewColorSaved
        if cfg then
            hgt.colorClass = cfg.colorClass
            hgt.colorReaction = cfg.colorReaction
            hgt.colorTapped = cfg.colorTapped
            hgt.colorDisconnected = cfg.colorDisconnected
            frame._previewColorSaved = nil
        end
        hgt.PostUpdateColor = nil
    end

    -- Re-apply the boss preview colors after a Dark Mode change: the dark refresher
    -- repaints every frame via ApplyDarkTheme, which would drop our red class-color
    -- substitute. Called from the dark-mode refresher while the preview is active.
    mod._ReapplyBossPreviewColor = function()
        for i = 1, 3 do
            local frame = frameList["boss" .. i]
            if frame then ApplyBossPreviewColor(frame) end
        end
    end

    -- Boss preview: force boss1/2/3 to render with the player's unit data so
    -- the user can see the boss frame styling live in-game without a real
    -- encounter. Gated out of combat to avoid taint; caller is responsible
    -- for auto-clearing on CUI options window close.
    mod.SetBossPreview = function(enabled)
        if InCombatLockdown() then return false end
        mod._bossPreviewActive = enabled and true or false
        if enabled and not mod._bossPreviewNames then mod._bossPreviewNames = GenBossPreviewNames() end
        for i = 1, 3 do
            local frame = frameList["boss" .. i]
            if frame then
                if enabled then
                    frame:SetAttribute("unit", "player")
                    frame:Show()
                    ApplyBossPreviewColor(frame)
                    if frame.UpdateAllElements then frame:UpdateAllElements("BossPreview") end
                    -- After UpdateAllElements re-tags the name, override it with a fake boss name.
                    ApplyBossPreviewName(
                        frame,
                        (mod._bossPreviewNames and mod._bossPreviewNames[i])
                            or PREVIEW_BOSS_NAMES[i]
                            or "Boss"
                    )
                    AttachFakeDebuffs(frame)
                    AttachFakeBuffs(frame)
                    -- Only the 2nd boss frame shows a sample cast bar.
                    if i == 2 then AttachFakeCastBar(frame) end
                else
                    ClearBossPreviewColor(frame)
                    ClearBossPreviewName(frame)
                    frame:SetAttribute("unit", "boss" .. i)
                    if not UnitExists("boss" .. i) then frame:Hide() end
                    if frame.UpdateAllElements then frame:UpdateAllElements("BossPreview") end
                    DetachFakeDebuffs(frame)
                    DetachFakeBuffs(frame)
                    DetachFakeCastBar(frame)
                end
            end
        end
        if not enabled then
            mod._bossPreviewNames = nil
            -- Restore the real Buffs/Debuffs elements (and their anchors/counts)
            -- that the fake overlay disabled while preview was active.
            if mod.ReloadFrames then mod.ReloadFrames() end
        end
        return true
    end
    mod.ResolveFontPath = ResolveFontPath

    -- Trigger the CludesUI options module registration now that ns.db is ready
    if mod._InitCUIModule then mod._InitCUIModule() end

    -- Player Aura Bars build here, the first point ns.db is known to exist,
    -- in a tick of their own: the container build is insecure work whose
    -- cost scales with the bar count, so it keeps its own watchdog budget
    -- instead of riding this execution (login budget split rule).
    if mod.PAB_CreateBars then C_Timer.After(0, mod.PAB_CreateBars) end
end

Inner.SetupOptionsPanel = SetupOptionsPanel
