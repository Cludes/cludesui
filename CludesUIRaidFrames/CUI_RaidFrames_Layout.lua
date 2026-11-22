if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
local CUI = CludesUI
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Layout.lua
--
--  Header creation and LayoutGroups.
--  Reads the earlier Raid Frames files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIRaidFrames.lua or an earlier Raid Frames file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local abs = math.abs
local tostring = tostring
local IsInRaid = IsInRaid
local InCombatLockdown = InCombatLockdown
local GetNumGroupMembers = GetNumGroupMembers
local CreateFrame = CreateFrame

local allButtons, ApplyFont, PixelSnap = Inner.allButtons, Inner.ApplyFont, Inner.PixelSnap
local separatedHdrs, ApplySortToHeaders = Inner.separatedHdrs, Inner.ApplySortToHeaders
local SetContainerFrame = Inner.SetContainerFrame

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val) saved = val end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val) containerFrame = val end

-------------------------------------------------------------------------------
--  Header creation
-------------------------------------------------------------------------------
-- One SecureGroupHeader set per layout mode: 8 separated group headers, or a
-- single flat header for Merge Groups (only structure that can fill/sort across
-- group boundaries). Only the ACTIVE mode builds at login (full-set build/style
-- dominates login cost); the other materializes on the first mode flip via
-- ReloadFrames/_CURF_RefreshAll. Combat blocks secure creation -- a combat-time
-- flip flags the REGEN reload path to build there instead.
mod._BuildHeaderSet = function(merge)
    if not containerFrame then return end
    if merge and mod._flatHeader then return end
    if not merge and separatedHdrs[1] then return end
    if InCombatLockdown() then
        mod._sizeTierDirtyInCombat = true
        return
    end

    local cfg = saved.profile

    -- Button dimensions passed to headers via attributes (pixel-snapped):
    -- active tier dims when a tier is live (late build inside a raid), else base.
    local bw = PixelSnap(mod._activeSizeW or cfg.frameWidth or 72)
    local bh = PixelSnap(mod._activeSizeH or cfg.frameHeight or 46)

    -- initialConfigFunction: runs in restricted env when header creates a button
    local initConfig = ([[
        self:SetWidth(%d)
        self:SetHeight(%d)
    ]]):format(bw, bh)

    -- Compute correct initial point/offset from saved growth direction. Self-heal
    -- a same-axis pair (see ns._RFEffectiveGrowth) before deriving anything from
    -- it -- this bootstrap runs from the raw profile, ahead of _LayoutGroupsImpl's
    -- own per-tier resolution and self-heal.
    local initUnitGrowth, initGroupGrowth =
        mod._RFEffectiveGrowth(cfg.unitGrowth or "DOWN", cfg.groupGrowth or "RIGHT", merge)
    local csInit = mod.RF_CellSpacing(cfg)
    local initPoint, initXOff, initYOff = mod._RFHeaderPoint(initUnitGrowth, csInit)

    -- A header makes children only while visible (IsVisible walks the parent
    -- chain): a set built with the container hidden (a Merge Groups flip while
    -- solo or in a party) shows the container around the pre-spawn below.
    local hid = not containerFrame:IsShown()
    if hid then containerFrame:Show() end

    if not merge then
        -----------------------------------------------------------
        --  8 separated group headers (one per raid group)
        -----------------------------------------------------------
        for set = 1, 8 do
            local heading =
                CreateFrame("Frame", "ERFGroupHeader" .. set, containerFrame, "SecureGroupHeaderTemplate")
            -- the header births an AuraContainer per child SECURE-SIDE -- the only
            -- combat-legal container source (covers in-combat /reload and mid-combat
            -- roster growth). The containers file adopts it as the debuff shell.
            heading:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
            heading:SetAttribute("template", "SecureUnitButtonTemplate")
            heading:SetAttribute("templateType", "Button")
            heading:SetAttribute("initialConfigFunction", initConfig)
            heading:SetAttribute("point", initPoint)
            heading:SetAttribute("xOffset", initXOff)
            heading:SetAttribute("yOffset", initYOff)
            heading:SetAttribute("groupFilter", tostring(set))
            heading:SetAttribute("showRaid", true)
            heading:SetAttribute("showParty", true)
            heading:SetAttribute("showPlayer", true)
            heading:SetAttribute("showSolo", cfg.showWhenSolo or false)
            heading:SetAttribute("maxColumns", 1)
            heading:SetAttribute("unitsPerColumn", 5)

            heading:SetAttribute("sortMethod", "INDEX")

            -- Pre-create 5 buttons per group
            heading:SetAttribute("startingIndex", -4)
            heading:Show()
            heading:SetAttribute("startingIndex", 1)

            -- Window-phase secure styling only; the insecure visual bodies run
            -- in the deferred login pass (or the restyle-loop fallback).
            for index = 1, 5 do
                local button = heading[index]
                if button then
                    mod._StyleButtonSecure(button)
                    allButtons[#allButtons + 1] = button
                end
            end

            separatedHdrs[set] = heading
        end
    else
        -----------------------------------------------------------
        --  Flat header for merge-groups mode (all members in one grid)
        -----------------------------------------------------------
        mod._flatHeader = CreateFrame("Frame", "ERFFlatHeader", containerFrame, "SecureGroupHeaderTemplate")
        mod._flatHeader:SetAttribute("auraContainerTemplate", "CustomAuraContainerTemplate")
        mod._flatHeader:SetAttribute("template", "SecureUnitButtonTemplate")
        mod._flatHeader:SetAttribute("templateType", "Button")
        mod._flatHeader:SetAttribute("initialConfigFunction", initConfig)
        mod._flatHeader:SetAttribute("point", initPoint)
        mod._flatHeader:SetAttribute("xOffset", initXOff)
        mod._flatHeader:SetAttribute("yOffset", initYOff)
        mod._flatHeader:SetAttribute("groupFilter", "1,2,3,4,5,6,7,8")
        mod._flatHeader:SetAttribute("showRaid", true)
        mod._flatHeader:SetAttribute("showParty", true)
        mod._flatHeader:SetAttribute("showPlayer", true)
        mod._flatHeader:SetAttribute("showSolo", cfg.showWhenSolo or false)
        mod._flatHeader:SetAttribute("unitsPerColumn", 5)
        mod._flatHeader:SetAttribute("maxColumns", 8)
        mod._flatHeader:SetAttribute("columnSpacing", mod.RF_GroupSpacing(cfg))
        mod._flatHeader:SetAttribute("columnAnchorPoint", mod._RFColAnchor(initUnitGrowth, initGroupGrowth))
        mod._flatHeader:SetAttribute("sortMethod", "INDEX")

        -- Pre-create 40 buttons
        mod._flatHeader:SetAttribute("startingIndex", -39)
        mod._flatHeader:Show()
        mod._flatHeader:SetAttribute("startingIndex", 1)
        mod._flatHeader:Hide() -- start hidden; LayoutGroups shows the right headers

        -- Window-phase secure styling only; bodies run in the deferred pass.
        for index = 1, 40 do
            local button = mod._flatHeader[index]
            if button then
                mod._StyleButtonSecure(button)
                allButtons[#allButtons + 1] = button
                mod._flatButtons[#mod._flatButtons + 1] = button
            end
        end
    end
    if hid then containerFrame:Hide() end

    -- Freshly built headers need the current sort attributes.
    ApplySortToHeaders()
end

local function CreateHeaders()
    if containerFrame then return end

    local cfg = saved.profile

    -- Container frame for positioning (not secure, just holds headers)
    SetContainerFrame(CreateFrame("Frame", "CludesUIRaidFrameContainer", UIParent))
    containerFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    containerFrame:SetSize(1, 1)
    containerFrame:SetFrameStrata(mod._ResolveFrameStrata(false))
    containerFrame:Show()

    -- Group-number labels (1-8) for the real raid frames. Own (non-secure)
    -- FontStrings parented to the container; they track each group's first unit
    -- via relative anchoring (no SetPoint is ever issued on the secure headers).
    -- Shown only when showGroupNumbers is on (see ns._UpdateGroupNumbers).
    if not mod._groupNumberLabels then
        -- Overlay host at a high frame level: labels parented straight to the
        -- container render BENEATH the bars (buttons are its descendants); a
        -- high level within the same (LOW) strata lifts them on top.
        mod._groupNumberOverlay = CreateFrame("Frame", nil, containerFrame)
        mod._groupNumberOverlay:SetAllPoints(containerFrame)
        mod._groupNumberOverlay:SetFrameLevel(9000)
        mod._groupNumberLabels = {}
        for gi = 1, 8 do
            local labelFS = mod._groupNumberOverlay:CreateFontString(nil, "OVERLAY")
            labelFS:Hide()
            mod._groupNumberLabels[gi] = labelFS
        end
    end

    -- Build ONLY the active mode's header set; the inactive one materializes
    -- on the first Merge Groups flip (see ns._BuildHeaderSet above).
    mod._BuildHeaderSet((cfg.mergeGroups and true) or false)
end

-------------------------------------------------------------------------------
--  Layout groups
--  Two perpendicular axes: groupGrowth (where next group goes) and
--  unitGrowth (where next unit within a group goes). groupGrowth also accepts
--  the grid flow "DOWNRIGHT" (ns._RFGroupFlow): ns._RF_GRID_ROWS groups stack
--  down one column before the next column starts to the right, instead of one
--  continuous run.
-------------------------------------------------------------------------------
local MOVER_GROUPS = 4

-- The separated layout's group slot origins, refilled by every pass
-- (ns._RFGroupFlow's out table).
local groupFlowSlots = {}

-- Real-frame group numbers (1-8): mirror the preview labels onto the actual
-- frames when showGroupNumbers is on, anchoring each group's label to its
-- first populated unit (shared groupNumberSize/Color). Raid + separated-groups
-- only (merged has no per-group first unit). Combat-safe: called only from
-- LayoutGroups (early-returns in combat), SetPoints only our own FontStrings.
function mod._UpdateGroupNumbers()
    local labels = mod._groupNumberLabels
    if not labels then return end
    if InCombatLockdown() then return end
    local cfg = saved.profile
    if (not cfg.showGroupNumbers) or cfg.mergeGroups or (not IsInRaid()) then
        for g = 1, 8 do
            if labels[g] then labels[g]:Hide() end
        end
        return
    end
    -- Effective unit growth (mirror the LayoutGroups tier override)
    local unitGrowth = cfg.unitGrowth or "DOWN"
    local activeOv = mod._activeTierOverride
    if activeOv and activeOv.unitGrowth then unitGrowth = activeOv.unitGrowth end
    local vg = mod._VisibleGroups() or { true, true, true, true, true, true, false, false }
    local size = cfg.groupNumberSize or 10
    local gc = cfg.groupNumberColor or {}
    local ox = cfg.groupNumberOffsetX or 0
    local oy = cfg.groupNumberOffsetY or 0
    for set = 1, 8 do
        local labelFS = labels[set]
        local heading = separatedHdrs[set]
        local firstBtn
        if labelFS and heading and vg[set] ~= false then
            -- First populated unit of this group (empty-but-visible groups -> none)
            for index = 1, 5 do
                local button = heading[index]
                if button and button:IsShown() and button:GetAttribute("unit") then
                    firstBtn = button
                    break
                end
            end
        end
        if labelFS then
            if firstBtn then
                labelFS:ClearAllPoints()
                if unitGrowth == "DOWN" then
                    labelFS:SetPoint("BOTTOM", firstBtn, "TOP", ox, 4 + oy)
                elseif unitGrowth == "UP" then
                    labelFS:SetPoint("TOP", firstBtn, "BOTTOM", ox, -4 + oy)
                elseif unitGrowth == "RIGHT" then
                    labelFS:SetPoint("RIGHT", firstBtn, "LEFT", -3 + ox, oy)
                else -- LEFT
                    labelFS:SetPoint("LEFT", firstBtn, "RIGHT", 3 + ox, oy)
                end
                ApplyFont(labelFS, size) -- must precede SetText (FontString needs a font first)
                labelFS:SetText(tostring(set))
                labelFS:SetTextColor(gc.r or 1, gc.g or 1, gc.b or 1, gc.a or 0.75)
                labelFS:Show()
            else
                labelFS:Hide()
            end
        end
    end
end

-- Subgroups holding at least one raid member: [subgroup] = true.
local function FilledGroups()
    local tbl = {}
    for ri = 1, GetNumGroupMembers() or 0 do
        local _, _, sub = GetRaidRosterInfo(ri)
        if sub then tbl[sub] = true end
    end
    return tbl
end

-- Real layout work. Call only through LayoutGroups() below, which wraps this in a
-- coalescing re-entrancy guard. Mutating secure group headers here (Hide/Show/
-- SetAttribute) and resizing the container makes Blizzard re-anchor their children
-- synchronously, which can re-enter layout through our own hooks. Stored on ns.
mod._LayoutGroupsImpl = function()
    if not containerFrame then return end
    if InCombatLockdown() then return end

    local cfg = saved.profile
    local merged = cfg.mergeGroups
    -- Belt: any path that flips the mode without passing through ReloadFrames
    -- still gets its header set built before this tries to show it.
    mod._BuildHeaderSet((merged and true) or false)
    local groupGrowth = cfg.groupGrowth or "RIGHT"
    local unitGrowth = cfg.unitGrowth or "DOWN"
    -- Per-tier growth overrides
    local activeOv = mod._activeTierOverride
    if activeOv then
        groupGrowth = activeOv.groupGrowth or groupGrowth
        unitGrowth = activeOv.unitGrowth or unitGrowth
    end
    -- Backstop: self-heal a same-axis pair that reached here without going
    -- through a guarded write site (see ns._RFEffectiveGrowth).
    unitGrowth, groupGrowth = mod._RFEffectiveGrowth(unitGrowth, groupGrowth, merged)
    -- Raid only: solo (Show When Solo) keeps the corner in both modes.
    local centered = IsInRaid() and mod._RFGroupCentered(activeOv, groupGrowth)
    local bw = PixelSnap(mod._activeSizeW or cfg.frameWidth or 72)
    local bh = PixelSnap(mod._activeSizeH or cfg.frameHeight or 46)
    local cs = mod.RF_CellSpacing(cfg)
    local gs = mod.RF_GroupSpacing(cfg)

    -- Header attributes for unit growth direction
    local hdrPoint, hdrXOff, hdrYOff = mod._RFHeaderPoint(unitGrowth, cs)

    -- Column anchor: where next column of 5 goes (perpendicular to unit growth)
    local colAnchor = mod._RFColAnchor(unitGrowth, groupGrowth)

    -- Group bounding box: size of one group along each axis
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end

    -- Build visible groups filter string from settings
    local vg = mod._VisibleGroups() or { true, true, true, true, true, true, false, false }
    -- Whether this layout applied the Mythic cap (the zone and difficulty checks compare against it).
    mod._rfLaidMythic = vg == mod._mythicGroups

    if merged then
        ---------------------------------------------------------------
        --  Merge-groups mode: single flat header, all members in one grid
        ---------------------------------------------------------------
        -- Hide separated headers
        for set = 1, 8 do
            local heading = separatedHdrs[set]
            if heading and heading:IsShown() then heading:Hide() end
        end

        -- Build groupFilter from visible groups
        local gfParts = {}
        for index = 1, 8 do
            if vg[index] ~= false then gfParts[#gfParts + 1] = tostring(index) end
        end
        local gfStr = table.concat(gfParts, ",")

        -- Configure flat header layout attributes
        if mod._flatHeader then
            -- Blizzard's header anchors its first button at the corner where
            -- "point" and "columnAnchorPoint" meet, then grows away from it --
            -- same corner ns._RFGrowthCorner names for separated headers. A
            -- fixed TOPLEFT here left the rendered grid offset from the
            -- container/mover box whenever growth pinned a different corner.
            -- Centered pins an edge midpoint instead: the header sizes itself to
            -- its shown columns in the secure update, so it stays centered on
            -- that point through mid-combat roster changes with no re-anchor.
            local hdrCorner = mod._RFGrowthCorner(unitGrowth, groupGrowth, centered)
            mod._flatHeader:ClearAllPoints()
            mod._flatHeader:SetPoint(hdrCorner, containerFrame, hdrCorner, 0, 0)
            local layoutChanged = false
            -- While Self Position owns the merged header (whole-raid nameList,
            -- applied by ApplySortToHeaders at the end of this pass), a
            -- groupFilter write here would fight its clear on every pass. Cache
            -- the string instead -- ApplySortToHeaders restores it whenever the
            -- nameList bails on unresolved names. Role + Prioritize Class and
            -- Sort By = FrameSort own it the same way.
            mod._flatGfStr = gfStr
            local selfOwnsHeader = (
                cfg.showSelfFirst
                or cfg.showSelfLast
                or (cfg.prioritizeClass == true and cfg.sortMode == "ROLE")
                or cfg.sortMode == "FRAMESORT"
            ) and IsInRaid()
            if not selfOwnsHeader and mod._flatHeader:GetAttribute("groupFilter") ~= gfStr then
                mod._flatHeader:SetAttribute("groupFilter", gfStr)
            end
            if
                mod._flatHeader:GetAttribute("point") ~= hdrPoint
                or mod._flatHeader:GetAttribute("xOffset") ~= hdrXOff
                or mod._flatHeader:GetAttribute("yOffset") ~= hdrYOff
                or mod._flatHeader:GetAttribute("columnAnchorPoint") ~= colAnchor
            then
                -- Clear child anchors before changing layout direction
                local ci, childFrame = 1, mod._flatHeader:GetAttribute("child1")
                while childFrame do
                    childFrame:ClearAllPoints()
                    ci = ci + 1
                    childFrame = mod._flatHeader:GetAttribute("child" .. ci)
                end
                mod._flatHeader:SetAttribute("point", hdrPoint)
                mod._flatHeader:SetAttribute("xOffset", hdrXOff)
                mod._flatHeader:SetAttribute("yOffset", hdrYOff)
                mod._flatHeader:SetAttribute("columnAnchorPoint", colAnchor)
                layoutChanged = true
            end
            if mod._flatHeader:GetAttribute("columnSpacing") ~= gs then
                mod._flatHeader:SetAttribute("columnSpacing", gs)
            end
            if layoutChanged and mod._flatHeader:IsShown() then
                mod._flatHeader:Hide()
                mod._flatHeader:Show()
            elseif not mod._flatHeader:IsShown() then
                mod._flatHeader:Show()
            end
        end
    else
        ---------------------------------------------------------------
        --  Per-group mode: 8 separated headers
        ---------------------------------------------------------------
        -- Hide flat header
        if mod._flatHeader and mod._flatHeader:IsShown() then mod._flatHeader:Hide() end

        -- Group slot origins along the growth flow: a plain direction is one
        -- continuous run, the grid flow ("Down and then Right") stacks
        -- ns._RF_GRID_ROWS groups per column. Eight slots are generated (up to
        -- 8 visible groups) but only the four the box is sized for
        -- (MOVER_GROUPS) set the normalization origin, so a group past the box
        -- keeps the same per-slot step instead of rescaling everything in front
        -- of it.
        local slots, minX, maxY = mod._RFGroupFlow(groupGrowth, groupW, groupH, gs, 8, groupFlowSlots)

        -- For UP/LEFT unit growth, pin each header by the corner its units
        -- grow away from: the offset moves (x, y) to that cell edge and the
        -- matching corner anchors there, so the group fills its cell. A
        -- TOPLEFT anchor for these directions displaces the frames a full
        -- group height/width outside the container, mismatching preview/mover.
        local hdrAnchor = "TOPLEFT"
        local hdrOffX, hdrOffY = 0, 0
        if unitGrowth == "UP" then
            hdrAnchor = "BOTTOMLEFT"
            hdrOffY = -groupH
        end
        if unitGrowth == "LEFT" then
            hdrAnchor = "TOPRIGHT"
            hdrOffX = groupW
        end

        -- "Hide Empty Groups": collapse memberless subgroups so the remaining
        -- groups close ranks (1/2/3/6 instead of a gap at 4/5). Real frames
        -- only; needs live raid roster data, so skipped outside a raid
        -- (GetRaidRosterInfo returns nil there -> would hide every group).
        -- Skipped while the group state hides the set too: a hidden header
        -- ignores the roster, so one hidden here would stay empty if the
        -- visibility driver shows the set mid-fight (the shown pass collapses).
        local occupied
        if cfg.hideEmptyGroups ~= false and IsInRaid() and mod._RFVisWanted() then
            occupied = FilledGroups()
        end

        local visSlot = 0 -- running counter for visible groups (collapses gaps)
        local groupOrder = cfg.customGroupOrder and mod._RFValidatedGroupOrder(cfg.groupOrder)

        -- Center Groups: shift the whole run by half the box space it leaves
        -- free. The run ends at the last shown slot holding members, so empty
        -- trailing headers (Hide Empty Groups off) do not push it out of the
        -- box. Same show test as the loop below; a group that gets its first
        -- member in combat is placed after combat, like Hide Empty Groups.
        local shiftX, shiftY = 0, 0
        if centered then
            local occ = occupied or FilledGroups()
            local num, isShown = 0, 0
            for slot = 1, 8 do
                local set = groupOrder and groupOrder[slot] or slot
                if separatedHdrs[set] and vg[set] ~= false and not (occupied and not occupied[set]) then
                    isShown = isShown + 1
                    if occ[set] then num = isShown end
                end
            end
            shiftX, shiftY = mod._RFCenterShift(slots, num)
        end
        for slot = 1, 8 do
            local set = groupOrder and groupOrder[slot] or slot
            local heading = separatedHdrs[set]
            if heading then
                if vg[set] == false or (occupied and not occupied[set]) then
                    if heading:IsShown() then heading:Hide() end
                else
                    local posX = PixelSnap(slots[visSlot][1] - minX + hdrOffX) + shiftX
                    local posY = PixelSnap(slots[visSlot][2] - maxY + hdrOffY) + shiftY
                    visSlot = visSlot + 1

                    heading:ClearAllPoints()
                    heading:SetPoint(hdrAnchor, containerFrame, "TOPLEFT", posX, posY)
                    local layoutChanged = false
                    if
                        heading:GetAttribute("point") ~= hdrPoint
                        or heading:GetAttribute("xOffset") ~= hdrXOff
                        or heading:GetAttribute("yOffset") ~= hdrYOff
                    then
                        -- Clear child anchors before changing layout direction
                        local ci, childFrame = 1, heading:GetAttribute("child1")
                        while childFrame do
                            childFrame:ClearAllPoints()
                            ci = ci + 1
                            childFrame = heading:GetAttribute("child" .. ci)
                        end
                        heading:SetAttribute("point", hdrPoint)
                        heading:SetAttribute("xOffset", hdrXOff)
                        heading:SetAttribute("yOffset", hdrYOff)
                        layoutChanged = true
                    end
                    if layoutChanged and heading:IsShown() then
                        heading:Hide()
                        heading:Show()
                    elseif not heading:IsShown() then
                        heading:Show()
                    end
                end
            end
        end
    end

    -- Apply sort after all headers are positioned
    ApplySortToHeaders()
    -- Which layout the headers now carry (shown: full; hidden: native), for
    -- UpdateVisibility to re-lay them when the set shows or hides.
    mod._rfRaidLaidVis = mod._RFVisWanted()

    -- Container size for unlock mode's mover. Merged mode's
    -- columnAnchorPoint is always perpendicular to unitGrowth (colAnchor above),
    -- so its actual render axis follows unitGrowth, not the literal groupGrowth
    -- (which can share unitGrowth's axis; Blizzard's header can't express that as
    -- a column direction). Keying the box off groupGrowth there mismatches the
    -- box against what merged mode really renders. Separated mode has no such
    -- header constraint and renders along groupGrowth literally, so it reads the
    -- same formula every other size consumer uses (ns._RFFootprint).
    local totalW, totalH
    if merged then
        if unitGrowth == "DOWN" or unitGrowth == "UP" then
            totalW = MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs
            totalH = groupH
        else
            totalW = groupW
            totalH = MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs
        end
    else
        totalW, totalH = mod._RFFootprint(bw, bh, unitGrowth, groupGrowth, cs, gs)
    end
    containerFrame:SetSize(PixelSnap(totalW), PixelSnap(totalH))

    -- Snap the container's screen position to the pixel grid. Skip when
    -- element-anchored: ApplyAnchorPosition already pixel-snaps, and a
    -- TOPLEFT re-anchor here would fight the anchor cascade.
    if
        not InCombatLockdown()
        and not (CUI.IsUnlockAnchored and CUI.IsUnlockAnchored("RF_RaidFrames"))
    then
        local l = containerFrame:GetLeft()
        local t = containerFrame:GetTop()
        if l and t then
            local snappedL = PixelSnap(l)
            local snappedT = PixelSnap(t)
            if abs(l - snappedL) > 0.01 or abs(t - snappedT) > 0.01 then
                containerFrame:ClearAllPoints()
                containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", snappedL, snappedT)
            end
        end
    end

    -- Update real-frame group numbers now that all headers are positioned.
    mod._UpdateGroupNumbers()
    mod.RF_SyncCompact(false)
end

-- Coalescing re-entrancy guard: a re-entrant LayoutGroups() call is NOT dropped
-- (would strand stale frames) -- it marks the pass dirty and the in-flight call
-- re-runs on return, bounded to 3 passes so a non-converging header feedback
-- loop (SetAttribute/SetSize -> engine re-anchors children -> our hook -> here)
-- can't spin into a watchdog kill. pcall clears the busy flag on error and
-- rethrows, so one error can't freeze every future layout. State on ns.
local function LayoutGroups()
    if mod._inLayoutGroups then
        mod._layoutGroupsDirty = true
        return
    end
    mod._inLayoutGroups = true
    local passes = 0
    repeat
        mod._layoutGroupsDirty = false
        passes = passes + 1
        local success, err = pcall(mod._LayoutGroupsImpl)
        if not success then
            mod._inLayoutGroups = false
            return geterrorhandler()(err)
        end
    until (not mod._layoutGroupsDirty) or passes >= 3
    mod._inLayoutGroups = false
    -- Cap reached with work still pending: a genuine non-converging relayout loop.
    -- The guard kept it from freezing the client; surface it once (out of combat)
    -- so it stays diagnosable instead of silently masking a real bug.
    if mod._layoutGroupsDirty and not mod._layoutLoopWarned and not InCombatLockdown() then
        mod._layoutLoopWarned = true
        print(
            "|cffff5555CludesUI Raid & Party Frames:|r layout did not settle after 3 passes; "
                .. "a re-entrant loop was bounded. Please report this if frames look wrong."
        )
    end
end

Inner.CreateHeaders, Inner.LayoutGroups, Inner.MOVER_GROUPS = CreateHeaders, LayoutGroups, MOVER_GROUPS
Inner.broken = false
