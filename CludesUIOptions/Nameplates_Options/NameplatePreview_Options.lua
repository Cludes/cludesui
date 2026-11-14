if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  Nameplates_Options\NameplatePreview_Options.lua
--  Nameplates options: the enemy nameplate preview in the content header of
--  the Display page (BuildNameplatePreview). Definitions only; the shared
--  helpers come from ns._NPO_OptEnv (filled by CUI_Nameplates_Options.lua).
-------------------------------------------------------------------------------
local mod = CludesUI._ModuleNS["CludesUINameplates"]
if not mod then
    return
end -- module disabled: no options page

-- The options page frame pool (CludesUI_FramePool.lua): under page reuse the
-- preview is built into the page's kept header root, and every frame the preview
-- makes there is handed back to the header's next build.
local CreateFrame = CludesUI._Pool.CreateFrame

-- The name slot's Strata, as on the live plate: a slot's text host sits at
-- level 900 in the slot's strata and the aura icons at 800 in MEDIUM (HIGH with
-- Raise Strata). MEDIUM keeps the name where the preview's text tier puts it
-- (over the auras, under raised ones); LOW and BACKGROUND draw it under every
-- aura, HIGH and up over raised auras too, its raid marker with it. Preview
-- levels over the health bar: text +10/+11, auras +9, raised auras +13 (their
-- duration text +15). The refresh re-parents the name and its marker to the
-- text tier before this runs, so MEDIUM needs nothing.
local function PreviewNameStrata(popFrame, healthBar, nameFS, nameRaidFrame, strata)
    if strata == "MEDIUM" then
        return
    end
    local low = (strata == "BACKGROUND" or strata == "LOW")
    local key = low and "_npNameLowHost" or "_npNameHighHost"
    local hostRegion = popFrame[key]
    if not hostRegion then
        hostRegion = CreateFrame("Frame", nil, popFrame)
        hostRegion:SetAllPoints(healthBar)
        popFrame[key] = hostRegion
    end
    hostRegion:SetFrameLevel(healthBar:GetFrameLevel() + (low and 7 or 16))
    nameFS:SetParent(hostRegion)
    if nameRaidFrame:IsShown() then
        nameRaidFrame:SetParent(hostRegion)
        nameRaidFrame:SetFrameLevel(hostRegion:GetFrameLevel() + 1)
    end
end

-- Core Positions chains in the preview (mirror ns.NP_CoreChain in
-- CUI_Nameplates_AuraContainers.lua): a slot holding two or more elements lays
-- them out one after another in its order (<pos>SlotOrder),
-- <pos>SlotElementSpacing apart (unset: the first aura row's gap in that order,
-- else the global aura spacing). The first shown element keeps the spot the
-- refresh gave it (at Top and Bottom the first aura row, which stays centred:
-- the elements before it in the order hang off its left edge); each later one
-- hangs off the one before it, keeping its own height (an icon centred on the
-- bar, a row on the bar's bottom). A chained aura row is laid out icon by icon
-- from its pinned end. Fills cx.sideEnd[side] with a side chain's outermost
-- element that meets the target arrows' span ({ frame, y, h }: the frame, its
-- bottom over the bar's bottom, its height), for the arrows to hug.
-- cx: DBVal, defaults, barH, arrowH, debuffY, rows[id] = { list, count, sz, h,
-- gap, slot }, icons[id] = { frame, slot, sz } (sz: the element's height; a
-- faction riding the Rare/Quest indicator is slot "none" there), classFaction,
-- factionFrame, sideEnd. A saved order that holds "quest" but not "questtext"
-- reads the Quest Objective Text right after the Quest Indicator, as live.
local CHAIN_MEMBER = {
    debuffs = "debuffs",
    buffs = "buffs",
    ccs = "ccs",
    raidmarker = "raidmarker",
    rare = "class",
    quest = "class",
    questtext = "qtext",
    faction = "faction",
}
local CHAIN_DEFAULT = { "debuffs", "buffs", "ccs", "raidmarker", "rare", "quest", "questtext", "faction" }
local CHAIN_POS = { "top", "right", "left", "topright", "topleft", "bottom" }
local function ChainPreview(cx)
    local DBVal, defaultSet = cx.DBVal, cx.defaults
    local barH = cx.barH
    cx.sideEnd.left, cx.sideEnd.right = nil, nil
    local a0, a1 = (barH - cx.arrowH) / 2, (barH + cx.arrowH) / 2
    for _, place in ipairs(CHAIN_POS) do
        -- The slot's members in its order.
        local members, seen = {}, {}
        local function take(ident)
            if seen[ident] then
                return
            end
            seen[ident] = true
            local r, ic = cx.rows[ident], cx.icons[ident]
            local at = (r and r.slot) or (ic and ic.slot) or "none"
            if at == place then
                members[#members + 1] = ident
            end
        end
        local source = DBVal(place .. "SlotOrder")
        if type(source) == "string" then
            local noQText = not string.find(source, "questtext", 1, true)
            for key in string.gmatch(source, "[^,]+") do
                if CHAIN_MEMBER[key] then
                    take(CHAIN_MEMBER[key])
                end
                if key == "quest" and noQText then
                    take("qtext")
                end
            end
        end
        for i = 1, #CHAIN_DEFAULT do
            take(CHAIN_MEMBER[CHAIN_DEFAULT[i]])
        end
        if #members >= 2 then
            local yOff = DBVal(place .. "SlotYOffset") or 0
            local sideName = (place == "left" or place == "right")
            local corner = (place == "topleft" or place == "topright")
            -- The shown members: a row (list, count, sz, h, gap) or an icon (frame, sz),
            -- with the bottom edge its own placement gives it over the slot's reference.
            local isShown = {}
            for i = 1, #members do
                local ident = members[i]
                local r = cx.rows[ident]
                if r then
                    local baseValue = 0
                    if sideName then
                        baseValue = yOff
                    elseif corner then
                        baseValue = cx.debuffY + yOff
                    end
                    isShown[#isShown + 1] = { id = ident, row = r, base = baseValue }
                else
                    local ic = cx.icons[ident]
                    local f = ic.frame
                    -- Rare/Quest + Faction with no mark: the badge stands in for the pair.
                    if ident == "class" and not f:IsShown() and cx.classFaction then
                        f = cx.factionFrame
                    end
                    if f:IsShown() then
                        local baseValue = 0
                        if sideName then
                            baseValue = yOff + barH / 2 - ic.sz / 2
                        elseif corner then
                            baseValue = ((ident == "raidmarker") and 0 or 2) + yOff
                        end
                        isShown[#isShown + 1] = { id = ident, frame = f, sz = ic.sz, base = baseValue }
                    end
                end
            end
            local k = #isShown
            if k > 0 then
                local s = DBVal(place .. "SlotElementSpacing")
                if type(s) ~= "number" then
                    s = nil
                    for i = 1, #members do
                        local r = cx.rows[members[i]]
                        if r then
                            s = r.gap
                            break
                        end
                    end
                    s = s or DBVal("auraSpacing") or defaultSet.auraSpacing
                end
                local dir = "right"
                if place == "left" then
                    dir = "left"
                elseif corner then
                    local g = DBVal(place .. "SlotGrowth") or defaultSet[place .. "SlotGrowth"]
                    if g == "up" or g == "left" then
                        dir = g
                    end
                end
                local centred = (place == "top" or place == "bottom")
                local pivot = 1
                if centred then
                    for i = 1, k do
                        if isShown[i].row then
                            pivot = i
                            break
                        end
                    end
                end
                -- A member's outer frame in direction d: a row the refresh placed grows
                -- outward from its first icon, so its last is the outer one; a row the
                -- chain pinned leftward is pinned at its last icon, so its first is.
                local function Outer(m, d)
                    if not m.row then
                        return m.frame
                    end
                    if d == "left" and m.pinned then
                        return m.row.list[1]
                    end
                    return m.row.list[m.row.count]
                end
                -- Hangs member m off prev (member j's outer frame) in direction d.
                local function Place(m, jdx, prev, d)
                    local dy = m.base - isShown[jdx].base
                    local r = m.row
                    local pin = m.frame
                    if r then
                        pin = (d == "left") and r.list[r.count] or r.list[1]
                        m.pinned = true
                    end
                    pin:ClearAllPoints()
                    if d == "up" then
                        local sd = (place == "topleft") and "LEFT" or "RIGHT"
                        pin:SetPoint("BOTTOM" .. sd, prev, "TOP" .. sd, 0, s)
                    elseif place == "bottom" then
                        if d == "left" then
                            pin:SetPoint("TOPRIGHT", prev, "TOPLEFT", -s, 0)
                        else
                            pin:SetPoint("TOPLEFT", prev, "TOPRIGHT", s, 0)
                        end
                    elseif d == "left" then
                        pin:SetPoint("BOTTOMRIGHT", prev, "BOTTOMLEFT", -s, dy)
                    else
                        pin:SetPoint("BOTTOMLEFT", prev, "BOTTOMRIGHT", s, dy)
                    end
                    if not r then
                        return
                    end
                    -- The row's other icons, from the pinned one.
                    local sp = r.gap + r.sz
                    for num = 1, r.count do
                        local f = r.list[num]
                        if f ~= pin then
                            f:ClearAllPoints()
                            if d == "up" then
                                f:SetPoint("BOTTOMLEFT", pin, "BOTTOMLEFT", 0, (num - 1) * (sp - r.sz + r.h))
                            elseif d == "left" then
                                f:SetPoint("BOTTOMRIGHT", pin, "BOTTOMRIGHT", -(r.count - num) * sp, 0)
                            else
                                f:SetPoint("BOTTOMLEFT", pin, "BOTTOMLEFT", (num - 1) * sp, 0)
                            end
                        end
                    end
                end
                for i = pivot + 1, k do
                    Place(isShown[i], i - 1, Outer(isShown[i - 1], dir), dir)
                end
                if centred then
                    for i = pivot - 1, 1, -1 do
                        local pm = isShown[i + 1]
                        local prev = (i + 1 == pivot) and (pm.row and pm.row.list[1] or pm.frame)
                            or Outer(pm, "left")
                        Place(isShown[i], i + 1, prev, "left")
                    end
                end
                if sideName then
                    for i = k, 1, -1 do
                        local m = isShown[i]
                        local posY, hgt = m.base, m.row and m.row.h or m.sz
                        if posY < a1 and a0 < posY + hgt then
                            cx.sideEnd[place] = { frame = Outer(m, dir), y = posY, h = hgt }
                            break
                        end
                    end
                end
            end
        end
    end
end

-- Core Text slot colours by the slot's Text Coloring mode. The preview is a
-- hostile NPC at the player's level: Hostility / Class shows the Hostile name
-- colour, Level Difficulty that level's difficulty colour (friendly levels
-- included, as the player stands in for the mob), Custom the slot colour.
-- File level, so the custom text popup (DisplayLayout_Options.lua) shares it
-- without holding a preview build. PV_LVL_COLOR is reused by every level read.
local PV_LVL_COLOR = { r = 1, g = 1, b = 1 }
function mod.NPO_PreviewSlotColor(slotKey)
    local environ = mod._NPO_OptEnv
    local saved, defaultSet = environ.DB(), environ.defaults
    local modeName = mod.NP_SlotColorMode(slotKey, saved)
    if modeName == "class" then
        return (saved and saved.enemyNameHostileColor) or defaultSet.hostile
    elseif modeName == "level" then
        local r, g, b = CludesUI.GetLevelColor("player", UnitEffectiveLevel("player"), true)
        if r then
            PV_LVL_COLOR.r, PV_LVL_COLOR.g, PV_LVL_COLOR.b = r, g, b
            return PV_LVL_COLOR
        end
    end
    return (saved and saved[slotKey .. "Color"]) or defaultSet[slotKey .. "Color"]
end

--- Build the nameplate preview in the content header area: an exact 1:1
--- replica of a real enemy nameplate (same pixel sizes, anchors, fonts,
--- borders; no glow, no added effects).
--- @param parent  Frame   contentHeaderFrame
--- @param parentW number  available width
--- @return number height consumed
local function BuildNameplatePreview(hostFrame, parentW)
    local environ = mod._NPO_OptEnv
    local ADDON_NAME, BAR_W, SavedDB, DBVal = environ.ADDON_NAME, environ.BAR_W, environ.DB, environ.DBVal
    local defaultSet, displayCastIcons, GetNPOptOutline, NAME_RAID_MARKER_GAP =
        environ.defaults, environ.displayCastIcons, environ.GetNPOptOutline, environ.NAME_RAID_MARKER_GAP
    local optionState, pcall, Pix, RandomizePreviewValues =
        environ.optState, environ.pcall, environ.PP, environ.RandomizePreviewValues
    local SetPVFont = environ.SetPVFont
    local FONT_PATH = (CludesUI.GetFontPath("nameplates")) or DBVal("font")

    -- Constants matching the real addon exactly
    local CAST_H = 17
    local BORDER_CORNER = 6
    local BORDER_TEX = "Interface\\AddOns\\CludesUINameplates\\Media\\border-colorless.png"

    -- Container sized in Update()
    local popFrame = CreateFrame("Frame", nil, hostFrame)
    popFrame:SetPoint("TOP", hostFrame, "TOP", 0, 0)

    -- Scale so the preview matches real nameplate size: real plates render at UIParent's effective scale, the panel's is smaller; this ratio keeps pixel values (bar/font/icon) physically sized, and Snap() still works via pf:GetEffectiveScale().
    local previewScale = UIParent:GetEffectiveScale() / hostFrame:GetEffectiveScale()
    popFrame:SetScale(previewScale)
    -- parentW in preview-local coordinates (used for centering the bar)
    local localParentW = parentW / previewScale

    -- Pixel-snap helper for the preview's scale; defined early so AddBorder and CreatePreviewBorderSet can use it.
    local function IsDragging()
        return CludesUI._sliderDragging and CludesUI._sliderDragging > 0
    end

    local function Snap(val)
        local s = popFrame:GetEffectiveScale()
        return math.floor(val * s + 0.5) / s
    end

    -- 1px in preview-scale coordinates (used for borders and icon insets)
    local px = Snap(1)

    -- Icon textures whose insets (px, -px) need refreshing when scale changes
    local _insetIcons = {}

    -- 1px black border helper uses Snap(), not PixelUtil (screen-pixel snap that can disagree with the preview's own grid); returns a refresh fn that re-snaps sizes on scale change.
    local _borderRefreshers = {}
    local function AddBorder(f)
        local function mkB()
            local posX = f:CreateTexture(nil, "OVERLAY", nil, 7)
            posX:SetColorTexture(0, 0, 0, 1)
            if posX.SetSnapToPixelGrid then
                posX:SetSnapToPixelGrid(false)
                posX:SetTexelSnappingBias(0)
            end
            return posX
        end
        local px = Snap(1)
        local t = mkB()
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
        t:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
        t:SetHeight(px)
        local b = mkB()
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        b:SetHeight(px)
        -- Vertical edges inset between horizontal edges to avoid corner overlap
        local l = mkB()
        l:SetPoint("TOPLEFT", t, "BOTTOMLEFT", 0, 0)
        l:SetPoint("BOTTOMLEFT", b, "TOPLEFT", 0, 0)
        l:SetWidth(px)
        local r = mkB()
        r:SetPoint("TOPRIGHT", t, "BOTTOMRIGHT", 0, 0)
        r:SetPoint("BOTTOMRIGHT", b, "TOPRIGHT", 0, 0)
        r:SetWidth(px)
        f._cuiIconEdges = { t, b, l, r }
        _borderRefreshers[#_borderRefreshers + 1] = function()
            local npx = Snap(1)
            t:SetHeight(npx)
            b:SetHeight(npx)
            l:SetWidth(npx)
            r:SetWidth(npx)
        end
    end

    -- Disable WoW's automatic pixel snapping on a texture (prevents sub-pixel jitter vs borders)
    local UnsnapTex = CludesUI.PP.DisablePixelSnap

    -- Health bar the central anchor for everything
    local healthBar = CreateFrame("StatusBar", nil, popFrame)
    healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    UnsnapTex(healthBar:GetStatusBarTexture())
    -- Preview constants packed to reduce upvalue count
    local PV_CONST = {
        FAKE_MAX_HP = 10000,
        DEBUFF_COUNT = 2,
        BUFF_COUNT = 1,
        CC_COUNT = 1,
    }
    -- There is one preview buff slot, so it shows the type THIS character
    -- removes -- and nil (no glow at all) for a character with no
    -- offensive dispel, which is what their nameplates will do.
    local function PreviewDispelType()
        local magic, enrage = false, false
        if mod.GetOffensiveDispelTypes then
            magic, enrage = mod.GetOffensiveDispelTypes()
        end
        if magic then
            return "magic"
        end
        if enrage then
            return "enrage"
        end
        return nil
    end
    if not optionState._previewHpPct then
        RandomizePreviewValues()
    end
    local previewHpPct = optionState._previewHpPct
    local previewHpVal = math.floor(PV_CONST.FAKE_MAX_HP * previewHpPct / 100)
    healthBar:SetMinMaxValues(0, PV_CONST.FAKE_MAX_HP)
    healthBar:SetValue(previewHpVal)
    healthBar:SetFrameLevel(popFrame:GetFrameLevel() + 10)
    healthBar:SetStatusBarColor(0.85, 0.20, 0.20, 1)

    local healthBG = healthBar:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    local _hbg = (SavedDB() and SavedDB().bgColor) or defaultSet.bgColor
    local _hba = (DBVal("bgAlpha") or defaultSet.bgAlpha)
    healthBG:SetColorTexture(_hbg.r, _hbg.g, _hbg.b, _hba)
    UnsnapTex(healthBG)

    -- Hash line on preview health bar
    local previewHashLine = healthBar:CreateTexture(nil, "OVERLAY", nil, 3)
    previewHashLine:SetColorTexture(1, 1, 1, 0.8)
    UnsnapTex(previewHashLine)
    previewHashLine:SetWidth(Snap(2))
    previewHashLine:SetPoint("TOP", healthBar, "TOP", 0, 0)
    previewHashLine:SetPoint("BOTTOM", healthBar, "BOTTOM", 0, 0)
    previewHashLine:Hide()

    -- Absorb preview: the live plates' own clip-frame bars and placement
    -- (ns.NP_BuildAbsorbBars), so the preview draws exactly what plates do.
    local absorbMask = healthBar:CreateMaskTexture()
    absorbMask:SetAllPoints(healthBar)
    absorbMask:SetTexture("Interface\\Buttons\\WHITE8X8")
    local pvAbs = {}
    mod.NP_BuildAbsorbBars(pvAbs, healthBar, absorbMask)
    local function ApplyPreviewAbsorbStyle()
        local look = DBVal("absorbStyle") or "blizzard"
        local texture = mod.NP_ABSORB_STYLE_TEX[look]
            or mod.ResolveOverlayTexPath(look)
            or mod.NP_ABSORB_STYLE_TEX.blizzard
        local alpha = DBVal("absorbAlpha")
        if alpha then
            alpha = alpha / 100
        elseif look == "clean" then
            alpha = (DBVal("absorbCleanAlpha") or 30) / 100
        else
            alpha = mod.NP_ABSORB_STYLE_ALPHA[look] or 0.8
        end
        local r, g, b = 1, 1, 1
        if look ~= "blizzard" then
            local c = (SavedDB() and SavedDB().absorbColor)
                or defaultSet.absorbColor
                or { r = 1, g = 1, b = 1 }
            r, g, b = c.r, c.g, c.b
        end
        for _, barFrame in ipairs({ pvAbs.absorb, pvAbs.absorbForward }) do
            barFrame:SetStatusBarTexture(texture)
            barFrame:SetStatusBarColor(r, g, b, alpha)
            local fillTex = barFrame:GetStatusBarTexture()
            if fillTex then
                fillTex:SetDrawLayer("ARTWORK", 1)
                fillTex:AddMaskTexture(absorbMask)
            end
        end
    end
    local function ToggleAbsorbPreview()
        if optionState.showAbsorbPreview then
            local modeName = DBVal("absorbEdgeMode") or "overlay"
            -- A shield smaller than the empty health (preview health is
            -- 60-75%), so each placement draws somewhere different: past the
            -- health edge, back over it, or at either end of the bar. A shield
            -- past empty health would draw Overlay and From Right Edge alike.
            local shield = 0.15
            mod.NP_SizeAbsorbBars(pvAbs, healthBar:GetWidth(), healthBar:GetHeight())
            if pvAbs._absEdge ~= modeName or pvAbs._absFill ~= healthBar:GetStatusBarTexture() then
                mod.NP_LayoutAbsorbBars(pvAbs, healthBar, modeName)
            end
            ApplyPreviewAbsorbStyle()
            pvAbs.absorb:SetMinMaxValues(0, 1)
            pvAbs.absorb:SetValue(shield)
            pvAbs._absCurClip:Show()
            if pvAbs._absFwOn then
                pvAbs.absorbForward:SetMinMaxValues(0, 1)
                pvAbs.absorbForward:SetValue(shield)
                pvAbs._absMissClip:Show()
            end
        else
            pvAbs._absCurClip:Hide()
            pvAbs._absMissClip:Hide()
        end
    end

    -- Bar texture applied directly via SetStatusBarTexture (no overlay); updated in the preview refresh below.

    local BORDER_TEX_SIMPLE = "Interface\\AddOns\\CludesUINameplates\\Media\\border-simple.png"

    -- Wrapper frame around the health bar: a plain Frame (not StatusBar) so the image border parented to it never interacts with StatusBar internals; sized to match the health bar exactly.
    local healthWrapper = CreateFrame("Frame", nil, popFrame)
    healthWrapper:SetFrameLevel(healthBar:GetFrameLevel() + 4)

    -- Border set builder: 9-slice image border on a plain Frame, using PixelUtil (mirrors the UnitFrames preview).
    local function CreatePreviewBorderSet(hostFrame, texture)
        local bc = (SavedDB() and SavedDB().borderColor) or defaultSet.borderColor
        local f = CreateFrame("Frame", nil, hostFrame)
        f:SetFrameLevel(hostFrame:GetFrameLevel() + 1)
        f:SetAllPoints()
        f._texs = {}
        local function Mk()
            local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
            t:SetTexture(texture)
            t:SetVertexColor(bc.r, bc.g, bc.b)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
            f._texs[#f._texs + 1] = t
            return t
        end
        -- Corners inset UV by half a texel (T) from edges (0/1) so the GPU fully samples the outermost solid pixel line.
        local T = 0.042
        local function UnsnapAfter(t)
            if t.SetSnapToPixelGrid then
                t:SetSnapToPixelGrid(false)
                t:SetTexelSnappingBias(0)
            end
        end
        local tl = Mk()
        Pix.Size(tl, BORDER_CORNER, BORDER_CORNER)
        Pix.Point(tl, "TOPLEFT", f, "TOPLEFT", 0, 0)
        tl:SetTexCoord(T, 0.5, T, 0.5)
        UnsnapAfter(tl)
        local tr = Mk()
        Pix.Size(tr, BORDER_CORNER, BORDER_CORNER)
        Pix.Point(tr, "TOPRIGHT", f, "TOPRIGHT", 0, 0)
        tr:SetTexCoord(0.5, 1 - T, T, 0.5)
        UnsnapAfter(tr)
        local bl = Mk()
        Pix.Size(bl, BORDER_CORNER, BORDER_CORNER)
        Pix.Point(bl, "BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
        bl:SetTexCoord(T, 0.5, 0.5, 1 - T)
        UnsnapAfter(bl)
        local br = Mk()
        Pix.Size(br, BORDER_CORNER, BORDER_CORNER)
        Pix.Point(br, "BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
        br:SetTexCoord(0.5, 1 - T, 0.5, 1 - T)
        UnsnapAfter(br)
        -- Edges: sample the center column/row with half-texel width
        local H = 0.042
        local topY = Mk()
        Pix.Height(topY, BORDER_CORNER)
        Pix.Point(topY, "TOPLEFT", tl, "TOPRIGHT", 0, 0)
        Pix.Point(topY, "TOPRIGHT", tr, "TOPLEFT", 0, 0)
        topY:SetTexCoord(0.5 - H, 0.5 + H, T, 0.5)
        UnsnapAfter(topY)
        local bot = Mk()
        Pix.Height(bot, BORDER_CORNER)
        Pix.Point(bot, "BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0)
        Pix.Point(bot, "BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
        bot:SetTexCoord(0.5 - H, 0.5 + H, 0.5, 1 - T)
        UnsnapAfter(bot)
        local lft = Mk()
        Pix.Width(lft, BORDER_CORNER)
        Pix.Point(lft, "TOPLEFT", tl, "BOTTOMLEFT", 0, 0)
        Pix.Point(lft, "BOTTOMLEFT", bl, "TOPLEFT", 0, 0)
        lft:SetTexCoord(T, 0.5, 0.5 - H, 0.5 + H)
        UnsnapAfter(lft)
        local rgt = Mk()
        Pix.Width(rgt, BORDER_CORNER)
        Pix.Point(rgt, "TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
        Pix.Point(rgt, "BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)
        rgt:SetTexCoord(0.5, 1 - T, 0.5 - H, 0.5 + H)
        UnsnapAfter(rgt)
        f._corners = { tl, tr, bl, br }
        f._hEdges = { topY, bot }
        f._vEdges = { lft, rgt }
        function f:ApplySize(sz)
            for _, c in ipairs(self._corners) do
                Pix.Size(c, sz, sz)
            end
            for _, e in ipairs(self._hEdges) do
                Pix.Height(e, sz)
            end
            for _, e in ipairs(self._vEdges) do
                Pix.Width(e, sz)
            end
        end
        return f
    end

    local borderFrame = CreatePreviewBorderSet(healthWrapper, BORDER_TEX)
    local simpleBorderFrame = CreatePreviewBorderSet(healthWrapper, BORDER_TEX_SIMPLE)
    -- Custom border preview: dedicated child frame the shared border engine draws onto when Custom Border is enabled; stored on the wrapper (a frame we own) so it adds no new builder local.
    healthWrapper._customBorder = CreateFrame("Frame", nil, healthWrapper)
    healthWrapper._customBorder:SetAllPoints(healthWrapper)
    healthWrapper._customBorder:Hide()

    -- Solid 1px edge lines on all 4 sides of healthWrapper: the image border's outermost pixel can vanish at non-native scales (texture filtering), so these sit below it as a pixel-perfect fallback.
    local function MkSolidEdge()
        local t = healthWrapper:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetColorTexture(0, 0, 0, 1) -- placeholder; color updated in Update()
        if t.SetSnapToPixelGrid then
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
        end
        return t
    end
    local solidT = MkSolidEdge()
    solidT:SetHeight(1)
    Pix.Point(solidT, "TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
    Pix.Point(solidT, "TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
    local solidB = MkSolidEdge()
    solidB:SetHeight(1)
    Pix.Point(solidB, "BOTTOMLEFT", healthWrapper, "BOTTOMLEFT", 0, 0)
    Pix.Point(solidB, "BOTTOMRIGHT", healthWrapper, "BOTTOMRIGHT", 0, 0)
    local solidL = MkSolidEdge()
    solidL:SetWidth(1)
    Pix.Point(solidL, "TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
    Pix.Point(solidL, "BOTTOMLEFT", healthWrapper, "BOTTOMLEFT", 0, 0)
    local solidR = MkSolidEdge()
    solidR:SetWidth(1)
    Pix.Point(solidR, "TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
    Pix.Point(solidR, "BOTTOMRIGHT", healthWrapper, "BOTTOMRIGHT", 0, 0)
    local _solidEdges = { solidT, solidB, solidL, solidR }

    -- 9-slice soft glow frame for the target-glow preview; matches the real nameplate glow (background.png, ADD blend, blue tint), packed into one table to stay under Lua's 60-upvalue limit.
    local previewGlow = {}
    do
        local GLOW_TEX = "Interface\\AddOns\\CludesUINameplates\\Media\\background.png"
        local GM = 0.48 -- margin
        local GC = 12 -- corner size
        previewGlow.extend = 6
        local gf = CreateFrame("Frame", nil, popFrame)
        gf:SetFrameLevel(popFrame:GetFrameLevel() + 1)
        previewGlow.frame = gf
        -- Collected so Update() can re-tint the preview glow with target Glow Color/Opacity, matching live nameplates.
        previewGlow.texs = {}
        local gc0 = mod.GetTargetGlowColor()
        local ga0 = mod.GetTargetGlowAlpha()
        local function Mk(coords)
            local t = gf:CreateTexture(nil, "BACKGROUND")
            t:SetTexture(GLOW_TEX)
            t:SetVertexColor(gc0.r, gc0.g, gc0.b, ga0)
            t:SetBlendMode("ADD")
            t:SetTexCoord(unpack(coords))
            previewGlow.texs[#previewGlow.texs + 1] = t
            return t
        end
        local tl = Mk({ 0, GM, 0, GM })
        Pix.Size(tl, GC, GC)
        tl:SetPoint("TOPLEFT")
        local tr = Mk({ 1 - GM, 1, 0, GM })
        Pix.Size(tr, GC, GC)
        tr:SetPoint("TOPRIGHT")
        local bl = Mk({ 0, GM, 1 - GM, 1 })
        Pix.Size(bl, GC, GC)
        bl:SetPoint("BOTTOMLEFT")
        local br = Mk({ 1 - GM, 1, 1 - GM, 1 })
        Pix.Size(br, GC, GC)
        br:SetPoint("BOTTOMRIGHT")
        local topY = Mk({ GM, 1 - GM, 0, GM })
        Pix.Height(topY, GC)
        topY:SetPoint("TOPLEFT", tl, "TOPRIGHT")
        topY:SetPoint("TOPRIGHT", tr, "TOPLEFT")
        local bot = Mk({ GM, 1 - GM, 1 - GM, 1 })
        Pix.Height(bot, GC)
        bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT")
        bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
        local lft = Mk({ 0, GM, GM, 1 - GM })
        Pix.Width(lft, GC)
        lft:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
        lft:SetPoint("BOTTOMLEFT", bl, "TOPLEFT")
        local rgt = Mk({ 1 - GM, 1, GM, 1 - GM })
        Pix.Width(rgt, GC)
        rgt:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT")
        rgt:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
        gf:Hide()
    end

    -- Target "Highlight" preview: translucent wash over the health bar (color/opacity via the Target Highlight cog); getter refs stashed on previewGlow (already an Update() upvalue) to avoid new upvalues in the near-cap closure.
    previewGlow.highlight = healthBar:CreateTexture(nil, "OVERLAY", nil, 5)
    previewGlow.highlight:SetAllPoints(healthBar)
    do
        local hc = mod.GetTargetHighlightColor()
        previewGlow.highlight:SetColorTexture(hc.r, hc.g, hc.b, mod.GetTargetHighlightAlpha())
    end
    previewGlow.highlight:Hide()
    previewGlow.getCUI = mod.GetTargetGlowCludesUI
    previewGlow.getBorderOn = mod.GetTargetGlowBorderColor
    previewGlow.getHighlight = mod.GetTargetGlowHighlight
    previewGlow.getBorderCol = mod.GetTargetBorderColor
    previewGlow.getGlowCol = mod.GetTargetGlowColor
    previewGlow.getGlowAlpha = mod.GetTargetGlowAlpha
    previewGlow.getHighlightCol = mod.GetTargetHighlightColor
    previewGlow.getHighlightAlpha = mod.GetTargetHighlightAlpha
    -- Classic WoW UI (Global Settings > Style), latched for the session
    -- like the live plates: the mock wears the plain 1px black edge on the
    -- health and cast bars. Stashed here so Update gains no upvalue.
    previewGlow.classic = CludesUI.BlizzStyle.Active("nameplates") == "classic"
    previewGlow.black = { r = 0, g = 0, b = 0 }
    -- The WoW Forever variant (latched the same way): the level box right
    -- of the bar.
    previewGlow.forever = CludesUI.BlizzStyle.Forever("nameplates")

    -- Text overlay frame: renders above health bar fill and borders (same as real addon)
    local healthTextFrame = CreateFrame("Frame", nil, healthBar)
    healthTextFrame:SetAllPoints(healthBar)
    healthTextFrame:SetFrameLevel(healthBar:GetFrameLevel() + 11)

    -- Top text overlay: renders above health bar + borders so top-slot text is never hidden
    local topTextFrame = CreateFrame("Frame", nil, popFrame)
    topTextFrame:SetAllPoints(healthBar)
    topTextFrame:SetFrameLevel(healthBar:GetFrameLevel() + 10)

    -- Name text (anchored BOTTOM to health TOP, +4px gap, width 113)
    local nameFS = popFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(nameFS, FONT_PATH, 11, GetNPOptOutline())
    nameFS:SetPoint("BOTTOM", healthBar, "TOP", 0, 4)
    nameFS:SetWordWrap(false)
    nameFS:SetMaxLines(1)
    nameFS:SetText(CludesUI.L("Enemy Name Text"))
    nameFS:SetTextColor(1, 1, 1, 1)

    local nameRaidFrame = CreateFrame("Frame", nil, popFrame)
    nameRaidFrame:SetFrameLevel(healthBar:GetFrameLevel() + 12)
    nameRaidFrame:Hide()
    local nameRaidIcon = nameRaidFrame:CreateTexture(nil, "ARTWORK")
    nameRaidIcon:SetAllPoints()
    nameRaidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
    if SetRaidTargetIconTexture then
        SetRaidTargetIconTexture(nameRaidIcon, 1)
    end

    -- Health percentage text (right-aligned inside health bar)
    local hpText = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(hpText, FONT_PATH, 10, GetNPOptOutline())
    hpText:SetPoint("RIGHT", healthBar, -2, 0)
    hpText:SetText(previewHpPct .. "%")

    -- Health number (centered, hidden by default)
    local hpNumber = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(hpNumber, FONT_PATH, 10, GetNPOptOutline())
    hpNumber:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    local hpNumStr = tostring(previewHpVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    hpNumber:SetText(hpNumStr)
    hpNumber:Hide()

    -- Standalone level FontString mirrors the live plate's levelText; the player's level stands in for the mob level. Plain text: its colour comes from the slot's Text Coloring mode (previewGlow.slotColor).
    local lvlText = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(lvlText, FONT_PATH, 10, GetNPOptOutline())
    lvlText:SetPoint("CENTER", healthBar, "CENTER", 0, 0)
    lvlText:SetText((mod.GetUnitLevelText and mod.GetUnitLevelText("player")) or "??")
    lvlText:Hide()
    -- Target of Target sample: the preview mob targets the player (WoW Forever:
    -- with the surname, in the slot's Name Format, as live).
    popFrame._totFS = healthTextFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(popFrame._totFS, FONT_PATH, 10, GetNPOptOutline())
    popFrame._totFS:Hide()
    -- Custom texts: one font string per position, as live, showing the tag samples.
    popFrame._customFS = {}
    for _, key in ipairs(mod.textSlotKeys) do
        local fontStr = healthTextFrame:CreateFontString(nil, "OVERLAY")
        SetPVFont(fontStr, FONT_PATH, 10, GetNPOptOutline())
        fontStr:Hide()
        popFrame._customFS[key] = fontStr
    end
    -- Paints a custom text's sample; true when it names the unit (its width then
    -- ends where the name's would, as live).
    popFrame._pvCustom = function(fontStr, slotKey)
        local c = mod.NP_CustomCompiled(slotKey, SavedDB())
        if c then
            mod.NP_PaintCustom(fontStr, c, nil, slotKey)
        else
            fontStr:SetText("")
        end
        return c and c.has.name
    end
    popFrame._totSample = function(slotKey)
        return mod.NP_FormatName(CludesUI.WithSurname(UnitName("player")) or "", slotKey)
    end
    -- Its colour: in Class mode the player's class colour (the sample target),
    -- else the slot colour passed in.
    popFrame._totSampleColor = function(slotKey, r, g, b)
        if slotKey and mod.NP_SlotColorMode(slotKey, SavedDB()) == "class" then
            local _, ct = UnitClass("player")
            local cc = ct and CludesUI.GetClassColor(ct)
            if cc then
                return cc.r, cc.g, cc.b
            end
        end
        return r, g, b
    end

    -- Raid marker: custom marker.png image, position/size from settings
    local MARKER_PATH = "Interface\\AddOns\\CludesUI\\media\\marker.png"
    local raidFrame = CreateFrame("Frame", nil, healthBar)
    -- +12 keeps the marker above name/health text (healthTextFrame is health+11), matching the live plate.
    raidFrame:SetFrameLevel(healthBar:GetFrameLevel() + 12)
    local raidIcon = raidFrame:CreateTexture(nil, "ARTWORK")
    raidIcon:SetAllPoints()
    raidIcon:SetTexture(MARKER_PATH)

    -- Target arrows packed into a table to reduce upvalue count
    local ARROW_PATH = "Interface\\AddOns\\" .. ADDON_NAME .. "\\Media\\Arrows\\"
    local arrows = {}
    arrows.left = popFrame:CreateTexture(nil, "OVERLAY")
    arrows.left:SetTexture(ARROW_PATH .. "arrow_left.png")
    arrows.left:SetSize(11, 16)
    arrows.left:SetPoint("RIGHT", healthBar, "LEFT", -8, 0)
    arrows.left:Hide()
    arrows.right = popFrame:CreateTexture(nil, "OVERLAY")
    arrows.right:SetTexture(ARROW_PATH .. "arrow_right.png")
    arrows.right:SetSize(11, 16)
    arrows.right:SetPoint("LEFT", healthBar, "RIGHT", 8, 0)
    arrows.right:Hide()
    popFrame._arrows = arrows -- expose for Update resizing

    -- Classification icon (elite dragon) shown when transient toggle is on
    local classIcon = popFrame:CreateTexture(nil, "OVERLAY")
    classIcon:SetTexture("Interface\\AddOns\\CludesUI\\media\\elite-rare-indicator.png")
    classIcon:SetSize(24, 24)
    classIcon:Hide()
    -- Faction badge preview (Core Positions "Faction" element)
    local factionIcon = popFrame:CreateTexture(nil, "OVERLAY", nil, -1) -- under classIcon when stacked
    factionIcon:SetSize(20, 20)
    factionIcon:Hide()
    -- Quest Objective Text sample (Core Positions "Quest Objective Text" element):
    -- a quest mob's progress text in a frame of its own, sized to the text, on the
    -- live element's tier (health + 2). Its placement rides pf._qt (Update fills
    -- pos, x, y, w, h and shown for the extent passes).
    do
        local f = CreateFrame("Frame", nil, popFrame)
        f:SetFrameLevel(healthBar:GetFrameLevel() + 2)
        local fontStr = f:CreateFontString(nil, "OVERLAY")
        SetPVFont(fontStr, FONT_PATH, 12, GetNPOptOutline())
        fontStr:SetPoint("CENTER", f, "CENTER", 0, 0)
        fontStr:SetJustifyH("CENTER")
        fontStr:SetTextColor(1, 1, 1, 1)
        fontStr:SetText("2/6")
        f:Hide()
        popFrame._qt = { frame = f, fs = fontStr, shown = false, pos = "none", x = 0, y = 0, w = 0, h = 0 }
    end

    -- Cast bar (icon + bar fill health bar width)
    local cast = CreateFrame("StatusBar", nil, popFrame)
    cast:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    UnsnapTex(cast:GetStatusBarTexture())
    cast:SetMinMaxValues(0, 1)
    cast:SetValue(optionState._previewCastFill)
    cast:SetFrameLevel(popFrame:GetFrameLevel() + 10)

    local castBG = cast:CreateTexture(nil, "BACKGROUND")
    castBG:SetAllPoints()
    local _pcbg = (SavedDB() and SavedDB().castBgColor) or defaultSet.castBgColor
    local _pcba = (DBVal("castBgAlpha") or defaultSet.castBgAlpha)
    castBG:SetColorTexture(_pcbg.r, _pcbg.g, _pcbg.b, _pcba)
    UnsnapTex(castBG)

    -- Cast bar parts packed into a table to reduce upvalue count
    local castParts = {}
    castParts.bg = castBG

    -- Cast icon (flush to the left of the cast bar)
    castParts.iconFrame = CreateFrame("Frame", nil, cast)
    castParts.iconFrame:SetFrameLevel(healthBar:GetFrameLevel() + 1)
    castParts.iconFrame:SetSize(CAST_H, CAST_H)
    castParts.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", 0, 0)
    AddBorder(castParts.iconFrame)
    castParts.icon = castParts.iconFrame:CreateTexture(nil, "ARTWORK")
    UnsnapTex(castParts.icon)
    castParts.icon:SetAllPoints()
    castParts.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    castParts.icon:SetTexture(displayCastIcons[optionState._previewCastIconIdx])

    castParts.spark = cast:CreateTexture(nil, "OVERLAY", nil, 1)
    castParts.spark:SetTexture("Interface\\AddOns\\CludesUI\\media\\cast_spark.tga")
    UnsnapTex(castParts.spark)
    castParts.spark:SetSize(8, CAST_H)
    castParts.spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, 0)
    castParts.spark:SetBlendMode("ADD")

    -- Cast text frame: dedicated child ABOVE the cast border so name/target/timer render in front (mirrors the live castTextFrame); the PP border is cast+1 and would otherwise draw over text on cast's own OVERLAY layer.
    castParts.textFrame = CreateFrame("Frame", nil, cast)
    castParts.textFrame:SetAllPoints(cast)
    castParts.textFrame:SetFrameLevel(cast:GetFrameLevel() + 10)

    -- Cast name (left, width 70)
    castParts.nameFS = castParts.textFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(castParts.nameFS, FONT_PATH, 10, GetNPOptOutline())
    castParts.nameFS:SetPoint("LEFT", cast, 5, 0)
    castParts.nameFS:SetJustifyH("LEFT")
    castParts.nameFS:SetWordWrap(false)
    castParts.nameFS:SetMaxLines(1)
    castParts.nameFS:SetText(CludesUI.L("Spell Name"))

    -- Cast timer (far right)
    castParts.timerFS = castParts.textFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(castParts.timerFS, FONT_PATH, 10, GetNPOptOutline())
    castParts.timerFS:SetPoint("RIGHT", cast, -3, 0)
    castParts.timerFS:SetJustifyH("RIGHT")
    castParts.timerFS:SetWordWrap(false)
    castParts.timerFS:SetMaxLines(1)
    castParts.timerFS:SetTextColor(1, 1, 1, 1)
    castParts.timerFS:SetText("2.3")

    -- Cast target (right, anchored left of timer)
    castParts.targetFS = castParts.textFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(castParts.targetFS, FONT_PATH, 10, GetNPOptOutline())
    castParts.targetFS:SetPoint("RIGHT", castParts.timerFS, "LEFT", -4, 0)
    castParts.targetFS:SetJustifyH("RIGHT")
    castParts.targetFS:SetWordWrap(false)
    castParts.targetFS:SetMaxLines(1)
    castParts.targetFS:SetText(UnitName("player") or CludesUI.L("Spell Target"))

    -- Blizzard Style (Global Settings > Style): the stock plate look over the
    -- mock at the end of every Update, as the live plates get it -- the
    -- shadowed background art around the bar (the user's own fill texture
    -- stays), the bar's inner shadow, no CUI borders, the selection ring or
    -- deselected overlay, and the stock cast bar art. Stashed on previewGlow
    -- (an Update upvalue already) so Update stays under Lua's 60-upvalue cap.
    previewGlow.applyBlizz = function()
        local B, success = mod.NP_BLIZZ, mod.NP_AtlasOK
        if not (B and success) then
            return
        end
        borderFrame:Hide()
        simpleBorderFrame:Hide()
        for _, e in ipairs(_solidEdges) do
            e:Hide()
        end
        if healthWrapper._customBorder then
            healthWrapper._customBorder:Hide()
        end
        if success(B.barBg) then
            healthBG:SetAtlas(B.barBg)
            healthBG:SetVertexColor(1, 1, 1, 1)
            healthBG:ClearAllPoints()
            healthBG:SetPoint("TOPLEFT", healthBar, "TOPLEFT", -2, 3)
            healthBG:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 6, -6)
        end
        -- The stock fill art's footprint masks the fill, the highlight
        -- wash and the shadow inside the background's rim, as live.
        local maskTex = previewGlow.blizzMask
        if not maskTex and success(B.bar) then
            maskTex = healthBar:CreateMaskTexture()
            maskTex:SetAtlas(B.bar)
            mod.NP_SeatBarMask(maskTex, healthBar)
            previewGlow.blizzMask = maskTex
        end
        if maskTex then
            local fillTex = healthBar:GetStatusBarTexture()
            if fillTex and previewGlow.blizzMaskedFill ~= fillTex then
                pcall(fillTex.RemoveMaskTexture, fillTex, maskTex)
                fillTex:AddMaskTexture(maskTex)
                previewGlow.blizzMaskedFill = fillTex
            end
            if not previewGlow.blizzMaskedHL then
                previewGlow.highlight:AddMaskTexture(maskTex)
                previewGlow.blizzMaskedHL = true
            end
        end
        if mod.NP_BlizzBarShadow then
            mod.NP_BlizzBarShadow(healthBar, healthBar:GetHeight(), maskTex)
        end
        -- Selection ring while the target glow preview is on, else the
        -- deselected overlay every other plate carries.
        local sel, desel = previewGlow.blizzSel, previewGlow.blizzDesel
        local fv = previewGlow.forever and success(B.selYellow)
        if not sel and (fv or success(B.selected)) and success(B.deselected) then
            sel = healthBar:CreateTexture(nil, "OVERLAY", nil, 5)
            if fv then
                -- WoW Forever's thin yellow ring, as live.
                sel:SetAtlas(B.selYellow)
                sel:SetPoint("TOPLEFT", healthBG, "TOPLEFT", -3, 2)
                sel:SetPoint("BOTTOMRIGHT", healthBG, "BOTTOMRIGHT", 0, 2)
            else
                sel:SetAtlas(B.selected)
                sel:SetPoint("TOPLEFT", healthBG, "TOPLEFT", -1, 1)
                sel:SetPoint("BOTTOMRIGHT", healthBG, "BOTTOMRIGHT", -3, 3)
            end
            previewGlow.blizzSel = sel
            desel = healthBar:CreateTexture(nil, "OVERLAY", nil, 4)
            desel:SetAtlas(B.deselected)
            desel:SetPoint("TOPLEFT", healthBar, "TOPLEFT", 0, 1)
            desel:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, -1)
            previewGlow.blizzDesel = desel
        end
        if sel then
            if optionState.showTargetGlowPreview then
                local c = NAMEPLATE_BORDER_TARGET_COLOR
                if c and c.r then
                    sel:SetVertexColor(c.r, c.g, c.b)
                else
                    sel:SetVertexColor(1, 1, 1)
                end
                sel:Show()
                desel:Hide()
            else
                sel:Hide()
                desel:Show()
            end
        end
        -- The highlight wash sits under the ring, as on the live plates.
        previewGlow.highlight:SetDrawLayer("OVERLAY", 0)
        -- Cast bar: stock background (the retail art under WoW
        -- Forever too, as live), fill art and pip; no CUI border.
        if success(B.castBg) then
            CludesUI.StockAtlas(castParts.bg, B.castBg)
            castParts.bg:SetVertexColor(1, 1, 1, 1)
            castParts.bg:ClearAllPoints()
            castParts.bg:SetPoint("TOPLEFT", cast, "TOPLEFT", 1, 0)
            castParts.bg:SetPoint("BOTTOMRIGHT", cast, "BOTTOMRIGHT", -1, 0)
        end
        if success(B.cast) then
            cast:GetStatusBarTexture():SetAtlas(B.cast)
            cast:SetStatusBarColor(1, 1, 1, 1)
        end
        if success(B.castPip) then
            castParts.spark:SetAtlas(B.castPip)
            castParts.spark:SetWidth(4)
        end
        if Pix.GetBorders(cast) then
            Pix.HideBorder(cast)
        end
        castParts.icon:SetTexCoord(0, 1, 0, 1)
        -- WoW Forever: the level box right of the bar, as live
        -- (ns.NP_ApplyForeverLevelBox), with a level 60 at an even match.
        if previewGlow.forever and success(B.lvlBg) then
            local L = mod.NP_FOREVER_LVL
            local boxFrame = previewGlow.fvBox
            if not boxFrame then
                -- The live box's own frame; the mock paints its text.
                boxFrame = mod.NP_BuildForeverLevelBox(healthBar)
                local fontStr = boxFrame._fs
                -- Font BEFORE any SetText: a FontString with no font raises.
                SetPVFont(fontStr, FONT_PATH, L.font, GetNPOptOutline())
                fontStr:SetText("60")
                local c = FAIR_DIFFICULTY_COLOR
                if c and c.r then
                    fontStr:SetTextColor(c.r, c.g, c.b, 1)
                else
                    fontStr:SetTextColor(1, 0.82, 0, 1)
                end
                if boxFrame._sel then
                    boxFrame._sel:SetVertexColor(L.target[1], L.target[2], L.target[3])
                end
                previewGlow.fvBox = boxFrame
                -- Exposed for the click-navigation hit overlays (built
                -- after the first pf:Update()); the overlay hides with it.
                popFrame._fvLevelBox = boxFrame
            end
            local bh = healthBar:GetHeight() + L.pad
            boxFrame:SetSize(L.w, bh)
            SetPVFont(boxFrame._fs, FONT_PATH, mod.NP_ForeverLevelFont(bh), GetNPOptOutline())
            -- Its target border rides the ring's preview toggle.
            if boxFrame._sel then
                boxFrame._sel:SetShown(optionState.showTargetGlowPreview and true or false)
            end
            -- Show Level Box, as live.
            boxFrame:SetShown(mod.NP_ForeverBoxOn())
        end
    end
    -- Classic WoW UI: the vanilla borders over the mock, as the live plates
    -- get them (ns.NP_ApplyClassicHealthArt / CastArt): the health border
    -- with a level in its plate, the cast border with the icon in its
    -- plate, the vanilla spark; no CUI border. Same stash as applyBlizz.
    previewGlow.applyClassic = function(barH, castH)
        local C = mod.NP_CLASSIC
        if
            not (
                C
                and C.health
                and mod.NP_ClassicBorderPieces
                and mod.NP_SeatClassicBorder
                and mod.NP_ClassicLevelOffset
            )
        then
            return
        end
        borderFrame:Hide()
        simpleBorderFrame:Hide()
        for _, e in ipairs(_solidEdges) do
            e:Hide()
        end
        if healthWrapper._customBorder then
            healthWrapper._customBorder:Hide()
        end
        local hp = previewGlow.classicHealthArt
        if not hp then
            local hostRegion = CreateFrame("Frame", nil, healthBar)
            hostRegion:SetAllPoints(healthBar)
            hostRegion:EnableMouse(false)
            hostRegion:SetFrameLevel(healthBar:GetFrameLevel() + 6)
            hp = mod.NP_ClassicBorderPieces(hostRegion, C.health)
            previewGlow.classicHealthArt = hp
            local lv = healthTextFrame:CreateFontString(nil, "OVERLAY")
            -- Font BEFORE any SetText: a FontString with no font raises.
            SetPVFont(lv, FONT_PATH, 10, GetNPOptOutline())
            lv:SetJustifyH("CENTER")
            lv:SetText("60")
            lv:SetTextColor(1, 0.82, 0, 1)
            previewGlow.classicLevel = lv
            -- Exposed for the click-navigation hit overlays below; this
            -- runs from the build's first pf:Update(), before they build.
            popFrame._classicLevel = lv
            local ch = CreateFrame("Frame", nil, cast)
            ch:SetAllPoints(cast)
            ch:EnableMouse(false)
            ch:SetFrameLevel(cast:GetFrameLevel() + 2)
            previewGlow.classicCastArt = mod.NP_ClassicBorderPieces(ch, C.cast)
            castParts.iconFrame:SetFrameLevel(ch:GetFrameLevel() + 1)
        end
        local kh, kc = barH, castH
        mod.NP_SeatClassicBorder(hp, healthBar, kh)
        mod.NP_SeatClassicBorder(previewGlow.classicCastArt, cast, kc)
        local lv = previewGlow.classicLevel
        SetPVFont(lv, FONT_PATH, mod.NP_ClassicLevelSize(kh), GetNPOptOutline())
        local lx, ly = mod.NP_ClassicLevelOffset(kh)
        lv:ClearAllPoints()
        lv:SetPoint("CENTER", healthBar, "RIGHT", lx, ly)
        lv:Show()
        castParts.spark:SetTexture(C.spark)
        castParts.spark:SetSize(C.sparkSize * kc, C.sparkSize * kc)
        castParts.spark:ClearAllPoints()
        castParts.spark:SetPoint("CENTER", cast:GetStatusBarTexture(), "RIGHT", 0, C.sparkY * kc)
        if Pix.GetBorders(cast) then
            Pix.HideBorder(cast)
        end
        castParts.icon:SetTexCoord(0, 1, 0, 1)
    end

    -- Class power pips (cosmetic preview queries live class/spec resource count); packed into a single table to stay under Lua's 60-upvalue limit.
    local CP = {
        PIP_W = 8,
        PIP_H = 3,
        PIP_GAP = 2,
        EMPTY_R = 0.35,
        EMPTY_G = 0.35,
        EMPTY_B = 0.35,
        EMPTY_A = 0.85,
        MAX_POSSIBLE = 10,
        FILL_FRAC = 0.70,
        DEFAULT_COLOR = { 1.00, 0.84, 0.30 },
        CLASS_COLORS = {
            ROGUE = { 1.00, 0.96, 0.41 },
            DRUID = { 1.00, 0.49, 0.04 },
            PALADIN = { 0.96, 0.55, 0.73 },
            MONK = { 0.00, 1.00, 0.60 },
            WARLOCK = { 0.58, 0.51, 0.79 },
            MAGE = { 0.25, 0.78, 0.92 },
            EVOKER = { 0.20, 0.58, 0.50 },
            DEMONHUNTER = { 0.34, 0.06, 0.46 },
            SHAMAN = { 0.00, 0.44, 0.87 },
            HUNTER = { 0.67, 0.83, 0.45 },
            WARRIOR = { 0.78, 0.61, 0.43 },
            DEATHKNIGHT = { 0.77, 0.12, 0.23 },
        },
        CLASS_MAP = {
            ROGUE = { Enum.PowerType.ComboPoints, 5 },
            DRUID = { Enum.PowerType.ComboPoints, 5 },
            PALADIN = { Enum.PowerType.HolyPower, 5 },
            MONK = {
                [268] = { "BREWMASTER_STAGGER", 1 },
                [269] = { Enum.PowerType.Chi, 5 },
            },
            WARLOCK = { Enum.PowerType.SoulShards, 5 },
            MAGE = { Enum.PowerType.ArcaneCharges, 4 },
            EVOKER = { Enum.PowerType.Essence, 5 },
            DEMONHUNTER = { [581] = { "SOUL_FRAGMENTS_VENGEANCE", 6 } },
            SHAMAN = { [263] = { "MAELSTROM_WEAPON", 10 } },
            HUNTER = { [255] = { "TIP_OF_THE_SPEAR", 3 } },
            WARRIOR = { [72] = { "WHIRLWIND_STACKS", 4 } },
            DEATHKNIGHT = {
                [250] = { Enum.PowerType.Runes, 6 },
                [251] = { Enum.PowerType.Runes, 6 },
                [252] = { Enum.PowerType.Runes, 6 },
            },
        },
        WHITE = "Interface\\Buttons\\WHITE8X8",
        SQUARE_SHAPE = { square = true, circle = true, diamond = true, hexagon = true, shield = true },
    }
    CP.pips = {}
    for i = 1, CP.MAX_POSSIBLE do
        local backdrop = popFrame:CreateTexture(nil, "OVERLAY", nil, 2)
        backdrop:SetTexture(CP.WHITE)
        backdrop:SetVertexColor(0.082, 0.082, 0.082, 1)
        backdrop:Hide()
        local pipTex = popFrame:CreateTexture(nil, "OVERLAY", nil, 3)
        pipTex:SetTexture(CP.WHITE)
        pipTex:SetVertexColor(1, 1, 1, 1)
        pipTex:SetSize(CP.PIP_W, CP.PIP_H)
        pipTex:Hide()
        pipTex._bg = backdrop
        CP.pips[i] = pipTex
    end
    -- Bar-type class resource (e.g. stagger) preview
    CP.bar = CreateFrame("StatusBar", nil, popFrame)
    CP.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    CP.bar:SetFrameLevel(popFrame:GetFrameLevel() + 5)
    CP.bar:Hide()
    CP.bar._bg = CP.bar:CreateTexture(nil, "BACKGROUND")
    CP.bar._bg:SetAllPoints()
    CP.bar._bg:SetColorTexture(0.082, 0.082, 0.082, 1)

    -- Offset badge: shown by UpdateCP (via CP.Clamp) only when the class-resource
    -- Y offset is clamped to the plate in the preview. Reports the real offset
    -- at the clamped pip position so the configured value is still communicated
    -- without the pips dragging the header or leaving the frame.
    CP.offBadge = popFrame:CreateFontString(nil, "OVERLAY")
    SetPVFont(CP.offBadge, FONT_PATH, 9, GetNPOptOutline())
    CP.offBadge:SetTextColor(1, 0.82, 0.30) -- gold: marks a clamped value
    CP.offBadge:Hide()
    -- Delta arrow drawn beside the badge, pointing the way the offset continues
    -- past the clamped pips.
    CP.offArrow = popFrame:CreateTexture(nil, "OVERLAY")
    CP.offArrow:SetVertexColor(1, 0.82, 0.30)
    CP.offArrow:Hide()
    CP.ARROW_UP = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"
    CP.ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"

    -- Preview-only: clamp the class-resource pips to the plate's own edges so a
    -- large Y offset can't drag the header or push pips out of frame.
    -- Position-aware: a bottom-anchored resource may travel the whole plate
    -- height; a top-anchored one only the room above the health bar. healthTopY
    -- and castBotY are the health bar's top and the cast bar's bottom in pf
    -- coordinates. Returns the offset to draw, the real offset (only when
    -- clamped), and the clamped group's inboard edge with the direction into
    -- the plate (for the badge).
    function CP.Clamp(topPos, yDir, offset, ph, healthTopY, castBotY)
        local anchorY = topPos and healthTopY or castBotY
        local bandTop = -2 -- just inside pf top
        -- Just below the cast bar: measured from castBotY (which includes the
        -- cast Y offset) so the band matches the pip anchor -- a skin with a
        -- cast drop (classic) must not read as clamped at tiny offsets.
        -- 13 = the preview's 15px lower pad minus the 2px margin.
        local bandBot = castBotY - ph - 13
        local edge = anchorY + yDir * offset
        local gTop = (yDir == 1) and (edge + ph) or edge
        local gBot = (yDir == 1) and edge or (edge - ph)
        local shift = 0
        if gTop > bandTop then
            shift = bandTop - gTop
        elseif gBot < bandBot then
            shift = bandBot - gBot
        end
        -- Pips pinned at the top edge (shift < 0) -> badge below them (dir -1,
        -- arrow up); pinned at the bottom -> badge above them (dir +1, arrow down).
        local edgeInboard = (shift < 0) and (gBot + shift) or (gTop + shift)
        local dirInboard = (shift < 0) and -1 or 1
        return yDir * ((edge + shift) - anchorY), -- clamped offset (cpYShown)
            (shift ~= 0) and offset or nil, -- real offset, only when clamped
            edgeInboard,
            dirInboard
    end

    -- Shows the real offset centred on centerX (pf coordinates) beside the
    -- clamped pips, with the arrow just left of the number pointing the way the
    -- offset continues.
    function CP.ShowBadge(edgeInboard, dirInboard, centerX, realOff)
        local b = CP.offBadge
        b:SetText(string.format("%+d", math.floor(realOff + 0.5)))
        local textH = b:GetStringHeight()
        local cy = Snap(edgeInboard + dirInboard * (textH / 2 + 3))
        b:ClearAllPoints()
        b:SetPoint("CENTER", popFrame, "TOPLEFT", Snap(centerX), cy)
        b:Show()
        local a = CP.offArrow
        a:SetTexture((dirInboard == -1) and CP.ARROW_UP or CP.ARROW_DOWN)
        -- The chevron fills 22 x 12 of its 30 px image.
        local asz = math.max(8, math.floor(textH * 1.1 + 0.5))
        a:SetSize(asz, asz)
        a:ClearAllPoints()
        a:SetPoint("RIGHT", b, "LEFT", -1, 0)
        a:Show()
    end

    -- Debuffs: 2 icons centered above name
    local debuffs = {}
    local debuffData = {
        { icon = 136207, text = "8", dur = 12, elapsed = 4, stacks = 3 }, -- SW:P  (12s total, 4s elapsed 8s left, 3 stacks)
        { icon = 135978, text = "14", dur = 18, elapsed = 4, stacks = 0 }, -- VT    (18s total, 4s elapsed 14s left)
    }
    for i = 1, PV_CONST.DEBUFF_COUNT do
        local d = CreateFrame("Frame", nil, popFrame)
        d:SetSize(26, 26)
        d:SetPoint("BOTTOM", nameFS, "TOP", (i - (PV_CONST.DEBUFF_COUNT + 1) / 2) * 30, 2)
        d:SetFrameLevel(healthBar:GetFrameLevel() + 9)
        AddBorder(d)

        d.icon = d:CreateTexture(nil, "ARTWORK")
        UnsnapTex(d.icon)
        d.icon:SetPoint("TOPLEFT", d, "TOPLEFT", px, -px)
        d.icon:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -px, px)
        d.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        d.icon:SetTexture(debuffData[i].icon)
        _insetIcons[#_insetIcons + 1] = { tex = d.icon, parent = d, kind = "debuffs" }

        -- Text child frame: sits above the icon frame so highlights can be sandwiched between icon artwork and text via frame levels.
        local textFrame = CreateFrame("Frame", nil, d)
        textFrame:SetAllPoints()
        textFrame:SetFrameLevel(d:GetFrameLevel() + 2)

        d.durationText = textFrame:CreateFontString(nil, "OVERLAY")
        -- Preview aura text mirrors runtime: SlugFlag drops slug when the toggle is on.
        d.durationText:SetFont(FONT_PATH, 11, CludesUI.SlugFlag("OUTLINE, SLUG"))
        d.durationText:SetPoint("TOPLEFT", d, "TOPLEFT", -3, 4)
        d.durationText:SetJustifyH("LEFT")
        d.durationText:SetText(debuffData[i].text)

        -- Stack count text (bottom-right)
        d.stackText = textFrame:CreateFontString(nil, "OVERLAY")
        d.stackText:SetFont(FONT_PATH, 11, CludesUI.SlugFlag("OUTLINE, SLUG"))
        d.stackText:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", 1, 1)
        d.stackText:SetJustifyH("RIGHT")
        if debuffData[i].stacks > 0 then
            d.stackText:SetText(tostring(debuffData[i].stacks))
        else
            d.stackText:SetText("")
        end

        debuffs[i] = d
    end

    -- Buffs: 2 icons (left of health bar by default)
    local buffs = {}
    local buffData = {
        { icon = 136224, text = "12", frac = 0.20 }, -- Enrage
        { icon = 132333, text = "7", frac = 0.45 }, -- Battle Shout
    }
    for i = 1, PV_CONST.BUFF_COUNT do
        local bf = CreateFrame("Frame", nil, popFrame)
        bf:SetSize(24, 24)
        bf:SetFrameLevel(healthBar:GetFrameLevel() + 9)
        AddBorder(bf)
        bf.icon = bf:CreateTexture(nil, "ARTWORK")
        UnsnapTex(bf.icon)
        bf.icon:SetPoint("TOPLEFT", bf, "TOPLEFT", px, -px)
        bf.icon:SetPoint("BOTTOMRIGHT", bf, "BOTTOMRIGHT", -px, px)
        bf.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        bf.icon:SetTexture(buffData[i].icon)
        _insetIcons[#_insetIcons + 1] = { tex = bf.icon, parent = bf, kind = "buffs" }
        local bfTextFrame = CreateFrame("Frame", nil, bf)
        bfTextFrame:SetAllPoints()
        bfTextFrame:SetFrameLevel(bf:GetFrameLevel() + 2)
        bf.durationText = bfTextFrame:CreateFontString(nil, "OVERLAY")
        bf.durationText:SetFont(FONT_PATH, 12, CludesUI.SlugFlag("OUTLINE, SLUG"))
        bf.durationText:SetPoint("CENTER", bf, "CENTER", 0, 0)
        bf.durationText:SetText(buffData[i].text)
        buffs[i] = bf
    end

    -- CC: 2 icons (right of health bar by default)
    local ccs = {}
    local ccData = {
        { icon = 136071, text = "5", frac = 0.55 }, -- Polymorph
        { icon = 118699, text = "3", frac = 0.70 }, -- Fear
    }
    for i = 1, PV_CONST.CC_COUNT do
        local castFrame = CreateFrame("Frame", nil, popFrame)
        castFrame:SetSize(24, 24)
        castFrame:SetFrameLevel(healthBar:GetFrameLevel() + 9)
        AddBorder(castFrame)
        castFrame.icon = castFrame:CreateTexture(nil, "ARTWORK")
        UnsnapTex(castFrame.icon)
        castFrame.icon:SetPoint("TOPLEFT", castFrame, "TOPLEFT", px, -px)
        castFrame.icon:SetPoint("BOTTOMRIGHT", castFrame, "BOTTOMRIGHT", -px, px)
        castFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        castFrame.icon:SetTexture(ccData[i].icon)
        _insetIcons[#_insetIcons + 1] = { tex = castFrame.icon, parent = castFrame, kind = "ccs" }
        local cfTextFrame = CreateFrame("Frame", nil, castFrame)
        cfTextFrame:SetAllPoints()
        cfTextFrame:SetFrameLevel(castFrame:GetFrameLevel() + 2)
        castFrame.durationText = cfTextFrame:CreateFontString(nil, "OVERLAY")
        castFrame.durationText:SetFont(FONT_PATH, 12, CludesUI.SlugFlag("OUTLINE, SLUG"))
        castFrame.durationText:SetPoint("CENTER", castFrame, "CENTER", 0, 0)
        castFrame.durationText:SetText(ccData[i].text)
        ccs[i] = castFrame
    end

    -- Icon Borders cog (Custom Border on Aura Icons / on Spell Icon), as the live plates
    -- draw them: an owned border child over the icon in place of its 1px edges, the aura
    -- icon inset at 0, the plate's custom border style, size (exact px included), colour
    -- and offsets. Update calls it after the 1px edge and inset refreshes and the cast
    -- icon layout, and it overrides them only where a custom icon border draws. Stashed on
    -- previewGlow (already an Update upvalue) so Update gains no upvalue.
    do
        -- The custom border style, read once per pass by iconBorders for every icon.
        local sTex, sPath, sSz, sPx, sR, sG, sB, sA, sOX, sOY, sSX, sSY, sMult
        -- One icon, built once. ApplyBorderStyle runs only when an input it draws from
        -- changed since this icon's last paint: texture key and its resolved file, size
        -- step, exact px, colour and alpha, offsets, shifts, the pixel grid, the icon's
        -- effective scale (the anchor snap), its frame level, or its shown state. The
        -- 1px edges and the inset are reset by every Update pass, so they are overridden
        -- on every pass.
        local function paint(f, enabled, lvlAdd, iconTex)
            local cb = f._pvCustomBorder
            if enabled then
                if not cb then
                    cb = CreateFrame("Frame", nil, f)
                    cb:SetAllPoints(f)
                    f._pvCustomBorder = cb
                end
                local lvl = f:GetFrameLevel() + lvlAdd
                local es = cb:GetEffectiveScale()
                if
                    not cb:IsShown()
                    or cb:GetFrameLevel() ~= lvl
                    or cb._sES ~= es
                    or cb._sMult ~= sMult
                    or cb._sTex ~= sTex
                    or cb._sPath ~= sPath
                    or cb._sSz ~= sSz
                    or cb._sPx ~= sPx
                    or cb._sR ~= sR
                    or cb._sG ~= sG
                    or cb._sB ~= sB
                    or cb._sA ~= sA
                    or cb._sOX ~= sOX
                    or cb._sOY ~= sOY
                    or cb._sSX ~= sSX
                    or cb._sSY ~= sSY
                then
                    cb:SetFrameLevel(lvl)
                    CludesUI.ApplyBorderStyle(
                        cb,
                        sSz,
                        sR,
                        sG,
                        sB,
                        sA,
                        sTex,
                        sOX,
                        sOY,
                        sSX,
                        sSY,
                        "nameplates",
                        sSz,
                        nil,
                        sPx
                    )
                    cb._sES, cb._sMult, cb._sTex, cb._sPath = es, sMult, sTex, sPath
                    cb._sSz, cb._sPx = sSz, sPx
                    cb._sR, cb._sG, cb._sB, cb._sA = sR, sG, sB, sA
                    cb._sOX, cb._sOY, cb._sSX, cb._sSY = sOX, sOY, sSX, sSY
                end
                local e = f._cuiIconEdges
                if e then
                    for k = 1, #e do
                        e[k]:Hide()
                    end
                end
                if iconTex then
                    iconTex:ClearAllPoints()
                    iconTex:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
                    iconTex:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
                end
            elseif cb and cb:IsShown() then
                -- Off through ApplyBorderStyle(frame, 0), so no UI scale re-apply revives it.
                CludesUI.ApplyBorderStyle(cb, 0)
                cb:Hide()
            end
        end
        previewGlow.iconBorders = function(customOn, showIcon)
            if CludesUI._prebuilding then
                return
            end
            local ib = mod.GetIconBorderEnabled
            local saved = SavedDB()
            if (saved and saved.castIconSeparator) or cast._iconSeam then
                mod.NP_ApplyCastIconSeparator(cast, castParts.iconFrame, saved, customOn and showIcon)
            end
            sTex = DBVal("customBorderTexture") or defaultSet.customBorderTexture
            sPath = CludesUI.ResolveBorderTexture(sTex)
            sSz = DBVal("customBorderSize") or defaultSet.customBorderSize
            sPx = CludesUI.BorderPx(saved and saved.customBorderSizePx, sSz, sTex)
            local ccol = (saved and saved.customBorderColor) or defaultSet.customBorderColor
            sR, sG, sB = ccol.r, ccol.g, ccol.b
            sA = DBVal("customBorderAlpha") or defaultSet.customBorderAlpha or 1
            sOX, sOY = DBVal("customBorderOffset"), DBVal("customBorderOffsetY")
            sSX, sSY = DBVal("customBorderShiftX"), DBVal("customBorderShiftY")
            sMult = CludesUI.PP.mult
            local castOn = customOn
                and showIcon
                and DBVal("castIconCustomBorder") == true
                and DBVal("castbarIconInWidth") ~= true
                and (not ib or ib("cast"))
            -- Above the icon, as the live border sits at the icon's level + 3.
            paint(castParts.iconFrame, castOn, 3)
            local auraOn = customOn and DBVal("auraIconCustomBorder") == true
            -- Under the aura text frame (icon level + 2).
            for i = 1, PV_CONST.DEBUFF_COUNT do
                paint(debuffs[i], auraOn and (not ib or ib("debuffs")), 1, debuffs[i].icon)
            end
            for i = 1, PV_CONST.BUFF_COUNT do
                paint(buffs[i], auraOn and (not ib or ib("buffs")), 1, buffs[i].icon)
            end
            for i = 1, PV_CONST.CC_COUNT do
                paint(ccs[i], auraOn and (not ib or ib("ccs")), 1, ccs[i].icon)
            end
        end
    end
    -- Core Text slot colours (file level, shared with the custom text popup).
    previewGlow.slotColor = mod.NPO_PreviewSlotColor

    -- Cached position values for the health bar anchor (see health block).
    local _cachedRawBarW, _cachedXOff

    -------------------------------------------------------------------
    --  Update re-reads DB, applies to existing frames. No rebuilds.
    -------------------------------------------------------------------
    popFrame.Update = function(self)
        local fontFile = (CludesUI.GetFontPath("nameplates")) or DBVal("font")
        -- Body-text outline, already slug-gated at the source (GetFontOutlineFlag).
        local npOutline = (CludesUI.GetFontOutlineFlag("nameplates")) or "OUTLINE, SLUG"
        local barH = Snap(DBVal("healthBarHeight"))
        local rawBarW = BAR_W + DBVal("healthBarWidth")
        local barW = IsDragging() and rawBarW or Snap(rawBarW)
        local castH = Snap(DBVal("castBarHeight") or defaultSet.castBarHeight)
        local showArrows = DBVal("showTargetArrows") == true
        local arrowStyleKey = DBVal("targetArrowStyle")
            or (DBVal("targetArrowDouble") and "double")
            or "simple"
        local arrowSt = mod.TARGET_ARROW_STYLES[arrowStyleKey] or mod.TARGET_ARROW_STYLES.simple
        local arrowScale = DBVal("targetArrowScale") or defaultSet.targetArrowScale or 1.0
        local arrowW = math.floor(arrowSt.w * arrowScale + 0.5)
        local arrowH = math.floor(16 * arrowScale + 0.5)
        if popFrame._arrows then
            local _acr, _acg, _acb = mod.GetTargetArrowColor(SavedDB())
            popFrame._arrows.left:SetTexture(mod.TARGET_ARROW_DIR .. arrowSt.l .. ".png")
            popFrame._arrows.right:SetTexture(mod.TARGET_ARROW_DIR .. arrowSt.r .. ".png")
            popFrame._arrows.left:SetVertexColor(_acr, _acg, _acb)
            popFrame._arrows.right:SetVertexColor(_acr, _acg, _acb)
            popFrame._arrows.left:SetSize(arrowW, arrowH)
            popFrame._arrows.right:SetSize(arrowW, arrowH)
        end
        local cbColor = (SavedDB() and SavedDB().castBar) or defaultSet.castBar
        local debuffY = DBVal("debuffYOffset") or defaultSet.debuffYOffset

        -- Class power top push: extra offset for name/auras when pips sit above the bar
        local cpPush = 0
        if DBVal("showClassPower") == true then
            local cpPos = DBVal("classPowerPos") or defaultSet.classPowerPos
            if cpPos == "top" then
                local cpScale = DBVal("classPowerScale") or defaultSet.classPowerScale
                -- Reserve only the base pip height above the bar; the Y offset is
                -- NOT added here so the preview frame never grows with the offset.
                -- UpdateCP clamps the pips inside the plate and badges the real value.
                cpPush = CP.PIP_H * cpScale
            end
        end
        -- Apply current random preview values (regenerated on tab switch only)
        local curHpPct = optionState._previewHpPct or 70
        local curHpVal = math.floor(PV_CONST.FAKE_MAX_HP * curHpPct / 100)
        healthBar:SetValue(curHpVal)
        local pctStr = curHpPct .. "%"
        local pctNoSignStr = tostring(curHpPct)
        local hpNumStr = tostring(curHpVal):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        local hpMaxStr =
            tostring(PV_CONST.FAKE_MAX_HP):reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
        -- Synthetic fractional percent so "Show % Decimal" is visible here (the fake preview HP is a whole number).
        local pctStrDec = string.format("%.1f%%", curHpPct + 0.4)
        local pctNoSignStrDec = string.format("%.1f", curHpPct + 0.4)
        -- Text on hpText/hpNumber is set later by the slot-based positioning logic
        cast:SetValue(optionState._previewCastFill or 0.60)
        castParts.icon:SetTexture(displayCastIcons[optionState._previewCastIconIdx or 1])
        do
            -- Backgrounds and Textured Background as live (the Blizzard Style
            -- pass below wins).
            local hbgC = (SavedDB() and SavedDB().bgColor) or defaultSet.bgColor
            local cbgC = (SavedDB() and SavedDB().castBgColor) or defaultSet.castBgColor
            mod.NP_TexBgPaint(
                healthBG,
                mod.NP_TexBgPath(SavedDB(), false),
                hbgC.r,
                hbgC.g,
                hbgC.b,
                DBVal("bgAlpha") or defaultSet.bgAlpha
            )
            mod.NP_TexBgPaint(
                castParts.bg,
                mod.NP_TexBgPath(SavedDB(), true),
                cbgC.r,
                cbgC.g,
                cbgC.b,
                DBVal("castBgAlpha") or defaultSet.castBgAlpha
            )
        end

        -- Cast bar border (pixel-perfect, mirrors the real nameplates)
        do
            local cbSz = DBVal("castBorderSize") or defaultSet.castBorderSize or 0
            local cbC = (SavedDB() and SavedDB().castBorderColor) or defaultSet.castBorderColor
            -- Classic WoW UI: no CUI edge; the vanilla cast border is drawn at the end of Update.
            if previewGlow.classic then
                cbSz = 0
                cbC = previewGlow.black
            end
            if Pix and Pix.CreateBorder then
                if cbSz and cbSz > 0 then
                    if Pix.GetBorders(cast) then
                        Pix.SetBorderColor(cast, cbC.r, cbC.g, cbC.b, 1)
                        Pix.SetBorderSize(cast, cbSz)
                        Pix.ShowBorder(cast)
                    else
                        Pix.CreateBorder(cast, cbC.r, cbC.g, cbC.b, 1, cbSz, "OVERLAY", 7)
                    end
                elseif Pix.GetBorders(cast) then
                    Pix.HideBorder(cast)
                end
            end
        end

        -- Border style toggle
        local customOn = DBVal("customBorderEnabled")
        if customOn == nil then
            customOn = defaultSet.customBorderEnabled
        end
        -- Classic WoW UI: the plain 1px black edge, as live (no custom border).
        if previewGlow.classic then
            customOn = false
        end
        local pcb = healthWrapper._customBorder
        if customOn then
            -- Custom border (shared engine) replaces the simple preview border.
            borderFrame:Hide()
            simpleBorderFrame:Hide()
            for _, e in ipairs(_solidEdges) do
                e:Hide()
            end
            if pcb and CludesUI.ApplyBorderStyle then
                local ctex = DBVal("customBorderTexture") or defaultSet.customBorderTexture
                local csz = DBVal("customBorderSize") or defaultSet.customBorderSize
                local ccol = (SavedDB() and SavedDB().customBorderColor) or defaultSet.customBorderColor
                local ca = DBVal("customBorderAlpha") or defaultSet.customBorderAlpha or 1
                local cbehind = DBVal("customBorderBehind")
                if cbehind == nil then
                    cbehind = defaultSet.customBorderBehind
                end
                pcb:SetFrameLevel(
                    cbehind and math.max(0, healthWrapper:GetFrameLevel() - 1)
                        or (healthWrapper:GetFrameLevel() + 2)
                )
                local cpx = CludesUI.BorderPx(SavedDB() and SavedDB().customBorderSizePx, csz, ctex)
                CludesUI.ApplyBorderStyle(
                    pcb,
                    csz,
                    ccol.r,
                    ccol.g,
                    ccol.b,
                    ca,
                    ctex,
                    DBVal("customBorderOffset"),
                    DBVal("customBorderOffsetY"),
                    DBVal("customBorderShiftX"),
                    DBVal("customBorderShiftY"),
                    "nameplates",
                    csz,
                    nil,
                    cpx
                )
                -- Show Seam Line, as the live wrap draws it (with or without Casts In
                -- Front of Nameplates: both draw the same single outline).
                mod.NP_SetWrapSeam(
                    pcb,
                    cast,
                    DBVal("wrapBorderCastbar") == true and DBVal("wrapBorderSeam") == true,
                    ctex,
                    csz,
                    cpx,
                    ccol.r,
                    ccol.g,
                    ccol.b,
                    ca,
                    healthBar
                )
                -- The mock cast bar sits above this border's frame: lift the seam over its
                -- fill, under its text (cast + 5), as it draws on a live plate.
                if pcb._cbSeamHost then
                    pcb._cbSeamHost:SetFrameLevel(cast:GetFrameLevel() + 3)
                end
            end
        else
            if pcb and CludesUI.ApplyBorderStyle then
                CludesUI.ApplyBorderStyle(pcb, 0)
                pcb:Hide()
                mod.NP_SetWrapSeam(pcb, nil, false)
            end
            local bOn = DBVal("showBorder")
            if bOn == nil then
                bOn = defaultSet.showBorder
            end
            -- Classic WoW UI: no CUI edge; the vanilla health border is drawn at the end of Update.
            if previewGlow.classic then
                bOn = false
            end
            if bOn then
                borderFrame:Hide()
                simpleBorderFrame:Show()
                for _, e in ipairs(_solidEdges) do
                    e:Show()
                end
                simpleBorderFrame:ApplySize(
                    previewGlow.classic and 1 or (DBVal("borderSize") or defaultSet.borderSize)
                )
            else
                borderFrame:Hide()
                simpleBorderFrame:Hide()
                for _, e in ipairs(_solidEdges) do
                    e:Hide()
                end
            end
        end
        -- Rounded corners, as on a live plate. The image border cannot round,
        -- so a rounded Basic border draws as a Solid one on the custom border
        -- frame (the live plate's Basic border is that same Solid border).
        do
            local radius = (not CludesUI.BlizzStyle.Get("nameplates") and DBVal("cornerRadius")) or 0
            -- Wrap Around Castbar keeps the plates square, as on a live plate.
            if DBVal("wrapBorderCastbar") == true then
                radius = 0
            end
            local look = customOn and (DBVal("customBorderTexture") or defaultSet.customBorderTexture)
                or "solid"
            -- A custom style that cannot round keeps the cast bar square too.
            if not CludesUI.RoundedStyleOK(look) then
                radius = 0
            end
            if radius > 0 and not customOn and pcb and simpleBorderFrame:IsShown() then
                local bc = (SavedDB() and SavedDB().borderColor) or defaultSet.borderColor
                simpleBorderFrame:Hide()
                for _, e in ipairs(_solidEdges) do
                    e:Hide()
                end
                pcb:Show()
                CludesUI.ApplyBorderStyle(
                    pcb,
                    DBVal("borderSize") or defaultSet.borderSize,
                    bc.r,
                    bc.g,
                    bc.b,
                    1,
                    "solid"
                )
            end
            if radius > 0 then
                -- Join Cast Bar: the preview always shows its cast bar.
                local corners, castCorners = DBVal("cornerMask"), DBVal("cornerMask")
                if DBVal("cornerJoinCast") then
                    corners, castCorners = CludesUI.RoundedJoinCorners(corners)
                end
                CludesUI.RoundCorners(popFrame, radius, {
                    roots = {},
                    rect = healthBar,
                    border = pcb,
                    style = look,
                    corners = corners,
                    textures = {
                        healthBar:GetStatusBarTexture(),
                        healthBG,
                        pvAbs.absorb:GetStatusBarTexture(),
                        pvAbs.absorbForward:GetStatusBarTexture(),
                    },
                })
                CludesUI.RoundCorners(cast, radius, {
                    roots = {},
                    border = cast,
                    corners = castCorners,
                    textures = { cast:GetStatusBarTexture(), castBG },
                })
            else
                CludesUI.RoundCorners(popFrame, 0)
                CludesUI.RoundCorners(cast, 0)
            end
        end

        -- Refresh all 1px AddBorder edges (cast icon, aura icons)
        for _, refreshFn in ipairs(_borderRefreshers) do
            refreshFn()
        end
        do
            local function setEdges(f, enabled)
                local e = f and f._cuiIconEdges
                if not e then
                    return
                end
                for i = 1, #e do
                    e[i]:SetShown(enabled)
                end
            end
            local ib = mod.GetIconBorderEnabled
            setEdges(castParts.iconFrame, not ib or ib("cast"))
            for i = 1, PV_CONST.DEBUFF_COUNT do
                setEdges(debuffs[i], not ib or ib("debuffs"))
            end
            for i = 1, PV_CONST.BUFF_COUNT do
                setEdges(buffs[i], not ib or ib("buffs"))
            end
            for i = 1, PV_CONST.CC_COUNT do
                setEdges(ccs[i], not ib or ib("ccs"))
            end
        end

        -- Refresh icon insets (1px from border) for current scale
        local curPx = Snap(1)
        for _, record in ipairs(_insetIcons) do
            local inset = curPx
            if record.kind and mod.GetIconBorderEnabled and not mod.GetIconBorderEnabled(record.kind) then
                inset = 0
            end
            record.tex:ClearAllPoints()
            record.tex:SetPoint("TOPLEFT", record.parent, "TOPLEFT", inset, -inset)
            record.tex:SetPoint("BOTTOMRIGHT", record.parent, "BOTTOMRIGHT", -inset, inset)
        end

        local bc = (SavedDB() and SavedDB().borderColor) or defaultSet.borderColor
        if previewGlow.classic then
            bc = previewGlow.black
        end
        for _, texture in ipairs(borderFrame._texs) do
            texture:SetVertexColor(bc.r, bc.g, bc.b)
        end
        for _, texture in ipairs(simpleBorderFrame._texs) do
            texture:SetVertexColor(bc.r, bc.g, bc.b)
        end
        for _, e in ipairs(_solidEdges) do
            e:SetColorTexture(bc.r, bc.g, bc.b, 1)
            if e.SetSnapToPixelGrid then
                e:SetSnapToPixelGrid(false)
                e:SetTexelSnappingBias(0)
            end
        end

        -- "Wrap Around Castbar" preview: skipped while never enabled (borders keep their original anchoring). When on, extends the border down to the cast bar and restores anchors on toggle-off; no re-leveling needed.
        local wrapOn = DBVal("wrapBorderCastbar")
        if wrapOn == nil then
            wrapOn = defaultSet.wrapBorderCastbar
        end
        local borderVisible
        if customOn then
            borderVisible = true
        else
            local b = DBVal("showBorder")
            if b == nil then
                b = defaultSet.showBorder
            end
            borderVisible = b
        end
        if previewGlow.classic then
            borderVisible = true
        end
        local wrapActive = wrapOn and borderVisible
        if wrapActive or self._wrapPrev then
            local bottomF = healthWrapper
            if wrapActive then
                bottomF = cast
            end
            simpleBorderFrame:ClearAllPoints()
            simpleBorderFrame:SetPoint("TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
            simpleBorderFrame:SetPoint("TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
            simpleBorderFrame:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            simpleBorderFrame:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            pcb:ClearAllPoints()
            pcb:SetPoint("TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
            pcb:SetPoint("TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
            pcb:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            pcb:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            -- Solid 1px fallback edges: extend bottom + side bottoms too (_solidEdges = {top, bottom, left, right}; top is untouched).
            local sB, sL, sR = _solidEdges[2], _solidEdges[3], _solidEdges[4]
            sB:ClearAllPoints()
            sB:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            sB:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            sL:ClearAllPoints()
            sL:SetPoint("TOPLEFT", healthWrapper, "TOPLEFT", 0, 0)
            sL:SetPoint("BOTTOMLEFT", bottomF, "BOTTOMLEFT", 0, 0)
            sR:ClearAllPoints()
            sR:SetPoint("TOPRIGHT", healthWrapper, "TOPRIGHT", 0, 0)
            sR:SetPoint("BOTTOMRIGHT", bottomF, "BOTTOMRIGHT", 0, 0)
            self._wrapPrev = wrapActive
        end

        -- Slots and each element's own icon size (its slot's size while unset), as live
        local debuffSlotVal = DBVal("debuffSlot") or defaultSet.debuffSlot
        local buffSlotVal = DBVal("buffSlot") or defaultSet.buffSlot
        local ccSlotVal = DBVal("ccSlot") or defaultSet.ccSlot
        local debuffSz = mod.NP_ElementSize("debuffs", SavedDB())
        local buffSz = mod.NP_ElementSize("buffs", SavedDB())
        local ccSz = mod.NP_ElementSize("ccs", SavedDB())

        -- Aura tier as on the live plate: auras (800) sit below the text tier (900),
        -- unless the slot's Raise Strata lifts them to HIGH, above everything else.
        -- Here: text health+10/+11, auras +9, raised auras +13 (hit overlays +15).
        do
            local hl = healthBar:GetFrameLevel()
            for k = 1, 3 do
                local entries = (k == 1 and debuffs) or (k == 2 and buffs) or ccs
                local slotVal = (k == 1 and debuffSlotVal) or (k == 2 and buffSlotVal) or ccSlotVal
                local lvl = hl + ((slotVal ~= "none" and DBVal(slotVal .. "SlotRaiseStrata")) and 13 or 9)
                for i = 1, #entries do
                    local f = entries[i]
                    if f:GetFrameLevel() ~= lvl then
                        f:SetFrameLevel(lvl)
                        f.durationText:GetParent():SetFrameLevel(lvl + 2)
                    end
                end
            end
        end

        -- Per-element gap between icons (user setting), then compute per-type center-to-center spacing
        local debuffGap = DBVal("debuffSpacing") or defaultSet.debuffSpacing
        local buffGap = DBVal("buffSpacing") or defaultSet.buffSpacing
        local ccGap = DBVal("ccSpacing") or defaultSet.ccSpacing
        local debuffSpacing = debuffGap + debuffSz
        local buffSpacing = buffGap + buffSz
        local ccSpacing = ccGap + ccSz

        -- Cropped icons mirror runtime: height = 80% of width + matching texcoord trim (off by default). ns.GetAuraCrop returns the height FACTOR (truthy number) when cropped, so preview follows the slider.
        local debuffCrop = mod.GetAuraCrop("debuffs")
        local buffCrop = mod.GetAuraCrop("buffs")
        local ccCrop = mod.GetAuraCrop("ccs")
        local debuffH = mod.GetAuraCropHeight(debuffCrop, debuffSz)
        local buffH = mod.GetAuraCropHeight(buffCrop, buffSz)
        local ccH = mod.GetAuraCropHeight(ccCrop, ccSz)

        -- Arrow visibility deferred until after auras are placed (arrows go OUTSIDE the outermost side aura).

        -- Raid marker position and size (slot-based)
        local rmPos = DBVal("raidMarkerPos") or defaultSet.raidMarkerPos
        local rmSize = mod.NP_ElementSize("raidmarker", SavedDB())
        local rmXOff, rmYOff = 0, 0
        if rmPos ~= "none" then
            rmXOff = DBVal(rmPos .. "SlotXOffset") or 0
            rmYOff = DBVal(rmPos .. "SlotYOffset") or 0
        end

        -- Classification slot
        local clPos = DBVal("classificationSlot") or defaultSet.classificationSlot

        -- Clear drag-show flags when not dragging
        if not IsDragging() then
            optionState._sliderDragShowRaidMarker = false
            optionState._sliderDragShowClassification = false
        end

        local showRM = optionState.showRaidMarkerPreview or optionState._sliderDragShowRaidMarker

        -- Cast spell icon settings (mirror ns.GetCastIconReserve), computed once and reused by the core icons, cast bar, and target arrows below; barH/castH are already-snapped profile numbers in scope.
        local icdb = SavedDB()
        local showIcon = true
        if icdb and icdb.showCastIcon ~= nil then
            showIcon = icdb.showCastIcon
        end
        local iconInWidth = defaultSet.castbarIconInWidth
        if icdb and icdb.castbarIconInWidth ~= nil then
            iconInWidth = icdb.castbarIconInWidth
        end
        local onRight = (icdb and icdb.castIconOnRight) or false
        local fullSize = (icdb and icdb.castIconFullSize) or false
        local iconScale = (icdb and icdb.castIconScale) or defaultSet.castIconScale
        local iconXOff = (icdb and icdb.castIconOffsetX) or defaultSet.castIconOffsetX or 0
        local iconYOff = (icdb and icdb.castIconOffsetY) or defaultSet.castIconOffsetY or 0
        local castIconLeftPush, castIconRightPush = 0, 0
        if previewGlow.classic then
            -- Classic WoW UI, as live: the spell icon sits inside the cast
            -- border's own plate and reserves nothing of its own, while the
            -- border art counts as part of the bar on both sides.
            castIconLeftPush, castIconRightPush = mod.NP_ClassicBarReserve()
        elseif showIcon and onRight and not iconInWidth and not fullSize then
            castIconRightPush = castH * iconScale
        end
        -- WoW Forever, as live: right-side elements clear the level box
        -- (it never counts for centring).
        if previewGlow.forever then
            castIconRightPush = castIconRightPush + mod.NP_ForeverSide()
        end
        -- The full-size icon pushes an element beside it only where their spans
        -- meet, as live during a cast (ns.NP_FullIconPush; the preview always
        -- shows its cast bar): the element centres on the bar plus y, sz tall.
        local function FullPush(sideName, posY, sz)
            if previewGlow.classic or not (showIcon and fullSize) or (sideName == "right") ~= onRight then
                return 0
            end
            local mid = barH / 2 + posY
            local castBottom = (DBVal("castBarOffsetY") or defaultSet.castBarOffsetY) - castH
            return mod.NP_MeetsFullIcon(mid - sz / 2, mid + sz / 2, barH, castBottom) and (barH + castH) or 0
        end

        raidFrame:ClearAllPoints()
        raidFrame:SetSize(rmSize, rmSize)
        if rmPos == "none" or not showRM then
            raidFrame:Hide()
            if popFrame._raidOverlay then
                popFrame._raidOverlay:Hide()
            end
        else
            if rmPos == "top" then
                raidFrame:SetPoint("BOTTOM", healthBar, "TOP", rmXOff, debuffY + cpPush + rmYOff)
            elseif rmPos == "left" then
                local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                raidFrame:SetPoint(
                    "RIGHT",
                    healthBar,
                    "LEFT",
                    -sideOff - castIconLeftPush - FullPush("left", rmYOff, rmSize) + rmXOff,
                    rmYOff
                )
            elseif rmPos == "right" then
                local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                raidFrame:SetPoint(
                    "LEFT",
                    healthBar,
                    "RIGHT",
                    sideOff + castIconRightPush + FullPush("right", rmYOff, rmSize) + rmXOff,
                    rmYOff
                )
            elseif rmPos == "topleft" then
                raidFrame:SetPoint(
                    "BOTTOMLEFT",
                    healthBar,
                    "TOPLEFT",
                    rmXOff,
                    cpPush + mod.NP_TopCornerLift("topleft", SavedDB()) + rmYOff
                )
            elseif rmPos == "topright" then
                raidFrame:SetPoint(
                    "BOTTOMRIGHT",
                    healthBar,
                    "TOPRIGHT",
                    rmXOff,
                    cpPush + mod.NP_TopCornerLift("topright", SavedDB()) + rmYOff
                )
            elseif rmPos == "bottom" then
                raidFrame:SetPoint("TOP", cast, "BOTTOM", rmXOff, -2 + rmYOff)
            end
            raidFrame:SetAlpha(1)
            raidFrame:Show()
            if popFrame._raidOverlay then
                popFrame._raidOverlay:Show()
            end
        end

        -- Classification icon (elite dragon) slot-based
        classIcon:ClearAllPoints()
        local clXOff, clYOff = 0, 0
        if clPos ~= "none" then
            clXOff = DBVal(clPos .. "SlotXOffset") or 0
            clYOff = DBVal(clPos .. "SlotYOffset") or 0
        end
        local hideRare = DBVal("classificationHideRare")
        -- The elite sample at the Elite/Rare Indicator's own size, or the quest
        -- mark it shows while that is off at the Quest Indicator's.
        local reIconSz = mod.NP_ElementSize(hideRare and "quest" or "rare", SavedDB())
        local showCL = optionState.showClassificationPreview or optionState._sliderDragShowClassification
        classIcon:SetSize(reIconSz, reIconSz)
        -- Both halves off (the WoW Forever look's seed can leave that when the
        -- Quest Indicator was already off, and the Quest Objective Text can take
        -- the Quest Indicator's place): live plates draw nothing there.
        if clPos == "none" or not showCL or (hideRare and not mod.NP_QuestIconOn(SavedDB())) then
            classIcon:Hide()
            if popFrame._classOverlay then
                popFrame._classOverlay:Hide()
            end
        else
            if clPos == "top" then
                classIcon:SetPoint("BOTTOM", healthBar, "TOP", clXOff, debuffY + cpPush + clYOff)
            elseif clPos == "left" then
                local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                classIcon:SetPoint(
                    "RIGHT",
                    healthBar,
                    "LEFT",
                    -sideOff - castIconLeftPush - FullPush("left", clYOff, reIconSz) + clXOff,
                    clYOff
                )
            elseif clPos == "right" then
                local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                classIcon:SetPoint(
                    "LEFT",
                    healthBar,
                    "RIGHT",
                    sideOff + castIconRightPush + FullPush("right", clYOff, reIconSz) + clXOff,
                    clYOff
                )
            elseif clPos == "topleft" then
                classIcon:SetPoint(
                    "BOTTOMLEFT",
                    healthBar,
                    "TOPLEFT",
                    clXOff,
                    2 + cpPush + mod.NP_TopCornerLift("topleft", SavedDB()) + clYOff
                )
            elseif clPos == "topright" then
                classIcon:SetPoint(
                    "BOTTOMRIGHT",
                    healthBar,
                    "TOPRIGHT",
                    clXOff,
                    2 + cpPush + mod.NP_TopCornerLift("topright", SavedDB()) + clYOff
                )
            elseif clPos == "bottom" then
                classIcon:SetPoint("TOP", cast, "BOTTOM", clXOff, -2 + clYOff)
            end
            -- The quest mark while the Elite/Rare Indicator is off.
            if hideRare then
                classIcon:SetAtlas("Crosshair_Quest_64")
            else
                classIcon:SetTexture("Interface\\AddOns\\CludesUI\\media\\elite-rare-indicator.png")
                classIcon:SetTexCoord(0, 1, 0, 1)
            end
            classIcon:Show()
            if popFrame._classOverlay then
                popFrame._classOverlay:Show()
            end
        end

        -- Faction badge, slot-based like the classification icon above. Shows the
        -- other faction's badge (what Opposite Faction Only would show).
        local fcCombined = DBVal("classificationIncludeFaction") == true
        local fcPos = fcCombined and clPos or (DBVal("factionSlot") or defaultSet.factionSlot or "none")
        local factionTopExtent = 0 -- height above the health bar, read by the height calculation
        factionIcon:ClearAllPoints()
        if fcPos == "none" then
            factionIcon:Hide()
            if popFrame._factionOverlay then
                popFrame._factionOverlay:Hide()
            end
        else
            local fcX = DBVal(fcPos .. "SlotXOffset") or 0
            local fcY = DBVal(fcPos .. "SlotYOffset") or 0
            local fcSz = mod.NP_ElementSize("faction", SavedDB())
            -- Sharing the slot with a showing Rare/Quest icon: stack behind it,
            -- overlapping by 40%, up or down in the Bottom slot (matches
            -- NameplateFrame:UpdateFaction).
            if fcCombined and classIcon:IsShown() then
                local step = math.floor(reIconSz * 0.6 + 0.5)
                fcY = fcY + ((fcPos == "bottom") and -step or step)
            end
            local mine = UnitFactionGroup("player")
            local fac = (mine == "Horde") and "Alliance" or "Horde"
            local fStyle = DBVal("factionStyle") or defaultSet.factionStyle
            CludesUI.SetFactionArt(factionIcon, fStyle, fac, CludesUI.FactionBadgeFor(fStyle, "player"))
            factionIcon:SetSize(fcSz, fcSz)
            if fcPos == "top" then
                factionTopExtent = debuffY + fcSz + fcY
            elseif fcPos == "topleft" or fcPos == "topright" then
                factionTopExtent = 2 + fcSz + mod.NP_TopCornerLift(fcPos, SavedDB()) + fcY
            end
            if fcPos == "top" then
                factionIcon:SetPoint("BOTTOM", healthBar, "TOP", fcX, debuffY + cpPush + fcY)
            elseif fcPos == "left" then
                local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                factionIcon:SetPoint(
                    "RIGHT",
                    healthBar,
                    "LEFT",
                    -sideOff - castIconLeftPush - FullPush("left", fcY, fcSz) + fcX,
                    fcY
                )
            elseif fcPos == "right" then
                local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                factionIcon:SetPoint(
                    "LEFT",
                    healthBar,
                    "RIGHT",
                    sideOff + castIconRightPush + FullPush("right", fcY, fcSz) + fcX,
                    fcY
                )
            elseif fcPos == "topleft" then
                factionIcon:SetPoint(
                    "BOTTOMLEFT",
                    healthBar,
                    "TOPLEFT",
                    fcX,
                    2 + cpPush + mod.NP_TopCornerLift("topleft", SavedDB()) + fcY
                )
            elseif fcPos == "topright" then
                factionIcon:SetPoint(
                    "BOTTOMRIGHT",
                    healthBar,
                    "TOPRIGHT",
                    fcX,
                    2 + cpPush + mod.NP_TopCornerLift("topright", SavedDB()) + fcY
                )
            elseif fcPos == "bottom" then
                factionIcon:SetPoint("TOP", cast, "BOTTOM", fcX, -2 + fcY)
            end
            factionIcon:Show()
            if popFrame._factionOverlay then
                popFrame._factionOverlay:Show()
            end
        end

        -- Quest Objective Text sample, placed like the Rare/Quest icon above (its
        -- hit overlay is the frame's child, so it shows and hides with it). The
        -- name width, chain, arrow and height passes below read pf._qt.
        do
            local qt = popFrame._qt
            local f = qt.frame
            local place = mod.NP_GetQuestTextSlot(SavedDB())
            qt.pos = place
            f:ClearAllPoints()
            if place == "none" or not optionState.showQuestTextPreview then
                qt.shown = false
                f:Hide()
                if qt.icon then
                    qt.icon:Hide()
                end
            else
                local posX = DBVal(place .. "SlotXOffset") or 0
                local posY = DBVal(place .. "SlotYOffset") or 0
                local fontStr = qt.fs
                local textSize = mod.NP_QuestTextSize(SavedDB())
                SetPVFont(fontStr, fontFile, textSize, npOutline)
                local counterW = math.max(math.ceil(fontStr:GetStringWidth() or 0), 1)
                local counterH = math.max(math.ceil(fontStr:GetStringHeight() or 0), 1)
                local wid, hgt = counterW, counterH
                if DBVal("showQuestObjectiveTypeIcon") == true then
                    local scale = DBVal("questObjectiveTypeIconScale") or 100
                    local textX, iconX, iconSize
                    wid, hgt, textX, iconX, iconSize =
                        mod.NP_QuestTypeIconLayout(counterW, counterH, textSize, scale)
                    local glyph = qt.icon
                    if not glyph then
                        glyph = f:CreateTexture(nil, "ARTWORK")
                        glyph:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")
                        qt.icon = glyph
                    end
                    fontStr:ClearAllPoints()
                    fontStr:SetPoint("CENTER", f, "CENTER", textX, 0)
                    glyph:ClearAllPoints()
                    glyph:SetSize(iconSize, iconSize)
                    glyph:SetPoint("LEFT", f, "CENTER", iconX, 0)
                    glyph:Show()
                    qt.iconLayoutOn = true
                else
                    if qt.iconLayoutOn then
                        fontStr:ClearAllPoints()
                        fontStr:SetPoint("CENTER", f, "CENTER", 0, 0)
                        qt.iconLayoutOn = nil
                    end
                    if qt.icon and qt.icon:IsShown() then
                        qt.icon:Hide()
                    end
                end
                f:SetSize(wid, hgt)
                if place == "top" then
                    f:SetPoint("BOTTOM", healthBar, "TOP", posX, debuffY + cpPush + posY)
                elseif place == "left" then
                    local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                    f:SetPoint(
                        "RIGHT",
                        healthBar,
                        "LEFT",
                        -sideOff - castIconLeftPush - FullPush("left", posY, hgt) + posX,
                        posY
                    )
                elseif place == "right" then
                    local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
                    f:SetPoint(
                        "LEFT",
                        healthBar,
                        "RIGHT",
                        sideOff + castIconRightPush + FullPush("right", posY, hgt) + posX,
                        posY
                    )
                elseif place == "topleft" then
                    f:SetPoint(
                        "BOTTOMLEFT",
                        healthBar,
                        "TOPLEFT",
                        posX,
                        2 + cpPush + mod.NP_TopCornerLift("topleft", SavedDB()) + posY
                    )
                elseif place == "topright" then
                    f:SetPoint(
                        "BOTTOMRIGHT",
                        healthBar,
                        "TOPRIGHT",
                        posX,
                        2 + cpPush + mod.NP_TopCornerLift("topright", SavedDB()) + posY
                    )
                elseif place == "bottom" then
                    f:SetPoint("TOP", cast, "BOTTOM", posX, -2 + posY)
                end
                qt.x, qt.y, qt.w, qt.h, qt.shown = posX, posY, wid, hgt, true
                f:Show()
            end
        end

        -- Arrow positioning happens after all auras are placed (arrows sit OUTSIDE the auras).

        -- Cast bar spans the health bar width. With "Make Icon Part of the Bar" it shrinks + shifts right so the icon (anchored to its left edge) sits inside the width; otherwise the icon hangs outside.
        local pIconW = 0
        local pShiftX = 0
        local pCastW = barW
        local pCastY = (DBVal("castBarOffsetY") or defaultSet.castBarOffsetY)
        if previewGlow.classic and mod.NP_ClassicCastLayout then
            -- Classic WoW UI, as live (ns.LayoutCastBar): the vanilla cast border
            -- hangs under the health border, plate under plain end, the stock gap lower.
            local drop
            pShiftX, pCastW, drop = mod.NP_ClassicCastLayout(barW, barH, castH)
            pCastY = pCastY + drop
        elseif showIcon and iconInWidth and not fullSize then
            pIconW = castH * iconScale
            if not onRight then
                pShiftX = pIconW
            end
        end
        cast:ClearAllPoints()
        cast:SetSize(math.max(1, pCastW - pIconW), castH)
        cast:SetPoint("TOPLEFT", healthBar, "BOTTOMLEFT", pShiftX, pCastY)
        do
            local cTexKey = DBVal("castBarTexture") or "none"
            local cTexPath =
                CludesUI.ResolveTexturePath(mod.healthBarTextures, cTexKey, "Interface\\Buttons\\WHITE8x8")
            cast:SetStatusBarTexture(cTexPath)
            UnsnapTex(cast:GetStatusBarTexture())
        end
        cast:SetStatusBarColor(cbColor.r, cbColor.g, cbColor.b, 1)
        -- Cast icon: size/anchor per side or full-size; SetSize (not SetScale) keeps AddBorder pixel-perfect. Full-size pins to the cast bottom so the square reaches the health top (zero-gap bar stack).
        castParts.iconFrame:ClearAllPoints()
        castParts.iconFrame:SetScale(1)
        if showIcon and previewGlow.classic and mod.NP_ClassicIconOffset then
            -- Classic WoW UI, as live (ns.LayoutCastIcon): the icon in the
            -- vanilla cast border's plate.
            local C = mod.NP_CLASSIC
            local ix, iy = mod.NP_ClassicIconOffset(castH)
            castParts.iconFrame:SetSize(C.icon * castH, C.icon * castH)
            castParts.iconFrame:SetPoint("CENTER", cast, "LEFT", ix + iconXOff, iy + iconYOff)
            castParts.iconFrame:Show()
        elseif showIcon then
            if fullSize then
                local fontStr = barH + castH
                castParts.iconFrame:SetSize(fontStr, fontStr)
                if onRight then
                    castParts.iconFrame:SetPoint("BOTTOMLEFT", cast, "BOTTOMRIGHT", iconXOff, iconYOff)
                else
                    castParts.iconFrame:SetPoint("BOTTOMRIGHT", cast, "BOTTOMLEFT", iconXOff, iconYOff)
                end
            else
                local scaledH = castH * iconScale
                castParts.iconFrame:SetSize(scaledH, scaledH)
                if onRight then
                    castParts.iconFrame:SetPoint("TOPLEFT", cast, "TOPRIGHT", iconXOff, iconYOff)
                else
                    castParts.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", iconXOff, iconYOff)
                end
            end
            castParts.iconFrame:Show()
        else
            castParts.iconFrame:SetSize(castH, castH)
            castParts.iconFrame:SetPoint("TOPRIGHT", cast, "TOPLEFT", 0, 0)
            castParts.iconFrame:Hide()
        end
        -- Custom icon borders (Icon Borders cog), over the 1px edges and insets set above.
        previewGlow.iconBorders(customOn, showIcon)
        -- The classic spark is a square sized by applyClassic below.
        if not previewGlow.classic then
            castParts.spark:SetHeight(castH)
        end
        -- Show Spark (Cast Color cog): default on; explicit false hides it.
        castParts.spark:SetShown(DBVal("castBarSparkEnabled") ~= false)

        -- Name font + color + position (font size set per-slot below)
        local nameYOff = DBVal("nameYOffset") or defaultSet.nameYOffset

        -- Slot-based text positioning Read slot assignments
        local slotTop = DBVal("textSlotTop") or defaultSet.textSlotTop
        local slotRight = DBVal("textSlotRight") or defaultSet.textSlotRight
        local slotLeft = DBVal("textSlotLeft") or defaultSet.textSlotLeft
        local slotCenter = DBVal("textSlotCenter") or defaultSet.textSlotCenter
        local slotBL = DBVal("textSlotBottomLeft") or defaultSet.textSlotBottomLeft
        local slotBR = DBVal("textSlotBottomRight") or defaultSet.textSlotBottomRight

        -- Hide all text elements first
        nameFS:Hide()
        hpText:Hide()
        hpNumber:Hide()
        lvlText:Hide()
        popFrame._totFS:Hide()
        nameFS:ClearAllPoints()
        hpText:ClearAllPoints()
        hpNumber:ClearAllPoints()
        lvlText:ClearAllPoints()
        popFrame._totFS:ClearAllPoints()
        for _, fontStr in pairs(popFrame._customFS) do
            fontStr:Hide()
            fontStr:ClearAllPoints()
        end

        -- Helper: position a health-related element in a bar slot
        local function PlaceHealthInBar(element, anchor, point, xOff, yOff, fontSize, cr, cg, cb, slotKey)
            yOff = yOff or 0
            local namesUnit
            local dec = slotKey and DBVal(slotKey .. "PctDecimal") == true
            if element == "healthPercent" or element == "healthPercentNoSign" then
                SetPVFont(hpText, fontFile, fontSize, npOutline)
                hpText:SetParent(healthTextFrame)
                hpText:SetText(
                    element == "healthPercentNoSign" and (dec and pctNoSignStrDec or pctNoSignStr)
                        or (dec and pctStrDec or pctStr)
                )
                hpText:SetPoint(point, healthBar, anchor, xOff, yOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "healthNumber" then
                SetPVFont(hpNumber, fontFile, fontSize, npOutline)
                hpNumber:SetParent(healthTextFrame)
                hpNumber:SetText(hpNumStr)
                hpNumber:SetPoint(point, healthBar, anchor, xOff, yOff)
                hpNumber:SetTextColor(cr, cg, cb, 1)
                hpNumber:Show()
            elseif mod.IsComboHealthText(element) then
                SetPVFont(hpText, fontFile, fontSize, npOutline)
                hpText:SetParent(healthTextFrame)
                mod.SetCombinedHealthText(hpText, element, dec and pctStrDec or pctStr, hpNumStr, hpMaxStr)
                hpText:SetPoint(point, healthBar, anchor, xOff, yOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "level" or element == "targetOfTarget" then
                local fontStr = (element == "level") and lvlText or popFrame._totFS
                if fontStr ~= lvlText then
                    cr, cg, cb = popFrame._totSampleColor(slotKey, cr, cg, cb)
                end
                SetPVFont(fontStr, fontFile, fontSize, npOutline)
                if fontStr ~= lvlText then
                    fontStr:SetText(popFrame._totSample(slotKey))
                end
                fontStr:SetParent(healthTextFrame)
                fontStr:SetPoint(point, healthBar, anchor, xOff, yOff)
                fontStr:SetTextColor(cr, cg, cb, 1)
                fontStr:Show()
            elseif element == "custom" then
                local fontStr = popFrame._customFS[slotKey]
                SetPVFont(fontStr, fontFile, fontSize, npOutline)
                fontStr:SetParent(healthTextFrame)
                namesUnit = popFrame._pvCustom(fontStr, slotKey)
                fontStr:SetPoint(point, healthBar, anchor, xOff, yOff)
                fontStr:SetTextColor(cr, cg, cb, 1)
                fontStr:Show()
            end
            -- Per-slot Width % + Wrap mirrors runtime. At 100% (default) the FontString stays UNCONSTRAINED (SetWidth 0): a width box on a single-point-anchored FontString ignores SetJustifyH and drifts to centre, so only impose one below 100%.
            local hfs = (element == "custom") and popFrame._customFS[slotKey]
                or (element == "healthNumber") and hpNumber
                or (element == "level") and lvlText
                or (element == "targetOfTarget") and popFrame._totFS
                or hpText
            -- Corner slots anchor by a corner of their own; justify by its side.
            hfs:SetJustifyH(
                ((point == "TOPLEFT" or point == "BOTTOMLEFT") and "LEFT")
                    or ((point == "TOPRIGHT" or point == "BOTTOMRIGHT") and "RIGHT")
                    or point
            )
            -- The corner slots never truncate (no Width % or Wrap), as live.
            local noClip = slotKey == "textSlotBottomLeft"
                or slotKey == "textSlotBottomRight"
                or slotKey == "textSlotTopLeft"
                or slotKey == "textSlotTopRight"
            local hwpct = (not noClip and slotKey and DBVal(slotKey .. "WidthPct")) or 100
            local hw = 0
            if namesUnit and not noClip then
                -- The bar left by the other bar texts (live: NP_BarRestWidth).
                hw = math.max(
                    (barW - mod.GetHealthBarWidth() + mod.NP_BarRestWidth(slotKey, SavedDB())) * hwpct / 100,
                    20
                )
            elseif hwpct < 100 then
                hw = barW * hwpct / 100
            end
            hfs:SetWidth(hw)
            local hwrap = false
            if not noClip and slotKey and DBVal(slotKey .. "Wrap") == true then
                hwrap = true
            end
            hfs:SetWordWrap(hwrap)
            hfs:SetMaxLines(hwrap and 2 or 1)
            if element == "custom" and hw > 0 then
                mod.ReflowFontString(hfs)
            end
        end

        -- Helper: position a health-related element in the top slot
        local function PlaceHealthOnTop(element, txOff, tyOff, fontSize, cr, cg, cb, slotKey)
            txOff = txOff or 0
            tyOff = tyOff or 0
            local namesUnit
            local dec = slotKey and DBVal(slotKey .. "PctDecimal") == true
            if element == "healthPercent" or element == "healthPercentNoSign" then
                SetPVFont(hpText, fontFile, fontSize, npOutline)
                hpText:SetText(
                    element == "healthPercentNoSign" and (dec and pctNoSignStrDec or pctNoSignStr)
                        or (dec and pctStrDec or pctStr)
                )
                hpText:SetParent(topTextFrame)
                hpText:SetPoint("BOTTOM", healthBar, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "healthNumber" then
                SetPVFont(hpNumber, fontFile, fontSize, npOutline)
                hpNumber:SetText(hpNumStr)
                hpNumber:SetParent(topTextFrame)
                hpNumber:SetPoint("BOTTOM", healthBar, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                hpNumber:SetTextColor(cr, cg, cb, 1)
                hpNumber:Show()
            elseif mod.IsComboHealthText(element) then
                SetPVFont(hpText, fontFile, fontSize, npOutline)
                mod.SetCombinedHealthText(hpText, element, dec and pctStrDec or pctStr, hpNumStr, hpMaxStr)
                hpText:SetParent(topTextFrame)
                hpText:SetPoint("BOTTOM", healthBar, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                hpText:SetTextColor(cr, cg, cb, 1)
                hpText:Show()
            elseif element == "level" or element == "targetOfTarget" then
                local fontStr = (element == "level") and lvlText or popFrame._totFS
                if fontStr ~= lvlText then
                    cr, cg, cb = popFrame._totSampleColor(slotKey, cr, cg, cb)
                end
                SetPVFont(fontStr, fontFile, fontSize, npOutline)
                if fontStr ~= lvlText then
                    fontStr:SetText(popFrame._totSample(slotKey))
                end
                fontStr:SetParent(topTextFrame)
                fontStr:SetPoint("BOTTOM", healthBar, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                fontStr:SetTextColor(cr, cg, cb, 1)
                fontStr:Show()
            elseif element == "custom" then
                local fontStr = popFrame._customFS[slotKey]
                SetPVFont(fontStr, fontFile, fontSize, npOutline)
                namesUnit = popFrame._pvCustom(fontStr, slotKey)
                fontStr:SetParent(topTextFrame)
                fontStr:SetPoint("BOTTOM", healthBar, "TOP", txOff, 4 + nameYOff + cpPush + tyOff)
                fontStr:SetTextColor(cr, cg, cb, 1)
                fontStr:Show()
            end
            -- Per-slot Width % + Wrap mirrors runtime. Top slot is centered and stays unconstrained at 100% (see PlaceHealthInBar for why a width box mis-positions the text).
            local hfs = (element == "custom") and popFrame._customFS[slotKey]
                or (element == "healthNumber") and hpNumber
                or (element == "level") and lvlText
                or (element == "targetOfTarget") and popFrame._totFS
                or hpText
            hfs:SetJustifyH("CENTER")
            local hwpct = (slotKey and DBVal(slotKey .. "WidthPct")) or 100
            local hw = 0
            if namesUnit then
                -- Centred between the Top Left / Top Right texts, as live.
                hw = math.max(
                    (
                        barW
                        - 2
                            * math.max(
                                mod.NP_TopCornerTextWidth("textSlotTopLeft", SavedDB()),
                                mod.NP_TopCornerTextWidth("textSlotTopRight", SavedDB())
                            )
                    )
                        * hwpct
                        / 100,
                    20
                )
            elseif hwpct < 100 then
                hw = barW * hwpct / 100
            end
            hfs:SetWidth(hw)
            local hwrap = false
            if slotKey and DBVal(slotKey .. "Wrap") == true then
                hwrap = true
            end
            hfs:SetWordWrap(hwrap)
            hfs:SetMaxLines(hwrap and 2 or 1)
        end

        -- Enemy name truncation mirrors runtime (width % of bar-derived width + wrap toggle), applied to the shared preview name FontString.
        local pvNameWPct = DBVal("enemyNameWidthPct") or defaultSet.enemyNameWidthPct
        local pvNameWrap = DBVal("enemyNameWrap") == true
        nameFS:SetWordWrap(pvNameWrap)
        nameFS:SetNonSpaceWrap(false)
        nameFS:SetMaxLines(pvNameWrap and 2 or 1)
        local pvNameMarkerEnabled = DBVal("nameRaidMarkerEnabled") == true
        local pvNameMarkerSize = DBVal("nameRaidMarkerSize") or defaultSet.nameRaidMarkerSize or 14
        local pvNameMarkerReserve = pvNameMarkerEnabled and (pvNameMarkerSize + NAME_RAID_MARKER_GAP) or 0
        local pvNameSlotKey

        local function LayoutPreviewNameRaidMarker()
            if not (pvNameMarkerEnabled and pvNameSlotKey and nameFS:IsShown()) then
                nameRaidFrame:Hide()
                return
            end
            nameRaidFrame:SetParent((pvNameSlotKey == "textSlotTop") and topTextFrame or healthTextFrame)
            nameRaidFrame:SetFrameLevel(healthBar:GetFrameLevel() + 12)
            nameRaidFrame:SetSize(pvNameMarkerSize, pvNameMarkerSize)
            nameRaidFrame:ClearAllPoints()
            nameRaidFrame:SetPoint("RIGHT", nameFS, "LEFT", -NAME_RAID_MARKER_GAP, 0)
            if SetRaidTargetIconTexture then
                SetRaidTargetIconTexture(nameRaidIcon, 1)
            end
            nameRaidFrame:Show()
        end

        -- Helper: position the name in a bar slot
        local function PlaceNameInBar(
            anchor,
            point,
            xOff,
            justify,
            txOff,
            tyOff,
            fontSize,
            cr,
            cg,
            cb,
            nameSlotKey
        )
            txOff = txOff or 0
            tyOff = tyOff or 0
            pvNameSlotKey = nameSlotKey
            local markerShift = 0
            if pvNameMarkerEnabled then
                markerShift = (justify == "LEFT") and pvNameMarkerReserve
                    or ((justify == "CENTER") and (pvNameMarkerReserve * 0.5) or 0)
            end
            SetPVFont(nameFS, fontFile, fontSize, npOutline)
            nameFS:SetParent(healthTextFrame)
            nameFS:SetPoint(point, healthBar, anchor, xOff + txOff + markerShift, tyOff)
            nameFS:SetJustifyH(justify)
            if
                nameSlotKey == "textSlotBottomLeft"
                or nameSlotKey == "textSlotBottomRight"
                or nameSlotKey == "textSlotTopLeft"
                or nameSlotKey == "textSlotTopRight"
            then
                -- On a corner of the bar the name never truncates (no width box, one line), as live.
                nameFS:SetWidth(0)
                nameFS:SetWordWrap(false)
                nameFS:SetMaxLines(1)
            else
                -- Estimate health text width in opposing bar slots
                local usedWidth = 0
                local barSlotInfo = {
                    { key = "textSlotRight", slot = slotRight },
                    { key = "textSlotLeft", slot = slotLeft },
                    { key = "textSlotCenter", slot = slotCenter },
                }
                for _, details in ipairs(barSlotInfo) do
                    if details.key ~= nameSlotKey then
                        local el = details.slot
                        if el == "custom" then
                            usedWidth = usedWidth + mod.NP_CustomWidth(details.key, SavedDB())
                        elseif el ~= "none" and not mod.IsNameElement(el) then
                            usedWidth = usedWidth + mod.EstimateHealthTextWidth(el)
                        end
                    end
                end
                nameFS:SetWidth(math.max((barW - usedWidth - pvNameMarkerReserve) * pvNameWPct / 100, 20))
            end
            nameFS:SetTextColor(cr, cg, cb, 1)
            nameFS:Show()
        end

        -- Process top slot
        local topXOff = DBVal("textSlotTopXOffset") or 0
        local topYOff = DBVal("textSlotTopYOffset") or 0
        local topFontSz = DBVal("textSlotTopSize") or defaultSet.textSlotTopSize
        local topC = previewGlow.slotColor("textSlotTop")
        if mod.IsNameElement(slotTop) then
            pvNameSlotKey = "textSlotTop"
            SetPVFont(nameFS, fontFile, topFontSz, npOutline)
            nameFS:SetParent(topTextFrame)
            nameFS:SetPoint(
                "BOTTOM",
                healthBar,
                "TOP",
                topXOff + (pvNameMarkerReserve * 0.5),
                4 + nameYOff + cpPush + topYOff
            )
            nameFS:SetJustifyH("CENTER")
            -- Centred between the Top Left / Top Right texts, as live.
            local nameW = barW
                - pvNameMarkerReserve
                - 2
                    * math.max(
                        mod.NP_TopCornerTextWidth("textSlotTopLeft", SavedDB()),
                        mod.NP_TopCornerTextWidth("textSlotTopRight", SavedDB())
                    )
            if rmPos ~= "none" and showRM then
                nameW = nameW - 2 * (rmSize - 2) - 7
            end
            if showCL and clPos ~= "none" then
                nameW = nameW - (reIconSz + 4)
            end
            -- The Quest Objective Text takes its own width, like the Rare/Quest icon.
            if popFrame._qt.shown then
                nameW = nameW - (popFrame._qt.w + 4)
            end
            nameFS:SetWidth(math.max(nameW * pvNameWPct / 100, 20))
            nameFS:SetTextColor(topC.r, topC.g, topC.b, 1)
            nameFS:Show()
        else
            PlaceHealthOnTop(slotTop, topXOff, topYOff, topFontSz, topC.r, topC.g, topC.b, "textSlotTop")
        end

        -- Process right slot
        local rightXOff = DBVal("textSlotRightXOffset") or 0
        local rightYOff = DBVal("textSlotRightYOffset") or 0
        local rightFontSz = DBVal("textSlotRightSize") or defaultSet.textSlotRightSize
        local rightC = previewGlow.slotColor("textSlotRight")
        if mod.IsNameElement(slotRight) then
            PlaceNameInBar(
                "RIGHT",
                "RIGHT",
                -2,
                "RIGHT",
                rightXOff,
                rightYOff,
                rightFontSz,
                rightC.r,
                rightC.g,
                rightC.b,
                "textSlotRight"
            )
        else
            PlaceHealthInBar(
                slotRight,
                "RIGHT",
                "RIGHT",
                -2 + rightXOff,
                rightYOff,
                rightFontSz,
                rightC.r,
                rightC.g,
                rightC.b,
                "textSlotRight"
            )
        end

        -- Process left slot
        local leftXOff = DBVal("textSlotLeftXOffset") or 0
        local leftYOff = DBVal("textSlotLeftYOffset") or 0
        local leftFontSz = DBVal("textSlotLeftSize") or defaultSet.textSlotLeftSize
        local leftC = previewGlow.slotColor("textSlotLeft")
        if mod.IsNameElement(slotLeft) then
            PlaceNameInBar(
                "LEFT",
                "LEFT",
                4,
                "LEFT",
                leftXOff,
                leftYOff,
                leftFontSz,
                leftC.r,
                leftC.g,
                leftC.b,
                "textSlotLeft"
            )
        else
            PlaceHealthInBar(
                slotLeft,
                "LEFT",
                "LEFT",
                4 + leftXOff,
                leftYOff,
                leftFontSz,
                leftC.r,
                leftC.g,
                leftC.b,
                "textSlotLeft"
            )
        end

        -- Process center slot
        local centerXOff = DBVal("textSlotCenterXOffset") or 0
        local centerYOff = DBVal("textSlotCenterYOffset") or 0
        local centerFontSz = DBVal("textSlotCenterSize") or defaultSet.textSlotCenterSize
        local centerC = previewGlow.slotColor("textSlotCenter")
        if mod.IsNameElement(slotCenter) then
            PlaceNameInBar(
                "CENTER",
                "CENTER",
                0,
                "CENTER",
                centerXOff,
                centerYOff,
                centerFontSz,
                centerC.r,
                centerC.g,
                centerC.b,
                "textSlotCenter"
            )
        else
            PlaceHealthInBar(
                slotCenter,
                "CENTER",
                "CENTER",
                centerXOff,
                centerYOff,
                centerFontSz,
                centerC.r,
                centerC.g,
                centerC.b,
                "textSlotCenter"
            )
        end

        -- Process the bottom slots: under the health bar's corners, below the
        -- cast bar (the preview always shows one), as live while casting.
        do
            -- Clamped at 0 like live: a raised cast bar never lifts them.
            local by = math.min(0, pCastY - castH) - 2
            local ext = 0
            for i = 1, 2 do
                local key = (i == 1) and "textSlotBottomLeft" or "textSlotBottomRight"
                local el = (i == 1) and slotBL or slotBR
                local corner = (i == 1) and "LEFT" or "RIGHT"
                local c = previewGlow.slotColor(key)
                local sz = DBVal(key .. "Size") or defaultSet[key .. "Size"]
                local bx, byo = DBVal(key .. "XOffset") or 0, by + (DBVal(key .. "YOffset") or 0)
                if mod.IsNameElement(el) then
                    PlaceNameInBar(
                        "BOTTOM" .. corner,
                        "TOP" .. corner,
                        0,
                        corner,
                        bx,
                        byo,
                        sz,
                        c.r,
                        c.g,
                        c.b,
                        key
                    )
                elseif el ~= "none" then
                    PlaceHealthInBar(el, "BOTTOM" .. corner, "TOP" .. corner, bx, byo, sz, c.r, c.g, c.b, key)
                end
                if el ~= "none" then
                    ext = math.max(ext, sz + 2 - (DBVal(key .. "YOffset") or 0))
                end
            end
            -- Read by the preview height below (a table field: no new pf.Update local).
            previewGlow.botTextH = ext
        end
        -- Process the top corner slots: over the health bar's top corners at the Top
        -- text's height, above the class power pips while the preview shows them, as live.
        do
            for i = 1, 2 do
                local key = (i == 1) and "textSlotTopLeft" or "textSlotTopRight"
                local el = DBVal(key) or defaultSet[key]
                local corner = (i == 1) and "LEFT" or "RIGHT"
                local c = previewGlow.slotColor(key)
                local sz = DBVal(key .. "Size") or defaultSet[key .. "Size"]
                local tx = DBVal(key .. "XOffset") or 0
                local ty = 4 + nameYOff + cpPush + (DBVal(key .. "YOffset") or 0)
                if mod.IsNameElement(el) then
                    PlaceNameInBar(
                        "TOP" .. corner,
                        "BOTTOM" .. corner,
                        0,
                        corner,
                        tx,
                        ty,
                        sz,
                        c.r,
                        c.g,
                        c.b,
                        key
                    )
                elseif el ~= "none" then
                    PlaceHealthInBar(el, "TOP" .. corner, "BOTTOM" .. corner, tx, ty, sz, c.r, c.g, c.b, key)
                end
            end
        end
        -- Preview sample for whichever name-family variant is slotted (player level stands in for mob level), run after slot branches so text re-flows under the new justify (SetJustifyH alone won't re-flow it). The name slot's key carries its Level | Name part colours.
        mod.SetNameElementText(
            nameFS,
            (mod.IsNameElement(slotTop) and slotTop)
                or (mod.IsNameElement(slotRight) and slotRight)
                or (mod.IsNameElement(slotLeft) and slotLeft)
                or (mod.IsNameElement(slotCenter) and slotCenter)
                or (mod.IsNameElement(slotBL) and slotBL)
                or (mod.IsNameElement(slotBR) and slotBR)
                or (mod.IsNameElement(DBVal("textSlotTopLeft")) and DBVal("textSlotTopLeft"))
                or (mod.IsNameElement(DBVal("textSlotTopRight")) and DBVal("textSlotTopRight"))
                or "enemyName",
            -- The slot's Name Format, as live.
            mod.NP_FormatName(CludesUI.L("Enemy Name Text"), pvNameSlotKey),
            "player",
            pvNameSlotKey
        )
        mod.ReflowFontString(nameFS)
        if DBVal("hideEnemyNameWhileCasting") == true then
            nameFS:Hide()
        end
        LayoutPreviewNameRaidMarker()
        PreviewNameStrata(
            popFrame,
            healthBar,
            nameFS,
            nameRaidFrame,
            pvNameSlotKey and DBVal(pvNameSlotKey .. "Strata") or "MEDIUM"
        )

        -- Health bar color: always uses "enemies in combat" color
        local eic = (SavedDB() and SavedDB().enemyInCombat) or defaultSet.enemyInCombat
        healthBar:SetStatusBarColor(eic.r, eic.g, eic.b, 1)

        -- Cast text sizes, colors, and offsets
        local cns = DBVal("castNameSize") or defaultSet.castNameSize
        local cts = DBVal("castTargetSize") or defaultSet.castTargetSize
        local cnc = (SavedDB() and SavedDB().castNameColor) or defaultSet.castNameColor
        local ctmSz = DBVal("castTimerSize") or defaultSet.castTimerSize
        local ctmC = (SavedDB() and SavedDB().castTimerColor) or defaultSet.castTimerColor
        local cnOX = DBVal("castNameOffsetX") or defaultSet.castNameOffsetX
        local cnOY = DBVal("castNameOffsetY") or defaultSet.castNameOffsetY
        local ctOX = DBVal("castTargetOffsetX") or defaultSet.castTargetOffsetX
        local ctOY = DBVal("castTargetOffsetY") or defaultSet.castTargetOffsetY
        local tmOX = DBVal("castTimerOffsetX") or defaultSet.castTimerOffsetX
        local tmOY = DBVal("castTimerOffsetY") or defaultSet.castTimerOffsetY
        SetPVFont(castParts.nameFS, fontFile, cns, npOutline)
        SetPVFont(castParts.targetFS, fontFile, cts, npOutline)
        SetPVFont(castParts.timerFS, fontFile, ctmSz, npOutline)
        castParts.timerFS:SetTextColor(ctmC.r, ctmC.g, ctmC.b, 1)
        castParts.nameFS:SetTextColor(cnc.r, cnc.g, cnc.b, 1)
        local dbRef = SavedDB()
        local pvShowTimer = defaultSet.showCastTimer
        if dbRef and dbRef.showCastTimer ~= nil then
            pvShowTimer = dbRef.showCastTimer
        end
        local pvNameSide = (dbRef and dbRef.castNameSide) or defaultSet.castNameSide
        local pvTargetSide = (dbRef and dbRef.castTargetSide) or defaultSet.castTargetSide
        local pvTimerSide = (dbRef and dbRef.castTimerSide) or defaultSet.castTimerSide
        local pvCombine = dbRef and dbRef.castCombineNameTarget == true
        local pvTimerW = ctmSz * 2.2
        -- Per-element cast text truncation (% of cast bar width + wrap), mirroring runtime.
        local pvNameTextW = barW * (DBVal("castNameWidthPct") or defaultSet.castNameWidthPct) / 100
        local pvTgtTextW = barW * (DBVal("castTargetWidthPct") or defaultSet.castTargetWidthPct) / 100
        local pvCNameWrap = DBVal("castNameWrap") == true
        local pvCTgtWrap = DBVal("castTargetWrap") == true
        castParts.nameFS:SetWordWrap(pvCNameWrap)
        castParts.nameFS:SetMaxLines(pvCNameWrap and 2 or 1)
        castParts.targetFS:SetWordWrap(pvCTgtWrap)
        castParts.targetFS:SetNonSpaceWrap(false)
        castParts.targetFS:SetMaxLines(pvCTgtWrap and 2 or 1)
        -- Spell name
        castParts.nameFS:ClearAllPoints()
        if pvNameSide == "none" then
            castParts.nameFS:Hide()
        else
            local pt, xb, jh =
                mod.GetCastTextAnchor(pvNameSide, pvShowTimer and pvTimerSide == pvNameSide, pvTimerW, false)
            castParts.nameFS:SetWidth(
                pvCombine
                        and (barW * (DBVal("castCombinedWidthPct") or defaultSet.castCombinedWidthPct) / 100)
                    or pvNameTextW
            )
            castParts.nameFS:SetJustifyH(jh)
            castParts.nameFS:SetPoint(pt, cast, pt, xb + cnOX, cnOY)
            castParts.nameFS:Show()
        end
        -- Spell target
        castParts.targetFS:ClearAllPoints()
        if pvCombine or pvTargetSide == "none" then
            castParts.targetFS:Hide()
        else
            local pt, xb, jh = mod.GetCastTextAnchor(
                pvTargetSide,
                pvShowTimer and pvTimerSide == pvTargetSide,
                pvTimerW,
                false
            )
            castParts.targetFS:SetWidth(pvTgtTextW)
            castParts.targetFS:SetJustifyH(jh)
            castParts.targetFS:SetPoint(pt, cast, pt, xb + ctOX, ctOY)
            castParts.targetFS:Show()
        end
        -- Cast timer (side only "left"/"right"; visibility via showCastTimer)
        castParts.timerFS:ClearAllPoints()
        if pvShowTimer then
            local tpt, txb, tjh = mod.GetCastTextAnchor(pvTimerSide, false, pvTimerW, true)
            castParts.timerFS:SetWidth(pvTimerW)
            castParts.timerFS:SetJustifyH(tjh)
            castParts.timerFS:SetPoint(tpt, cast, tpt, txb + tmOX, tmOY)
            castParts.timerFS:Show()
        else
            castParts.timerFS:Hide()
        end
        -- Force new justify onto already-rendered text (JustifyH alone won't re-flow it; see ns.ReflowFontString).
        mod.ReflowFontString(castParts.nameFS)
        mod.ReflowFontString(castParts.targetFS)
        mod.ReflowFontString(castParts.timerFS)
        local useClassColor = defaultSet.castTargetClassColor
        if dbRef and dbRef.castTargetClassColor ~= nil then
            useClassColor = dbRef.castTargetClassColor
        end
        local pvTargetHex
        if useClassColor then
            local _, pClass = UnitClass("player")
            local c = pClass and RAID_CLASS_COLORS and RAID_CLASS_COLORS[pClass]
            if c then
                castParts.targetFS:SetTextColor(c.r, c.g, c.b, 1)
                pvTargetHex = (c.GenerateHexColor and c:GenerateHexColor()) or c.colorStr or "ffffffff"
            else
                castParts.targetFS:SetTextColor(1, 1, 1, 1)
                pvTargetHex = "ffffffff"
            end
        else
            local ctc = (dbRef and dbRef.castTargetColor) or defaultSet.castTargetColor
            castParts.targetFS:SetTextColor(ctc.r, ctc.g, ctc.b, 1)
            pvTargetHex = string.format(
                "ff%02x%02x%02x",
                math.floor(ctc.r * 255 + 0.5),
                math.floor(ctc.g * 255 + 0.5),
                math.floor(ctc.b * 255 + 0.5)
            )
        end
        local pvTargetText = UnitName("player") or CludesUI.L("Spell Target")
        castParts.targetFS:SetText(pvTargetText)
        if pvCombine then
            castParts.nameFS:SetFormattedText(
                "%s - |c" .. pvTargetHex .. "%s|r",
                CludesUI.L("Spell Name"),
                pvTargetText
            )
        else
            castParts.nameFS:SetText(CludesUI.L("Spell Name"))
        end

        -- Name/target/timer widths are set per-element above (each uses its configured % of bar width; timer uses its reserved slot) to mirror the in-game layout.

        -- Helper: position a single preview frame into a slot
        local function PlaceInSlot(widget, slotName, slotPos, total, iconW, iconH, slotSpacing, sxOff, syOff)
            sxOff = sxOff or 0
            syOff = syOff or 0
            -- Vertical center-to-center distance: cropped icons are shorter, so "up"-growth stacked slots pack tighter. slotSpacing is horizontal (gap+width); swap width for height here (equal when uncropped).
            local slotSpacingV = slotSpacing - iconW + iconH
            widget:ClearAllPoints()
            if slotName == "top" then
                -- Anchor auras to whichever FontString is in the top slot
                local anchor
                if mod.IsNameElement(slotTop) then
                    anchor = nameFS
                elseif slotTop == "healthNumber" then
                    anchor = hpNumber
                elseif slotTop == "level" then
                    anchor = lvlText
                elseif slotTop == "targetOfTarget" then
                    anchor = popFrame._totFS
                elseif slotTop == "custom" then
                    anchor = popFrame._customFS.textSlotTop
                elseif slotTop ~= "none" then
                    anchor = hpText
                else
                    anchor = healthBar
                end
                -- Only add cpPush when anchoring to health bar (top slot is "none")
                local slotCpPush = (slotTop == "none") and cpPush or 0
                widget:SetPoint(
                    "BOTTOM",
                    anchor,
                    "TOP",
                    (slotPos - (total + 1) / 2) * slotSpacing + sxOff,
                    debuffY + slotCpPush + syOff
                )
            elseif slotName == "left" or slotName == "right" then
                -- Classic WoW UI: gap off the border art, as live does; the
                -- full-size spell icon pushes the row out where they meet (the
                -- row spans its Y offset up by one icon).
                local sideOff = (DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset)
                    + mod.NP_ClassicSide(slotName)
                    + FullPush(slotName, syOff + iconH / 2 - barH / 2, iconH)
                    + (slotPos - 1) * slotSpacing
                if slotName == "left" then
                    widget:SetPoint("BOTTOMRIGHT", healthBar, "BOTTOMLEFT", -sideOff + sxOff, syOff)
                else
                    widget:SetPoint("BOTTOMLEFT", healthBar, "BOTTOMRIGHT", sideOff + sxOff, syOff)
                end
            elseif slotName == "topleft" then
                local growth = DBVal("topleftSlotGrowth") or defaultSet.topleftSlotGrowth
                local position = slotPos - 1 -- 0 for icon 1, never moves
                local baseX = sxOff
                -- Above the Top Left text while one shows, as live.
                local baseY = debuffY + cpPush + mod.NP_TopCornerLift("topleft", SavedDB()) + syOff
                if growth == "up" then
                    widget:SetPoint(
                        "BOTTOMLEFT",
                        healthBar,
                        "TOPLEFT",
                        baseX,
                        baseY + position * slotSpacingV
                    )
                elseif growth == "right" then
                    widget:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", baseX + position * slotSpacing, baseY)
                else
                    widget:SetPoint("BOTTOMLEFT", healthBar, "TOPLEFT", baseX - position * slotSpacing, baseY)
                end
            elseif slotName == "topright" then
                local growth = DBVal("toprightSlotGrowth") or defaultSet.toprightSlotGrowth
                local position = slotPos - 1 -- 0 for icon 1, never moves
                local baseX = sxOff
                -- Above the Top Right text while one shows, as live.
                local baseY = debuffY + cpPush + mod.NP_TopCornerLift("topright", SavedDB()) + syOff
                if growth == "up" then
                    widget:SetPoint(
                        "BOTTOMRIGHT",
                        healthBar,
                        "TOPRIGHT",
                        baseX,
                        baseY + position * slotSpacingV
                    )
                elseif growth == "left" then
                    widget:SetPoint(
                        "BOTTOMRIGHT",
                        healthBar,
                        "TOPRIGHT",
                        baseX - position * slotSpacing,
                        baseY
                    )
                else
                    widget:SetPoint(
                        "BOTTOMRIGHT",
                        healthBar,
                        "TOPRIGHT",
                        baseX + position * slotSpacing,
                        baseY
                    )
                end
            elseif slotName == "bottom" then
                widget:SetPoint(
                    "TOP",
                    cast,
                    "BOTTOM",
                    (slotPos - (total + 1) / 2) * slotSpacing + sxOff,
                    -2 + syOff
                )
            end
        end

        local function AuraDurationVal(kindOf, suffix)
            local saved = SavedDB()
            local key = kindOf .. "DurationText" .. suffix
            local oldKey = "auraDurationText" .. suffix
            if saved and saved[key] ~= nil then
                return saved[key]
            end
            if saved and saved[oldKey] ~= nil then
                return saved[oldKey]
            end
            return defaultSet[oldKey]
        end
        local debuffDurSz = AuraDurationVal("debuff", "Size")
        local debuffDurX = AuraDurationVal("debuff", "X")
        local debuffDurY = AuraDurationVal("debuff", "Y")
        local debuffDurC = AuraDurationVal("debuff", "Color")
        local buffDurSz = AuraDurationVal("buff", "Size")
        local buffDurX = AuraDurationVal("buff", "X")
        local buffDurY = AuraDurationVal("buff", "Y")
        local buffDurC = AuraDurationVal("buff", "Color")
        local ccDurSz = AuraDurationVal("cc", "Size")
        local ccDurX = AuraDurationVal("cc", "X")
        local ccDurY = AuraDurationVal("cc", "Y")
        local ccDurC = AuraDurationVal("cc", "Color")
        local auraStackSz = DBVal("auraStackTextSize") or defaultSet.auraStackTextSize
        local auraStackC = (SavedDB() and SavedDB().auraStackTextColor) or defaultSet.auraStackTextColor
        local auraStackX = DBVal("auraStackTextX") or defaultSet.auraStackTextX
        local auraStackY = DBVal("auraStackTextY") or defaultSet.auraStackTextY
        local auraStackPos = DBVal("auraStackTextPosition") or defaultSet.auraStackTextPosition
        local atPos = DBVal("auraTextPosition") or defaultSet.auraTextPosition
        local debuffTPos = DBVal("debuffTimerPosition") or atPos
        local buffTPos = DBVal("buffTimerPosition") or atPos
        local ccTPos = DBVal("ccTimerPosition") or atPos

        -- Helper: apply timer position to a duration text fontstring
        local function ApplyTimerPos(durText, auraFrame, place, dim, posX, posY, color)
            if place == "none" then
                durText:Hide()
                return
            end
            durText:Show()
            durText:SetFont(fontFile, dim, CludesUI.SlugFlag("OUTLINE, SLUG"))
            durText:SetTextColor(color.r, color.g, color.b, 1)
            durText:ClearAllPoints()
            if place == "center" then
                durText:SetPoint("CENTER", auraFrame, "CENTER", posX, posY)
                durText:SetJustifyH("CENTER")
            elseif place == "topright" then
                durText:SetPoint("TOPRIGHT", auraFrame, "TOPRIGHT", 3 + posX, 4 + posY)
                durText:SetJustifyH("RIGHT")
            elseif place == "bottomleft" then
                durText:SetPoint("BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + posX, -4 + posY)
                durText:SetJustifyH("LEFT")
            elseif place == "bottomright" then
                durText:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + posX, -4 + posY)
                durText:SetJustifyH("RIGHT")
            else
                durText:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -3 + posX, 4 + posY)
                durText:SetJustifyH("LEFT")
            end
        end

        -- Helper: apply stack-count position to a stack text fontstring
        local function ApplyStackPos(countText, auraFrame)
            if auraStackPos == "none" then
                countText:Hide()
                return
            end
            countText:Show()
            countText:SetFont(fontFile, auraStackSz, CludesUI.SlugFlag("OUTLINE, SLUG"))
            countText:SetTextColor(auraStackC.r, auraStackC.g, auraStackC.b, 1)
            countText:ClearAllPoints()
            if auraStackPos == "center" then
                countText:SetPoint("CENTER", auraFrame, "CENTER", auraStackX, auraStackY)
                countText:SetJustifyH("CENTER")
            elseif auraStackPos == "topright" then
                countText:SetPoint("TOPRIGHT", auraFrame, "TOPRIGHT", 3 + auraStackX, 4 + auraStackY)
                countText:SetJustifyH("RIGHT")
            elseif auraStackPos == "bottomleft" then
                countText:SetPoint("BOTTOMLEFT", auraFrame, "BOTTOMLEFT", -3 + auraStackX, -4 + auraStackY)
                countText:SetJustifyH("LEFT")
            elseif auraStackPos == "topleft" then
                countText:SetPoint("TOPLEFT", auraFrame, "TOPLEFT", -3 + auraStackX, 4 + auraStackY)
                countText:SetJustifyH("LEFT")
            else
                countText:SetPoint("BOTTOMRIGHT", auraFrame, "BOTTOMRIGHT", 3 + auraStackX, -4 + auraStackY)
                countText:SetJustifyH("RIGHT")
            end
        end

        -- Aura slot XY offsets (slot-based)
        local debuffXOff, debuffYOff = 0, 0
        if debuffSlotVal ~= "none" then
            debuffXOff = DBVal(debuffSlotVal .. "SlotXOffset") or 0
            debuffYOff = DBVal(debuffSlotVal .. "SlotYOffset") or 0
        end
        local buffXOff, buffYOff = 0, 0
        if buffSlotVal ~= "none" then
            buffXOff = DBVal(buffSlotVal .. "SlotXOffset") or 0
            buffYOff = DBVal(buffSlotVal .. "SlotYOffset") or 0
        end
        local ccXOff, ccYOff = 0, 0
        if ccSlotVal ~= "none" then
            ccXOff = DBVal(ccSlotVal .. "SlotXOffset") or 0
            ccYOff = DBVal(ccSlotVal .. "SlotYOffset") or 0
        end

        for i = 1, PV_CONST.DEBUFF_COUNT do
            if debuffSlotVal == "none" then
                debuffs[i]:Hide()
            else
                debuffs[i]:Show()
                debuffs[i]:SetSize(Snap(debuffSz), Snap(debuffH))
                mod.SetAuraIconCrop(debuffs[i].icon, debuffCrop, debuffSz, debuffH)
                debuffs[i].durationText:SetFont(fontFile, debuffDurSz, CludesUI.SlugFlag("OUTLINE, SLUG"))
                debuffs[i].durationText:SetTextColor(debuffDurC.r, debuffDurC.g, debuffDurC.b, 1)
                ApplyTimerPos(
                    debuffs[i].durationText,
                    debuffs[i],
                    debuffTPos,
                    debuffDurSz,
                    debuffDurX,
                    debuffDurY,
                    debuffDurC
                )
                ApplyStackPos(debuffs[i].stackText, debuffs[i])
                PlaceInSlot(
                    debuffs[i],
                    debuffSlotVal,
                    i,
                    PV_CONST.DEBUFF_COUNT,
                    debuffSz,
                    debuffH,
                    debuffSpacing,
                    debuffXOff,
                    debuffYOff
                )
            end
        end

        -- Buff size + duration text styling + slot position
        for i = 1, PV_CONST.BUFF_COUNT do
            if buffSlotVal == "none" then
                buffs[i]:Hide()
                if buffs[i].dispelGlow and buffs[i].dispelGlow.active then
                    mod.StopDispelGlow(buffs[i])
                end
            else
                buffs[i]:Show()
                buffs[i]:SetSize(Snap(buffSz), Snap(buffH))
                mod.SetAuraIconCrop(buffs[i].icon, buffCrop, buffSz, buffH)
                buffs[i].durationText:SetFont(fontFile, buffDurSz, CludesUI.SlugFlag("OUTLINE, SLUG"))
                buffs[i].durationText:SetTextColor(buffDurC.r, buffDurC.g, buffDurC.b, 1)
                ApplyTimerPos(
                    buffs[i].durationText,
                    buffs[i],
                    buffTPos,
                    buffDurSz,
                    buffDurX,
                    buffDurY,
                    buffDurC
                )
                PlaceInSlot(
                    buffs[i],
                    buffSlotVal,
                    i,
                    PV_CONST.BUFF_COUNT,
                    buffSz,
                    buffH,
                    buffSpacing,
                    buffXOff,
                    buffYOff
                )
                -- Dispel glow preview: the live buff row's glow. StartSpecGlow
                -- restarts it only when the style or a setting changed.
                local previewType = PreviewDispelType()
                if DBVal("dispelGlow") == true and previewType then
                    mod.StartDispelGlow(buffs[i], buffSz, previewType, buffH)
                elseif buffs[i].dispelGlow and buffs[i].dispelGlow.active then
                    mod.StopDispelGlow(buffs[i])
                end
            end
        end

        -- CC size + duration text styling + slot position
        for i = 1, PV_CONST.CC_COUNT do
            if ccSlotVal == "none" then
                ccs[i]:Hide()
            else
                ccs[i]:Show()
                ccs[i]:SetSize(Snap(ccSz), Snap(ccH))
                mod.SetAuraIconCrop(ccs[i].icon, ccCrop, ccSz, ccH)
                ccs[i].durationText:SetFont(fontFile, ccDurSz, CludesUI.SlugFlag("OUTLINE, SLUG"))
                ccs[i].durationText:SetTextColor(ccDurC.r, ccDurC.g, ccDurC.b, 1)
                ApplyTimerPos(ccs[i].durationText, ccs[i], ccTPos, ccDurSz, ccDurX, ccDurY, ccDurC)
                PlaceInSlot(ccs[i], ccSlotVal, i, PV_CONST.CC_COUNT, ccSz, ccH, ccSpacing, ccXOff, ccYOff)
            end
        end

        -- Core Positions chains: a slot holding two or more elements lays them out one
        -- after another (ChainPreview, mirroring the live chain); its inputs ride one
        -- kept table (this function is near Lua 5.1's 200-local cap).
        do
            local cx = optionState._pvChain
            if not cx then
                cx = {
                    rows = { debuffs = {}, buffs = {}, ccs = {} },
                    icons = { raidmarker = {}, class = {}, qtext = {}, faction = {} },
                    sideEnd = {},
                }
                optionState._pvChain = cx
            end
            cx.DBVal, cx.defaults = DBVal, defaultSet
            cx.barH, cx.arrowH, cx.debuffY = barH, arrowH, debuffY
            local r = cx.rows.debuffs
            r.list, r.count, r.sz, r.h, r.gap, r.slot =
                debuffs, PV_CONST.DEBUFF_COUNT, debuffSz, debuffH, debuffGap, debuffSlotVal
            r = cx.rows.buffs
            r.list, r.count, r.sz, r.h, r.gap, r.slot =
                buffs, PV_CONST.BUFF_COUNT, buffSz, buffH, buffGap, buffSlotVal
            r = cx.rows.ccs
            r.list, r.count, r.sz, r.h, r.gap, r.slot = ccs, PV_CONST.CC_COUNT, ccSz, ccH, ccGap, ccSlotVal
            r = cx.icons.raidmarker
            r.frame, r.slot, r.sz = raidFrame, rmPos, rmSize
            -- The Rare/Quest member counts only while a half is on or the badge rides it (as live).
            r = cx.icons.class
            r.frame, r.sz = classIcon, reIconSz
            r.slot = (hideRare and not mod.NP_QuestIconOn(SavedDB()) and not fcCombined) and "none" or clPos
            r = cx.icons.qtext
            r.frame, r.slot, r.sz = popFrame._qt.frame, popFrame._qt.pos, popFrame._qt.h
            r = cx.icons.faction
            r.frame, r.slot = factionIcon, fcCombined and "none" or fcPos
            r.sz = mod.NP_ElementSize("faction", SavedDB())
            cx.classFaction, cx.factionFrame = fcCombined, factionIcon
            ChainPreview(cx)
        end

        -- Position target arrows OUTSIDE the side elements they meet (mirror live
        -- PositionArrowsOutsideAuras): they centre on the bar, arrowH tall, and an
        -- element its slot's Y offset moved above or below them is passed over.
        if showArrows then
            arrows.left:ClearAllPoints()
            arrows.right:ClearAllPoints()
            local sideOff = DBVal("sideAuraXOffset") or defaultSet.sideAuraXOffset
            -- The cast icon (and Classic WoW UI's border) on the arrows' own span.
            local leftExtent = castIconLeftPush + FullPush("left", 0, arrowH)
            local rightExtent = castIconRightPush + FullPush("right", 0, arrowH)
            -- One element on `side`, centred on the bar plus y, sz tall, reaching
            -- `reach` past the bar's edge.
            local function add(sideName, posY, sz, reach)
                if math.abs(posY) >= (sz + arrowH) / 2 then
                    return
                end
                if sideName == "left" then
                    leftExtent = math.max(leftExtent, reach)
                elseif sideName == "right" then
                    rightExtent = math.max(rightExtent, reach)
                end
            end
            -- Aura slots (debuffs, buffs, ccs): a row spans its Y offset up by one
            -- icon, sits past Classic WoW UI's border art and steps out for the
            -- full-size spell icon where it meets it, as live.
            local function addAuraSide(slotVal, total, sz, hgt, sp, xOff, yOff)
                if slotVal ~= "left" and slotVal ~= "right" then
                    return
                end
                local posY = yOff + hgt / 2 - barH / 2
                add(
                    slotVal,
                    posY,
                    hgt,
                    sideOff
                        + mod.NP_ClassicSide(slotVal)
                        + FullPush(slotVal, posY, hgt)
                        + (total - 1) * sp
                        + sz
                        + ((slotVal == "left") and -xOff or xOff)
                )
            end
            addAuraSide(
                debuffSlotVal,
                PV_CONST.DEBUFF_COUNT,
                debuffSz,
                debuffH,
                debuffSpacing,
                debuffXOff,
                debuffYOff
            )
            addAuraSide(buffSlotVal, PV_CONST.BUFF_COUNT, buffSz, buffH, buffSpacing, buffXOff, buffYOff)
            addAuraSide(ccSlotVal, PV_CONST.CC_COUNT, ccSz, ccH, ccSpacing, ccXOff, ccYOff)
            -- Side icons (raid marker, classification, Quest Objective Text,
            -- faction), each past its own cast icon push; w: the element's width
            -- (sz, its height, when nil).
            local function addIcon(sideName, posY, sz, xOff, wid)
                if sideName ~= "left" and sideName ~= "right" then
                    return
                end
                add(
                    sideName,
                    posY,
                    sz,
                    sideOff
                        + ((sideName == "left") and castIconLeftPush or castIconRightPush)
                        + FullPush(sideName, posY, sz)
                        + (wid or sz)
                        + ((sideName == "left") and -xOff or xOff)
                )
            end
            if raidFrame:IsShown() then
                addIcon(rmPos, rmYOff, rmSize, rmXOff)
            end
            if classIcon:IsShown() then
                addIcon(clPos, clYOff, reIconSz, clXOff)
            end
            if popFrame._qt.shown then
                local qt = popFrame._qt
                addIcon(qt.pos, qt.y, qt.h, qt.x, qt.w)
            end
            if factionIcon:IsShown() and (fcPos == "left" or fcPos == "right") then
                -- Stacked behind a showing Rare/Quest icon it sits higher.
                local fy = (DBVal(fcPos .. "SlotYOffset") or 0)
                    + ((fcCombined and classIcon:IsShown()) and math.floor(reIconSz * 0.6 + 0.5) or 0)
                addIcon(
                    fcPos,
                    fy,
                    mod.NP_ElementSize("faction", SavedDB()),
                    DBVal(fcPos .. "SlotXOffset") or 0
                )
            end
            -- A side chain's outermost element is hugged at its outer bottom corner,
            -- the arrow centred on the bar, as live.
            local chainEnd = optionState._pvChain.sideEnd
            if chainEnd.left then
                arrows.left:SetPoint(
                    "RIGHT",
                    chainEnd.left.frame,
                    "BOTTOMLEFT",
                    -8,
                    barH / 2 - chainEnd.left.y
                )
            else
                arrows.left:SetPoint("RIGHT", healthBar, "LEFT", -(leftExtent + 8), 0)
            end
            if chainEnd.right then
                arrows.right:SetPoint(
                    "LEFT",
                    chainEnd.right.frame,
                    "BOTTOMRIGHT",
                    8,
                    barH / 2 - chainEnd.right.y
                )
            else
                arrows.right:SetPoint("LEFT", healthBar, "RIGHT", rightExtent + 8, 0)
            end
            arrows.left:Show()
            arrows.right:Show()
            if popFrame._arrowOverlay then
                popFrame._arrowOverlay:Show()
            end
        else
            arrows.left:Hide()
            arrows.right:Hide()
            if popFrame._arrowOverlay then
                popFrame._arrowOverlay:Hide()
            end
        end

        -- Height calculation: "top" slot auras stack above the top text; corner items (and a "top" raid marker or classification icon) anchor to the health bar beside it, so the two count as max, not sum.
        -- Its working locals live in a block: this function is near Lua 5.1's 200-local cap.
        local healthFromTop
        do
            local stackExtent, cornerExtent = 0, 0
            local function isCorner(s)
                return s == "topleft" or s == "topright"
            end
            -- Extents use iconH: a cropped icon is shorter than its size (width).
            local function addAura(slotVal, total, sz, iconH, spacing, yOff)
                if slotVal == "top" then
                    stackExtent = math.max(stackExtent, iconH + yOff)
                elseif isCorner(slotVal) then
                    -- "up" growth stacks the icons, as PlaceInSlot does
                    local stackH = 0
                    if (DBVal(slotVal .. "SlotGrowth") or defaultSet[slotVal .. "SlotGrowth"]) == "up" then
                        stackH = (total - 1) * (spacing - sz + iconH)
                    end
                    cornerExtent = math.max(
                        cornerExtent,
                        debuffY + mod.NP_TopCornerLift(slotVal, SavedDB()) + iconH + stackH + yOff
                    )
                end
            end
            addAura(debuffSlotVal, PV_CONST.DEBUFF_COUNT, debuffSz, debuffH, debuffSpacing, debuffYOff)
            addAura(buffSlotVal, PV_CONST.BUFF_COUNT, buffSz, buffH, buffSpacing, buffYOff)
            addAura(ccSlotVal, PV_CONST.CC_COUNT, ccSz, ccH, ccSpacing, ccYOff)
            if showRM then
                if rmPos == "top" then
                    cornerExtent = math.max(cornerExtent, debuffY + rmSize + rmYOff)
                elseif isCorner(rmPos) then
                    cornerExtent =
                        math.max(cornerExtent, mod.NP_TopCornerLift(rmPos, SavedDB()) + rmSize + rmYOff)
                end
            end
            if showCL then
                if clPos == "top" then
                    cornerExtent = math.max(cornerExtent, debuffY + reIconSz + clYOff)
                elseif isCorner(clPos) then
                    cornerExtent =
                        math.max(cornerExtent, 2 + mod.NP_TopCornerLift(clPos, SavedDB()) + reIconSz + clYOff)
                end
            end
            -- The Quest Objective Text, placed like the Rare/Quest icon.
            local qt = popFrame._qt
            if qt.shown then
                if qt.pos == "top" then
                    cornerExtent = math.max(cornerExtent, debuffY + qt.h + qt.y)
                elseif isCorner(qt.pos) then
                    cornerExtent =
                        math.max(cornerExtent, 2 + mod.NP_TopCornerLift(qt.pos, SavedDB()) + qt.h + qt.y)
                end
            end
            cornerExtent = math.max(cornerExtent, factionTopExtent)
            -- The Top Left / Top Right texts themselves (their top over the bar).
            cornerExtent = math.max(
                cornerExtent,
                mod.NP_TopCornerLift("topleft", SavedDB()),
                mod.NP_TopCornerLift("topright", SavedDB())
            )
            -- Only include name text height when something is actually in the top slot
            local topTextH = (slotTop ~= "none") and (topFontSz + 4 + nameYOff + topYOff) or 0
            -- Only add debuffY gap when an aura occupies the center "top" position or the top text slot is used
            local hasTopAura = (debuffSlotVal == "top") or (buffSlotVal == "top") or (ccSlotVal == "top")
            local effectiveDebuffY = (hasTopAura or slotTop ~= "none") and debuffY or 0
            local topStackH = topTextH + effectiveDebuffY + stackExtent
            -- 15 matches the bottom margin below the cast bar in totalH
            healthFromTop = Snap(15 + math.max(topStackH, cornerExtent) + cpPush)
        end
        healthBar:ClearAllPoints()
        healthBar:SetSize(barW, barH)

        -- Size the plain-Frame wrapper to match the health bar exactly; the image border lives on this wrapper (not the StatusBar).
        healthWrapper:ClearAllPoints()
        healthWrapper:SetSize(barW, barH)

        local pfW = localParentW
        local dragging = IsDragging()
        local xOff
        if dragging and _cachedRawBarW then
            local delta = (rawBarW - _cachedRawBarW) / 2
            xOff = _cachedXOff - delta
            healthBar:SetPoint("TOPLEFT", popFrame, "TOPLEFT", xOff, -healthFromTop)
            healthWrapper:SetPoint("TOPLEFT", popFrame, "TOPLEFT", xOff, -healthFromTop)
        else
            xOff = Snap((pfW - barW) / 2)
            _cachedRawBarW = rawBarW
            _cachedXOff = xOff
            healthBar:SetPoint("TOPLEFT", popFrame, "TOPLEFT", xOff, -healthFromTop)
            healthWrapper:SetPoint("TOPLEFT", popFrame, "TOPLEFT", xOff, -healthFromTop)
        end

        -- Preview hash line
        local hlEnabled = DBVal("hashLineEnabled")
        local hlPct = DBVal("hashLinePercent") or defaultSet.hashLinePercent
        if hlEnabled and hlPct and hlPct > 0 then
            local hlX = barW * (hlPct / 100)
            previewHashLine:ClearAllPoints()
            previewHashLine:SetPoint("TOP", healthBar, "TOPLEFT", hlX, 0)
            previewHashLine:SetPoint("BOTTOM", healthBar, "BOTTOMLEFT", hlX, 0)
            local hlc = (SavedDB() and SavedDB().hashLineColor) or defaultSet.hashLineColor
            previewHashLine:SetColorTexture(hlc.r, hlc.g, hlc.b, 0.8)
            previewHashLine:Show()
        else
            previewHashLine:Hide()
        end

        -- Preview bar texture: apply via SetStatusBarTexture
        do
            local texKey = DBVal("healthBarTexture") or "none"
            local texPath =
                CludesUI.ResolveTexturePath(mod.healthBarTextures, texKey, "Interface\\Buttons\\WHITE8x8")
            healthBar:SetStatusBarTexture(texPath)
            UnsnapTex(healthBar:GetStatusBarTexture())
        end

        -- Class power pips (preview): the renderer is a nested function, defined and called once right here so its ~38 locals live in their own scope -- pf.Update was over Lua 5.1's 200-local-per-function cap.
        popFrame.UpdateCP = function()
            local showCP = DBVal("showClassPower") == true
            local cpExtraH = 0
            local cpIsBarType = false
            local cpResourceName = nil
            -- Hide the clamp badge/arrow by default; the render branches below re-show
            -- them only when the offset is actually clamped to the plate.
            CP.offBadge:Hide()
            CP.offArrow:Hide()
            if showCP then
                -- The pips are clamped to the plate (CP.Clamp) and the real offset is
                -- badged when clamped, so the preview frame size never changes with
                -- the offset.
                local cpCenterX = xOff + barW / 2 -- health-bar center (barW is shadowed in branches)
                local castBotY = -healthFromTop - barH + pCastY - castH
                -- Determine pip count from player's class, using live UnitPowerMax when available
                local _, playerClass = UnitClass("player")
                local cpInfo = CP.CLASS_MAP[playerClass]
                -- Match the module: vanilla content has only these two resources,
                -- so previewing the rest would promise pips that never appear.
                if CludesUI.IS_FOREVER then
                    cpInfo = (playerClass == "ROGUE" or playerClass == "DRUID") and CP.CLASS_MAP[playerClass]
                        or nil
                end
                local cpMax = 0
                if cpInfo then
                    -- Resolve spec-specific entries (numeric specID keys)
                    if cpInfo[1] == nil then
                        local specInfo = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization()
                        local specID = specInfo and C_SpecializationInfo.GetSpecializationInfo(specInfo)
                        cpInfo = specID and cpInfo[specID]
                    end
                    if cpInfo then
                        cpResourceName = type(cpInfo[1]) == "string" and cpInfo[1] or nil
                        if type(cpInfo[1]) == "string" then
                            if cpInfo[1] == "BREWMASTER_STAGGER" then
                                cpIsBarType = true
                                cpMax = 1
                            elseif cpInfo[1] == "SOUL_FRAGMENTS_VENGEANCE" then
                                cpMax = 6
                            elseif
                                cpInfo[1] == "MAELSTROM_WEAPON"
                                and CludesUI
                                and CludesUI.GetMaelstromWeapon
                            then
                                local _, mMax = CludesUI.GetMaelstromWeapon()
                                cpMax = (mMax and mMax > 0) and mMax or cpInfo[2]
                            elseif cpInfo[1] == "TIP_OF_THE_SPEAR" then
                                cpMax = cpInfo[2]
                            elseif cpInfo[1] == "WHIRLWIND_STACKS" then
                                cpMax = cpInfo[2]
                            else
                                cpMax = cpInfo[2]
                            end
                        else
                            local liveMax = UnitPowerMax("player", cpInfo[1])
                            cpMax = (liveMax and liveMax > 0) and liveMax or cpInfo[2]
                        end
                    end
                end
                local cpCur = math.floor(cpMax * CP.FILL_FRAC + 0.5)
                local useClassColors = DBVal("classPowerClassColors")
                if useClassColors == nil then
                    useClassColors = defaultSet.classPowerClassColors
                end
                local cpColor = CP.DEFAULT_COLOR
                if useClassColors then
                    cpColor = CP.CLASS_COLORS[playerClass] or CP.DEFAULT_COLOR
                else
                    local cc = (SavedDB() and SavedDB().classPowerCustomColor)
                        or defaultSet.classPowerCustomColor
                    cpColor = { cc.r, cc.g, cc.b }
                end

                local cpBgCol = (SavedDB() and SavedDB().classPowerBgColor) or defaultSet.classPowerBgColor

                if cpIsBarType then
                    -- Bar-type preview (stagger): single StatusBar
                    for i = 1, CP.MAX_POSSIBLE do
                        CP.pips[i]:Hide()
                        if CP.pips[i]._bg then
                            CP.pips[i]._bg:Hide()
                        end
                        mod.HidePipDecor(CP.pips[i])
                    end
                    local cpScale = DBVal("classPowerScale") or defaultSet.classPowerScale
                    local cpYOff = DBVal("classPowerYOffset") or defaultSet.classPowerYOffset
                    local cpXOff = DBVal("classPowerXOffset") or defaultSet.classPowerXOffset
                    local cpPos = DBVal("classPowerPos") or defaultSet.classPowerPos
                    local scaledH = Snap(CP.PIP_H * cpScale)
                    local barW = Snap(CP.PIP_W * cpScale * 6)

                    local anchorPoint, anchorRelPoint, anchorFrame, yDir
                    if cpPos == "top" then
                        anchorPoint = "BOTTOM"
                        anchorRelPoint = "TOP"
                        anchorFrame = healthBar
                        yDir = 1
                    else
                        anchorPoint = "TOP"
                        anchorRelPoint = "BOTTOM"
                        anchorFrame = cast
                        yDir = -1
                    end
                    local cpYShown, cpYReal, cpEdgeIn, cpDirIn =
                        CP.Clamp(cpPos == "top", yDir, cpYOff, scaledH, -healthFromTop, castBotY)

                    local barFrame = CP.bar
                    barFrame:ClearAllPoints()
                    barFrame:SetSize(barW, scaledH)
                    barFrame:SetPoint(
                        anchorPoint,
                        anchorFrame,
                        anchorRelPoint,
                        Snap(cpXOff),
                        Snap(yDir * cpYShown)
                    )
                    barFrame:SetMinMaxValues(0, 100)
                    barFrame:SetValue(45) -- preview at 45% (moderate stagger)
                    barFrame:SetStatusBarColor(1.0, 0.85, 0.2, 1) -- yellow for preview
                    barFrame._bg:SetColorTexture(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                    barFrame:Show()

                    if cpPos ~= "top" then
                        cpExtraH = scaledH
                    end
                    if cpYReal then
                        CP.ShowBadge(cpEdgeIn, cpDirIn, cpCenterX + cpXOff, cpYReal)
                    end
                elseif cpMax <= 0 then
                    for i = 1, CP.MAX_POSSIBLE do
                        CP.pips[i]:Hide()
                        if CP.pips[i]._bg then
                            CP.pips[i]._bg:Hide()
                        end
                        mod.HidePipDecor(CP.pips[i])
                    end
                    CP.bar:Hide()
                else
                    CP.bar:Hide()
                    local cpScale = DBVal("classPowerScale") or defaultSet.classPowerScale
                    local cpYOff = DBVal("classPowerYOffset") or defaultSet.classPowerYOffset
                    local cpXOff = DBVal("classPowerXOffset") or defaultSet.classPowerXOffset
                    local cpPos = DBVal("classPowerPos") or defaultSet.classPowerPos
                    local cpGap = DBVal("classPowerGap") or defaultSet.classPowerGap
                    local cpShape = DBVal("classPowerShape") or defaultSet.classPowerShape
                    local cpBorderOn = DBVal("classPowerBorder") == true
                    local cpBorderCol = (SavedDB() and SavedDB().classPowerBorderColor)
                        or defaultSet.classPowerBorderColor
                    local cpBorderPx = cpBorderOn
                            and Snap(DBVal("classPowerBorderSize") or defaultSet.classPowerBorderSize)
                        or 0
                    local cpIconKind = mod.GetPipIconKind(cpShape)
                    local cpSquare = CP.SQUARE_SHAPE[cpShape] or (cpIconKind ~= nil)
                    local scaledW = Snap(CP.PIP_W * cpScale)
                    local scaledH = cpSquare and scaledW or Snap(CP.PIP_H * cpScale)
                    local scaledGap = Snap(cpGap * cpScale)
                    local totalPipW = cpMax * scaledW + (cpMax - 1) * scaledGap

                    -- Determine anchor frame and direction
                    local anchorPoint, anchorRelPoint, anchorFrame, yDir
                    if cpPos == "top" then
                        anchorPoint = "BOTTOM"
                        anchorRelPoint = "TOP"
                        anchorFrame = healthBar
                        yDir = 1
                    else
                        -- Bottom: attach below cast bar (preview always shows cast bar)
                        anchorPoint = "TOP"
                        anchorRelPoint = "BOTTOM"
                        anchorFrame = cast
                        yDir = -1
                    end
                    local cpYShown, cpYReal, cpEdgeIn, cpDirIn =
                        CP.Clamp(cpPos == "top", yDir, cpYOff, scaledH, -healthFromTop, castBotY)

                    local cpEmptyCol = (SavedDB() and SavedDB().classPowerEmptyColor)
                        or defaultSet.classPowerEmptyColor

                    -- Pre-compute each pip's left-edge X in group-local coords; anchor via BOTTOMLEFT/TOPLEFT to avoid half-pixel center offsets.
                    local pipPositions = {}
                    for i = 1, cpMax do
                        pipPositions[i] = Snap((i - 1) * (scaledW + scaledGap))
                    end
                    local groupW = pipPositions[cpMax] + scaledW
                    local halfGroup = Snap(groupW / 2)

                    local leftAnchor = (anchorPoint == "BOTTOM") and "BOTTOMLEFT" or "TOPLEFT"

                    for i = 1, CP.MAX_POSSIBLE do
                        local pipTex = CP.pips[i]
                        if i <= cpMax then
                            pipTex:ClearAllPoints()
                            pipTex:SetSize(scaledW, scaledH)
                            local pipLeftX = Snap(pipPositions[i] - halfGroup + cpXOff)
                            pipTex:SetPoint(
                                leftAnchor,
                                anchorFrame,
                                anchorRelPoint,
                                pipLeftX,
                                Snap(yDir * cpYShown)
                            )

                            -- Background behind each pip
                            local backdrop = pipTex._bg
                            if backdrop then
                                backdrop:ClearAllPoints()
                                backdrop:SetAllPoints(pipTex)
                                backdrop:SetTexture(CP.WHITE)
                                backdrop:SetTexCoord(0, 1, 0, 1)
                                backdrop:SetDesaturated(false)
                                backdrop:SetVertexColor(cpBgCol.r, cpBgCol.g, cpBgCol.b, cpBgCol.a)
                                backdrop:Show()
                            end

                            mod.ApplyPipShape(popFrame, pipTex, cpShape, cpBorderOn, cpBorderCol, cpBorderPx)

                            if cpIconKind == "holypower" then
                                local num = (i - 1) % 5 + 1
                                local flip = (num == 5)
                                local position = flip and 4 or num
                                if backdrop then
                                    backdrop:SetAtlas("nameplates-holypower" .. position .. "-off")
                                    backdrop:SetDesaturated(true)
                                    if flip then
                                        backdrop:SetTexCoord(1, 0, 0, 1)
                                    end
                                    backdrop:SetVertexColor(1, 1, 1, cpBgCol.a)
                                    backdrop:Show()
                                end
                                if i <= cpCur then
                                    pipTex:SetAtlas("nameplates-holypower" .. position .. "-on")
                                    if flip then
                                        pipTex:SetTexCoord(1, 0, 0, 1)
                                    end
                                    pipTex:SetVertexColor(1, 1, 1, 1)
                                    UnsnapTex(pipTex)
                                    pipTex:Show()
                                else
                                    pipTex:Hide()
                                end
                            elseif cpIconKind then
                                pipTex:SetAtlas(mod.GetPipIconAtlas(cpIconKind, i <= cpCur, i))
                                if (i > cpCur) and mod.CP_ICON_DIM_EMPTY[cpIconKind] then
                                    pipTex:SetVertexColor(0.35, 0.35, 0.35, 1)
                                else
                                    pipTex:SetVertexColor(1, 1, 1, 1)
                                end
                                UnsnapTex(pipTex)
                                pipTex:Show()
                            else
                                pipTex:SetTexture(CP.WHITE)
                                pipTex:SetTexCoord(0, 1, 0, 1)
                                if i <= cpCur then
                                    pipTex:SetVertexColor(cpColor[1], cpColor[2], cpColor[3], 1)
                                else
                                    pipTex:SetVertexColor(
                                        cpEmptyCol.r,
                                        cpEmptyCol.g,
                                        cpEmptyCol.b,
                                        cpEmptyCol.a
                                    )
                                end
                                UnsnapTex(pipTex)
                                pipTex:Show()
                            end
                        else
                            pipTex:Hide()
                            if pipTex._bg then
                                pipTex._bg:Hide()
                            end
                            if pipTex._border then
                                pipTex._border:Hide()
                            end
                            if pipTex._borderBox then
                                pipTex._borderBox:Hide()
                            end
                        end
                    end
                    -- Base reservation only -- the offset never grows the frame (pips
                    -- are clamped to the plate by CP.Clamp instead).
                    if cpPos ~= "top" then
                        cpExtraH = scaledH
                    end
                    if cpYReal then
                        CP.ShowBadge(cpEdgeIn, cpDirIn, cpCenterX + cpXOff, cpYReal)
                    end
                end
            else
                for i = 1, CP.MAX_POSSIBLE do
                    CP.pips[i]:Hide()
                    if CP.pips[i]._bg then
                        CP.pips[i]._bg:Hide()
                    end
                    mod.HidePipDecor(CP.pips[i])
                end
                CP.bar:Hide()
            end
            return cpExtraH
        end
        local cpExtraH = popFrame.UpdateCP()

        local totalH = Snap(healthFromTop + barH + castH + cpExtraH + 15)
        -- Add extra height for auras in the "bottom" slot (below cast bar)
        local bottomExtent = 0
        local function isBottomSlot(s)
            return s == "bottom"
        end
        if isBottomSlot(debuffSlotVal) then
            bottomExtent = math.max(bottomExtent, debuffH + 2 - debuffYOff)
        end
        if isBottomSlot(buffSlotVal) then
            bottomExtent = math.max(bottomExtent, buffH + 2 - buffYOff)
        end
        if isBottomSlot(ccSlotVal) then
            bottomExtent = math.max(bottomExtent, ccH + 2 - ccYOff)
        end
        if isBottomSlot(rmPos) and showRM then
            bottomExtent = math.max(bottomExtent, rmSize + 2 - rmYOff)
        end
        if isBottomSlot(clPos) and showCL then
            bottomExtent = math.max(bottomExtent, reIconSz + 2 - clYOff)
        end
        if popFrame._qt.shown and isBottomSlot(popFrame._qt.pos) then
            bottomExtent = math.max(bottomExtent, popFrame._qt.h + 2 - popFrame._qt.y)
        end
        -- The Bottom Left / Bottom Right texts hang there too.
        bottomExtent = math.max(bottomExtent, previewGlow.botTextH or 0)
        totalH = totalH + bottomExtent
        self:SetSize(localParentW, totalH)

        -- Target glow preview (9-slice soft glow matching real nameplates)
        local pgf = previewGlow.frame
        pgf:ClearAllPoints()
        local ge = previewGlow.extend
        Pix.Point(pgf, "TOPLEFT", healthWrapper, "TOPLEFT", -ge, ge)
        Pix.Point(pgf, "BOTTOMRIGHT", healthWrapper, "BOTTOMRIGHT", ge, -ge)
        local glowCUI = previewGlow.getCUI()
        local glowBorder = previewGlow.getBorderOn()
        local glowHighlight = previewGlow.getHighlight()
        -- CludesUI: background glow, tinted + faded with the Glow Color/Opacity
        if optionState.showTargetGlowPreview and glowCUI then
            local gc = previewGlow.getGlowCol()
            local ga = previewGlow.getGlowAlpha()
            for _, t in ipairs(previewGlow.texs) do
                t:SetVertexColor(gc.r, gc.g, gc.b, ga)
            end
            pgf:Show()
        else
            pgf:Hide()
        end
        -- Border Color: override the preview border with the custom target color
        if optionState.showTargetGlowPreview and glowBorder then
            local bc = previewGlow.getBorderCol()
            for _, texture in ipairs(borderFrame._texs) do
                texture:SetVertexColor(bc.r, bc.g, bc.b)
            end
            for _, texture in ipairs(simpleBorderFrame._texs) do
                texture:SetVertexColor(bc.r, bc.g, bc.b)
            end
            for _, e in ipairs(_solidEdges) do
                e:SetColorTexture(bc.r, bc.g, bc.b, 1)
                UnsnapTex(e)
            end
        end
        -- Highlight: translucent wash across the preview health bar (color/opacity via the Target Highlight cog).
        if previewGlow.highlight then
            local showHL = optionState.showTargetGlowPreview and glowHighlight
            if showHL then
                local hc = previewGlow.getHighlightCol()
                previewGlow.highlight:SetColorTexture(hc.r, hc.g, hc.b, previewGlow.getHighlightAlpha())
            end
            previewGlow.highlight:SetShown(showHL)
        end

        -- Stock styles: the stock look over everything laid out above.
        if previewGlow.classic then
            -- Classic WoW UI: the vanilla borders round both bars (the
            -- border block hid the CUI edges); the cast icon shows its
            -- whole art in the cast border's plate and the harmful aura
            -- mocks wear the stock dispel-type border like the live
            -- cells. No ring, overlay or mask.
            previewGlow.applyClassic(barH, castH)
            if mod.NP_ApplyClassicIconArt then
                for i = 1, PV_CONST.DEBUFF_COUNT do
                    mod.NP_ApplyClassicIconArt(debuffs[i])
                end
                for i = 1, PV_CONST.CC_COUNT do
                    mod.NP_ApplyClassicIconArt(ccs[i])
                end
            end
        elseif CludesUI.BlizzStyle.Get("nameplates") then
            previewGlow.applyBlizz()
            -- Aura mocks: the stock rounded mask and ring, as the live cells
            -- (sized above, so the ring geometry reads the frames).
            if mod.NP_ApplyBlizzIconArt then
                for i = 1, PV_CONST.DEBUFF_COUNT do
                    mod.NP_ApplyBlizzIconArt(debuffs[i], debuffs[i].icon)
                end
                for i = 1, PV_CONST.BUFF_COUNT do
                    mod.NP_ApplyBlizzIconArt(buffs[i], buffs[i].icon)
                end
                for i = 1, PV_CONST.CC_COUNT do
                    mod.NP_ApplyBlizzIconArt(ccs[i], ccs[i].icon)
                end
            end
        end

        -- Absorb preview: update and toggle
        ToggleAbsorbPreview()

        -- Notify framework so the scroll area adjusts: report full content header height (preset offset + bottom padding, not just the preview frame), converting totalH from preview-local to parent-space.
        -- Only while this preview is the header on screen: an update of the preview
        -- left on another page (stashed, or in its hidden kept header root) must not
        -- resize that page's header.
        if self:IsVisible() then
            local headerExtra = popFrame._headerExtra or 0
            local hintH = (optionState._previewHintFS and optionState._previewHintFS:IsShown()) and 29 or 0
            CludesUI:UpdateContentHeaderHeight(totalH * previewScale + headerExtra + hintH)
        end

        -- Refresh text overlay sizes (font/text may have changed)
        if popFrame._textOverlays then
            for _, shade in ipairs(popFrame._textOverlays) do
                if shade._syncFS then
                    shade:SetShown(shade._syncFS:IsShown())
                end
                if shade._resizeToText then
                    shade._resizeToText()
                end
            end
        end
    end

    -- Expose preview elements for click-navigation hit overlays
    popFrame._nameFS = nameFS
    popFrame._hpText = hpText
    popFrame._hpNumber = hpNumber
    popFrame._lvlText = lvlText
    popFrame._debuffs = debuffs
    popFrame._buffs = buffs
    popFrame._ccs = ccs
    popFrame._cast = cast
    popFrame._castIconFrame = castParts.iconFrame
    popFrame._castNameFS = castParts.nameFS
    popFrame._castTargetFS = castParts.targetFS
    popFrame._castTimerFS = castParts.timerFS
    popFrame._raidFrame = raidFrame
    popFrame._classIcon = classIcon
    popFrame._factionIcon = factionIcon
    popFrame._questTextFrame = popFrame._qt.frame
    popFrame._health = healthBar
    popFrame._healthWrapper = healthWrapper
    popFrame._cpPips = CP.pips
    popFrame._cpBar = CP.bar
    popFrame._cpMax = CP.MAX_POSSIBLE
    popFrame._arrows = arrows

    optionState.activePreview = popFrame
    popFrame:Update()
    -- Return visual height in parent-scale pixels (pf:GetHeight() is local, scale it)
    return popFrame:GetHeight() * previewScale
end

-- Used by CUI_Nameplates_Options.lua
mod.NPO_BuildNameplatePreview = BuildNameplatePreview
