if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- A set of ids written as one list of numbers: [[ id id ... ]] -> { [id] = true }.
local function IdSet(ids)
    local set = {}
    for id in ids:gmatch("%S+") do
        set[tonumber(id)] = true
    end
    return set
end

-------------------------------------------------------------------------------
--  CUI_Minimap_Apply.lua
--
--  ApplyMinimap, the full apply pass.
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local SKIN, flyoutOwnedFrames = Inner.EBS, Inner.flyoutOwnedFrames
local GetBorderStyleColor, GetFFD = Inner.GetBorderStyleColor, Inner.GetFFD
local minimapDecorations, Pix, QueueApplyAll = Inner.minimapDecorations, Inner.PP, Inner.QueueApplyAll
local TEMP_DISABLED, BuildFlyoutContents = Inner.TEMP_DISABLED, Inner.BuildFlyoutContents
local CollectFlyoutButtons, CreateFlyoutToggle = Inner.CollectFlyoutButtons, Inner.CreateFlyoutToggle
local HideFlyoutPanel, InvalidateFlyout = Inner.HideFlyoutPanel, Inner.InvalidateFlyout
local ApplyMinimapFont, GetCoordsModePos = Inner.ApplyMinimapFont, Inner.GetCoordsModePos
local GetDescColor, GetElementModes = Inner.GetDescColor, Inner.GetElementModes
local MAP_POS_ANCHORS, RefreshClockCVars = Inner.MAP_POS_ANCHORS, Inner.RefreshClockCVars
local ResolveElementAnchor, UpdateClock = Inner.ResolveElementAnchor, Inner.UpdateClock
local UpdateCoords, UpdateLocation = Inner.UpdateCoords, Inner.UpdateLocation
local HideAllMinimapButtons = Inner.HideAllMinimapButtons
local RestartZoomResetTimer, SaveZoomLevel = Inner.RestartZoomResetTimer, Inner.SaveZoomLevel
local HideVaultTooltip, ShowVaultTooltip = Inner.HideVaultTooltip, Inner.ShowVaultTooltip
local GetCalendarLockoutEntries = Inner.GetCalendarLockoutEntries
local HideCalendarTooltip, ShowCalendarTooltip = Inner.HideCalendarTooltip, Inner.ShowCalendarTooltip
local ApplyOmniumFolio, CaptureBlizzardMinimap = Inner.ApplyOmniumFolio, Inner.CaptureBlizzardMinimap
local LayoutIndicatorFrames = Inner.LayoutIndicatorFrames
local SyncIndicatorVisibility, DesiredMapParent = Inner.SyncIndicatorVisibility, Inner.DesiredMapParent

-- The setters are called as I.Set<Name> in this file: ApplyMinimap is close to
-- Lua's limit of 60 upvalues per function, and I costs one where a local per
-- setter costs six.

-- Shared state: one copy per file. A write goes through the Set<Name>
-- function of ns._internals, which hands the value to every copy.
local flyoutToggle
Inner.flyoutToggleSetters[#Inner.flyoutToggleSetters + 1] = function(val) flyoutToggle = val end
local flyoutPanel
Inner.flyoutPanelSetters[#Inner.flyoutPanelSetters + 1] = function(val) flyoutPanel = val end
local coordPanel
Inner.coordFrameSetters[#Inner.coordFrameSetters + 1] = function(val) coordPanel = val end
local coordTimer
Inner.coordTickerSetters[#Inner.coordTickerSetters + 1] = function(val) coordTimer = val end
-- The clock, zone text and FPS readout sit this far above the map: other addons
-- pin their minimap icons at fixed frame levels around 2000, and icons above the
-- text would cover it. A field, not a local: ApplyMinimap is near the upvalue cap.
SKIN._INFO_TEXT_LEVEL = 2100
-- A middle click on the map: the micro menu, under Open Micro Menu on Middle
-- Click (read live). Run by the interceptor over the map and by the clock and
-- the FPS readout, which sit above the interceptor and would take the click.
function SKIN._MapMiddleClick()
    if not SKIN._ToggleMicroMenu then return end
    local mapCfg = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
    if mapCfg and mapCfg.openMicroMenuOnMiddleClick == false then return end
    SKIN._ToggleMicroMenu()
end
local clockPanel
Inner.clockFrameSetters[#Inner.clockFrameSetters + 1] = function(val) clockPanel = val end
local clockBack
Inner.clockBgSetters[#Inner.clockBgSetters + 1] = function(val) clockBack = val end
local locationPanel
Inner.locationFrameSetters[#Inner.locationFrameSetters + 1] = function(val) locationPanel = val end
local locationBack
Inner.locationBgSetters[#Inner.locationBgSetters + 1] = function(val) locationBack = val end

local clockTimer
local fpsBack
local difficultyText
local addonButtonPoll = nil

-- Set while Blizzard's Toggle Minimap key has hidden the map (the hook, in CUI_Minimap_Lifecycle.lua, sits below
-- UpdateMinimapVisibility); every visibility pass then keeps the map hidden.
local _mmKeyHidden
Inner.mmKeyHiddenSetters[#Inner.mmKeyHiddenSetters + 1] = function(val) _mmKeyHidden = val end

local function ApplyMinimap()
    if TEMP_DISABLED.minimap then return end
    if InCombatLockdown() then
        QueueApplyAll()
        return
    end

    local p = SKIN.db.profile.minimap
    p.enabled = true
    local blizz = SKIN._MinimapBlizz()

    -- Rotate Minimap: enforce the CVar to match our setting (out of combat only).
    CludesUI.SetCVar("rotateMinimap", p.rotateMinimap and "1" or "0", "CludesUIMinimap")
    -- Icon Size: nothing while unset (Edit Mode's value stands).
    SKIN._ApplyMinimapIconScale()

    local mapFrame = Minimap
    if not mapFrame then return end

    if not p.enabled then
        -- Untouched this session: do nothing (zero interference with other addons).
        if not GetFFD(mapFrame).active then return end
        -- Was active, now disabled: only a reload hands control back to Blizzard cleanly; the options toggle prompts for it.
        return
    end

    -- Ensure Blizzard_TimeManager is loaded so GameTimeFrame (calendar) exists
    if not _G.GameTimeFrame and C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_TimeManager")
    end

    -- Snapshot Blizzard's native size/position before we modify anything
    CaptureBlizzardMinimap()

    -- Reparent out of MinimapCluster so its layout cannot override our size, and so the
    -- native render is clipped by the frame we own rather than by Blizzard's cluster.
    -- Deferred via C_Timer.After(0) to avoid tainting the secure frame environment when
    -- ApplyMinimap fires during a ShowUIPanel/World Map open -- that taint causes
    -- ADDON_ACTION_BLOCKED when the dungeon pin data provider later calls the protected SetPropagateMouseClicks() on map pins.
    local needsClusterHide = MinimapCluster and MinimapCluster:IsShown()
    -- A cropped canvas's parent is built later in this pass, so the first crop has
    -- to schedule the reparent on the layout frame's absence.
    local needsReparent = mapFrame:GetParent() ~= DesiredMapParent(mapFrame)
        or (SKIN._MapCrop(p, p.mapSize or 140) > 0 and not GetFFD(mapFrame).layoutFrame)
    if needsReparent or needsClusterHide then
        C_Timer.After(0, function()
            if InCombatLockdown() then
                QueueApplyAll()
                return
            end
            local wanted = DesiredMapParent(mapFrame)
            if mapFrame:GetParent() ~= wanted then mapFrame:SetParent(wanted) end
            if needsClusterHide and MinimapCluster then
                MinimapCluster:SetAlpha(0)
                MinimapCluster:EnableMouse(false)
            end
            -- The cluster's Edit Mode selection box ignores that alpha.
            SKIN._SuppressMinimapSelection()
        end)
    end
    -- Blizzard reparents the minimap during housing transitions and other events; hook SetParent to force it back.
    if not GetFFD(mapFrame).parentGuard then
        GetFFD(mapFrame).parentGuard = true
        hooksecurefunc(mapFrame, "SetParent", function()
            local wanted = DesiredMapParent(mapFrame)
            if mapFrame:GetParent() ~= wanted then
                if InCombatLockdown() then
                    -- Dropping it would leave the map parented to -- and clipped by --
                    -- whatever reparented it (the cluster, on a battleground or housing
                    -- transition) for the rest of the session.
                    QueueApplyAll()
                else
                    mapFrame:SetParent(wanted)
                end
            end
        end)
        -- Lock strata/level so Blizzard can't change them during transitions
        if mapFrame.SetFixedFrameStrata then mapFrame:SetFixedFrameStrata(true) end
        if mapFrame.SetFixedFrameLevel then mapFrame:SetFixedFrameLevel(true) end
    end
    -- Visibility-aware terminal: an unconditional Show() here would force-show the
    -- minimap for a frame on EVERY rebuild (blink at visibility never/mouseover, e.g.
    -- settings-override transitions), before the deferred sweep corrects it. Render the profile's visibility directly instead.
    do
        local vis = CludesUI.EvalVisibility and p and CludesUI.EvalVisibility(p)
        -- Opacity in every state: a hidden map carries it into its next Show().
        SKIN._WriteMapAlpha(mapFrame, p)
        if _mmKeyHidden then
            mapFrame:Hide()
        elseif not CludesUI.EvalVisibility or vis == true then
            mapFrame:Show()
        elseif vis == "mouseover" then
            -- Idle state is a real Hide(), not alpha 0 -- see UpdateMinimapVisibility.
            if mapFrame:IsMouseOver() then
                mapFrame:Show()
            else
                mapFrame:Hide()
            end
        elseif vis then
            mapFrame:Show()
        else
            mapFrame:Hide()
        end
    end

    -- Middle-click interceptor: transparent frame over the minimap passing left/right
    -- clicks through but routing middle-click to our micro menu instead of the ping
    -- (zero taint risk). Also the SQUARE mouse surface: the Minimap's own hit region
    -- stays circular, so wheel zoom dies in the square skin's corners -- this overlay covers the full rect and handles the wheel there.
    if not GetFFD(mapFrame).pingBlocker then
        local clickBlock = CreateFrame("Frame", nil, mapFrame)
        clickBlock:SetAllPoints()
        clickBlock:SetFrameLevel(mapFrame:GetFrameLevel() + 10)
        clickBlock:SetPassThroughButtons("LeftButton", "RightButton")
        clickBlock:SetPropagateMouseMotion(true)
        clickBlock:SetScript("OnMouseUp", function(_, button)
            if button == "MiddleButton" then SKIN._MapMiddleClick() end
        end)
        clickBlock:SetScript("OnMouseWheel", function(_, delta)
            local mapCfg = SKIN.db and SKIN.db.profile.minimap
            if not mapCfg or not mapCfg.scrollZoom then return end
            local zoom = mapFrame:GetZoom()
            if delta > 0 then
                zoom = min(zoom + 1, 5)
            else
                zoom = max(zoom - 1, 0)
            end
            mapFrame:SetZoom(zoom)
            SaveZoomLevel()
            RestartZoomResetTimer()
        end)
        -- Map-region hover reveal, entry-path-proof: the Minimap's motion focus follows
        -- its CIRCULAR hit region, so entering the square skin through a corner (or
        -- directly onto an unhooked child) never fires its OnEnter. This overlay covers
        -- the FULL rect and, with SetPropagateMouseMotion, gets enter/leave while still
        -- passing motion through (_HVRevealMapHover self-guards via region + dedupe).
        clickBlock:HookScript("OnEnter", function()
            if SKIN._HVRevealMapHover then SKIN._HVRevealMapHover() end
        end)
        GetFFD(mapFrame).pingBlocker = clickBlock
    end

    for _, name in ipairs(minimapDecorations) do
        local widget = _G[name]
        -- Blizzard Style keeps the stock compass ring (placed once the map has
        -- its size); Classic WoW UI draws its own ring and hides it like CUI.
        if widget and not (blizz and not SKIN._MinimapClassic() and name == "MinimapCompassTexture") then
            widget:Hide()
        end
    end
    -- WoW Forever's Rotate Minimap shows a fixed ring under the compass, and
    -- Blizzard re-shows it on every rotate change without touching its alpha;
    -- the looks that hide the compass keep it invisible the same way.
    if CludesUI.IS_FOREVER and SKIN._MinimapStyle() ~= "blizzard" then
        local underlay = _G.MinimapCompassTextureUnderlay
        if underlay then underlay:SetAlpha(0) end
    end
    -- The addon compartment is placed (or parked) by EBS._ApplyAddonCompartment
    -- at the end of this pass, once the map has its final size and position.

    -- The stock map is round and Forever Square square; the stored shape waits for the CUI look.
    local shape = SKIN._MapShape(p)
    local round = (shape == "circle" or shape == "textured_circle")
    local isRectangular = (shape == "rectangular")

    if GetFFD(mapFrame).bg then GetFFD(mapFrame).bg:SetAlpha(0) end

    local red, green, blue, borderA = GetBorderStyleColor(p)
    -- Hide the circular quest area ring on square minimaps
    if mapFrame.SetArchBlobRingScalar then mapFrame:SetArchBlobRingScalar(round and 1 or 0) end
    if mapFrame.SetQuestBlobRingScalar then mapFrame:SetQuestBlobRingScalar(round and 1 or 0) end

    mapFrame:SetScale(1.0)
    local mapPx = p.mapSize or 140
    -- Blizzard's map projection and native player arrow require a square Minimap
    -- canvas. Rectangular mode therefore crops that square canvas with a centered
    -- 4:3 mask; resizing the Blizzard frame itself makes the terrain slide away
    -- from the arrow as zoom changes. A square frame's title bar crops it the same
    -- way, with the crop mask cut for its size (EBS._MapCrop).
    mapFrame:SetSize(mapPx, mapPx)
    local cropPx, cropMask = SKIN._MapCrop(p, mapPx)
    local maskID = round and 186178 or cropMask or 130937
    mapFrame:SetMaskTexture(maskID)
    -- Minimap button libraries and map pins read this global to place their
    -- buttons and pins on the map's edge; the 4:3 crop keeps square corners.
    -- Leave a definition another addon made alone.
    if GetMinimapShape == nil or GetMinimapShape == SKIN._shapeFn then
        local mapShapeName = round and "ROUND" or "SQUARE"
        if SKIN._shapeName ~= mapShapeName then
            SKIN._shapeName = mapShapeName
            SKIN._shapeFn = function() return mapShapeName end
            GetMinimapShape = SKIN._shapeFn
        end
    end
    mapFrame:SetHitRectInsets(0, 0, cropPx, cropPx)
    if cropPx > 0 and not GetFFD(mapFrame).layoutFrame then
        local layoutInfo = CreateFrame("Frame", nil, UIParent)
        layoutInfo:EnableMouse(false)
        GetFFD(mapFrame).layoutFrame = layoutInfo
    end
    do
        local layoutInfo = GetFFD(mapFrame).layoutFrame
        if layoutInfo then
            -- Re-anchored every pass for the reason the border host below is: this
            -- anchor spans the deferred SetParent that hangs the canvas off it.
            layoutInfo:ClearAllPoints()
            layoutInfo:SetPoint("CENTER", mapFrame, "CENTER")
            layoutInfo:SetSize(mapPx, mapPx - 2 * cropPx)
            layoutInfo:SetFrameLevel(mapFrame:GetFrameLevel())
        end
    end
    do
        local clickBlock = GetFFD(mapFrame).pingBlocker
        if clickBlock then
            clickBlock:ClearAllPoints()
            clickBlock:SetAllPoints(GetFFD(mapFrame).layoutFrame or mapFrame)
        end
    end

    if blizz then
        -- Stock styles: the stock chrome (compass ring + top bar, or the vanilla
        -- ring + banner) instead of any CUI border.
        if SKIN._MinimapClassic() then
            SKIN._ApplyClassicMinimapChrome(mapFrame, mapPx)
        else
            SKIN._ApplyBlizzMinimapChrome(mapFrame, mapPx)
            if CludesUI.IS_FOREVER and SKIN._MinimapForever() then SKIN._ApplyForeverDiel(mapFrame, mapPx) end
            -- WoW Forever: a queue eye Action Bars parks on the ring follows a
            -- resize (its anchor on the map already follows a move).
            if CludesUI.IS_FOREVER then
                local ab = CludesUI._ModuleNS.CludesUIActionBars
                if ab then ab.AB_ForeverEyeRelayout() end
            end
        end
        if GetFFD(mapFrame).borderHost then GetFFD(mapFrame).borderHost:Hide() end
        if GetFFD(mapFrame).circBorder then GetFFD(mapFrame).circBorder:Hide() end
        if GetFFD(mapFrame).texCircBorder then GetFFD(mapFrame).texCircBorder:Hide() end
    elseif SKIN._fvSquare then
        -- A square frame on the Forever client (the WoW Forever look's heavy
        -- bronze frame, or Blizzard Style's slim line) in place of the
        -- CludesUI border (latched for the session, so no CUI border is
        -- ever built beside it).
        SKIN._ApplyForeverSquare(mapFrame)
    elseif not round then
        -- Square / Rectangular: shared border-style engine (solid = PP strips, textured =
        -- BackdropTemplate) on a dedicated host frame -- the engine shows/hides the host
        -- freely, so it must never be the Minimap itself.
        local bs = p.borderSize or 1
        local owner = GetFFD(mapFrame).borderHost
        if not owner then
            owner = CreateFrame("Frame", nil, mapFrame)
            owner:EnableMouse(false)
            GetFFD(mapFrame).borderHost = owner
        end
        -- Re-anchor on EVERY apply, not just create: this pass queues the Minimap's
        -- reparent to UIParent a frame out (above), and a host anchored across that
        -- reparent keeps its stored points while the engine never resolves them --
        -- GetPoint still reports valid TOPLEFT/BOTTOMRIGHT, but the host comes out 0x0
        -- with IsRectValid false (draws nothing while every other property reads
        -- healthy) -- which is why this presented as a border setting that would not
        -- survive a reload even though the stored value was never lost; anchoring only at
        -- creation made it permanent for the session, tracking how much else was loading
        -- at login rather than the actual setting. Re-setting the points forces a layout recompute; harmless no-op otherwise.
        owner:ClearAllPoints()
        owner:SetAllPoints(GetFFD(mapFrame).layoutFrame or mapFrame)
        -- Same level as the minimap keeps the border under all child buttons; Show Behind drops it under the map surface for the Shadow style.
        owner:SetFrameLevel(
            p.borderBehind and math.max(0, mapFrame:GetFrameLevel() - 1) or mapFrame:GetFrameLevel()
        )
        owner:SetAlpha(1)
        -- Exact size beside the legacy step (nil = the legacy path unchanged).
        local pixel = CludesUI.BorderPx(p.borderSizePx, bs, p.borderTexture or "solid")
        CludesUI.ApplyBorderStyle(
            owner,
            bs,
            red,
            green,
            blue,
            borderA,
            p.borderTexture or "solid",
            p.borderTextureOffset,
            p.borderTextureOffsetY,
            p.borderTextureShiftX,
            p.borderTextureShiftY,
            "minimap",
            bs,
            nil,
            pixel
        )
        if GetFFD(mapFrame).circBorder then GetFFD(mapFrame).circBorder:Hide() end
        if GetFFD(mapFrame).texCircBorder then GetFFD(mapFrame).texCircBorder:Hide() end
    elseif p.shape == "circle" then
        -- Circle: solid colored disc behind the minimap, slightly larger = border ring
        if GetFFD(mapFrame).borderHost then GetFFD(mapFrame).borderHost:Hide() end
        if not GetFFD(mapFrame).circBorder then
            local disc = CreateFrame("Frame", nil, mapFrame)
            disc:SetFrameLevel(mapFrame:GetFrameLevel() - 1)
            local texture = disc:CreateTexture(nil, "BACKGROUND")
            texture:SetAllPoints(disc)
            texture:SetTexture("Interface\\Common\\CommonMaskCircle")
            disc._tex = texture
            GetFFD(mapFrame).circBorder = disc
        end
        local bs = p.borderSize or 1
        local circBorder = GetFFD(mapFrame).circBorder
        circBorder:ClearAllPoints()
        circBorder:SetPoint("TOPLEFT", mapFrame, "TOPLEFT", -bs, bs)
        circBorder:SetPoint("BOTTOMRIGHT", mapFrame, "BOTTOMRIGHT", bs, -bs)
        circBorder._tex:SetVertexColor(red, green, blue, 1)
        circBorder:Show()
        if GetFFD(mapFrame).texCircBorder then GetFFD(mapFrame).texCircBorder:Hide() end
    elseif p.shape == "textured_circle" then
        -- Textured Circle: void ring border, hide the solid circle border
        if GetFFD(mapFrame).borderHost then GetFFD(mapFrame).borderHost:Hide() end
        if GetFFD(mapFrame).circBorder then GetFFD(mapFrame).circBorder:Hide() end
        if not GetFFD(mapFrame).texCircBorder then
            local ring = mapFrame:CreateTexture(nil, "OVERLAY", nil, 7)
            ring:SetAtlas("wowlabs_minimapvoid-ring-single")
            GetFFD(mapFrame).texCircBorder = ring
        end
        local inset = 2
        local texCircBorder = GetFFD(mapFrame).texCircBorder
        texCircBorder:ClearAllPoints()
        texCircBorder:SetPoint("TOPLEFT", mapFrame, "TOPLEFT", -inset, inset)
        texCircBorder:SetPoint("BOTTOMRIGHT", mapFrame, "BOTTOMRIGHT", inset, -inset)
        texCircBorder:SetVertexColor(red, green, blue, 1)
        texCircBorder:Show()
    end

    -- Live-update border on accent change, only while the border actually resolves to the accent (accent swatch active, no class colour override).
    -- Neither square frame on the Forever client draws an CUI border to recolour.
    if p.useClassColor and not p.borderUseClassColor and not SKIN._fvSquare then
        if not GetFFD(mapFrame).accentBorderCB then
            GetFFD(mapFrame).accentBorderCB = function(ar, ag, ab)
                -- Registration outlives mode switches: re-check before recoloring.
                local mapCfg = SKIN.db and SKIN.db.profile.minimap
                if not mapCfg or not mapCfg.useClassColor or mapCfg.borderUseClassColor then return end
                local owner = GetFFD(mapFrame).borderHost
                if owner and owner:IsShown() then CludesUI.SetBorderStyleColor(owner, ar, ag, ab, 1) end
                local callback = GetFFD(mapFrame).circBorder
                if callback and callback:IsShown() then callback._tex:SetVertexColor(ar, ag, ab, 1) end
                local tcb = GetFFD(mapFrame).texCircBorder
                if tcb and tcb:IsShown() then tcb:SetVertexColor(ar, ag, ab, 1) end
            end
        end
        CludesUI.RegAccent({ type = "callback", fn = GetFFD(mapFrame).accentBorderCB })
    end

    -- Custom housing overlay: our own texture behind the minimap showing the housing indoor map when Blizzard hides the real content. No Blizzard frame manipulation.
    if not GetFFD(mapFrame).housingTex then
        local widget = CreateFrame("Frame", nil, mapFrame)
        widget:SetAllPoints(GetFFD(mapFrame).layoutFrame or mapFrame)
        widget:SetFrameLevel(mapFrame:GetFrameLevel() + 1)
        local texture = widget:CreateTexture(nil, "ARTWORK")
        if round then
            local inset = -mapPx * 0.10
            texture:SetPoint("TOPLEFT", widget, "TOPLEFT", inset, -inset)
            texture:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -inset, inset)
        elseif cropPx > 0 then
            texture:SetSize(mapPx, mapPx)
            texture:SetPoint("CENTER", widget, "CENTER")
        else
            texture:SetAllPoints(widget)
        end
        if round or cropPx > 0 then
            local mask = widget:CreateMaskTexture()
            mask:SetAllPoints(widget)
            -- The housing frame already has the visible size, so it takes a
            -- whole-frame mask: Rectangular's full rectangular one, a square
            -- frame's crop the plain square (the canvas takes the crop masks).
            mask:SetTexture(
                isRectangular and "Interface\\AddOns\\CludesUIMinimap\\Media\\minimap_rectangular-mask.blp"
                    or (round and maskID)
                    or 130937
            )
            texture:AddMaskTexture(mask)
            widget._mask = mask
            widget._maskAttached = true
        end
        widget._isCircle = round
        widget._tex = texture
        widget:Hide()
        GetFFD(mapFrame).housingFrame = widget
        GetFFD(mapFrame).housingTex = texture
        -- Watch for MinimapBackdrop atlas changes to detect housing
        local backdrop = _G.MinimapBackdrop
        if backdrop then
            local function CheckHousing()
                local housingAtlas
                local regions = { backdrop:GetRegions() }
                for ri = 1, #regions do
                    local region = regions[ri]
                    if region and region.GetAtlas then
                        local atlas = region:GetAtlas()
                        if atlas and atlas:find("housing") then
                            housingAtlas = atlas
                            break
                        end
                    end
                end
                if housingAtlas then
                    if widget._isCircle then
                        texture:SetAtlas(housingAtlas)
                    else
                        texture:SetTexture("Interface\\AddOns\\CludesUIMinimap\\Media\\housing-minimap.png")
                    end
                    widget:Show()
                else
                    widget:Hide()
                end
            end
            GetFFD(mapFrame).checkHousing = CheckHousing
            -- Check on zone transitions
            if not GetFFD(mapFrame).housingZoneHook then
                GetFFD(mapFrame).housingZoneHook = true
                local zf = CreateFrame("Frame")
                zf:RegisterEvent("PLAYER_ENTERING_WORLD")
                zf:RegisterEvent("ZONE_CHANGED_NEW_AREA")
                zf:RegisterEvent("ZONE_CHANGED_INDOORS")
                zf:SetScript("OnEvent", function() C_Timer.After(0.5, CheckHousing) end)
            end
        end
    else
        -- Update existing housing frame on reapply (shape/mask can change live).
        local widget = GetFFD(mapFrame).housingFrame
        if widget then
            widget:ClearAllPoints()
            widget:SetAllPoints(GetFFD(mapFrame).layoutFrame or mapFrame)
            widget:SetFrameLevel(mapFrame:GetFrameLevel() + 1)
            widget._isCircle = round
            if widget._tex then
                widget._tex:ClearAllPoints()
                if round then
                    local inset = -mapPx * 0.10
                    widget._tex:SetPoint("TOPLEFT", widget, "TOPLEFT", inset, -inset)
                    widget._tex:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -inset, inset)
                elseif cropPx > 0 then
                    widget._tex:SetSize(mapPx, mapPx)
                    widget._tex:SetPoint("CENTER", widget, "CENTER")
                else
                    widget._tex:SetAllPoints(widget)
                end
            end
            if round or cropPx > 0 then
                if not widget._mask then
                    local mask = widget:CreateMaskTexture()
                    mask:SetAllPoints(widget)
                    widget._mask = mask
                end
                if widget._tex and not widget._maskAttached then
                    widget._tex:AddMaskTexture(widget._mask)
                    widget._maskAttached = true
                end
                widget._mask:SetTexture(
                    isRectangular
                            and "Interface\\AddOns\\CludesUIMinimap\\Media\\minimap_rectangular-mask.blp"
                        or (round and maskID)
                        or 130937
                )
                widget._mask:Show()
            elseif widget._mask then
                if widget._tex and widget._maskAttached then
                    pcall(widget._tex.RemoveMaskTexture, widget._tex, widget._mask)
                    widget._maskAttached = false
                end
                widget._mask:Hide()
            end
        end
    end
    -- Shape changes do not fire a zone event. Reuse the existing housing detector
    -- so atlas/texture selection follows the new shape immediately.
    if GetFFD(mapFrame).checkHousing then GetFFD(mapFrame).checkHousing() end
    -- Clamp to the screen, a cropped map's whole square canvas included: the engine
    -- keeps the canvas's terrain on screen, so a canvas whose hidden strip passes the
    -- top or bottom edge slides its terrain inside the frame and leaves a strip with
    -- no map at that edge. A cropped map therefore stops that strip short of the top
    -- and bottom edges; the Unlock Mode box follows the canvas there.
    mapFrame:SetClampedToScreen(true)
    local bInset = round and (p.borderSize or 1) or 0
    mapFrame:SetClampRectInsets(-bInset, bInset, bInset, -bInset)
    -- Force the engine to re-render at the new size: nudge zoom, restore same frame.
    local curZoom = mapFrame:GetZoom()
    mapFrame:SetZoom(curZoom > 0 and 0 or 1)
    mapFrame:SetZoom(curZoom)

    -- Zoom buttons: parent to the minimap bottom-right, raise above the map surface,
    -- hook SetPoint so Blizzard can't re-anchor them (Midnight uses Minimap.ZoomIn/
    -- ZoomOut, not global MinimapZoomIn). With Zoom +/- Icons unchecked they live under
    -- the hidden frame instead, so Blizzard's hover show/fade never renders them; re-checking reparents them back.
    local zoomInBtn = mapFrame.ZoomIn or _G.MinimapZoomIn
    local zoomOutBtn = mapFrame.ZoomOut or _G.MinimapZoomOut
    local hideZoom = p.hideZoomButtons
    if hideZoom and (zoomInBtn or zoomOutBtn) and not SKIN._hiddenFrame then
        SKIN._hiddenFrame = CreateFrame("Frame")
        SKIN._hiddenFrame:Hide()
    end
    if zoomInBtn then
        zoomInBtn:SetParent(hideZoom and SKIN._hiddenFrame or mapFrame)
        zoomInBtn:SetFrameLevel(mapFrame:GetFrameLevel() + 10)
        SKIN._ZoomAnchor(zoomInBtn, true, mapFrame)
        if SKIN._MinimapClassic() then SKIN._ClassicZoomButton(zoomInBtn, true, mapPx / 140) end
        zoomInBtn:EnableMouse(true)
        zoomInBtn:SetAlpha(1)
        -- Start in Blizzard's between-hovers state (hidden; hover handlers Show/Hide on map enter/leave) so it is not visible from /reload until hovered.
        zoomInBtn:SetShown(mapFrame:IsMouseOver())
        if not GetFFD(zoomInBtn).hooked then
            hooksecurefunc(zoomInBtn, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                SKIN._ZoomAnchor(self, true, mapFrame)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomInBtn).hooked = true
        end
    end
    if zoomOutBtn then
        zoomOutBtn:SetParent(hideZoom and SKIN._hiddenFrame or mapFrame)
        zoomOutBtn:SetFrameLevel(mapFrame:GetFrameLevel() + 10)
        SKIN._ZoomAnchor(zoomOutBtn, false, mapFrame)
        if SKIN._MinimapClassic() then SKIN._ClassicZoomButton(zoomOutBtn, false, mapPx / 140) end
        zoomOutBtn:EnableMouse(true)
        zoomOutBtn:SetAlpha(1)
        -- Same between-hovers start as ZoomIn above
        zoomOutBtn:SetShown(mapFrame:IsMouseOver())
        if not GetFFD(zoomOutBtn).hooked then
            hooksecurefunc(zoomOutBtn, "SetPoint", function(self)
                if GetFFD(self).inHook then return end
                GetFFD(self).inHook = true
                SKIN._ZoomAnchor(self, false, mapFrame)
                GetFFD(self).inHook = false
            end)
            GetFFD(zoomOutBtn).hooked = true
        end
    end

    -- Map-region hover reveal (zoom buttons + hover-mode folio). Blizzard's fader hides
    -- the zoom buttons on the Minimap's OnLeave, which also fires when the mouse moves
    -- onto a mouse-enabled child (clock, FPS text, folio, buttons); OnEnter never fires
    -- when the cursor enters the region directly on such a child. Both route through
    -- EBS._HVRevealMapHover (no-ops off-region, self-cancelling exit watcher); hooked children's own OnEnter covers direct entry.
    if not GetFFD(mapFrame).hoverRevealHooked then
        GetFFD(mapFrame).hoverRevealHooked = true
        mapFrame:HookScript("OnEnter", function() SKIN._HVRevealMapHover() end)
        -- Real exits hide instantly (matching Blizzard's zoom fade); moving onto a child keeps the reveal alive and the watcher covers the exit from there.
        mapFrame:HookScript("OnLeave", function(self)
            if SKIN._HoverStillOver(self) then
                SKIN._HVRevealMapHover()
            else
                SKIN._HVHideNow()
            end
        end)
    end

    if zoomInBtn and not GetFFD(zoomInBtn).zoomSaveHooked then
        zoomInBtn:HookScript("OnClick", function()
            SaveZoomLevel()
            RestartZoomResetTimer()
        end)
        GetFFD(zoomInBtn).zoomSaveHooked = true
    end
    if zoomOutBtn and not GetFFD(zoomOutBtn).zoomSaveHooked then
        zoomOutBtn:HookScript("OnClick", function()
            SaveZoomLevel()
            RestartZoomResetTimer()
        end)
        GetFFD(zoomOutBtn).zoomSaveHooked = true
    end

    -- Mark zoom buttons so GatherMinimapButtons skips them
    if zoomInBtn then flyoutOwnedFrames[zoomInBtn] = true end
    if zoomOutBtn then flyoutOwnedFrames[zoomOutBtn] = true end

    -- Flyout toggle button (bottom-left corner) -- create before hiding children
    CreateFlyoutToggle()

    HideAllMinimapButtons()

    -- Show/hide flyout toggle based on whether any grouped buttons exist
    local groupedButtons = CollectFlyoutButtons()
    local mp2 = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
    local hideGroupBtn = mp2 and mp2.hideExtraBtns and mp2.hideExtraBtns.groupButton
    if #groupedButtons > 0 and not hideGroupBtn then
        flyoutToggle:Show()
    else
        flyoutToggle:Hide()
    end

    -- Poll for late-loading addons that attach buttons after ADDON_LOADED
    if not addonButtonPoll then
        addonButtonPoll = CreateFrame("Frame")
        addonButtonPoll:RegisterEvent("ADDON_LOADED")
        local pollPending = false
        addonButtonPoll:SetScript("OnEvent", function()
            if pollPending then return end
            pollPending = true
            C_Timer.After(0.1, function()
                pollPending = false
                HideAllMinimapButtons()
                -- New buttons may have appeared: rebuild the grid on next open.
                InvalidateFlyout()
                -- If already open, rebuild now so they appear without a reopen.
                if flyoutPanel and flyoutPanel:IsShown() then BuildFlyoutContents() end
            end)
        end)
    end
    addonButtonPoll:Show()

    -- Rebuild on next open so button-list changes (ungroup, new addon, profile swap) are picked up and buttons HideAllMinimapButtons just hid are re-shown.
    InvalidateFlyout()
    -- Close the flyout if it was open (layout may have changed)
    HideFlyoutPanel()

    -- Hide Blizzard zone text (we use our own location bar)
    local zoneBtn = MinimapZoneTextButton
    if zoneBtn then zoneBtn:Hide() end
    if MinimapCluster and MinimapCluster.ZoneTextButton then MinimapCluster.ZoneTextButton:Hide() end
    if MinimapZoneText then MinimapZoneText:Hide() end

    RefreshClockCVars()

    -- Clock -- none, inside the map, or boxed on the map edge
    local clockMode, locationMode = GetElementModes(p)
    if clockMode ~= "none" then
        if not clockBack then
            Inner.SetClockBg(CreateFrame("Button", nil, mapFrame, "BackdropTemplate"))
            clockBack:SetSize(80, 16)
            clockBack:SetPoint("TOP", mapFrame, "TOP", 0, 7)
            clockBack:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            clockBack:SetFrameLevel(mapFrame:GetFrameLevel() + SKIN._INFO_TEXT_LEVEL)
            clockBack:RegisterForClicks("AnyUp")
            clockBack:SetScript("OnClick", function(_, btnFrame)
                -- The clock sits above the map's middle-click interceptor, which lets
                -- only the left and right buttons through: the clock acts on those two,
                -- and a middle click does here what it does on the map.
                if btnFrame ~= "LeftButton" and btnFrame ~= "RightButton" then
                    if btnFrame == "MiddleButton" then SKIN._MapMiddleClick() end
                    return
                end
                -- With the Great Vault hover tooltip assigned, clicking the clock opens the vault (same as the Great Vault button), not the clock config.
                -- WoW Forever has no Great Vault: a saved "vault" reads as none there.
                local mapCfg = SKIN.db and SKIN.db.profile.minimap
                if mapCfg and mapCfg.clockHoverTooltip == "vault" and not CludesUI.IS_FOREVER then
                    CludesUI.ToggleGreatVault()
                    return
                end
                if ToggleTimeManager then ToggleTimeManager() end
            end)
        end
        if not clockPanel then
            Inner.SetClockFrame(clockBack:CreateFontString(nil, "OVERLAY"))
            ApplyMinimapFont(clockPanel, 10)
            clockPanel:SetPoint("CENTER", clockBack, "CENTER", 0, 0)
            clockPanel:SetTextColor(1, 1, 1, 0.9)
        end
        local cxOff = p.clockOffsetX or 0
        local cyOff = p.clockOffsetY or 0
        if clockMode == "inside" then
            clockBack:SetBackdropColor(0, 0, 0, 0)
        else
            local ar, ag, ab = SKIN._EdgeBoxColor(p)
            clockBack:SetBackdropColor(ar, ag, ab, 1)
        end
        local cpt, crel, cbx, cby = ResolveElementAnchor(p.clockPosition or "top", clockMode, round)
        clockBack:ClearAllPoints()
        clockBack:SetPoint(cpt, GetFFD(mapFrame).layoutFrame or mapFrame, crel, cbx + cxOff, cby + cyOff)
        -- Align the TEXT edge with the anchor so it lands where the coordinates text
        -- would: inside style pins text to the same wrapper corner the wrapper pins to
        -- the map (wrapper is wider, so centered text would drift toward the middle); edge style keeps it centered in the box.
        clockPanel:ClearAllPoints()
        if clockMode == "inside" then
            clockPanel:SetPoint(cpt, clockBack, cpt, 0, 0)
        else
            clockPanel:SetPoint("CENTER", clockBack, "CENTER", 0, 0)
        end
        local cs = p.clockScale or 1.15
        clockBack:SetScale(cs)
        _G._CUBS_ClockBg = clockBack
        clockBack:Show()
        clockPanel:Show()
        if not clockTimer then
            clockTimer = CreateFrame("Frame") -- kept for CVar event + Show/Hide API
            clockTimer._ticker = nil
            clockTimer.Show = function(self)
                if self._ticker then return end
                self._ticker = C_Timer.NewTicker(10, function() UpdateClock() end)
            end
            clockTimer.Hide = function(self)
                if self._ticker then
                    self._ticker:Cancel()
                    self._ticker = nil
                end
            end
            clockTimer:RegisterEvent("CVAR_UPDATE")
            clockTimer:SetScript("OnEvent", function(_, _, cvarName)
                if cvarName == "timeMgrUseMilitaryTime" or cvarName == "timeMgrUseLocalTime" then
                    RefreshClockCVars()
                    UpdateClock()
                end
            end)
        end
        clockTimer:Show()
        UpdateClock()
        -- Hover tooltip (Show on Clock Hover): lockouts or Great Vault, reusing the calendar/vault tooltips and their scaling. Mode read live on each hover.
        if not clockBack._cuiHoverHooked then
            clockBack._cuiHoverHooked = true
            clockBack:SetScript("OnEnter", function(self)
                SKIN._HVRevealMapHover()
                local mapCfg = SKIN.db and SKIN.db.profile.minimap
                local mode = (mapCfg and mapCfg.clockHoverTooltip) or "none"
                if CludesUI.IS_FOREVER and mode == "vault" then mode = "none" end
                if mode == "lockouts" then
                    if CludesUI.InProtectedInstance() then return end
                    local entries = GetCalendarLockoutEntries()
                    if entries then ShowCalendarTooltip(self, entries) end
                elseif mode == "vault" then
                    ShowVaultTooltip(self)
                end
            end)
            clockBack:SetScript("OnLeave", function()
                HideCalendarTooltip()
                HideVaultTooltip()
            end)
        end
    else
        if clockBack then clockBack:Hide() end
        if clockPanel then clockPanel:Hide() end
        if clockTimer then clockTimer:Hide() end
    end

    LayoutIndicatorFrames(mapFrame, p, round)

    -- Hook Blizzard mail/crafting Show/Hide to sync our custom indicator visibility
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    local mailFrame = indicator and indicator.MailFrame
    local craftingFrame = indicator and indicator.CraftingOrderFrame
    if mailFrame and not GetFFD(mailFrame).visHooked then
        GetFFD(mailFrame).visHooked = true
        local function onMailChange()
            local mapCfg = SKIN.db and SKIN.db.profile.minimap
            if not mapCfg or not mapCfg.enabled then return end
            SyncIndicatorVisibility()
            local s = SKIN._MapShape(mapCfg)
            LayoutIndicatorFrames(mapFrame, mapCfg, s == "circle" or s == "textured_circle")
        end
        hooksecurefunc(mailFrame, "Show", onMailChange)
        hooksecurefunc(mailFrame, "Hide", onMailChange)
    end
    if craftingFrame and not GetFFD(craftingFrame).visHooked then
        GetFFD(craftingFrame).visHooked = true
        local function onCraftChange()
            local mapCfg = SKIN.db and SKIN.db.profile.minimap
            if not mapCfg or not mapCfg.enabled then return end
            SyncIndicatorVisibility()
            local s = SKIN._MapShape(mapCfg)
            LayoutIndicatorFrames(mapFrame, mapCfg, s == "circle" or s == "textured_circle")
        end
        hooksecurefunc(craftingFrame, "Show", onCraftChange)
        hooksecurefunc(craftingFrame, "Hide", onCraftChange)
    end

    -- Location bar -- none, inside the map, or boxed on the map edge
    if locationMode ~= "none" then
        if not locationBack then
            Inner.SetLocationBg(CreateFrame("Frame", nil, mapFrame, "BackdropTemplate"))
            locationBack:SetSize(120, 18)
            locationBack:SetPoint("BOTTOM", mapFrame, "BOTTOM", 0, -7)
            locationBack:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground" })
            locationBack:SetFrameLevel(mapFrame:GetFrameLevel() + SKIN._INFO_TEXT_LEVEL)
            locationBack:RegisterEvent("ZONE_CHANGED")
            locationBack:RegisterEvent("ZONE_CHANGED_INDOORS")
            locationBack:RegisterEvent("ZONE_CHANGED_NEW_AREA")
            locationBack:RegisterEvent("PLAYER_REGEN_ENABLED") -- guardrails-allow: combat-deferral by Cludes: moved unchanged by the file split; multi-event zone text listener, kept as is in the combat queue migration
            locationBack:SetScript("OnEvent", function() UpdateLocation() end)
        end
        if not locationPanel then
            Inner.SetLocationFrame(locationBack:CreateFontString(nil, "OVERLAY"))
            ApplyMinimapFont(locationPanel, 10)
            locationPanel:SetPoint("CENTER", locationBack, "CENTER", 0, 0)
            locationPanel:SetTextColor(1, 1, 1, 0.9)
        end
        local lxOff = p.locationOffsetX or 0
        local lyOff = p.locationOffsetY or 0
        if locationMode == "inside" then
            locationBack:SetBackdropColor(0, 0, 0, 0)
        else
            local ar, ag, ab = SKIN._EdgeBoxColor(p)
            locationBack:SetBackdropColor(ar, ag, ab, 1)
        end
        local lpt, lrel, lbx, lby = ResolveElementAnchor(p.locationPosition or "bottom", locationMode, round)
        locationBack:ClearAllPoints()
        locationBack:SetPoint(lpt, GetFFD(mapFrame).layoutFrame or mapFrame, lrel, lbx + lxOff, lby + lyOff)
        -- Align the TEXT edge with the anchor (see the clock block above): inside pins it to the wrapper corner matching the map anchor, edge keeps it centered.
        locationPanel:ClearAllPoints()
        if locationMode == "inside" then
            locationPanel:SetPoint(lpt, locationBack, lpt, 0, 0)
        else
            locationPanel:SetPoint("CENTER", locationBack, "CENTER", 0, 0)
        end
        if blizz and GetFFD(mapFrame).blizzHeader then
            -- Stock styles: the zone text rides the top bar -- the banner's text
            -- slot under Classic WoW UI, held to the slot by both ends on WoW
            -- Forever's bar (a longer name is cut short with an ellipsis), as
            -- that client's own zone text is (offsets still apply).
            local heading = GetFFD(mapFrame).blizzHeader
            locationBack:SetBackdropColor(0, 0, 0, 0)
            locationBack:ClearAllPoints()
            locationBack:SetPoint("CENTER", heading._zoneSlot or heading, "CENTER", lxOff, lyOff)
            locationPanel:ClearAllPoints()
            if heading._fvBar then
                locationPanel:SetPoint("LEFT", heading._zoneSlot, "LEFT", lxOff, lyOff)
                locationPanel:SetPoint("RIGHT", heading._zoneSlot, "RIGHT", lxOff, lyOff)
                locationPanel:SetWordWrap(false)
            else
                locationPanel:SetPoint("CENTER", locationBack, "CENTER", 0, 0)
            end
        elseif SKIN._fvSquare and SKIN._fvTitleOn then
            -- Either square: the zone text rides the frame's title bar, held
            -- to the bar's band by both ends (a longer name is cut short with
            -- an ellipsis); the offsets still apply.
            local slot = GetFFD(mapFrame).fvTitleSlot
            locationBack:SetBackdropColor(0, 0, 0, 0)
            locationBack:ClearAllPoints()
            locationBack:SetPoint("CENTER", slot, "CENTER", lxOff, lyOff)
            locationPanel:ClearAllPoints()
            locationPanel:SetPoint("LEFT", slot, "LEFT", lxOff, lyOff)
            locationPanel:SetPoint("RIGHT", slot, "RIGHT", lxOff, lyOff)
            locationPanel:SetWordWrap(false)
        end
        local ls = p.locationScale or 1.15
        locationBack:SetScale(ls)
        _G._CUBS_LocationBg = locationBack
        locationBack:Show()
        locationPanel:Show()
        UpdateLocation()
    else
        if locationBack then locationBack:Hide() end
        if locationPanel then locationPanel:Hide() end
    end

    -- Coordinates -- mode (never/hover/always) + anchor position around the map
    if not coordPanel then
        Inner.SetCoordFrame(mapFrame:CreateFontString(nil, "OVERLAY"))
        ApplyMinimapFont(coordPanel, 11)
        coordPanel:SetTextColor(1, 1, 1, 0.9)
    end
    local coordsMode, coordsPos = GetCoordsModePos(p)
    local cpAnchor = MAP_POS_ANCHORS[coordsPos] or MAP_POS_ANCHORS.topLeft
    -- Base offsets (past the heavy band under Forever Square), then the nudges.
    local cpx, cpy = SKIN._FvInsideXY(coordsPos, cpAnchor[3], cpAnchor[4])
    cpx = cpx + (p and p.coordsBelowOffsetX or 0)
    cpy = cpy + (p and p.coordsBelowOffsetY or 0)
    coordPanel:ClearAllPoints()
    coordPanel:SetPoint(cpAnchor[1], GetFFD(mapFrame).layoutFrame or mapFrame, cpAnchor[2], cpx, cpy)
    coordPanel:SetScale(p and p.coordsScale or 1.0)
    _G._CUBS_CoordFrame = coordPanel
    if not coordTimer then
        Inner.SetCoordTicker(CreateFrame("Frame")) -- kept for Show/Hide API
        coordTimer._ticker = nil
        coordTimer.Show = function(self)
            if self._ticker then return end
            self._ticker = C_Timer.NewTicker(0.5, function() UpdateCoords() end)
        end
        coordTimer.Hide = function(self)
            if self._ticker then
                self._ticker:Cancel()
                self._ticker = nil
            end
        end
    end
    if coordsMode == "always" then
        coordPanel:Show()
        coordTimer:Show()
        UpdateCoords()
    else
        coordPanel:Hide()
        coordTimer:Hide()
    end
    -- Hover mode (coords ticker runs only while the map region is hovered) is driven by EBS._HVRevealMapHover via the shared hover-reveal hooks installed above.

    -- FPS/MS readout (Text section): same format/options as the QoL FPS counter.
    if p.showFPS then
        if not fpsBack then
            fpsBack = CreateFrame("Frame", nil, mapFrame)
            fpsBack:SetSize(60, 20)
            fpsBack:SetFrameLevel(mapFrame:GetFrameLevel() + SKIN._INFO_TEXT_LEVEL)
            fpsBack:EnableMouse(false)
            local function MakeFS(size)
                local fontStr = fpsBack:CreateFontString(nil, "OVERLAY")
                ApplyMinimapFont(fontStr, size)
                fontStr:SetTextColor(1, 1, 1, 1)
                return fontStr
            end
            local DIV_W = (Pix.Snap and Pix.Snap(1)) or 1
            local DIV_H = 10
            local DIV_PAD = 6
            local function MakeDivider()
                local skinData = fpsBack:CreateTexture(nil, "OVERLAY")
                skinData:SetColorTexture(1, 1, 1, 1)
                skinData:SetSize(DIV_W, DIV_H)
                return skinData
            end
            -- One FontString per SEGMENT ("58 FPS"): number+suffix rasterize in a single
            -- pass, so spacing can never wobble sub-pixel like two separately snapped
            -- strings. Suffix colour rides an inline escape (Accented Text); SetFormattedText keeps formatting C-side with no template rebuilds.
            local fsFps, worldFs, fsLocal = MakeFS(12), MakeFS(12), MakeFS(12)
            fpsBack._fsAll = { fsFps, worldFs, fsLocal }
            local divWorld = MakeDivider()
            local divLocal = MakeDivider()

            local floor = math.floor
            local function UpdateFPS(self)
                local mapCfg = SKIN.db and SKIN.db.profile.minimap
                -- Numbers render white; the "FPS"/"MS" suffixes take the description colour while FPS/MS is checked in Accented Text (default on).
                local hex = "ffffff"
                if (mapCfg and mapCfg.fpsColorSuffix) ~= false then
                    local _, _, _, hgt = GetDescColor(mapCfg)
                    hex = hgt
                end

                local fps = floor(GetFramerate() + 0.5)
                local showWorld = mapCfg and mapCfg.fpsShowWorldMS
                local _localMS = mapCfg and mapCfg.fpsShowLocalMS
                local showLocal = (_localMS == nil) and true or _localMS
                local _, _, latHome, latWorld = GetNetStats()

                fsFps:ClearAllPoints()
                fsFps:SetPoint("LEFT", self, "LEFT", 0, 0)
                fsFps:SetFormattedText("%d |cff%sFPS|r", fps, hex)
                local totalW = fsFps:GetStringWidth() or 0
                local anchor = fsFps

                if showWorld then
                    divWorld:ClearAllPoints()
                    divWorld:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                    divWorld:Show()
                    worldFs:ClearAllPoints()
                    worldFs:SetPoint("LEFT", divWorld, "RIGHT", DIV_PAD, 0)
                    worldFs:SetFormattedText("%d |cff%sMS|r", latWorld, hex)
                    worldFs:Show()
                    totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + (worldFs:GetStringWidth() or 0)
                    anchor = worldFs
                else
                    divWorld:Hide()
                    worldFs:Hide()
                end

                if showLocal then
                    divLocal:ClearAllPoints()
                    divLocal:SetPoint("LEFT", anchor, "RIGHT", DIV_PAD, 0)
                    divLocal:Show()
                    fsLocal:ClearAllPoints()
                    fsLocal:SetPoint("LEFT", divLocal, "RIGHT", DIV_PAD, 0)
                    fsLocal:SetFormattedText("%d |cff%sMS|r", latHome, hex)
                    fsLocal:Show()
                    totalW = totalW + DIV_PAD + DIV_W + DIV_PAD + (fsLocal:GetStringWidth() or 0)
                else
                    divLocal:Hide()
                    fsLocal:Hide()
                end

                self:SetSize(totalW + 4, 20)
            end

            local elapsed = 0
            fpsBack:SetScript("OnUpdate", function(self, dt)
                elapsed = elapsed + dt
                if elapsed < (self._interval or 3) then return end
                elapsed = 0
                UpdateFPS(self)
            end)
            fpsBack._updateNow = function()
                elapsed = 0
                UpdateFPS(fpsBack)
            end

            -- Hover tooltip (Show on FPS/MS Hover): same dispatch as the clock
            fpsBack:SetScript("OnEnter", function(self)
                SKIN._HVRevealMapHover()
                local mapCfg = SKIN.db and SKIN.db.profile.minimap
                local mode = (mapCfg and mapCfg.fpsHoverTooltip) or "none"
                if CludesUI.IS_FOREVER and mode == "vault" then mode = "none" end
                if mode == "lockouts" then
                    if CludesUI.InProtectedInstance() then return end
                    local entries = GetCalendarLockoutEntries()
                    if entries then ShowCalendarTooltip(self, entries) end
                elseif mode == "vault" then
                    ShowVaultTooltip(self)
                end
            end)
            fpsBack:SetScript("OnLeave", function()
                HideCalendarTooltip()
                HideVaultTooltip()
            end)
            -- With the Great Vault hover tooltip assigned, clicking the readout opens
            -- the vault. Mouse is enabled only while a hover tooltip is assigned, so this never intercepts clicks otherwise.
            fpsBack:SetScript("OnMouseUp", function(_, btnFrame)
                -- Above the map's middle-click interceptor, like the clock.
                if btnFrame == "MiddleButton" then
                    SKIN._MapMiddleClick()
                    return
                end
                if btnFrame ~= "LeftButton" then return end
                local mapCfg = SKIN.db and SKIN.db.profile.minimap
                if mapCfg and mapCfg.fpsHoverTooltip == "vault" and not CludesUI.IS_FOREVER then
                    CludesUI.ToggleGreatVault()
                end
            end)
        end
        local fsz = p.fpsTextSize or 12
        for _, fontStr in ipairs(fpsBack._fsAll) do
            ApplyMinimapFont(fontStr, fsz)
        end
        fpsBack._interval = p.fpsUpdateInterval or 3
        local fAnchor = MAP_POS_ANCHORS[p.fpsPosition or "bottomLeft"] or MAP_POS_ANCHORS.bottomLeft
        -- Past the heavy band under Forever Square.
        local fx, fy = SKIN._FvInsideXY(p.fpsPosition, fAnchor[3], fAnchor[4])
        -- One evenly spaced chain at natural widths; the anchored corner is the stable edge the row breathes from.
        fpsBack:ClearAllPoints()
        fpsBack:SetPoint(
            fAnchor[1],
            GetFFD(mapFrame).layoutFrame or mapFrame,
            fAnchor[2],
            fx + (p.fpsOffsetX or 0),
            fy + (p.fpsOffsetY or 0)
        )
        fpsBack:SetScale(p.fpsScale or 1.0)
        _G._CUBS_FpsBg = fpsBack
        -- Mouse only while a hover tooltip is assigned, so it never blocks map clicks
        -- (WoW Forever reads a saved "vault" as none).
        fpsBack:EnableMouse(
            (p.fpsHoverTooltip or "none") ~= "none"
                and not (CludesUI.IS_FOREVER and p.fpsHoverTooltip == "vault")
        )
        fpsBack:Show()
        fpsBack._updateNow()
    else
        if fpsBack then fpsBack:Hide() end
    end

    -- Instance Difficulty as Text: compact "20M" readout replacing the Blizzard flag
    -- (suppressed above while enabled); event-driven, zero cost while disabled. Count renders white, letter follows the description colour (as FPS/MS suffixes).
    if p.diffTextEnabled then
        if not difficultyText then
            difficultyText = CreateFrame("Frame", nil, mapFrame)
            local fontStr = mapFrame:CreateFontString(nil, "OVERLAY")
            fontStr:SetTextColor(1, 1, 1, 1)
            difficultyText._text = fontStr
            -- Difficulty ID -> suffix letter; count prefix rules alongside.
            local SUFFIX = {
                [1] = "N",
                [2] = "H",
                [23] = "M", -- dungeons
                [14] = "N",
                [15] = "H",
                [16] = "M",
                [233] = "M", -- raids
                [3] = "N",
                [4] = "N",
                [5] = "H",
                [6] = "H", -- legacy raids
                [9] = "N",
                [148] = "N",
                [173] = "N",
                [174] = "H",
                [7] = "LFR",
                [17] = "LFR",
                [205] = "F",
            }
            local FLEX = { [14] = true, [15] = true, [233] = true } -- size = current group
            local NOCOUNT = { [205] = true } -- letter only
            local TW = { [24] = true, [33] = true, [151] = true }
            local EVT = { [18] = true, [19] = true, [30] = true }
            local PVP = { [25] = true, [29] = true, [32] = true, [34] = true, [45] = true }
            local SCEN = { [12] = "S", [38] = "S", [11] = "HS", [39] = "HS", [40] = "MS" }
            local GARRISON = IdSet([[
                1152 1153 1154 1158 1159 1160 1330 1331
            ]])
            -- Difficulty (Reactive): letter colours by tier (normal/scenarios bronze like delves, heroic blue, mythic purple, keystones legendary orange).
            local REACTIVE_HEX = {
                N = "c69b6d",
                H = "0070dd",
                M = "a335ee",
                S = "c69b6d",
                HS = "0070dd",
                MS = "a335ee",
                LFR = "9d9d9d",
                F = "9d9d9d",
                TW = "00ccff",
                EVT = "ffffff",
                PvP = "ffffff",
            }
            difficultyText._update = function(self)
                local result = self._text
                local mp2 = SKIN.db and SKIN.db.profile.minimap
                if not (mp2 and mp2.diffTextEnabled) then
                    result:SetText("")
                    return
                end
                local _, instanceType, diffID, _, maxPlayers, _, _, instanceID, groupSize = GetInstanceInfo()
                if not diffID or diffID == 0 or instanceType == "none" or GARRISON[instanceID] then
                    result:SetText("")
                    return
                end
                -- Letter colour follows Accented Text: Reactive = tier colour, plain Difficulty = flat accent/custom, neither = white; Reactive wins.
                local reactive = mp2.diffTextReactive
                local hex = "ffffff"
                if not reactive and mp2.diffTextAccent then
                    local _, _, _, hgt = GetDescColor(mp2)
                    hex = hgt
                end
                if diffID == 8 then
                    -- Active keystone: key level after the colored M+
                    if reactive then hex = "ff8000" end
                    local lvl = C_ChallengeMode
                        and C_ChallengeMode.GetActiveKeystoneInfo
                        and C_ChallengeMode.GetActiveKeystoneInfo()
                    result:SetFormattedText("|cff%sM+|r%s", hex, (lvl and lvl > 0) and lvl or "")
                    return
                end
                if diffID == 208 then
                    -- Delve: tier number from the scenario header widget
                    if reactive then hex = "c69b6d" end
                    local tier
                    local success, details =
                        pcall(C_UIWidgetManager.GetScenarioHeaderDelvesWidgetVisualizationInfo, 6183)
                    if success and details and details.tierText then
                        tier = tostring(details.tierText):match("%d+")
                    end
                    result:SetFormattedText("|cff%sT|r%s", hex, tier or "")
                    return
                end
                local letter
                if TW[diffID] then
                    letter = "TW"
                elseif EVT[diffID] then
                    letter = "EVT"
                elseif PVP[diffID] then
                    letter = "PvP"
                elseif SCEN[diffID] then
                    letter = SCEN[diffID]
                else
                    letter = SUFFIX[diffID]
                end
                if not letter then
                    result:SetText("")
                    return
                end
                if reactive then hex = REACTIVE_HEX[letter] or "ffffff" end
                local total
                if SUFFIX[diffID] and not NOCOUNT[diffID] then
                    total = FLEX[diffID] and groupSize or maxPlayers
                end
                result:SetFormattedText("%s|cff%s%s|r", (total and total > 0) and total or "", hex, letter)
            end
            difficultyText:SetScript("OnEvent", function(self) self._update(self) end)
        end
        local fontStr = difficultyText._text
        ApplyMinimapFont(fontStr, p.diffTextSize or 12)
        local a = MAP_POS_ANCHORS[p.diffTextPosition or "topLeft"] or MAP_POS_ANCHORS.topLeft
        -- Past the heavy band under Forever Square.
        local dx, dy = SKIN._FvInsideXY(p.diffTextPosition, a[3], a[4])
        fontStr:ClearAllPoints()
        fontStr:SetPoint(
            a[1],
            GetFFD(mapFrame).layoutFrame or mapFrame,
            a[2],
            dx + (p.diffTextOffsetX or 0),
            dy + (p.diffTextOffsetY or 0)
        )
        fontStr:Show()
        difficultyText:RegisterEvent("PLAYER_ENTERING_WORLD")
        difficultyText:RegisterEvent("ZONE_CHANGED_NEW_AREA")
        difficultyText:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
        difficultyText:RegisterEvent("GROUP_ROSTER_UPDATE")
        difficultyText:RegisterEvent("CHALLENGE_MODE_START")
        difficultyText:RegisterEvent("CHALLENGE_MODE_COMPLETED")
        difficultyText:RegisterEvent("CHALLENGE_MODE_RESET")
        difficultyText._update(difficultyText)
    elseif difficultyText then
        difficultyText:UnregisterAllEvents()
        difficultyText._text:Hide()
    end

    -- Mousewheel zoom lives on the square overlay (the Minimap's own hit region is
    -- circular, leaving the square skin's corners wheel-dead); Scroll to Zoom off leaves both wheel-disabled so the wheel falls through to camera zoom.
    do
        local clickBlock = GetFFD(mapFrame).pingBlocker
        if clickBlock then clickBlock:EnableMouseWheel(p.scrollZoom and true or false) end
        mapFrame:EnableMouseWheel(false)
    end

    if not GetFFD(mapFrame).active then
        local saved = p.savedZoom or 0
        if saved >= 0 and saved <= mapFrame:GetZoomLevels() then mapFrame:SetZoom(saved) end
    end

    -- Re-arm (or disarm) the Auto Zoom Reset timer on every apply, so
    -- enabling it or changing the seconds slider in the options takes
    -- effect immediately.
    RestartZoomResetTimer()

    -- Position: only set on first activation; after that, unlock mode owns positioning.
    if not GetFFD(mapFrame).active then
        mapFrame:ClearAllPoints()
        if p.position then
            local pixel, py = p.position.x, p.position.y
            local PPa = CludesUI and CludesUI.PP
            if PPa and pixel and py then
                local es = mapFrame:GetEffectiveScale()
                local isCenterAnchor = (p.position.point == "CENTER")
                    and (p.position.relPoint == "CENTER" or p.position.relPoint == nil)
                if isCenterAnchor and PPa.SnapCenterForDim then
                    pixel = PPa.SnapCenterForDim(pixel, mapFrame:GetWidth() or 0, es)
                    py = PPa.SnapCenterForDim(py, mapFrame:GetHeight() or 0, es)
                elseif PPa.SnapForES then
                    pixel = PPa.SnapForES(pixel, es)
                    py = PPa.SnapForES(py, es)
                end
            end
            mapFrame:SetPoint(p.position.point, UIParent, p.position.relPoint, pixel, py)
        else
            mapFrame:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -10)
        end
    end

    -- Mark module as active so persistent hooks know they can fire
    GetFFD(mapFrame).active = true

    ApplyOmniumFolio()
    SKIN._ApplyAddonCompartment()
    SKIN._ApplyExternalEventButton()
    -- Elements linked to the minimap follow a change of its insets.
    SKIN._NotifyMinimapExtent()
end

-- Blizzard's external event button (a link to an event outside the game,
-- shown and hidden by Blizzard while one runs; a child of MinimapBackdrop,
-- WoW Forever only) stays on the map with the backdrop. Blizzard Style and
-- the WoW Forever look give it the stock spot on the ring (its centre 101.5
-- left of and 0.5 above the map centre at the stock 198px map, scaled with
-- the map); the other looks the map's top-left corner at the folio's scale.
-- Above the ping blocker so it takes the mouse. Method calls on Blizzard's
-- plain button only, every apply pass (Blizzard anchors it once, at load).
function SKIN._ApplyExternalEventButton()
    local backdrop = _G.MinimapBackdrop
    local button = backdrop and backdrop.ExternalEventURLButton
    if not (button and Minimap) then return end
    button:ClearAllPoints()
    if SKIN._MinimapBlizz() and not SKIN._MinimapClassic() then
        button:SetScale(1)
        local s = (Minimap:GetWidth() or 198) / 198
        button:SetPoint("CENTER", Minimap, "CENTER", -101.5 * s, 0.5 * s)
    else
        -- Forever Square steps it in past the heavy band, as the texts inside the map.
        local posX, posY = SKIN._FvInsideXY("top", 2, -2)
        button:SetScale(0.75)
        button:SetPoint("TOPLEFT", GetFFD(Minimap).layoutFrame or Minimap, "TOPLEFT", posX, posY)
    end
    button:SetFrameLevel(Minimap:GetFrameLevel() + 11)
end

Inner.SetApplyMinimap(ApplyMinimap)
Inner.ApplyMinimap = ApplyMinimap
Inner.broken = false
