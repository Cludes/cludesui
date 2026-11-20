if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Unlock.lua
--
--  Unit frame movers for Unlock Mode. RegisterUFUnlockElements is published
--  as I.RegisterUFUnlockElements for CUI_UnitFrames_Lifecycle.lua (EnableBody
--  calls it). db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local Pix = CludesUI.PP

local Inner = mod._internals
local frameList, GetSettingsForUnit, GetFrameDimensions =
    Inner.frames, Inner.GetSettingsForUnit, Inner.GetFrameDimensions
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-------------------------------------------------------------------------------
--  Register unit frame elements with Unlock Mode. Called synchronously from
--  OnEnable (right after InitializeFrames) so registration lands inside the
--  PLAYER_LOGIN pre-lockdown window on a combat reload -- timers never fire
--  during the loading screen, so a deferred registration would land after
--  combat lockdown re-engaged, leaving anchored unit frames unpositionable
--  until combat dropped.
-------------------------------------------------------------------------------
local function RegisterUFUnlockElements()
    if CludesUI and CludesUI.RegisterUnlockElements then
        local MK = CludesUI.MakeUnlockElement
        local UNIT_LABELS = {
            player = "Player",
            target = "Target",
            focus = "Focus",
            pet = "Pet",
            targettarget = "Target of Target",
            focustarget = "Focus Target",
            boss = "Boss Frames",
            classPower = "Class Resource",
            playerCastbar = "Player Frame Mini Cast Bar",
            targetCastbar = "Target Cast Bar",
            focusCastbar = "Focus Cast Bar",
            petCastbar = "Pet Cast Bar",
        }
        local elements = {}
        local orderBase = 100

        local function Rebuild()
            mod.ReloadFrames()
        end

        -- Which frame's Visibility governs each mover (the minis follow their
        -- parent, and so does a class resource bar unlocked from the player frame).
        local MOVER_VIS_OF = {
            pet = "player",
            targettarget = "target",
            focustarget = "focus",
            classPower = "player",
        }
        local function MakeUFElement(key, sequence)
            return MK({
                key = key,
                label = UNIT_LABELS[key] or key,
                group = "Unit Frames",
                order = orderBase + sequence,
                -- Blizzard Style frames are the stock size: no resize handles or
                -- Width/Height fields (Frame Scale in the options instead).
                noResize = (mod.UF_Blizz() and key ~= "classPower" and not key:find("Castbar", 1, true))
                    or nil,
                -- Only the look fixes the size: size matches to and from the
                -- frame stay stored for the CludesUI look (the cast bars keep
                -- following the visible art meanwhile), and spec layouts never
                -- bank the look's size as the frame's own.
                sizeFixedByLook = (mod.UF_Blizz() and key ~= "classPower") or nil,
                -- Visibility "never" keeps the frame built but never on screen, so
                -- there is nothing to drag. Re-read on each unlock-mode open, so
                -- lifting it (a spec override, the dropdown) needs no /reload. The
                -- minis and an unlocked class resource bar have no Visibility of
                -- their own and ride the frame they follow; Always Show Pet opts out.
                isHidden = function()
                    if key == "pet" and saved.profile.pet and saved.profile.pet.alwaysShow then
                        return false
                    end
                    return mod.VisEffective(saved.profile[MOVER_VIS_OF[key] or key]) == "never"
                end,
                getFrame = function(key)
                    if key == "boss" then
                        return frameList["boss1"]
                    end
                    if key == "classPower" then
                        return frameList._classPowerBar
                    end
                    return frameList[key]
                end,
                getSize = function(key)
                    if key == "classPower" then
                        if frameList._classPowerBar then
                            local wid = frameList._classPowerBar:GetWidth()
                            local hgt = frameList._classPowerBar:GetHeight()
                            if wid < 10 then
                                wid = 120
                            end
                            if hgt < 5 then
                                hgt = 14
                            end
                            return wid, hgt
                        end
                        return 120, 14
                    end
                    local wid, hgt = GetFrameDimensions((key == "boss") and "boss1" or key)
                    -- Blizzard Style: sizes (and so size matches) are the
                    -- visible art, not the stock box's transparent padding.
                    if mod.UF_Blizz() then
                        local l, region, t, b = mod.UF_BlizzVis((key == "boss") and frameList.boss1 or frameList[key])
                        if l then
                            return wid - l - region, hgt - t - b
                        end
                    end
                    return wid, hgt
                end,
                -- The size the unit's own settings give (the CludesUI look),
                -- for code that must never take the style's stock size for it.
                getSettingSize = function(key)
                    if key == "classPower" then
                        return nil
                    end
                    return GetFrameDimensions((key == "boss") and "boss1" or key, true)
                end,
                -- Blizzard Style: the mover outlines the visible art.
                getInsets = function(key)
                    if not mod.UF_Blizz() then
                        return nil
                    end
                    return mod.UF_BlizzVis((key == "boss") and frameList.boss1 or frameList[key])
                end,
                -- Size matching: what a textured border draws outside the frame
                -- (nil for a solid border, the stock looks, class resource, boss).
                getMatchPad = mod.UF_FrameBorderPad,
                -- Extra height the unlock overlay should extend BELOW the frame.
                -- Boss frames have a castbar anchored under the frame (not a
                -- separate movable element like the player/target cast bars), so
                -- the overlay grows down to wrap it. Other units return 0.
                getBottomExtra = function(key)
                    if key ~= "boss" then
                        return 0
                    end
                    local b = saved.profile.boss
                    if b and b.showCastbar ~= false then
                        return b.castbarHeight or 14
                    end
                    return 0
                end,
                -- Blizzard Style: stock frame sizes, so new width/height matches are refused
                -- and unlock resizes never write frameWidth/healthHeight into the CUI-look settings.
                matchUnavailable = function()
                    if mod.UF_Blizz() then
                        return CludesUI.L("Size matching is unavailable with Blizzard Style Unit Frames.")
                    end
                end,
                setWidth = function(key, wid)
                    if key == "classPower" then
                        return
                    end
                    if mod.UF_Blizz() then
                        return
                    end
                    if
                        not CludesUI._unlockActive
                        and not CludesUI._propagatingMatch
                        and not CludesUI._unlockLayerApplying
                    then
                        Rebuild()
                        return
                    end
                    local unitToken = (key == "boss") and "boss1" or key
                    local s = GetSettingsForUnit(unitToken)
                    if not s then
                        return
                    end
                    local oldW = s.frameWidth
                    -- The pet, ToT and FoT frames always attach their portrait.
                    local miniUnit = unitToken == "pet"
                        or unitToken == "targettarget"
                        or unitToken == "focustarget"
                    local wPStyle = s.portraitStyle or saved.profile.portraitStyle or "attached"
                    if miniUnit and wPStyle == "detached" then
                        wPStyle = "attached"
                    end
                    local showPortrait = wPStyle ~= "none" and s.showPortrait ~= false
                    local isAttached = wPStyle == "attached"
                    if showPortrait and isAttached then
                        -- The portrait's width, as GetFrameDimensions adds it:
                        -- the one subtraction that gives a reported size back.
                        local adjPH
                        local powerPos = s.powerPosition or "below"
                        local powerIsAtt = (powerPos == "below" or powerPos == "above")
                        if miniUnit then
                            -- A mini portrait squares off the bar stack, which
                            -- only a WoW Forever pet's attached power bar grows
                            -- (StyleSimpleFrame); Size does not touch it.
                            local petPowerH = (unitToken == "pet" and mod.UF_PetHasPower and powerIsAtt)
                                    and (s.powerHeight or 6)
                                or 0
                            adjPH = s.healthHeight + petPowerH
                        else
                            local pSizeAdj = s.portraitSize or 0
                            local ptH = s.healthHeight + (powerIsAtt and (s.powerHeight or 6) or 0)
                            adjPH = ptH + pSizeAdj
                            if adjPH < 8 then
                                adjPH = 8
                            end
                        end
                        s.frameWidth = math.max(Pix.Snap(wid - adjPH), s.healthVerticalFill and 20 or 50)
                    else
                        -- Vertical Fill bars are tall and slim (the options' Bar Width goes to 20).
                        s.frameWidth = math.max(Pix.Snap(wid), s.healthVerticalFill and 20 or 50)
                    end
                    -- A size match re-applied at the width the frame already has
                    -- (the settle pass re-runs every match after any anchored
                    -- element resizes) leaves nothing to rebuild.
                    if CludesUI._propagatingMatch and s.frameWidth == oldW then
                        return
                    end
                    Rebuild()
                end,
                setHeight = function(key, hgt)
                    if key == "classPower" then
                        return
                    end
                    if mod.UF_Blizz() then
                        return
                    end
                    if
                        not CludesUI._unlockActive
                        and not CludesUI._propagatingMatch
                        and not CludesUI._unlockLayerApplying
                    then
                        Rebuild()
                        return
                    end
                    local unitToken = (key == "boss") and "boss1" or key
                    local s = GetSettingsForUnit(unitToken)
                    if not s then
                        return
                    end
                    local powerPos = s.powerPosition or "below"
                    local powerIsAtt = (powerPos == "below" or powerPos == "above")
                    local powerH = powerIsAtt and (s.powerHeight or 6) or 0
                    local btbPos = s.btbPosition or "bottom"
                    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
                    local btbH = (s.bottomTextBar and btbIsAtt) and (s.bottomTextBarHeight or 16) or 0
                    local oldH = s.healthHeight
                    s.healthHeight = math.max(Pix.Snap(hgt - powerH - btbH), 8)
                    if CludesUI._propagatingMatch and s.healthHeight == oldH then
                        return
                    end
                    Rebuild()
                end,
                loadPos = function(key)
                    local place = saved.profile.positions[key]
                    if not place then
                        return nil
                    end
                    return {
                        point = place.point,
                        relPoint = place.relPoint or place.point,
                        x = place.x,
                        y = place.y,
                    }
                end,
                savePos = function(key, anchorPoint, relPoint, posX, posY)
                    saved.profile.positions[key] =
                        { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    if CludesUI._unlockActive then
                        return
                    end
                    if key == "boss" then
                        local spacing = mod.UF_BossSpacing()
                        local bossStackDir = saved.profile.boss and saved.profile.boss.bossStackDirection
                            or "down"
                        -- boss1 to UIParent; chain 2..5 from the previous boss.
                        if frameList.boss1 then
                            frameList.boss1:ClearAllPoints()
                            frameList.boss1:SetPoint(
                                anchorPoint,
                                UIParent,
                                relPoint,
                                mod.UF_ScaledOffsets(frameList.boss1, posX, posY)
                            )
                        end
                        for index = 2, 5 do
                            local bf = frameList["boss" .. index]
                            local previous = frameList["boss" .. (index - 1)]
                            if bf and previous then
                                bf:ClearAllPoints()
                                if bossStackDir == "up" then
                                    bf:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, spacing)
                                else
                                    bf:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, -spacing)
                                end
                            end
                        end
                    elseif key == "classPower" then
                        if frameList._classPowerBar then
                            frameList._classPowerBar:ClearAllPoints()
                            frameList._classPowerBar:SetPoint(anchorPoint, UIParent, relPoint, posX, posY)
                        end
                    else
                        local fr = frameList[key]
                        if fr then
                            fr:ClearAllPoints()
                            fr:SetPoint(anchorPoint, UIParent, relPoint, mod.UF_ScaledOffsets(fr, posX, posY))
                        end
                    end
                end,
                clearPos = function(key)
                    saved.profile.positions[key] = nil
                end,
                applyPos = function(key)
                    local place = saved.profile.positions[key]
                    if not place then
                        return
                    end
                    -- Unlock-anchored elements: the anchor system is the position
                    -- authority. Only bootstrap from the saved standalone position
                    -- while the frame has no bounds yet (first placement); otherwise
                    -- leave it alone so the anchor position is never clobbered.
                    local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(key)
                    local pt = place.point
                    local rpt = place.relPoint or pt
                    local px, py = place.x, place.y
                    local PPa = CludesUI and CludesUI.PP
                    -- Helper: snap (x, y) for a frame using SnapCenterForDim for
                    -- CENTER anchors and SnapForES otherwise. CENTER snap needs
                    -- the frame's actual size to handle odd-pixel-dim frames
                    -- correctly (cy must be integer + 0.5 for odd heights).
                    local function SnapForFrame(fr, posX, posY)
                        if not PPa or not fr or not posX or not posY then
                            return posX, posY
                        end
                        local es = fr:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            return PPa.SnapCenterForDim(posX, fr:GetWidth() or 0, es),
                                PPa.SnapCenterForDim(posY, fr:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            return PPa.SnapForES(posX, es), PPa.SnapForES(posY, es)
                        end
                        return posX, posY
                    end
                    if key == "boss" then
                        local spacing = mod.UF_BossSpacing()
                        local bossStackDir = saved.profile.boss and saved.profile.boss.bossStackDirection
                            or "down"
                        if frameList.boss1 and not (anchored and frameList.boss1:GetLeft()) then
                            local bx, by = SnapForFrame(
                                frameList.boss1,
                                mod.UF_ScaledOffsets(frameList.boss1, place.x, place.y)
                            )
                            frameList.boss1:ClearAllPoints()
                            frameList.boss1:SetPoint(pt, UIParent, rpt, bx, by)
                        end
                        for index = 2, 5 do
                            local bf = frameList["boss" .. index]
                            local previous = frameList["boss" .. (index - 1)]
                            if bf and previous then
                                bf:ClearAllPoints()
                                if bossStackDir == "up" then
                                    bf:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, spacing)
                                else
                                    bf:SetPoint("TOPLEFT", previous, "TOPLEFT", 0, -spacing)
                                end
                            end
                        end
                    elseif key == "classPower" then
                        local cpb = frameList._classPowerBar
                        if cpb and not (anchored and cpb:GetLeft()) then
                            px, py = SnapForFrame(cpb, px, py)
                            cpb:ClearAllPoints()
                            cpb:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    else
                        local fr = frameList[key]
                        if fr and not (anchored and fr:GetLeft()) then
                            px, py = SnapForFrame(fr, mod.UF_ScaledOffsets(fr, px, py))
                            fr:ClearAllPoints()
                            fr:SetPoint(pt, UIParent, rpt, px, py)
                        end
                    end
                end,
            })
        end

        -- Core unit frames. Only register a mover for units that actually use
        -- the CludesUI frame; a unit set to Blizzard-default or Hidden has no
        -- CUI frame to move.
        local function AddUFElement(unit, sequence)
            if mod.GetUnitFrameSource(unit) == "cui" then
                elements[#elements + 1] = MakeUFElement(unit, sequence)
            end
        end
        AddUFElement("player", 1)
        AddUFElement("target", 2)
        AddUFElement("focus", 3)
        AddUFElement("pet", 4)
        AddUFElement("targettarget", 5)
        AddUFElement("focustarget", 6)
        if mod.GetUnitFrameSource("boss") == "cui" then
            local bossElem = MakeUFElement("boss", 7)
            -- Boss is a stack of 5 chained frames; resize / match actions don't make
            -- sense on the aggregate element. Boss can still anchor to other elements;
            -- it just can't be used as an anchor target.
            bossElem.noResize = true -- removes Width/Height Match + resize handles
            bossElem.noAnchorTarget = true -- others cannot anchor to boss
            elements[#elements + 1] = bossElem
        end

        -- Conditional elements. WoW Forever: the style that builds
        -- (ns.UF_ForeverCPStyle; a rogue under the CludesUI look reads its
        -- own), not the shared showClassPowerBar.
        local cpShown = saved.profile.player.showClassPowerBar
        if mod.UF_ForeverCPStyle then
            cpShown = mod.UF_ForeverCPStyle(saved.profile.player.classPowerStyle or "none") ~= "none"
        end
        if
            mod.GetUnitFrameSource("player") == "cui"
            and cpShown
            and not saved.profile.player.lockClassPowerToFrame
        then
            elements[#elements + 1] = MakeUFElement("classPower", 9)
        end

        -- Cast bar elements: standalone registration, no special-case branching
        local function MakeCastBarElement(cbKey, unitKey, sequence)
            local function GetCBFrame()
                local uf = frameList[unitKey]
                return uf and uf.Castbar and uf.Castbar:GetParent()
            end
            local function GetCBSettings()
                if unitKey == "player" then
                    return saved.profile.player
                end
                return GetSettingsForUnit(unitKey)
            end
            local function GetWidthKey()
                return unitKey == "player" and "playerCastbarWidth" or "castbarWidth"
            end
            local function GetHeightKey()
                return unitKey == "player" and "playerCastbarHeight" or "castbarHeight"
            end
            return MK({
                key = cbKey,
                label = UNIT_LABELS[cbKey] or cbKey,
                group = "Unit Frames",
                order = orderBase + sequence,
                getFrame = function()
                    return GetCBFrame()
                end,
                -- Blizzard Style: the holder carries the layout aspect (see
                -- ns.UF_CastbarAspectTemplate), so the mover cannot anchor to
                -- it and takes the same screen spot by absolute anchor.
                detachedMover = (mod.UF_Blizz() and mod.UF_LayoutAspectOK()) or nil,
                isHidden = function()
                    -- Live show/hide: mirror the per-unit cast bar enable setting
                    -- (player defaults off; target/focus default on). The mover is
                    -- gated on each unlock-mode open, so toggling the setting takes
                    -- effect without a /reload.
                    local s = GetCBSettings()
                    if not s then
                        return true
                    end
                    if mod.VisEffective(s) == "never" then
                        return true
                    end
                    if unitKey == "player" then
                        return not s.showPlayerCastbar
                    end
                    -- Pet: off by default, and no bar exists until built at login.
                    if unitKey == "pet" then
                        return s.showCastbar ~= true
                    end
                    return s.showCastbar == false
                end,
                getSize = function()
                    -- Return stored DB values so cog menu shows what the
                    -- user typed, not the pixel-snapped frame size.
                    local s = GetCBSettings()
                    if s then
                        local wid = s[GetWidthKey()] or 181
                        local hgt = s[GetHeightKey()] or 14
                        return wid, hgt
                    end
                    return 100, 14
                end,
                -- Classic WoW UI: the vanilla frame's rim outside the holder
                -- (icon included, the frame wraps both), so a width or height
                -- match lines up with what is on screen. The CludesUI look:
                -- a Custom Border Style cast border's reach (nil while off).
                getMatchPad = function()
                    if mod.UF_Style() ~= "classic" then
                        return mod.UF_CastBorderPad(unitKey, GetCBSettings())
                    end
                    local CF = CludesUI.ClassicFrame
                    if not CF then
                        return nil
                    end
                    local s = GetCBSettings()
                    return CF.Pad(CF.ScaleK(s and s[mod.UF_CastClassicKey(unitKey)]), false)
                end,
                setWidth = function(_, wid)
                    local s = GetCBSettings()
                    if not s then
                        return
                    end
                    local newW = math.max(Pix.Snap(wid), 30)
                    s[GetWidthKey()] = newW
                    local frame = GetCBFrame()
                    -- Stored height, not the live one: a holder on the Blizzard
                    -- Style aura block reads back a secret rect.
                    if frame then
                        Pix.Size(frame, newW, s[GetHeightKey()] or 14)
                    end
                end,
                setHeight = function(_, hgt)
                    if not CludesUI._unlockActive and not CludesUI._unlockLayerApplying then
                        return
                    end
                    local s = GetCBSettings()
                    if not s then
                        return
                    end
                    local newH = math.max(Pix.Snap(hgt), 5)
                    s[GetHeightKey()] = newH
                    local frame = GetCBFrame()
                    if frame then
                        Pix.Size(frame, s[GetWidthKey()] or 181, newH)
                    end
                    local uf = frameList[unitKey]
                    local cbar = uf and uf.Castbar
                    if cbar and cbar._blizzCast then
                        -- Blizzard Style: the icon spans the bar and its text box.
                        cbar._icoSide = newH
                        mod.UF_BlizzCastIcon(cbar)
                    elseif cbar and cbar._blizzFrame and mod.UF_BLIZZ.cast then
                        -- Classic kit: the vanilla frame's overhangs scale with
                        -- the height, so the whole cast pass re-runs.
                        cbar._icoSide = newH
                        mod.UF_ApplyBlizzCastbar(cbar)
                    elseif cbar and cbar._iconFrame then
                        cbar._iconFrame:SetSize(newH, newH)
                    end
                end,
                loadPos = function()
                    local place = saved.profile.positions[cbKey]
                    if not place then
                        return nil
                    end
                    return {
                        point = place.point,
                        relPoint = place.relPoint or place.point,
                        x = place.x,
                        y = place.y,
                    }
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    saved.profile.positions[cbKey] =
                        { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    if CludesUI._unlockActive then
                        return
                    end
                    local frame = GetCBFrame()
                    if frame then
                        frame:ClearAllPoints()
                        frame:SetPoint(anchorPoint, UIParent, relPoint, posX, posY)
                    end
                end,
                clearPos = function()
                    saved.profile.positions[cbKey] = nil
                end,
                applyPos = function()
                    local place = saved.profile.positions[cbKey]
                    if not place then
                        return
                    end
                    local frame = GetCBFrame()
                    if not frame then
                        return
                    end
                    -- Unlock-anchored castbars: the anchor system owns the
                    -- position (castbars are anchored to their unit frame by
                    -- default). Only bootstrap while the frame has no bounds.
                    if CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(cbKey) and frame:GetLeft() then
                        return
                    end
                    local pt, rpt = place.point, place.relPoint or place.point
                    local px, py = place.x, place.y
                    local PPa = CludesUI and CludesUI.PP
                    if PPa and px and py then
                        local es = frame:GetEffectiveScale()
                        local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                        if isCenterAnchor and PPa.SnapCenterForDim then
                            px = PPa.SnapCenterForDim(px, frame:GetWidth() or 0, es)
                            py = PPa.SnapCenterForDim(py, frame:GetHeight() or 0, es)
                        elseif PPa.SnapForES then
                            px = PPa.SnapForES(px, es)
                            py = PPa.SnapForES(py, es)
                        end
                    end
                    frame:ClearAllPoints()
                    frame:SetPoint(pt, UIParent, rpt, px or 0, py or 0)
                end,
            })
        end

        -- Always register all three cast bars; visibility is gated live via each
        -- element's isHidden (mirrors the show setting), so toggling a cast bar
        -- on/off takes effect on the next unlock-mode open -- no /reload needed.
        if mod.GetUnitFrameSource("player") == "cui" then
            elements[#elements + 1] = MakeCastBarElement("playerCastbar", "player", 10)
        end
        if mod.GetUnitFrameSource("target") == "cui" then
            elements[#elements + 1] = MakeCastBarElement("targetCastbar", "target", 11)
        end
        if mod.GetUnitFrameSource("focus") == "cui" then
            elements[#elements + 1] = MakeCastBarElement("focusCastbar", "focus", 12)
        end
        if mod.GetUnitFrameSource("pet") == "cui" then
            elements[#elements + 1] = MakeCastBarElement("petCastbar", "pet", 13)
        end

        CludesUI:RegisterUnlockElements(elements, "CludesUIUnitFrames")
        -- First sighting of each frame's border pad: the login reload ran before
        -- these elements existed, so without it the first border change after
        -- login would only be recorded, never re-pushed.
        if CludesUI.MatchPadChanged then
            local padKeys = mod.UF_PAD_KEYS
            for index = 1, #padKeys do
                CludesUI.MatchPadChanged(padKeys[index])
            end
        end

        -- Seed default anchor + width-match for castbars so they start anchored to
        -- their parent frame with matched width out of the box. Only seed if the user
        -- has NEVER configured this castbar in unlock mode (tracked by
        -- _castbarUnlockSeeded); once they have, stop overwriting their choices.
        if CludesUIDB then
            if not CludesUIDB.unlockAnchors then
                CludesUIDB.unlockAnchors = {}
            end
            if not CludesUIDB.unlockWidthMatch then
                CludesUIDB.unlockWidthMatch = {}
            end
            if not CludesUIDB._castbarUnlockSeeded then
                CludesUIDB._castbarUnlockSeeded = {}
            end
            local CB_DEFAULTS = {
                { cb = "playerCastbar", parent = "player" },
                { cb = "targetCastbar", parent = "target" },
                { cb = "focusCastbar", parent = "focus" },
                { cb = "petCastbar", parent = "pet" },
            }
            local cbPositions = saved and saved.profile and saved.profile.positions
            for _, def in ipairs(CB_DEFAULTS) do
                if not CludesUIDB._castbarUnlockSeeded[def.cb] then
                    -- Skip seeding if the user already has a saved position
                    -- (they moved the cast bar freely without anchoring)
                    local hasPos = cbPositions and cbPositions[def.cb]
                    if not hasPos then
                        if not CludesUIDB.unlockAnchors[def.cb] then
                            CludesUIDB.unlockAnchors[def.cb] = { target = def.parent, side = "BOTTOM" }
                        end
                        if not CludesUIDB.unlockWidthMatch[def.cb] then
                            CludesUIDB.unlockWidthMatch[def.cb] = def.parent
                        end
                    end
                    -- Mark as seeded so we never overwrite user changes
                    CludesUIDB._castbarUnlockSeeded[def.cb] = true
                end
            end
        end
    end
end

Inner.RegisterUFUnlockElements = RegisterUFUnlockElements
