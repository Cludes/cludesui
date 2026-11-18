if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_ExtraBars.lua
--
--  Blizzard movable frames (the Extra Action Button), the holders for the
--  Micro Menu and Bag Bar, and the extra bars setup. Loads after
--  CUI_ActionBars_DataBars.lua and reads the main file through ns only.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, type = ipairs, type
local InCombatLockdown = InCombatLockdown
local hooksecurefunc = hooksecurefunc
local C_Timer_After = C_Timer.After
local GetBindingKey = GetBindingKey

local ABAR, EAB_VTABLE, EXTRA_BARS = mod.EAB, mod.EAB_VTABLE, mod.EXTRA_BARS
local ForceCooldownPaint = mod.ForceCooldownPaint
local Inner = mod._internals
local BLIZZ_MOVABLE_OVERLAY, FormatHotkeyText, SafeEnableMouse =
    Inner.BLIZZ_MOVABLE_OVERLAY, Inner.FormatHotkeyText, Inner.SafeEnableMouse
local SetupDataBars, _quickKeybindState = Inner.SetupDataBars, Inner._quickKeybindState
local blizzMovableHolders, extraBarHolders, hoverStates =
    Inner.blizzMovableHolders, Inner.extraBarHolders, Inner.hoverStates
local AttachExtraBarHoverHooks -- assigned below, published as ns.AttachExtraBarHoverHooks

-------------------------------------------------------------------------------
--  Blizzard Movable Frames (Extra Action Button): a non-secure holder frame
--  that ExtraAbilityContainer is reparented into, kept out of Blizzard's
--  bottom managed column so unlock mode can place it freely. The Encounter
--  Bar stays Blizzard's (Edit Mode owns its position).
--  Overlay sizes are hardcoded (don't affect actual Blizzard frame rendering).
-------------------------------------------------------------------------------
local function SetupBlizzardMovableFrame(barId)
    local holderFrame = CreateFrame("Frame", "CludesEAB_" .. barId, UIParent)
    holderFrame:SetClampedToScreen(true)
    holderFrame:EnableMouse(false)
    blizzMovableHolders[barId] = holderFrame

    local shade = BLIZZ_MOVABLE_OVERLAY[barId]
    holderFrame:SetSize(shade and shade.w or 50, shade and shade.h or 50)

    -- Identify which Blizzard frames to manage for this bar key.
    -- extraFrames = all frames that get reparented into the holder.
    local primaryFrame -- the frame we read position from before reparenting
    local extraFrames = {}

    if barId == "ExtraActionButton" then
        -- ExtraAbilityContainer is the layout container Blizzard's Edit Mode
        -- positions. It parents ExtraActionBarFrame and ZoneAbilityFrame.
        -- We take ownership of the whole container.
        if ExtraAbilityContainer then
            primaryFrame = ExtraAbilityContainer
            extraFrames[#extraFrames + 1] = ExtraAbilityContainer
        end
        -- ExtraActionBarFrame mouse is disabled in the container setup below.
    end

    if #extraFrames == 0 then
        holderFrame:Hide()
        return
    end

    -- Restore saved position BEFORE reparenting so we can still read the
    -- original Blizzard-placed position if no save exists yet.
    local place = ABAR.db.profile.barPositions[barId]
    if place and place.point then
        holderFrame:ClearAllPoints()
        holderFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x, place.y)
    else
        -- Try to capture Blizzard's current Edit Mode position immediately.
        -- If the frame has no valid bounds yet, defer via OnUpdate.
        local source = primaryFrame
        local function TryCapturePosition(self)
            local bL, bT = source:GetLeft(), source:GetTop()
            local bR, bB = source:GetRight(), source:GetBottom()
            if bL and bT and bR and bB and (bR - bL) > 1 then
                local bS = source:GetEffectiveScale()
                local uS = UIParent:GetEffectiveScale()
                local uiW, uiH = UIParent:GetSize()
                local cx = (bL + bR) * 0.5 * bS / uS - uiW / 2
                local cy = (bT + bB) * 0.5 * bS / uS - uiH / 2
                ABAR.db.profile.barPositions[barId] =
                    { point = "CENTER", relPoint = "CENTER", x = cx, y = cy }
                holderFrame:ClearAllPoints()
                holderFrame:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
                if self then
                    self:SetScript("OnUpdate", nil)
                end
                return true
            end
            return false
        end
        if not TryCapturePosition(nil) then
            holderFrame:ClearAllPoints()
            holderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            local attempts = 0
            local captureFrame = CreateFrame("Frame")
            captureFrame:SetScript("OnUpdate", function(self)
                attempts = attempts + 1
                if TryCapturePosition(self) or attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- Reparent all managed frames into the holder, centered. Safe to call
    -- multiple times. In combat the move waits for combat to end, queued
    -- once per bar however many asks; until then a container Blizzard
    -- parented into its bottom managed column is laid out in its own slot.
    local reparentKey = "BlizzMovableReparent" .. barId
    local function ReparentIntoHolder()
        if InCombatLockdown() then
            mod.CombatQueue.Defer(reparentKey, ReparentIntoHolder)
            return
        end
        for _, frame in ipairs(extraFrames) do
            frame:SetParent(holderFrame)
            -- ExtraAbilityContainer is an Edit Mode system: base methods only.
            CludesUI.ClearFramePoints(frame)
            CludesUI.SetFramePoint(frame, "CENTER", holderFrame, "CENTER", 0, 0)
        end
    end

    -- Extra Action Button: disable the container's layout-driven repositioning and
    -- reparent it into our holder. Keep OnShow/OnHide cleared on the container so
    -- Blizzard's layout code cannot fire, but leave the child frames
    -- (ExtraActionBarFrame, ZoneAbilityFrame) untouched so they show and hide normally.
    if barId == "ExtraActionButton" and ExtraAbilityContainer then
        -- Hide the Edit Mode selection overlay so it doesn't appear in
        -- Blizzard's Edit Mode (we own this frame's position via unlock).
        local eacSel = ExtraAbilityContainer.Selection
        if eacSel then
            eacSel:SetAlpha(0)
            eacSel:EnableMouse(false)
            if not CludesUI._GetFFD(eacSel).showHooked then
                CludesUI._GetFFD(eacSel).showHooked = true
                hooksecurefunc(eacSel, "Show", function(self)
                    self:SetAlpha(0)
                    self:EnableMouse(false)
                end)
            end
        end

        -- Disable mouse on ExtraActionBarFrame so it cannot absorb clicks
        -- when no extra action bar is active.
        if ExtraActionBarFrame and not InCombatLockdown() and ExtraActionBarFrame:IsMouseEnabled() then
            ExtraActionBarFrame:EnableMouse(false)
        end

        -- CLAUDE.md exception to the never-SetScript rule: these handlers are
        -- cleared, never hooked. The OnShow parents the container into the
        -- bottom managed column, also in combat when an extra or zone ability
        -- appears, and the re-park waits for combat to end (the extra button
        -- makes the container protected); our holder's Show/Hide would also
        -- run both handlers inside our call, tainting the column's
        -- managed-frame state. A cleared handler runs no code.
        ExtraAbilityContainer:SetScript("OnShow", nil)
        ExtraAbilityContainer:SetScript("OnHide", nil)

        -- Refresh ExtraActionButton1's keybind text and cooldown swipe. The
        -- broadcaster kill at load prevents Blizzard's UPDATE_BINDINGS and cooldown
        -- updates from reaching this button, so we drive both here. UpdateAction runs
        -- first; the keybind is set after so Blizzard's own UpdateHotkeys (which hides
        -- the key when GetBindingKey is momentarily nil) can't clobber our text.
        -- Unlike the cooldown -- which recovers via the ACTIONBAR_UPDATE_COOLDOWN
        -- dispatcher -- the keybind has no such fallback, so every path that can
        -- reveal the button refreshes it.
        local function RefreshExtraActionButton()
            local eab1 = ExtraActionButton1
            if not eab1 then
                return
            end
            -- Cooldown-only refresh below; avoids passing secret cooldown values through a tainted call.
            local hk = eab1.HotKey
            if hk then
                local key1 = GetBindingKey("EXTRAACTIONBUTTON1")
                if key1 then
                    hk:SetText(FormatHotkeyText(key1))
                    hk:Show()
                end
            end
            ForceCooldownPaint(eab1)
            -- Re-evaluate the broadcaster need now: this container Show/AddFrame
            -- refresh is a reliable delve-entry signal (the button's own OnShow
            -- doesn't fire then), and RefreshBroadcaster reads the button's
            -- actual visibility to decide.
            if mod.RefreshBroadcaster then
                mod.RefreshBroadcaster()
            end
        end

        -- Hook AddFrame so newly added ability buttons stay clickable, and
        -- refresh the extra action button. When the container is already shown
        -- (e.g. a zone ability is active) and the extra action button then
        -- becomes active, that fires AddFrame but not the container's Show hook,
        -- so this is the only refresh signal for that path. Deferred one frame so
        -- Blizzard has finished assigning the button's action before we read it.
        if ExtraAbilityContainer.AddFrame then
            hooksecurefunc(ExtraAbilityContainer, "AddFrame", function(_, widget)
                if widget and widget.EnableMouse and not InCombatLockdown() then
                    widget:EnableMouse(true)
                end
                C_Timer_After(0, RefreshExtraActionButton)
            end)
        end

        -- Reposition the container into our holder.
        local function RepositionExtraContainer()
            if InCombatLockdown() then
                return
            end
            local boxHolder = ExtraAbilityContainer
            boxHolder:SetParent(holderFrame)
            CludesUI.ClearFramePoints(boxHolder)
            CludesUI.SetFramePoint(boxHolder, "CENTER", holderFrame, "CENTER", 0, 0)
        end
        RepositionExtraContainer()

        -- Re-reparent when Edit Mode tries to reposition the container.
        if ExtraAbilityContainer.ApplySystemAnchor then
            hooksecurefunc(ExtraAbilityContainer, "ApplySystemAnchor", function()
                local _, relFrame = ExtraAbilityContainer:GetPoint()
                if relFrame ~= holderFrame then
                    RepositionExtraContainer()
                end
                -- Do NOT write to BottomManagedFrameContainer.showingFrames here.
                -- Writing into that Blizzard-owned table from this insecure hook
                -- taints the managed-frame-position system; a later in-combat layout
                -- pass (e.g. leaving a queued/follower instance while in combat) then
                -- blocks the protected ClearAllPoints on the managed containers
                -- (ADDON_ACTION_BLOCKED naming this addon). The container stays out
                -- of Blizzard's layout without it: its OnShow is cleared above, and
                -- the SetParent hook below moves it back into the holder whenever
                -- Blizzard parents it into the column (in combat, once combat ends).
            end)
        end

        -- Re-reparent if the container shows outside the holder. (Its OnShow
        -- script is cleared above; this method hook still fires on Show.)
        hooksecurefunc(ExtraAbilityContainer, "Show", function()
            if ExtraAbilityContainer:GetParent() ~= holderFrame then
                RepositionExtraContainer()
            end
            RefreshExtraActionButton()
        end)

        -- Quick-reload catch-up: if the button is already showing, its
        -- Show/AddFrame fired before this deferred setup registered the
        -- hooks above, so we missed them. Refresh now so the keybind isn't
        -- left blank until the next show -- the cooldown recovers on its own
        -- via the dispatcher, the keybind has no such fallback.
        if ExtraActionButton1 and ExtraActionButton1:IsShown() then
            RefreshExtraActionButton()
        end
    end

    -- Initial reparent.
    ReparentIntoHolder()

    -- Hook SetParent on every managed frame so we re-reparent immediately if
    -- Blizzard or another addon steals the frame back.
    for _, frame in ipairs(extraFrames) do
        hooksecurefunc(frame, "SetParent", function(self, newParent)
            if newParent ~= holderFrame then
                ReparentIntoHolder()
            end
        end)
    end

    -- Apply visibility settings
    local s = ABAR.db.profile.bars[barId]
    if s and ABAR.VisibilityCompat.IsNever(s) then
        holderFrame:Hide()
    end

    return holderFrame
end

-- Re-disable mouse on ExtraActionBarFrame after every combat: Blizzard's
-- secure code re-enables mouse on protected frames during combat.
local _blizzMovableCombatFrame = CreateFrame("Frame")
_blizzMovableCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
_blizzMovableCombatFrame:SetScript("OnEvent", function()
    if InCombatLockdown() then
        return
    end
    if ExtraActionBarFrame and ExtraActionBarFrame:IsMouseEnabled() then
        ExtraActionBarFrame:EnableMouse(false)
    end
end)

local function SetupBlizzardMovableFrames()
    for _, details in ipairs(EXTRA_BARS) do
        if details.isBlizzardMovable then
            -- EncounterBar: position fully owned by Blizzard Edit Mode.
            if details.key == "EncounterBar" then
                -- no-op: let Blizzard own position entirely
            else
                SetupBlizzardMovableFrame(details.key)
            end
        end
    end
end

-------------------------------------------------------------------------------
--  Extra Bar Holders (MicroBar, BagBar) positioning via holder frames.
--  Reparents Blizzard frames into holder frames so unlock mode can position them.
-------------------------------------------------------------------------------
AttachExtraBarHoverHooks = function(details)
    -- Position-only Blizzard-owned bars (the QueueStatus eye) never get mouseover
    -- fade hooks -- CUI controls only their position now, not visibility. Without
    -- this, a stale "mouseover" setting would fade the eye to alpha 0 on leave.
    if details.noManagedVisibility then
        return
    end
    -- Idempotent: only attach once per bar key
    if hoverStates[details.key] then
        return
    end

    local blizzFrame = _G[details.frameName]
    if not blizzFrame then
        return
    end
    local holderFrame = extraBarHolders[details.key]
    local hoverFrame = details.hoverFrame and _G[details.hoverFrame]

    -- Fade the Blizzard frame directly rather than the holder.
    -- The holder is for positioning only; fading it can be overridden by
    -- Blizzard's own layout code calling SetAlpha on the child frame.
    local fadeTarget = blizzFrame
    local hoverRoot = hoverFrame or blizzFrame

    local status = EAB_VTABLE.Hover.GetState(details.key, fadeTarget)

    local function IsChildOfHoverRoot(widget)
        while widget do
            if widget == hoverRoot then
                return true
            end
            widget = widget.GetParent and widget:GetParent() or nil
        end
        return false
    end

    local function IsHoverRootActive()
        local foci = GetMouseFoci()
        if foci then
            for _, focus in ipairs(foci) do
                if focus and IsChildOfHoverRoot(focus) then
                    return true
                end
            end
        end

        return hoverRoot:IsMouseOver()
    end

    local OnEnter, OnLeave = EAB_VTABLE.Hover.BuildHandlers(details.key, status, {
        canEnter = function()
            return IsHoverRootActive()
        end,
        isStillHovered = function()
            return IsHoverRootActive()
        end,
        markHoveredWhileActive = true,
    })

    hoverRoot:HookScript("OnEnter", OnEnter)
    hoverRoot:HookScript("OnLeave", OnLeave)

    -- Recurse into child frames to hook all interactive buttons, including
    -- those nested inside sub-containers (e.g. MicroMenu inside MicroMenuContainer).
    local function HookChildren(hostFrame, depth)
        depth = depth or 0
        if depth > 3 then
            return
        end
        for _, childFrame in ipairs({ hostFrame:GetChildren() }) do
            if
                childFrame:IsObjectType("Button")
                or childFrame:IsObjectType("CheckButton")
                or childFrame:IsObjectType("ItemButton")
            then
                childFrame:HookScript("OnEnter", OnEnter)
                childFrame:HookScript("OnLeave", OnLeave)
            else
                -- Recurse into non-button containers
                HookChildren(childFrame, depth + 1)
            end
        end
    end
    HookChildren(hoverRoot)
end

-- WoW Forever: while the variant renders and no eye position is saved, the
-- queue eye sits at a minimap spot and is never captured: the one the
-- minimap's spot helper gives while it answers (on the ring where Blizzard's
-- Forever layout puts it while the minimap draws that ring, or diagonally
-- off the map's bottom-left corner under Forever Square), else Blizzard's
-- Forever layout anchor on the map. Anchored to the map, so a move carries
-- it; the minimap's apply pass calls the relayout below on a resize, and a
-- button row starting at the ring's bottom-left reads the predicate to start
-- past the eye. An unlock-mode drag saves a position, which wins until the
-- look changes (every switch to the variant clears it). Once per profile,
-- while the spot helper answers, a spot saved before the variant placed the
-- eye (a login capture) gives way; the stamp is set as soon as nothing is
-- saved, so every later spot is the player's own.
function mod.AB_ForeverEyeParked()
    if not mod.AB_Forever() then
        return false
    end
    local p = ABAR.db.profile
    local qs = p.barPositions.QueueStatus
    if not p.foreverEyeRingSeeded then
        if not (qs and qs.point) then
            p.foreverEyeRingSeeded = true
        else
            local mm = CludesUI._ModuleNS.CludesUIMinimap
            if mm and mm.MinimapQueueEyeSpot() then
                p.foreverEyeRingSeeded = true
                p.barPositions.QueueStatus = nil
                qs = nil
            end
        end
    end
    return not (qs and qs.point)
end
-- Places the holder there; true when parked.
function mod.AB_ForeverEyePark(holderFrame)
    if not (holderFrame and mod.AB_ForeverEyeParked()) then
        return false
    end
    local mm = CludesUI._ModuleNS.CludesUIMinimap
    local map, posX, posY
    if mm then
        map, posX, posY = mm.MinimapQueueEyeSpot()
    end
    holderFrame:ClearAllPoints()
    if map then
        holderFrame:SetPoint("CENTER", map, "CENTER", posX, posY)
    else
        -- Blizzard's stock spot, which scales with the minimap's Edit Mode size.
        local ms = (MinimapCluster and MinimapCluster.GetEditModeScale and MinimapCluster:GetEditModeScale())
            or 1
        holderFrame:SetPoint("CENTER", Minimap, "CENTER", -68 * ms, -68 * ms)
    end
    return true
end
function mod.AB_ForeverEyeRelayout()
    mod.AB_ForeverEyePark(extraBarHolders.QueueStatus)
end

-- Blizzard Style on the WoW Forever client: that client frames the micro menu
-- (MicroMenu.BackgroundArt and BorderArt) and the bag bar (the BagsBar frame
-- and strip atlases), which the retail look has none of, so they fade, as the
-- Blizzard Skins+ cards fade them when they skin these bars. Alpha only on
-- Blizzard's own textures: nothing is hidden, reparented, hooked or written
-- as a key in that tree. Run with each bar's follow pass (setup, Edit Mode
-- re-anchors and resizes); the bag bar's art is found once. The WoW Forever
-- look keeps the art.
local FV_BAG_ART = { "actionbar-frame", "iconframe-background" }
local fvBagArt
local function FadeForeverBarArt(barId)
    if not (CludesUI.IS_FOREVER and mod.AB_Style() == "blizzard" and not mod.AB_Forever()) then
        return
    end
    if barId == "MicroBar" then
        local mm = _G.MicroMenu
        if mm and mm.BackgroundArt then
            mm.BackgroundArt:SetAlpha(0)
        end
        if mm and mm.BorderArt then
            mm.BorderArt:SetAlpha(0)
        end
        return
    end
    local barFrame = _G.BagsBar
    if not barFrame then
        return
    end
    if not fvBagArt then
        fvBagArt = {}
        local regions = { barFrame:GetRegions() }
        for i = 1, #regions do
            local region = regions[i]
            local atlas = region.GetAtlas and region:GetAtlas()
            if atlas then
                local la = atlas:lower()
                for jdx = 1, #FV_BAG_ART do
                    if la:find(FV_BAG_ART[jdx], 1, true) then
                        fvBagArt[#fvBagArt + 1] = region
                        break
                    end
                end
            end
        end
    end
    for i = 1, #fvBagArt do
        fvBagArt[i]:SetAlpha(0)
    end
end

local function SetupExtraBarHolder(barId, frameName, barInfo)
    local blizzFrame = _G[frameName]
    if not blizzFrame then
        return
    end

    local holderFrame = CreateFrame("Frame", "CludesEAB_" .. barId, UIParent)
    holderFrame:SetClampedToScreen(true)
    extraBarHolders[barId] = holderFrame

    -- Size the holder to match the Blizzard frame
    local wid, hgt = blizzFrame:GetWidth(), blizzFrame:GetHeight()
    if wid and wid > 1 and hgt and hgt > 1 then
        holderFrame:SetSize(wid, hgt)
    else
        holderFrame:SetSize(200, 40)
    end

    -- MicroBar/BagBar: position fully owned by Blizzard Edit Mode.
    -- Don't save or restore positions -- passive-follow handles it.
    -- Early return skips all position capture/restore code below.
    if barId == "MicroBar" or barId == "BagBar" then
        ABAR.db.profile.barPositions[barId] = nil
        local function SyncFollow()
            local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
            if fw and fw > 1 and fh and fh > 1 then
                -- In our own units: Edit Mode's Size setting scales the frame.
                local k = blizzFrame:GetEffectiveScale() / holderFrame:GetEffectiveScale()
                holderFrame:SetSize(fw * k, fh * k)
            end
            holderFrame:ClearAllPoints()
            holderFrame:SetPoint("CENTER", blizzFrame, "CENTER", 0, 0)
            -- The bar's end caps follow the frame's size and orientation.
            mod.AB_ExtraCaps(barId)
            FadeForeverBarArt(barId)
        end
        SyncFollow()
        blizzFrame:HookScript("OnSizeChanged", function()
            SyncFollow()
        end)
        if blizzFrame.ApplySystemAnchor then
            hooksecurefunc(blizzFrame, "ApplySystemAnchor", function()
                C_Timer_After(0, SyncFollow)
            end)
        end
        -- A Size change only rescales the frame (no size event).
        if blizzFrame.UpdateSystemSettingSize then
            hooksecurefunc(blizzFrame, "UpdateSystemSettingSize", function()
                C_Timer_After(0, SyncFollow)
            end)
        end
        return holderFrame
    end

    -- Restore saved position or capture current Blizzard position
    local place = ABAR.db.profile.barPositions[barId]
    if barId == "QueueStatus" and mod.AB_ForeverEyePark(holderFrame) then
        -- WoW Forever: at its stock spot on the minimap (never captured).
    elseif place and place.point then
        holderFrame:ClearAllPoints()
        holderFrame:SetPoint(place.point, UIParent, place.relPoint or place.point, place.x, place.y)
    else
        local bL, bT = blizzFrame:GetLeft(), blizzFrame:GetTop()
        local bR, bB = blizzFrame:GetRight(), blizzFrame:GetBottom()
        if bL and bT and bR and bB and (bR - bL) > 1 then
            local bS = blizzFrame:GetEffectiveScale()
            local uiS = UIParent:GetEffectiveScale()
            local uiW, uiH = UIParent:GetSize()
            local cx = (bL + bR) * 0.5 * bS / uiS - uiW / 2
            local cy = (bT + bB) * 0.5 * bS / uiS - uiH / 2
            ABAR.db.profile.barPositions[barId] = {
                point = "CENTER",
                relPoint = "CENTER",
                x = cx,
                y = cy,
            }
            holderFrame:ClearAllPoints()
            holderFrame:SetPoint("CENTER", UIParent, "CENTER", cx, cy)
        else
            -- Defer capture
            holderFrame:ClearAllPoints()
            holderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
            local attempts = 0
            local captureFrame = CreateFrame("Frame")
            captureFrame:SetScript("OnUpdate", function(self)
                attempts = attempts + 1
                local cL, cT = blizzFrame:GetLeft(), blizzFrame:GetTop()
                local cR, cB = blizzFrame:GetRight(), blizzFrame:GetBottom()
                if cL and cT and cR and cB and (cR - cL) > 1 then
                    local cS = blizzFrame:GetEffectiveScale()
                    local uS = UIParent:GetEffectiveScale()
                    local uiW, uiH = UIParent:GetSize()
                    local ccx = (cL + cR) * 0.5 * cS / uS - uiW / 2
                    local ccy = (cT + cB) * 0.5 * cS / uS - uiH / 2
                    ABAR.db.profile.barPositions[barId] = {
                        point = "CENTER",
                        relPoint = "CENTER",
                        x = ccx,
                        y = ccy,
                    }
                    holderFrame:ClearAllPoints()
                    holderFrame:SetPoint("CENTER", UIParent, "CENTER", ccx, ccy)
                    self:SetScript("OnUpdate", nil)
                elseif attempts > 300 then
                    self:SetScript("OnUpdate", nil)
                end
            end)
        end
    end

    -- QueueStatusButton: reparent to UIParent so micro menu visibility
    -- (mouseover/combat hide) doesn't affect the eye. Hook UpdatePosition to
    -- prevent snap-back.
    if barId == "QueueStatus" then
        SafeEnableMouse(holderFrame, false)

        -- Reparent to UIParent (independent of micro menu visibility)
        local function EnsureQueueParent()
            if blizzFrame:GetParent() ~= UIParent and not InCombatLockdown() then
                blizzFrame:SetParent(UIParent)
                if MicroMenuContainer and MicroMenuContainer.Layout then
                    C_Timer_After(0, function()
                        if MicroMenuContainer and MicroMenuContainer.Layout then
                            MicroMenuContainer:Layout()
                        end
                    end)
                end
            end
        end
        EnsureQueueParent()

        local function SyncQueueHolderSize()
            local fw, fh = blizzFrame:GetWidth(), blizzFrame:GetHeight()
            if fw and fw > 1 and fh and fh > 1 then
                holderFrame:SetSize(fw, fh)
            end
        end

        -- On WoW Forever the eye is an Edit Mode system whose SetPoint and
        -- ClearAllPoints are Blizzard overrides that flag Edit Mode's anchor
        -- pass (tainted from here); the saved base methods move it cleanly.
        local function RepositionQueue()
            CludesUI.ClearFramePoints(blizzFrame)
            CludesUI.SetFramePoint(blizzFrame, "CENTER", holderFrame, "CENTER", 0, 0)
        end

        RepositionQueue()
        SyncQueueHolderSize()
        blizzFrame:HookScript("OnSizeChanged", SyncQueueHolderSize)

        -- Prevent Blizzard from snapping the eye back or reparenting away
        local _upGuard = false
        local function Repin()
            if _upGuard then
                return
            end
            _upGuard = true
            RepositionQueue()
            EnsureQueueParent()
            _upGuard = false
        end
        if type(blizzFrame.UpdatePosition) == "function" then
            hooksecurefunc(blizzFrame, "UpdatePosition", Repin)
        end
        -- WoW Forever: the eye is an Edit Mode system with no UpdatePosition.
        -- Blizzard re-anchors it through UpdateDefaultAnchor (its own layout
        -- apply, the micro menu's anchor, drag and settings) and, through a
        -- callback that holds the unhooked function, on a Minimap size change.
        if CludesUI.IS_FOREVER then
            if type(blizzFrame.UpdateDefaultAnchor) == "function" then
                hooksecurefunc(blizzFrame, "UpdateDefaultAnchor", Repin)
            end
            if MinimapCluster and type(MinimapCluster.SetEditModeScale) == "function" then
                hooksecurefunc(MinimapCluster, "SetEditModeScale", function()
                    mod.AB_ForeverEyeRelayout()
                    Repin()
                end)
            end
        end

        -- Recover from external Hide() calls (other addons, stale state).
        -- When Blizzard updates the queue display, re-check parent and
        -- force Show() if the player is actually in a queue.
        if type(blizzFrame.UpdateDisplay) == "function" then
            hooksecurefunc(blizzFrame, "UpdateDisplay", function()
                EnsureQueueParent()
            end)
        end

        -- Safety net: on LFG_UPDATE, re-parent and let Blizzard show the eye
        local queueWatcher = mod.TakeShell()
        queueWatcher:RegisterEvent("LFG_UPDATE")
        queueWatcher:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
        queueWatcher:RegisterEvent("LFG_ROLE_CHECK_UPDATE")
        queueWatcher:RegisterEvent("LFG_PROPOSAL_UPDATE")
        queueWatcher:SetScript("OnEvent", function()
            EnsureQueueParent()
            RepositionQueue()
        end)

        return holderFrame
    end
    -- All current extra bars (MicroBar, BagBar, QueueStatus) return above;
    -- nothing reaches here.
end

local function SetupExtraBarHolders()
    for _, details in ipairs(EXTRA_BARS) do
        if not details.isDataBar and not details.isBlizzardMovable and details.frameName then
            SetupExtraBarHolder(details.key, details.frameName, details)
        end
    end
end

local function RegisterExtraBarsWithUnlockMode()
    if not CludesUI or not CludesUI.RegisterUnlockElements then
        return
    end
    local MK = CludesUI.MakeUnlockElement
    local elements = {}
    local orderBase = 350
    for position, details in ipairs(EXTRA_BARS) do
        if not details.isDataBar and not details.isBlizzardMovable and details.frameName then
            local bk = details.key
            -- MicroBar, BagBar: position fully owned by Blizzard Edit Mode.
            -- Skip unlock registration entirely.
            if bk == "MicroBar" or bk == "BagBar" then
                -- no-op: visibility-only holder, no unlock mover
            else
                local isBlizzOwned = (bk == "QueueStatus")
                elements[#elements + 1] = MK({
                    key = bk,
                    label = details.label,
                    group = "Action Bars",
                    order = orderBase + position,
                    noResize = true,
                    noAnchorTo = isBlizzOwned,
                    noAnchorTarget = isBlizzOwned,
                    isHidden = function()
                        local s = ABAR.db.profile.bars[bk]
                        if not s then
                            return false
                        end
                        local shade = ABAR._visOverride and ABAR._visOverride[bk]
                        if shade then
                            return shade == "never"
                        end
                        return ABAR.VisibilityCompat.IsNever(s)
                    end,
                    getFrame = function()
                        return extraBarHolders[bk]
                    end,
                    getSize = function()
                        local holderFrame = extraBarHolders[bk]
                        if holderFrame then
                            return holderFrame:GetWidth(), holderFrame:GetHeight()
                        end
                        return 200, 40
                    end,
                    savePos = function(_, anchorPoint, relPoint, posX, posY)
                        if anchorPoint and posX and posY then
                            ABAR.db.profile.barPositions[bk] = {
                                point = anchorPoint,
                                relPoint = relPoint or anchorPoint,
                                x = posX,
                                y = posY,
                            }
                        end
                        if not CludesUI._unlockActive then
                            local holderFrame = extraBarHolders[bk]
                            if holderFrame and anchorPoint and posX and posY then
                                holderFrame:ClearAllPoints()
                                holderFrame:SetPoint(
                                    anchorPoint,
                                    UIParent,
                                    relPoint or anchorPoint,
                                    posX,
                                    posY
                                )
                            end
                        end
                    end,
                    loadPos = function()
                        local place = ABAR.db.profile.barPositions[bk]
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
                    clearPos = function()
                        ABAR.db.profile.barPositions[bk] = nil
                    end,
                    applyPos = function()
                        local place = ABAR.db.profile.barPositions[bk]
                        local holderFrame = extraBarHolders[bk]
                        if not holderFrame then
                            return
                        end
                        -- MicroBar/BagBar: Blizzard owns position, never move
                        if bk == "MicroBar" or bk == "BagBar" then
                            return
                        end
                        holderFrame:ClearAllPoints()
                        if place and place.point then
                            holderFrame:SetPoint(
                                place.point,
                                UIParent,
                                place.relPoint or place.point,
                                place.x,
                                place.y
                            )
                        elseif not (bk == "QueueStatus" and mod.AB_ForeverEyePark(holderFrame)) then
                            holderFrame:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
                        end
                    end,
                })
            end -- else (not MicroBar/BagBar)
        end
    end
    CludesUI:RegisterUnlockElements(elements, "CludesUIActionBars")
end

-------------------------------------------------------------------------------
--  Extra Bars (MicroBar, BagBar) visibility-only management
--  These use Blizzard's existing frames, we just manage visibility.
-------------------------------------------------------------------------------
local function SetupExtraBars()
    if not ABAR.db then
        return
    end

    -- Setup Blizzard movable frames (Extra Action Button)
    SetupBlizzardMovableFrames()

    -- Setup extra bar holders (MicroBar, BagBar) for visibility/mouseover
    SetupExtraBarHolders()

    for _, details in ipairs(EXTRA_BARS) do
        if not details.isDataBar and not details.isBlizzardMovable then
            local blizzFrame = _G[details.frameName]
            if blizzFrame then
                local s = ABAR.db.profile.bars[details.key]
                if s then
                    local holderFrame = extraBarHolders[details.key]
                    if ABAR.VisibilityCompat.IsNever(s) and not details.blizzOwnedVisibility then
                        blizzFrame:Hide()
                        if holderFrame then
                            holderFrame:Hide()
                        end
                    end
                    AttachExtraBarHoverHooks(details)
                end
            end
        end -- not isDataBar/isBlizzardMovable
    end

    _quickKeybindState.art.ForEachSpecialButton(_quickKeybindState.art.InitializeButton)

    -- Register extra bars with unlock mode
    if CludesUI and CludesUI.RegisterUnlockElements then
        RegisterExtraBarsWithUnlockMode()
    else
        C_Timer_After(1, function()
            if CludesUI and CludesUI.RegisterUnlockElements then
                RegisterExtraBarsWithUnlockMode()
            end
        end)
    end

    -- Setup data bars (XP, Rep)
    SetupDataBars()

    -- Apply correct initial alpha now that holders exist.
    -- RefreshMouseover ran at OnEnable before holders were created, so
    -- bars with mouseoverEnabled never got their alpha set to 0.
    ABAR:RefreshMouseover()
end

-- Setup extra bars after a short delay to ensure frames exist
local extraBarFrame = CreateFrame("Frame")
extraBarFrame:RegisterEvent("PLAYER_LOGIN")
extraBarFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    C_Timer_After(0.5, SetupExtraBars)
end)

mod.AttachExtraBarHoverHooks = AttachExtraBarHoverHooks -- called by CUI_ActionBars_Fade.lua
