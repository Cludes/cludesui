if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PartyLayout.lua
--
--  The party layout, the kit portrait events, party visibility,
--  ReloadPartyFrames and the unlock mode registration.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local floor = math.floor
local pairs = pairs
local ipairs = ipairs
local wipe = wipe
local tostring = tostring
local UnitExists = UnitExists
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local InCombatLockdown = InCombatLockdown

local allButtons, ApplyFont, eventFrame = Inner.allButtons, Inner.ApplyFont, Inner.eventFrame
local GetFFD, IsPowerBarEnabled, PixelSnap = Inner.GetFFD, Inner.IsPowerBarEnabled, Inner.PixelSnap
local ResolveHealthTexture, unitToButton = Inner.ResolveHealthTexture, Inner.unitToButton
local unitTrackers, LayoutTopNameBar = Inner.unitTrackers, Inner.LayoutTopNameBar
local StyleButton, StartGhostTicker = Inner.StyleButton, Inner.StartGhostTicker
local StartRangeTicker, StopGhostTicker = Inner.StartRangeTicker, Inner.StopGhostTicker
local StopRangeTicker, SetFramesVisible = Inner.StopRangeTicker, Inner.SetFramesVisible

local db
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    db = val
end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val)
    containerFrame = val
end
local framesVisible = false
Inner.framesVisibleSetters[#Inner.framesVisibleSetters + 1] = function(val)
    framesVisible = val
end

-- Layout party frames: apply unitGrowth direction and cell spacing to the header.
mod._LayoutPartyFrames = function()
    if not mod._partyHeader then
        return
    end
    if InCombatLockdown() then
        return
    end

    local s = db.profile
    local pw, ph, pcs = mod.RF_PartyDims(s)
    local bw, bh, cs = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)
    -- Party target frames along the stack sit between the frames: the pitch opens by their room.
    local along = mod.PT_AlongPitch(s)
    mod._ptPitchApplied = along
    cs = cs + along
    local unitGrowth = mod._PartyGrowth(s)

    local hdrPoint, hdrXOff, hdrYOff
    if unitGrowth == "DOWN" then
        hdrPoint = "TOP"
        hdrXOff = 0
        hdrYOff = -cs
    elseif unitGrowth == "UP" then
        hdrPoint = "BOTTOM"
        hdrXOff = 0
        hdrYOff = cs
    elseif unitGrowth == "RIGHT" then
        hdrPoint = "LEFT"
        hdrXOff = cs
        hdrYOff = 0
    else -- LEFT
        hdrPoint = "RIGHT"
        hdrXOff = -cs
        hdrYOff = 0
    end

    local needsRelayout = mod._partyHeader:GetAttribute("point") ~= hdrPoint
        or mod._partyHeader:GetAttribute("xOffset") ~= hdrXOff
        or mod._partyHeader:GetAttribute("yOffset") ~= hdrYOff
    if needsRelayout then
        local wasShown = mod._partyHeader:IsShown()
        if wasShown then
            mod._partyHeader:Hide()
        end
        for idx = 1, 5 do
            local button = mod._partyHeader[idx]
            if button then
                button:ClearAllPoints()
            end
        end
        mod._partyHeader:SetAttribute("point", hdrPoint)
        mod._partyHeader:SetAttribute("xOffset", hdrXOff)
        mod._partyHeader:SetAttribute("yOffset", hdrYOff)
        if wasShown then
            mod._partyHeader:Show()
        end
    end

    -- Self button + header slot positioning (also sets the header's own size,
    -- which drives the children's centered anchors). Shared with the slider
    -- hot path; returns useSelf for the showPlayer attribute logic below.
    -- Self-first via composition: a static unit="player" self button owns
    -- slot 0 and the party header excludes the player (showPlayer=false);
    -- self ordering only matters in a group (see ns._PositionPartySlots).
    local useSelf = mod._PositionPartySlots(bw, bh, cs, unitGrowth)
    local hideSelf = s.partyHideSelf

    -- Size container for unlock mode mover (always sized for 5 units)
    mod._SizePartyContainer(bw, bh, cs, unitGrowth)

    -- Apply sort attributes + player visibility to the party header
    if not InCombatLockdown() then
        local pSortMode = s.partySortMode or s.sortMode
        local sortByRole = pSortMode == "ROLE"
        local roleOrder = s.partyRoleOrder or s.roleOrder or { "TANK", "HEALER", "DAMAGER" }
        -- A party set the group state hides takes no nameList: a nameList is also
        -- a filter, and the visibility driver can show the set mid-fight, when no
        -- list can be rebuilt, so a stale one would drop the new members. The
        -- shown pass (_UpdatePartyVisibility) applies the lists.
        local _, live = mod._RFVisWanted()
        -- Sort By = FrameSort: a nameList in FrameSort's order (native index
        -- order while FrameSort is absent or its list is empty).
        local fsRank = live and (pSortMode == "FRAMESORT") and mod._FrameSortRanks(not mod._fsFromProvider)
            or nil
        -- showPlayer is false when the self button owns the player (useSelf) or
        -- when hiding self; true only for a normal in-header player frame. In
        -- arena useSelf is forced false (no self button), so this reduces to
        -- "show the player unless Hide Self" -- and the arena nameList below
        -- keeps membership consistent by omitting the player when Hide Self.
        local wantShowPlayer = not hideSelf and not useSelf

        -- Prioritize Class drives the header with an explicit nameList ordered by
        -- role (optional primary) -> class -> name. nameList is honored only when
        -- groupFilter is cleared, so we clear it and let showParty/showPlayer pick
        -- members. When off, fall back to the native groupBy/sortMethod path.
        local wantGroupBy, wantSortMethod, wantGroupingOrder, wantNameList, wantGroupFilter
        local smallRaidGroup = mod._SmallRaidGroup()
        if not live then
            -- Hidden set: the native path below.
        elseif mod._PartyInRaid() then
            -- Party-in-raid runs on raid units, where Prioritize Class cannot
            -- work (it iterates party1-4) and neither the self button nor
            -- showPlayer can order or hide the player. A raid-token nameList
            -- does both: it honors Show Self First / Self Last / Hide Self and
            -- still shows every teammate -- the whole team in arena, group 1
            -- only in Small Raid mode (bailing to native order until names
            -- resolve; the fallback groupFilter below keeps the group limit).
            if fsRank then
                wantNameList = mod._BuildFrameSortRaidPartyNameList(fsRank, hideSelf, smallRaidGroup)
            end
            if not wantNameList then
                local pSelfFirst = s.partyShowSelfFirst
                if pSelfFirst == nil then
                    pSelfFirst = s.showSelfFirst
                end
                local pSelfLast = s.partySelfLast
                if pSelfLast == nil then
                    pSelfLast = s.showSelfLast
                end
                wantNameList = mod._BuildArenaNameList(
                    hideSelf,
                    pSelfFirst,
                    pSelfLast,
                    sortByRole,
                    roleOrder,
                    smallRaidGroup
                )
            end
        elseif fsRank then
            wantNameList = mod._BuildFrameSortPartyNameList(fsRank, wantShowPlayer)
        elseif s.partyPrioritizeClass then
            wantNameList =
                mod._BuildPartyClassNameList(wantShowPlayer, sortByRole, roleOrder, s.partyClassOrder)
        end
        if wantNameList then
            wantGroupBy = nil
            wantSortMethod = "NAMELIST"
            wantGroupingOrder = ""
            wantGroupFilter = nil
        else
            wantNameList = nil
            wantGroupBy = sortByRole and "ASSIGNEDROLE" or nil
            wantSortMethod = sortByRole and "NAME" or "INDEX"
            wantGroupingOrder = sortByRole and (table.concat(roleOrder, ",") .. ",NONE") or ""
            -- Small Raid keeps its group-1 limit in a party too (every party member
            -- is subgroup 1 there), so a party the driver keeps shown as it turns
            -- into a small raid mid-fight shows group 1, not the first five raiders.
            local fGroup = smallRaidGroup or ((s.partySmallRaid == true and not mod._InArena()) and 1) or nil
            wantGroupFilter = fGroup and tostring(fGroup) or "1,2,3,4,5,6,7,8"
        end

        local function ApplyAttrs()
            mod._partyHeader:SetAttribute("groupFilter", wantGroupFilter)
            mod._partyHeader:SetAttribute("nameList", wantNameList)
            mod._partyHeader:SetAttribute("groupingOrder", wantGroupingOrder)
            mod._partyHeader:SetAttribute("groupBy", wantGroupBy)
            mod._partyHeader:SetAttribute("sortMethod", wantSortMethod)
            mod._partyHeader:SetAttribute("showPlayer", wantShowPlayer)
        end
        local needsHideShow = (mod._partyHeader:GetAttribute("groupBy") ~= wantGroupBy)
            or (mod._partyHeader:GetAttribute("sortMethod") ~= wantSortMethod)
            or (mod._partyHeader:GetAttribute("groupingOrder") ~= wantGroupingOrder)
            or (mod._partyHeader:GetAttribute("showPlayer") ~= wantShowPlayer)
            or (mod._partyHeader:GetAttribute("nameList") ~= wantNameList)
            or (mod._partyHeader:GetAttribute("groupFilter") ~= wantGroupFilter)
        if needsHideShow then
            mod._fsChanged = true
        end
        if needsHideShow and mod._partyHeader:IsShown() then
            mod._partyHeader:Hide()
            ApplyAttrs()
            mod._partyHeader:Show()
        elseif needsHideShow then
            ApplyAttrs()
        end
        -- Which layout the header now carries (shown: full; hidden: native), for
        -- _UpdatePartyVisibility to re-lay it when the set hides.
        mod._partyLaidVis = live
    end

    -- Self button + header slot positioning ran above (ns._PositionPartySlots),
    -- before the attribute pass so a header Hide/Show re-process anchors the
    -- children against the already-correct header position and size.
    mod.RF_SyncCompact(true)

    -- The friendly boss group attaches to this container (and to the growth axis derived above)
    -- while not in a raid, so every layout pass -- Horizontal Frames, Flip Growth, party size,
    -- cell spacing -- has to move it too. OOC only (this function bails in combat). In a raid the
    -- boss group hangs off the raid headers instead, so skip the re-anchor scan there.
    if (not IsInRaid() or mod._PartyInRaid()) and mod.FB_ReAnchor then
        mod.FB_ReAnchor()
    end
    -- The party target frames ride FB_ReAnchor above; this covers the raid branch that skips it
    -- (delta-gated, a no-op after it).
    mod._PT_Layout()
end

-- Party visibility: show/hide based on group state.
-- Party portraits (the Party Frames kit's socket, or the PORTRAIT section):
-- the portrait events, registered only while the party frames are shown
-- with a portrait that needs them (nothing runs while they are hidden, the
-- portrait is off or it shows class art; UNIT_MODEL_CHANGED for a 3D model
-- alone). Tokens a party button can hold: player/party1-4 in a party,
-- raid1-9 in arena and Small Raid mode (group 1 of a raid under 10 members
-- can sit at any raid index up to 9). Turning them on repaints every
-- portrait once, which covers any change made while the frames were hidden.
-- Called on the visibility edges and after every party reload (settings).
mod._kitPortraitUnits = {
    "player",
    "party1",
    "party2",
    "party3",
    "party4",
    "raid1",
    "raid2",
    "raid3",
    "raid4",
    "raid5",
    "raid6",
    "raid7",
    "raid8",
    "raid9",
}
mod.RF_KitPortraitEvents = function(on)
    -- Before the unit trackers exist there is nothing to register yet.
    if not unitTrackers.player then
        return
    end
    local kit = mod.RF_PartyKit()
    on = on and true or false
    -- Kit hide edge: its always-on power registrations go too.
    if kit and mod._kitShownEv ~= on then
        mod._kitShownEv = on
        if not on and mod.UpdatePowerEventRegistration then
            mod.UpdatePowerEventRegistration()
        end
    end
    local art = on and mod.RF_PtEventMode and mod.RF_PtEventMode(kit) or nil
    local wanted, wantModel = art ~= nil, art == "3d"
    local was, wasModel = mod._kitPortraitEv or false, mod._ptModelEv or false
    if was == wanted and wasModel == wantModel then
        return
    end
    mod._kitPortraitEv, mod._ptModelEv = wanted, wantModel
    local units = mod._kitPortraitUnits
    for idx = 1, #units do
        local u = units[idx]
        local t = unitTrackers[u]
        if t then
            if wanted ~= was then
                if wanted then
                    t:RegisterUnitEvent("UNIT_PORTRAIT_UPDATE", u)
                else
                    t:UnregisterEvent("UNIT_PORTRAIT_UPDATE")
                end
            end
            if wantModel ~= wasModel then
                if wantModel then
                    t:RegisterUnitEvent("UNIT_MODEL_CHANGED", u)
                else
                    t:UnregisterEvent("UNIT_MODEL_CHANGED")
                end
            end
        end
    end
    if wanted and not was then
        eventFrame:RegisterEvent("PORTRAITS_UPDATED")
        -- 2D art and the kit socket repaint; a 3D model repaints on its own
        -- show edge (and on a settings swap through its cleared memos).
        if mod.RF_PtRepaintAll then
            mod.RF_PtRepaintAll("Resync")
        end
    elseif was and not wanted then
        eventFrame:UnregisterEvent("PORTRAITS_UPDATED")
    end
end

mod._UpdatePartyVisibility = function()
    if not mod._partyHeader then
        return
    end
    if InCombatLockdown() then
        return
    end
    if mod._partyPvActive or mod._raidPvActive then
        return
    end
    -- Defensive: re-assert full opacity unless a size preview is dimming the
    -- real frames (see UpdateVisibility). Out of combat only (bails above).
    if not mod._sizePreviewTier and mod._partyContainerFrame then
        local dimmed = mod._partyContainerFrame:GetAlpha() ~= 1
        mod._partyContainerFrame:SetAlpha(1)
        if mod._ptModelOn then
            mod.RF_PtContainerAlpha(1)
        end
        if dimmed then
            mod._PF_AlphaSync()
        end
    end

    local s = db.profile
    -- Profile and spec-override swaps: Include Own Target first, so an enable edge below takes it.
    if mod._ptInclDesired ~= (s.partyTargetIncludeSelf == true) then
        mod.PT_SetIncludeSelf(s.partyTargetIncludeSelf)
    end
    -- An enable edge here refreshes the target frames itself (the show edge below then skips it).
    local ptWas = mod._ptEnabled
    if mod._ptDesired ~= (s.partyShowTargets == true) then
        mod.PT_SetEnabled(s.partyShowTargets)
    end
    -- Arena and Small Raid mode show party frames even though IsInRaid() is
    -- true. The header binds raid units via showRaid=true; the raid container
    -- is hidden there by UpdateVisibility.
    local _, visible = mod._RFVisWanted()
    local wasVisible = mod._partyFramesVisible
    mod._partyFramesVisible = visible
    if mod._NotifyTrackerProviders then
        mod._NotifyTrackerProviders()
    end

    -- Update showSolo attribute, but only when it changed -- re-setting a
    -- SecureGroupHeader attribute re-triggers a full child re-process even when
    -- unchanged (see UpdateVisibility's showSolo guard).
    local wantPartySolo = s.partyShowWhenSolo or false
    if mod._partyHeader and mod._partyHeader:GetAttribute("showSolo") ~= wantPartySolo then
        mod._partyHeader:SetAttribute("showSolo", wantPartySolo)
    end

    -- Only the container shows and hides (the header stays shown inside it);
    -- the driver decides the same way, synced first so the two agree this frame.
    mod._RFSyncVisDrivers()
    mod._partyContainerFrame:SetShown(visible)
    if visible then
        -- Suppress Blizzard party frames
        if mod._SuppressBlizzParty then
            mod._SuppressBlizzParty()
        end

        mod._LayoutPartyFrames()
        mod._RebuildPartyUnitMap()
        if mod.UpdatePowerEventRegistration then
            mod.UpdatePowerEventRegistration()
        end
        mod._UpdateAllPartyButtons()
        mod.RF_KitPortraitEvents(true)

        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        if not framesVisible then
            StopRangeTicker()
            StopGhostTicker()
        end

        if wasVisible then
            mod._RFForgetOccupants(mod._partyAllButtons)
        end
        wipe(mod._partyUnitToButton)
        mod.RF_KitPortraitEvents(false)
        -- A hidden set runs native (see _LayoutPartyFrames), so the driver can
        -- show it mid-fight with every member in place.
        if mod._partyLaidVis ~= false then
            mod._LayoutPartyFrames()
        end
    end

    -- Attach-point edges the layout pass above cannot cover: the boss group's own roster pass can
    -- run before the party frames are up, and the hidden branch lays out only when the set hides
    -- (the group then falls back to its free position). EDGE only -- this recompute runs on every
    -- roster event.
    if mod._fbPartyAttachState ~= visible then
        mod._fbPartyAttachState = visible
        if mod.FB_ReAnchor then
            mod.FB_ReAnchor()
        end
    end
    -- Party target frames skip roster refreshes while the party frames are hidden: their show edge
    -- takes one (units, your raid token, the listeners). EDGE only.
    if mod._ptVisState ~= visible then
        mod._ptVisState = visible
        if visible and ptWas then
            mod._PT_RefreshAll()
        end
    end
end

-- Combat half of the two passes above. In combat the visibility drivers show
-- and hide the containers themselves; this keeps the Lua side in step with no
-- protected call: the flags that gate unit events, the routing maps, the range
-- and ghost tickers, the power and portrait registrations, the tracker
-- providers. The shown set's header re-reads the roster as it shows, and each
-- assignment remaps and repaints its button. Edge-gated (a roster storm with no
-- set change costs two compares); an edge marks the roster dirty so combat end
-- runs the full passes (layout, sort, sizes).
mod._RFCombatVisEdge = function()
    local raid, party = mod._RFVisWanted()
    local raidEdge = raid ~= (framesVisible == true)
    local partyEdge = party ~= (mod._partyFramesVisible == true)
    if not raidEdge and not partyEdge then
        return
    end
    mod._rosterDirtyInCombat = true
    if raidEdge then
        SetFramesVisible(raid)
        mod._raidFramesVisible = raid
        if not raid then
            mod._RFForgetOccupants(allButtons)
            wipe(unitToButton)
        end
    end
    if partyEdge then
        mod._partyFramesVisible = party
        if not party then
            mod._RFForgetOccupants(mod._partyAllButtons)
            wipe(mod._partyUnitToButton)
        end
        mod.RF_KitPortraitEvents(party)
    end
    if raid or party then
        if IsInGroup() then
            StartRangeTicker()
            StartGhostTicker()
        end
    else
        StopRangeTicker()
        StopGhostTicker()
    end
    if mod.UpdatePowerEventRegistration then
        mod.UpdatePowerEventRegistration()
    end
    if mod._NotifyTrackerProviders then
        mod._NotifyTrackerProviders()
    end
end

-- Reload party frames: apply party-specific sizing then shared rendering.
-- Uses ns._partyProxy for all reads so party overrides take effect.
-- Anchor closures (captured db.profile at StyleButton time) need a temp-swap:
-- we write party_ values onto db.profile, call the closures, then restore.
mod.ReloadPartyFrames = function(skipButtons)
    if not mod._partyHeader then
        return
    end
    -- Re-evaluate UNIT_FLAGS registration before the temp-swap below (which
    -- overwrites db.profile), so a section sync/unsync that flips the party's
    -- effective combat-icon state turns the party trackers on/off in step.
    if mod.UpdateCombatEventRegistration then
        mod.UpdateCombatEventRegistration()
    end
    local p = mod._partyProxy -- reads party_ keys with fallthrough
    local raw = db.profile
    -- Scaled reads for everything in INDICATOR_SCALE_KEYS (role/leader/marker
    -- icons, aura icon sizes, text sizes): mirrors the raid loop, which reads
    -- through ns._scaledProfile. Non-scale keys pass through unchanged.
    local pp = mod._scaledPartyProxy

    -- Recompute the party indicator/aura scale (Auto Resize) up front; the
    -- _UpdateAllPartyButtons() call at the end re-renders indicators with it.
    if mod._UpdatePartyIndicatorScale then
        mod._UpdatePartyIndicatorScale()
    end

    -- Temp-swap: write party overrides onto db.profile so anchor closures
    -- (which captured db.profile) read party values. Only for keys whose
    -- section is custom (unsynced). `swapped` records WHICH keys were swapped:
    -- a key whose raid value is nil (no default, never set on raid) stores
    -- nothing in `saved`, so restoring from `saved` alone would skip it and
    -- leave the party value on the shared raid key permanently.
    local saved, swapped = {}, {}
    local pxSib = mod._PARTY_PX_SIBLING
    for key, section in pairs(mod._PARTY_KEY_SECTION) do
        if mod._IsPartySectionCustom(section) then
            local pv = rawget(raw, "party_" .. key)
            -- An exact-size companion swaps whenever its sibling does (its party
            -- value may be nil): recorded in `swapped` so the restore writes it back.
            local sib = pxSib[key]
            if pv ~= nil or (sib and rawget(raw, "party_" .. sib) ~= nil) then
                swapped[#swapped + 1] = key
                saved[key] = raw[key]
                raw[key] = pv
            end
        end
    end

    -- Now db.profile has party values in place. Read from it directly for
    -- sizing (which also needs party width/height overrides).
    local pw, ph, _, pres = mod.RF_PartyDims(raw)
    local bw, bh = PixelSnap(pw), PixelSnap(ph)
    -- The bars' width (an attached portrait takes its share of the box).
    local barW = bw - ((pres and pres > 0) and PixelSnap(pres) or 0)
    local powerH = IsPowerBarEnabled(raw) and PixelSnap(raw.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, button in ipairs(skipButtons and mod._emptyList or mod._partyAllButtons) do
        local d = GetFFD(button)
        if not d.styled then
            -- _isParty BEFORE StyleButton: the container setup inside it
            -- resolves the style key and settings proxy from this flag, and
            -- the dispel slots BIND that key permanently. Styling first
            -- registered party dispel slots under the RAID key -- party
            -- dispel mode/icons/colors never applied (8.8.3 field reports).
            d._isParty = true
            mod._StyleButtonSecure(button)
            StyleButton(button)
        end

        -- Window/initialConfigFunction own sizes in combat (see raid loop).
        if not InCombatLockdown() then
            button:SetSize(bw, bh)
        end

        -- Party portrait (CUI_RaidFrames_Portrait.lua; the kit keeps its own):
        -- ahead of the bar layout below, which hangs the bars off its area.
        if not d.kit then
            local pu = button:GetAttribute("unit")
            mod.RF_PtApply(button, d, pp, bw, bh, pu and UnitExists(pu) and pu or nil)
        end

        -- Health bar height/anchor + Top Name Bar (reads party-resolved `raw`).
        -- The Party Frames kit owns its bar rects (its pass runs below, after
        -- the texture swaps, so its masks seat on the new fills).
        if not d.kit then
            LayoutTopNameBar(
                raw,
                bh,
                powerH,
                d.health,
                d.topNameBar,
                d.topNameBarBg,
                d.topNameBarText,
                d.power
            )
        end
        if d.health then
            d.health:SetStatusBarTexture(texPath)
            d.health:GetStatusBarTexture():SetHorizTile(false)
            if d.ReanchorAbsorbToFill then
                d.ReanchorAbsorbToFill()
            end
        end

        -- Background: through its stamped owner (dark-mode aware), AFTER the
        -- fill texture swap (see the raid loop).
        if d.bg then
            d._bgSt, d._bgA = nil, nil
            local u = button:GetAttribute("unit")
            if u and UnitExists(u) then
                mod._ApplyHealthBg(d, d.health, raw, u)
            end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show). This is a
        -- second writer of health height alongside UpdateButton's own cached transition
        -- (LayoutTopNameBar above sized health assuming power reserved), so drop the
        -- cache or UpdateAllButtons below sees applied == computed and never corrects it.
        if d.kit then
            -- Party Frames kit: the mana bar always shows in the art's track
            -- (no role gate, no height); then the kit pass itself.
            if d.power then
                d.power:SetStatusBarTexture(texPath)
                d.power:GetStatusBarTexture():SetHorizTile(false)
            end
            local u = button:GetAttribute("unit")
            mod.RF_ApplyPartyKit(button, d, pp, u and UnitExists(u) and u or nil)
        else
            d._appliedHidePower = nil
            if d.power then
                d.power:Hide()
                if powerH > 0 then
                    d.power:SetHeight(powerH)
                    d.power:SetStatusBarTexture(texPath)
                    d.power:GetStatusBarTexture():SetHorizTile(false)
                end
            end
        end
        if d.powerBg then
            d.powerBg:SetColorTexture(
                (raw.powerBgColor or {}).r or 0,
                (raw.powerBgColor or {}).g or 0,
                (raw.powerBgColor or {}).b or 0,
                (raw.powerBgDarkness or 70) / 100
            )
            d._pwBgTintType = nil
        end
        if d.UpdatePowerBorder then
            d.UpdatePowerBorder(true)
        end

        -- The texts: Power Text hidden with the bar above (not under the kit, whose
        -- mana bar stays shown) until _UpdateAllPartyButtons below shows it again; every
        -- text restyled and re-anchored, the name on the party bar width (the kit's is
        -- its own).
        if d.AnchorTexts then
            if not d.kit then
                mod.RF_TextPowerHide(d)
            end
            d.AnchorTexts()
            mod.RF_TextNameWidth(d, barW)
        end

        -- Status text
        if d.statusText then
            local stc = raw.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(d.statusText, pp.statusTextSize or 14)
            d.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if d.AnchorStatusText then
                d.AnchorStatusText()
            end
        end

        -- Role icon
        if d.roleIcon then
            local riSz = PixelSnap(pp.roleIconSize or 14)
            d.roleIcon:SetSize(riSz, riSz)
            if d.AnchorRoleIcon then
                d.AnchorRoleIcon()
            end
        end

        -- Leader icon
        if d.leaderIcon then
            local liSz = PixelSnap(pp.leaderIconSize or 14)
            d.leaderIcon:SetSize(liSz, liSz)
            if d.kitG then
                mod.RF_KitLeader(d, pp)
            else
                d.leaderIcon:ClearAllPoints()
                local liPos = (raw.leaderIconPosition or "top"):upper()
                d.leaderIcon:SetPoint(
                    liPos,
                    mod.RF_AnchorHost(d.health, pp),
                    liPos,
                    pp.leaderIconOffsetX or 0,
                    pp.leaderIconOffsetY or 0
                )
            end
            -- Re-assert the host's strata/level above the border
            if d.leaderHost then
                mod.ApplyLeaderStrata(d.leaderHost)
            end
        end

        -- Raid marker
        if d.raidMarker then
            local rmSz = PixelSnap(pp.raidMarkerSize or 16)
            d.raidMarker:SetSize(rmSz, rmSz)
            if d.AnchorRaidMarker then
                d.AnchorRaidMarker()
            end
        end

        -- Ready check / summon
        if d.readyCheck then
            local rcSz = PixelSnap(pp.readyCheckSize or 20)
            d.readyCheck:SetSize(rcSz, rcSz)
            if d.AnchorReadyCheck then
                d.AnchorReadyCheck()
            end
        end

        -- Combat icon
        if d.combatIcon then
            local cciSz = PixelSnap(pp.combatIndicatorSize or 16)
            d.combatIcon:SetSize(cciSz, cciSz)
            if d.AnchorCombatIcon then
                d.AnchorCombatIcon()
            end
        end

        -- Ping marker
        if d.pingFrame then
            mod._RFAnchorPing(d)
        end
        if mod.RF_FvMissingAnchor then
            mod.RF_FvMissingAnchor(button, d)
        end

        -- Border
        if d.UpdateBorder then
            d.UpdateBorder()
        end
    end

    -- Restore db.profile to raid values (via `swapped`, so a nil raid value
    -- is written back as nil rather than skipped)
    for _, key in ipairs(swapped) do
        raw[key] = saved[key]
    end

    -- Re-layout header
    mod._LayoutPartyFrames()
    mod._RebuildPartyUnitMap()
    -- Re-sync UNIT_POWER_UPDATE registration: a Power Bar section sync/unsync
    -- (or a party-side role-flag edit) changes the party's effective power
    -- gating, same reasoning as UpdateCombatEventRegistration above. Must run
    -- after the temp-swap restore so raid reads see raid values.
    if mod.UpdatePowerEventRegistration then
        mod.UpdatePowerEventRegistration()
    end
    mod._UpdateAllPartyButtons()

    -- Aura containers read the party class through its scaled proxy; the
    -- fingerprint guards make this near-free when nothing party-side changed.
    if mod.RFC_ReloadAll then
        mod.RFC_ReloadAll()
    end
    -- Party Frames kit: an attached Friendly Boss group clears the kit's
    -- outside auras, which these settings move (out of combat only).
    if mod.RF_PartyKit() and mod.FB_ReAnchor and not InCombatLockdown() then
        mod.FB_ReAnchor()
    end
    -- Portrait events follow the portrait settings (a no-op when unchanged).
    mod.RF_KitPortraitEvents(mod._partyFramesVisible)
    -- Pets and target frames beside the party frames are styled from the party settings.
    if not skipButtons then
        mod.PF_PartyRestyle()
        mod._PT_Restyle()
    end
end

local function RegisterWithUnlockMode()
    if not (CludesUI and CludesUI.RegisterUnlockElements) then
        return
    end
    if not containerFrame then
        return
    end

    -- Snap saved positions to the physical pixel grid using each container's own
    -- effective scale, via the REAL PP (CludesUI.PP) -- the file-local PP is
    -- PanelPP, which has no .Snap (`PP.Snap or floor` would fall through to plain
    -- integer rounding, not physical pixels). Matches the SnapForES pattern every
    -- other unlock element uses (and RF's own PixelSnap), keeping the container crisp.
    local realPP = CludesUI and CludesUI.PP
    local function snap(widget, val)
        if realPP and realPP.SnapForES and widget then
            return realPP.SnapForES(val, widget:GetEffectiveScale())
        end
        return floor(val + 0.5)
    end

    CludesUI:RegisterUnlockElements({
        CludesUI.MakeUnlockElement({
            key = "RF_RaidFrames",
            label = "Raid Frames",
            group = "Raid & Party Frames",
            order = 500,
            noResize = true,
            -- RF positions its own container via _ApplyTierOffset (base 20-man top-left
            -- + per-tier offset, tier-footprint-INDEPENDENT), re-run on init/PEW/roster+
            -- tier changes/combat end. The centralized ApplySavedPositions init loop
            -- re-anchors at unlockPos.point using the CURRENT (per-tier) container size,
            -- which diverges from that scheme for every non-20 size and clobbers the
            -- correct position ~0.6s after login. noInitHook keeps that loop off the
            -- container so _ApplyTierOffset stays sole authority (mover/save/anchors unaffected).
            noInitHook = true,

            getFrame = function()
                return containerFrame
            end,
            getSize = function()
                return containerFrame:GetWidth(), containerFrame:GetHeight()
            end,

            savePos = function(_, anchorPoint, relPoint, posX, posY, srcPoint, srcRelPoint)
                -- srcPoint/srcRelPoint: the PRE-conversion anchor the unlock framework
                -- received. Anything other than CENTER/CENTER means the CENTER coords were
                -- measured from the container's LIVE (ACTIVE-tier) bounds and must be
                -- rebased to the BASE footprint's equivalent center (the convention every
                -- apply reads), or a mover drag during a non-base tier lands off by a
                -- constant offset on the next _ApplyTierOffset pass. CENTER/CENTER or
                -- absent (revert/nudge/typed-edit) means already stored-convention; rebasing again would corrupt it.
                if
                    srcPoint
                    and not (srcPoint == "CENTER" and (srcRelPoint or "CENTER") == "CENTER")
                    and mod._RFRebaseSavedCenter
                then
                    posX, posY = mod._RFRebaseSavedCenter(posX, posY)
                end
                db.profile.unlockPos = {
                    point = anchorPoint,
                    relPoint = relPoint,
                    x = snap(containerFrame, posX),
                    y = snap(containerFrame, posY),
                }
            end,
            loadPos = function()
                return db.profile.unlockPos
            end,
            clearPos = function()
                db.profile.unlockPos = nil
            end,
            applyPos = function()
                -- Delegate to the tier-aware authority (base top-left + per-tier
                -- offset) so any framework apply matches _ApplyTierOffset instead
                -- of the old re-anchor-at-unlockPos.point scheme, which used the
                -- current tier's container size and mispositioned non-20 sizes.
                if mod._ApplyTierOffset then
                    mod._ApplyTierOffset()
                end
            end,
        }),
        CludesUI.MakeUnlockElement({
            key = "RF_PartyFrames",
            label = "Party Frames",
            group = "Raid & Party Frames",
            order = 501,
            noResize = true,

            getFrame = function()
                return mod._partyContainerFrame
            end,
            getSize = function()
                return mod._partyContainerFrame:GetWidth(), mod._partyContainerFrame:GetHeight()
            end,

            savePos = function(_, anchorPoint, relPoint, posX, posY)
                db.profile.partyUnlockPos = {
                    point = anchorPoint,
                    relPoint = relPoint,
                    x = snap(mod._partyContainerFrame, posX),
                    y = snap(mod._partyContainerFrame, posY),
                }
            end,
            loadPos = function()
                return db.profile.partyUnlockPos
            end,
            clearPos = function()
                db.profile.partyUnlockPos = nil
            end,
            applyPos = function()
                -- Element-anchored: the anchor system owns the position. Only
                -- apply the saved pos as a bootstrap while the frame has no
                -- resolved geometry yet (anchor pass corrects it after).
                if
                    CludesUI.IsUnlockAnchored
                    and CludesUI.IsUnlockAnchored("RF_PartyFrames")
                    and mod._partyContainerFrame
                    and mod._partyContainerFrame:GetLeft()
                then
                    return
                end
                local place = db.profile.partyUnlockPos
                if place and mod._partyContainerFrame then
                    mod._partyContainerFrame:ClearAllPoints()
                    mod._partyContainerFrame:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
                end
            end,
        }),
        CludesUI.MakeUnlockElement({
            key = "RF_HealerMana",
            label = "Healer Mana Display",
            group = "Raid & Party Frames",
            order = 502,
            noResize = true,
            -- Disabled feature = no mover. Gates on the SETTING (mode none),
            -- not on the group-type activity gate: an enabled display should
            -- stay positionable while solo. The options mode setter
            -- re-registers via ns._RFRegisterUnlock so an open unlock session
            -- gains or loses the mover live in both directions.
            isHidden = function()
                local hm = mod._HMSet and mod._HMSet()
                return not hm or (hm.mode or "none") == "none"
            end,
            getFrame = function()
                return mod._hmContainer or (mod._HMEnsureContainer and mod._HMEnsureContainer())
            end,
            getSize = function()
                local c = mod._hmContainer
                if c then
                    return c:GetWidth(), c:GetHeight()
                end
                return 50, 25
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                local hm = mod._HMSet()
                hm.unlockPos = {
                    point = anchorPoint,
                    relPoint = relPoint,
                    x = snap(mod._hmContainer, posX),
                    y = snap(mod._hmContainer, posY),
                }
            end,
            loadPos = function()
                return mod._HMSet().unlockPos
            end,
            clearPos = function()
                mod._HMSet().unlockPos = nil
            end,
            applyPos = function()
                local c = mod._hmContainer
                local place = mod._HMSet().unlockPos
                if c and place and place.point then
                    c:ClearAllPoints()
                    c:SetPoint(
                        place.point,
                        UIParent,
                        place.relPoint or place.point,
                        place.x or 0,
                        place.y or 0
                    )
                end
            end,
        }),
        CludesUI.MakeUnlockElement({
            key = "RF_PlayerGroup",
            label = "Player Group Label",
            group = "Raid & Party Frames",
            order = 503,
            noResize = true,
            isHidden = function()
                return not mod._PGSet().enabled
            end,
            -- Built only while enabled: the saved-position pass calls this
            -- for every element.
            getFrame = function()
                if mod._PGSet().enabled then
                    return mod._PGEnsureFrame()
                end
                return mod._pgFrame
            end,
            getSize = function()
                local f = mod._pgFrame
                if f then
                    return f:GetWidth(), f:GetHeight()
                end
                return 50, 25
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                mod._PGSet().unlockPos = {
                    point = anchorPoint,
                    relPoint = relPoint,
                    x = snap(mod._pgFrame, posX),
                    y = snap(mod._pgFrame, posY),
                }
            end,
            loadPos = function()
                return mod._PGSet().unlockPos
            end,
            clearPos = function()
                mod._PGSet().unlockPos = nil
            end,
            applyPos = function()
                mod._PGApplyPos()
            end,
        }),
    })
end
-- Options-side re-registration seam (the function above is a file-scope local
-- the options file cannot reach): setting changes that flip an element's
-- isHidden verdict re-register so an open unlock session updates live.
mod._RFRegisterUnlock = RegisterWithUnlockMode

Inner.RegisterWithUnlockMode = RegisterWithUnlockMode
Inner.broken = false
