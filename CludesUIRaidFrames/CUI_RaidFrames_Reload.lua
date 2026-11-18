if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_RaidFrames_Reload.lua
--
--  ReloadFrames, the raid size tiers and the tier offset.
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
local min = math.min
local pairs = pairs
local ipairs = ipairs
local type = type
local UnitExists = UnitExists
local InCombatLockdown = InCombatLockdown

local allButtons, ApplyFont, eventFrame = Inner.allButtons, Inner.ApplyFont, Inner.eventFrame
local GetFFD, IsPowerBarEnabled, PixelSnap = Inner.GetFFD, Inner.IsPowerBarEnabled, Inner.PixelSnap
local ResolveHealthTexture, unitToButton = Inner.ResolveHealthTexture, Inner.unitToButton
local LayoutTopNameBar, StyleButton = Inner.LayoutTopNameBar, Inner.StyleButton
local RebuildUnitMap, UpdateAllButtons = Inner.RebuildUnitMap, Inner.UpdateAllButtons
local LayoutGroups, MOVER_GROUPS = Inner.LayoutGroups, Inner.MOVER_GROUPS

local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end
local containerFrame
Inner.containerFrameSetters[#Inner.containerFrameSetters + 1] = function(val)
    containerFrame = val
end

-- Assigned in CUI_RaidFrames_Visibility.lua (see SetRangeUpdate).
local RangeUpdate

-------------------------------------------------------------------------------
--  Reload: re-apply all settings to existing buttons
-------------------------------------------------------------------------------
-- skipButtons (login window only): run the layout/tier/proxy machinery but
-- skip the per-button restyle loop -- the insecure styling bodies run in the
-- deferred login pass, which then calls this again in full.
mod._emptyList = mod._emptyList or {}
local function ReloadFrames(skipButtons)
    local s = mod._scaledProfile
    -- Keep UNIT_FLAGS registration in lockstep with the combat-icon toggle so a
    -- disabled option listens for nothing (runs no event code).
    if mod.UpdateCombatEventRegistration then
        mod.UpdateCombatEventRegistration()
    end
    -- Hide Groups 5-8 in Mythic Raid hears difficulty switches only while on.
    if saved.profile.mythicRaidHideGroups then
        eventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    else
        eventFrame:UnregisterEvent("PLAYER_DIFFICULTY_CHANGED")
    end
    -- Rebuild dispel-color curves so custom-color edits take effect immediately.
    if mod._RebuildDispelCurves then
        mod._RebuildDispelCurves()
    end
    -- Recalculate active tier from current group size + overrides
    local numMembers = mod._GetEffectiveRaidSize()
    local prevW, prevH = mod._activeSizeW, mod._activeSizeH
    if numMembers > 0 then
        mod._activeSizeW, mod._activeSizeH = mod._GetRaidSizeFrameDimensions(numMembers)
        -- Active tier override (per-tier growth) via the single cascade authority.
        local _, activeTierOv = mod._RFResolveTierOverride(numMembers)
        mod._activeTierOverride = activeTierOv
    else
        mod._activeSizeW, mod._activeSizeH = nil, nil
        mod._activeTierOverride = nil
    end
    local bw = PixelSnap(mod._activeSizeW or s.frameWidth or 72)
    local bh = PixelSnap(mod._activeSizeH or s.frameHeight or 46)

    -- Auto-resize indicators: scale factor based on active tier vs base 20-man
    -- Read base dimensions from raw db.profile (not proxy, which returns active tier)
    local sizeScale = 1
    if mod._activeSizeW and mod._activeSizeH then
        local baseW = saved.profile.frameWidth or 72
        local baseH = saved.profile.frameHeight or 46
        local scale = math.min(mod._activeSizeW / baseW, mod._activeSizeH / baseH)
        sizeScale = math.max(math.min(scale, 1.5), 0.7)
    end
    -- Auto Resize Icons (two independent checkboxes): Tracked Buffs gates the
    -- Buff Manager scale; Indicators & Auras gates indicator/aura/text sizes.
    -- Tracked Buffs defaults on (nil treated as on) to preserve the prior
    -- hardcoded always-on behavior.
    mod._bmScale = (saved.profile.autoResizeTrackedBuffs ~= false) and sizeScale or 1
    mod._indicatorScale = saved.profile.autoResizeIndicators and sizeScale or 1
    if mod._RefreshProxyModes then
        mod._RefreshProxyModes()
    end

    -- Mode flips (Merge Groups toggle, profile swaps) can need a header set
    -- that was not built at login; materialize it before the restyle loop so
    -- the new buttons take this reload's styling like everything else.
    mod._BuildHeaderSet((saved.profile.mergeGroups and true) or false)

    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - powerH)
    local texPath = ResolveHealthTexture()

    for _, button in ipairs(skipButtons and mod._emptyList or allButtons) do
        local skinData = GetFFD(button)
        if not skinData.styled then
            mod._StyleButtonSecure(button)
            StyleButton(button)
        end

        -- Window/initialConfigFunction own sizes in combat; skipping here is
        -- safe (out of combat the resize applies normally).
        if not InCombatLockdown() then
            button:SetSize(bw, bh)
        end

        -- Health bar height/anchor + Top Name Bar. The helper reserves the top
        -- bar's height from the top of the health area and styles the bar.
        LayoutTopNameBar(s, bh, powerH, skinData.health, skinData.topNameBar, skinData.topNameBarBg, skinData.topNameBarText, skinData.power)
        if skinData.health then
            skinData.health:SetStatusBarTexture(texPath)
            skinData.health:GetStatusBarTexture():SetHorizTile(false)
            -- Re-anchor absorb clips to the new fill texture object
            if skinData.ReanchorAbsorbToFill then
                skinData.ReanchorAbsorbToFill()
            end
        end

        -- Background: through its stamped owner (dark-mode aware), AFTER the
        -- fill texture swap so the anchors bind the new fill edge. Stamps are
        -- cleared first so the restyle re-applies anchors + color; a direct
        -- SetColorTexture here is never overwritten by the stamped health tick.
        if skinData.bg then
            skinData._bgSt, skinData._bgA = nil, nil
            local u = button:GetAttribute("unit")
            if u and UnitExists(u) then
                mod._ApplyHealthBg(skinData, skinData.health, s, u)
            end
        end

        -- Power bar (always hide here; UpdateButton handles per-role show). This is a
        -- second writer of health height alongside UpdateButton's own cached transition
        -- (LayoutTopNameBar above sized health assuming power reserved), so drop the
        -- cache or UpdateAllButtons below sees applied == computed and never corrects it.
        skinData._appliedHidePower = nil
        if skinData.power then
            skinData.power:Hide()
            if powerH > 0 then
                skinData.power:SetHeight(powerH)
                skinData.power:SetStatusBarTexture(texPath)
                skinData.power:GetStatusBarTexture():SetHorizTile(false)
            end
        end
        if skinData.powerBg then
            skinData.powerBg:SetColorTexture(
                (s.powerBgColor or {}).r or 0,
                (s.powerBgColor or {}).g or 0,
                (s.powerBgColor or {}).b or 0,
                (s.powerBgDarkness or 70) / 100
            )
            skinData._pwBgTintType = nil
        end
        if skinData.UpdatePowerBorder then
            skinData.UpdatePowerBorder(true)
        end

        -- The texts: Power Text hidden with the bar above until UpdateAllButtons
        -- below shows it again; every text restyled and re-anchored (the full paint that
        -- follows fills them).
        if skinData.AnchorTexts then
            mod.RF_TextPowerHide(skinData)
            skinData.AnchorTexts()
        end

        -- Status text (DEAD/OFFLINE/AFK)
        if skinData.statusText then
            local stc = s.statusTextColor or { r = 1, g = 1, b = 1 }
            ApplyFont(skinData.statusText, s.statusTextSize or 14)
            skinData.statusText:SetTextColor(stc.r, stc.g, stc.b)
            if skinData.AnchorStatusText then
                skinData.AnchorStatusText()
            end
        end

        -- Role icon size + position
        if skinData.roleIcon then
            local riSz = PixelSnap(s.roleIconSize or 14)
            skinData.roleIcon:SetSize(riSz, riSz)
            if skinData.AnchorRoleIcon then
                skinData.AnchorRoleIcon()
            end
        end

        -- Leader icon size + position
        if skinData.leaderIcon then
            local liSz = PixelSnap(s.leaderIconSize or 14)
            skinData.leaderIcon:SetSize(liSz, liSz)
            skinData.leaderIcon:ClearAllPoints()
            local liPos = (s.leaderIconPosition or "top"):upper()
            skinData.leaderIcon:SetPoint(
                liPos,
                mod.RF_AnchorHost(skinData.health, s),
                liPos,
                s.leaderIconOffsetX or 0,
                s.leaderIconOffsetY or 0
            )
            -- Re-assert the host's strata/level above the border
            if skinData.leaderHost then
                mod.ApplyLeaderStrata(skinData.leaderHost)
            end
        end

        -- Raid marker size + position
        if skinData.raidMarker then
            local rmSz = PixelSnap(s.raidMarkerSize or 16)
            skinData.raidMarker:SetSize(rmSz, rmSz)
            if skinData.AnchorRaidMarker then
                skinData.AnchorRaidMarker()
            end
        end

        -- Ready check / summon size + position
        if skinData.readyCheck then
            local rcSz = PixelSnap(s.readyCheckSize or 20)
            skinData.readyCheck:SetSize(rcSz, rcSz)
            if skinData.AnchorReadyCheck then
                skinData.AnchorReadyCheck()
            end
        end

        -- Combat icon size + position
        if skinData.combatIcon then
            local cciSz = PixelSnap(s.combatIndicatorSize or 16)
            skinData.combatIcon:SetSize(cciSz, cciSz)
            if skinData.AnchorCombatIcon then
                skinData.AnchorCombatIcon()
            end
        end

        -- Ping marker size + position (overlay exists only after a first ping)
        if skinData.pingFrame then
            mod._RFAnchorPing(skinData)
        end
        if mod.RF_FvMissingAnchor then
            mod.RF_FvMissingAnchor(button, skinData)
        end

        -- Border
        if skinData.UpdateBorder then
            skinData.UpdateBorder()
        end
    end

    -- Re-layout headers (may switch between flat/grouped)
    LayoutGroups()
    -- Apply tier-based position offset
    if mod._ApplyTierOffset then
        mod._ApplyTierOffset()
    end
    RebuildUnitMap()
    UpdateAllButtons()
    -- Immediate range update so new buttons don't flash full alpha
    RangeUpdate()

    -- Friendly Boss Frames and Extra Frames inherit size/growth/spacing/
    -- border/text settings; restyle + re-anchor them with everything else
    -- (growth changes move the anchor points, not just the anchored-to header).
    if mod.FB_Apply then
        mod.FB_Apply()
    end
    if mod.XF_Apply then
        mod.XF_Apply()
    end
    -- Player Group Label follows the raid frame style.
    if mod.PG_Apply then
        mod.PG_Apply()
    end
    -- Pet frames (the ones styled from the raid settings restyle here, the rest in the party
    -- reload): the login window's pass skips them (OnEnable builds them once the party frames
    -- exist, which the Beside Owner pets need).
    if not skipButtons then
        mod.PF_Apply(true)
    end

    -- 12.1 aura containers reload with every real pass (direct call inside
    -- the body -- immune to the Options file's setup-time capture of ns.ReloadFrames).
    if mod.RFC_ReloadAll then
        mod.RFC_ReloadAll()
    end
end

mod.ReloadFrames = ReloadFrames
mod.PixelSnap = PixelSnap
mod._allButtons = allButtons
-- The raid unit map (RebuildUnitMap wipes it in place, so this stays live).
mod._raidUnitToButton = unitToButton

-- Global Dark Mode master: RF stores Dark Mode as a fill-color MODE
-- (healthColorMode == "dark"), not a boolean -- enabling remembers the prior
-- mode, disabling restores it, never clobbering a Classic/Custom choice. The
-- party override (party_healthColorMode, present only when the party color
-- section is decoupled) flips the same way. db is set at PLAYER_LOGIN; the
-- closures read it lazily.
CludesUI.RegisterDarkModeToggle({
    id = "raidFrames",
    isOn = function()
        return (saved and saved.profile and saved.profile.healthColorMode == "dark") or false
    end,
    setOn = function(enabled)
        if not (saved and saved.profile) then
            return
        end
        local p = saved.profile
        if enabled then
            if p.healthColorMode ~= "dark" then
                p._darkPrevHealthColorMode = p.healthColorMode or "class"
                p.healthColorMode = "dark"
            end
            if rawget(p, "party_healthColorMode") ~= nil and p.party_healthColorMode ~= "dark" then
                p._darkPrevPartyHealthColorMode = p.party_healthColorMode
                p.party_healthColorMode = "dark"
            end
            -- The party target frames' own Fill Color flips the same way.
            if p.partyTargetHealthColorMode ~= "dark" then
                p._darkPrevPartyTargetHealthColorMode = p.partyTargetHealthColorMode or "class"
                p.partyTargetHealthColorMode = "dark"
            end
        else
            if p.healthColorMode == "dark" then
                p.healthColorMode = p._darkPrevHealthColorMode or "class"
            end
            p._darkPrevHealthColorMode = nil
            if rawget(p, "party_healthColorMode") == "dark" then
                p.party_healthColorMode = p._darkPrevPartyHealthColorMode or "class"
            end
            p._darkPrevPartyHealthColorMode = nil
            if p.partyTargetHealthColorMode == "dark" then
                p.partyTargetHealthColorMode = p._darkPrevPartyTargetHealthColorMode or "class"
            end
            p._darkPrevPartyTargetHealthColorMode = nil
        end
        if mod.ReloadFrames then
            mod.ReloadFrames()
        end
        if mod.ReloadPartyFrames then
            mod.ReloadPartyFrames()
        end
    end,
})

-- Lightweight resize: only changes button/health/power dimensions + layout.
-- No texture, border, font, or anchor changes. Safe for slider hot path.
mod._ResizeButtons = function(wid, hgt)
    if InCombatLockdown() then
        return
    end
    local bw = PixelSnap(wid)
    local bh = PixelSnap(hgt)
    local s = saved.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - mod.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    local xfset = s.extraFrames
    for _, button in ipairs(allButtons) do
        local skinData = GetFFD(button)
        if skinData.styled then
            local xbw, xbh, xhealthH = bw, bh, healthH
            -- Extra Frames duplicates carry their size offset through the
            -- live slider path too (XF.Layout re-applies it on full reloads).
            if skinData._isExtra and xfset then
                xbw = PixelSnap(math.max(10, wid + (xfset.extraWidth or 0)))
                xbh = PixelSnap(math.max(10, hgt + (xfset.extraHeight or 0)))
                xhealthH = PixelSnap(xbh - mod.RF_HealthPowerInset(s, powerH))
            end
            button:SetSize(xbw, xbh)
            -- Full height when the power bar is hidden for this role (mirrors
            -- _ResizePartyButtons; avoids a dark strip on OFF-role units since
            -- d.power always exists). Top Name Bar reserves its height from the
            -- top (health top anchor stays -topBarH; only correct height here).
            if skinData.health then
                skinData.health:SetHeight(((skinData.power and skinData.power:IsShown()) and xhealthH or xbh) - topBarH)
            end
            mod.RF_TextNameWidth(skinData, xbw)
        end
    end
    mod._activeSizeW = wid
    mod._activeSizeH = hgt
    if mod._RefreshProxyModes then
        mod._RefreshProxyModes()
    end
    LayoutGroups()
    -- Container footprint may have changed: re-derive the growth-corner anchor
    -- so the pinned corner holds during live slider drags and the unlock
    -- framework's OnSizeChanged can never leave a stale centered position.
    if mod._ApplyTierOffset then
        mod._ApplyTierOffset()
    end
end

-- Lightweight party resize: only changes button/health/power dimensions + container.
-- No sort/self-first re-chain. Safe for slider hot path.
mod._ResizePartyButtons = function(wid, hgt)
    if InCombatLockdown() then
        return
    end
    if not mod._partyAllButtons then
        return
    end
    local bw = PixelSnap(wid)
    local bh = PixelSnap(hgt)
    local s = saved.profile
    local powerH = IsPowerBarEnabled(s) and PixelSnap(s.powerHeight or 4) or 0
    local healthH = PixelSnap(bh - mod.RF_HealthPowerInset(s, powerH))
    local topBarH = (s.topNameBarEnabled and PixelSnap(s.topNameBarHeight or 20)) or 0
    -- Auto Resize scale depends on frame size; recompute on this lightweight
    -- width/height slider path (which skips the full reload).
    if mod._UpdatePartyIndicatorScale then
        mod._UpdatePartyIndicatorScale()
    end
    local autoResize = s.partyAutoResizeIndicators
    -- The bars' width: an attached portrait takes its share of the box.
    local _, _, _, pres = mod.RF_PartyDims(s)
    local barW = bw - ((pres and pres > 0) and PixelSnap(pres) or 0)
    for _, button in ipairs(mod._partyAllButtons) do
        local skinData = GetFFD(button)
        if skinData.styled then
            button:SetSize(bw, bh)
            if skinData.kit then
                -- Party Frames kit: its own bar rects, spots and name width
                -- (Frame Scale drags land here).
                mod.RF_ApplyPartyKit(button, skinData, mod._scaledPartyProxy)
            else
                -- Use full height if power bar is hidden for this button's role; the
                -- Top Name Bar always reserves topBarH from the top.
                if skinData.health then
                    local hh = ((skinData.power and skinData.power:IsShown()) and healthH or bh) - topBarH
                    skinData.health:SetHeight(hh)
                end
                mod.RF_TextNameWidth(skinData, barW)
                -- Party portrait: the attached square follows the height.
                if skinData.pt then
                    mod.RF_PtApply(button, skinData, mod._scaledPartyProxy, bw, bh, nil)
                end
            end
            -- Live-rescale indicators/auras. No-op for hidden buttons / no unit
            -- (e.g. options menu while not grouped), so cheap there.
            if autoResize then
                -- Scale derives from frame size (recomputed above): re-apply
                -- the scaled sizes during the drag (same set as the full reload).
                local pp = mod._scaledPartyProxy
                if skinData.roleIcon then
                    local riSz = PixelSnap(pp.roleIconSize or 14)
                    skinData.roleIcon:SetSize(riSz, riSz)
                    if skinData.AnchorRoleIcon then
                        skinData.AnchorRoleIcon()
                    end
                end
                if skinData.leaderIcon then
                    local liSz = PixelSnap(pp.leaderIconSize or 14)
                    skinData.leaderIcon:SetSize(liSz, liSz)
                end
                if skinData.raidMarker then
                    local rmSz = PixelSnap(pp.raidMarkerSize or 16)
                    skinData.raidMarker:SetSize(rmSz, rmSz)
                end
                if skinData.combatIcon then
                    local cciSz = PixelSnap(pp.combatIndicatorSize or 16)
                    skinData.combatIcon:SetSize(cciSz, cciSz)
                    if skinData.AnchorCombatIcon then
                        skinData.AnchorCombatIcon()
                    end
                end
                mod.RF_TextFonts(skinData, pp)
                if skinData.statusText then
                    ApplyFont(skinData.statusText, pp.statusTextSize or 14)
                end
            end
        end
    end
    -- Container resize deferred to drag end (SetSize on the container makes
    -- SecureGroupHeaderTemplate re-process children -> blink). Slot offsets +
    -- the header's own size DO follow the live size: keeps the self button
    -- aligned with the stack and the centered child anchors growing from the
    -- correct origin. Pure anchor tracking -- no secure re-process, no blink.
    if mod._PositionPartySlots then
        local _, _, pcs = mod.RF_PartyDims(s)
        mod._PositionPartySlots(bw, bh, PixelSnap(pcs) + mod.PT_AlongPitch(s), mod._PartyGrowth(s))
    end
end

-- Convert a saved (point, relPoint, x, y) UIParent anchor to the TOPLEFT
-- screen coords (UIParent bottom-left space, same space GetLeft/GetTop use)
-- the frame would occupy at the given size.
mod._RFPosTopLeft = function(place, wid, hgt)
    local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
    local function frac(p)
        p = p or "CENTER"
        local fx = (p:find("LEFT") and 0) or (p:find("RIGHT") and 1) or 0.5
        local fy = (p:find("BOTTOM") and 0) or (p:find("TOP") and 1) or 0.5
        return fx, fy
    end
    local rfx, rfy = frac(place.relPoint)
    local pfx, pfy = frac(place.point)
    local ax = uw * rfx + (place.x or 0)
    local ay = uh * rfy + (place.y or 0)
    return ax - pfx * wid, ay + (1 - pfy) * hgt
end

-- Groups stacked in one column before the flow steps to the next column, for
-- the grid group growth ("Down and then Right"): G1/G2 fill the first column
-- top to bottom, G3/G4 the column to its right. Fixed at 2 so a 20-man raid
-- lands on the classic 2x2 block; a plain direction is the same flow with one
-- group per column (every other value below).
mod._RF_GRID_ROWS = 2

-- Group slot origins (relative to the growth corner, before normalization) for a
-- group growth direction, plus the origin those slots normalize against (min x,
-- max y) so slot 0 always sits at the growth corner whichever way the flow runs.
-- THE single copy of the per-slot step math -- the live layout, the 20-player
-- preview and the size preview all place groups through it, so they cannot drift.
-- `count` slots are generated (LayoutGroups can place up to 8 visible groups
-- into the 4-group box) but only the first MOVER_GROUPS of them -- what the box
-- is actually sized for -- set the origin, so a group past the box keeps the
-- same per-slot step instead of rescaling the box in front of it. `out`, when
-- given, is refilled in place (its slot pairs reused) and returned instead of a
-- new table.
mod._RFGroupFlow = function(groupGrowth, groupW, groupH, gs, total, result)
    local num = total or MOVER_GROUPS
    local stepX, stepY = 0, 0
    if groupGrowth == "DOWNRIGHT" then
        -- Column advance is horizontal; the rows inside a column run down.
        stepX, stepY = (groupW + gs), -(groupH + gs)
    elseif groupGrowth == "DOWN" then
        stepY = -(groupH + gs)
    elseif groupGrowth == "UP" then
        stepY = (groupH + gs)
    elseif groupGrowth == "RIGHT" then
        stepX = (groupW + gs)
    else
        stepX = -(groupW + gs) -- LEFT
    end
    local slots, minX, maxY = result or {}, 0, 0
    for index = 0, num - 1 do
        local px, py
        if groupGrowth == "DOWNRIGHT" then
            px = floor(index / mod._RF_GRID_ROWS) * stepX
            py = (index % mod._RF_GRID_ROWS) * stepY
        else
            px, py = index * stepX, index * stepY
        end
        local p = slots[index]
        if p then
            p[1], p[2] = px, py
        else
            slots[index] = { px, py }
        end
    end
    local nc = min(MOVER_GROUPS, num)
    for index = 0, nc - 1 do
        local px, py = slots[index][1], slots[index][2]
        if px < minX then
            minX = px
        end
        if py > maxY then
            maxY = py
        end
    end
    return slots, minX, maxY
end

-- Footprint of the 4-group mover box for a frame size and growth pair. Callers
-- that also derive a corner from the same pair (ns._RFCornerTerms/_RFGrowthCorner)
-- must self-heal (ns._RFEffectiveGrowth) BEFORE calling either, so the size and
-- the corner agree -- this function does not self-heal internally to avoid a
-- caller healing one but not the other.
mod._RFFootprint = function(bw, bh, unitGrowth, groupGrowth, cs, gs)
    bw, bh = PixelSnap(bw), PixelSnap(bh)
    local groupW, groupH
    if unitGrowth == "RIGHT" or unitGrowth == "LEFT" then
        groupW = 5 * bw + 4 * cs
        groupH = bh
    else
        groupW = bw
        groupH = 5 * bh + 4 * cs
    end
    if groupGrowth == "DOWNRIGHT" then
        -- Grid flow: one column of ns._RF_GRID_ROWS groups, then the next
        -- column to its right (see ns._RFGroupFlow). MOVER_GROUPS (4) fills
        -- two columns at any row count that divides it.
        local rowList = mod._RF_GRID_ROWS
        local cols = floor((MOVER_GROUPS + rowList - 1) / rowList)
        return PixelSnap(cols * groupW + (cols - 1) * gs), PixelSnap(rowList * groupH + (rowList - 1) * gs)
    end
    if groupGrowth == "DOWN" or groupGrowth == "UP" then
        return PixelSnap(groupW), PixelSnap(MOVER_GROUPS * groupH + (MOVER_GROUPS - 1) * gs)
    end
    return PixelSnap(MOVER_GROUPS * groupW + (MOVER_GROUPS - 1) * gs), PixelSnap(groupH)
end

-- TOPLEFT of the BASE (20-man) footprint at the saved unlock position: the shared
-- growth origin for every size tier and the previews. Also returns the base footprint's
-- width/height so corner math never recomputes it (extra return values -- existing
-- two-value callers are unaffected). Returns nil when no position has been saved yet.
mod._RFBaseTopLeft = function()
    local s = saved.profile
    local place = s.unlockPos
    if not place then
        return nil
    end
    local cs = mod.RF_CellSpacing(s)
    local gs = mod.RF_GroupSpacing(s)
    local ug, gg = mod._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", s.mergeGroups)
    local wid, hgt = mod._RFFootprint(s.frameWidth or 72, s.frameHeight or 46, ug, gg, cs, gs)
    local l, t = mod._RFPosTopLeft(place, wid, hgt)
    return l, t, wid, hgt
end

-- Shared growth-direction helpers. A single source of truth for "is this
-- direction vertical" and for deriving the flat header's point/xOffset/yOffset
-- and columnAnchorPoint from a growth pair -- both _LayoutGroupsImpl and
-- _BuildHeaderSet's header-creation bootstrap need the identical derivation,
-- and previously hand-duplicated it.
mod._RFGrowthIsVertical = function(g)
    return g == "DOWN" or g == "UP"
end

-- First-button point/xOffset/yOffset for a header growing along unitGrowth.
mod._RFHeaderPoint = function(unitGrowth, cs)
    if unitGrowth == "DOWN" then
        return "TOP", 0, -cs
    elseif unitGrowth == "UP" then
        return "BOTTOM", 0, cs
    elseif unitGrowth == "RIGHT" then
        return "LEFT", cs, 0
    else -- LEFT
        return "RIGHT", -cs, 0
    end
end

-- Blizzard's flat header can only wrap into columns when columnAnchorPoint runs
-- perpendicular to unitGrowth -- see ns._RFEffectiveGrowth below for why merged
-- mode never actually reaches a same-axis pair here in practice.
mod._RFColAnchor = function(unitGrowth, groupGrowth)
    if groupGrowth == "DOWN" or groupGrowth == "RIGHT" then
        if mod._RFGrowthIsVertical(unitGrowth) then
            return "LEFT"
        end
        return "TOP"
    else -- UP or LEFT
        if mod._RFGrowthIsVertical(unitGrowth) then
            return "RIGHT"
        end
        return "BOTTOM"
    end
end

-- Self-heals a same-axis Group/Unit Growth pair when Merge Groups is on (see
-- _RFColAnchor above), applied as a read-time backstop for a pair that reached
-- here without a guarded write (a stale per-tier override, a spec override,
-- hand-edited SavedVariables). Group Growth wins here; the options UI's
-- write-time KeepGrowthPerpendicular uses the same resolution EXCEPT its Unit
-- Growth dropdown, which deliberately lets Unit Growth win instead. Also maps the
-- grid flow ("Down and then Right") onto the single column axis the flat header
-- can render; no-op if not merged.
mod._RFEffectiveGrowth = function(unitGrowth, groupGrowth, merged)
    if not merged then
        return unitGrowth, groupGrowth
    end
    -- The grid flow needs two axes; Blizzard's flat header only has one column
    -- axis, so merged mode degrades it to the plain RIGHT run it CAN render --
    -- same shape as the same-axis fallback below.
    if groupGrowth == "DOWNRIGHT" then
        groupGrowth = "RIGHT"
    end
    if mod._RFGrowthIsVertical(unitGrowth) == mod._RFGrowthIsVertical(groupGrowth) then
        unitGrowth = mod._RFGrowthIsVertical(unitGrowth) and "RIGHT" or "DOWN"
    end
    return unitGrowth, groupGrowth
end

-- Pinned screen corner implied by a growth pair: frames grow AWAY from this corner, so
-- it stays fixed when a tier's footprint differs from the base. Horizontal side = whichever
-- growth is horizontal (RIGHT pins LEFT edge, LEFT pins RIGHT edge); vertical side likewise
-- (DOWN pins TOP, UP pins BOTTOM). Every ns._RFEffectiveGrowth caller heals a same-axis pair
-- before reaching here whenever merged is true, so this only ever sees one for separated mode
-- (merged=false is a no-op for _RFEffectiveGrowth), where every combination of the two
-- axes is legitimate -- including the grid flow, whose column advance is horizontal (so
-- it pins LEFT like RIGHT) and whose rows run down (so it pins TOP like DOWN). This
-- tie-break (UP beats BOTTOM, LEFT beats RIGHT, default TOP+LEFT) is what existing
-- per-tier offsets are calibrated against -- matching Blizzard's own same-axis corner instead
-- would be dead code here for merged and a silent position-shift regression for separated.
-- With centered (Center Groups), the group axis pins its MIDPOINT instead: the
-- result is the edge midpoint on the other axis (TOP/BOTTOM for a horizontal
-- group run, LEFT/RIGHT for a vertical one).
mod._RFGrowthCorner = function(unitGrowth, groupGrowth, centered)
    local hgt = (unitGrowth == "LEFT" or groupGrowth == "LEFT") and "RIGHT" or "LEFT"
    local val = (unitGrowth == "UP" or groupGrowth == "UP") and "BOTTOM" or "TOP"
    if centered then
        return mod._RFGrowthIsVertical(groupGrowth) and hgt or val
    end
    return val .. hgt
end

-- Whether Center Groups applies for an effective (self-healed) group growth: the
-- tier override's own value when it has one, else the base key. The grid flow has
-- two group axes and never centers.
mod._RFGroupCentered = function(shade, groupGrowth)
    if groupGrowth == "DOWNRIGHT" then
        return false
    end
    local c = saved.profile.groupGrowthCentered
    if shade and shade.groupGrowthCentered ~= nil then
        c = shade.groupGrowthCentered
    end
    return c == true
end

-- Pixel-snapped shift that centers a run of n groups inside the MOVER_GROUPS box,
-- along the per-slot step of a _RFGroupFlow slot list (needs slots 0 and 1). More
-- than MOVER_GROUPS groups give a negative shift: the run overflows both sides.
mod._RFCenterShift = function(slots, num)
    local frame = (MOVER_GROUPS - num) / 2
    return PixelSnap(frame * (slots[1][1] - slots[0][1])), PixelSnap(frame * (slots[1][2] - slots[0][2]))
end

-- Signed corner terms: how far a tier footprint's TOPLEFT shifts from the base
-- footprint's TOPLEFT so the growth-derived corner stays pinned. THE single copy of the
-- corner arithmetic -- the forward origin (_RFTierTopLeft), the one-time offset rebase
-- (conversion #2 in _NormalizeTierOffsetAnchors) and the mover save-path inverse
-- (_RFRebaseSavedCenter) all read these two values. Both terms are zero when the
-- footprints match, so the base tier is exact by arithmetic. A centered axis pins the
-- midpoint, so it moves by half the size difference.
mod._RFCornerTerms = function(tw, th, bw, bh, unitGrowth, groupGrowth, centered)
    local corner = mod._RFGrowthCorner(unitGrowth, groupGrowth, centered)
    local fx = (corner:find("RIGHT") and 1) or (corner:find("LEFT") and 0) or 0.5
    local fy = (corner:find("BOTTOM") and 1) or (corner:find("TOP") and 0) or 0.5
    return fx * (bw - tw), -fy * (bh - th)
end

-- THE centralized growth-corner origin: returns the TOPLEFT (UIParent bottom-left space)
-- for a tier footprint (tw, th) whose growth-derived corner is pinned at the BASE
-- footprint's same corner, plus the tier's saved offsets. Every consumer (live
-- _ApplyTierOffset, size previews) anchors through this one function so previews land
-- exactly where live frames land. Base footprint / zero offsets: every corner term
-- cancels, plain base top-left -- profiles without raidSizeOverrides unaffected. Returns
-- nil with no saved unlock position.
mod._RFTierTopLeft = function(tw, th, unitGrowth, groupGrowth, ox, oy, centered)
    local bl, bt, bw, bh = mod._RFBaseTopLeft()
    if not bl then
        return nil
    end
    local kx, ky = mod._RFCornerTerms(tw, th, bw, bh, unitGrowth, groupGrowth, centered)
    return bl + (ox or 0) + kx, bt + (oy or 0) + ky
end

-- Resolve the active size tier bucket and its override table, cascading
-- toward 20 (10 falls back to 15, 30 falls back to 25). The single copy of
-- the cascade -- _GetRaidSizeFrameDimensions, ReloadFrames and
-- _ApplyTierOffset all route through here. Returns tier, override; the
-- override is nil for the base 20 tier or when none is defined.
mod._RFResolveTierOverride = function(numMembers)
    local overrides = saved.profile.raidSizeOverrides
    if not overrides or not numMembers or numMembers <= 0 then
        return 20, nil
    end
    -- User-tunable switch boundaries (per-tier cog sliders): the LOWER tiers
    -- store the highest count they COVER (sizeCap), the UPPER tiers the
    -- count they ENGAGE at (sizeMin). Absent keys reproduce the classic
    -- cascade exactly (10/15/20, 25 engaging at 21, 30 at 26, 40 at 31), so
    -- profiles that never touch the sliders resolve byte-identically.
    local o10, o15, o25, o30, o40 = overrides[10], overrides[15], overrides[25], overrides[30], overrides[40]
    local b10 = (o10 and o10.sizeCap) or 10
    local b15 = (o15 and o15.sizeCap) or 15
    local b25 = (o25 and o25.sizeMin) or 21
    local b30 = (o30 and o30.sizeMin) or 26
    local b40 = (o40 and o40.sizeMin) or 31
    local tier
    if numMembers <= b10 then
        tier = 10
    elseif numMembers <= b15 then
        tier = 15
    elseif numMembers < b25 then
        tier = 20
    elseif numMembers < b30 then
        tier = 25
    elseif numMembers < b40 then
        tier = 30
    else
        tier = 40
    end
    if tier == 20 then
        return 20, nil
    end
    local shade
    if tier < 20 then
        shade = overrides[tier] or (tier == 10 and overrides[15]) or nil
    else
        shade = overrides[tier]
        if not shade and tier == 30 then
            shade = overrides[25]
        end
        if not shade and tier == 40 then
            shade = overrides[30] or overrides[25]
        end
    end
    return tier, shade or nil
end

-- Inverse of the corner scheme, for the unlock mover SAVE path only. The framework
-- measures a dragged container's CENTER from its LIVE bounds -- i.e. on the ACTIVE
-- tier's footprint -- but every apply interprets unlockPos as the BASE footprint's
-- center. Convert a live-measured center to its base-footprint equivalent so the next
-- _ApplyTierOffset reproduces the drop position (within one physical pixel of
-- snapping). With the base tier active, or no overrides defined, every term cancels and
-- the center passes through unchanged -- zero behavior change for base saves.
mod._RFRebaseSavedCenter = function(cx, cy)
    local s = saved.profile
    local _, shade = mod._RFResolveTierOverride(mod._GetEffectiveRaidSize())
    if not shade then
        return cx, cy
    end
    local cs = mod.RF_CellSpacing(s)
    local gs = mod.RF_GroupSpacing(s)
    local bug, bgg = mod._RFEffectiveGrowth(s.unitGrowth or "DOWN", s.groupGrowth or "RIGHT", s.mergeGroups)
    local bw, bh = mod._RFFootprint(s.frameWidth or 72, s.frameHeight or 46, bug, bgg, cs, gs)
    local ug, gg = mod._RFEffectiveGrowth(
        shade.unitGrowth or s.unitGrowth or "DOWN",
        shade.groupGrowth or s.groupGrowth or "RIGHT",
        s.mergeGroups
    )
    local tw, th = mod._RFFootprint(
        shade.width or s.frameWidth or 72,
        shade.height or s.frameHeight or 46,
        ug,
        gg,
        cs,
        gs
    )
    local kx, ky = mod._RFCornerTerms(tw, th, bw, bh, ug, gg, mod._RFGroupCentered(shade, gg))
    return cx - (shade.offsetX or 0) - kx - (tw - bw) / 2, cy - (shade.offsetY or 0) - ky - (bh - th) / 2
end

-- Owned creation point for raidSizeOverrides: fresh tables are ALREADY in
-- the current offset scheme, so both one-time conversion markers are
-- stamped at birth -- otherwise the next _NormalizeTierOffsetAnchors pass
-- would "convert" (and silently shift) offsets that were never old-scheme.
mod._EnsureRaidSizeOverrides = function()
    local s = saved.profile
    if not s.raidSizeOverrides then
        s.raidSizeOverrides = { _topLeftAnchored = true, _cornerAnchored = true }
    else
        -- Existing table: run any pending conversion now so edits that
        -- follow operate on post-conversion values.
        mod._NormalizeTierOffsetAnchors()
    end
    return s.raidSizeOverrides
end

-- One-time conversions (markers travel INSIDE raidSizeOverrides, so imported/swapped
-- profiles self-convert -- no migration-flag inheritance trap). Each applies at most
-- once, in order, rebasing offsets against the PREVIOUS scheme's post-conversion values
-- so every tier's on-screen position is preserved (within one physical pixel of rounding).
--   #1 (_topLeftAnchored): old "re-anchor container at unlockPos.point" offsets ->
--      offsets relative to the base footprint's TOPLEFT.
--   #2 (_cornerAnchored): TOPLEFT-relative offsets -> offsets relative to the
--      growth-derived pinned corner (ns._RFGrowthCorner). Only tiers whose effective
--      growth pins RIGHT and/or BOTTOM change; DOWN+RIGHT tiers keep identical offsets.
mod._NormalizeTierOffsetAnchors = function()
    local s = saved and saved.profile
    if not s then
        return
    end
    local shade = s.raidSizeOverrides
    if not shade then
        return
    end
    -- Heal string-keyed numeric tiers ("25" beside 25): planted by the spec
    -- override system's container fabrication before it learned to use the numeric
    -- form. The module reads tiers numerically, so a phantom never renders yet
    -- captures every override read/write for its tier. With a numeric twin the
    -- phantom is dropped (the twin is the rendered truth; override values re-apply
    -- from their store at the next boundary); without one it becomes the numeric
    -- tier it was meant to be. Must run BEFORE the markers early-return below:
    -- converted profiles are the common carriers.
    local phantoms
    for key, val in pairs(shade) do
        if type(key) == "string" and tonumber(key) ~= nil and type(val) == "table" then
            phantoms = phantoms or {}
            phantoms[#phantoms + 1] = key
        end
    end
    if phantoms then
        for index = 1, #phantoms do
            local key = phantoms[index]
            local num = tonumber(key)
            if shade[num] == nil then
                shade[num] = shade[key]
            end
            shade[key] = nil
        end
    end
    if shade._topLeftAnchored and shade._cornerAnchored then
        return
    end
    local cs = mod.RF_CellSpacing(s)
    local gs = mod.RF_GroupSpacing(s)
    local place = s.unlockPos
    local bl, bt, bw, bh = mod._RFBaseTopLeft()
    if not shade._topLeftAnchored then
        shade._topLeftAnchored = true
        if place and bl then
            for _, o in pairs(shade) do
                if type(o) == "table" then
                    local ug, gg = mod._RFEffectiveGrowth(
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT",
                        s.mergeGroups
                    )
                    local tw, th = mod._RFFootprint(
                        o.width or s.frameWidth or 72,
                        o.height or s.frameHeight or 46,
                        ug,
                        gg,
                        cs,
                        gs
                    )
                    local tl, tooltip = mod._RFPosTopLeft(place, tw, th)
                    o.offsetX = math.floor((o.offsetX or 0) + (tl - bl) + 0.5)
                    o.offsetY = math.floor((o.offsetY or 0) + (tooltip - bt) + 0.5)
                end
            end
        end
    end
    if not shade._cornerAnchored then
        shade._cornerAnchored = true
        if place and bl then
            for _, o in pairs(shade) do
                if type(o) == "table" then
                    local ug, gg = mod._RFEffectiveGrowth(
                        o.unitGrowth or s.unitGrowth or "DOWN",
                        o.groupGrowth or s.groupGrowth or "RIGHT",
                        s.mergeGroups
                    )
                    local tw, th = mod._RFFootprint(
                        o.width or s.frameWidth or 72,
                        o.height or s.frameHeight or 46,
                        ug,
                        gg,
                        cs,
                        gs
                    )
                    local kx, ky = mod._RFCornerTerms(tw, th, bw, bh, ug, gg)
                    if kx ~= 0 then
                        o.offsetX = math.floor((o.offsetX or 0) - kx + 0.5)
                    end
                    if ky ~= 0 then
                        o.offsetY = math.floor((o.offsetY or 0) - ky + 0.5)
                    end
                end
            end
        end
    end
end

-- Apply tier-based position to the container frame. The active tier's 4-group
-- footprint pins its growth-derived corner (ns._RFGrowthCorner, from the tier's
-- EFFECTIVE unit + group growth) at the BASE (20-man) footprint's same corner, plus the tier's saved
-- offsets, via the shared ns._RFTierTopLeft origin -- so a larger/smaller tier grows away
-- from the pinned corner (e.g. RIGHT+DOWN pins top-left, LEFT+UP pins bottom-right).
-- unlockPos itself is untouched (saved tier offsets were rebased once per scheme by
-- _NormalizeTierOffsetAnchors). Base tier or no overrides: every corner term cancels,
-- identical to the plain base top-left.
--
-- While anchored, the unlock anchor system owns the container's position, so the tier
-- offset is folded into the position IT computes rather than applied on top afterwards --
-- applying it after would sit outside the anchor's idempotent guard and reposition every pass forever.
CludesUI._anchorExtraOffset = CludesUI._anchorExtraOffset or {}
CludesUI._anchorExtraOffset["RF_RaidFrames"] = function()
    local _, shade = mod._RFResolveTierOverride(mod._GetEffectiveRaidSize())
    return (shade and shade.offsetX) or 0, (shade and shade.offsetY) or 0
end

mod._ApplyTierOffset = function()
    if not containerFrame or InCombatLockdown() then
        return
    end
    -- Element-anchored container: the unlock anchor system owns the POSITION
    -- (absolute coords recomputed from the anchor target), so repositioning
    -- from unlockPos here would clobber it on every roster/tier pass.
    --
    -- The per-tier offset still applies, though: it is added ON TOP of whatever the
    -- anchor computed, rather than replacing it. Skipping it outright is what made the
    -- per-tier offset fields silently inert for anyone who anchored the raid frames to
    -- another element -- the setting was saved, shown in the options, and did nothing.
    if CludesUI.IsUnlockAnchored and CludesUI.IsUnlockAnchored("RF_RaidFrames") then
        -- The anchor owns the position and now folds the tier offset into it
        -- (see _anchorExtraOffset above), so a tier change just needs the
        -- anchor re-run; moving the container from here would fight it.
        if CludesUI.ReapplyUnlockAnchor then
            CludesUI.ReapplyUnlockAnchor("RF_RaidFrames")
        end
        return
    end
    local s = saved.profile
    if not s.unlockPos then
        return
    end
    local _, shade = mod._RFResolveTierOverride(mod._GetEffectiveRaidSize())
    local cs = mod.RF_CellSpacing(s)
    local gs = mod.RF_GroupSpacing(s)
    local fw = (shade and shade.width) or s.frameWidth or 72
    local fh = (shade and shade.height) or s.frameHeight or 46
    local ug, gg = mod._RFEffectiveGrowth(
        (shade and shade.unitGrowth) or s.unitGrowth or "DOWN",
        (shade and shade.groupGrowth) or s.groupGrowth or "RIGHT",
        s.mergeGroups
    )
    local tw, th = mod._RFFootprint(fw, fh, ug, gg, cs, gs)
    local posX, posY = mod._RFTierTopLeft(
        tw,
        th,
        ug,
        gg,
        (shade and shade.offsetX) or 0,
        (shade and shade.offsetY) or 0,
        mod._RFGroupCentered(shade, gg)
    )
    if not posX then
        return
    end
    containerFrame:ClearAllPoints()
    containerFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", PixelSnap(posX), PixelSnap(posY))
    -- Hidden container (frames not shown -- solo, party, or just left the raid):
    -- LayoutGroups no longer runs for it, so re-derive the SIZE here too. Left alone,
    -- the dormant container keeps the LAST raid tier's footprint, and unlock mode's
    -- mover reads live container geometry: the control appears at a stale spot with a
    -- stale box, and a drag-save there stores a center measured on the wrong footprint
    -- (off by half the width delta -- the "whole layout drifted left after a raid"
    -- corruption). While shown, LayoutGroups owns the size as before.
    if not containerFrame:IsShown() then
        containerFrame:SetSize(tw, th)
    end
end

Inner.ReloadFrames = ReloadFrames
Inner.SetRangeUpdate = function(frame)
    RangeUpdate = frame
end
Inner.broken = false
