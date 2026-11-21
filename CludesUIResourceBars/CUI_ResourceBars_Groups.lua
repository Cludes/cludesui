if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ResourceBars_Groups.lua
--
--  Border Around All groups, the Blizzard Style bar backing, shadow and
--  mask, and the chrome of the stock cast bar.
--  Reads the earlier Resource Bars files through ns and ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIResourceBars.lua or an earlier Resource Bars file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local Pix = CludesUI.PP

local ERB, GetPrimaryPowerType = Inner.ERB, Inner.GetPrimaryPowerType
local GetSecondaryResource, DEFAULTS = Inner.GetSecondaryResource, Inner.DEFAULTS
local IsVerticalOrientation, NormalizeAnchorKey = Inner.IsVerticalOrientation, Inner.NormalizeAnchorKey
local ShouldShowBar, ShouldShowSecondary = Inner.ShouldShowBar, Inner.ShouldShowSecondary

local mainFrame
Inner.mainFrameSetters[#Inner.mainFrameSetters + 1] = function(val) mainFrame = val end
local health
Inner.healthBarSetters[#Inner.healthBarSetters + 1] = function(val) health = val end
local primaryBar
Inner.primaryBarSetters[#Inner.primaryBarSetters + 1] = function(val) primaryBar = val end
local secondaryFrame
Inner.secondaryFrameSetters[#Inner.secondaryFrameSetters + 1] = function(val) secondaryFrame = val end
local castBarFrame
Inner.castBarFrameSetters[#Inner.castBarFrameSetters + 1] = function(val) castBarFrame = val end

-------------------------------------------------------------------------------
--  "Border Around All" (general.classicBorderAll, off by default; one key
--  for both stock styles, each style keeping its own value through the Style
--  page's per-style slots): one frame round the shown health, power and
--  class resource bars as a group instead of one per bar -- the vanilla
--  frame under Classic WoW UI, the personal resource display's panel under
--  Blizzard Style (ERB_ApplyBlizzGroupPanel). It holds only while at
--  least two bars show, share one orientation and one length (width-matched
--  to each other in unlock mode, or simply equal), their long-axis edges line
--  up within a physical pixel and no gap between them is wider than a bar
--  plus the frame's reach; otherwise every bar keeps its own frame (the
--  setting stays on and takes over again once they line up). The group frame
--  is our own host anchored from the first bar's TOPLEFT to the last bar's
--  BOTTOMRIGHT, so the layout engine keeps it on the bars through every move
--  with no Lua running; membership and eligibility are decided on the
--  visibility pass (which follows every rebuild and every visibility edge)
--  and on unlock moves, coalesced to one pass per frame. All three bars wear
--  the lead bar's Border Size while the setting is on, so a fallback's
--  per-bar frames and the size-match pads agree with the group frame. On ns.
-------------------------------------------------------------------------------
mod._erbGrpMatchKeys = { "ERB_Health", "ERB_Power", "ERB_ClassResource" }
mod._erbGrpMembers, mod._erbGrpLo, mod._erbGrpHi = {}, {}, {}
function mod.ERB_GroupSettingOn(profile)
    profile = profile or (ERB.db and ERB.db.profile)
    return (profile and profile.general and profile.general.classicBorderAll and mod.ERB_BarsBlizz()) and true
        or false
end
-- The bar whose Border Size the group wears: health, else power, else the
-- class resource (settings only, so the pads never flip at runtime).
function mod.ERB_GroupLeadCfg(profile)
    if profile.health and profile.health.enabled then return profile.health end
    if profile.primary and profile.primary.enabled ~= false then return profile.primary end
    return profile.secondary
end
-- A health, power or class resource bar's frame scale: the group's while
-- the setting is on under Classic WoW UI, the bar's own otherwise.
function mod.ERB_BarFrameK(conf)
    local profile = ERB.db and ERB.db.profile
    if profile and mod.ERB_GroupSettingOn(profile) then
        return mod.ERB_ClassicFrameK(mod.ERB_GroupLeadCfg(profile))
    end
    return mod.ERB_ClassicFrameK(conf)
end
-- The unlock-mode match root of a bar on its long axis (width links for a
-- horizontal bar, height links for a vertical one), following chained
-- links; the key itself when unmatched.
function mod.ERB_GroupMatchRoot(key, vertical)
    local get = vertical and CludesUI.GetHeightMatchTarget or CludesUI.GetWidthMatchTarget
    if not get then return key end
    for _ = 1, 16 do
        local nxt = get(key)
        if not nxt then break end
        -- A match with Extra Width/Height is not its target's length: root here.
        if CludesUI.GetMatchExtra and CludesUI.GetMatchExtra(vertical and "h" or "w", key) then break end
        key = nxt
    end
    return key
end
-- Whether the setting can apply to this profile on this character (the
-- options toggle's requirement): ok, or false and why ("count" = fewer than
-- two bars have something to show, "orient" = mixed orientations, "width" =
-- neither width-matched to each other nor the same length). A bar the group
-- could never hold does not count: one riding the cursor, shown only on
-- mouseover (revealed on its own) or set never to show.
function mod.ERB_GroupCheck(profile)
    if not profile then return false, "count" end
    local g = profile.general or DEFAULTS.profile.general
    local hp, pp, sp = profile.health, profile.primary, profile.secondary
    local hasRes = GetSecondaryResource() ~= nil
    local es = mainFrame and mainFrame:GetEffectiveScale() or 1
    local tol = ((Pix and Pix.perfect) or 1) / es + 0.01
    local num, vert, length, root, sameRoot, sameLen = 0, nil, nil, nil, true, true
    for index = 1, 3 do
        local inBar, val, l
        if index == 1 then
            inBar = hp
                and hp.enabled
                and not (health and health._erbMouseTrack or (not health and NormalizeAnchorKey(hp.anchorTo) == "mouse"))
                and hp.visibility ~= "never"
                and ShouldShowBar(hp) ~= "mouseover"
            val = hp and IsVerticalOrientation(hp.orientation or g.orientation)
            l = (hp and hp.width) or 214
        elseif index == 2 then
            inBar = pp
                and pp.enabled ~= false
                and GetPrimaryPowerType() ~= nil
                and not (sp and sp.hidePowerIfResource and sp.enabled ~= false and hasRes)
                and not (primaryBar and primaryBar._erbMouseTrack or (not primaryBar and NormalizeAnchorKey(
                    pp.anchorTo
                ) == "mouse"))
                and pp.visibility ~= "never"
                and ShouldShowBar(pp) ~= "mouseover"
            val = pp and IsVerticalOrientation(pp.orientation or g.orientation)
            l = (pp and pp.width) or 214
        else
            -- Blizzard Class Resource Art stands outside the group frame.
            inBar = sp
                and sp.enabled ~= false
                and hasRes
                and not mod._erbArtOn
                and not (secondaryFrame and secondaryFrame._erbMouseTrack or (not secondaryFrame and NormalizeAnchorKey(
                    sp.anchorTo
                ) == "mouse"))
                and sp.visibility ~= "never"
                and ShouldShowSecondary() ~= "mouseover"
            val = sp and (sp.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
            l = (sp and sp.pipWidth) or 214
        end
        -- Membership for ERB_BarsAnchoredTight (reused table).
        mod._erbGrpChk[index] = inBar and true or false
        if inBar then
            num = num + 1
            val = val and true or false
            mod._erbGrpChkVert = val
            if vert == nil then
                vert = val
            elseif vert ~= val then
                return false, "orient"
            end
            local region = mod.ERB_GroupMatchRoot(mod._erbGrpMatchKeys[index], val)
            if root == nil then
                root = region
            elseif root ~= region then
                sameRoot = false
            end
            if length == nil then
                length = l
            elseif math.abs(length - l) > tol then
                sameLen = false
            end
        end
    end
    if num < 2 then return false, "count" end
    if not (sameRoot or sameLen) then return false, "width" end
    return true
end
mod._erbGrpChk = {}
-- Whether the bars the group would hold already sit as one stack: every
-- shown member but one anchored (unlock mode) to another member along the
-- stacking axis, within a physical pixel either way. Turns Border Around All
-- on by default under Classic WoW UI (ERB_SeedStockBars); the runtime check
-- still decides each session whether the group frame holds.
function mod.ERB_BarsAnchoredTight(p)
    if not (p and mod.ERB_GroupCheck(p)) then return false end
    local anchors = CludesUIDB and CludesUIDB.unlockAnchors
    if not anchors then return false end
    local P = CludesUI.PP
    local ui = UIParent and UIParent:GetEffectiveScale() or 1
    if not ui or ui <= 0 then ui = 1 end
    local tol = ((P and P.perfect) or 1) / ui + 0.01
    local keyList, members, vert = mod._erbGrpMatchKeys, mod._erbGrpChk, mod._erbGrpChkVert
    local total, linked = 0, 0
    for index = 1, 3 do
        if members[index] then
            total = total + 1
            local details = anchors[keyList[index]]
            local target = details and details.target
            local inGroup = false
            for jdx = 1, 3 do
                if jdx ~= index and members[jdx] and keyList[jdx] == target then inGroup = true end
            end
            if inGroup then
                local side = CludesUI.GetUnlockAnchorSide(details)
                local onAxis
                if vert then
                    onAxis = (side == "LEFT" or side == "RIGHT")
                else
                    onAxis = (side == "TOP" or side == "BOTTOM")
                end
                if
                    onAxis
                    and math.abs(details.offsetX or 0) <= tol
                    and math.abs(details.offsetY or 0) <= tol
                then
                    linked = linked + 1
                end
            end
        end
    end
    return total >= 2 and linked == total - 1
end
-- A bar's own frame (the classic art, or the Blizzard Style panel) steps
-- aside while the group frame wears it (the per-bar pieces stay seated, so a
-- fallback is instant).
function mod.ERB_GroupSuppress(barFrame, grouped)
    if not barFrame then return end
    grouped = grouped and true or nil
    if barFrame._classicGrouped == grouped then return end
    barFrame._classicGrouped = grouped
    if barFrame._classicArt then barFrame._classicArt:SetShown(not grouped) end
    -- Blizzard Style: the atlas panel, or a vertical bar's nine pieces.
    local pcs = barFrame._blizzBar9On and barFrame._blizzBar9
    if pcs then
        for index = 1, 9 do
            pcs[index]:SetShown(not grouped)
        end
    elseif barFrame._blizzBarBg then
        barFrame._blizzBarBg:SetShown(not grouped)
    end
end
-- Back to per-bar frames. `keepSig` (the evaluator's own fallbacks) keeps
-- the membership stamp, so the same members with no geometry change are not
-- re-judged on every visibility pass; nil (the setting turned off) clears it.
function mod.ERB_GroupRelease(keepSig)
    local owner = mod._erbGroupHost
    if owner then
        owner:Hide()
        owner._gFirst = nil
    end
    mod.ERB_GroupSuppress(health, false)
    mod.ERB_GroupSuppress(primaryBar, false)
    mod.ERB_GroupSuppress(secondaryFrame, false)
    mod._erbGroupActive = false
    mod._erbGrpLastSig = keepSig
end
-- Decide and seat the group. Membership (ns._erbGrpH/P/S) comes from the
-- visibility pass; a pass with the same members and no geometry change is
-- a no-op. A secret rect keeps the last decision standing and an unresolved
-- one falls back, both retried on the next pass.
function mod.ERB_GroupEval()
    if not mod._erbGroupOn then
        if mod._erbGroupActive then mod.ERB_GroupRelease() end
        return
    end
    -- Members must share one opacity (bar opacity, out-of-combat fade): the
    -- frame rides the first member's alpha. Part of the stamp, so a fade edge
    -- re-judges the group.
    local aEq, a0 = true, nil
    if mod._erbGrpH then a0 = mod.ResolveBarAlpha(_G._CURB_ResolveHealthCfg()) end
    if mod._erbGrpP then
        local a = mod.ResolveBarAlpha(_G._CURB_ResolvePowerCfg())
        if a0 and math.abs(a - a0) > 0.01 then aEq = false end
        a0 = a0 or a
    end
    if mod._erbGrpS then
        local a = mod.ResolveBarAlpha(_G._CURB_ResolveSecondaryCfg())
        if a0 and math.abs(a - a0) > 0.01 then aEq = false end
    end
    local sig = (mod._erbGrpH and 1 or 0)
        + (mod._erbGrpP and 2 or 0)
        + (mod._erbGrpS and 4 or 0)
        + (aEq and 8 or 0)
    if sig == mod._erbGrpLastSig and not mod._erbGrpGeomDirty then return end
    mod._erbGrpLastSig = sig
    mod._erbGrpGeomDirty = nil
    local profile = ERB.db and ERB.db.profile
    if not (profile and mainFrame) then
        mod.ERB_GroupRelease(sig)
        return
    end
    local g = profile.general or DEFAULTS.profile.general
    local m, lo, hi, num = mod._erbGrpMembers, mod._erbGrpLo, mod._erbGrpHi, 0
    local vertical
    for index = 1, 3 do
        local frame, val
        if index == 1 and mod._erbGrpH then
            frame = health
            val = IsVerticalOrientation(profile.health.orientation or g.orientation)
        elseif index == 2 and mod._erbGrpP then
            frame = primaryBar
            val = IsVerticalOrientation(profile.primary.orientation or g.orientation)
        elseif index == 3 and mod._erbGrpS then
            frame = secondaryFrame
            val = (profile.secondary.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
        end
        if frame then
            val = val and true or false
            if vertical == nil then
                vertical = val
            elseif vertical ~= val then
                mod.ERB_GroupRelease(sig)
                return
            end
            num = num + 1
            m[num] = frame
        end
    end
    for index = num + 1, 3 do
        m[index] = nil
    end
    if num < 2 or not aEq then
        mod.ERB_GroupRelease(sig)
        return
    end
    -- Long-axis edges must line up (this also holds the lengths equal live);
    -- the cross-axis spans order the members and bound the gaps.
    local sec = issecretvalue
    local es = mainFrame:GetEffectiveScale()
    local tol = ((Pix and Pix.perfect) or 1) / es + 0.01
    local a1, a2, thick = nil, nil, 0
    for index = 1, num do
        local frame = m[index]
        local left, right, top, bottom = frame:GetLeft(), frame:GetRight(), frame:GetTop(), frame:GetBottom()
        if not (left and right and top and bottom) then
            mod.ERB_GroupRelease(sig)
            mod._erbGrpGeomDirty = true
            return
        end
        if sec and (sec(left) or sec(right) or sec(top) or sec(bottom)) then
            mod._erbGrpGeomDirty = true
            return
        end
        local s1, s2, c1, c2 = left, right, bottom, top
        if vertical then
            s1, s2, c1, c2 = bottom, top, left, right
        end
        if index == 1 then
            a1, a2 = s1, s2
        elseif math.abs(s1 - a1) > tol or math.abs(s2 - a2) > tol then
            mod.ERB_GroupRelease(sig)
            return
        end
        lo[index], hi[index] = c1, c2
        if c2 - c1 > thick then thick = c2 - c1 end
    end
    -- Order along the cross axis (insertion sort on the member slots):
    -- horizontal bars stack top to bottom, vertical ones sit left to right.
    for index = 2, num do
        local frame, l1, h1 = m[index], lo[index], hi[index]
        local jdx = index - 1
        while jdx >= 1 and ((vertical and lo[jdx] > l1) or (not vertical and hi[jdx] < h1)) do
            m[jdx + 1], lo[jdx + 1], hi[jdx + 1] = m[jdx], lo[jdx], hi[jdx]
            jdx = jdx - 1
        end
        m[jdx + 1], lo[jdx + 1], hi[jdx + 1] = frame, l1, h1
    end
    local CF = CludesUI.ClassicFrame
    local k = mod.ERB_BarFrameK(nil)
    local classic = mod.ERB_BarsClassic()
    -- The frame's reach across the stacking axis: the vanilla frame's
    -- overhangs, or the Blizzard panel's 3 + 7.
    local reach = classic and (CF and ((CF.OVER_T + CF.OVER_B) * k) or 0) or 10
    for index = 2, num do
        local gap = vertical and (lo[index] - hi[index - 1]) or (lo[index - 1] - hi[index])
        if gap > thick + reach + tol then
            mod.ERB_GroupRelease(sig)
            return
        end
    end
    local first, last = m[1], m[num]
    local owner = mod._erbGroupHost
    if not owner then
        owner = CreateFrame("Frame", nil, mainFrame)
        owner:EnableMouse(false)
        -- The union's extent moved without a pass of ours (an anchor cascade
        -- sliding one member): look again next frame.
        owner:SetScript("OnSizeChanged", mod.ERB_GroupDirty)
        mod._erbGroupHost = owner
    end
    if owner._gFirst ~= first or owner._gLast ~= last then
        owner._gFirst, owner._gLast = first, last
        -- A child of the first bar: its alpha, fade and hide carry the frame.
        if owner:GetParent() ~= first then owner:SetParent(first) end
        owner:ClearAllPoints()
        owner:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
        owner:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
    end
    local lvl, minLvl = 0, nil
    for index = 1, num do
        local fl = m[index]:GetFrameLevel()
        if fl > lvl then lvl = fl end
        if not minLvl or fl < minLvl then minLvl = fl end
    end
    owner._blizzVertical = vertical or nil
    if classic then
        -- The vanilla frame rides above every member (its art at +9).
        if owner:GetFrameLevel() ~= lvl then owner:SetFrameLevel(lvl) end
        local uw = vertical and (hi[num] - lo[1]) or (a2 - a1)
        local uh = vertical and (a2 - a1) or (hi[1] - lo[num])
        mod.ERB_ApplyClassicBarChrome(owner, nil, uw, uh, vertical, k)
    else
        -- The Blizzard panel sits under every member's own textures (as a
        -- bar's panel does under its fill); the separators ride above.
        local below = math.max(0, minLvl - 1)
        if owner:GetFrameLevel() ~= below then owner:SetFrameLevel(below) end
        mod.ERB_ApplyBlizzGroupPanel(owner, vertical, lvl + 9)
    end
    mod.ERB_GroupSeatSeparators(owner, g, num, vertical)
    owner:Show()
    mod.ERB_GroupSuppress(health, mod._erbGrpH)
    mod.ERB_GroupSuppress(primaryBar, mod._erbGrpP)
    mod.ERB_GroupSuppress(secondaryFrame, mod._erbGrpS)
    mod._erbGroupActive = true
end
-- Blizzard Style "Border Around All": the personal resource display's panel
-- round the whole group as a nine-slice, so its rims and drop shadow keep
-- their single-bar size however long and tall the group is (a bar's own
-- panel gets this from SetAtlas; a texcoord cut of the sheet does not, and a
-- panel stretched end to end slides its side rims in under the fills). The
-- atlas is 132x19: 2 columns left of the fill (soft edge, rim), 6 right of it
-- (rim, drop shadow), 3 rows above (soft edge, rim, inner shadow row) and 7
-- below (rim, drop shadow); the fill area stretches across the bars and the
-- gaps between them. A vertical group takes the art a quarter turn
-- counter-clockwise, as a vertical bar's panel does (3 left, 6 above, 7
-- right, 2 below). Under every member, as a bar's panel sits under its fill;
-- `sepLevel` seats the separators' art frame above every member.
mod._erbGrpU = { 0, 2 / 132, 126 / 132, 1 } -- art columns: left cap, fill, right cap
mod._erbGrpV = { 0, 3 / 19, 12 / 19, 1 } -- art rows: top cap, fill, bottom cap
-- Screen edges per orientation: { anchor side, offset } for the 4 x edges
-- (left to right) and the 4 y edges (top to bottom).
mod._erbGrpEdges = {
    [false] = {
        x = { { "LEFT", -2 }, { "LEFT", 0 }, { "RIGHT", 0 }, { "RIGHT", 6 } },
        y = { { "TOP", 3 }, { "TOP", 0 }, { "BOTTOM", 0 }, { "BOTTOM", -7 } },
    },
    [true] = {
        x = { { "LEFT", -3 }, { "LEFT", 0 }, { "RIGHT", 0 }, { "RIGHT", 7 } },
        y = { { "TOP", 6 }, { "TOP", 0 }, { "BOTTOM", 0 }, { "BOTTOM", -2 } },
    },
}
-- The nine pieces `pcs` seated round `anchor` (the group host, or a
-- vertical bar's fill rect), art from `info` (the panel atlas).
function mod.ERB_SeatBlizzPanel9(pcs, anchor, vertical, details)
    local file = details.file or details.filename
    local left, right, top, bottom =
        details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
    local E = mod._erbGrpEdges[vertical and true or false]
    local GRP_U, GRP_V = mod._erbGrpU, mod._erbGrpV
    for index = 1, 3 do -- screen column (left to right)
        for jdx = 1, 3 do -- screen row (top to bottom)
            local texture = pcs[(jdx - 1) * 3 + index]
            texture:SetTexture(file)
            if vertical then
                -- Screen x runs down the art's rows, screen y up its
                -- columns (right to left): column i = art row band i,
                -- row j = art column band 4 - j.
                local ua = left + (right - left) * GRP_U[4 - jdx]
                local ub = left + (right - left) * GRP_U[5 - jdx]
                local va = top + (bottom - top) * GRP_V[index]
                local vb = top + (bottom - top) * GRP_V[index + 1]
                texture:SetTexCoord(ub, va, ua, va, ub, vb, ua, vb)
            else
                texture:SetTexCoord(
                    left + (right - left) * GRP_U[index],
                    left + (right - left) * GRP_U[index + 1],
                    top + (bottom - top) * GRP_V[jdx],
                    top + (bottom - top) * GRP_V[jdx + 1]
                )
            end
            local x1, x2, y1, y2 = E.x[index], E.x[index + 1], E.y[jdx], E.y[jdx + 1]
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", anchor, y1[1] .. x1[1], x1[2], y1[2])
            texture:SetPoint("BOTTOMRIGHT", anchor, y2[1] .. x2[1], x2[2], y2[2])
        end
    end
end
function mod.ERB_ApplyBlizzGroupPanel(owner, vertical, sepLevel)
    local details = C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_BG)
    local pcs = owner._blizzGrpPanel9
    if not pcs then
        pcs = {}
        for index = 1, 9 do
            local tex = owner:CreateTexture(nil, "BACKGROUND", nil, -2)
            if tex.SetSnapToPixelGrid then
                tex:SetSnapToPixelGrid(false)
                tex:SetTexelSnappingBias(0)
            end
            pcs[index] = tex
        end
        owner._blizzGrpPanel9 = pcs
    end
    local sa = owner._sepArt
    if not sa then
        sa = CreateFrame("Frame", nil, owner)
        sa:EnableMouse(false)
        sa:SetAllPoints(owner)
        owner._sepArt = sa
    end
    if sa:GetFrameLevel() ~= sepLevel then sa:SetFrameLevel(sepLevel) end
    if not details then
        for index = 1, 9 do
            pcs[index]:Hide()
        end
        return
    end
    vertical = vertical and true or false
    if owner._blizzGrpRot ~= vertical then
        owner._blizzGrpRot = vertical
        mod.ERB_SeatBlizzPanel9(pcs, owner, vertical, details)
    end
    for index = 1, 9 do
        pcs[index]:Show()
    end
end
-- Separator lines between the grouped bars (the Border Around All cog):
-- general.classicBorderAllSepSize physical pixels (nil = 1, 0 = none) in
-- classicBorderAllSepR/G/B (nil = black), centred in each gap and snapped to
-- whole physical pixels, on the group frame's art frame (above the fills,
-- like the frame). Runs on the evaluator's sorted members; textures made
-- once, re-seated per evaluation, spares hidden.
function mod.ERB_GroupSeatSeparators(owner, g, num, vertical)
    local seps = owner._seps
    if not seps then
        seps = {}
        owner._seps = seps
    end
    local size = g.classicBorderAllSepSize
    if size == nil then size = 1 end
    local af = owner._classicArt or owner._sepArt
    local used = 0
    if af and size > 0 then
        local m, lo, hi = mod._erbGrpMembers, mod._erbGrpLo, mod._erbGrpHi
        local px = ((Pix and Pix.perfect) or 1) / owner:GetEffectiveScale()
        local t = size * px
        local red, green, blue =
            g.classicBorderAllSepR or 0, g.classicBorderAllSepG or 0, g.classicBorderAllSepB or 0
        for index = 1, num - 1 do
            used = index
            local s = seps[index]
            if not s then
                s = af:CreateTexture(nil, "OVERLAY", nil, 3)
                seps[index] = s
            end
            s:SetColorTexture(red, green, blue, 1)
            -- Members are sorted top to bottom (horizontal bars) or left to
            -- right (vertical bars); the line hangs off the earlier one.
            local a = m[index]
            local gap = vertical and (lo[index + 1] - hi[index]) or (lo[index] - hi[index + 1])
            local off = math.floor(((gap - t) / 2) / px + 0.5) * px
            s:ClearAllPoints()
            if vertical then
                s:SetPoint("TOPLEFT", a, "TOPRIGHT", off, 0)
                s:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT", off, 0)
                s:SetWidth(t)
            else
                s:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -off)
                s:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT", 0, -off)
                s:SetHeight(t)
            end
            s:Show()
        end
    end
    for index = used + 1, #seps do
        seps[index]:Hide()
    end
end
-- Coalesced re-evaluation (unlock moves, saved positions, the host's own
-- resize): one pass next frame. Idle while the setting is off.
function mod.ERB_GroupFlush()
    mod._erbGrpFlushPending = nil
    mod._erbGrpGeomDirty = true
    mod.ERB_GroupEval()
end
function mod.ERB_GroupDirty()
    if not (mod._erbGroupOn or mod._erbGroupActive) then return end
    mod._erbGrpGeomDirty = true
    if mod._erbGrpFlushPending then return end
    mod._erbGrpFlushPending = true
    C_Timer.After(0, mod.ERB_GroupFlush)
end

-- The panel art on `bg`: the atlas as is, or (vertical) the sheet file with
-- the atlas rect's corners rotated a quarter turn counter-clockwise (an
-- atlas cannot take texcoords). Memo on the orientation. (A live vertical
-- bar takes the nine-slice in ERB_ApplyBlizzBarChrome instead.)
function mod.ERB_SeatBlizzBarBg(backdrop, vertical)
    vertical = vertical and true or false
    if backdrop._blizzRot == vertical then return end
    local details = C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_BG)
    if not details then return end
    backdrop._blizzRot = vertical
    if vertical then
        backdrop:SetTexture(details.file or details.filename)
        local left, right, top, bottom =
            details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
        backdrop:SetTexCoord(right, top, left, top, right, bottom, left, bottom)
    else
        backdrop:SetAtlas(mod.ERB_BLIZZ_BAR_BG)
    end
end
-- Inner bevel under the style: the stock fill art bakes a dark edge into
-- its long sides (and a darker left end), which is what makes the stock
-- bar read as recessed inside the frame; the user's own texture has none,
-- so without this the bar reads as pasted over the frame. Four gradient
-- strips on the fill's StatusBar at OVERLAY -3 (above fill and backing,
-- under hash lines and text), the long edges carrying the bevel and the
-- short ends the end darkening whichever way the bar runs, masked to the
-- bar shape. Created once, re-sized on every chrome pass.
mod._erbShadeClear = CreateColor(0, 0, 0, 0)
mod._erbShadeTop = CreateColor(0, 0, 0, 0.55)
mod._erbShadeBottom = CreateColor(0, 0, 0, 0.30)
mod._erbShadeEnd = CreateColor(0, 0, 0, 0.35)
function mod.ERB_BlizzBarShadow(scrollBar, mask, fw, fh)
    if not scrollBar then return end
    local sh = scrollBar._blizzShadow
    if not sh then
        sh = {}
        scrollBar._blizzShadow = sh
        for index = 1, 4 do
            local texture = scrollBar:CreateTexture(nil, "OVERLAY", nil, -3)
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            if texture.SetSnapToPixelGrid then
                texture:SetSnapToPixelGrid(false)
                texture:SetTexelSnappingBias(0)
            end
            sh[index] = texture
        end
    end
    -- An explicit flag (the chrome pass's target orientation) wins over the
    -- bar's own, which lags on the pass that flips it.
    local vertical = scrollBar._blizzVertical
    if vertical == nil then
        vertical = scrollBar.GetOrientation and scrollBar:GetOrientation() == "VERTICAL"
    end
    local wid, hgt = fw or scrollBar:GetWidth(), fh or scrollBar:GetHeight()
    -- A bar carrying secret values reports secret sizes: leave the strips
    -- as they are (a later plain-sized pass lays them) rather than compare.
    if issecretvalue and (issecretvalue(wid) or issecretvalue(hgt)) then return end
    if not wid or wid <= 0 then wid = 100 end
    if not hgt or hgt <= 0 then hgt = 10 end
    local long, short = hgt, wid
    if vertical then
        long, short = wid, hgt
    end
    local a = math.max(2, math.floor(long * 0.2))
    local b = math.max(1, math.floor(long * 0.1))
    local e = math.max(2, math.floor(short * 0.15))
    for index = 1, 4 do
        sh[index]:ClearAllPoints()
    end
    -- VERTICAL gradients run bottom -> top, HORIZONTAL left -> right.
    if vertical then
        sh[1]:SetGradient("HORIZONTAL", mod._erbShadeTop, mod._erbShadeClear)
        sh[1]:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
        sh[1]:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
        sh[1]:SetWidth(a)
        sh[2]:SetGradient("HORIZONTAL", mod._erbShadeClear, mod._erbShadeBottom)
        sh[2]:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
        sh[2]:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        sh[2]:SetWidth(b)
        sh[3]:SetGradient("VERTICAL", mod._erbShadeClear, mod._erbShadeEnd)
        sh[3]:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
        sh[3]:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
        sh[3]:SetHeight(e)
        sh[4]:SetGradient("VERTICAL", mod._erbShadeEnd, mod._erbShadeClear)
        sh[4]:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
        sh[4]:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        sh[4]:SetHeight(e)
    else
        sh[1]:SetGradient("VERTICAL", mod._erbShadeClear, mod._erbShadeTop)
        sh[1]:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
        sh[1]:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
        sh[1]:SetHeight(a)
        sh[2]:SetGradient("VERTICAL", mod._erbShadeBottom, mod._erbShadeClear)
        sh[2]:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
        sh[2]:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        sh[2]:SetHeight(b)
        sh[3]:SetGradient("HORIZONTAL", mod._erbShadeEnd, mod._erbShadeClear)
        sh[3]:SetPoint("TOPLEFT", scrollBar, "TOPLEFT", 0, 0)
        sh[3]:SetPoint("BOTTOMLEFT", scrollBar, "BOTTOMLEFT", 0, 0)
        sh[3]:SetWidth(e)
        sh[4]:SetGradient("HORIZONTAL", mod._erbShadeClear, mod._erbShadeEnd)
        sh[4]:SetPoint("TOPRIGHT", scrollBar, "TOPRIGHT", 0, 0)
        sh[4]:SetPoint("BOTTOMRIGHT", scrollBar, "BOTTOMRIGHT", 0, 0)
        sh[4]:SetWidth(e)
    end
    for index = 1, 4 do
        sh[index]:Show()
    end
    if mask and sh._mask ~= mask then
        for index = 1, 4 do
            if sh._mask then pcall(sh[index].RemoveMaskTexture, sh[index], sh._mask) end
            sh[index]:AddMaskTexture(mask)
        end
        sh._mask = mask
    end
end
-- Seat the row's bar-shape mask on one texture, once per texture object
-- (AddMaskTexture is additive).
function mod.ERB_MaskTex(texture, mask)
    if texture and mask and texture._blizzMasked ~= mask then
        texture:AddMaskTexture(mask)
        texture._blizzMasked = mask
    end
end
-- Pips and runes under the style: every texture a pip draws (backing, fill,
-- pixel-border strips, the inner bars the secret renderer and recharge
-- create) takes the row's bar-shape mask so the end pips round off with
-- the frame; middle pips sit inside the footprint's straight edges and are
-- unaffected. Stamps the mask on the pip so the lazy creation and
-- re-texture sites can re-seat (a path swap mints a new fill object); the
-- per-object memo makes every other call free.
function mod.ERB_MaskPip(pip, mask)
    if not (pip and mask) then return end
    pip._blizzMask = mask
    local M = mod.ERB_MaskTex
    M(pip._bg, mask)
    M(pip._fill, mask)
    local bf = pip._border and pip._border._frame
    local c = bf and Pix.GetBorders(bf)
    if c then
        M(c._top, mask)
        M(c._bottom, mask)
        M(c._left, mask)
        M(c._right, mask)
    end
    local scrollBar = pip._secretBar
    if scrollBar then M(scrollBar:GetStatusBarTexture(), mask) end
    scrollBar = pip._bandResetBar
    if scrollBar then M(scrollBar:GetStatusBarTexture(), mask) end
    scrollBar = pip._secretThreshBar
    if scrollBar then M(scrollBar:GetStatusBarTexture(), mask) end
    scrollBar = pip._rechargeBar
    if scrollBar then M(scrollBar:GetStatusBarTexture(), mask) end
    local bands = pip._bandBars
    if bands then
        for k = 1, #bands do
            M(bands[k]:GetStatusBarTexture(), mask)
        end
    end
end
-- Seat the host's bar-shape mask on `target`'s fill and backing (`target`
-- defaults to the host; the class resource frame passes its bar-type bar).
-- Memoized per texture object: a status bar texture path swap mints a new
-- fill object, and AddMaskTexture is additive.
function mod.ERB_SeatBlizzMask(owner, target)
    local mask = owner and owner._blizzBarMask
    if not mask then return end
    target = target or owner
    local fillTex = target.GetStatusBarTexture and target:GetStatusBarTexture()
    if fillTex and target._blizzMaskedFill ~= fillTex then
        fillTex:AddMaskTexture(mask)
        target._blizzMaskedFill = fillTex
    end
    local bgTex = target._bg
    if bgTex and target._blizzMaskedBg ~= bgTex then
        bgTex:AddMaskTexture(mask)
        target._blizzMaskedBg = bgTex
    end
end
-- First existing atlas for a piece, memoized (false = none available).
function mod.ERB_BlizzAtlas(key)
    local memo = mod._erbBlizzAtlasMemo
    local hit = memo[key]
    if hit ~= nil then return hit or nil end
    local entries = mod.ERB_CAST_BLIZZ[key]
    local found = false
    if entries and C_Texture and C_Texture.GetAtlasInfo then
        for index = 1, #entries do
            if C_Texture.GetAtlasInfo(entries[index]) then
                found = entries[index]
                break
            end
        end
    end
    memo[key] = found
    return found or nil
end
-- Cast icon side (0 while the icon is off): the bar height, or under
-- Blizzard Style the bar plus the stock text box's 13px drop while the spell
-- text shows, so the icon spans bar and box (Classic WoW UI has no text box:
-- the icon stays a square of the bar height). The frame width, the fill
-- inset and the unlock sizing all take it from here.
function mod.ERB_CastIconW(callback)
    if callback.showIcon == false or mod.ERB_CastIconPortrait(callback) or mod.ERB_CastIconFree(callback) then
        return 0
    end
    local hgt = callback.height
    if mod.ERB_CastStyle() == "blizzard" and callback.showSpellText and mod.ERB_BlizzAtlas("textbox") then
        return hgt + 13
    end
    return hgt
end
-- Resolve lazily: Unit Frames can load after Resource Bars.
function mod.ERB_CastIconPortrait(callback)
    if not callback.iconOnPortrait or callback.showIcon == false then return nil end
    local uf = CludesUI._ModuleNS["CludesUIUnitFrames"]
    if uf and uf.UF_GetPlayerCastPortrait then return uf.UF_GetPlayerCastPortrait() end
end
-- Icon Size / Offset: a custom size or any offset takes the icon out of the
-- frame (ERB_CastIconW is 0) and it floats beside the bar with its own border.
-- The stock styles keep it inside their frame art.
function mod.ERB_CastIconFree(callback)
    if callback.showIcon == false or mod.ERB_CastIconPortrait(callback) or mod.ERB_CastStyle() ~= "cui" then
        return false
    end
    return (callback.iconSize or 0) > 0
        or (callback.iconOffsetX or 0) ~= 0
        or (callback.iconOffsetY or 0) ~= 0
end
-- Lays out a floating icon (live bar and options preview), or hides its border.
function mod.ERB_LayoutFreeCastIcon(iconFrame, owner, callback, free)
    local P = CludesUI.PP
    if not free then
        if P.GetBorders(iconFrame) then P.HideBorder(iconFrame) end
        return
    end
    local size = (callback.iconSize or 0) > 0 and callback.iconSize or callback.height
    iconFrame:SetSize(size, size)
    iconFrame:ClearAllPoints()
    if callback.iconOnRight then
        iconFrame:SetPoint("LEFT", owner, "RIGHT", callback.iconOffsetX or 0, callback.iconOffsetY or 0)
    else
        iconFrame:SetPoint("RIGHT", owner, "LEFT", callback.iconOffsetX or 0, callback.iconOffsetY or 0)
    end
    if (callback.borderSize or 0) > 0 then
        if not P.GetBorders(iconFrame) then P.CreateBorder(iconFrame, 0, 0, 0, 1, 1) end
        P.SetBorderColor(
            iconFrame,
            callback.borderR or 0,
            callback.borderG or 0,
            callback.borderB or 0,
            callback.borderA or 1
        )
        P.ShowBorder(iconFrame)
    elseif P.GetBorders(iconFrame) then
        P.HideBorder(iconFrame)
    end
end
-- Fill art for the current cast kind ("cast" | "channel" | "interrupted").
-- One field test when the style is off; a memo skips repeat atlas swaps.
function mod.ERB_SetBlizzCastFill(kind)
    local frame = castBarFrame
    if not frame or not frame._blizzFill then return end
    if frame._blizzFillKind == kind then return end
    local atlas = mod.ERB_BlizzAtlas(kind)
    if not atlas then return end
    frame._blizzFillKind = kind
    frame._bar:GetStatusBarTexture():SetAtlas(atlas)
end
-- Frame art around the bar plus, under Blizzard Style, the text box under it
-- (the spell name moves into the box, honouring the Spell Text side and
-- offsets); Classic WoW UI draws the vanilla frame alone. Rebuilt on every
-- BuildCastBar pass; regions are created once.
function mod.ERB_ApplyBlizzCastChrome(callback, barW)
    local frame = castBarFrame
    if not frame then return end
    local clip = frame._barClip
    if not frame._blizzFrame then
        -- Own host above the bar and icon (the CUI border child is hidden by
        -- its size-0 pass under this style, so the art cannot ride on it).
        local af = CreateFrame("Frame", nil, frame)
        af:SetAllPoints(frame)
        af:EnableMouse(false)
        frame._blizzArtFrame = af
        local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
        if fr.SetSnapToPixelGrid then
            fr:SetSnapToPixelGrid(false)
            fr:SetTexelSnappingBias(0)
        end
        frame._blizzFrame = fr
        local tb = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        if tb.SetSnapToPixelGrid then
            tb:SetSnapToPixelGrid(false)
            tb:SetTexelSnappingBias(0)
        end
        frame._blizzTextBox = tb
    end
    -- Same level the CUI border host uses (re-asserted: the bar's level follows its strata setting).
    frame._blizzArtFrame:SetFrameLevel(frame:GetFrameLevel() + 5)
    local fr, tb = frame._blizzFrame, frame._blizzTextBox
    if mod.ERB_CastClassic() then
        -- Classic WoW UI: the vanilla frame round the whole bar, icon
        -- included (the icon is part of the bar, so it sits inside the
        -- frame's window beside the fill and the frame wraps the bar's rect,
        -- not the fill's clip); no text box, the spell name stays on the bar
        -- where the text pass put it.
        mod.ERB_SeatClassicChrome(fr, frame, callback.height, false, mod.ERB_ClassicFrameK(callback))
        tb:Hide()
        return
    end
    local frameAtlas = mod.ERB_BlizzAtlas("frame")
    if frameAtlas then
        mod.ERB_StockAtlas(fr, frameAtlas)
        fr:ClearAllPoints()
        fr:SetPoint("TOPLEFT", clip, "TOPLEFT", -2, 2)
        fr:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 2, -2)
        fr:Show()
    else
        fr:Hide()
    end
    local boxAtlas = callback.showSpellText and mod.ERB_BlizzAtlas("textbox")
    if boxAtlas then
        mod.ERB_StockAtlas(tb, boxAtlas)
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", clip, "BOTTOMLEFT", 0, 3)
        tb:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, -13)
        tb:Show()
        local nameText = frame._nameText
        local side = callback.spellTextSide or "left"
        local posX, posY = callback.spellTextX or 0, callback.spellTextY or 0
        nameText:ClearAllPoints()
        if side == "right" then
            nameText:SetJustifyH("RIGHT")
            nameText:SetPoint("RIGHT", tb, "RIGHT", -8 + posX, posY)
        elseif side == "center" then
            nameText:SetJustifyH("CENTER")
            nameText:SetPoint("CENTER", tb, "CENTER", posX, posY)
        else
            nameText:SetJustifyH("LEFT")
            nameText:SetPoint("LEFT", tb, "LEFT", 8 + posX, posY)
        end
        nameText:SetWidth(math.max(10, (barW or callback.width or 220) - 16))
        mod.ReflowFontString(nameText)
    else
        tb:Hide()
    end
end

Inner.broken = false
