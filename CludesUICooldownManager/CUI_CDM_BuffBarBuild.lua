if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarBuild.lua
--
--  BuildTrackedBuffBars: builds or rebuilds every tracking bar.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local pcall = pcall

local TBB_POPULAR_BUFFS, _tbbWake, GroupGrowOf = Inner.TBB_POPULAR_BUFFS, Inner._tbbWake, Inner.GroupGrowOf
local GroupSpacingOf, ResetReflowStates = Inner.GroupSpacingOf, Inner.ResetReflowStates
local tbbFrames, ApplyTrackedBuffBarSettings = Inner.tbbFrames, Inner.ApplyTrackedBuffBarSettings
local CreateTrackedBuffBarFrame = Inner.CreateTrackedBuffBarFrame
local EffectiveIconSpellID, TBBUsesVisCondition = Inner.EffectiveIconSpellID, Inner.TBBUsesVisCondition
local SetECME, SetRebuildPending = Inner.SetECME, Inner.SetRebuildPending
local SetReflowDirty, SetTickFrame = Inner.SetReflowDirty, Inner.SetTickFrame
local SetAnyPandemic, SetAnyThreshold = Inner.SetAnyPandemic, Inner.SetAnyThreshold
local SetAnyStacks, SetAnyVisCond = Inner.SetAnyStacks, Inner.SetAnyVisCond

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
Inner.ecmeSetters[#Inner.ecmeSetters + 1] = function(val)
    ECME = val
end
local tbbTickFrame
Inner.tickFrameSetters[#Inner.tickFrameSetters + 1] = function(val)
    tbbTickFrame = val
end

-------------------------------------------------------------------------------
--  Build / Rebuild All Tracking Bars
-------------------------------------------------------------------------------
function mod.BuildTrackedBuffBars()
    SetECME(mod.ECME)
    if not ECME or not ECME.db then
        return
    end
    -- No InCombatLockdown guard needed: TBB frames are ours (UIParent), not secure Blizzard frames, so positioning in combat is safe.
    SetRebuildPending(false)
    SetReflowDirty(true)

    -- Per-spec unlock-link views: the global anchor/match stores must hold THIS spec's TBB entries before any anchored-state below is read.
    mod.SyncTBBUnlockLinks()

    local profile = ECME.db.profile

    -- NEVER auto-swap width/height per build: the Vertical Orientation toggle already swaps
    -- dimensions, and a per-build swap fights slider input and makes resizes erratic.
    do
        local tbb = mod.GetTrackedBuffBars()
        local barList = tbb and tbb.bars
        if barList then
        end
    end

    -- "Use Blizzard CDM Bars": hide all TBB frames and bail
    if profile.cdmBars and profile.cdmBars.useBlizzardBuffBars then
        for index = 1, #tbbFrames do
            if tbbFrames[index] then
                tbbFrames[index]:Hide()
            end
        end
        _tbbWake._enabled = false
        _tbbWake:UnregisterAllEvents()
        if tbbTickFrame then
            tbbTickFrame:Hide()
        end
        return
    end

    -- Pre-populate bars for spells newly added to Blizzard's Tracked Bars section BEFORE reading the bar list, so this rebuild picks them up.
    mod.EnsureTBBAutoBars()

    local tbb = mod.GetTrackedBuffBars()
    -- Hold the per-group orientation invariant before reading any configs
    mod.EnforceTBBGroupOrientation(tbb)
    local barList = tbb.bars
    local _tbbPos = mod.GetTBBPositions()
    ResetReflowStates()

    -- Hide bars beyond current count
    for index = #barList + 1, #tbbFrames do
        if tbbFrames[index] then
            tbbFrames[index]:Hide()
        end
    end

    -- Feature-gating flags: collected in the bar loop, handed on behind it
    local _anyPandemic = false
    local _anyThreshold = false
    local _anyStacks = false
    local _anyVisCond = false

    local anyEnabled = false
    local anyLust = false -- any enabled bloodlust bar -> needs the Sated listener
    local anyAntiClip = false -- WoW Forever: any enabled bar drawing the anti-clip glow
    local lastBarByGroup = {} -- gid -> previous enabled member frame (chain tail)
    for index, conf in ipairs(barList) do
        -- Update gating flags
        if conf.pandemicGlow then
            _anyPandemic = true
        end
        if conf.stackThresholdEnabled then
            _anyThreshold = true
            _anyStacks = true
        end
        if (conf.stacksPosition or "center") ~= "none" then
            _anyStacks = true
        end
        if conf.stackBasedBar and conf.trackType ~= "cooldown" and conf.stackThresholdMaxEnabled then
            _anyStacks = true
        end
        local visCond = TBBUsesVisCondition(conf)
        if visCond then
            _anyVisCond = true
        end

        if not tbbFrames[index] then
            tbbFrames[index] = CreateTrackedBuffBarFrame(UIParent, index)
        end
        local barFrame = tbbFrames[index]
        -- Per-bar gate flag for the tick (our frame; the tick never re-derives it).
        barFrame._tbbVisCond = visCond or nil

        if conf.enabled == false then
            barFrame:Hide()
        else
            anyEnabled = true
            if conf.popularKey == "bloodlust" then
                anyLust = true
            end
            if conf.pandemicGlow then
                anyAntiClip = true
            end
            ApplyTrackedBuffBarSettings(barFrame, conf)

            -- Icon texture: preset icon, else the EFFECTIVE (override-resolved) form of the
            -- saved spell, never the raw saved id -- a bar saved for a base form seeds the
            -- talented override's icon and vice versa. The live tick re-derives from the
            -- bound frame/aura and overwrites this seed whenever better data exists.
            if barFrame._icon and barFrame._icon._tex then
                local iconID
                if conf.popularKey then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == conf.popularKey then
                            iconID = pe.icon
                            break
                        end
                    end
                end
                if not iconID then
                    local effSID = EffectiveIconSpellID(conf)
                    if effSID then
                        local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(effSID)
                        if spInfo then
                            iconID = spInfo.iconID
                        end
                    end
                end
                if iconID then
                    barFrame._icon._tex:SetTexture(iconID)
                end
                -- Rebuilds can re-pair bar index <-> config (add/remove shifts indices), so
                -- reset per-bar icon source state and let the next tick re-derive instead of trusting stale caches.
                barFrame._lastIconSID = nil
                barFrame._cachedBlizzIconTex = nil
                barFrame._cachedBlizzIconOwner = nil
            end

            -- Name text
            local namePos2 = conf.namePosition or ((conf.showName ~= false) and "left" or "none")
            if namePos2 ~= "none" and barFrame._nameText then
                local customName = mod.TBBCustomName(conf)
                local displayName = customName or conf.name
                -- Preset bars take the live label the same way the icon does above
                -- (the copy saved at pick time can name the other faction's lust),
                -- unless the bar has a name of its own.
                if conf.popularKey and not customName then
                    for _, pe in ipairs(TBB_POPULAR_BUFFS) do
                        if pe.key == conf.popularKey then
                            displayName = pe.name or displayName
                            break
                        end
                    end
                end
                if (not displayName or displayName == "") and conf.spellID and conf.spellID > 0 then
                    local spInfo = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(conf.spellID)
                    displayName = spInfo and spInfo.name
                    if not displayName and C_Spell.RequestLoadSpellData then
                        C_Spell.RequestLoadSpellData(conf.spellID)
                    end
                end
                barFrame._nameText:SetText(displayName or "")
                barFrame._nameSet = displayName and displayName ~= "" or false
            end

            -- Saved position / grouping. A group's FIRST enabled member takes the independent
            -- branch (its own saved pos) and becomes the group anchor; later members chain to
            -- the previous member using the group's grow/spacing. Independent bars (gid 0) always take the independent branch.
            local groupId = mod.TBBBarGroupID(conf)
            local prevInGroup = groupId ~= 0 and lastBarByGroup[groupId] or nil
            if prevInGroup then
                -- Grouped: position relative to the previous member
                local growDir = (GroupGrowOf(tbb, groupId) or "DOWN"):upper()
                local spacing = GroupSpacingOf(tbb, groupId) or 2
                barFrame:ClearAllPoints()
                if growDir == "UP" then
                    barFrame:SetPoint("BOTTOM", prevInGroup, "TOP", 0, spacing)
                elseif growDir == "RIGHT" then
                    barFrame:SetPoint("LEFT", prevInGroup, "RIGHT", spacing, 0)
                elseif growDir == "LEFT" then
                    barFrame:SetPoint("RIGHT", prevInGroup, "LEFT", -spacing, 0)
                else
                    barFrame:SetPoint("TOP", prevInGroup, "BOTTOM", 0, -spacing)
                end
            else
                -- Independent positioning (group anchors and ungrouped bars). A global group's
                -- anchor reads the shared registry position and its anchored-ness through the group's stable TBBG_ key.
                local gkeyPos = groupId ~= 0 and mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId)
                    or nil
                local posKey = tostring(index)
                local place, unlockKey
                if gkeyPos then
                    local record = mod.TBBGlobalGroup(gkeyPos)
                    place = record and record.pos
                    unlockKey = "TBBG_" .. gkeyPos
                    -- Stamp the anchor bar's size onto the registry entry so the
                    -- "Shift Elements If No Bars" stand-in (memberless specs)
                    -- holds the slot at the size the group last rendered. Gated
                    -- on the option so None profiles see zero new writes; a
                    -- never-stamped entry's stand-in uses the bar defaults.
                    if record and (record.shiftNoBar == "Up" or record.shiftNoBar == "Down") then
                        record.width = conf.width or 270
                        record.height = conf.height or 24
                    end
                else
                    place = _tbbPos[posKey]
                    unlockKey = "TBB_" .. posKey
                end
                if place and place.point then
                    local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not barFrame:GetLeft() then
                        barFrame:ClearAllPoints()
                        if place.scale then
                            pcall(function()
                                barFrame:SetScale(place.scale)
                            end)
                        end
                        barFrame:SetPoint(
                            place.point,
                            UIParent,
                            place.relPoint or place.point,
                            place.x or 0,
                            place.y or 0
                        )
                    end
                else
                    local anchored = CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored(unlockKey)
                    if not anchored or not barFrame:GetLeft() then
                        barFrame:ClearAllPoints()
                        barFrame:SetPoint(
                            "CENTER",
                            UIParent,
                            "CENTER",
                            0,
                            200 - (index - 1) * ((conf.height or 24) + 4)
                        )
                    end
                end
            end

            if groupId ~= 0 then
                lastBarByGroup[groupId] = barFrame
            end
            barFrame._tbbReady = true
            barFrame._isPassive = nil
            barFrame._stackCount = 0
            barFrame._isLifebloom = nil -- re-resolve Lifebloom identity after rebuild
            barFrame:Hide() -- tick shows it when active
        end
    end
    SetAnyPandemic(_anyPandemic)
    SetAnyThreshold(_anyThreshold)
    SetAnyStacks(_anyStacks)
    SetAnyVisCond(_anyVisCond)
    -- WoW Forever: a Tracking Bar's Pandemic Glow is the anti-clip glow, which
    -- listens to your casts only while an enabled bar uses it (CUI_CDM_ForeverAntiClip.lua).
    if mod.CDM_AntiClipBars then
        mod.CDM_AntiClipBars(anyAntiClip)
    end

    -- Tick frame: every frame while anything is live (bar fill+spark need smooth updates);
    -- the idle sleeper in UpdateTrackedBuffBarTimers parks it when nothing is.
    _tbbWake._enabled = anyEnabled and true or false
    if anyEnabled then
        if not tbbTickFrame then
            SetTickFrame(mod.TakeShell())
            local tbbAccum = 0
            tbbTickFrame:SetScript("OnUpdate", function(self, elapsed)
                tbbAccum = tbbAccum + elapsed
                if tbbAccum < 0.016 then
                    return
                end
                self._lastDt = tbbAccum
                tbbAccum = 0
                mod.UpdateTrackedBuffBarTimers()
            end)
        end
        _tbbWake.Wake()
    else
        _tbbWake:UnregisterAllEvents()
        if tbbTickFrame then
            tbbTickFrame:Hide()
        end
    end

    -- Start/stop the player-only Sated-debuff listener that drives the lust displays. Goes
    -- through the arbiter so a Custom Auras (icon) lust display keeps the listener armed even when no Tracking Bar lust bar exists.
    mod.UpdateLustListener()

    -- "Shift Elements If No Bars" (global groups): position each opted-in
    -- group's stand-in, and on an empty<->populated EDGE re-cascade the group's
    -- anchor chain so anchored elements pick up (or drop) the shift. The flip
    -- changes neither the stand-in's size nor its position (both come from the
    -- registry), so neither OnSizeChanged nor a move hook fires -- the cascade
    -- must be explicit, exactly like ResourceBars' BuildBars tail. Edge-gated
    -- via the per-key memo so a None-everywhere profile schedules ZERO anchor
    -- work here; unlock entry/exit manage the shift themselves.
    do
        local reg = mod.GetTBBGlobalGroups and mod.GetTBBGlobalGroups()
        if reg then
            for gk, record in pairs(reg) do
                -- Also keep maintaining a stand-in that already exists with the
                -- option back at None (session fallback, see TBBStandinFrame):
                -- it must track registry-pos edits from other specs instead of
                -- freezing anchored children on a phantom (audit-caught).
                if
                    record.shiftNoBar == "Up"
                    or record.shiftNoBar == "Down"
                    or (mod.TBBStandinFrame and mod.TBBStandinFrame(gk))
                then
                    mod.TBBEnsureStandin(gk)
                end
                if not CludesUI._unlockActive and CludesUI.PropagateAnchorChain then
                    -- dir: 0 = covered (members present or option off), +/-1 =
                    -- shifting. Unset memo reads as 0, so the first build with
                    -- nothing to shift schedules nothing (ERB memo parity).
                    local direction = mod.TBBShiftDirFor(record, gk)
                    local memo = mod._tbbShiftDirMemo
                    if not memo then
                        memo = {}
                        mod._tbbShiftDirMemo = memo
                    end
                    if direction ~= (memo[gk] or 0) then
                        memo[gk] = direction
                        CludesUI.PropagateAnchorChain("TBBG_" .. gk)
                    end
                end
            end
        end
    end

    -- Unlock mode
    if mod.RegisterTBBUnlockElements then
        mod.RegisterTBBUnlockElements()
    end

    -- 12.1 engine-driven decimal timer text (nil on 12.0: module self-gates)
    if mod.TBBDecimals_Sync then
        mod.TBBDecimals_Sync()
    end

    -- Match pads follow each bar's border settings: a bar or group whose pad
    -- changed is re-pushed through its match once, deferred (compare-only here).
    if CludesUI.MatchPadChanged then
        for index = 1, #barList do
            CludesUI.MatchPadChanged(mod._tbbUKey[index])
        end
        local greg = mod.GetTBBGlobalGroups and mod.GetTBBGlobalGroups()
        if greg then
            for gk in pairs(greg) do
                CludesUI.MatchPadChanged(mod._tbbgUKey[gk])
            end
        end
    end

    -- Group loot rolls already up keep clear of the rebuilt bars.
    mod.RequestLootPlacement()
end

Inner.broken = false
