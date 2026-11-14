if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Minimap_Styles.lua
--
--  The addon compartment and the stock styles (Blizzard Style, Classic WoW
--  UI).
--  Reads the earlier Minimap files through ns._internals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._internals
-- CludesUIMinimap.lua or an earlier CUI_Minimap_*.lua file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local ADDON_NAME, SKIN, GetFFD, Pix = Inner.ADDON_NAME, Inner.EBS, Inner.GetFFD, Inner.PP
local GetElementModes, _customIndicators = Inner.GetElementModes, Inner._customIndicators

-------------------------------------------------------------------------------
--  Addon Compartment
--  Blizzard's addon-compartment button is a child of MinimapCluster, which this
--  module alpha-zeroes and mouse-disables -- so it has to be reparented onto our
--  own Minimap to be visible at all. The old code parked it on a hidden frame
--  unconditionally, which is why hideAddonCompartment (default false) had no
--  effect and the compartment was simply gone with no way to get it back.
--  Handled exactly like the Omnium Folio: plain (non-secure) Blizzard button,
--  so SetParent/SetPoint/SetScale are safe, and the same re-assert hooks keep
--  Blizzard's own relayout from dragging it back into the hidden cluster.
--  Namespace-scoped (EBS fields, not locals).
-------------------------------------------------------------------------------
function SKIN._ParkAddonCompartment(button)
    if not SKIN._hiddenFrame then
        SKIN._hiddenFrame = CreateFrame("Frame")
        SKIN._hiddenFrame:Hide()
    end
    SKIN._compartmentApplying = true
    if button:GetParent() ~= SKIN._hiddenFrame then
        GetFFD(button).origParent = GetFFD(button).origParent or button:GetParent()
        button:SetParent(SKIN._hiddenFrame)
    end
    SKIN._compartmentApplying = false
end

function SKIN._PositionAddonCompartment(button)
    local mp = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
    if not mp or not Minimap then
        return
    end
    SKIN._compartmentApplying = true
    if button:GetParent() ~= Minimap then
        button:SetParent(Minimap)
    end
    button:SetFrameStrata("HIGH")
    button:SetFrameLevel((Minimap:GetFrameLevel() or 0) + 10)
    button:SetScale(mp.addonCompartmentScale or 0.9)
    button:ClearAllPoints()
    -- Anchor the button's chosen corner to the minimap's same corner; X/Y nudge
    -- from there (positive X = right, positive Y = up), same as the folio.
    local corner = mp.addonCompartmentCorner or "TOPRIGHT"
    local placed = false
    if SKIN._MinimapBlizz() then
        -- Stock styles: the stock spot is under the calendar (the button's
        -- top-left to the calendar's bottom-left; calendar hidden = right of the
        -- top bar); any other corner is that corner's diagonal on the compass
        -- ring. The nudges still apply.
        local nx, ny = mp.addonCompartmentX or 0, mp.addonCompartmentY or 0
        if corner == "TOPRIGHT" then
            local cal = _customIndicators.calendar
            local heading = GetFFD(Minimap).blizzHeader
            if cal and cal:IsShown() and heading and heading._fvBar then
                -- WoW Forever's header: centred under the calendar, 1 up.
                button:SetPoint("TOP", cal, "BOTTOM", nx, 1 + ny)
                placed = true
            elseif cal and cal:IsShown() then
                button:SetPoint("TOPLEFT", cal, "BOTTOMLEFT", nx, ny)
                placed = true
            elseif heading then
                button:SetPoint("TOPLEFT", heading, "TOPRIGHT", 1 + nx, ny)
                placed = true
            end
        else
            local mapW = Minimap:GetWidth() or (mp.mapSize or 140)
            local r = (mapW / 2 + 5 * (mapW / 198)) / (button:GetScale() or 1)
            local dx = (corner == "BOTTOMLEFT" or corner == "TOPLEFT") and -0.7071 or 0.7071
            local dy = (corner == "BOTTOMLEFT" or corner == "BOTTOMRIGHT") and -0.7071 or 0.7071
            button:SetPoint("CENTER", Minimap, "CENTER", r * dx + nx, r * dy + ny)
            placed = true
        end
    end
    if not placed then
        button:SetPoint(
            corner,
            GetFFD(Minimap).layoutFrame or Minimap,
            corner,
            mp.addonCompartmentX or 0,
            mp.addonCompartmentY or 0
        )
    end
    -- The cluster's alpha/mouse state does not follow the reparent, and the
    -- pre-fix sessions left it parked on a hidden frame -- re-assert both.
    button:SetAlpha(1)
    button:EnableMouse(true)
    SKIN._compartmentApplying = false
end

function SKIN._ApplyAddonCompartment()
    local button = _G.AddonCompartmentFrame
    if not button then
        return
    end
    local mp = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
    if not mp then
        return
    end

    -- One-time persistent hooks, mirroring the folio's: Blizzard re-anchors and
    -- reparents this button on edit-mode relayouts and cluster updates, often
    -- without a Show(), which would otherwise drop it back into the alpha-0
    -- cluster until /reload.
    if not SKIN._compartmentHooked then
        SKIN._compartmentHooked = true
        local function reassert(self)
            if SKIN._compartmentApplying then
                return
            end
            local m = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
            if not m then
                return
            end
            if m.hideAddonCompartment then
                SKIN._ParkAddonCompartment(self)
            else
                SKIN._PositionAddonCompartment(self)
            end
        end
        hooksecurefunc(button, "Show", reassert)
        hooksecurefunc(button, "SetParent", reassert)
        hooksecurefunc(button, "SetPoint", reassert)
        hooksecurefunc(button, "SetScale", reassert)
        -- Hovering the compartment counts as hovering the map region, so the
        -- hover-reveal elements stay alive while the cursor is on it.
        button:HookScript("OnEnter", function()
            if SKIN._HVRevealMapHover then
                SKIN._HVRevealMapHover()
            end
        end)
    end

    if mp.hideAddonCompartment then
        SKIN._ParkAddonCompartment(button)
        return
    end
    SKIN._PositionAddonCompartment(button)
    -- Blizzard shows/hides this button itself from the number of addons that
    -- registered a compartment entry -- only nudge it when at least one did, so
    -- an empty compartment is never forced on screen.
    if not button:IsShown() then
        local reg = button.registeredAddons
        if reg and #reg > 0 then
            button:Show()
        end
    end
end

-- The square frames' crop masks (Media/crop, made by .tools/minimap-crop/
-- make_crop_masks.py): minimap-crop-<r>.tga cuts r of its 256 rows off the
-- top and the bottom, for r in CROP_MASK_MIN..CROP_MASK_MAX (both frames'
-- crops over the Map Size slider).
SKIN.CROP_MASK_MIN, SKIN.CROP_MASK_MAX = 5, 31
local cropMasks = {}
-- The strip cropped off the top and bottom of the square canvas, and the
-- canvas mask that cuts it: Rectangular's 4:3 (32/256 of the canvas each), or,
-- under a square frame on the Forever client with its title bar, half the
-- bar's extra height each, so the whole frame, bar included, is a square (the
-- nearest crop mask, and the crop that mask cuts). 0 keeps the canvas whole.
SKIN._MapCrop = function(p, mapSize)
    if not p then
        return 0
    end
    if SKIN._MapShape(p) == "rectangular" then
        return mapSize * 32 / 256,
            "Interface\\AddOns\\CludesUIMinimap\\Media\\minimap_rectangular-crop-mask.tga"
    end
    if SKIN._MinimapFvSquare() then
        local _, locationMode = GetElementModes(p)
        if locationMode ~= "none" then
            local r = math.floor((SKIN._SqTitle() - SKIN._SqOut()) / 2 * 256 / mapSize + 0.5)
            r = math.max(SKIN.CROP_MASK_MIN, math.min(SKIN.CROP_MASK_MAX, r))
            local maskTex = cropMasks[r]
            if not maskTex then
                maskTex = "Interface\\AddOns\\CludesUIMinimap\\Media\\crop\\minimap-crop-" .. r .. ".tga"
                cropMasks[r] = maskTex
            end
            return r * mapSize / 256, maskTex
        end
    end
    return 0
end

-- The mask that crops rectangular mode's square canvas covers the terrain only -- the
-- engine keeps drawing unit blips across the whole canvas, and the one thing that
-- confines the native render is the minimap's PARENT rect (ordinary child frames and
-- textures are not clipped by it, so our border and buttons still draw outside).
-- Parenting the canvas to the layout frame of the visible size is what crops the
-- blips, for every crop.
local function DesiredMapParent(minimap)
    local p = SKIN.db and SKIN.db.profile.minimap
    if p and SKIN._MapCrop(p, p.mapSize or 140) > 0 then
        return GetFFD(minimap).layoutFrame or UIParent
    end
    return UIParent
end

-------------------------------------------------------------------------------
--  Stock styles (Global Settings > Style): Blizzard Style and Classic WoW UI.
--  Both force the round map, drop the CUI border and put the zoom buttons,
--  indicators and button row where a stock layout puts them; only the art
--  differs. Blizzard Style wears the 12.1 kit: Blizzard's compass ring (its
--  own texture, so Rotate Minimap keeps turning it) sized onto the map and a
--  header of ours in the stock NineSlice kit. Classic WoW UI wears the
--  vanilla texture files: the UI-Minimap-Border ring and zone banner on
--  frames of ours, the vanilla zoom buttons, the ring-border indicators.
--  Every CUI feature keeps working. Reload-gated per-profile flags, read only
--  on apply passes; all of this is skipped while both are off.
-------------------------------------------------------------------------------
-- The style this module RENDERS this session: "cui" | "blizzard" | "classic".
-- Read from the profile once (first call with a profile present) and latched
-- for the session: a live profile switch never flips the look under the
-- one-time chrome setup; the profile system prompts for a reload instead.
SKIN._MinimapStyle = function()
    local val = SKIN._styleLatch
    if val == nil then
        local m = SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap
        if not m then
            return "cui"
        end
        val = (m.useClassicStyle and "classic") or (m.useBlizzardStyle and "blizzard") or "cui"
        -- The WoW Forever variant of Blizzard Style, latched with it: the
        -- Forever client, Blizzard Style, and the sibling useForeverStyle
        -- flag set together with the Blizzard one.
        local fv = val == "blizzard" and CludesUI.IS_FOREVER == true and m.useForeverStyle == true
        -- Its Border Style Forever Square (where the heavy bronze art
        -- exists): the CludesUI look's square map in that frame, so the
        -- module renders "cui" and every stock site stands down, the
        -- variant's ring pieces with them. Forever Circle ("circle") is the
        -- variant as it is, Slim Square ("slim") the slim square below;
        -- anything else is Forever Square, the default.
        local fvSlim = fv and m.foreverBorder == "slim"
        SKIN._fvSquare = fv and not fvSlim and m.foreverBorder ~= "circle" and CludesUI.ForeverHeavyOK()
            or false
        -- Plain Blizzard Style on the Forever client has a Border Style of
        -- its own (blizzBorder): Square, the default there, is the same
        -- square map in the slim bronze line (EBS._sqSlim) instead of the
        -- heavy frame; "circle" is the variant's Forever Circle exactly
        -- (EBS._bzCircle: the variant's pieces render, while the published
        -- getters still name Blizzard Style). EBS._fvSquare reads true under
        -- either square. The variant's own Slim Square is that slim square.
        SKIN._sqSlim = (
            fvSlim
            or (val == "blizzard" and not fv and CludesUI.IS_FOREVER == true and m.blizzBorder ~= "circle")
        )
                and CludesUI.ForeverBorderOK()
            or false
        SKIN._bzCircle = val == "blizzard" and not fv and CludesUI.IS_FOREVER == true and not SKIN._sqSlim
        -- The look the profile's flags name (published MinimapForever), before
        -- a square renders it as the CludesUI layout.
        SKIN._fvLook = fv
        if SKIN._bzCircle then
            fv = true
        end
        if SKIN._sqSlim then
            SKIN._fvSquare = true
        end
        if SKIN._fvSquare then
            val, fv = "cui", false
        end
        SKIN._foreverLatch = fv
        SKIN._styleLatch = val
    end
    return val
end
-- Stock-art mode: true for both stock styles (the geometry, gating and
-- placement they share).
SKIN._MinimapBlizz = function()
    return SKIN._MinimapStyle() ~= "cui"
end
SKIN._MinimapClassic = function()
    return SKIN._MinimapStyle() == "classic"
end
-- WoW Forever variant: the style still reads "blizzard" (every stock site
-- stays as it is); this gates the Forever-only pieces, Blizzard Style's
-- Circle on the Forever client included (it draws the variant's round map
-- exactly). False off Forever, and under either square.
SKIN._MinimapForever = function()
    if SKIN._styleLatch == nil then
        SKIN._MinimapStyle()
    end
    return SKIN._foreverLatch == true
end
-- A square frame on the Forever client, latched above: the WoW Forever look's
-- Forever Square or Blizzard Style's Square (EBS._sqSlim tells them apart).
-- False under every other look and off Forever.
SKIN._MinimapFvSquare = function()
    if SKIN._styleLatch == nil then
        SKIN._MinimapStyle()
    end
    return SKIN._fvSquare == true
end
-- The shape the map renders: the stock styles' round map, Forever Square's
-- square, else the stored Shape (read live).
SKIN._MapShape = function(p)
    if SKIN._MinimapBlizz() then
        return "circle"
    end
    if SKIN._MinimapFvSquare() then
        return "square"
    end
    return (p and p.shape) or "square"
end
-- SetAtlas for a stock-look texture: CludesUI.StockAtlas (retail art
-- where the Forever client swaps the name), native under the WoW Forever
-- look. Plain SetAtlas on retail.
SKIN._StockAtlas = function(texture, name, ...)
    if SKIN._MinimapForever() then
        return texture:SetAtlas(name, ...)
    end
    return CludesUI.StockAtlas(texture, name, ...)
end
-- Published on the module ns for the Style page and the profile-switch check,
-- which compare the look the profile flags name: under either square that is
-- still the look its flags name (Blizzard Style, or Blizzard Style plus its
-- WoW Forever variant), whatever the module renders.
CludesUI._ModuleNS[ADDON_NAME].MinimapBlizz = SKIN._MinimapBlizz
CludesUI._ModuleNS[ADDON_NAME].MinimapStyle = function()
    local val = SKIN._MinimapStyle()
    if SKIN._fvSquare then
        return "blizzard"
    end
    return val
end
CludesUI._ModuleNS[ADDON_NAME].MinimapForever = function()
    if SKIN._styleLatch == nil then
        SKIN._MinimapStyle()
    end
    return SKIN._fvLook == true
end
-- The options page: a square frame renders this session, and the shape the
-- map renders.
CludesUI._ModuleNS[ADDON_NAME].MinimapFvSquare = SKIN._MinimapFvSquare
CludesUI._ModuleNS[ADDON_NAME].MinimapShape = function()
    return SKIN._MapShape(SKIN.db and SKIN.db.profile and SKIN.db.profile.minimap)
end
-- Profiles (ProfileChangesStyle's `extra`, handed the incoming minimap
-- table): true when that profile would render another square (or none) than
-- the one latched this session (the latch above, read off `m`), so the
-- switch asks for a reload. A stored profile keeps no default values, so an
-- unset Border Style is the square there too.
CludesUI._ModuleNS[ADDON_NAME].MinimapFvBorderChanged = function(m)
    local sq = nil
    if
        type(m) == "table"
        and not m.useClassicStyle
        and m.useBlizzardStyle
        and CludesUI.IS_FOREVER == true
    then
        if m.useForeverStyle == true then
            if m.foreverBorder == "slim" then
                if CludesUI.ForeverBorderOK() then
                    sq = "slim"
                end
            elseif m.foreverBorder ~= "circle" and CludesUI.ForeverHeavyOK() then
                sq = "heavy"
            end
        elseif m.blizzBorder ~= "circle" and CludesUI.ForeverBorderOK() then
            sq = "slim"
        end
    end
    local current = SKIN._MinimapFvSquare() and (SKIN._sqSlim and "slim" or "heavy") or nil
    return sq ~= current
end

-- Zoom button anchor, shared by the apply pass and the SetPoint re-assert
-- hooks: CUI stacks them at the bottom-right corner; the stock styles place
-- them where their stock map does (offsets scale with the map size).
SKIN._ZoomAnchor = function(button, isIn, minimap)
    local p = SKIN.db and SKIN.db.profile.minimap
    button:ClearAllPoints()
    local look = p and SKIN._MinimapStyle() or "cui"
    if look == "classic" then
        -- Vanilla: MinimapZoomIn CENTER 69,-37 and MinimapZoomOut CENTER 43,-65
        -- of the backdrop centred on the 140px map.
        local s = (p.mapSize or 140) / 140
        if isIn then
            button:SetPoint("CENTER", minimap, "CENTER", 69 * s, -37 * s)
        else
            button:SetPoint("CENTER", minimap, "CENTER", 43 * s, -65 * s)
        end
    elseif look == "blizzard" then
        local s = (p.mapSize or 140) / 198
        if isIn then
            button:SetPoint("CENTER", minimap, "CENTER", 88 * s, -68 * s)
        else
            button:SetPoint("CENTER", minimap, "CENTER", 72 * s, -84 * s)
        end
    else
        -- Forever Square steps them in past the heavy band and its shade, 6px
        -- from the edges as the texts inside the map sit (EBS._FvInsideXY);
        -- the slim square's line leaves them where they are.
        local posX, posY = -2, isIn and 20 or 2
        if SKIN._fvSquare and not SKIN._sqSlim then
            posX, posY = -6, isIn and 24 or 6
        end
        button:SetPoint("BOTTOMRIGHT", GetFFD(minimap).layoutFrame or minimap, "BOTTOMRIGHT", posX, posY)
    end
end

-- A button's spot on the ring round the map (stock-style button row):
-- radius r, angle t (radians, 0 = right, counter-clockwise), snapped to the
-- physical grid at the row's effective scale.
SKIN._ArcPoint = function(button, minimap, r, t, es)
    button:SetPoint(
        "CENTER",
        minimap,
        "CENTER",
        Pix.SnapForES(r * math.cos(t), es),
        Pix.SnapForES(r * math.sin(t), es)
    )
end

-- Compass ring + top border bar. The compass lives on MinimapBackdrop, the
-- Minimap's own child, which stays put and is only sized onto the map
-- (method calls, no keys written). The bar is a frame of our own wearing the
-- stock header kit: the cluster's BorderTop is a NineSlice with this layout,
-- and moving Blizzard's frame here would drag the cluster children anchored
-- to it (tracking, indicator frame, clock) along and inflate the cluster's
-- Edit Mode layout rect. Idempotent per apply pass.
-- On WoW Forever the same compass atlas draws that client's square ring, and
-- Blizzard re-sizes the backdrop, the compass and its rotate-mode underlay to
-- the atlas (unscaled) on every Rotate Minimap change: there the backdrop and
-- compass are pinned by two corners round the map centre, which no SetSize
-- can undo, and the underlay follows the compass rect.
SKIN._ApplyBlizzMinimapChrome = function(minimap, mapSize)
    local s = mapSize / 198
    local d = GetFFD(minimap)
    local compass = _G.MinimapCompassTexture
    -- WoW Forever look only: plain Blizzard Style keeps its own geometry everywhere.
    local fv = SKIN._MinimapForever() == true
    local hw, hh, rh = nil, nil, nil
    if fv then
        local rw
        rw, rh = SKIN._ForeverRingSize()
        hw, hh = rw * s / 2, rh * s / 2
    end
    -- MinimapBackdrop is the Minimap's own child frame carrying the compass ring
    -- (and the landing page button, which this module positions itself).
    local backdrop = _G.MinimapBackdrop
    if backdrop and backdrop ~= minimap then
        if backdrop:GetParent() ~= minimap then
            backdrop:SetParent(minimap)
        end
        backdrop:ClearAllPoints()
        if fv then
            backdrop:SetPoint("TOPLEFT", minimap, "CENTER", -hw, hh)
            backdrop:SetPoint("BOTTOMRIGHT", minimap, "CENTER", hw, -hh)
        else
            backdrop:SetPoint("CENTER", minimap, "CENTER", 0, 0)
            backdrop:SetSize(215 * s, 226 * s)
        end
        backdrop:SetFrameLevel(minimap:GetFrameLevel() + 3)
        backdrop:SetAlpha(1)
        backdrop:Show()
    end
    if compass then
        compass:ClearAllPoints()
        if fv then
            compass:SetPoint("TOPLEFT", minimap, "CENTER", -hw, hh)
            compass:SetPoint("BOTTOMRIGHT", minimap, "CENTER", hw, -hh)
            -- Rotate mode: the fixed circle under the turning chevron (a
            -- Forever-only region; Blizzard shows and hides it itself).
            local underlay = _G.MinimapCompassTextureUnderlay
            if underlay then
                underlay:ClearAllPoints()
                underlay:SetAllPoints(compass)
            end
        else
            compass:SetPoint("CENTER", minimap, "CENTER", 0, 0)
            compass:SetSize(215 * s, 226 * s)
        end
        compass:SetAlpha(1)
        compass:Show()
    end
    -- Top bar: the stock 175x16 kit, bottom edge 24px above the map's top,
    -- centred 5px right of the map centre in the stock cluster; scaled, so
    -- the offsets stay unscaled. WoW Forever's bar is its header button art
    -- (152x23) over the map's centre: its taller ring grows the stock
    -- container, which lifts the bar to (ring height / 2 - 92) above the map
    -- (34.5 for the 253px ring), clear of the north chevron. The zone text
    -- rides that bar's slot, 8 in from each end (the clock, Blizzard's tenant
    -- of its right end, stays the module's own element); a client without the
    -- art keeps the stock kit 3 higher.
    local headerFrame = d.blizzHeader
    if not headerFrame then
        headerFrame = CreateFrame("Frame", nil, minimap)
        headerFrame:EnableMouse(false)
        local barFrame = fv and C_Texture.GetAtlasInfo(SKIN.FV_HEADER_ATLAS)
        if barFrame then
            local texture = headerFrame:CreateTexture(nil, "BACKGROUND")
            texture:SetAllPoints(headerFrame)
            texture:SetAtlas(SKIN.FV_HEADER_ATLAS)
            headerFrame:SetSize(barFrame.width, barFrame.height)
            local slotIndex = CreateFrame("Frame", nil, headerFrame)
            slotIndex:EnableMouse(false)
            slotIndex:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 8, -1)
            slotIndex:SetPoint("BOTTOMRIGHT", headerFrame, "BOTTOMRIGHT", -8, -1)
            headerFrame._zoneSlot = slotIndex
            headerFrame._fvBar = true
        else
            headerFrame:SetSize(175, 16)
            if NineSliceUtil and NineSliceUtil.ApplyLayoutByName then
                pcall(
                    NineSliceUtil.ApplyLayoutByName,
                    headerFrame,
                    "UniqueCornersLayout",
                    "ui-hud-minimap-button"
                )
            end
        end
        d.blizzHeader = headerFrame
    end
    local barY = 24
    if headerFrame._fvBar then
        barY = rh / 2 - 92
    elseif fv then
        barY = rh / 2 - 89
    end
    headerFrame:ClearAllPoints()
    headerFrame:SetPoint("BOTTOM", minimap, "TOP", headerFrame._fvBar and 0 or 5, barY)
    headerFrame:SetScale(s)
    headerFrame:SetFrameLevel(minimap:GetFrameLevel() + 4)
    headerFrame:Show()
end

-- WoW Forever's compass atlas size (a 253px square there), read once.
SKIN._ForeverRingSize = function()
    if not SKIN._fvRingW then
        local details = C_Texture.GetAtlasInfo("UI-HUD-Minimap-Frame")
        SKIN._fvRingW = details and details.width or 253
        SKIN._fvRingH = details and details.height or 253
    end
    return SKIN._fvRingW, SKIN._fvRingH
end

-- WoW Forever look, Border Style Forever Square: the CludesUI look's square
-- map wears the bronze frame of Forever's own windows (CludesUI.
-- ForeverHeavy at the window scale, as the chat and Damage Meters windows
-- wear it) in place of the CludesUI border. The rim's outer edge sits
-- EBS.FV_SQUARE_OUT past the map's edge, so the map's square corners lie
-- inside the rim's corner cuts; unlock mode's mover outlines the frame
-- (MoverInsets in CUI_Minimap_Lifecycle.lua) and the elements inside the
-- map step in past the rim (EBS._FvInsideXY). While
-- the zone text shows, the frame keeps the windows' title bar over the map
-- (the rim's outer edge EBS.FV_SQUARE_TITLE above the map's top, the bar's
-- divider on that edge) and the zone text rides the bar's band (fvTitleSlot,
-- the band between the side rims); Zone Text Style None closes the frame at
-- the map's top. While the bar shows, the map loses half the bar's extra
-- height off its top and bottom each (EBS._MapCrop), so the whole frame, bar
-- included, is a square; the frame and its pieces anchor to the map as it
-- shows (the layout frame). The rows hang from the frame's outer edge (fvOuter), clear
-- of the rim's outer shadow by EBS.FV_ROW_AIR. Two levels over the map (the
-- housing overlay under it), under the text boxes and the buttons; every
-- piece mouse-transparent. Built once; re-anchored every pass, as the border
-- host is (the map's deferred reparent). A queue eye Action Bars parks off
-- the frame's corner follows a resize.
-- Blizzard Style's Square on the Forever client, and the WoW Forever look's
-- Slim Square (EBS._sqSlim), is the same
-- map and layout in the slim bronze line (CludesUI.ForeverBorder, the
-- shipped art): the line's outer edge EBS.FV_SLIM_OUT past the map's sides
-- and bottom, so the map's square corners lie under the line's corner cuts,
-- and its title bar drawn in the line too: the line round the map and a
-- band above it (black at EBS.FV_SLIM_BAND, the line's outer edge
-- EBS.FV_SLIM_TITLE above the map's top) with the line's divider on the
-- map's top.
SKIN.FV_SQUARE_OUT = 3
SKIN.FV_SQUARE_TITLE = 27
SKIN.FV_SLIM_OUT = CludesUI.FOREVER_BORDER.fill
SKIN.FV_SLIM_TITLE = 24
SKIN.FV_SLIM_BAND = 0.75
-- The square frame's outer edge past the map's sides and bottom (and its
-- top without the title bar), and past its top with the title bar.
function SKIN._SqOut()
    return SKIN._sqSlim and SKIN.FV_SLIM_OUT or SKIN.FV_SQUARE_OUT
end
function SKIN._SqTitle()
    return SKIN._sqSlim and SKIN.FV_SLIM_TITLE or SKIN.FV_SQUARE_TITLE
end
-- Rows outside the frame: the rim's outer shadow and 2px more past its outer
-- edge (Distance from Map adds to it), and between two ring buttons' rings
-- (Icon Spacing adds to it).
SKIN.FV_ROW_AIR = 4
SKIN.FV_RING_GAP = 3
SKIN._ApplyForeverSquare = function(minimap)
    local d = GetFFD(minimap)
    local slim = SKIN._sqSlim
    local widget = d.fvFrame
    if not widget then
        widget = CreateFrame("Frame", nil, minimap)
        widget:EnableMouse(false)
        if slim then
            local band = widget:CreateTexture(nil, "BACKGROUND")
            band:SetColorTexture(0, 0, 0, SKIN.FV_SLIM_BAND)
            d.fvSlimBand = band
            d.fvSlimRing = CludesUI.ForeverBorder(widget, "ARTWORK")
            d.fvSlimRule = CludesUI.ForeverBorderDivider(widget, "ARTWORK", 1)
        else
            widget:SetScale(CludesUI.FOREVER_HEAVY.k)
            d.fvHeavyRim = CludesUI.ForeverHeavy(widget, "ARTWORK")
        end
        d.fvFrame = widget
        local slotIndex = CreateFrame("Frame", nil, minimap)
        slotIndex:EnableMouse(false)
        d.fvTitleSlot = slotIndex
        local outer = CreateFrame("Frame", nil, minimap)
        outer:EnableMouse(false)
        d.fvOuter = outer
    end
    local _, locationMode = GetElementModes(SKIN.db.profile.minimap)
    local titleText = locationMode ~= "none"
    SKIN._fvTitleOn = titleText
    -- The map as it shows: the layout frame once the title bar crops the canvas.
    local vis = d.layoutFrame or minimap
    widget:SetFrameLevel(minimap:GetFrameLevel() + 2)
    widget:ClearAllPoints()
    widget:SetAllPoints(vis)
    local o = SKIN._SqOut()
    local topY = titleText and SKIN._SqTitle() or o
    if slim then
        CludesUI.ForeverBorderSeat(d.fvSlimRing, vis, nil, -o, topY, o, -o)
        local band, rule = d.fvSlimBand, d.fvSlimRule
        band:SetShown(titleText)
        rule:SetShown(titleText)
        if titleText then
            -- The band from FOREVER_BORDER.fill inside the line (its corners
            -- inside the corner cuts) down to the map's top; the divider
            -- between the side lines' inner edges, its bottom on the map's top.
            local B = CludesUI.FOREVER_BORDER
            band:ClearAllPoints()
            band:SetPoint("TOPLEFT", vis, "TOPLEFT", B.fill - o, topY - B.fill)
            band:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", o - B.fill, 0)
            rule:ClearAllPoints()
            rule:SetPoint("BOTTOMLEFT", vis, "TOPLEFT", B.line - o, 0)
            rule:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", o - B.line, 0)
        end
    else
        CludesUI.ForeverHeavyTitle(d.fvHeavyRim, titleText)
        CludesUI.ForeverHeavySeat(d.fvHeavyRim, vis, nil, -o, topY, o, -o)
    end
    widget:Show()
    d.fvOuter:ClearAllPoints()
    d.fvOuter:SetPoint("TOPLEFT", vis, "TOPLEFT", -o, topY)
    d.fvOuter:SetPoint("BOTTOMRIGHT", vis, "BOTTOMRIGHT", o, -o)
    d.fvTitleSlot:ClearAllPoints()
    if slim then
        -- The band between the side lines (2px of air past the map's sides),
        -- from 1px under the top line's inner shadow down to 5 above the
        -- map's top, clear of the divider's line and outer shadow.
        d.fvTitleSlot:SetPoint("TOPLEFT", vis, "TOPLEFT", 2, topY - 4)
        d.fvTitleSlot:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", -2, 5)
    else
        -- The band between the side rims (their inner edges 3 inside the map's
        -- sides), 2px of air at each end.
        local barFrame = CludesUI.FOREVER_HEAVY.title
        d.fvTitleSlot:SetPoint("TOPLEFT", vis, "TOPLEFT", o + 2, topY - barFrame.band)
        d.fvTitleSlot:SetPoint("BOTTOMRIGHT", vis, "TOPRIGHT", -o - 2, topY - barFrame.bandEnd)
    end
    local ab = CludesUI._ModuleNS.CludesUIActionBars
    if ab then
        ab.AB_ForeverEyeRelayout()
    end
end

-- WoW Forever: the queue eye's stock spot on the ring (Blizzard's Forever
-- layout: 68 left of and 68 below the 198px map's centre, scaled with the
-- map), for Action Bars to park the eye on. The map frame and the offsets;
-- nil unless the map wears Blizzard's ring on that client (Blizzard Style or
-- its WoW Forever variant) or a square frame (the variant's Forever Square,
-- Blizzard Style's slim square), whose eye sits diagonally off the frame's
-- bottom-left corner (the 45px eye's top-right corner on the frame's outer
-- corner), clear of the rows the CludesUI layout hangs along the edges.
SKIN._QueueEyeSpot = function()
    if not CludesUI.IS_FOREVER then
        return nil
    end
    local sq = SKIN._MinimapFvSquare()
    if not sq and SKIN._MinimapStyle() ~= "blizzard" then
        return nil
    end
    local dim = SKIN.db.profile.minimap.mapSize or 140
    if sq then
        local o = dim / 2 + SKIN._SqOut() + 22.5
        -- The frame's bottom rises with the map's crop.
        return Minimap, -o, -(o - SKIN._MapCrop(SKIN.db.profile.minimap, dim))
    end
    local s = dim / 198
    return Minimap, -68 * s, -68 * s
end
CludesUI._ModuleNS[ADDON_NAME].MinimapQueueEyeSpot = SKIN._QueueEyeSpot

-- WoW Forever look: the day/night orb Blizzard hangs on the ring's upper
-- right (its own sits in the cluster this module hides). Stock geometry: a
-- 42px bronze rim over a 33px sun or moon disc, centred 55 right of and 86
-- above the 198px map's centre; always drawn at its native size, while the
-- offset scales with the map. Above the compass so the rotating chevron
-- passes under it, below the ping blocker, mouse-transparent like the stock
-- one; a child of the map, so it hides with it. Built once under the latch;
-- the disc repaints only on DIEL_CYCLE_CHANGED.
SKIN._ApplyForeverDiel = function(minimap, mapSize)
    local d = GetFFD(minimap)
    local orb = d.foreverDiel
    if not orb then
        local rim = C_Texture.GetAtlasInfo("UI-HUD-Minimap-Frame-Cycle")
        if not rim then
            return
        end
        orb = CreateFrame("Frame", nil, minimap)
        orb:SetSize(rim.width, rim.height)
        orb:EnableMouse(false)
        local disc = orb:CreateTexture(nil, "BACKGROUND", nil, 0)
        disc:SetPoint("CENTER")
        local border = orb:CreateTexture(nil, "OVERLAY", nil, 1)
        border:SetAllPoints()
        border:SetAtlas("UI-HUD-Minimap-Frame-Cycle")
        local function Paint(isDay)
            disc:SetAtlas(isDay and "UI-HUD-Minimap-DayCycle" or "UI-HUD-Minimap-NightCycle", true)
        end
        orb:RegisterEvent("DIEL_CYCLE_CHANGED")
        orb:SetScript("OnEvent", function(_, _, isDay)
            Paint(isDay)
        end)
        Paint(C_DateAndTime.IsDayTime())
        d.foreverDiel = orb
    end
    local s = mapSize / 198
    orb:ClearAllPoints()
    orb:SetPoint("CENTER", minimap, "CENTER", 55 * s, 86 * s)
    orb:SetFrameLevel(minimap:GetFrameLevel() + 5)
    orb:Show()
end

-- Classic WoW UI: the stock zoom button wearing the vanilla button files at
-- the vanilla 32px size, scaled with the map. Texture setters and SetSize
-- only on this Blizzard button; the one-time skin is memoized in its lookup
-- record. The vanilla files fill the whole button, so the atlas coordinates
-- the stock art left behind are reset.
SKIN._ClassicZoomButton = function(button, isIn, s)
    button:SetSize(32 * s, 32 * s)
    local d = GetFFD(button)
    if d.classicSkin then
        return
    end
    d.classicSkin = true
    local baseValue = isIn and "Interface\\Minimap\\UI-Minimap-ZoomInButton-"
        or "Interface\\Minimap\\UI-Minimap-ZoomOutButton-"
    button:SetNormalTexture(baseValue .. "Up")
    button:SetPushedTexture(baseValue .. "Down")
    button:SetDisabledTexture(baseValue .. "Disabled")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    local texture = button:GetNormalTexture()
    if texture then
        texture:SetTexCoord(0, 1, 0, 1)
    end
    texture = button:GetPushedTexture()
    if texture then
        texture:SetTexCoord(0, 1, 0, 1)
    end
    texture = button:GetDisabledTexture()
    if texture then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetDesaturated(false)
    end
    texture = button:GetHighlightTexture()
    if texture then
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetBlendMode("ADD")
    end
end

-- Classic WoW UI chrome: the vanilla UI-Minimap-Border file on two frames of
-- ours. The ring: the 192x192 region the vanilla MinimapBorder draws, centred
-- 8 left and 24 below the map centre (the art's circle sits on the map, the
-- rest is the lower-left bulge), on a frame above the map like the vanilla
-- backdrop, scaled by mapSize/140. The banner: the MinimapBorderTop strip
-- (sheet rows 0..28, columns 80..256) on OUR header frame (the same header
-- record the indicators, compartment and zone text anchor to), drawn in
-- three pieces at the sheet's own pixel size -- the 36-column rounded left
-- end, the 16-column right end and the middle stretched between them -- so
-- it spans the map plus the vanilla 18 a side without growing taller on a
-- big map; its bottom sits 4 above the map's top, under the map and ring as
-- the cluster's own region is; its zone-text slot is a 12-tall box centred
-- on the banner between the ends. Created once, re-anchored per apply pass.
SKIN._ApplyClassicMinimapChrome = function(minimap, mapSize)
    local s = mapSize / 140
    local d = GetFFD(minimap)
    local ring = d.classicRing
    if not ring then
        ring = CreateFrame("Frame", nil, minimap)
        ring:EnableMouse(false)
        local texture = ring:CreateTexture(nil, "ARTWORK")
        texture:SetAllPoints(ring)
        texture:SetTexture("Interface\\Minimap\\UI-Minimap-Border")
        texture:SetTexCoord(0.25, 1.0, 0.125, 0.875)
        d.classicRing = ring
    end
    ring:ClearAllPoints()
    ring:SetPoint("CENTER", minimap, "CENTER", -8 * s, -24 * s)
    ring:SetSize(192 * s, 192 * s)
    ring:SetFrameLevel(minimap:GetFrameLevel() + 3)
    ring:Show()
    local headerFrame = d.blizzHeader
    if not headerFrame then
        headerFrame = CreateFrame("Frame", nil, minimap)
        headerFrame:EnableMouse(false)
        local file = "Interface\\Minimap\\UI-Minimap-Border"
        local capL = headerFrame:CreateTexture(nil, "ARTWORK")
        capL:SetTexture(file)
        capL:SetTexCoord(0.3125, 0.453125, 0.0, 0.109375)
        capL:SetSize(36, 28)
        capL:SetPoint("TOPLEFT", headerFrame, "TOPLEFT", 0, 0)
        local capR = headerFrame:CreateTexture(nil, "ARTWORK")
        capR:SetTexture(file)
        capR:SetTexCoord(0.9375, 1.0, 0.0, 0.109375)
        capR:SetSize(16, 28)
        capR:SetPoint("TOPRIGHT", headerFrame, "TOPRIGHT", 0, 0)
        local mid = headerFrame:CreateTexture(nil, "ARTWORK")
        mid:SetTexture(file)
        mid:SetTexCoord(0.453125, 0.9375, 0.0, 0.109375)
        mid:SetPoint("TOPLEFT", capL, "TOPRIGHT", 0, 0)
        mid:SetPoint("BOTTOMRIGHT", capR, "BOTTOMLEFT", 0, 0)
        local slotIndex = CreateFrame("Frame", nil, headerFrame)
        slotIndex:SetHeight(12)
        slotIndex:SetPoint("CENTER", headerFrame, "CENTER", 0, 1)
        slotIndex:EnableMouse(false)
        headerFrame._zoneSlot = slotIndex
        d.blizzHeader = headerFrame
    end
    headerFrame:ClearAllPoints()
    headerFrame:SetSize(mapSize + 36, 28)
    headerFrame:SetPoint("BOTTOM", minimap, "TOP", 0, 4)
    headerFrame._zoneSlot:SetWidth(math.max(40, mapSize + 36 - 52))
    headerFrame:SetFrameLevel(math.max(0, minimap:GetFrameLevel() - 1))
    headerFrame:Show()
end

Inner.DesiredMapParent = DesiredMapParent
Inner.broken = false
