if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_PreviewParty.lua
--
--  The party preview, the restore of the real frames and the fade-out for
--  unlock mode.
--  Reads the earlier preview files through ns and ns._previewInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._previewInternals
-- CUI_RaidFrames_Preview.lua or an earlier preview file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ipairs = ipairs
local wipe = wipe
local tinsert = table.insert
local UnitClass = UnitClass
local InCombatLockdown = InCombatLockdown
local CreateFrame = CreateFrame

local RF = mod._internals -- the table of the Raid Frames chain
local ApplyFont, LayoutGroups, PixelSnap = RF.ApplyFont, RF.LayoutGroups, RF.PixelSnap
local UpdateVisibility = mod.UpdateVisibility

local StopPvAuraTicker, CreatePreviewFrame = Inner.StopPvAuraTicker, Inner.CreatePreviewFrame
local ApplyPreviewData, previewHealthValues = Inner.ApplyPreviewData, Inner.previewHealthValues
local previewPowerValues, HidePreview = Inner.previewPowerValues, Inner.HidePreview

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of the table that holds its list, which hands the value to
-- every copy: db, PP and containerFrame are the Raid Frames chain's.
local saved
RF.dbSetters[#RF.dbSetters + 1] = function(val)
    saved = val
end
local containerFrame
RF.containerFrameSetters[#RF.containerFrameSetters + 1] = function(val)
    containerFrame = val
end
local previewActive = false
Inner.previewActiveSetters[#Inner.previewActiveSetters + 1] = function(val)
    previewActive = val
end

-------------------------------------------------------------------------------
--  Party preview (5-player, 1 group)
--  Fully separate from raid preview -- shares CreatePreviewFrame and
--  ApplyPreviewData via temp-swap pattern but has its own frame pool,
--  health values, role assignments, layout, and overlay container.
-------------------------------------------------------------------------------
mod._partyPvFrames = {}
mod._partyPvHV = {}
mod._partyPvPV = {}
mod._partyPvActive = false
mod._partyPvInit = false
mod.partyPvAbsorbValues = {}
mod.partyPvHealAbsorbValues = {}
mod.partyPvHealPredValues = {}
mod.partyPvReducedMaxHealth = {}
mod._partyPvRoles = {}
mod._partyPvCT = {}

local function BuildPartyPreviewRoles()
    for i = 1, 5 do
        mod._partyPvRoles[i] = nil
    end
    wipe(mod._partyPvCT)

    -- Effective role: the player's spec wins over a stale assigned role
    local playerRole = CludesUI.UnitEffectiveRole("player")
    if playerRole ~= "TANK" and playerRole ~= "HEALER" then
        playerRole = "DAMAGER"
    end

    -- Slot 1 = player
    mod._partyPvRoles[1] = playerRole
    local _, pct = UnitClass("player")
    mod._partyPvCT[1] = pct or "WARRIOR"
    mod._partyPvRoles._playerSlot = 1

    -- Fill remaining: 1 tank, 1 healer, 3 DPS total
    local needTank = (playerRole ~= "TANK") and 1 or 0
    local needHealer = (playerRole ~= "HEALER") and 1 or 0
    local tankIdx, healerIdx, dpsIdx = 1, 1, 1

    for i = 2, 5 do
        if needTank > 0 then
            mod._partyPvRoles[i] = "TANK"
            mod._partyPvCT[i] = mod._PV_TANK_CLASSES[tankIdx]
            tankIdx = (tankIdx % #mod._PV_TANK_CLASSES) + 1
            needTank = needTank - 1
        elseif needHealer > 0 then
            mod._partyPvRoles[i] = "HEALER"
            mod._partyPvCT[i] = mod._PV_HEALER_CLASSES[healerIdx]
            healerIdx = (healerIdx % #mod._PV_HEALER_CLASSES) + 1
            needHealer = needHealer - 1
        else
            mod._partyPvRoles[i] = "DAMAGER"
            mod._partyPvCT[i] = mod._PV_DPS_CLASSES[dpsIdx]
            dpsIdx = (dpsIdx % #mod._PV_DPS_CLASSES) + 1
        end
    end

    -- Sort by role order + self-first (reads party-specific settings)
    local sortMode = saved.profile.partySortMode or saved.profile.sortMode or "INDEX"
    local showSelfFirst = saved.profile.partyShowSelfFirst
    if showSelfFirst == nil then
        showSelfFirst = saved.profile.showSelfFirst
    end
    local selfLast = saved.profile.partySelfLast
    if selfLast == nil then
        selfLast = saved.profile.showSelfLast
    end
    if selfLast then
        showSelfFirst = true
    end -- self ordering active either way
    local prioritizeClass = saved.profile.partyPrioritizeClass
    if sortMode == "ROLE" or showSelfFirst or prioritizeClass then
        local set = {}
        for u = 1, 5 do
            set[u] = {
                role = mod._partyPvRoles[u],
                classToken = mod._partyPvCT[u],
                isPlayer = (u == 1),
                idx = u,
            }
        end
        if sortMode == "ROLE" or prioritizeClass then
            -- Mirror the live header order: role (optional primary) -> class (when
            -- Prioritize Class is on) -> original slot. Comparator matches
            -- _BuildPartyClassNameList so the preview replicates the real frames.
            local sortByRole = (sortMode == "ROLE")
            local roleOrder = saved.profile.partyRoleOrder
                or saved.profile.roleOrder
                or { "TANK", "HEALER", "DAMAGER" }
            local rolePri = {}
            for i, region in ipairs(roleOrder) do
                rolePri[region] = i
            end
            local classPri
            if prioritizeClass then
                classPri = {}
                local co = saved.profile.partyClassOrder or mod._GetDefaultClassOrder()
                for i, c in ipairs(co) do
                    classPri[c] = i
                end
            end
            table.sort(set, function(a, b)
                if sortByRole then
                    local ra, rb = rolePri[a.role] or 99, rolePri[b.role] or 99
                    if ra ~= rb then
                        return ra < rb
                    end
                end
                if classPri then
                    local ca, callback = classPri[a.classToken] or 99, classPri[b.classToken] or 99
                    if ca ~= callback then
                        return ca < callback
                    end
                end
                return a.idx < b.idx
            end)
        end
        if showSelfFirst then
            local playerPos
            for i, record in ipairs(set) do
                if record.isPlayer then
                    playerPos = i
                    break
                end
            end
            if playerPos then
                if selfLast and playerPos < #set then
                    local playerEntry = table.remove(set, playerPos)
                    set[#set + 1] = playerEntry
                elseif not selfLast and playerPos > 1 then
                    local playerEntry = table.remove(set, playerPos)
                    tinsert(set, 1, playerEntry)
                end
            end
        end
        for u = 1, 5 do
            mod._partyPvRoles[u] = set[u].role
            mod._partyPvCT[u] = set[u].classToken
            if set[u].isPlayer then
                mod._partyPvRoles._playerSlot = u
            end
        end
    end

    -- Random picks (only once per session)
    if not mod._partyPvRoles._randomized then
        mod._partyPvRoles._randomized = true
        local tanks = {}
        for i = 1, 5 do
            if mod._partyPvRoles[i] == "TANK" then
                tanks[#tanks + 1] = i
            end
        end
        mod._partyPvRoles._threatIndex = tanks[math.random(#tanks)] or 1
        -- Marker on the player (slot 1) so each of the four status indicators
        -- gets its own non-player frame (clean 1-per-frame showcase, no overlap).
        mod._partyPvRoles._markerSlot1 = 1
        mod._partyPvRoles._markerSlot2 = nil -- only 1 marker in 5-man
        local dispelTypes = { "Magic", "Curse", "Disease", "Poison", "" }
        mod._partyPvRoles._dispelMap = {}
        for i, dt in ipairs(dispelTypes) do
            mod._partyPvRoles._dispelMap[i] = dt
        end
        -- Status showcase: 1 dead, 1 offline, 1 AFK, 1 summon-accepted, one each on
        -- the four non-player slots (2-5). No ready-check ticks. (Incoming-rez isn't
        -- previewed here: a 5-man has only four non-player slots and they're all
        -- taken, so there's no room for a separate rez corpse the way the raid
        -- preview has one. The live indicator still shows on party frames.)
        local statusSlots = { 2, 3, 4, 5 }
        for i = #statusSlots, 2, -1 do
            local jdx = math.random(i)
            statusSlots[i], statusSlots[jdx] = statusSlots[jdx], statusSlots[i]
        end
        mod._partyPvRoles._deadSlot = statusSlots[1]
        mod._partyPvRoles._offlineSlot = statusSlots[2]
        mod._partyPvRoles._afkSlot = statusSlots[3]
        mod._partyPvRoles._readyCheck = { [statusSlots[4]] = "summon_accepted" }
    end
end

local function InitPartyPreviewHealthValues()
    if mod._partyPvInit then
        return
    end
    mod._partyPvInit = true
    for i = 1, 5 do
        mod._partyPvHV[i] = 40 + math.random(60)
        mod._partyPvPV[i] = 50 + math.random(50)
        mod.partyPvAbsorbValues[i] = 0
        mod.partyPvHealAbsorbValues[i] = 0
    end
    -- 1-2 shields
    local slot1 = math.random(5)
    mod.partyPvAbsorbValues[slot1] = 5 + math.random(25)
    if math.random() > 0.5 then
        local slot2 = math.random(5)
        if mod.partyPvAbsorbValues[slot2] == 0 then
            mod.partyPvAbsorbValues[slot2] = 3 + math.random(15)
        end
    end
    -- 1 heal absorb
    local haSlot = math.random(2, 5)
    mod.partyPvHealAbsorbValues[haSlot] = 20 + math.random(20)
    -- 1 heal prediction
    mod.partyPvHealPredValues = {}
    for i = 1, 5 do
        mod.partyPvHealPredValues[i] = 0
    end
    for i = 1, 5 do
        if mod._partyPvHV[i] < 90 then
            mod.partyPvHealPredValues[i] = 10 + math.random(20)
            break
        end
    end
    -- 1 reduced max health
    mod.partyPvReducedMaxHealth = {}
    for i = 1, 5 do
        mod.partyPvReducedMaxHealth[i] = 0
    end
    local rmhSlot = math.random(2, 5)
    mod.partyPvReducedMaxHealth[rmhSlot] = 0.10 + math.random() * 0.15
end

local function GetOrCreatePartyPvFrame(index)
    if mod._partyPvFrames[index] then
        return mod._partyPvFrames[index]
    end
    local frame = CreatePreviewFrame(index, true)
    frame._isParty = true
    -- Reparent from raid preview container to party overlay container
    if mod._partyOC then
        frame:SetParent(mod._partyOC)
    end
    mod._partyPvFrames[index] = frame
    return frame
end

-- Apply preview data with party-specific width/height override
-- The raid values ApplyPartyPreviewData overwrites for one call, kept to put back.
local savedHealth, savedPower = {}, {}

local function ApplyPartyPreviewData(frame, index)
    local s = saved.profile
    -- Use party proxy so ApplyPreviewData reads party-specific settings
    mod._previewSettingsOverride = mod._scaledPartyProxy

    -- Sandwich values sourced through the effective overlay (panel-closed
    -- values while a view swap is active); s stays live db.profile so the
    -- mutation+restore semantics are unchanged.
    local eff = mod._pvOverlayProxy or saved.profile
    local origW, origH = s.frameWidth, s.frameHeight
    -- The bars' width (a party portrait widens the frame after the restore).
    local ew, eh, _, eres = mod.RF_PartyDims(eff)
    s.frameWidth, s.frameHeight = ew - (eres or 0), eh

    -- Temporarily swap preview value tables so ApplyPreviewData reads party data
    local origAbsorb = mod.previewAbsorbValues
    local origHA = mod.previewHealAbsorbValues
    local origHP = mod.previewHealPredValues
    local origRMH = mod.previewReducedMaxHealth

    for i = 1, 5 do
        savedHealth[i], savedPower[i] = previewHealthValues[i], previewPowerValues[i]
        previewHealthValues[i] = mod._partyPvHV[i]
        previewPowerValues[i] = mod._partyPvPV[i]
    end
    mod.previewAbsorbValues = mod.partyPvAbsorbValues
    mod.previewHealAbsorbValues = mod.partyPvHealAbsorbValues
    mod.previewHealPredValues = mod.partyPvHealPredValues
    mod.previewReducedMaxHealth = mod.partyPvReducedMaxHealth

    ApplyPreviewData(frame, index, mod._partyPvRoles, mod._partyPvCT)

    -- Re-apply BM indicators with the party proxy so Auto Resize scales the
    -- preview indicators/auras live. CreatePreviewFrame applies them only once
    -- (at creation, with the raid proxy), so without this the party preview
    -- would never reflect the party scale. Index 1 matches the creation call.
    if frame._bmIconPool and mod.BM_ApplyPreviewIndicators then
        mod.BM_ApplyPreviewIndicators(frame, 1, mod._scaledPartyProxy)
    end

    -- Restore everything
    mod._previewSettingsOverride = nil
    s.frameWidth = origW
    s.frameHeight = origH
    for i = 1, 5 do
        previewHealthValues[i] = savedHealth[i]
        previewPowerValues[i] = savedPower[i]
    end
    mod.previewAbsorbValues = origAbsorb
    mod.previewHealAbsorbValues = origHA
    mod.previewHealPredValues = origHP
    mod.previewReducedMaxHealth = origRMH

    -- Party Frames kit: bar rects, art, spots and a mock portrait, after the
    -- restore above (nothing here may run inside that swap window).
    if frame.kit then
        -- Forced: the refresh above re-laid the bars out at the box's edges.
        mod.RF_ApplyPartyKit(frame, frame, mod._scaledPartyProxy, nil, true)
        local roles = mod._partyPvRoles
        -- (Greyed only while the preview actually shows that slot offline.)
        mod.RF_KitPreviewPortrait(
            frame,
            mod._partyPvCT[index],
            index == (roles._playerSlot or 1),
            mod._indicatorsVisible ~= false and index == roles._offlineSlot
        )
    elseif mod.RF_PtPreview then
        -- Party portrait: the frame takes the box width, the bars move beside
        -- the portrait, then a mock paint (same slots as the kit's).
        local roles = mod._partyPvRoles
        mod.RF_PtPreview(
            frame,
            mod._scaledPartyProxy,
            mod._partyPvCT[index],
            index == (roles._playerSlot or 1),
            mod._indicatorsVisible ~= false and index == roles._offlineSlot
        )
    end
end

-- Party overlay container (separate from raid overlay). Position is hardcoded
-- (see RefreshPartyPreview) -- not draggable, nothing saved to the profile.
mod._partyOC = nil

local function GetOrCreatePartyOverlayContainer()
    if mod._partyOC then
        return mod._partyOC
    end

    local oc = CreateFrame("Frame", nil, UIParent)
    oc:SetFrameStrata("FULLSCREEN_DIALOG")
    oc:SetFrameLevel(10)
    oc:SetClampedToScreen(true)
    oc:Hide()

    -- The raid preview window's look and title (CUI_RaidFrames_PreviewRaid.lua).
    mod.RF_StylePreviewWindow(oc)

    mod._partyOC = oc
    return oc
end

local function RefreshPartyPreview()
    if not mod._partyPvActive then
        return
    end
    if mod._RebuildPvOverlay then
        mod._RebuildPvOverlay()
    end
    -- Recompute party indicator/aura scale before applying preview data so the
    -- party preview reflects Auto Resize live (preview reads _scaledPartyProxy).
    if mod._UpdatePartyIndicatorScale then
        mod._UpdatePartyIndicatorScale()
    end
    local s = mod._pvOverlayProxy or saved.profile
    local pw, ph, pcs = mod.RF_PartyDims(s)
    local wid, hgt, spacing = PixelSnap(pw), PixelSnap(ph), PixelSnap(pcs)
    -- Party target frames along the stack open the frames' pitch, as on the real frames.
    local pitch = spacing + mod.PT_AlongPitch(s, s.partyShowTargets == true)
    local mode = saved.profile.previewMode or "overlay"

    BuildPartyPreviewRoles()

    -- "Hide Self": mirror the real party frames (showPlayer=false) by hiding the
    -- player's preview frame and reflowing the remaining members to fill the gap.
    -- The player's slot is whatever BuildPartyPreviewRoles resolved it to after
    -- Sort By + Self First/Last (NOT assumed to be slot 1).
    local hideSelf = s.partyHideSelf
    local playerSlot = mod._partyPvRoles._playerSlot or 1
    local shownCount = hideSelf and 4 or 5

    local isOverlay = (mode == "overlay")
    local anchorPad = isOverlay and 10 or 0
    local topExtra = isOverlay and 25 or 0 -- top space for the centered "Preview" title
    local unitGrowth = mod._PartyGrowth(s)
    local isVert = (unitGrowth == "DOWN" or unitGrowth == "UP")
    local totalW, totalH
    if isVert then
        totalW = wid
        totalH = hgt * shownCount + pitch * (shownCount - 1)
    else
        totalW = wid * shownCount + pitch * (shownCount - 1)
        totalH = hgt
    end

    -- Pets (Show Pets on the Party tab) beside the party frames, or beside each frame (Beside
    -- Owner), and the party target frames beside each frame (after Beside Owner pets on their
    -- side; pets beside the party frames clear them); the overlay grows to hold them.
    local ptSpec = mod.PT_PreviewSpec(s, wid, hgt)
    local petSpec = isOverlay and mod.PF_PreviewSpec(true, s, wid, hgt, spacing, totalW, totalH, ptSpec)
    if ptSpec and petSpec and petSpec.owner then
        ptSpec = mod.PT_PreviewSpec(s, wid, hgt, petSpec)
    end
    local padL, padT, padR, padB = 0, 0, 0, 0
    if petSpec and petSpec.owner then
        padL, padT, padR, padB = petSpec.padL, petSpec.padT, petSpec.padR, petSpec.padB
    elseif petSpec then
        padL = math.max(0, -petSpec.ox)
        padT = math.max(0, petSpec.oy)
        padR = math.max(0, petSpec.ox + petSpec.bw - totalW)
        padB = math.max(0, petSpec.bh - petSpec.oy - totalH)
    end
    if isOverlay and ptSpec then
        padL, padT = math.max(padL, ptSpec.padL), math.max(padT, ptSpec.padT)
        padR, padB = math.max(padR, ptSpec.padR), math.max(padB, ptSpec.padB)
    end
    -- Your own frame's target shows only with Include Own Target.
    local ptSkip = (not s.partyTargetIncludeSelf) and playerSlot or nil

    -- Determine parent frame: overlay container for overlay, UIParent for real
    local parentFrame
    if isOverlay then
        GetOrCreatePartyOverlayContainer()
        parentFrame = mod._partyOC
    else
        parentFrame = UIParent
        if mod._partyOC then
            mod._partyOC:Hide()
        end
    end

    local slot = 0 -- running layout position; skips the hidden player frame
    local lastF -- the last frame along the growth
    for i = 1, 5 do
        local frame = GetOrCreatePartyPvFrame(i)
        if hideSelf and i == playerSlot then
            frame:Hide()
        else
            lastF = frame
            if frame:GetParent() ~= parentFrame then
                frame:SetParent(parentFrame)
            end
            frame:SetFrameStrata(isOverlay and "FULLSCREEN_DIALOG" or "HIGH")
            frame:ClearAllPoints()
            if isVert then
                local yOff = slot * (hgt + pitch)
                if unitGrowth == "DOWN" then
                    frame:SetPoint(
                        "TOPLEFT",
                        parentFrame,
                        "TOPLEFT",
                        anchorPad + padL,
                        -anchorPad - topExtra - padT - yOff
                    )
                else
                    -- UP fills the same box from the bottom upward (positive
                    -- offsets); the container's extra top height creates the
                    -- title gap, so no per-frame correction is needed here.
                    frame:SetPoint(
                        "BOTTOMLEFT",
                        parentFrame,
                        "BOTTOMLEFT",
                        anchorPad + padL,
                        anchorPad + padB + yOff
                    )
                end
            else
                local xOff = slot * (wid + pitch)
                if unitGrowth == "LEFT" then
                    xOff = -xOff
                end
                if unitGrowth == "RIGHT" then
                    frame:SetPoint(
                        "TOPLEFT",
                        parentFrame,
                        "TOPLEFT",
                        anchorPad + padL + xOff,
                        -anchorPad - topExtra - padT
                    )
                else
                    frame:SetPoint(
                        "TOPRIGHT",
                        parentFrame,
                        "TOPRIGHT",
                        -anchorPad - padR + xOff,
                        -anchorPad - topExtra - padT
                    )
                end
            end
            ApplyPartyPreviewData(frame, i)
            frame:Show()
            slot = slot + 1
        end
    end

    -- Size and position overlay container
    if isOverlay and mod._partyOC then
        mod._partyOC:SetSize(
            totalW + padL + padR + anchorPad * 2,
            totalH + padT + padB + anchorPad * 2 + topExtra
        )
        mod._partyOC:SetFrameStrata("FULLSCREEN_DIALOG")
        mod._partyOC:SetFrameLevel(10)
        if mod._partyOC._title then
            ApplyFont(mod._partyOC._title, 13)
            mod._partyOC._title:SetText(CludesUI.L("Party Preview"):upper())
            mod._partyOC._title:SetTextColor(1, 1, 1, 0.9)
            mod._partyOC._title:Show()
        end
        -- Beside the options panel (not draggable, not saved).
        mod.RF_DockPreviewWindow(mod._partyOC)
        mod._partyOC:Show()
        -- Styled from the party settings, as the preview's own frames are.
        if petSpec and petSpec.owner then
            mod.PF_ShowOwnerPreview(petSpec, mod._scaledPartyProxy, mod._partyOC, lastF)
        elseif petSpec then
            mod.PF_ShowPreview(
                petSpec,
                mod._scaledPartyProxy,
                mod._partyOC,
                mod._partyOC,
                anchorPad + padL + petSpec.ox,
                -anchorPad - topExtra - padT + petSpec.oy
            )
        else
            mod.PF_HidePreview()
        end
        mod.PT_ShowPreview(ptSpec, s, mod._partyOC, ptSkip)
    end

    -- Real mode: anchor frames to the actual party container, mirroring the
    -- real layout's basePoint logic (_PositionPartySlots). Slot 0 sits at the
    -- container corner the growth direction moves AWAY from, so Flip Frame
    -- Growth keeps the stack bounded by the container instead of growing past
    -- it. A plain TOPLEFT anchor misaligned the flipped preview by a full
    -- stack height/width versus the edit-mode location.
    if mode == "real" and mod._partyContainerFrame then
        local place = s.partyUnlockPos
        -- Editing an override with a custom unlock mode: anchor the preview at the
        -- LAYER's recorded party-container position (a lightweight proxy frame stands
        -- in for the real container, which sits at the REAL spec's position).
        local anchorTo = mod._partyContainerFrame
        local se = mod._PvSessionElem and mod._PvSessionElem("RF_PartyFrames")
        if se and se.point then
            local proxy = mod._pvSessionPartyAnchor
            if not proxy then
                proxy = CreateFrame("Frame", nil, UIParent)
                mod._pvSessionPartyAnchor = proxy
            end
            proxy:SetSize(mod._partyContainerFrame:GetSize())
            proxy:ClearAllPoints()
            proxy:SetPoint(
                se.point,
                UIParent,
                se.relPoint or se.point,
                PixelSnap(se.x or 0),
                PixelSnap(se.y or 0)
            )
            anchorTo = proxy
            place = place or se
        end
        local cw, ch = anchorTo:GetSize()
        local realPets = mod.PF_PreviewSpec(true, s, wid, hgt, spacing, cw, ch, ptSpec)
        if realPets and realPets.owner then
            mod.PF_ShowOwnerPreview(realPets, mod._scaledPartyProxy, UIParent, lastF)
        elseif realPets then
            mod.PF_ShowPreview(realPets, mod._scaledPartyProxy, UIParent, anchorTo, realPets.ox, realPets.oy)
        else
            mod.PF_HidePreview()
        end
        if ptSpec and realPets and realPets.owner then
            ptSpec = mod.PT_PreviewSpec(s, wid, hgt, realPets)
        end
        mod.PT_ShowPreview(ptSpec, s, UIParent, ptSkip)
        if place then
            local stepX, stepY = 0, 0
            local basePoint = "TOPLEFT"
            if unitGrowth == "RIGHT" then
                stepX = wid + pitch
            elseif unitGrowth == "LEFT" then
                stepX = -(wid + pitch)
                basePoint = "TOPRIGHT"
            elseif unitGrowth == "UP" then
                stepY = hgt + pitch
                basePoint = "BOTTOMLEFT"
            else -- DOWN
                stepY = -(hgt + pitch)
            end
            -- Centered growth: mirror _PositionPartySlots, which shifts the stack by
            -- (5 - shown)/2 slots so the shown frames sit centered in the 5-slot
            -- container. The preview always shows a full party, so shown is 5, or 4
            -- with Hide Self (the real layout subtracts the hidden self the same way).
            local centerShift = 0
            if s.partyFlipGrowth == "centered" then
                centerShift = (5 - shownCount) / 2
            end
            local cShiftX = PixelSnap(stepX * centerShift)
            local cShiftY = PixelSnap(stepY * centerShift)
            local position = 0 -- running position; skips the hidden player frame
            for i = 1, 5 do
                local frame = mod._partyPvFrames[i]
                if frame then
                    if hideSelf and i == playerSlot then
                        frame:Hide()
                    else
                        frame:ClearAllPoints()
                        frame:SetPoint(
                            basePoint,
                            anchorTo,
                            basePoint,
                            PixelSnap(stepX * position) + cShiftX,
                            PixelSnap(stepY * position) + cShiftY
                        )
                        position = position + 1
                    end
                end
            end
        end
    end

    mod.RF_PreviewCompact(mod._partyPvFrames, mod._scaledPartyProxy, true, unitGrowth)
end

local function ShowPartyPreview()
    -- See ShowPreview: never engage the preview (which reparents the real
    -- containers under a hidden frame) unless the options window is open and we
    -- are out of combat. Guards against deferred post-close ShowPartyPreview.
    if not mod._testMode and not (CludesUI:IsShown()) then
        return
    end
    if InCombatLockdown() then
        return
    end
    -- Kill any active size preview
    if mod._sizePreviewTier then
        mod._sizePreviewTier = nil
        if mod._HideSizePreview then
            mod._HideSizePreview()
        end
    end
    if mod._partyPvActive then
        RefreshPartyPreview()
        return
    end
    local mode = saved.profile.previewMode or "overlay"
    if mode == "none" then
        return
    end

    mod._partyPvActive = true
    -- Hide the real containers via alpha (combat-reversible); see ShowPreview.
    -- Never reparent secure-header containers (the restore would be blocked in
    -- combat and strand the frames for the whole pull).
    mod._SetRealFramesPreviewHidden(true)
    if mode == "overlay" then
        GetOrCreatePartyOverlayContainer()
    end
    InitPartyPreviewHealthValues()
    BuildPartyPreviewRoles()
    RefreshPartyPreview()
end

-- skipRestore: leave the real frames parented to the hidden frame instead of
-- restoring them. Used on in-panel tab swaps where another preview shows on the
-- next frame -- restoring here would flash the real frames for one frame before
-- the deferred ShowPreview re-hides them. Panel close restores explicitly.
local function HidePartyPreview(skipRestore)
    if not mod._partyPvActive then
        return
    end
    mod.RF_PreviewCompact(nil, nil, true)
    -- Stop the aura ticker while still party-active so it clears the party aura
    -- icons (PvFrames resolves to the party set here), then deactivate.
    StopPvAuraTicker()
    mod._partyPvActive = false
    for i = 1, 5 do
        if mod._partyPvFrames[i] then
            mod._partyPvFrames[i]:Hide()
        end
    end
    if mod._partyOC then
        mod._partyOC:Hide()
    end
    mod.PF_HidePreview()
    mod.PT_HidePreview()
    if skipRestore then
        return
    end
    -- The containers were only alpha-hidden (never reparented or moved); restore
    -- is a combat-legal SetAlpha(1) plus dropping the mouse blockers. See
    -- HidePreview. No combat gate, no SetParent/SetPoint, no ns._restorePending.
    mod._SetRealFramesPreviewHidden(false)
    if not InCombatLockdown() then
        LayoutGroups()
        if mod._ApplyTierOffset then
            mod._ApplyTierOffset()
        end
    end
    UpdateVisibility()
    if mod._UpdatePartyVisibility then
        mod._UpdatePartyVisibility()
    end
end

mod.ShowPartyPreview = ShowPartyPreview
mod.HidePartyPreview = HidePartyPreview
mod.partyPvActive = function()
    return mod._partyPvActive
end

-- Guaranteed restore invariant. Ensures both real containers are parented to UIParent
-- and their visibility recomputed whenever no preview should be active (e.g. the
-- options panel just closed). Heals the "frames stuck hidden under the preview parent"
-- case even when the preview flags were left false by a skip-restore tab swap or a
-- post-close deferred ShowPreview. Defers to PLAYER_REGEN_ENABLED in combat
-- (reparenting secure-header containers is a protected action).
function mod.EnsureRealFramesRestored()
    if not containerFrame then
        return
    end
    -- Tear down any genuinely-active preview FIRST. HidePreview/HidePartyPreview
    -- now restore container alpha and drop the mouse blockers via combat-legal
    -- ops only (SetAlpha on our containers; Hide/SetParent on our own non-secure
    -- preview frames), so they never defer anything.
    if previewActive then
        HidePreview()
    end
    if mod._partyPvActive then
        HidePartyPreview()
    end
    -- Hard guarantee: force both real containers fully opaque and drop any mouse
    -- blockers, unconditionally. SetAlpha is not protected, so this is valid in
    -- combat and heals the "left alpha-hidden with the flags already false" cases
    -- (skip-restore tab swap, combat-cancelled deferred Show). The containers are
    -- never reparented or moved anymore, so nothing protected needs deferral.
    mod._SetRealFramesPreviewHidden(false)
    -- The layout/visibility recompute below SetPoints/Shows secure headers, so
    -- out of combat only. The alpha restore above already makes the frames
    -- visible during combat.
    if InCombatLockdown() then
        return
    end
    UpdateVisibility()
    if mod._UpdatePartyVisibility then
        mod._UpdatePartyVisibility()
    end
end

-- Fade out overlay previews when entering unlock mode
do
    local FADE_DUR = 0.1
    local function FadeOutFrame(widget)
        if not widget or not widget:IsShown() then
            return
        end
        local startAlpha = widget:GetAlpha()
        local elapsed = 0
        widget:SetScript("OnUpdate", function(self, dt)
            elapsed = elapsed + dt
            if elapsed >= FADE_DUR then
                self:SetAlpha(0)
                self:Hide()
                self:SetScript("OnUpdate", nil)
                self:SetAlpha(startAlpha)
                return
            end
            self:SetAlpha(startAlpha * (1 - elapsed / FADE_DUR))
        end)
    end
    _G._CURF_UnlockModeOpen = function()
        FadeOutFrame(mod._overlayContainer)
        FadeOutFrame(mod._partyOC)
    end
end

Inner.broken = false
