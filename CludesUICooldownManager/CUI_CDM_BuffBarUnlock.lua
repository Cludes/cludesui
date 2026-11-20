if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_CDM_BuffBarUnlock.lua
--
--  Unlock Mode registration of the tracking bars and their groups.
--  Reads the earlier Tracking Bars files through ns and ns._buffBarInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._buffBarInternals
-- CludesUICdmBuffBars.lua or an earlier Tracking Bars file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local tbbFrames = Inner.tbbFrames

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._buffBarInternals, which hands the value to every copy.
local ECME
Inner.ecmeSetters[#Inner.ecmeSetters + 1] = function(val)
    ECME = val
end

-------------------------------------------------------------------------------
--  Unlock Mode Registration
-------------------------------------------------------------------------------
function mod.RegisterTBBUnlockElements()
    if not CludesUI or not CludesUI.RegisterUnlockElements then
        return
    end
    if not ECME or not ECME.db then
        return
    end
    -- Per-spec unlock-link views: this path can run on spec change before a TBB build (CDM
    -- setup registers synchronously so anchor data is ready for CollectAndReanchor), so sync the link stores here too.
    mod.SyncTBBUnlockLinks()
    local MK = CludesUI.MakeUnlockElement
    -- Never call UnregisterUnlockElement for TBB keys -- it triggers PruneStaleLinks which
    -- destroys saved anchor data in unlockAnchors. Instead, just overwrite registrations;
    -- the isHidden callback handles hiding movers for bars that don't exist in the current spec.
    local tbb = mod.GetTrackedBuffBars()
    local barList = (tbb and tbb.bars) or {}

    -- Membership/grow/spec may have changed: growth-edge extent watch re-derives lazily on next use.
    mod._tbbExtentWatch = nil

    -- Each group's anchor (first enabled member) owns that group's mover; the other members hide theirs. Computed per build so it tracks group edits.
    local elements = {}
    for i, conf in ipairs(barList) do
        local position = i
        local posKey = tostring(position)
        local barFrame = tbbFrames[position]
        local barGid = mod.TBBBarGroupID(conf)
        local isGroupMover = barGid ~= 0
            and position == mod.TBBGroupAnchorIndex(barGid)
            and mod.TBBGroupedCount(barGid) >= 2
        if barFrame then
            elements[#elements + 1] = MK({
                key = "TBB_" .. posKey,
                label = isGroupMover
                        and (mod.TBBGroupName(barGid) or CludesUI.Lf("Tracking Bar Group %d", barGid))
                    or CludesUI.Lf(
                        "Tracking Bar: %s",
                        mod.TBBCustomName(conf) or conf.name or CludesUI.Lf("Bar %d", position)
                    ),
                group = "Cooldown Manager",
                order = 650,
                noResize = true,
                -- Tracking bars may size-MATCH to other elements (allowMatchSource), but other
                -- elements may NOT match to them (noSizeMatchTarget): a tracking bar's size is
                -- driven by its own CDM sliders/dynamic content, so it should never be a sizing reference.
                allowMatchSource = true,
                noSizeMatchTarget = true,
                -- Outside reach of the bar's textured border: taken off a width /
                -- height it is matched to, so what it draws is what matches.
                getMatchPad = function()
                    local tbl = mod.GetTrackedBuffBars()
                    local c = tbl and tbl.bars and tbl.bars[position]
                    return mod.TBBBorderMatchPad(c, tbbFrames[position])
                end,
                isHidden = function()
                    local tbl = mod.GetTrackedBuffBars()
                    local b = tbl and tbl.bars
                    if not b or position > #b then
                        return true
                    end
                    local c = b[position]
                    -- Independent bars always show their own mover.
                    local groupId = mod.TBBBarGroupID(c)
                    if groupId == 0 then
                        return false
                    end
                    -- Global group: the stable TBBG_ mover owns the whole group -- every member's own mover hides, anchor included.
                    if mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId) then
                        return true
                    end
                    -- Grouped bars: only the group's anchor shows a mover (moves the
                    -- whole group); hide every other member, enabled OR disabled (a
                    -- disabled member re-enables straight into the chain, so its own
                    -- mover would be a phantom). No member enabled -> anchor nil, all hidden.
                    return position ~= mod.TBBGroupAnchorIndex(groupId)
                end,
                -- Grouped non-anchor members are positioned by the relative SetPoint
                -- chain in BuildTrackedBuffBars; report them as addon-owned so the
                -- generic anchor system never repositions them (a cascade/override
                -- SetPoint would sever the chain, e.g. in combat via a stale per-member
                -- link). A group ANCHOR returns false (stays element-anchorable).
                -- Global-group members are ALL addon-owned (anchor included): its
                -- position comes from the registry via BuildTrackedBuffBars, and the
                -- TBBG_ element carries the group's anchorable identity instead.
                isAnchored = function()
                    local tbl = mod.GetTrackedBuffBars()
                    local b = tbl and tbl.bars
                    local c = b and b[position]
                    local groupId = c and mod.TBBBarGroupID(c) or 0
                    if groupId == 0 then
                        return false
                    end
                    if mod.TBBGroupGlobalKey and mod.TBBGroupGlobalKey(groupId) then
                        return true
                    end
                    return position ~= mod.TBBGroupAnchorIndex(groupId)
                end,
                getFrame = function()
                    -- Never expose a stale frame when the current spec has fewer bars: anchors
                    -- involving this key stay dormant (children hold position) instead of gluing to a hidden frame at another spec's coordinates.
                    local tbl = mod.GetTrackedBuffBars()
                    local b = tbl and tbl.bars
                    if not b or position > #b then
                        return nil
                    end
                    return tbbFrames[position]
                end,
                getSize = function()
                    -- width/height ARE the total footprint (icon included), so matching reads the stored dims directly.
                    local tbl = mod.GetTrackedBuffBars()
                    local c = tbl.bars and tbl.bars[position]
                    local PPg = CludesUI and CludesUI.PP
                    local sn = PPg and PPg.Snap
                        or function(val)
                            return val
                        end
                    if c then
                        return sn(c.width or 270), sn(c.height or 24)
                    end
                    return 270, 24
                end,
                setWidth = function(_, wid)
                    local tbl = mod.GetTrackedBuffBars()
                    local c = tbl.bars and tbl.bars[position]
                    if not c then
                        return
                    end
                    local frame = tbbFrames[position]
                    local PPt = CludesUI and CludesUI.PP
                    wid = PPt and PPt.Snap(wid) or math.floor(wid + 0.5)
                    -- Persist during unlock (manual) AND match propagation, so a width match TO
                    -- another element survives the next BuildTrackedBuffBars instead of reverting to the slider value.
                    if CludesUI._unlockActive or CludesUI._propagatingMatch then
                        c.width = wid
                        -- Grouped bars share width: fan this out to the rest of the group
                        -- (covers unlock drag-resize AND a width-MATCH on the group anchor, both routing through here).
                        mod.PropagateTBBGroupSize(position, "width", wid)
                    end
                    if frame then
                        frame:SetWidth(wid)
                    end
                end,
                setHeight = function(_, hgt)
                    local tbl = mod.GetTrackedBuffBars()
                    local c = tbl.bars and tbl.bars[position]
                    if not c then
                        return
                    end
                    local PPt = CludesUI and CludesUI.PP
                    hgt = PPt and PPt.Snap(hgt) or math.floor(hgt + 0.5)
                    local frame = tbbFrames[position]
                    -- Persist during unlock AND match propagation (see setWidth).
                    if CludesUI._unlockActive or CludesUI._propagatingMatch then
                        c.height = hgt
                        mod.PropagateTBBGroupSize(position, "height", hgt)
                    end
                    if frame then
                        frame:SetHeight(hgt)
                    end
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    local place = mod.GetTBBPositions()
                    place[posKey] = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    -- A group is dragged via its anchor's mover, but the saved position is
                    -- keyed by the anchor's INDEX. If the anchor later changes (first
                    -- member leaves the group or is disabled) the new anchor would read a
                    -- stale coordinate and teleport. Mirror the group origin into every
                    -- member's key so whichever bar becomes the anchor reads it correctly.
                    local tbl = mod.GetTrackedBuffBars()
                    local c0 = tbl.bars and tbl.bars[position]
                    local groupId = c0 and mod.TBBBarGroupID(c0) or 0
                    if
                        groupId ~= 0
                        and position == mod.TBBGroupAnchorIndex(groupId)
                        and mod.TBBGroupedCount(groupId) >= 2
                    then
                        for jdx, c in ipairs(tbl.bars or {}) do
                            if jdx ~= position and mod.TBBBarGroupID(c) == groupId then
                                place[tostring(jdx)] =
                                    { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                            end
                        end
                    end
                    if not CludesUI._unlockActive then
                        local frame = tbbFrames[position]
                        if frame then
                            frame:ClearAllPoints()
                            frame:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
                        end
                        mod.BuildTrackedBuffBars()
                    end
                end,
                loadPos = function()
                    local place = mod.GetTBBPositions()
                    return place[posKey]
                end,
                clearPos = function()
                    local place = mod.GetTBBPositions()
                    place[posKey] = nil
                end,
                applyPos = function()
                    mod.BuildTrackedBuffBars()
                end,
            })
        end
    end

    -- Global groups: one stable mover per registry entry, registered even when the
    -- active spec has no member bars (never unregister -- links must survive;
    -- isHidden/getFrame nil keep empty groups inert). The mover reads/writes the shared
    -- registry position, so one drag places the group for every spec.
    local reg = mod.GetTBBGlobalGroups and mod.GetTBBGlobalGroups()
    if reg then
        -- Alias map: the anchor bar's frame carries the move/resize hooks under its per-bar
        -- TBB_ key; children anchored to the group's stable TBBG_ key need those notifications
        -- too. Rebuilt each registration pass (anchor index shifts on edits/deletes).
        local aliases = CludesUI._unlockKeyAliases
        if not aliases then
            aliases = {}
            CludesUI._unlockKeyAliases = aliases
        end
        for k, val in pairs(aliases) do
            if type(val) == "string" and val:find("^TBBG_") then
                aliases[k] = nil
            end
        end
        for gkey, record in pairs(reg) do
            local gk = gkey
            local lgid = mod.TBBLocalGidForGlobal(gk)
            local anchorIdx = lgid and mod.TBBGroupAnchorIndex(lgid)
            if anchorIdx then
                aliases["TBB_" .. anchorIdx] = "TBBG_" .. gk
            end
            elements[#elements + 1] = MK({
                key = "TBBG_" .. gk,
                label = CludesUI.Lf("Tracking Bars: %1$s", record.name or gk),
                group = "Cooldown Manager",
                order = 651,
                noResize = true,
                allowMatchSource = true,
                noSizeMatchTarget = true,
                -- The group anchor bar's border reach (its frame is the group's);
                -- nil for a memberless spec's stand-in, which draws no border.
                getMatchPad = function()
                    local groupId = mod.TBBLocalGidForGlobal(gk)
                    local ai = groupId and mod.TBBGroupAnchorIndex(groupId)
                    local tbl = ai and mod.GetTrackedBuffBars()
                    local c = tbl and tbl.bars and tbl.bars[ai]
                    return mod.TBBBorderMatchPad(c, ai and tbbFrames[ai])
                end,
                isHidden = function()
                    local groupId = mod.TBBLocalGidForGlobal(gk)
                    return not groupId or not mod.TBBGroupAnchorIndex(groupId)
                end,
                isAnchored = function()
                    return false
                end,
                getFrame = function()
                    local groupId = mod.TBBLocalGidForGlobal(gk)
                    local ai = groupId and mod.TBBGroupAnchorIndex(groupId)
                    if ai then
                        return tbbFrames[ai]
                    end
                    -- No member bars on the active spec. With "Shift Elements If
                    -- No Bars" set, the opt-in stand-in holds the group's slot so
                    -- anchored elements keep position (and shift into it); with
                    -- it off (None), nil keeps legacy behavior -- anchors stay
                    -- dormant (or take their stored fallback) instead of gluing
                    -- to a stale frame. A stand-in built earlier this session
                    -- keeps resolving after a None flip (see TBBStandinFrame).
                    local e = mod.TBBGlobalGroup(gk)
                    if e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down") then
                        return mod.TBBEnsureStandin(gk)
                    end
                    return mod.TBBStandinFrame and mod.TBBStandinFrame(gk) or nil
                end,
                getSize = function()
                    local groupId = mod.TBBLocalGidForGlobal(gk)
                    local ai = groupId and mod.TBBGroupAnchorIndex(groupId)
                    local tbl = mod.GetTrackedBuffBars()
                    local c = ai and tbl.bars and tbl.bars[ai]
                    local PPg = CludesUI and CludesUI.PP
                    local sn = PPg and PPg.Snap
                        or function(val)
                            return val
                        end
                    if c then
                        return sn(c.width or 270), sn(c.height or 24)
                    end
                    -- Memberless spec: the registry's last-stamped anchor size
                    -- (what the stand-in renders at), else the defaults.
                    local e = mod.TBBGlobalGroup(gk)
                    if e and e.width then
                        return sn(e.width), sn(e.height or 24)
                    end
                    return 270, 24
                end,
                setWidth = function(_, wid)
                    local groupId = mod.TBBLocalGidForGlobal(gk)
                    local ai = groupId and mod.TBBGroupAnchorIndex(groupId)
                    local tbl = mod.GetTrackedBuffBars()
                    local c = ai and tbl.bars and tbl.bars[ai]
                    local PPt = CludesUI and CludesUI.PP
                    wid = PPt and PPt.Snap(wid) or math.floor(wid + 0.5)
                    if c then
                        local frame = tbbFrames[ai]
                        if CludesUI._unlockActive or CludesUI._propagatingMatch then
                            c.width = wid
                            mod.PropagateTBBGroupSize(ai, "width", wid)
                        end
                        if frame then
                            frame:SetWidth(wid)
                        end
                        return
                    end
                    -- Memberless spec, STRICTLY gated on "Shift Elements If No
                    -- Bars" being Up/Down (the stand-in feature): a width match
                    -- landing here must still persist (the registry stamp is
                    -- what the stand-in renders from) and resize the frame, so
                    -- its size-changed hook reaches anchored children -- an
                    -- edge-preserve follower has to track the matched width
                    -- even while the group has no bars (field report). With the
                    -- option off this stays the legacy hard no-op: no write,
                    -- no resize.
                    local e = mod.TBBGlobalGroup(gk)
                    if not (e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down")) then
                        return
                    end
                    if CludesUI._unlockActive or CludesUI._propagatingMatch then
                        e.width = wid
                    end
                    local scrollFrame = mod.TBBStandinFrame and mod.TBBStandinFrame(gk)
                    if scrollFrame then
                        scrollFrame:SetWidth(wid)
                    end
                end,
                setHeight = function(_, hgt)
                    local groupId = mod.TBBLocalGidForGlobal(gk)
                    local ai = groupId and mod.TBBGroupAnchorIndex(groupId)
                    local tbl = mod.GetTrackedBuffBars()
                    local c = ai and tbl.bars and tbl.bars[ai]
                    local PPt = CludesUI and CludesUI.PP
                    hgt = PPt and PPt.Snap(hgt) or math.floor(hgt + 0.5)
                    if c then
                        local frame = tbbFrames[ai]
                        if CludesUI._unlockActive or CludesUI._propagatingMatch then
                            c.height = hgt
                            mod.PropagateTBBGroupSize(ai, "height", hgt)
                        end
                        if frame then
                            frame:SetHeight(hgt)
                        end
                        return
                    end
                    -- Memberless stand-in: same strict option gate as setWidth
                    -- (option off = legacy hard no-op). Height also feeds the
                    -- shift magnitude (target height), so anchored children
                    -- re-shift to the matched size.
                    local e = mod.TBBGlobalGroup(gk)
                    if not (e and (e.shiftNoBar == "Up" or e.shiftNoBar == "Down")) then
                        return
                    end
                    if CludesUI._unlockActive or CludesUI._propagatingMatch then
                        e.height = hgt
                    end
                    local scrollFrame = mod.TBBStandinFrame and mod.TBBStandinFrame(gk)
                    if scrollFrame then
                        scrollFrame:SetHeight(hgt)
                    end
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    local e = mod.TBBGlobalGroup(gk)
                    if not e then
                        return
                    end
                    e.pos = { point = anchorPoint, relPoint = relPoint, x = posX, y = posY }
                    if not CludesUI._unlockActive then
                        mod.BuildTrackedBuffBars()
                    end
                end,
                loadPos = function()
                    local e = mod.TBBGlobalGroup(gk)
                    return e and e.pos
                end,
                clearPos = function()
                    local e = mod.TBBGlobalGroup(gk)
                    if e then
                        e.pos = nil
                    end
                end,
                applyPos = function()
                    mod.BuildTrackedBuffBars()
                end,
            })
        end
    end

    if #elements > 0 then
        CludesUI:RegisterUnlockElements(elements, "CludesUICooldownManager")
    end

    -- Fallback anchors: bars/groups may have appeared or vanished for this spec -- let
    -- opted-in children re-evaluate (no-op when nobody opted in, or before the unlock module has loaded).
    if CludesUI.NotifyFallbackTargetsChanged then
        CludesUI.NotifyFallbackTargetsChanged()
    end
end
_G._CUCME_RegisterTBBUnlock = mod.RegisterTBBUnlockElements

Inner.broken = false
