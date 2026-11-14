if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
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
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local Pix = CludesUI.PP

local ERB, GetPrimaryPowerType = Inner.ERB, Inner.GetPrimaryPowerType
local GetSecondaryResource, DEFAULTS = Inner.GetSecondaryResource, Inner.DEFAULTS
local IsVerticalOrientation, NormalizeAnchorKey = Inner.IsVerticalOrientation, Inner.NormalizeAnchorKey
local ShouldShowBar, ShouldShowSecondary = Inner.ShouldShowBar, Inner.ShouldShowSecondary

local mainFrame
Inner.mainFrameSetters[#Inner.mainFrameSetters + 1] = function(val)
    mainFrame = val
end
local healthBar
Inner.healthBarSetters[#Inner.healthBarSetters + 1] = function(val)
    healthBar = val
end
local primaryBar
Inner.primaryBarSetters[#Inner.primaryBarSetters + 1] = function(val)
    primaryBar = val
end
local secondaryFrame
Inner.secondaryFrameSetters[#Inner.secondaryFrameSetters + 1] = function(val)
    secondaryFrame = val
end
local castBarFrame
Inner.castBarFrameSetters[#Inner.castBarFrameSetters + 1] = function(val)
    castBarFrame = val
end

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
function mod.ERB_GroupSettingOn(p)
    p = p or (ERB.db and ERB.db.profile)
    return (p and p.general and p.general.classicBorderAll and mod.ERB_BarsBlizz()) and true or false
end
-- The bar whose Border Size the group wears: health, else power, else the
-- class resource (settings only, so the pads never flip at runtime).
function mod.ERB_GroupLeadCfg(p)
    if p.health and p.health.enabled then
        return p.health
    end
    if p.primary and p.primary.enabled ~= false then
        return p.primary
    end
    return p.secondary
end
-- A health, power or class resource bar's frame scale: the group's while
-- the setting is on under Classic WoW UI, the bar's own otherwise.
function mod.ERB_BarFrameK(conf)
    local p = ERB.db and ERB.db.profile
    if p and mod.ERB_GroupSettingOn(p) then
        return mod.ERB_ClassicFrameK(mod.ERB_GroupLeadCfg(p))
    end
    return mod.ERB_ClassicFrameK(conf)
end
-- The unlock-mode match root of a bar on its long axis (width links for a
-- horizontal bar, height links for a vertical one), following chained
-- links; the key itself when unmatched.
function mod.ERB_GroupMatchRoot(key, vertical)
    local get = vertical and CludesUI.GetHeightMatchTarget or CludesUI.GetWidthMatchTarget
    if not get then
        return key
    end
    for _ = 1, 16 do
        local nxt = get(key)
        if not nxt then
            break
        end
        -- A match with Extra Width/Height is not its target's length: root here.
        if CludesUI.GetMatchExtra and CludesUI.GetMatchExtra(vertical and "h" or "w", key) then
            break
        end
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
function mod.ERB_GroupCheck(p)
    if not p then
        return false, "count"
    end
    local g = p.general or DEFAULTS.profile.general
    local hp, pp, sp = p.health, p.primary, p.secondary
    local hasRes = GetSecondaryResource() ~= nil
    local es = mainFrame and mainFrame:GetEffectiveScale() or 1
    local tol = ((Pix and Pix.perfect) or 1) / es + 0.01
    local num, vert, len, root, sameRoot, sameLen = 0, nil, nil, nil, true, true
    for idx = 1, 3 do
        local inBar, val, l
        if idx == 1 then
            inBar = hp
                and hp.enabled
                and not (healthBar and healthBar._erbMouseTrack or (not healthBar and NormalizeAnchorKey(
                    hp.anchorTo
                ) == "mouse"))
                and hp.visibility ~= "never"
                and ShouldShowBar(hp) ~= "mouseover"
            val = hp and IsVerticalOrientation(hp.orientation or g.orientation)
            l = (hp and hp.width) or 214
        elseif idx == 2 then
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
        mod._erbGrpChk[idx] = inBar and true or false
        if inBar then
            num = num + 1
            val = val and true or false
            mod._erbGrpChkVert = val
            if vert == nil then
                vert = val
            elseif vert ~= val then
                return false, "orient"
            end
            local r = mod.ERB_GroupMatchRoot(mod._erbGrpMatchKeys[idx], val)
            if root == nil then
                root = r
            elseif root ~= r then
                sameRoot = false
            end
            if len == nil then
                len = l
            elseif math.abs(len - l) > tol then
                sameLen = false
            end
        end
    end
    if num < 2 then
        return false, "count"
    end
    if not (sameRoot or sameLen) then
        return false, "width"
    end
    return true
end
mod._erbGrpChk = {}
-- Whether the bars the group would hold already sit as one stack: every
-- shown member but one anchored (unlock mode) to another member along the
-- stacking axis, within a physical pixel either way. Turns Border Around All
-- on by default under Classic WoW UI (ERB_SeedStockBars); the runtime check
-- still decides each session whether the group frame holds.
function mod.ERB_BarsAnchoredTight(p)
    if not (p and mod.ERB_GroupCheck(p)) then
        return false
    end
    local anchors = CludesUIDB and CludesUIDB.unlockAnchors
    if not anchors then
        return false
    end
    local Prm = CludesUI.PP
    local ui = UIParent and UIParent:GetEffectiveScale() or 1
    if not ui or ui <= 0 then
        ui = 1
    end
    local tol = ((Prm and Prm.perfect) or 1) / ui + 0.01
    local keyList, members, vert = mod._erbGrpMatchKeys, mod._erbGrpChk, mod._erbGrpChkVert
    local total, linked = 0, 0
    for idx = 1, 3 do
        if members[idx] then
            total = total + 1
            local details = anchors[keyList[idx]]
            local targetUnit = details and details.target
            local inGroup = false
            for jdx = 1, 3 do
                if jdx ~= idx and members[jdx] and keyList[jdx] == targetUnit then
                    inGroup = true
                end
            end
            if inGroup then
                local sideName = CludesUI.GetUnlockAnchorSide(details)
                local onAxis
                if vert then
                    onAxis = (sideName == "LEFT" or sideName == "RIGHT")
                else
                    onAxis = (sideName == "TOP" or sideName == "BOTTOM")
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
    if not barFrame then
        return
    end
    grouped = grouped and true or nil
    if barFrame._classicGrouped == grouped then
        return
    end
    barFrame._classicGrouped = grouped
    if barFrame._classicArt then
        barFrame._classicArt:SetShown(not grouped)
    end
    -- Blizzard Style: the atlas panel, or a vertical bar's nine pieces.
    local pcs = barFrame._blizzBar9On and barFrame._blizzBar9
    if pcs then
        for idx = 1, 9 do
            pcs[idx]:SetShown(not grouped)
        end
    elseif barFrame._blizzBarBg then
        barFrame._blizzBarBg:SetShown(not grouped)
    end
end
-- Back to per-bar frames. `keepSig` (the evaluator's own fallbacks) keeps
-- the membership stamp, so the same members with no geometry change are not
-- re-judged on every visibility pass; nil (the setting turned off) clears it.
function mod.ERB_GroupRelease(keepSig)
    local hostRegion = mod._erbGroupHost
    if hostRegion then
        hostRegion:Hide()
        hostRegion._gFirst = nil
    end
    mod.ERB_GroupSuppress(healthBar, false)
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
        if mod._erbGroupActive then
            mod.ERB_GroupRelease()
        end
        return
    end
    -- Members must share one opacity (bar opacity, out-of-combat fade): the
    -- frame rides the first member's alpha. Part of the stamp, so a fade edge
    -- re-judges the group.
    local aEq, a0 = true, nil
    if mod._erbGrpH then
        a0 = mod.ResolveBarAlpha(_G._CURB_ResolveHealthCfg())
    end
    if mod._erbGrpP then
        local a = mod.ResolveBarAlpha(_G._CURB_ResolvePowerCfg())
        if a0 and math.abs(a - a0) > 0.01 then
            aEq = false
        end
        a0 = a0 or a
    end
    if mod._erbGrpS then
        local a = mod.ResolveBarAlpha(_G._CURB_ResolveSecondaryCfg())
        if a0 and math.abs(a - a0) > 0.01 then
            aEq = false
        end
    end
    local sig = (mod._erbGrpH and 1 or 0)
        + (mod._erbGrpP and 2 or 0)
        + (mod._erbGrpS and 4 or 0)
        + (aEq and 8 or 0)
    if sig == mod._erbGrpLastSig and not mod._erbGrpGeomDirty then
        return
    end
    mod._erbGrpLastSig = sig
    mod._erbGrpGeomDirty = nil
    local p = ERB.db and ERB.db.profile
    if not (p and mainFrame) then
        mod.ERB_GroupRelease(sig)
        return
    end
    local g = p.general or DEFAULTS.profile.general
    local m, lo, hi, num = mod._erbGrpMembers, mod._erbGrpLo, mod._erbGrpHi, 0
    local vertical
    for idx = 1, 3 do
        local f, val
        if idx == 1 and mod._erbGrpH then
            f = healthBar
            val = IsVerticalOrientation(p.health.orientation or g.orientation)
        elseif idx == 2 and mod._erbGrpP then
            f = primaryBar
            val = IsVerticalOrientation(p.primary.orientation or g.orientation)
        elseif idx == 3 and mod._erbGrpS then
            f = secondaryFrame
            val = (p.secondary.pipOrientation or "HORIZONTAL") ~= "HORIZONTAL"
        end
        if f then
            val = val and true or false
            if vertical == nil then
                vertical = val
            elseif vertical ~= val then
                mod.ERB_GroupRelease(sig)
                return
            end
            num = num + 1
            m[num] = f
        end
    end
    for idx = num + 1, 3 do
        m[idx] = nil
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
    for idx = 1, num do
        local f = m[idx]
        local l, r, t, b = f:GetLeft(), f:GetRight(), f:GetTop(), f:GetBottom()
        if not (l and r and t and b) then
            mod.ERB_GroupRelease(sig)
            mod._erbGrpGeomDirty = true
            return
        end
        if sec and (sec(l) or sec(r) or sec(t) or sec(b)) then
            mod._erbGrpGeomDirty = true
            return
        end
        local s1, s2, c1, c2 = l, r, b, t
        if vertical then
            s1, s2, c1, c2 = b, t, l, r
        end
        if idx == 1 then
            a1, a2 = s1, s2
        elseif math.abs(s1 - a1) > tol or math.abs(s2 - a2) > tol then
            mod.ERB_GroupRelease(sig)
            return
        end
        lo[idx], hi[idx] = c1, c2
        if c2 - c1 > thick then
            thick = c2 - c1
        end
    end
    -- Order along the cross axis (insertion sort on the member slots):
    -- horizontal bars stack top to bottom, vertical ones sit left to right.
    for idx = 2, num do
        local f, l1, h1 = m[idx], lo[idx], hi[idx]
        local jdx = idx - 1
        while jdx >= 1 and ((vertical and lo[jdx] > l1) or (not vertical and hi[jdx] < h1)) do
            m[jdx + 1], lo[jdx + 1], hi[jdx + 1] = m[jdx], lo[jdx], hi[jdx]
            jdx = jdx - 1
        end
        m[jdx + 1], lo[jdx + 1], hi[jdx + 1] = f, l1, h1
    end
    local CF = CludesUI.ClassicFrame
    local k = mod.ERB_BarFrameK(nil)
    local classic = mod.ERB_BarsClassic()
    -- The frame's reach across the stacking axis: the vanilla frame's
    -- overhangs, or the Blizzard panel's 3 + 7.
    local reach = classic and (CF and ((CF.OVER_T + CF.OVER_B) * k) or 0) or 10
    for idx = 2, num do
        local gap = vertical and (lo[idx] - hi[idx - 1]) or (lo[idx - 1] - hi[idx])
        if gap > thick + reach + tol then
            mod.ERB_GroupRelease(sig)
            return
        end
    end
    local first, last = m[1], m[num]
    local hostRegion = mod._erbGroupHost
    if not hostRegion then
        hostRegion = CreateFrame("Frame", nil, mainFrame)
        hostRegion:EnableMouse(false)
        -- The union's extent moved without a pass of ours (an anchor cascade
        -- sliding one member): look again next frame.
        hostRegion:SetScript("OnSizeChanged", mod.ERB_GroupDirty)
        mod._erbGroupHost = hostRegion
    end
    if hostRegion._gFirst ~= first or hostRegion._gLast ~= last then
        hostRegion._gFirst, hostRegion._gLast = first, last
        -- A child of the first bar: its alpha, fade and hide carry the frame.
        if hostRegion:GetParent() ~= first then
            hostRegion:SetParent(first)
        end
        hostRegion:ClearAllPoints()
        hostRegion:SetPoint("TOPLEFT", first, "TOPLEFT", 0, 0)
        hostRegion:SetPoint("BOTTOMRIGHT", last, "BOTTOMRIGHT", 0, 0)
    end
    local lvl, minLvl = 0, nil
    for idx = 1, num do
        local fl = m[idx]:GetFrameLevel()
        if fl > lvl then
            lvl = fl
        end
        if not minLvl or fl < minLvl then
            minLvl = fl
        end
    end
    hostRegion._blizzVertical = vertical or nil
    if classic then
        -- The vanilla frame rides above every member (its art at +9).
        if hostRegion:GetFrameLevel() ~= lvl then
            hostRegion:SetFrameLevel(lvl)
        end
        local uw = vertical and (hi[num] - lo[1]) or (a2 - a1)
        local uh = vertical and (a2 - a1) or (hi[1] - lo[num])
        mod.ERB_ApplyClassicBarChrome(hostRegion, nil, uw, uh, vertical, k)
    else
        -- The Blizzard panel sits under every member's own textures (as a
        -- bar's panel does under its fill); the separators ride above.
        local below = math.max(0, minLvl - 1)
        if hostRegion:GetFrameLevel() ~= below then
            hostRegion:SetFrameLevel(below)
        end
        mod.ERB_ApplyBlizzGroupPanel(hostRegion, vertical, lvl + 9)
    end
    mod.ERB_GroupSeatSeparators(hostRegion, g, num, vertical)
    hostRegion:Show()
    mod.ERB_GroupSuppress(healthBar, mod._erbGrpH)
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
function mod.ERB_SeatBlizzPanel9(pcs, anchorFrame, vertical, details)
    local file = details.file or details.filename
    local l, r, t, b =
        details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
    local E = mod._erbGrpEdges[vertical and true or false]
    local GRP_U, GRP_V = mod._erbGrpU, mod._erbGrpV
    for idx = 1, 3 do -- screen column (left to right)
        for jdx = 1, 3 do -- screen row (top to bottom)
            local texture = pcs[(jdx - 1) * 3 + idx]
            texture:SetTexture(file)
            if vertical then
                -- Screen x runs down the art's rows, screen y up its
                -- columns (right to left): column i = art row band i,
                -- row j = art column band 4 - j.
                local ua = l + (r - l) * GRP_U[4 - jdx]
                local ub = l + (r - l) * GRP_U[5 - jdx]
                local va = t + (b - t) * GRP_V[idx]
                local vb = t + (b - t) * GRP_V[idx + 1]
                texture:SetTexCoord(ub, va, ua, va, ub, vb, ua, vb)
            else
                texture:SetTexCoord(
                    l + (r - l) * GRP_U[idx],
                    l + (r - l) * GRP_U[idx + 1],
                    t + (b - t) * GRP_V[jdx],
                    t + (b - t) * GRP_V[jdx + 1]
                )
            end
            local x1, x2, y1, y2 = E.x[idx], E.x[idx + 1], E.y[jdx], E.y[jdx + 1]
            texture:ClearAllPoints()
            texture:SetPoint("TOPLEFT", anchorFrame, y1[1] .. x1[1], x1[2], y1[2])
            texture:SetPoint("BOTTOMRIGHT", anchorFrame, y2[1] .. x2[1], x2[2], y2[2])
        end
    end
end
function mod.ERB_ApplyBlizzGroupPanel(hostRegion, vertical, sepLevel)
    local details = C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_BG)
    local pcs = hostRegion._blizzGrpPanel9
    if not pcs then
        pcs = {}
        for idx = 1, 9 do
            local t = hostRegion:CreateTexture(nil, "BACKGROUND", nil, -2)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            pcs[idx] = t
        end
        hostRegion._blizzGrpPanel9 = pcs
    end
    local sa = hostRegion._sepArt
    if not sa then
        sa = CreateFrame("Frame", nil, hostRegion)
        sa:EnableMouse(false)
        sa:SetAllPoints(hostRegion)
        hostRegion._sepArt = sa
    end
    if sa:GetFrameLevel() ~= sepLevel then
        sa:SetFrameLevel(sepLevel)
    end
    if not details then
        for idx = 1, 9 do
            pcs[idx]:Hide()
        end
        return
    end
    vertical = vertical and true or false
    if hostRegion._blizzGrpRot ~= vertical then
        hostRegion._blizzGrpRot = vertical
        mod.ERB_SeatBlizzPanel9(pcs, hostRegion, vertical, details)
    end
    for idx = 1, 9 do
        pcs[idx]:Show()
    end
end
-- Separator lines between the grouped bars (the Border Around All cog):
-- general.classicBorderAllSepSize physical pixels (nil = 1, 0 = none) in
-- classicBorderAllSepR/G/B (nil = black), centred in each gap and snapped to
-- whole physical pixels, on the group frame's art frame (above the fills,
-- like the frame). Runs on the evaluator's sorted members; textures made
-- once, re-seated per evaluation, spares hidden.
function mod.ERB_GroupSeatSeparators(hostRegion, g, num, vertical)
    local seps = hostRegion._seps
    if not seps then
        seps = {}
        hostRegion._seps = seps
    end
    local dim = g.classicBorderAllSepSize
    if dim == nil then
        dim = 1
    end
    local af = hostRegion._classicArt or hostRegion._sepArt
    local used = 0
    if af and dim > 0 then
        local m, lo, hi = mod._erbGrpMembers, mod._erbGrpLo, mod._erbGrpHi
        local px = ((Pix and Pix.perfect) or 1) / hostRegion:GetEffectiveScale()
        local t = dim * px
        local r, gr, b = g.classicBorderAllSepR or 0, g.classicBorderAllSepG or 0, g.classicBorderAllSepB or 0
        for idx = 1, num - 1 do
            used = idx
            local s = seps[idx]
            if not s then
                s = af:CreateTexture(nil, "OVERLAY", nil, 3)
                seps[idx] = s
            end
            s:SetColorTexture(r, gr, b, 1)
            -- Members are sorted top to bottom (horizontal bars) or left to
            -- right (vertical bars); the line hangs off the earlier one.
            local a = m[idx]
            local gap = vertical and (lo[idx + 1] - hi[idx]) or (lo[idx] - hi[idx + 1])
            local offset = math.floor(((gap - t) / 2) / px + 0.5) * px
            s:ClearAllPoints()
            if vertical then
                s:SetPoint("TOPLEFT", a, "TOPRIGHT", offset, 0)
                s:SetPoint("BOTTOMLEFT", a, "BOTTOMRIGHT", offset, 0)
                s:SetWidth(t)
            else
                s:SetPoint("TOPLEFT", a, "BOTTOMLEFT", 0, -offset)
                s:SetPoint("TOPRIGHT", a, "BOTTOMRIGHT", 0, -offset)
                s:SetHeight(t)
            end
            s:Show()
        end
    end
    for idx = used + 1, #seps do
        seps[idx]:Hide()
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
    if not (mod._erbGroupOn or mod._erbGroupActive) then
        return
    end
    mod._erbGrpGeomDirty = true
    if mod._erbGrpFlushPending then
        return
    end
    mod._erbGrpFlushPending = true
    C_Timer.After(0, mod.ERB_GroupFlush)
end

-- The panel art on `bg`: the atlas as is, or (vertical) the sheet file with
-- the atlas rect's corners rotated a quarter turn counter-clockwise (an
-- atlas cannot take texcoords). Memo on the orientation. (A live vertical
-- bar takes the nine-slice in ERB_ApplyBlizzBarChrome instead.)
function mod.ERB_SeatBlizzBarBg(backdrop, vertical)
    vertical = vertical and true or false
    if backdrop._blizzRot == vertical then
        return
    end
    local details = C_Texture.GetAtlasInfo(mod.ERB_BLIZZ_BAR_BG)
    if not details then
        return
    end
    backdrop._blizzRot = vertical
    if vertical then
        backdrop:SetTexture(details.file or details.filename)
        local l, r, t, b =
            details.leftTexCoord, details.rightTexCoord, details.topTexCoord, details.bottomTexCoord
        backdrop:SetTexCoord(r, t, l, t, r, b, l, b)
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
function mod.ERB_BlizzBarShadow(scrollBar, maskTex, fw, fh)
    if not scrollBar then
        return
    end
    local sh = scrollBar._blizzShadow
    if not sh then
        sh = {}
        scrollBar._blizzShadow = sh
        for idx = 1, 4 do
            local texture = scrollBar:CreateTexture(nil, "OVERLAY", nil, -3)
            texture:SetTexture("Interface\\Buttons\\WHITE8X8")
            if texture.SetSnapToPixelGrid then
                texture:SetSnapToPixelGrid(false)
                texture:SetTexelSnappingBias(0)
            end
            sh[idx] = texture
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
    if issecretvalue and (issecretvalue(wid) or issecretvalue(hgt)) then
        return
    end
    if not wid or wid <= 0 then
        wid = 100
    end
    if not hgt or hgt <= 0 then
        hgt = 10
    end
    local long, short = hgt, wid
    if vertical then
        long, short = wid, hgt
    end
    local a = math.max(2, math.floor(long * 0.2))
    local b = math.max(1, math.floor(long * 0.1))
    local e = math.max(2, math.floor(short * 0.15))
    for idx = 1, 4 do
        sh[idx]:ClearAllPoints()
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
    for idx = 1, 4 do
        sh[idx]:Show()
    end
    if maskTex and sh._mask ~= maskTex then
        for idx = 1, 4 do
            if sh._mask then
                pcall(sh[idx].RemoveMaskTexture, sh[idx], sh._mask)
            end
            sh[idx]:AddMaskTexture(maskTex)
        end
        sh._mask = maskTex
    end
end
-- Seat the row's bar-shape mask on one texture, once per texture object
-- (AddMaskTexture is additive).
function mod.ERB_MaskTex(texture, maskTex)
    if texture and maskTex and texture._blizzMasked ~= maskTex then
        texture:AddMaskTexture(maskTex)
        texture._blizzMasked = maskTex
    end
end
-- Pips and runes under the style: every texture a pip draws (backing, fill,
-- pixel-border strips, the inner bars the secret renderer and recharge
-- create) takes the row's bar-shape mask so the end pips round off with
-- the frame; middle pips sit inside the footprint's straight edges and are
-- unaffected. Stamps the mask on the pip so the lazy creation and
-- re-texture sites can re-seat (a path swap mints a new fill object); the
-- per-object memo makes every other call free.
function mod.ERB_MaskPip(pipTex, maskTex)
    if not (pipTex and maskTex) then
        return
    end
    pipTex._blizzMask = maskTex
    local M = mod.ERB_MaskTex
    M(pipTex._bg, maskTex)
    M(pipTex._fill, maskTex)
    local bf = pipTex._border and pipTex._border._frame
    local c = bf and Pix.GetBorders(bf)
    if c then
        M(c._top, maskTex)
        M(c._bottom, maskTex)
        M(c._left, maskTex)
        M(c._right, maskTex)
    end
    local scrollBar = pipTex._secretBar
    if scrollBar then
        M(scrollBar:GetStatusBarTexture(), maskTex)
    end
    scrollBar = pipTex._bandResetBar
    if scrollBar then
        M(scrollBar:GetStatusBarTexture(), maskTex)
    end
    scrollBar = pipTex._secretThreshBar
    if scrollBar then
        M(scrollBar:GetStatusBarTexture(), maskTex)
    end
    scrollBar = pipTex._rechargeBar
    if scrollBar then
        M(scrollBar:GetStatusBarTexture(), maskTex)
    end
    local bands = pipTex._bandBars
    if bands then
        for k = 1, #bands do
            M(bands[k]:GetStatusBarTexture(), maskTex)
        end
    end
end
-- Seat the host's bar-shape mask on `target`'s fill and backing (`target`
-- defaults to the host; the class resource frame passes its bar-type bar).
-- Memoized per texture object: a status bar texture path swap mints a new
-- fill object, and AddMaskTexture is additive.
function mod.ERB_SeatBlizzMask(hostRegion, targetUnit)
    local maskTex = hostRegion and hostRegion._blizzBarMask
    if not maskTex then
        return
    end
    targetUnit = targetUnit or hostRegion
    local fillTex = targetUnit.GetStatusBarTexture and targetUnit:GetStatusBarTexture()
    if fillTex and targetUnit._blizzMaskedFill ~= fillTex then
        fillTex:AddMaskTexture(maskTex)
        targetUnit._blizzMaskedFill = fillTex
    end
    local bgTex = targetUnit._bg
    if bgTex and targetUnit._blizzMaskedBg ~= bgTex then
        bgTex:AddMaskTexture(maskTex)
        targetUnit._blizzMaskedBg = bgTex
    end
end
-- First existing atlas for a piece, memoized (false = none available).
function mod.ERB_BlizzAtlas(key)
    local memo = mod._erbBlizzAtlasMemo
    local hit = memo[key]
    if hit ~= nil then
        return hit or nil
    end
    local entries = mod.ERB_CAST_BLIZZ[key]
    local found = false
    if entries and C_Texture and C_Texture.GetAtlasInfo then
        for idx = 1, #entries do
            if C_Texture.GetAtlasInfo(entries[idx]) then
                found = entries[idx]
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
function mod.ERB_CastIconW(cb)
    if cb.showIcon == false or mod.ERB_CastIconPortrait(cb) or mod.ERB_CastIconFree(cb) then
        return 0
    end
    local hgt = cb.height
    if mod.ERB_CastStyle() == "blizzard" and cb.showSpellText and mod.ERB_BlizzAtlas("textbox") then
        return hgt + 13
    end
    return hgt
end
-- Resolve lazily: Unit Frames can load after Resource Bars.
function mod.ERB_CastIconPortrait(cb)
    if not cb.iconOnPortrait or cb.showIcon == false then
        return nil
    end
    local uf = CludesUI._ModuleNS["CludesUIUnitFrames"]
    if uf and uf.UF_GetPlayerCastPortrait then
        return uf.UF_GetPlayerCastPortrait()
    end
end
-- Icon Size / Offset: a custom size or any offset takes the icon out of the
-- frame (ERB_CastIconW is 0) and it floats beside the bar with its own border.
-- The stock styles keep it inside their frame art.
function mod.ERB_CastIconFree(cb)
    if cb.showIcon == false or mod.ERB_CastIconPortrait(cb) or mod.ERB_CastStyle() ~= "cui" then
        return false
    end
    return (cb.iconSize or 0) > 0 or (cb.iconOffsetX or 0) ~= 0 or (cb.iconOffsetY or 0) ~= 0
end
-- Lays out a floating icon (live bar and options preview), or hides its border.
function mod.ERB_LayoutFreeCastIcon(iconFrame, hostRegion, cb, free)
    local Prm = CludesUI.PP
    if not free then
        if Prm.GetBorders(iconFrame) then
            Prm.HideBorder(iconFrame)
        end
        return
    end
    local dim = (cb.iconSize or 0) > 0 and cb.iconSize or cb.height
    iconFrame:SetSize(dim, dim)
    iconFrame:ClearAllPoints()
    if cb.iconOnRight then
        iconFrame:SetPoint("LEFT", hostRegion, "RIGHT", cb.iconOffsetX or 0, cb.iconOffsetY or 0)
    else
        iconFrame:SetPoint("RIGHT", hostRegion, "LEFT", cb.iconOffsetX or 0, cb.iconOffsetY or 0)
    end
    if (cb.borderSize or 0) > 0 then
        if not Prm.GetBorders(iconFrame) then
            Prm.CreateBorder(iconFrame, 0, 0, 0, 1, 1)
        end
        Prm.SetBorderColor(iconFrame, cb.borderR or 0, cb.borderG or 0, cb.borderB or 0, cb.borderA or 1)
        Prm.ShowBorder(iconFrame)
    elseif Prm.GetBorders(iconFrame) then
        Prm.HideBorder(iconFrame)
    end
end
-- Fill art for the current cast kind ("cast" | "channel" | "interrupted").
-- One field test when the style is off; a memo skips repeat atlas swaps.
function mod.ERB_SetBlizzCastFill(kindOf)
    local f = castBarFrame
    if not f or not f._blizzFill then
        return
    end
    if f._blizzFillKind == kindOf then
        return
    end
    local atlas = mod.ERB_BlizzAtlas(kindOf)
    if not atlas then
        return
    end
    f._blizzFillKind = kindOf
    f._bar:GetStatusBarTexture():SetAtlas(atlas)
end
-- Frame art around the bar plus, under Blizzard Style, the text box under it
-- (the spell name moves into the box, honouring the Spell Text side and
-- offsets); Classic WoW UI draws the vanilla frame alone. Rebuilt on every
-- BuildCastBar pass; regions are created once.
function mod.ERB_ApplyBlizzCastChrome(cb, barW)
    local f = castBarFrame
    if not f then
        return
    end
    local clip = f._barClip
    if not f._blizzFrame then
        -- Own host above the bar and icon (the CUI border child is hidden by
        -- its size-0 pass under this style, so the art cannot ride on it).
        local af = CreateFrame("Frame", nil, f)
        af:SetAllPoints(f)
        af:EnableMouse(false)
        f._blizzArtFrame = af
        local fr = af:CreateTexture(nil, "OVERLAY", nil, 2)
        if fr.SetSnapToPixelGrid then
            fr:SetSnapToPixelGrid(false)
            fr:SetTexelSnappingBias(0)
        end
        f._blizzFrame = fr
        local tb = f:CreateTexture(nil, "BACKGROUND", nil, -1)
        if tb.SetSnapToPixelGrid then
            tb:SetSnapToPixelGrid(false)
            tb:SetTexelSnappingBias(0)
        end
        f._blizzTextBox = tb
    end
    -- Same level the CUI border host uses (re-asserted: the bar's level follows its strata setting).
    f._blizzArtFrame:SetFrameLevel(f:GetFrameLevel() + 5)
    local fr, tb = f._blizzFrame, f._blizzTextBox
    if mod.ERB_CastClassic() then
        -- Classic WoW UI: the vanilla frame round the whole bar, icon
        -- included (the icon is part of the bar, so it sits inside the
        -- frame's window beside the fill and the frame wraps the bar's rect,
        -- not the fill's clip); no text box, the spell name stays on the bar
        -- where the text pass put it.
        mod.ERB_SeatClassicChrome(fr, f, cb.height, false, mod.ERB_ClassicFrameK(cb))
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
    local boxAtlas = cb.showSpellText and mod.ERB_BlizzAtlas("textbox")
    if boxAtlas then
        mod.ERB_StockAtlas(tb, boxAtlas)
        tb:ClearAllPoints()
        tb:SetPoint("TOPLEFT", clip, "BOTTOMLEFT", 0, 3)
        tb:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", 0, -13)
        tb:Show()
        local nameText = f._nameText
        local sideName = cb.spellTextSide or "left"
        local posX, posY = cb.spellTextX or 0, cb.spellTextY or 0
        nameText:ClearAllPoints()
        if sideName == "right" then
            nameText:SetJustifyH("RIGHT")
            nameText:SetPoint("RIGHT", tb, "RIGHT", -8 + posX, posY)
        elseif sideName == "center" then
            nameText:SetJustifyH("CENTER")
            nameText:SetPoint("CENTER", tb, "CENTER", posX, posY)
        else
            nameText:SetJustifyH("LEFT")
            nameText:SetPoint("LEFT", tb, "LEFT", 8 + posX, posY)
        end
        nameText:SetWidth(math.max(10, (barW or cb.width or 220) - 16))
        mod.ReflowFontString(nameText)
    else
        tb:Hide()
    end
end

Inner.broken = false
