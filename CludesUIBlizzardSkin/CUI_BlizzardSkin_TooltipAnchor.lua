if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_BlizzardSkin_TooltipAnchor.lua
--
--  Where the default tooltip sits: the UberTooltips CVar, anchor to cursor,
--  the fixed position with its Unlock Mode mover, growth direction.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIBlizzardSkin.lua or an earlier CUI_BlizzardSkin_*.lua file
-- failed to load.
if not Inner or Inner.last ~= "Dialogs" then return end

-------------------------------------------------------------------------------
--  UberTooltips CVar enforcement (only if user has manually set it in CUI)
-------------------------------------------------------------------------------
do
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        if not CludesUIDB then CludesUIDB = {} end
        if CludesUIDB.uberTooltipsManual then
            CludesUI.SetCVar("UberTooltips", CludesUIDB.uberTooltips and "1" or "0", "CludesUIBlizzardSkin")
        else
            CludesUI.SetCVar("UberTooltips", "1", "CludesUIBlizzardSkin")
        end
    end)
end

-------------------------------------------------------------------------------
--  Anchor Tooltip to Cursor
--  Re-owns the default GameTooltip to a 1x1 frame tracking the mouse, so the
--  tooltip follows the cursor at a user-chosen position + X/Y offset, via
--  GameTooltip_SetDefaultAnchor (the post-hook every default-anchored tooltip --
--  units, world objects, action buttons -- runs through). Installed on first
--  enable; a no-op (Blizzard's anchor stands) when toggled off, and the tracking frame only ticks while a tooltip is shown.
-------------------------------------------------------------------------------

-- Is a tooltip owner handed to us by a Blizzard hook safe to anchor to? It can
-- be a FORBIDDEN frame: Blizzard's nameplate aura buttons are forbidden and call
-- GameTooltip_SetDefaultAnchor on hover, so passing one straight to SetOwner from
-- our tainted hook raises "Attempt to access forbidden object from code tainted
-- by an AddOn". Testing the tooltip alone is NOT enough -- it is the OWNER that
-- is off limits, not GameTooltip itself. Nothing can be anchored to a forbidden
-- frame, so both anchor modes must leave Blizzard's anchoring alone there;
-- IsForbidden is the only method safe to call on such a frame, so it is asked
-- first and nothing else is touched. File scope on purpose: the cursor and fixed anchor modes (separate do-blocks) both need it.
local function TooltipOwnerUsable(hostFrame)
    if not hostFrame then return false end
    local func = hostFrame.IsForbidden
    if type(func) == "function" and func(hostFrame) then return false end
    return true
end

-- Stand-in tooltips: taint-sensitive callers that cannot touch the global
-- GameTooltip build their own GameTooltipTemplate frame and flag it
-- LIKE_GLOBAL_GAMETOOLTIP -- the ecosystem convention asking to be treated
-- as _G.GameTooltip. They still route through GameTooltip_SetDefaultAnchor,
-- so honour the flag for the ANCHOR decision only. The armed-state
-- bookkeeping stays strict-identity: it gates SetPoint enforcement hooked
-- onto GameTooltip's OWN setters, so arming it for a stand-in would enforce
-- against another frame's state. A stand-in needs no ongoing enforcement:
-- GameTooltip_SetDefaultAnchor is a pure one-shot (SetOwner + corner
-- SetPoint, no registration), so nothing Blizzard-side ever re-anchors a
-- stand-in -- every re-build re-enters these hooks.
local function TooltipIsGlobalLike(tipFrame)
    if tipFrame == GameTooltip then return true end
    return type(tipFrame) == "table" and tipFrame.LIKE_GLOBAL_GAMETOOLTIP == true
end

do
    -- Selected position = where the tooltip sits relative to the cursor, so the tooltip corner touching the cursor is the opposite one.
    local POINT_FOR_POS = {
        bottomright = "TOPLEFT",
        bottomleft = "TOPRIGHT",
        topright = "BOTTOMLEFT",
        topleft = "BOTTOMRIGHT",
        right = "LEFT",
        left = "RIGHT",
        top = "BOTTOM",
        bottom = "TOP",
        center = "CENTER",
    }

    local cursorAnchor
    local hooked = false

    local function EnsureCursorFrame()
        if cursorAnchor then return cursorAnchor end
        cursorAnchor = CreateFrame("Frame", "CludesUI_TooltipCursorAnchor", UIParent)
        cursorAnchor:SetSize(1, 1)
        cursorAnchor:SetFrameStrata("TOOLTIP")
        cursorAnchor:Hide()
        local lastX, lastY
        cursorAnchor:SetScript("OnUpdate", function(self)
            local scale = UIParent:GetEffectiveScale()
            if scale <= 0 then return end
            local posX, posY = GetCursorPosition()
            if posX ~= lastX or posY ~= lastY then
                lastX, lastY = posX, posY
                self:ClearAllPoints()
                self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", posX / scale, posY / scale)
            end
        end)
        return cursorAnchor
    end

    -- Show + position the tracking frame at the pointer NOW: the OnUpdate alone only
    -- repositions it next frame, so a tooltip anchored to it and shown synchronously this frame (as the custom CDM frames do) would have no valid rect yet and render nothing.
    local function PositionCursorFrameNow(castFrame)
        castFrame:Show()
        local scale = UIParent:GetEffectiveScale()
        if scale > 0 then
            local posX, posY = GetCursorPosition()
            castFrame:ClearAllPoints()
            castFrame:SetPoint("CENTER", UIParent, "BOTTOMLEFT", posX / scale, posY / scale)
        end
    end

    local function ApplyCursorAnchor(tipFrame, hostFrame)
        if not TooltipIsGlobalLike(tipFrame) then return end
        -- Gated by the customTooltips master (matches the grayed-out option), so disabling the reskin restores the default tooltip position.
        if CludesUIDB and CludesUIDB.customTooltips == false then return end
        if not (CludesUIDB and CludesUIDB.tooltipAnchorCursor) then return end
        -- Owner checked as well as the tooltip: a forbidden owner cannot be passed to SetOwner below. See TooltipOwnerUsable.
        if not TooltipOwnerUsable(hostFrame) or tipFrame:IsForbidden() then return end
        -- "Show Tooltips" suppression parks the tip in a hidden host (CUI_BlizzardSkin_TooltipVisibility.lua): it stays alive and invisible so the peek modifier can reveal it, so anchor it normally -- it must already ride the cursor when revealed.
        local castFrame = EnsureCursorFrame()
        PositionCursorFrameNow(castFrame)
        local anchorPoint = POINT_FOR_POS[CludesUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tipFrame:SetOwner(hostFrame, "ANCHOR_NONE")
        tipFrame:ClearAllPoints()
        tipFrame:SetPoint(
            anchorPoint,
            castFrame,
            "CENTER",
            CludesUIDB.tooltipCursorOffsetX or 0,
            CludesUIDB.tooltipCursorOffsetY or 0
        )
    end

    -- Re-assert the cursor anchor WITHOUT re-owning the tooltip (SetOwner would
    -- wipe content). A content-setter that clears/hides the tip mid-build (e.g.
    -- SetItemByID) fires OnHide, hiding the tracking frame and leaving the tip
    -- anchored to a hidden/unpositioned frame so it never appears. Call this
    -- AFTER content is set and before Show: re-shows + repositions the tracker
    -- and re-points the tooltip. No-op (safe unconditionally) when the cursor anchor or reskin master is off.
    CludesUI._repointTooltipAtCursor = function(tipFrame)
        if tipFrame ~= GameTooltip then return end
        if CludesUIDB and CludesUIDB.customTooltips == false then return end
        if not (CludesUIDB and CludesUIDB.tooltipAnchorCursor) then return end
        if tipFrame:IsForbidden() then return end
        local castFrame = EnsureCursorFrame()
        PositionCursorFrameNow(castFrame)
        local anchorPoint = POINT_FOR_POS[CludesUIDB.tooltipCursorPosition or "top"] or "BOTTOM"
        tipFrame:ClearAllPoints()
        tipFrame:SetPoint(
            anchorPoint,
            castFrame,
            "CENTER",
            CludesUIDB.tooltipCursorOffsetX or 0,
            CludesUIDB.tooltipCursorOffsetY or 0
        )
    end

    local function InstallHook()
        if hooked then return end
        hooked = true
        EnsureCursorFrame()
        -- Stop the tracker when the tooltip closes; ApplyCursorAnchor reshows it.
        GameTooltip:HookScript("OnHide", function()
            if cursorAnchor then cursorAnchor:Hide() end
        end)
        hooksecurefunc("GameTooltip_SetDefaultAnchor", ApplyCursorAnchor)
        -- World-unit tooltips fade out (~1-2s) on mouse-off instead of hiding instantly like
        -- unitframe/item/buff/CDM tips; while riding the cursor that lingering fade trails the pointer, so collapse it to an instant hide -- only while the cursor anchor is on.
        if GameTooltip.FadeOut then
            hooksecurefunc(GameTooltip, "FadeOut", function(self)
                if self ~= GameTooltip then return end
                if CludesUIDB and CludesUIDB.tooltipAnchorCursor then self:Hide() end
            end)
        end
    end

    CludesUI._applyTooltipCursorAnchor = function()
        if CludesUIDB and CludesUIDB.tooltipAnchorCursor then
            InstallHook()
        elseif cursorAnchor then
            cursorAnchor:Hide()
        end
    end

    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self)
        self:UnregisterAllEvents()
        CludesUI._applyTooltipCursorAnchor()
    end)
end

-------------------------------------------------------------------------------
--  Fixed Tooltip Position (CUI-owned, movable in Unlock Mode)
--  CUI permanently owns the default GameTooltip's screen position: every default-anchored
--  tooltip is re-pointed onto OUR anchor frame, dragged via a real Unlock Mode mover.
--  Position is PER PROFILE (profiles[name].tooltipFixedPos); a profile with none gets a
--  ONE-TIME seed captured from wherever Blizzard's Edit Mode container currently sits, so
--  the takeover is visually a no-op until the user drags the box. GameTooltipDefaultContainer
--  is only ever READ, never written, so the user's Edit Mode position survives intact and
--  stands again if the reskin master is off. Same GameTooltip_SetDefaultAnchor post-hook
--  family as the cursor anchor and growth direction (tooltip unprotected, content never
--  touched, no taint surface); Anchor to Cursor takes precedence. Placed BEFORE the growth-direction block so its hook registers first and growth enforcement composes on top of our corner.
-------------------------------------------------------------------------------
do
    -- Representative mover-box size; real tooltips vary, but they pin corner-to-corner to the box so they render inside this footprint.
    local FIXED_W, FIXED_H = 280, 165
    local anchor

    local function ActiveProfile() return CludesUI.GetActiveProfileData() end

    -- Fixed mode is the permanent baseline: no toggle. Only the reskin master (off = vanilla tooltips) and Anchor to Cursor sideline it.
    local function WantFixed()
        if CludesUIDB and CludesUIDB.customTooltips == false then return false end
        if CludesUIDB and CludesUIDB.tooltipAnchorCursor then return false end
        return true
    end

    local function EnsureFixedFrame()
        if anchor then return anchor end
        anchor = CreateFrame("Frame", "CludesUI_TooltipFixedAnchor", UIParent)
        anchor:SetSize(FIXED_W, FIXED_H)
        anchor:EnableMouse(false)
        -- Placeholder point; PositionFromSaved overrides from the profile pos.
        anchor:SetPoint("CENTER", UIParent, "CENTER", -350, -150)
        return anchor
    end

    -- One-time per-profile seed: store where Blizzard's Edit Mode container puts
    -- the tooltip RIGHT NOW, so the takeover changes nothing visually until the
    -- user drags the mover. READ only, container never modified. Retries
    -- harmlessly until the container has a real rect (Edit Mode layouts land
    -- after login); a stored position (seeded or dragged) is never overwritten, so this runs at most once per profile.
    local function EnsureSeeded()
        local profileTbl = ActiveProfile()
        if not profileTbl or profileTbl.tooltipFixedPos then return end
        -- Adopt a position left under the old account-global key.
        if CludesUIDB and CludesUIDB.tooltipFixedPos then
            profileTbl.tooltipFixedPos = CludesUIDB.tooltipFixedPos
            CludesUIDB.tooltipFixedPos = nil
            return
        end
        local c = _G.GameTooltipDefaultContainer
        if not c or not c.GetLeft then return end
        local l, button = c:GetLeft(), c:GetBottom()
        if not l or not button then return end
        local wid, ch = c:GetWidth() or 0, c:GetHeight() or 0
        local us = UIParent:GetEffectiveScale() or 1
        if us <= 0 then return end
        local region = (c:GetEffectiveScale() or us) / us
        -- Blizzard pins the tooltip's corner to the container corner nearest the
        -- closest screen corner. Find that point, then park our box so ITS
        -- matching corner sits exactly there; an idle container may be
        -- collapsed to a sliver (corners coincide), still correct.
        local uw, uh = UIParent:GetWidth(), UIParent:GetHeight()
        local ccx = (l + wid / 2) * region - uw / 2
        local ccy = (button + ch / 2) * region - uh / 2
        local pixel = (ccx < 0) and (l * region) or ((l + wid) * region)
        local py = (ccy < 0) and (button * region) or ((button + ch) * region)
        profileTbl.tooltipFixedPos = {
            centerX = pixel + ((ccx < 0) and (FIXED_W / 2) or (-FIXED_W / 2)) - uw / 2,
            centerY = py + ((ccy < 0) and (FIXED_H / 2) or (-FIXED_H / 2)) - uh / 2,
        }
    end

    -- Park the anchor frame at the ACTIVE profile's position (center offsets from UIParent
    -- center, matching how the mover stores CENTER coords). Reading the profile live every call makes profile switches self-heal on the next tooltip show, with zero extra wiring.
    local function PlaceFromSaved()
        local anchorFrame = EnsureFixedFrame()
        EnsureSeeded()
        local profileTbl = ActiveProfile()
        local place = profileTbl and profileTbl.tooltipFixedPos
        anchorFrame:ClearAllPoints()
        if place and place.centerX and place.centerY then
            anchorFrame:SetPoint("CENTER", UIParent, "CENTER", place.centerX, place.centerY)
        else
            anchorFrame:SetPoint("CENTER", UIParent, "CENTER", -350, -150)
        end
    end

    -- Corner of the box the tooltip pins to: the one nearest the closest screen corner, so
    -- growth always runs INTO the screen (and the box). Growth Direction, when set, forces the vertical component -- the same rule its own enforcement block applies, so the two never fight.
    local function CornerFor(anchorFrame)
        local cx, cy = -350, -150
        local l, button = anchorFrame:GetLeft(), anchorFrame:GetBottom()
        if l and button then
            cx = l + (anchorFrame:GetWidth() or 0) / 2 - UIParent:GetWidth() / 2
            cy = button + (anchorFrame:GetHeight() or 0) / 2 - UIParent:GetHeight() / 2
        else
            local profileTbl = ActiveProfile()
            local place = profileTbl and profileTbl.tooltipFixedPos
            if place and place.centerX and place.centerY then
                cx, cy = place.centerX, place.centerY
            end
        end
        local direction = CludesUIDB and CludesUIDB.tooltipGrowthDirection
        local vert = (direction == "down" and "TOP")
            or (direction == "up" and "BOTTOM")
            or ((cy < 0) and "BOTTOM" or "TOP")
        return vert .. ((cx < 0) and "LEFT" or "RIGHT")
    end

    -- Blizzard's container logic can re-anchor a default-anchored tooltip a few
    -- frames after show WITHOUT clearing points first (see Growth Direction
    -- below), pinning a second corner and stretching the tooltip between our
    -- box and Blizzard's container. Enforcement rides the same armed/disarmed
    -- SetPoint pattern: NEVER reads hook args (hooked secure setters can receive secret values), re-derives everything, rewrites only on deviation.
    local _fixedEnforcing = false
    local _fixedArmed = false

    local function EnforceFixed(tipFrame)
        if not WantFixed() then return end
        if tipFrame:IsForbidden() then return end
        local anchorFrame = anchor
        if not anchorFrame then return end
        local cornerPoint = CornerFor(anchorFrame)
        local anchorPoint, relTo = tipFrame:GetPoint(1)
        -- GetPoint can hand back a SECRET point: Blizzard anchors the world cursor
        -- tooltip (SetWorldCursor -> GameTooltip_SetDefaultAnchor) from restricted
        -- code, and comparing a secret raises, so the classification MUST short-circuit
        -- ahead of the compares. A secret anchor is by definition not ours: treat it as
        -- a deviation and re-point. Our own write reads back clean, so the early-out works again from the next call on.
        local secretPt = issecretvalue and (issecretvalue(anchorPoint) or issecretvalue(relTo))
        if
            not secretPt
            and tipFrame:GetNumPoints() == 1
            and anchorPoint == cornerPoint
            and relTo == anchorFrame
        then
            return
        end
        _fixedEnforcing = true
        tipFrame:ClearAllPoints()
        tipFrame:SetPoint(cornerPoint, anchorFrame, cornerPoint, 0, 0)
        _fixedEnforcing = false
    end

    local function ApplyFixedAnchor(tipFrame, hostFrame)
        if not TooltipIsGlobalLike(tipFrame) then return end
        if not WantFixed() then return end
        if tipFrame:IsForbidden() then return end
        -- A forbidden owner (nameplate aura button) cannot be anchored to:
        -- leave Blizzard's anchoring alone AND disarm SetPoint enforcement.
        -- Arming happens in the SetDefaultAnchor hook before this runs; leaving
        -- it armed would let EnforceFixed yank the tooltip into our box with no matching SetOwner. See TooltipOwnerUsable.
        if not TooltipOwnerUsable(hostFrame) then
            _fixedArmed = false
            return
        end
        -- An open Unlock Mode session owns the anchor frame (live drags + uncommitted edits): re-parking from saved would snap it back mid-session, so pin to wherever the session has it.
        -- A screen-edge link in Unlock Mode owns the position too: re-parking would pull the box off the edge until the anchor chain moves it back a frame later.
        if CludesUI._unlockActive then
            EnsureSeeded()
        elseif not CludesUI.IsUnlockAnchored("CUI_TooltipAnchor") then
            PlaceFromSaved()
        end
        tipFrame:SetOwner(hostFrame, "ANCHOR_NONE")
        EnforceFixed(tipFrame)
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tipFrame, hostFrame)
        if not TooltipIsGlobalLike(tipFrame) then return end
        -- Only the global tooltip can be armed: the SetPoint enforcement below
        -- is hooked onto GameTooltip's own setters. See TooltipIsGlobalLike.
        if tipFrame == GameTooltip then _fixedArmed = true end
        ApplyFixedAnchor(tipFrame, hostFrame)
    end)
    -- Every explicit tooltip build starts with SetOwner, which runs BEFORE the SetDefaultAnchor post-hook re-arms the flag, so explicitly-anchored uses (bags, other addons) never get their anchors rewritten.
    hooksecurefunc(GameTooltip, "SetOwner", function(self)
        _fixedArmed = false
        if not anchor or self:IsForbidden() then return end
        -- Left on our box, Blizzard's next restricted SetPoint fails with an anchor family error.
        -- pcall'd: an owner's forbidden layout aspect restricts the tooltip without
        -- IsForbidden reporting it (see _ttUsable), and this runs on every SetOwner.
        local success, _, relTo = pcall(self.GetPoint, self, 1)
        if not success or (issecretvalue and issecretvalue(relTo)) then return end
        if relTo == anchor then self:ClearAllPoints() end
    end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tip)
        if _fixedEnforcing or not _fixedArmed then return end
        if tip ~= GameTooltip then return end
        EnforceFixed(tip)
    end)

    -- Reposition (and seed if needed) now: login, world entry, reset paths.
    CludesUI._applyTooltipFixedAnchor = function() PlaceFromSaved() end

    -- Unlock Mode element: a real draggable mover for the tooltip position. Writes ONLY
    -- our per-profile key, never Blizzard's tooltip container. Hidden while Anchor to Cursor is on or the reskin master is off (both leave the fixed anchor inactive).
    local function RegisterUnlock()
        if not (CludesUI and CludesUI.RegisterUnlockElements and CludesUI.MakeUnlockElement) then return end
        local MK = CludesUI.MakeUnlockElement
        CludesUI:RegisterUnlockElements({
            MK({
                key = "CUI_TooltipAnchor",
                label = "Tooltip",
                group = "Blizzard Windows",
                order = 650,
                subtitle = "Fixed Position",
                noResize = true, -- tooltip size is dynamic; nothing to resize
                noAnchorTarget = true,
                noAnchorTo = true,
                noSizeMatchTarget = true,
                isHidden = function() return not WantFixed() end,
                getFrame = function()
                    -- MUST stay side-effect-free: unlock mode calls getFrame from its drag
                    -- machinery (OnUpdate/OnDragStop), so parking from saved here would snap a live drag back on release. Boot/applyPos/loadPos do parking + seeding.
                    return EnsureFixedFrame()
                end,
                getSize = function() return FIXED_W, FIXED_H end,
                savePos = function(_, _point, _relPoint, posX, posY)
                    -- Unlock mode hands over CENTER/CENTER coords; on Cancel the frame
                    -- still sits at the dragged spot, so never read the live position.
                    local profileTbl = ActiveProfile()
                    if not profileTbl then return end
                    profileTbl.tooltipFixedPos = { centerX = posX, centerY = posY }
                end,
                loadPos = function()
                    EnsureSeeded()
                    local profileTbl = ActiveProfile()
                    local place = profileTbl and profileTbl.tooltipFixedPos
                    if place and place.centerX and place.centerY then
                        return { point = "CENTER", relPoint = "CENTER", x = place.centerX, y = place.centerY }
                    end
                    return nil
                end,
                clearPos = function()
                    -- Clearing the profile key makes the next apply re-seed from Blizzard's CURRENT Edit Mode spot, so "reset position" = wherever Blizzard would put it today.
                    local profileTbl = ActiveProfile()
                    if profileTbl then profileTbl.tooltipFixedPos = nil end
                    PlaceFromSaved()
                end,
                applyPos = function() PlaceFromSaved() end,
            }),
        })
    end

    local bootFrame = CreateFrame("Frame")
    bootFrame:RegisterEvent("PLAYER_LOGIN")
    bootFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    bootFrame:SetScript("OnEvent", function(self, evt)
        if evt == "PLAYER_LOGIN" then
            EnsureFixedFrame()
            PlaceFromSaved()
            RegisterUnlock()
        else
            -- Edit Mode layouts land after login, so the one-time seed may have found no container rect yet. Retry once in-world, then stop listening (later seeds happen lazily at tooltip show).
            self:UnregisterAllEvents()
            PlaceFromSaved()
        end
    end)
end

-------------------------------------------------------------------------------
--  Growth Direction (default screen-anchored tooltip)
--  Blizzard picks the default tooltip's anchored corner dynamically from the
--  container's screen position, and the pinned corner decides which way added lines
--  grow (TOP pinned = expands down, BOTTOM pinned = expands up). tooltipGrowthDirection
--  "up"/"down" forces the vertical component of whatever corner Blizzard chose,
--  keeping its horizontal side; "default" (or unset) leaves Blizzard's dynamic pick
--  alone. Re-point only, same GameTooltip_SetDefaultAnchor post-hook family as the
--  cursor anchor (no taint surface: tooltip unprotected, content never touched). Cursor-anchored mode re-points the tooltip itself and takes precedence.
-------------------------------------------------------------------------------
do
    local function WantForcedDir()
        if CludesUIDB and CludesUIDB.customTooltips == false then return nil end
        local direction = CludesUIDB and CludesUIDB.tooltipGrowthDirection
        if direction ~= "up" and direction ~= "down" then return nil end
        if CludesUIDB.tooltipAnchorCursor then return nil end
        return direction
    end

    -- Blizzard's container logic RE-ANCHORS the tooltip a few frames after show (and
    -- on size changes) WITHOUT clearing points first. SetPoint only replaces a
    -- same-keyword point, so its re-assert ADDED a second corner next to the forced
    -- one -- top and bottom both pinned, tooltip stretched to fill the gap.
    -- Enforcement rides a SetPoint hook instead: any anchor write that isn't ours
    -- while a default-anchored tooltip is up gets collapsed back to the single
    -- forced corner. The hook never reads its args (hooked setters can receive
    -- secret values), re-deriving everything from GetPoint; _growthEnforcing guards re-entry from our own SetPoint inside the hook.
    local _growthEnforcing = false
    local _growthDefaultAnchored = false

    local function Enforce(tipFrame)
        local direction = WantForcedDir()
        if not direction then return end
        if tipFrame:IsForbidden() then return end
        local anchorPoint, relTo, _, posX, posY = tipFrame:GetPoint(1)
        -- A point written by restricted code (world cursor tooltip) is SECRET:
        -- find() and == on it raise, and the forced corner cannot be derived from it
        -- at all. Skip this pass; the next one, after a clean re-anchor, enforces normally.
        if issecretvalue and (issecretvalue(anchorPoint) or issecretvalue(posX) or issecretvalue(posY)) then
            return
        end
        if not anchorPoint then return end
        relTo = relTo or GameTooltipDefaultContainer
        if not relTo then return end
        local horiz = (anchorPoint:find("LEFT") and "LEFT") or (anchorPoint:find("RIGHT") and "RIGHT") or ""
        local newPoint = ((direction == "down") and "TOP" or "BOTTOM") .. horiz
        if tipFrame:GetNumPoints() == 1 and anchorPoint == newPoint then return end
        _growthEnforcing = true
        tipFrame:ClearAllPoints()
        tipFrame:SetPoint(newPoint, relTo, newPoint, posX or 0, posY or 0)
        _growthEnforcing = false
    end

    hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tipFrame)
        if not TooltipIsGlobalLike(tipFrame) then return end
        -- Only the global tooltip can be armed: the SetPoint enforcement below
        -- is hooked onto GameTooltip's own setters. See TooltipIsGlobalLike.
        if tipFrame == GameTooltip then _growthDefaultAnchored = true end
        Enforce(tipFrame)
    end)
    -- Every tooltip build starts with SetOwner (runs BEFORE the SetDefaultAnchor post-hook re-arms the flag), so explicitly-anchored uses (bags, other addons) never get their anchors rewritten.
    hooksecurefunc(GameTooltip, "SetOwner", function() _growthDefaultAnchored = false end)
    hooksecurefunc(GameTooltip, "SetPoint", function(tip)
        if _growthEnforcing or not _growthDefaultAnchored then return end
        Enforce(tip)
    end)
end

Inner.last = "TooltipAnchor"
