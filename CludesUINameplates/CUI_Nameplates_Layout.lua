if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Nameplates_Layout.lua
--
--  Setting getters (offsets, sizes, scales, slots, borders, class power
--  options), the glow aliases, the dispel glow and aura slot positioning.
--  Reads the earlier nameplate files through ns and ns._npInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._npInternals
-- CludesUINameplates.lua or an earlier nameplate file failed to load.
if not Inner or Inner.broken then return end
Inner.broken = true

local ipairs, type = ipairs, type
local Pix = CludesUI.PP
-- The core's table of the options page frame pool (CludesUI_PixelPerfect.lua
-- makes it, the options addon fills it): the builders the options preview shares
-- with the plates create through it, so a preview frame is handed back to the
-- preview's next build. A plate's parent is no pool host: a plain CreateFrame.
local Pool = CludesUI._Pool
local UnitIsPlayer = UnitIsPlayer
local GetTime = GetTime

local BAR_W, defaultSet = Inner.BAR_W, Inner.defaults

local p
Inner.profileSetters[#Inner.profileSetters + 1] = function(val) p = val end

local function GetNameplateYOffset() return (p and p.nameplateYOffset) or defaultSet.nameplateYOffset end
mod.GetNameplateYOffset = GetNameplateYOffset
local function GetStackSpacingScale() return (p and p.stackSpacingScale) or defaultSet.stackSpacingScale end
mod.GetStackSpacingScale = GetStackSpacingScale
local function GetCastScale() return (p and p.castScale) or defaultSet.castScale end
mod.GetCastScale = GetCastScale
local function GetTargetScale() return (p and p.targetScale) or defaultSet.targetScale end
mod.GetTargetScale = GetTargetScale
local function GetHealthBarHeight() return (p and p.healthBarHeight) or defaultSet.healthBarHeight end
mod.GetHealthBarHeight = GetHealthBarHeight
local function GetFriendlyHealthBarHeight()
    return (p and p.friendlyHealthBarHeight) or defaultSet.friendlyHealthBarHeight
end
mod.GetFriendlyHealthBarHeight = GetFriendlyHealthBarHeight
local function GetFriendlyHealthBarWidth()
    return (p and p.friendlyHealthBarWidth) or defaultSet.friendlyHealthBarWidth
end
mod.GetFriendlyHealthBarWidth = GetFriendlyHealthBarWidth
local function GetEnemyNameTextSize()
    -- Returns the font size of the top text slot (used for stacking gap calculations)
    return (p and p.textSlotTopSize) or defaultSet.textSlotTopSize or 10
end
mod.GetEnemyNameTextSize = GetEnemyNameTextSize
local function GetDebuffTextColor()
    local color = (p and p.debuffTimerColor) or defaultSet.debuffTimerColor
    return color.r, color.g, color.b, 1
end
mod.GetDebuffTextColor = GetDebuffTextColor

-- Nameplate glow styles (Pandemic, Dispel, Important Cast) in their saved
-- order: a view over the shared styles without Shape Glow (1 Pixel, 2 Action
-- Button, 3 Auto-Cast, 4 GCD, 5 Modern, 6 Classic). scale/previewScale are
-- nameplate preview-only fields layered over the shared entries.
mod.NP_GLOW_VIEW = CludesUI.Glows.MakeView({ 1, 2, 3, 5, 6, 7 }, {
    [2] = { scale = 1.36, previewScale = 1.28 },
    [4] = { scale = 1.47, previewScale = 1.47 },
    [5] = { scale = 1.34, previewScale = 1.34 },
    [6] = { scale = 1.47, previewScale = 1.47 },
})
local PANDEMIC_GLOW_STYLES = mod.NP_GLOW_VIEW.list
mod.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
-- Exposed cross-addon (e.g. CDM "Apply Pandemic Glow to all" sync) so styles translate by NAME,
-- never raw index: this list omits "Custom Shape Glow", so the same index differs per side.
if CludesUI then CludesUI.NameplatePandemicGlowStyles = PANDEMIC_GLOW_STYLES end

-- PANDEMIC_GLOW_STYLES index -> shared CludesUI.Glows.STYLES index.
mod.NP_TO_SHARED_GLOW = mod.NP_GLOW_VIEW.toShared

-- Pandemic Glow style of a nameplate profile. A style picked from 9.6 on is
-- pandemicGlowPick. Without one, the key from before 9.6 is read as a view:
-- its old default (Pixel, 1) and nil mean Blizzard Pandemic Border, any other
-- value is that pick (stored profiles and old profile strings can hold the old
-- default written out, and must keep the border). Cross-addon for the CDM
-- "Apply Pandemic Glow to all" sync.
local function PandemicStyleOf(np)
    local pick = np and np.pandemicGlowPick
    if type(pick) == "number" then return pick end
    local old = np and np.pandemicGlowStyle
    if type(old) ~= "number" or old == 1 then return CludesUI.Glows.PANDEMIC_BORDER end
    return old
end
CludesUI.NameplatePandemicStyle = PandemicStyleOf
local function GetPandemicGlowStyle() return PandemicStyleOf(p) end
mod.GetPandemicGlowStyle = GetPandemicGlowStyle
local function GetPandemicGlowLines() return (p and p.pandemicGlowLines) or defaultSet.pandemicGlowLines end
mod.GetPandemicGlowLines = GetPandemicGlowLines
local function GetPandemicGlowThickness()
    return (p and p.pandemicGlowThickness) or defaultSet.pandemicGlowThickness
end
mod.GetPandemicGlowThickness = GetPandemicGlowThickness
local function GetPandemicGlowSpeed() return (p and p.pandemicGlowSpeed) or defaultSet.pandemicGlowSpeed end
mod.GetPandemicGlowSpeed = GetPandemicGlowSpeed
function mod.GetPandemicGlow()
    local val = p and p.pandemicGlow
    if val == nil then val = defaultSet.pandemicGlow end
    return val == true
end
-- Full render spec for the pandemic glow (live debuff glow and its preview).
-- An unset color mode is Custom: the swatch color this glow always drew.
-- Blizzard Pandemic Border (CludesUI.Glows.PANDEMIC_BORDER) sits outside
-- the view and is always drawn untinted.
function mod.GetPandemicGlowSpec(result)
    result = result or {}
    local position = GetPandemicGlowStyle()
    if position == CludesUI.Glows.PANDEMIC_BORDER then
        result.style = position
        result.r, result.g, result.b = nil, nil, nil
    else
        result.style = mod.NP_TO_SHARED_GLOW[position] or 1
        local color = (p and p.pandemicGlowColor) or defaultSet.pandemicGlowColor
        result.r, result.g, result.b =
            CludesUI.Glows.ResolveColor((p and p.pandemicGlowMode) or "custom", color.r, color.g, color.b)
    end
    result.lines = GetPandemicGlowLines()
    result.thickness = GetPandemicGlowThickness()
    result.speed = GetPandemicGlowSpeed()
    local bgc = (p and p.pandemicGlowBackgroundColor) or defaultSet.pandemicGlowBackgroundColor
    result.bg = (p and p.pandemicGlowBackground == true) or nil
    result.bgR, result.bgG, result.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
    return result
end

-- Offensive dispel capability: the shared parent detector (AuraKit), which
-- asks what the PLAYER knows, never what an aura is, so it keeps working in
-- restricted content.
do
    local AKd = CludesUI.AuraKit
    -- Capability picks the buff row's candidate filter, so a change has to
    -- rebuild the containers, not merely repaint them.
    AKd.OnOffensiveDispelChange(function()
        if mod.NPC_ReloadAll then mod.NPC_ReloadAll() end
    end)

    -- canDispelMagic, canDispelEnrage. Consumed by the buff row to pick its
    -- candidate filter and by the glow gate.
    mod.GetOffensiveDispelTypes = function() return AKd.OffensiveDispelTypes() end

    mod.GetDispelGlow = function() return (p and p.dispelGlow) or defaultSet.dispelGlow end
    mod.GetDispelGlowStyle = function()
        -- The same view as the Pandemic Glow's: dispelGlowPick holds a style
        -- picked from 9.6 on; without one, the key from before 9.6 with its
        -- old default (Action Button Glow, 2) or nil means Blizzard Pandemic
        -- Border, and any other value is that pick.
        local raw = p and p.dispelGlowPick
        if raw == nil then
            raw = p and p.dispelGlowStyle
            if raw == nil or raw == 2 then return CludesUI.Glows.PANDEMIC_BORDER end
        end
        -- Out-of-range picks read (and render) as Action Button Glow; Blizzard
        -- Border and Blizzard Pandemic Border sit outside the view.
        if
            type(raw) == "number"
            and (
                raw == CludesUI.Glows.STEALABLE_BORDER
                or raw == CludesUI.Glows.PANDEMIC_BORDER
                or (raw >= 1 and raw <= #mod.NP_GLOW_VIEW.list)
            )
        then
            return raw
        end
        return 2
    end
    -- Per-type colors. The buff row is split into a Magic group and a
    -- non-Magic (enrage) group, so the type is a property of the GROUP and
    -- resolves once at style-build time -- no per-aura read, which is what
    -- made the old ColorMixin-per-aura version impossible under 12.1.
    local TYPE_COLOR = {
        magic = { r = 0.2, g = 0.6, b = 1.0 },
        enrage = { r = 1.0, g = 0.2, b = 0.2 },
    }
    function mod.GetDispelGlowUseTypeColor()
        local val = p and p.dispelGlowUseTypeColor
        if val == nil then val = defaultSet.dispelGlowUseTypeColor end
        return val == true
    end
    -- dispelType is "magic", "enrage", or nil for the undifferentiated row.
    mod.GetDispelGlowColor = function(dispelType)
        if dispelType and mod.GetDispelGlowUseTypeColor() then
            local color = TYPE_COLOR[dispelType]
            if color then return color.r, color.g, color.b end
        end
        -- Never customized = "default": no tint request (nil), the suite's
        -- default look (gold). An explicit swatch pick is stored and honored.
        local color = p and p.dispelGlowColor
        local modeName = (p and p.dispelGlowColorMode) or (color and "custom" or "default")
        return CludesUI.Glows.ResolveColor(modeName, color and color.r, color and color.g, color and color.b)
    end
    -- Full render spec for the dispel glow (live purge glow and its preview).
    mod.GetDispelGlowSpec = function(dispelType, result)
        result = result or {}
        local position = mod.GetDispelGlowStyle()
        -- Blizzard Border sits outside the view and keeps Blizzard's own art
        -- until a colour is picked (ns.GetDispelBorderColor); Blizzard
        -- Pandemic Border is always drawn untinted.
        if position == CludesUI.Glows.STEALABLE_BORDER then
            result.style = position
            result.r, result.g, result.b = mod.GetDispelBorderColor(dispelType)
        elseif position == CludesUI.Glows.PANDEMIC_BORDER then
            result.style = position
            result.r, result.g, result.b = nil, nil, nil
        else
            result.style = mod.NP_TO_SHARED_GLOW[position] or 2
            result.r, result.g, result.b = mod.GetDispelGlowColor(dispelType)
        end
        result.lines = p and p.dispelGlowLines
        result.thickness = p and p.dispelGlowThickness
        result.speed = p and p.dispelGlowSpeed
        local bgc = p and p.dispelGlowBackgroundColor
        result.bg = (p and p.dispelGlowBackground == true) or nil
        result.bgR, result.bgG, result.bgB = bgc and bgc.r, bgc and bgc.g, bgc and bgc.b
        return result
    end
    -- Blizzard Border tint: the glow colour, except the untouched default gold
    -- (the profile merge fills the key, so it is compared, not nil-tested)
    -- keeps Blizzard's own stealable art. Per-type colours always tint.
    mod.GetDispelBorderColor = function(dispelType)
        local red, green, blue = mod.GetDispelGlowColor(dispelType)
        if dispelType and mod.GetDispelGlowUseTypeColor() then return red, green, blue end
        local skinData = defaultSet.dispelGlowColor
        if red == nil or (skinData and red == skinData.r and green == skinData.g and blue == skinData.b) then
            return nil, nil, nil
        end
        return red, green, blue
    end
end
local function GetCastBarHeight() return (p and p.castBarHeight) or defaultSet.castBarHeight end
mod.GetCastBarHeight = GetCastBarHeight
local function GetFocusCastHeight() return (p and p.focusCastHeight) or defaultSet.focusCastHeight end
mod.GetFocusCastHeight = GetFocusCastHeight
local function GetShowCastIcon()
    if p and p.showCastIcon ~= nil then return p.showCastIcon end
    return defaultSet.showCastIcon
end
mod.GetShowCastIcon = GetShowCastIcon
local function GetCastIconScale() return (p and p.castIconScale) or defaultSet.castIconScale end
mod.GetCastIconScale = GetCastIconScale
-- "Make Icon Part of the Bar": bar shifts right and narrows by the icon width so the icon
-- (anchored to the bar's left edge) sits inside the footprint instead of hanging off it.
function mod.GetCastIconInWidth()
    if p and p.castbarIconInWidth ~= nil then return p.castbarIconInWidth end
    return defaultSet.castbarIconInWidth
end
-- "Icon on Right": place the cast spell icon on the right of the bars.
function mod.GetCastIconOnRight()
    if p and p.castIconOnRight ~= nil then return p.castIconOnRight end
    return defaultSet.castIconOnRight
end
-- "Full Sized": icon is a square the combined height of the health + cast bar,
-- flush from the top of the health bar to the bottom of the cast bar.
function mod.GetCastIconFullSize()
    if p and p.castIconFullSize ~= nil then return p.castIconFullSize end
    return defaultSet.castIconFullSize
end
local function GetHideEnemyNameWhileCasting()
    if p and p.hideEnemyNameWhileCasting ~= nil then return p.hideEnemyNameWhileCasting end
    return defaultSet.hideEnemyNameWhileCasting
end

-- Position + size the cast bar within `footprintW` per the icon-in-width setting. A full-size
-- icon spans the health band too (which the cast bar cannot reserve), so in-width applies only
-- at normal size. Left icon: shift bar right into the reserved gap; right icon: fix left edge,
-- narrow only the right. iconW = castH * icon scale (rendered size).
function mod.LayoutCastBar(backing, footprintW, castH)
    local iconW = 0
    local shiftX = 0
    local wid = footprintW
    local classic = mod.NP_Classic()
    -- Cast Bar Y Offset: + up, - down; `or` fallback only fires when nil (0 is truthy in Lua).
    local offsetY = (p and p.castBarOffsetY) or defaultSet.castBarOffsetY
    if classic then
        -- Classic WoW UI: the vanilla cast border hangs under the health
        -- border with its icon plate under the health border's plain end,
        -- so the bar shifts right by the two plates' difference, keeps the
        -- footprint (widened by that difference when the bars' heights
        -- differ) and sits the stock gap lower; the icon rides in the plate.
        local drop
        shiftX, wid, drop = mod.NP_ClassicCastLayout(footprintW, GetHealthBarHeight(), castH)
        offsetY = offsetY + drop
    elseif GetShowCastIcon() and mod.GetCastIconInWidth() and not mod.GetCastIconFullSize() then
        iconW = castH * (GetCastIconScale() or 1)
        if not mod.GetCastIconOnRight() then shiftX = iconW end
    end
    backing.cast:ClearAllPoints()
    backing.cast:SetSize(math.max(1, wid - iconW), castH)
    -- Snap to whole physical pixels at the plate's own scale (nameplates have their own scale
    -- stack, not UIParent's) so the health-bottom/cast-top gap stays constant instead of
    -- oscillating +/-1px as the plate slides to fractional screen positions.
    if offsetY ~= 0 and Pix then
        local plateES = backing:GetEffectiveScale()
        local onePx = (plateES and plateES > 0) and (Pix.perfect / plateES) or (Pix.mult or 1)
        offsetY = math.floor(offsetY / onePx + 0.5) * onePx
    end
    backing.cast:SetPoint("TOPLEFT", backing.health, "BOTTOMLEFT", shiftX, offsetY)
    -- The cast bar's bottom edge below the health bar's: the bottom text slots
    -- drop by this while a cast shows (PlaceSlotText). Clamped at 0, so a cast
    -- bar raised above the health bar never lifts them.
    backing._castDrop = math.min(0, offsetY - castH)
    if mod._npBottomUsed and backing.AnchorBottomTexts and backing.cast:IsShown() then
        backing:AnchorBottomTexts()
    end
    if classic then mod.NP_ApplyClassicCastArt(backing, castH) end
end

-- Size + anchor the cast spell icon; always square. Normal: cast-bar height, hangs off the
-- bar's left (default) or right edge, top-aligned, scaled by Scale. Full: a (healthH + castH)
-- square anchored to a cast BOTTOM corner (top flush with health top) with scale forced to 1
-- to stay flush to both edges. Frame level fixed at creation (health+1), never touched here.
function mod.LayoutCastIcon(backing, castH)
    local iconTex = backing.castIconFrame
    local onRight = mod.GetCastIconOnRight()
    local xOff = (p and p.castIconOffsetX) or defaultSet.castIconOffsetX
    local yOff = (p and p.castIconOffsetY) or defaultSet.castIconOffsetY
    iconTex:ClearAllPoints()
    if mod.NP_Classic() then
        -- Classic WoW UI: the icon in the vanilla cast border's plate, a
        -- fixed square at the plate's centre (the border's middle sits half
        -- a sheet row under the bar's); the offsets still nudge it.
        local C = mod.NP_CLASSIC
        local ix, iy = mod.NP_ClassicIconOffset(castH)
        iconTex:SetScale(1)
        iconTex:SetSize(C.icon * castH, C.icon * castH)
        iconTex:SetPoint("CENTER", backing.cast, "LEFT", ix + xOff, iy + yOff)
        return
    end
    if mod.GetCastIconFullSize() then
        local edgeSide = GetHealthBarHeight() + castH
        iconTex:SetScale(1)
        -- Link the icon's three shared edges DIRECTLY to the bar edges (top=health top,
        -- bottom=cast bottom, inner side=bars' outer edge) instead of deriving from its own
        -- size: anchored to the same points the health/cast borders use, they pixel-snap
        -- together and shift as ONE unit instead of rounding independently. SetWidth keeps it
        -- square (height is fixed by the top/bottom anchors = side).
        iconTex:SetWidth(edgeSide)
        if onRight then
            iconTex:SetPoint("TOPLEFT", backing.health, "TOPRIGHT", xOff, yOff)
            iconTex:SetPoint("BOTTOMLEFT", backing.cast, "BOTTOMRIGHT", xOff, yOff)
        else
            iconTex:SetPoint("TOPRIGHT", backing.health, "TOPLEFT", xOff, yOff)
            iconTex:SetPoint("BOTTOMRIGHT", backing.cast, "BOTTOMLEFT", xOff, yOff)
        end
    else
        iconTex:SetScale(GetCastIconScale() or 1)
        iconTex:SetSize(castH, castH)
        if onRight then
            iconTex:SetPoint("TOPLEFT", backing.cast, "TOPRIGHT", xOff, yOff)
        else
            iconTex:SetPoint("TOPRIGHT", backing.cast, "TOPLEFT", xOff, yOff)
        end
    end
end

-- How far the cast icon protrudes past the bar edge, plus that side ("left"/"right"). The
-- target arrows and the side-slot elements step out by it (ns.NP_SideIconPush,
-- ns.NP_FullIconPush) so they never land under the icon. Returns
-- 0 for left/normal and in-width-tucked icons. Optional `plate` matters only for the full-size
-- icon (a cast-bar child rendered only during a cast): its reserve is gated on the cast bar
-- being shown; a settings-only query (no plate) assumes the space is reserved.
function mod.GetCastIconReserve(backing)
    if not GetShowCastIcon() then return 0, nil end
    -- Classic WoW UI seats the icon inside the cast border's own plate, which
    -- ns.NP_ClassicBarReserve already accounts for, so a stored Icon on Right
    -- or Full Sized reserves a gap nothing occupies there.
    if mod.NP_Classic() then return 0, nil end
    local onRight = mod.GetCastIconOnRight()
    local edgeSide = onRight and "right" or "left"
    if mod.GetCastIconFullSize() then
        -- Reserve the full-size icon's footprint only while visible (cast bar up), so side
        -- elements sit flush against the bar when idle instead of shoved out by a phantom gap.
        if backing and backing.cast and not backing.cast:IsShown() then return 0, edgeSide end
        return GetHealthBarHeight() + GetCastBarHeight(), edgeSide
    end
    if onRight and not mod.GetCastIconInWidth() then
        return GetCastBarHeight() * (GetCastIconScale() or 1), edgeSide
    end
    return 0, edgeSide
end

-- Whether an element beside the bars meets the full-size cast icon. The element spans y0..y1
-- above the health bar's bottom; the icon runs from the health bar's top (barH) down to the
-- cast bar's bottom (castBottom, from the health bar's bottom), both moved by its Y offset.
-- The options preview passes its own bar measures.
function mod.NP_MeetsFullIcon(y0, y1, barHeight, castBottom)
    local iy = (p and p.castIconOffsetY) or defaultSet.castIconOffsetY or 0
    return y0 < barHeight + iy and castBottom + iy < y1
end

-- The full-size cast icon's push on `side` for an element spanning y0..y1 above the health
-- bar's bottom: the icon's width while it shows there (a cast is up) and the two meet, else 0,
-- so an element its slot's Y offset moved clear of the icon stays put.
function mod.NP_FullIconPush(backing, edgeSide, y0, y1)
    if not mod.GetCastIconFullSize() then return 0 end
    local res, iconSide = mod.GetCastIconReserve(backing)
    if res <= 0 or iconSide ~= edgeSide then return 0 end
    if mod.NP_MeetsFullIcon(y0, y1, GetHealthBarHeight(), backing._castDrop or -GetCastBarHeight()) then
        return res
    end
    return 0
end

-- How far an icon in a side slot (raid marker, classification, faction, Quest Objective Text;
-- the target arrows too) steps out on `side`. It centres on the bar plus y and is sz tall.
-- The normal-size cast icon's reserve always applies, the full-size icon's only where the two
-- meet; plus Classic WoW UI's border reach or WoW Forever's level box (ns.NP_ClassicSide).
function mod.NP_SideIconPush(backing, edgeSide, posY, sz)
    local push
    if mod.GetCastIconFullSize() then
        local mid = GetHealthBarHeight() / 2 + posY
        push = mod.NP_FullIconPush(backing, edgeSide, mid - sz / 2, mid + sz / 2)
    else
        local res, iconSide = mod.GetCastIconReserve(backing)
        push = (iconSide == edgeSide) and res or 0
    end
    return push + mod.NP_ClassicSide(edgeSide)
end
local function GetKickTickEnabled()
    if p and p.kickTickEnabled ~= nil then return p.kickTickEnabled end
    return true
end
mod.GetKickTickEnabled = GetKickTickEnabled
local function GetKickTickColor()
    local color = (p and p.kickTickColor) or defaultSet.kickTickColor
    return color.r, color.g, color.b
end
mod.GetKickTickColor = GetKickTickColor
-- Optional element ("debuffs", "buffs", "ccs") selects per-element spacing; no arg
-- falls back to the global auraSpacing. One function, not two locals (200-local cap).
local function GetAuraSpacing(part)
    if part == "debuffs" then
        return (p and p.debuffSpacing) or defaultSet.debuffSpacing
    elseif part == "buffs" then
        return (p and p.buffSpacing) or defaultSet.buffSpacing
    elseif part == "ccs" then
        return (p and p.ccSpacing) or defaultSet.ccSpacing
    end
    return (p and p.auraSpacing) or defaultSet.auraSpacing
end
mod.GetAuraSpacing = GetAuraSpacing
local function GetDebuffYOffset() return (p and p.debuffYOffset) or defaultSet.debuffYOffset end
mod.GetDebuffYOffset = GetDebuffYOffset
local function GetSideAuraXOffset() return (p and p.sideAuraXOffset) or defaultSet.sideAuraXOffset end
mod.GetSideAuraXOffset = GetSideAuraXOffset
local function GetRaidMarkerPos() return (p and p.raidMarkerPos) or defaultSet.raidMarkerPos end
mod.GetRaidMarkerPos = GetRaidMarkerPos
-- Core Positions element sizes: ns.NP_ElementSize (below, beside the slot getters).
local function GetRaidMarkerSize() return mod.NP_ElementSize("raidmarker") end
mod.GetRaidMarkerSize = GetRaidMarkerSize
local function GetRaidMarkerYOffset() return 0 end
mod.GetRaidMarkerYOffset = GetRaidMarkerYOffset
local function GetClassificationSlot() return (p and p.classificationSlot) or defaultSet.classificationSlot end
mod.GetClassificationSlot = GetClassificationSlot
-- The Elite/Rare Indicator's size (the quest icon has its own: ns.NP_ElementSize("quest")).
local function GetRareEliteIconSize() return mod.NP_ElementSize("rare") end
mod.GetRareEliteIconSize = GetRareEliteIconSize
-- Faction badge slot and size. With "Rare/Quest + Faction" the badge rides the
-- classification slot.
function mod.NP_GetFactionSlot()
    if p and p.classificationIncludeFaction then return GetClassificationSlot() end
    return (p and p.factionSlot) or defaultSet.factionSlot
end
function mod.NP_GetFactionIconSize() return mod.NP_ElementSize("faction") end
function mod.NP_GetFactionStyle() return (p and p.factionStyle) or defaultSet.factionStyle end
-- Which faction badge a unit gets: its faction ("Horde"/"Alliance", drawn with
-- CludesUI.SetFactionArt in the Icon Style) and whether to dim it, or nil for none.
-- Neutral units and unreadable (secret) values show nothing; an unreadable PvP flag
-- counts as flagged, so nothing is hidden or greyed on a guess. Faction NPCs count
-- unless Players Only is on. Art matches Blizzard's Forever target frame badge.
function mod.NP_FactionBadge(unitToken)
    if not unitToken or mod.NP_GetFactionSlot() == "none" then return nil end
    -- Both toggles default off, so an unset key reads the same as its default.
    if p and p.factionPlayersOnly then
        local isPlayer = UnitIsPlayer(unitToken)
        if issecretvalue(isPlayer) or not isPlayer then return nil end
    end
    local fac = UnitFactionGroup(unitToken)
    if issecretvalue(fac) or (fac ~= "Horde" and fac ~= "Alliance") then return nil end
    if p and p.factionOppositeOnly then
        local mine = UnitFactionGroup("player")
        if issecretvalue(mine) then return nil end
        -- Mercenary mode: the player fights for the other faction.
        if UnitIsMercenary("player") then
            if mine == "Horde" then
                mine = "Alliance"
            elseif mine == "Alliance" then
                mine = "Horde"
            end
        end
        if mine == fac then return nil end
    end
    local dim = false
    local pvpMode = (p and p.factionPvP) or defaultSet.factionPvP
    if pvpMode ~= "ignore" then
        local pvp = UnitIsPVP(unitToken)
        local unflagged = not issecretvalue(pvp) and not pvp
        if unflagged and pvpMode == "only" then return nil end
        dim = unflagged and pvpMode == "dim"
    end
    return fac, dim
end
local function GetNameYOffset() return (p and p.nameYOffset) or defaultSet.nameYOffset end
mod.GetNameYOffset = GetNameYOffset
local textSlots = {
    "textSlotTop",
    "textSlotRight",
    "textSlotLeft",
    "textSlotCenter",
    "textSlotBottomLeft",
    "textSlotBottomRight",
    "textSlotTopLeft",
    "textSlotTopRight",
}
mod.textSlotKeys = textSlots
-- The slots that share the bar's line for the name-width estimate.
mod._npBarTextKeys = { "textSlotRight", "textSlotLeft", "textSlotCenter" }

local function GetTextSlot(slotName) return (p and p[slotName]) or defaultSet[slotName] end
mod.GetTextSlot = GetTextSlot

local function FindSlotForElement(part)
    for _, layoutKey in ipairs(textSlots) do
        if GetTextSlot(layoutKey) == part then return layoutKey end
    end
    return nil
end
mod.FindSlotForElement = FindSlotForElement

-- The four combined health-text elements (percent + number, either order, "|" or "-"
-- separator). One set so every eligibility check treating them as one category stays in sync.
local COMBO_HEALTH_ELEMENTS = {
    healthPctNum = true,
    healthNumPct = true,
    healthPctNumDash = true,
    healthNumPctDash = true,
    healthNumMax = true, -- current / max number; no percent
}
local function IsComboHealthText(part) return COMBO_HEALTH_ELEMENTS[part] == true end
mod.IsComboHealthText = IsComboHealthText

local function SetCombinedHealthText(fontStr, part, pctText, numText, maxText)
    if part == "healthNumMax" then
        fontStr:SetFormattedText("%s / %s", numText, maxText or "")
    elseif part == "healthPctNum" then
        fontStr:SetFormattedText("%s | %s", pctText, numText)
    elseif part == "healthNumPct" then
        fontStr:SetFormattedText("%s | %s", numText, pctText)
    elseif part == "healthPctNumDash" then
        fontStr:SetFormattedText("%s - %s", pctText, numText)
    elseif part == "healthNumPctDash" then
        fontStr:SetFormattedText("%s - %s", numText, pctText)
    else
        fontStr:SetText("")
    end
end
mod.SetCombinedHealthText = SetCombinedHealthText

-- Name-family text elements: display variants rendered by the plate's single name FontString
-- (enemy name and level+name combos). Exactly one may occupy a slot at a time (enforced by the
-- options-side slot assignment). STANDALONE level is deliberately NOT in the family: it renders
-- on its own FontString (plate.levelText, via health-text slot machinery) so name and level can
-- occupy different slots. do/end + ns funcs: no new locals (cap).
do
    local NAME_FAMILY = {
        enemyName = true,
        levelName = true,
        nameLevel = true,
    }
    -- Per slot: its Text Coloring key names (prebuilt, so reads build no strings) and
    -- the materialized Level | Name / Name | Level format strings (NP_RefreshSlotNameParts).
    local SK, PARTS = {}, {}
    local PLAIN = { ln = "%s | %s", nl = "%s | %s", diff = false }
    for i = 1, #textSlots do
        local text = textSlots[i]
        SK[text] = {
            mode = text .. "ColorMode",
            class = text .. "ClassColor",
            color = text .. "Color",
            nameOn = text .. "NameColorOn",
            name = text .. "NameColor",
            lvlOn = text .. "LevelColorOn",
            lvl = text .. "LevelColor",
            diff = text .. "LevelDiffOn",
        }
        PARTS[text] = { ln = PLAIN.ln, nl = PLAIN.nl, diff = false }
    end
    function mod.IsNameElement(part) return NAME_FAMILY[part] == true end
    -- Slot currently holding a name-family element (nil when none is slotted).
    -- db: a profile to read instead of the live one.
    function mod.FindNameSlot(saved)
        saved = saved or p
        for _, layoutKey in ipairs(textSlots) do
            if NAME_FAMILY[(saved and saved[layoutKey]) or defaultSet[layoutKey]] then return layoutKey end
        end
        return nil
    end
    -- A slot's Core Text Coloring mode: "custom" (the slot colour),
    -- "class" (Hostility / Class, painted per unit) or "level" (Level Difficulty, the
    -- unit's level difficulty colour; any text but Target of Target, which names
    -- another unit). An unset <slot>ColorMode is derived from keys read
    -- here and never written: levelDifficultyColor makes a standalone level "level";
    -- <slot>ClassColor, or enemyNameTextReactionColor on the first name slot, makes
    -- "class". The one place modes are derived. db: a profile to read instead of the
    -- live one.
    function mod.NP_SlotColorMode(slotName, saved)
        saved = saved or p or defaultSet
        local k = SK[slotName]
        if not k then return "custom" end
        local el = saved[slotName] or defaultSet[slotName]
        local m = saved[k.mode]
        if m == "class" or m == "custom" then return m end
        if m == "level" then return (el ~= "targetOfTarget") and "level" or "custom" end
        if el == "level" and saved.levelDifficultyColor == true then return "level" end
        if saved[k.class] == true then return "class" end
        if
            saved.enemyNameTextReactionColor == true
            and NAME_FAMILY[el]
            and mod.FindNameSlot(saved) == slotName
        then
            return "class"
        end
        return "custom"
    end
    -- Level | Name / Name | Level: the level part in the difficulty colour (applies
    -- while the slot's mode is not "level"). A custom level colour turns it off; unset
    -- follows levelDifficultyColor.
    function mod.NP_SlotLevelDiff(slotName, saved)
        saved = saved or p or defaultSet
        local k = SK[slotName]
        if not k then return false end
        if saved[k.lvlOn] == true then return false end
        local val = saved[k.diff]
        if val ~= nil then return val == true end
        return saved.levelDifficultyColor == true
    end
    -- A combo part's stored colour (part "name" or "level"), falling back to the slot
    -- colour; r, g, b. Whether it applies is <slot>NameColorOn / <slot>LevelColorOn.
    function mod.NP_SlotPartColor(slotName, part, saved)
        saved = saved or p or defaultSet
        local k = SK[slotName]
        if not k then return 1, 1, 1 end
        local color = saved[part == "level" and k.lvl or k.name] or saved[k.color] or defaultSet[k.color]
        if color then return color.r, color.g, color.b end
        return 1, 1, 1
    end
    -- Materializes every slot's combo format strings: a part with a custom colour is
    -- wrapped in its escape inside the format (the name stays a %s argument), and diff
    -- marks a level part drawn in the difficulty colour. Run by NP_RefreshSlotClassFlags.
    function mod.NP_RefreshSlotNameParts()
        local saved = p or defaultSet
        for i = 1, #textSlots do
            local s = textSlots[i]
            local k, frame = SK[s], PARTS[s]
            local nm, lv = "%s", "%s"
            if saved[k.nameOn] == true then
                nm = CludesUI.HexColor(mod.NP_SlotPartColor(s, "name", saved)) .. "%s|r"
            end
            if saved[k.lvlOn] == true then
                lv = CludesUI.HexColor(mod.NP_SlotPartColor(s, "level", saved)) .. "%s|r"
            end
            frame.ln = lv .. " | " .. nm
            frame.nl = nm .. " | " .. lv
            frame.diff = mod.NP_SlotColorMode(s, saved) ~= "level" and mod.NP_SlotLevelDiff(s, saved)
        end
    end
    -- r, g, b for a readable level: the skull's colour below 0, else the difficulty
    -- colour (nil when attackability or the player's level is secret). "player" is the
    -- options preview's stand-in mob, ranked as attackable like a hostile mob.
    -- friendly: rank friendly units by difficulty whatever levelDifficultyColorFriendly says.
    local function LevelRGB(unitToken, level, friendly)
        if level < 0 then return CludesUI.GetLevelDifficultyColor(-1) end
        return CludesUI.GetLevelColor(
            unitToken,
            level,
            friendly or unitToken == "player" or (p and p.levelDifficultyColorFriendly)
        )
    end
    -- The unit's level difficulty colour, r, g, b; nil while its level cannot be read.
    function mod.NP_UnitLevelColor(unitToken)
        local level = UnitEffectiveLevel(unitToken)
        if type(level) ~= "number" or (issecretvalue and issecretvalue(level)) then return nil end
        return LevelRGB(unitToken, level)
    end
    -- Display string for the unit's EFFECTIVE level (so scaling/Chromie time read as the game
    -- ranks them). "??" for skull-ranked (-1) or unreadable (secret) levels, matching default UI.
    -- color "diff" wraps it in the difficulty colour (an unreadable level stays a plain
    -- "??"); "diffAll" does too and ranks friendly units as well (the friendly player
    -- plates' Color Level by Difficulty); any other value returns it plain.
    function mod.GetUnitLevelText(unitToken, color)
        local level = UnitEffectiveLevel(unitToken)
        if type(level) ~= "number" or (issecretvalue and issecretvalue(level)) then return "??" end
        -- Forever: a hidden player level the PvP feature knows.
        if level < 0 and CludesUI.KnownHiddenLevel then
            level = CludesUI.KnownHiddenLevel(unitToken) or level
        end
        local txt = level < 0 and "??" or tostring(level)
        if color == "diff" or color == "diffAll" then
            return CludesUI.ColorText(txt, LevelRGB(unitToken, level, color == "diffAll"))
        end
        return txt
    end
    -- Write a name-family element's text into a FontString (shared by runtime update and
    -- options preview). name may be SECRET: only ever passed as a %s display arg, never inspected.
    -- slotKey (nil = FindNameSlot's) picks the combo's materialized part colours; the rest
    -- of the text keeps the font string's colour.
    function mod.SetNameElementText(fontStr, part, name, unitToken, slotName)
        if part == "levelName" or part == "nameLevel" then
            local frame = PARTS[slotName or mod.FindNameSlot()] or PLAIN
            local level = mod.GetUnitLevelText(unitToken, frame.diff and "diff")
            if part == "levelName" then
                fontStr:SetFormattedText(frame.ln, level, name)
            else
                fontStr:SetFormattedText(frame.nl, name, level)
            end
        elseif part == "level" then
            fontStr:SetFormattedText("%s", mod.GetUnitLevelText(unitToken))
        else
            fontStr:SetText(name)
        end
    end
    -- Name Format (text-slot cog): one word, initials or a Character Count;
    -- unset shows the name whole. Keys are prebuilt; the split and its cache
    -- live in CludesUI.ShortName. unit: whose name it is (on WoW Forever,
    -- First / Last Name leave a non-player's name whole; nil = the preview).
    do
        local NAME_FORMAT_KEYS = {
            textSlotTop = "textSlotTopNameFormat",
            textSlotRight = "textSlotRightNameFormat",
            textSlotLeft = "textSlotLeftNameFormat",
            textSlotCenter = "textSlotCenterNameFormat",
            textSlotBottomLeft = "textSlotBottomLeftNameFormat",
            textSlotBottomRight = "textSlotBottomRightNameFormat",
            textSlotTopLeft = "textSlotTopLeftNameFormat",
            textSlotTopRight = "textSlotTopRightNameFormat",
        }
        local short = CludesUI.ShortName
        function mod.NP_FormatName(name, slotName, unitToken)
            local layoutKey = slotName and NAME_FORMAT_KEYS[slotName]
            local modeName = layoutKey and p and p[layoutKey]
            if modeName then modeName = CludesUI.UnitNameFormat(modeName, unitToken) end
            if modeName then return short(name, modeName) end
            return name
        end
    end
end

-- Estimate pixel width of health text per element. Actual rendered widths are
-- unreadable (secret values), so use flat worst-case pixel assumptions.
local HEALTH_TEXT_PADDING = 10 -- safety margin in px
local healthTextWidths = {
    healthPercent = 38,
    healthPercentNoSign = 38,
    healthNumber = 38,
    healthPctNum = 75,
    healthNumPct = 75,
    healthPctNumDash = 75,
    healthNumPctDash = 75,
    healthNumMax = 75,
    level = 24, -- standalone level: "70" / "??"
    targetOfTarget = 60,
}
local function EstimateHealthTextWidth(part) return (healthTextWidths[part] or 0) + HEALTH_TEXT_PADDING end
mod.EstimateHealthTextWidth = EstimateHealthTextWidth

-- Custom text (element "custom"): any slot may show one, each with its own template
-- (<slot>CustomFormat) on its own font string (plate[ns.NP_CustomFSKey[slot]]), parsed by
-- CludesUI.TextTags against this binding of the unit schema. Pieces take (unit, slotKey)
-- and hand values only to format setters: health, absorb and names may be secret. A nil unit
-- is the options preview (the schema samples). do/end + ns funcs: no new locals (cap).
do
    local TT, scrollFrame, IsZeroValue = CludesUI.TextTags, string.format, CludesUI.IsZeroValue
    local FS_KEY, FORMAT_KEY = {}, {}
    for i = 1, #textSlots do
        local text = textSlots[i]
        FS_KEY[text] = "custom" .. text:sub(9) -- textSlotTop -> customTop
        FORMAT_KEY[text] = text .. "CustomFormat"
    end
    mod.NP_CustomFSKey = FS_KEY
    -- The unit's name as the name slot writes it (the slot's Name Format).
    local function Name(unit, slotName)
        local name = CludesUI.WithSurname(UnitName(unit))
        if type(name) == "nil" then return "" end
        return mod.NP_FormatName(name, slotName, unit)
    end
    -- Tag modifiers shape the plain name. They do not also apply the slot's Name Format.
    -- [name:last] and [target:last] show nothing for your own unit while your name is
    -- your first name alone (OwnSurnameHidden: WoW Forever, Blizzard's My Surname off).
    local function Shaped(modeName)
        return function(unit)
            if modeName == "last" and CludesUI.OwnSurnameHidden(unit) then return "" end
            local name = CludesUI.WithSurname(UnitName(unit))
            if type(name) == "nil" then return "" end
            return CludesUI.ShortName(name, modeName)
        end
    end
    local function TargetShaped(modeName)
        local piece = Shaped(modeName)
        return function(unit)
            local tu = mod._npToTUnits[unit]
            if not tu then
                tu = unit .. "target"
                mod._npToTUnits[unit] = tu
            end
            if not UnitExists(tu) then return "" end
            return piece(tu)
        end
    end
    local P = {
        ["hp"] = function(unit)
            if UnitIsDeadOrGhost(unit) then return CludesUI.L("DEAD") end
            return scrollFrame("%d", UnitHealth(unit) or 0)
        end,
        ["hp:abr"] = function(unit)
            if UnitIsDeadOrGhost(unit) then return CludesUI.L("DEAD") end
            return mod.AbbreviateValue(UnitHealth(unit) or 0, "health")
        end,
        ["hp:max"] = function(unit) return scrollFrame("%d", UnitHealthMax(unit) or 0) end,
        ["hp:max:abr"] = function(unit) return mod.AbbreviateValue(UnitHealthMax(unit) or 0, "maxHealth") end,
        ["hp:pct"] = function(unit)
            if UnitIsDeadOrGhost(unit) then return "0" end
            return scrollFrame("%d", UnitHealthPercent(unit, true, CurveConstants.ScaleTo100) or 0)
        end,
        ["absorb"] = function(unit) return C_StringUtil.TruncateWhenZero(UnitGetTotalAbsorbs(unit) or 0) end,
        ["absorb:abr"] = function(unit)
            local val = UnitGetTotalAbsorbs(unit) or 0
            if IsZeroValue(val) then return "" end
            return mod.AbbreviateValue(val, "absorb")
        end,
        ["name"] = Name,
        ["name:first"] = Shaped("first"),
        ["name:last"] = Shaped("last"),
        ["name:abbr"] = Shaped("abbr"),
        ["target"] = function(unit, slotName)
            local tu = mod._npToTUnits[unit]
            if not tu then
                tu = unit .. "target"
                mod._npToTUnits[unit] = tu
            end
            if not UnitExists(tu) then return "" end
            return Name(tu, slotName)
        end,
        ["target:first"] = TargetShaped("first"),
        ["target:last"] = TargetShaped("last"),
        ["target:abbr"] = TargetShaped("abbr"),
        ["level"] = function(unit) return mod.GetUnitLevelText(unit) end,
    }
    local CAT = TT.Bind(TT.UNIT, P)
    mod.NP_TextTags = CAT
    -- Weak both ways: each value points back at its key (c.parsed), which a weak-key
    -- table alone would never let go of in Lua 5.1. Plates hold what they paint.
    local compiled = setmetatable({}, { __mode = "kv" })
    local args = {}
    -- A slot's parsed template (nil while empty). db: a profile to read instead of the live one.
    function mod.NP_CustomParse(slotName, saved)
        saved = saved or p
        return TT.Parse(CAT, saved and saved[FORMAT_KEY[slotName]])
    end
    -- A slot's compiled template { fmt, n, reads, has, parsed, [i] = piece }, nil while
    -- empty. Built once per parse result.
    function mod.NP_CustomCompiled(slotName, saved)
        local parsed = mod.NP_CustomParse(slotName, saved)
        if not parsed then return nil end
        local c = compiled[parsed]
        if not c then
            local keyList = parsed.keys
            c = { fmt = parsed.fmt, n = #keyList, reads = parsed.reads, has = parsed.has, parsed = parsed }
            for i = 1, c.n do
                c[i] = P[keyList[i]]
            end
            compiled[parsed] = c
        end
        return c
    end
    -- One SetFormattedText per paint; unit nil paints the schema samples.
    function mod.NP_PaintCustom(fontStr, cfg, unitToken, slotName)
        if not unitToken then
            fontStr:SetText(TT.Preview(CAT, cfg.parsed))
            return
        end
        local num = cfg.n
        for i = 1, num do
            args[i] = cfg[i](unitToken, slotName)
        end
        fontStr:SetFormattedText(cfg.fmt, unpack(args, 1, num))
        -- An empty Top text (no target, no shield) keeps its line: the top aura row
        -- and the range text anchor to it. GetText reads nil while empty.
        if slotName == "textSlotTop" and not fontStr:GetText() then fontStr:SetText(" ") end
    end
    -- Estimated width of a slot's custom text, 0 while empty. db: as NP_CustomParse.
    function mod.NP_CustomWidth(slotName, saved)
        local parsed = mod.NP_CustomParse(slotName, saved)
        if not parsed then return 0 end
        return TT.EstimateWidth(CAT, parsed) + HEALTH_TEXT_PADDING
    end
    -- The bar width left to a name-like text in a bar slot: the bar minus the estimated
    -- widths of the other bar slots' texts (a name-family text at the schema's name width).
    -- db: a profile to read instead of the live one.
    function mod.NP_BarRestWidth(slotName, saved)
        saved = saved or p
        local wid = mod.GetHealthBarWidth()
        local barFrame = mod._npBarTextKeys
        for i = 1, #barFrame do
            local layoutKey = barFrame[i]
            if layoutKey ~= slotName then
                local el = (saved and saved[layoutKey]) or defaultSet[layoutKey]
                if el == "custom" then
                    wid = wid - mod.NP_CustomWidth(layoutKey, saved)
                elseif mod.IsNameElement(el) then
                    wid = wid - (TT.UNIT.keys.name.width + HEALTH_TEXT_PADDING)
                elseif el ~= "none" then
                    wid = wid - EstimateHealthTextWidth(el)
                end
            end
        end
        return wid
    end
end

local function GetHealthBarWidth()
    local extra = (p and p.healthBarWidth) or defaultSet.healthBarWidth
    return BAR_W + extra
end
mod.GetHealthBarWidth = GetHealthBarWidth

-- The Top Left / Top Right texts sit on the bar's top corners, at the Top text's
-- height. A Core Positions element on the same corner (the raid marker, the Rare/Quest
-- indicator, the Quest Objective Text, the faction badge, an aura row, the cast lockout)
-- rises by this to clear the text: the text's top above the bar, from its Size and Y offset
-- (0 while the corner shows no text). pos: "topleft" / "topright". db: a profile to read
-- instead of the live one.
do
    local CORNER_KEY = { topleft = "textSlotTopLeft", topright = "textSlotTopRight" }
    function mod.NP_TopCornerLift(place, saved)
        saved = saved or p
        local layoutKey = CORNER_KEY[place]
        if not layoutKey then return 0 end
        local el = (saved and saved[layoutKey]) or defaultSet[layoutKey]
        if not mod.NP_ElementFSKey(el, layoutKey) then return 0 end
        local size = (saved and saved[layoutKey .. "Size"]) or defaultSet[layoutKey .. "Size"] or 10
        local posY = (saved and saved[layoutKey .. "YOffset"]) or 0
        local nameY = (saved and saved.nameYOffset) or defaultSet.nameYOffset or 0
        return math.max(0, 4 + nameY + posY + size)
    end
    -- The estimated width of a top corner's text, 0 while it shows none (a Top name
    -- leaves room for the wider of the two on each side). db: as above.
    function mod.NP_TopCornerTextWidth(layoutKey, saved)
        saved = saved or p
        local el = (saved and saved[layoutKey]) or defaultSet[layoutKey]
        if el == "custom" then return mod.NP_CustomWidth(layoutKey, saved) end
        if not mod.NP_ElementFSKey(el, layoutKey) or mod.IsNameElement(el) then return 0 end
        return EstimateHealthTextWidth(el)
    end
end

-- Y offset for plate content relative to the nameplate frame. Always 0: the Blizzard nameplate
-- frame grows from its CENTER, not its base, so a taller SetNamePlateSize enlarges the hitbox
-- evenly above AND below the unit; anchoring content at the frame center needs no compensation.
local function GetHitboxYShift() return 0 end
mod.GetHitboxYShift = GetHitboxYShift
-- Slot-based size/offset getters. Key strings memoized per posKey (closed set of six literals,
-- lazy-filled) so these hot getters allocate nothing; VALUES still read live so profile swaps cannot stale.
mod._slotKeyMemo = mod._slotKeyMemo or {}
local function GetSlotKeys(placeKey)
    local m = mod._slotKeyMemo[placeKey]
    if not m then
        m = {
            size = placeKey .. "SlotSize",
            x = placeKey .. "SlotXOffset",
            y = placeKey .. "SlotYOffset",
        }
        mod._slotKeyMemo[placeKey] = m
    end
    return m
end
local function GetSlotSize(placeKey)
    local m = GetSlotKeys(placeKey)
    return (p and p[m.size]) or defaultSet[m.size] or 24
end
mod.GetSlotSize = GetSlotSize
local function GetSlotOffsets(placeKey)
    local m = GetSlotKeys(placeKey)
    local xOff = (p and p[m.x]) or defaultSet[m.x] or 0
    local yOff = (p and p[m.y]) or defaultSet[m.y] or 0
    return xOff, yOff
end
mod.GetSlotOffsets = GetSlotOffsets

-- Core Positions elements: the one place their sizes, their slots, the Quest Objective
-- Text view and the split Show In Instances keys are read. Elements are named by the
-- options' row keys (debuffs, buffs, ccs, raidmarker, rare, quest, questtext, faction).
-- Every function takes an optional db (a profile to read instead of the live one).
-- Plain table reads, no allocation. do/end + ns functions: no new main-chunk locals.
do
    -- Each element's own size (no defaults entry: unset follows the slot's size).
    local SIZE_KEY = {
        debuffs = "debuffCoreSize",
        buffs = "buffCoreSize",
        ccs = "ccCoreSize",
        raidmarker = "raidMarkerCoreSize",
        rare = "rareCoreSize",
        quest = "questCoreSize",
        faction = "factionCoreSize",
    }
    mod.NP_CORE_SIZE_KEY = SIZE_KEY
    -- Split Show In Instances keys (no defaults entry: unset follows
    -- classificationShowInInstances).
    local SII_KEY = {
        rare = "rareShowInInstances",
        quest = "questShowInInstances",
        questtext = "questTextShowInInstances",
    }
    mod.NP_SHOW_IN_INSTANCES_KEY = SII_KEY
    local SLOT_KEY = {
        debuffs = "debuffSlot",
        buffs = "buffSlot",
        ccs = "ccSlot",
        raidmarker = "raidMarkerPos",
        rare = "classificationSlot",
        quest = "classificationSlot",
        faction = "factionSlot",
    }
    -- The size an element has while its slot is None: its defaults key, else the literal.
    local NONE_KEY = {
        debuffs = "debuffIconSize",
        buffs = "buffIconSize",
        ccs = "ccIconSize",
        raidmarker = "raidMarkerSize",
        rare = "rareEliteIconSize",
        quest = "rareEliteIconSize",
    }
    local NONE_LAST =
        { debuffs = 26, buffs = 24, ccs = 24, raidmarker = 24, rare = 20, quest = 20, faction = 20 }
    -- The last fallback of a slot size with no defaults entry.
    local SLOT_LAST = { rare = 20, quest = 20, faction = 20 }

    local function ClassSlot(skinData)
        return (skinData and skinData.classificationSlot) or defaultSet.classificationSlot
    end
    local function HideQuest(skinData)
        local val = skinData and skinData.classificationHideQuest
        if val == nil then val = defaultSet.classificationHideQuest end
        return val and true or false
    end
    -- Quest Objective Text read from the legacy Replace Quest Icon with Objective key: no
    -- questTextSlot yet, Replace on and the Quest Indicator on in a slot. The text then
    -- takes the indicator's slot and the indicator reads off.
    local function Legacy(skinData)
        if skinData and skinData.questTextSlot ~= nil then return false end
        local region = skinData and skinData.replaceQuestIconWithObjective
        if region == nil then region = defaultSet.replaceQuestIconWithObjective end
        if region ~= true or ClassSlot(skinData) == "none" then return false end
        return not HideQuest(skinData)
    end
    local function QuestTextSlot(skinData)
        local val = skinData and skinData.questTextSlot
        if val ~= nil then return val end
        if Legacy(skinData) then return ClassSlot(skinData) end
        return "none"
    end
    local function ElementSlot(elem, skinData)
        if elem == "questtext" then return QuestTextSlot(skinData) end
        if elem == "faction" and skinData and skinData.classificationIncludeFaction then
            return ClassSlot(skinData)
        end
        local layoutKey = SLOT_KEY[elem]
        if not layoutKey then return "none" end
        return (skinData and skinData[layoutKey]) or defaultSet[layoutKey]
    end

    function mod.NP_LegacyQuestText(saved) return Legacy(saved or p) end
    function mod.NP_GetQuestTextSlot(saved) return QuestTextSlot(saved or p) end
    -- The Quest Indicator half of the Rare/Quest element is on.
    function mod.NP_QuestIconOn(saved)
        local skinData = saved or p
        if ClassSlot(skinData) == "none" or HideQuest(skinData) then return false end
        return not Legacy(skinData)
    end
    function mod.NP_ElementSlot(elem, saved) return ElementSlot(elem, saved or p) end
    -- An element's size: its own key, else the size of slot pos (default: its own slot),
    -- else that slot's default; while the slot is None, the element's own fallback.
    function mod.NP_ElementSize(elem, saved, place)
        local skinData = saved or p
        local layoutKey = SIZE_KEY[elem]
        local val = layoutKey and skinData and skinData[layoutKey]
        if type(val) == "number" then return val end
        place = place or ElementSlot(elem, skinData)
        if not place or place == "none" then
            local nk = NONE_KEY[elem]
            return (nk and defaultSet[nk]) or NONE_LAST[elem] or 24
        end
        local m = GetSlotKeys(place)
        return (skinData and skinData[m.size]) or defaultSet[m.size] or SLOT_LAST[elem] or 24
    end
    -- Show In Instances of kind "rare" / "quest" / "questtext".
    function mod.NP_ShowInInstances(kind, saved)
        local skinData = saved or p
        local layoutKey = SII_KEY[kind]
        local val = layoutKey and skinData and skinData[layoutKey]
        if val == nil then
            val = skinData and skinData.classificationShowInInstances
            if val == nil then val = defaultSet.classificationShowInInstances end
        end
        return val and true or false
    end
    function mod.NP_QuestTextSize(saved)
        local skinData = saved or p
        return (skinData and skinData.questObjectiveTextSize) or defaultSet.questObjectiveTextSize or 14
    end
    -- Writes the Quest Objective Text view into the profile before a change of the
    -- Elite/Rare, Quest or Quest Objective Text boxes: questTextSlot takes its effective
    -- value, and a profile read through the legacy key unchecks the Quest Indicator too.
    -- The legacy key is never read for the profile again.
    function mod.NP_MaterializeQuestText(saved)
        if not saved or saved.questTextSlot ~= nil then return end
        local legacy = Legacy(saved)
        saved.questTextSlot = legacy and ClassSlot(saved) or "none"
        if legacy then saved.classificationHideQuest = true end
    end
end

local function GetDebuffIconSize() return mod.NP_ElementSize("debuffs") end
mod.GetDebuffIconSize = GetDebuffIconSize
local function GetBuffIconSize() return mod.NP_ElementSize("buffs") end
mod.GetBuffIconSize = GetBuffIconSize
local function GetCCIconSize() return mod.NP_ElementSize("ccs") end
mod.GetCCIconSize = GetCCIconSize
-- Cropped aura icons (mirrors Unit Frames "Cropped Icons"). On: icon frame goes rectangular
-- (height = 80% of width), texture trimmed top/bottom so artwork is never squished; horizontal
-- zoom stays at the nameplate default (0.08). do/end + ns functions: no new main-chunk locals (cap).
do
    local AURA_CROP_HEIGHT = 0.80
    local AURA_ZOOM = 0.08
    -- Returns FALSE when uncropped, else the height FACTOR: 1 - 2*(cropPercent/100), so default
    -- 10% yields 0.80. Callers that only truth-test the result work unchanged.
    function mod.GetAuraCrop(part)
        local on, percent
        if part == "debuffs" then
            on = (p and p.debuffCropIcons) or defaultSet.debuffCropIcons
            percent = p and p.debuffCropPercent
        elseif part == "buffs" then
            on = (p and p.buffCropIcons) or defaultSet.buffCropIcons
            percent = p and p.buffCropPercent
        elseif part == "ccs" then
            on = (p and p.ccCropIcons) or defaultSet.ccCropIcons
            percent = p and p.ccCropPercent
        end
        if not on then return false end
        percent = tonumber(percent) or 10
        if percent < 5 then
            percent = 5
        elseif percent > 25 then
            percent = 25
        end
        return 1 - 2 * (percent / 100)
    end
    -- Frame height for an icon width: shorter when cropped, square when not. `cropped` is
    -- GetAuraCrop's result: a factor number, or plain true (falls back to AURA_CROP_HEIGHT).
    function mod.GetAuraCropHeight(cropped, wid)
        if cropped then
            local factor = (type(cropped) == "number") and cropped or AURA_CROP_HEIGHT
            return math.floor(wid * factor + 0.5)
        end
        return wid
    end
    -- Texcoord trim. Cropped scales the vertical span to the rectangle's aspect
    -- so the texture keeps its proportions; uncropped is the original square zoom.
    function mod.SetAuraIconCrop(iconTex, cropped, wid, hgt)
        if not iconTex then return end
        -- Stock styles draw the whole icon (zoom 0), as the engine cells do.
        local z = mod.NP_Blizz() and 0 or AURA_ZOOM
        if cropped and wid and hgt and wid > 0 then
            local uSpan = 1 - 2 * z
            local vSpan = uSpan * (hgt / wid)
            local v0 = 0.5 - vSpan / 2
            iconTex:SetTexCoord(z, 1 - z, v0, 1 - v0)
        else
            iconTex:SetTexCoord(z, 1 - z, z, 1 - z)
        end
    end
end
local function GetTargetGlowStyle()
    if p and p.targetGlowStyle then return p.targetGlowStyle end
    return defaultSet.targetGlowStyle
end
mod.GetTargetGlowStyle = GetTargetGlowStyle
-- Multi-toggle target glow model (CludesUI / Border Color / Highlight). Live conversion, NO
-- migration: each toggle returns its own stored key when set, else derives from targetGlowStyle
-- (stays in defaults so the fallback source is always present). Mapping: cludesui ->
-- CludesUI; vibrant -> CludesUI + Border Color; none -> nothing. On ns (local budget).
-- The WoW Forever style marks its target with Highlight alone: CUI Glow, Border
-- Color and Border Size read off there whatever the profile holds (the saved
-- choices stay for the other styles).
function mod.GetTargetGlowCludesUI()
    if mod.NP_Forever() then return false end
    if p and p.targetGlowCludesUI ~= nil then return p.targetGlowCludesUI end
    local style = (p and p.targetGlowStyle) or defaultSet.targetGlowStyle
    return style == "cludesui" or style == "vibrant"
end
function mod.GetTargetGlowBorderColor()
    if mod.NP_Forever() then return false end
    if p and p.targetGlowBorderColor ~= nil then return p.targetGlowBorderColor end
    local style = (p and p.targetGlowStyle) or defaultSet.targetGlowStyle
    return style == "vibrant"
end
function mod.GetTargetGlowHighlight()
    if p and p.targetGlowHighlight ~= nil then return p.targetGlowHighlight end
    return false -- no legacy equivalent
end
function mod.GetTargetGlowBorderSize()
    if mod.NP_Forever() then return false end
    if p and p.targetGlowBorderSize ~= nil then return p.targetGlowBorderSize end
    return false -- no legacy equivalent
end
-- nil until the effect's first enable snapshots the user's current border size (options side);
-- nil = applies nothing (fail-safe for imported partial profiles).
function mod.GetTargetBorderSizeValue()
    local val = p and p.targetBorderSizeValue
    return val
end
function mod.GetTargetBorderColor() return (p and p.targetBorderColor) or defaultSet.targetBorderColor end
function mod.GetTargetGlowColor() return (p and p.targetGlowColor) or defaultSet.targetGlowColor end
function mod.GetTargetGlowAlpha()
    local a = p and p.targetGlowAlpha
    if a == nil then return defaultSet.targetGlowAlpha end
    return a
end
function mod.GetTargetHighlightColor()
    return (p and p.targetHighlightColor) or defaultSet.targetHighlightColor
end
function mod.GetTargetHighlightAlpha()
    local a = p and p.targetHighlightAlpha
    if a == nil then return defaultSet.targetHighlightAlpha end
    return a
end
-- Hover Effect (mirrors the Target Effect model, user-directed 2026-08-16).
-- Highlight is the ONLY default-on channel and reuses the legacy
-- hoverColor/hoverAlpha keys as its color/opacity, so every existing AND new
-- profile renders EXACTLY the old flat hover highlight (including the alpha
-- 0 = invisible case) until other channels are opted in. New-channel colors
-- start from the target effect's defaults.
function mod.GetHoverGlowCludesUI() return (p and p.hoverGlowCludesUI) == true end
function mod.GetHoverGlowBorderColor() return (p and p.hoverGlowBorderColor) == true end
function mod.GetHoverGlowHighlight()
    if p and p.hoverGlowHighlight ~= nil then return p.hoverGlowHighlight == true end
    return true
end
function mod.GetHoverGlowBorderSize() return (p and p.hoverGlowBorderSize) == true end
-- nil until the effect's first enable snapshots the user's current border
-- size (options side); nil = applies nothing.
function mod.GetHoverBorderSizeValue() return p and p.hoverBorderSizeValue end
function mod.GetHoverBorderColor() return (p and p.hoverBorderColor) or defaultSet.targetBorderColor end
function mod.GetHoverGlowColor() return (p and p.hoverGlowColor) or defaultSet.targetGlowColor end
function mod.GetHoverGlowAlpha()
    local a = p and p.hoverGlowAlpha
    if a == nil then return defaultSet.targetGlowAlpha end
    return a
end
local function GetShowTargetGlow()
    return mod.GetTargetGlowCludesUI() or mod.GetTargetGlowBorderColor() or mod.GetTargetGlowHighlight()
end
mod.GetShowTargetGlow = GetShowTargetGlow
local function GetShowClassPower()
    if p and p.showClassPower ~= nil then return p.showClassPower end
    return defaultSet.showClassPower
end
mod.GetShowClassPower = GetShowClassPower
-- On ns, not file locals (Lua's 200-local limit); callers use ns.GetClassPower*().
mod.GetClassPowerPos = function() return (p and p.classPowerPos) or defaultSet.classPowerPos end
mod.GetClassPowerYOffset = function() return (p and p.classPowerYOffset) or defaultSet.classPowerYOffset end
mod.GetClassPowerXOffset = function() return (p and p.classPowerXOffset) or defaultSet.classPowerXOffset end
mod.GetClassPowerScale = function() return (p and p.classPowerScale) or defaultSet.classPowerScale end
mod.GetClassPowerGap = function() return (p and p.classPowerGap) or defaultSet.classPowerGap end
local function GetClassPowerClassColors()
    if p and p.classPowerClassColors ~= nil then return p.classPowerClassColors end
    return defaultSet.classPowerClassColors
end
mod.GetClassPowerClassColors = GetClassPowerClassColors
local function GetClassPowerCustomColor()
    local color = (p and p.classPowerCustomColor) or defaultSet.classPowerCustomColor
    return color
end
mod.GetClassPowerCustomColor = GetClassPowerCustomColor
mod.GetClassPowerBgColor = function()
    local color = (p and p.classPowerBgColor) or defaultSet.classPowerBgColor
    return color
end
mod.GetClassPowerEmptyColor = function()
    local color = (p and p.classPowerEmptyColor) or defaultSet.classPowerEmptyColor
    return color
end
-- On ns, not file locals (Lua's 200 main-chunk local limit).
function mod.GetClassPowerShape() return (p and p.classPowerShape) or defaultSet.classPowerShape end
function mod.GetClassPowerBorder()
    local val = p and p.classPowerBorder
    if val == nil then return defaultSet.classPowerBorder end
    return val
end
function mod.GetClassPowerBorderColor()
    return (p and p.classPowerBorderColor) or defaultSet.classPowerBorderColor
end
function mod.GetClassPowerBorderSize()
    return (p and p.classPowerBorderSize) or defaultSet.classPowerBorderSize
end
local function IsBorderEnabled()
    -- The stock styles carry their own art instead of an CUI border: the
    -- stock background art (Blizzard Style), the vanilla border sheets
    -- (Classic WoW UI, ns.NP_ApplyClassicHealthArt).
    if mod.NP_Blizz() then return false end
    local val = p and p.showBorder
    if val == nil then return defaultSet.showBorder end
    return val
end
mod.IsBorderEnabled = IsBorderEnabled
-- Per-icon 1px borders (cast / buff / debuff / CC). nil = border shown
-- (old profiles without the key keep their borders). Setting a hide key
-- to true hides the border; false shows it.
function mod.GetIconBorderEnabled(kind)
    -- Stock styles: the stock cast icon has no border, and the aura items
    -- carry the rounded ring overlay (Blizzard) or the stock dispel-type
    -- border (classic) instead of a 1px border.
    if mod.NP_Blizz() then return false end
    local layoutKey
    if kind == "cast" then
        layoutKey = "hideCastIconBorder"
    elseif kind == "debuffs" then
        layoutKey = "hideDebuffIconBorder"
    elseif kind == "buffs" then
        layoutKey = "hideBuffIconBorder"
    else
        layoutKey = "hideCCIconBorder"
    end
    local val = p and p[layoutKey]
    if val == nil then
        val = defaultSet[layoutKey]
        if val == nil then return true end -- no default at all: border shown
    end
    return not val
end
function mod.ApplyFrameIconBorder(widget, enabled, adjustIconInset)
    local Pix = CludesUI and CludesUI.PP
    if not (widget and Pix and Pix.GetBorders and Pix.GetBorders(widget)) then return end
    if enabled then
        if Pix.ShowBorder then Pix.ShowBorder(widget) end
    elseif Pix.HideBorder then
        Pix.HideBorder(widget)
    end
    -- Aura slots keep a 1px icon inset for the border; borderless fills the
    -- icon to the edge so no bare rim shows (matches the options preview).
    -- OPT-IN: the cast icon (inset 0 by design, border draws on top) and the
    -- lockout icon own their geometry and must not be re-anchored here.
    if adjustIconInset and widget.icon then
        local px = enabled and 1 or 0
        widget.icon:ClearAllPoints()
        Pix.Point(widget.icon, "TOPLEFT", widget, "TOPLEFT", px, -px)
        Pix.Point(widget.icon, "BOTTOMRIGHT", widget, "BOTTOMRIGHT", -px, px)
    end
end
function mod.NP_CanShowCastIconSeparator(saved)
    if
        not saved
        or saved.castbarIconInWidth ~= true
        or saved.showCastIcon == false
        or saved.castIconFullSize == true
        or mod.NP_Blizz()
    then
        return false
    end
    local texture = saved.customBorderTexture or defaultSet.customBorderTexture
    return (saved.customBorderSize or defaultSet.customBorderSize) > 0
        and (texture == "solid" or texture == "" or CludesUI.GetBorderCompanion(texture, "sepV") ~= nil)
end

-- Shared by live plates and the preview; the cast bar owns this lazy divider. It
-- does not follow the target or threat tint, so the border-colour passes that land
-- here (every threat repaint) change nothing: only a moved style input restyles it.
function mod.NP_ApplyCastIconSeparator(cast, iconTex, saved, customOn, strata)
    local seamTex = cast._iconSeam
    if
        not (
            saved
            and saved.castIconSeparator == true
            and customOn
            and mod.NP_CanShowCastIconSeparator(saved)
        )
    then
        if seamTex and seamTex:IsShown() then
            seamTex:Hide()
            CludesUI.RegisterPxReapply(seamTex, nil)
        end
        return
    end
    if not seamTex then
        seamTex = Pool.CreateFrame("Frame", nil, cast)
        seamTex:SetAllPoints(cast)
        seamTex:EnableMouse(false)
        seamTex._tex = seamTex:CreateTexture(nil, "OVERLAY", nil, 7)
        cast._iconSeam = seamTex
    end
    local st = strata or cast:GetFrameStrata()
    local level = iconTex:GetFrameLevel() + 5
    local layoutKey = saved.customBorderTexture or defaultSet.customBorderTexture
    local size = saved.customBorderSize or defaultSet.customBorderSize
    local px = CludesUI.BorderPx(saved.customBorderSizePx, size, layoutKey)
    local right = saved.castIconOnRight == true
    local color = saved.customBorderColor or defaultSet.customBorderColor
    local a = saved.customBorderAlpha or defaultSet.customBorderAlpha
    -- Restyle inputs: shown state, strata, level (a strata change resets it), texture,
    -- size step, exact px, side, the scale its width snaps to, and its colour.
    if
        seamTex:IsShown()
        and seamTex:GetFrameStrata() == st
        and seamTex:GetFrameLevel() == level
        and seamTex._key == layoutKey
        and seamTex._size == size
        and seamTex._px == px
        and seamTex._right == right
        and seamTex._es == seamTex:GetEffectiveScale()
        and seamTex._r == color.r
        and seamTex._g == color.g
        and seamTex._b == color.b
        and seamTex._a == a
    then
        return
    end
    seamTex:SetFrameStrata(st)
    seamTex:SetFrameLevel(level)
    seamTex._key, seamTex._size, seamTex._px, seamTex._right = layoutKey, size, px, right
    seamTex._r, seamTex._g, seamTex._b, seamTex._a = color.r, color.g, color.b, a
    seamTex._tex:SetVertexColor(color.r, color.g, color.b, a)
    mod.NP_LayoutCastIconSeparator(seamTex)
    seamTex:Show()
    CludesUI.RegisterPxReapply(seamTex, strata and mod.NP_LayoutCastIconSeparator or nil)
end

function mod.NP_LayoutCastIconSeparator(seamTex)
    local t, es = seamTex._tex, seamTex:GetEffectiveScale()
    seamTex._es = es
    if CludesUI.GetBorderCompanion(seamTex._key, "sepV") then
        CludesUI.PlaceBorderDividerV(
            t,
            seamTex,
            seamTex._right,
            false,
            seamTex._key,
            seamTex._size,
            seamTex._px,
            es
        )
        return
    end
    local onePixel = es > 0 and Pix.perfect / es or Pix.mult
    t:SetColorTexture(1, 1, 1, 1)
    t:SetTexCoord(0, 1, 0, 1)
    t:ClearAllPoints()
    local topY = seamTex._right and "TOPRIGHT" or "TOPLEFT"
    local bottom = seamTex._right and "BOTTOMRIGHT" or "BOTTOMLEFT"
    t:SetPoint(topY, seamTex, topY, 0, 0)
    t:SetPoint(bottom, seamTex, bottom, 0, 0)
    t:SetWidth(math.max(1, math.floor((seamTex._px or seamTex._size) + 0.5)) * onePixel)
    t:Show()
end

-- Every write of the cast spell icon's border goes through here. Custom Border on
-- Spell Icon (castIconCustomBorder, Border = Custom): the icon wears the plate's custom
-- border in place of its 1px edge. The border is our own frame, a child of the cast bar
-- laid over the icon rather than a child of the icon, whose Scale would multiply an
-- exact pixel size; so it rides Casts In Front of Nameplates with the bar but does not
-- hide with the icon, and turns off through ApplyBorderStyle(frame, 0) so the UI scale
-- re-apply cannot bring it back. MEDIUM strata lifts it out of the plate's flattened
-- layer above the icon art (the lift's strata while the cast bar is lifted). Style
-- inputs restyle only when one moved; a colour change (Use Target Border Color on the
-- target) is a plain tint. Off, this is the 1px edge call plus the opt-in gates.
function mod.ApplyCastIconBorder(backing)
    local iconTex = backing and backing.castIconFrame
    if not iconTex then return end
    if (p and p.castIconSeparator) or backing.cast._iconSeam then
        mod.NP_ApplyCastIconSeparator(
            backing.cast,
            iconTex,
            p,
            mod.IsCustomBorderEnabled(),
            backing._castOverlayLifted and backing.cast:GetFrameStrata() or "MEDIUM"
        )
    end
    local barFrame = backing._castIconBorder
    if
        not (
            p
            and p.castIconCustomBorder
            and mod.IsCustomBorderEnabled()
            and not mod.GetCastIconInWidth()
            and GetShowCastIcon()
            and mod.GetIconBorderEnabled("cast")
        )
    then
        if barFrame and barFrame:IsShown() then
            CludesUI.ApplyBorderStyle(barFrame, 0)
            barFrame:Hide()
        end
        mod.ApplyFrameIconBorder(iconTex, mod.GetIconBorderEnabled("cast"))
        return
    end
    mod.ApplyFrameIconBorder(iconTex, false)
    if not barFrame then
        barFrame = CreateFrame("Frame", nil, backing.cast)
        barFrame:SetAllPoints(iconTex)
        barFrame:EnableMouse(false)
        backing._castIconBorder = barFrame
    end
    local texture = p.customBorderTexture or defaultSet.customBorderTexture
    local sz = p.customBorderSize or defaultSet.customBorderSize
    local px = CludesUI.BorderPx(p.customBorderSizePx, sz, texture)
    local red, green, blue, a
    if p.castIconTargetBorder and backing._isTarget and mod.GetTargetGlowBorderColor() then
        local color = mod.GetTargetBorderColor()
        red, green, blue, a = color.r, color.g, color.b, 1
    else
        local color = p.customBorderColor or defaultSet.customBorderColor
        red, green, blue, a =
            color.r, color.g, color.b, p.customBorderAlpha or defaultSet.customBorderAlpha or 1
    end
    local strata = backing._castOverlayLifted and backing.cast:GetFrameStrata() or "MEDIUM"
    local level = iconTex:GetFrameLevel() + 3
    local offX, offY = p.customBorderOffset, p.customBorderOffsetY
    local shX, shY = p.customBorderShiftX, p.customBorderShiftY
    -- Restyle inputs: shown state, strata, level (a strata change resets it), texture,
    -- size step, exact px, both offsets and both shifts. Anything else is colour.
    if
        not barFrame:IsShown()
        or barFrame:GetFrameStrata() ~= strata
        or barFrame:GetFrameLevel() ~= level
        or barFrame._sTex ~= texture
        or barFrame._sSz ~= sz
        or barFrame._sPx ~= px
        or barFrame._sOX ~= offX
        or barFrame._sOY ~= offY
        or barFrame._sSX ~= shX
        or barFrame._sSY ~= shY
    then
        barFrame:SetFrameStrata(strata)
        barFrame:SetFrameLevel(level)
        CludesUI.ApplyBorderStyle(
            barFrame,
            sz,
            red,
            green,
            blue,
            a,
            texture,
            offX,
            offY,
            shX,
            shY,
            "nameplates",
            sz,
            nil,
            px
        )
        if Pix.GetBorders(barFrame) then
            Pix.CreateBorder(barFrame, nil, nil, nil, nil, nil, nil, nil, true)
        end
        barFrame._sTex, barFrame._sSz, barFrame._sPx = texture, sz, px
        barFrame._sOX, barFrame._sOY, barFrame._sSX, barFrame._sSY = offX, offY, shX, shY
    else
        CludesUI.SetBorderStyleColor(barFrame, red, green, blue, a)
    end
end
local function GetBorderColor()
    -- Classic WoW UI: the plate's edge is always black.
    if mod.NP_Classic() then return 0, 0, 0 end
    local color = (p and p.borderColor) or defaultSet.borderColor
    return color.r, color.g, color.b
end
mod.GetBorderColor = GetBorderColor
-- Health border size: the classic plate's fixed 1px edge, else the profile's
-- Border Size. Friendly plates mirror it.
function mod.NP_BorderSize()
    if mod.NP_Classic() then return 1 end
    return (p and p.borderSize) or defaultSet.borderSize
end
-- Cast bar border colour: black under Classic WoW UI, else the profile's.
function mod.NP_CastBorderColor()
    if mod.NP_Classic() then return 0, 0, 0 end
    local color = (p and p.castBorderColor) or defaultSet.castBorderColor
    return color.r, color.g, color.b
end
-- "Wrap Border Around Castbar". The cast-visibility hook reads this on every
-- cast show/hide, so it must stay a trivial table lookup.
function mod.GetWrapBorderCastbar()
    local val = p and p.wrapBorderCastbar
    if val == nil then return defaultSet.wrapBorderCastbar end
    return val
end
local function GetAuraSlots()
    local ds = (p and p.debuffSlot) or defaultSet.debuffSlot
    local bs = (p and p.buffSlot) or defaultSet.buffSlot
    local cs = (p and p.ccSlot) or defaultSet.ccSlot
    return ds, bs, cs
end
mod.GetAuraSlots = GetAuraSlots

-- Raise Strata: per-slot Core Positions toggle. On, the element in that slot is bumped
-- MEDIUM -> HIGH so it renders above the rest of the plate. On ns (local budget).
function mod.GetSlotRaiseStrata(placeKey)
    if not placeKey or placeKey == "none" then return false end
    local layoutKey = placeKey .. "SlotRaiseStrata"
    if p and p[layoutKey] ~= nil then return p[layoutKey] end
    return defaultSet[layoutKey] or false
end

-- Apply each slot's Raise Strata setting to its element frame. Frames otherwise share MEDIUM
-- strata; HIGH lifts that element above the flattened text/aura/indicator tiers, and its
-- children inherit it. The aura containers apply their own (AnchorNPContainer).
function mod.ApplySlotStrata(backing)
    if not backing then return end
    local function StrataFor(slotRec) return mod.GetSlotRaiseStrata(slotRec) and "HIGH" or "MEDIUM" end
    if backing.raidFrame then backing.raidFrame:SetFrameStrata(StrataFor(GetRaidMarkerPos())) end
    if backing.classFrame then backing.classFrame:SetFrameStrata(StrataFor(GetClassificationSlot())) end
    if backing.factionFrame then backing.factionFrame:SetFrameStrata(StrataFor(mod.NP_GetFactionSlot())) end
    if backing.questTextFrame then
        backing.questTextFrame:SetFrameStrata(StrataFor(mod.NP_GetQuestTextSlot()))
    end
end

-- Pandemic glow engine: procedural ants, button glow, autocast shine, FlipBook. do...end keeps
-- internal locals out of the main chunk's 200-local budget; externally-needed items stored on ns.
do
    -------------------------------------------------------------------------------
    --  Glow engines from shared CludesUI_Glows.lua; aliases for the wrapper below.
    -------------------------------------------------------------------------------
    local _G_Glows = CludesUI.Glows
    local StartProceduralAnts = _G_Glows.StartProceduralAnts
    local StopProceduralAnts = _G_Glows.StopProceduralAnts
    local StartButtonGlow = _G_Glows.StartButtonGlow
    local StopButtonGlow = _G_Glows.StopButtonGlow
    local StartAutoCastShine = _G_Glows.StartAutoCastShine
    local StopAutoCastShine = _G_Glows.StopAutoCastShine
    local StartGlow = _G_Glows.StartGlow
    local StopAllGlows = _G_Glows.StopAllGlows
    mod.StartProceduralAnts = StartProceduralAnts
    mod.StopProceduralAnts = StopProceduralAnts
    mod.StartButtonGlow = StartButtonGlow
    mod.StopButtonGlow = StopButtonGlow
    mod.StartAutoCastShine = StartAutoCastShine
    mod.StopAutoCastShine = StopAutoCastShine
    mod.StartGlow = StartGlow
    mod.StopAllGlows = StopAllGlows

    -------------------------------------------------------------------------------
    --  Dispellable buff glow: highlights enemy buffs the player can purge/soothe
    -------------------------------------------------------------------------------
    local function StopDispelGlow(slotRec)
        local dataGroup = slotRec.dispelGlow
        if not dataGroup or not dataGroup.active then return end
        dataGroup.active = false
        _G_Glows.StopAllGlows(dataGroup.wrapper)
        dataGroup.wrapper:Hide()
    end

    -- Draws the preview glow's last request (dg.sz, dg.h, dg.type). Same spec and
    -- engine path as the live purge glow, so the preview is the live look.
    local function DrawDispelGlow(dataGroup)
        mod.GetDispelGlowSpec(dataGroup.type, dataGroup.spec)
        _G_Glows.StartSpecGlow(
            dataGroup.wrapper,
            dataGroup.spec,
            dataGroup.sz,
            dataGroup.h,
            "engine",
            _G_Glows.PANEL_EXTRA
        )
    end

    -- Preview only: the live nameplate glow runs through CludesUI.Glows on the
    -- engine buttons. dispelType is "magic" / "enrage" / nil. slotH: the icon
    -- height (cropped icons). The glow draws only while the preview is visible:
    -- hidden (options closed, another page, a build made hidden) it stops, so its
    -- animations cost nothing, and it draws again when it shows (unchanged,
    -- StartSpecGlow returns at once).
    local function StartDispelGlow(slotRec, slotSize, dispelType, slotH)
        local dataGroup = slotRec.dispelGlow
        if not dataGroup then
            local holder = Pool.CreateFrame("Frame", nil, slotRec)
            holder:SetAllPoints()
            -- Under the duration text (its frame sits at slot + 2), as the live
            -- glow host sits under the text carrier.
            holder:SetFrameLevel(slotRec:GetFrameLevel() + 1)
            holder:Show()
            dataGroup = { wrapper = holder, active = false, spec = {} }
            slotRec.dispelGlow = dataGroup
            holder:SetScript("OnShow", function()
                if dataGroup.active then DrawDispelGlow(dataGroup) end
            end)
            holder:SetScript("OnHide", function(self)
                if dataGroup.active then _G_Glows.StopAllGlows(self) end
            end)
        end
        local sz = slotSize or 26
        dataGroup.sz, dataGroup.h, dataGroup.type = sz, slotH or sz, dispelType
        dataGroup.active = true
        local holder = dataGroup.wrapper
        if not holder:IsShown() then
            -- Its OnShow draws, now or once the preview shows.
            holder:Show()
        elseif holder:IsVisible() then
            DrawDispelGlow(dataGroup)
        end
        -- Always opaque. Visibility used to ride a per-aura dispel-type curve's
        -- alpha; dispellability is now decided by which aura GROUP the button
        -- belongs to, and this path only ever draws the options preview.
        holder:SetAlpha(1)
    end

    mod.StopDispelGlow = StopDispelGlow
    mod.StartDispelGlow = StartDispelGlow
end -- do (glow engine)

-- Forward declaration (assigned in CUI_Nameplates_ClassPower.lua, see SetClassPowerTopPush)
local GetClassPowerTopPush

-- XY offset for an aura slot key ("debuffSlot", "raidMarker", "classification").
local auraSlotToDBKey = {
    debuffSlot = "debuffSlot",
    buffSlot = "buffSlot",
    ccSlot = "ccSlot",
    classification = "classificationSlot",
    raidMarker = "raidMarkerPos",
    faction = "factionSlot",
}
local function GetAuraSlotOffsets(slotName)
    local dbKey = auraSlotToDBKey[slotName]
    if not dbKey then return 0, 0 end
    local place = (p and p[dbKey]) or defaultSet[dbKey]
    if not place or place == "none" then return 0, 0 end
    return GetSlotOffsets(place)
end
-- 12.1 aura containers read layout inputs through these.
mod.GetAuraSlotOffsets = GetAuraSlotOffsets
function mod.NP_GetProfile() return p end
function mod.NP_GetDefaults() return defaultSet end
function mod.NP_ClassPowerTopPush(backing)
    if GetClassPowerTopPush then return GetClassPowerTopPush(backing) or 0 end
    return 0
end

-- Get XY offset for a text slot key (e.g. "textSlotTop")
local function GetTextSlotOffsets(slotName)
    local xOff = (p and p[slotName .. "XOffset"]) or 0
    local yOff = (p and p[slotName .. "YOffset"]) or 0
    return xOff, yOff
end

-- Get font size for a text slot key (e.g. "textSlotTop")
local function GetTextSlotSize(slotName)
    return (p and p[slotName .. "Size"]) or defaultSet[slotName .. "Size"] or 10
end
mod.GetTextSlotSize = GetTextSlotSize

-- Get color for a text slot key (e.g. "textSlotTop")
local function GetTextSlotColor(slotName)
    local color = (p and p[slotName .. "Color"]) or defaultSet[slotName .. "Color"]
    if color then return color.r, color.g, color.b end
    return 1, 1, 1
end

-- Per-slot host frame for a Core Text Position, honoring the slot's Strata
-- option. MEDIUM (the default) keeps today's shared text tier: the top slot
-- owns topTextFrame outright (its strata is applied directly), the other
-- slots share healthTextFrame. A non-default strata on a non-top slot gets
-- a lazily-created host so the four slots layer independently; hosts carry
-- only font strings (no child frames), so SetFrameStrata propagation is not
-- a concern -- except the name raid marker frame and debuff coloring's Color
-- Name copies, whose callers re-assert their strata and levels after parenting.
mod.SlotTextHost = function(self, slotName, strata)
    if slotName == "textSlotTop" then
        local frame = self.topTextFrame
        frame:SetFrameStrata(strata)
        return frame
    end
    if strata == "MEDIUM" then return self.healthTextFrame end
    local hosts = self._slotTextHosts
    if not hosts then
        hosts = {}
        self._slotTextHosts = hosts
    end
    local frame = hosts[slotName]
    if not frame then
        frame = CreateFrame("Frame", nil, self)
        frame:SetAllPoints(self.health)
        frame:SetFrameLevel(900)
        hosts[slotName] = frame
    end
    frame:SetFrameStrata(strata)
    return frame
end

mod.DEFAULT_CAST_LOCKOUT_DURATION = 4
mod.CAST_LOCKOUT_ICON = "Interface\\Icons\\Ability_Kick"

function mod.ShowCastLockoutAsCrowdControl()
    if p and p.showCastLockoutAsCrowdControl ~= nil then return p.showCastLockoutAsCrowdControl end
    return defaultSet.showCastLockoutAsCrowdControl
end

function mod.GetActiveCastLockout(backing)
    local lockout = backing._castLockout
    if not lockout then return nil end
    if not mod.ShowCastLockoutAsCrowdControl() or lockout.expires <= GetTime() then
        backing._castLockout = nil
        return nil
    end
    return lockout
end

-- How far one side-slot icon pushes a target arrow out: 0 unless it meets the arrow's span (the
-- icon centres on the bar plus y and is sz tall, the arrow ah tall), else its outer edge, past
-- its own cast icon push (as its Update* placed it) and its slot's X offset. w: its width
-- (default sz; the Quest Objective Text is as wide as its text).
local function ArrowSideReach(backing, edgeSide, posY, sz, xOff, ah, wid)
    if math.abs(posY) >= (sz + ah) / 2 then return 0 end
    local reach = GetSideAuraXOffset() + mod.NP_SideIconPush(backing, edgeSide, posY, sz) + (wid or sz)
    if edgeSide == "left" then return reach - xOff end
    return reach + xOff
end

-- Side guests: elements another module parks beside the bars (the Kick Tracker's icons). A
-- guest provider answers (plate, side, a0, a1) with the outermost frame it has on that side of
-- the plate whose vertical span meets a0..a1 (the arrows' span, above the bar's bottom) and
-- that frame's centre height over the bar's centre in plate units, or nil. The arrows hug it
-- as they hug a side aura row, and ahead of one: the two cannot be measured against each other.
mod.NP_SideGuests = {}
function mod.NP_AddSideGuest(func)
    local entries = mod.NP_SideGuests
    for i = 1, #entries do
        if entries[i] == func then return end
    end
    entries[#entries + 1] = func
end

-- Restricted-tree rendering: inside the aspect-restricted nameplate subtree, SINGLE-POINT +
-- SetSize regions render displaced from their anchor, while rects fully defined by anchors
-- (fill, bg, hash line) render exactly. So an arrow pins TOP+BOTTOM to two corners (hash-line
-- pattern): edges resolve engine-side, offsets stay small numbers, nothing here reads geometry
-- ("Can't measure restricted regions"); the symmetric pair keeps the centring exact under
-- pixel-mult rounding. A side guest the arrow meets is hugged at the middle of its outer edge,
-- both points on it, half the arrow up and down (less the guest's own height over the bar's
-- centre), so the arrow stays the bar's and exactly its own height. A side aura row the arrow
-- meets is hugged at its engine-sized outer edge (aura counts are secret): rows are
-- BOTTOM-anchored at the bar's bottom plus their slot's Y offset and grow outward, so the row's
-- bottom outer corner is the one point whose two axes are both truthful, and the arrow centres
-- on the bar from there. A row the full-size cast icon did not push out (it misses the icon)
-- leaves the arrow to clear the icon too, one icon width further out. Otherwise the arrow's
-- inner edge sits `extent` + 8 past the bar's edge.
local function PlaceArrow(backing, arrow, edgeSide, extent, aw, ah)
    local barHeight = GetHealthBarHeight()
    local a0, a1 = (barHeight - ah) / 2, (barHeight + ah) / 2
    local posX = 8 + aw / 2
    local guests = mod.NP_SideGuests
    local guest, gy
    for i = 1, #guests do
        guest, gy = guests[i](backing, edgeSide, a0, a1)
        if guest then break end
    end
    local row, ry, rh
    if not guest and mod.NPC_SideRow then
        row, ry, rh = mod.NPC_SideRow(backing, edgeSide, a0, a1)
    end
    arrow:ClearAllPoints()
    if guest then
        local edge = (edgeSide == "left") and "LEFT" or "RIGHT"
        if edgeSide == "left" then posX = -posX end
        gy = gy or 0
        Pix.Point(arrow, "TOP", guest, edge, posX, ah / 2 - gy)
        Pix.Point(arrow, "BOTTOM", guest, edge, posX, -ah / 2 - gy)
    elseif row and ry < a1 and a0 < ry + rh then
        local iconTex = mod.NP_FullIconPush(backing, edgeSide, a0, a1)
        if iconTex > 0 and mod.NP_FullIconPush(backing, edgeSide, ry, ry + rh) == 0 then
            posX = posX + iconTex
        end
        local cy = barHeight / 2 - ry
        local corner = (edgeSide == "left") and "BOTTOMLEFT" or "BOTTOMRIGHT"
        if edgeSide == "left" then posX = -posX end
        Pix.Point(arrow, "TOP", row, corner, posX, cy + ah / 2)
        Pix.Point(arrow, "BOTTOM", row, corner, posX, cy - ah / 2)
    else
        local dy = (ah - barHeight) / 2
        posX = posX + extent
        if edgeSide == "left" then
            Pix.Point(arrow, "TOP", backing.health, "TOPLEFT", -posX, dy)
            Pix.Point(arrow, "BOTTOM", backing.health, "BOTTOMLEFT", -posX, -dy)
        else
            Pix.Point(arrow, "TOP", backing.health, "TOPRIGHT", posX, dy)
            Pix.Point(arrow, "BOTTOM", backing.health, "BOTTOMRIGHT", posX, -dy)
        end
    end
    Pix.Width(arrow, aw)
end

-- Position target arrows outside the side elements they meet: the cast icon, the side-slot
-- icons (raid marker, classification, faction, Quest Objective Text) and a side aura row. An
-- element its slot's Y offset moved clear of the arrows (above or below them) is passed over.
local function PositionArrowsOutsideAuras(backing)
    if not backing.leftArrow then return end
    if not backing.leftArrow:IsShown() then return end
    local arrowStyle = mod.ResolveTargetArrowStyle(p)
    local sc = (p and p.targetArrowScale) or 1.0
    local aw = math.floor(((arrowStyle and arrowStyle.w) or 16) * sc + 0.5)
    local ah = math.floor(16 * sc + 0.5)
    -- The cast icon (and Classic WoW UI's border), measured on the arrows' own span.
    local leftExtent = mod.NP_SideIconPush(backing, "left", 0, ah)
    local rightExtent = mod.NP_SideIconPush(backing, "right", 0, ah)
    local rmPos = GetRaidMarkerPos()
    if (rmPos == "left" or rmPos == "right") and backing.raidFrame and backing.raidFrame:IsShown() then
        local rx, ry = GetAuraSlotOffsets("raidMarker")
        local region = ArrowSideReach(backing, rmPos, ry, GetRaidMarkerSize(), rx, ah)
        if rmPos == "left" then
            leftExtent = math.max(leftExtent, region)
        else
            rightExtent = math.max(rightExtent, region)
        end
    end
    -- The Rare/Quest icon at the size its update set (elite/rare mark or quest icon).
    local clSlot = GetClassificationSlot()
    local castFrame = backing.classFrame
    if (clSlot == "left" or clSlot == "right") and castFrame and castFrame:IsShown() then
        local cx, cy = GetAuraSlotOffsets("classification")
        local region = ArrowSideReach(backing, clSlot, cy, castFrame._npSz or GetRareEliteIconSize(), cx, ah)
        if clSlot == "left" then
            leftExtent = math.max(leftExtent, region)
        else
            rightExtent = math.max(rightExtent, region)
        end
    end
    -- The faction badge (its own, or Rare/Quest + Faction, stacked higher behind a showing
    -- Rare/Quest icon as UpdateFaction places it).
    local fcSlot = mod.NP_GetFactionSlot()
    if
        (fcSlot == "left" or fcSlot == "right")
        and backing.factionFrame
        and backing.factionFrame:IsShown()
    then
        local fx, fy = GetSlotOffsets(fcSlot)
        if p and p.classificationIncludeFaction and castFrame:IsShown() then
            fy = fy + math.floor((castFrame._npSz or GetRareEliteIconSize()) * 0.6 + 0.5)
        end
        local region = ArrowSideReach(backing, fcSlot, fy, mod.NP_GetFactionIconSize(), fx, ah)
        if fcSlot == "left" then
            leftExtent = math.max(leftExtent, region)
        else
            rightExtent = math.max(rightExtent, region)
        end
    end
    -- The Quest Objective Text (its text, or the quest icon standing in for it).
    local qf = backing.questTextFrame
    if qf and qf:IsShown() then
        local qtSlot = mod.NP_GetQuestTextSlot()
        if qtSlot == "left" or qtSlot == "right" then
            local qx, qy = GetSlotOffsets(qtSlot)
            local region = ArrowSideReach(backing, qtSlot, qy, qf._npSz or 0, qx, ah, qf._npW)
            if qtSlot == "left" then
                leftExtent = math.max(leftExtent, region)
            else
                rightExtent = math.max(rightExtent, region)
            end
        end
    end
    PlaceArrow(backing, backing.leftArrow, "left", leftExtent, aw, ah)
    PlaceArrow(backing, backing.rightArrow, "right", rightExtent, aw, ah)
end
mod.PositionArrowsOutsideAuras = PositionArrowsOutsideAuras

Inner.EstimateHealthTextWidth, Inner.GetAuraSlotOffsets = EstimateHealthTextWidth, GetAuraSlotOffsets
Inner.GetBorderColor = GetBorderColor
Inner.GetCastBarHeight, Inner.GetCastScale = GetCastBarHeight, GetCastScale
Inner.GetClassificationSlot = GetClassificationSlot
Inner.GetClassPowerClassColors = GetClassPowerClassColors
Inner.GetClassPowerCustomColor = GetClassPowerCustomColor
Inner.GetDebuffYOffset = GetDebuffYOffset
Inner.GetEnemyNameTextSize, Inner.GetFocusCastHeight = GetEnemyNameTextSize, GetFocusCastHeight
Inner.GetHealthBarHeight, Inner.GetHealthBarWidth = GetHealthBarHeight, GetHealthBarWidth
Inner.GetHideEnemyNameWhileCasting = GetHideEnemyNameWhileCasting
Inner.GetHitboxYShift, Inner.GetKickTickColor = GetHitboxYShift, GetKickTickColor
Inner.GetKickTickEnabled, Inner.GetNameplateYOffset = GetKickTickEnabled, GetNameplateYOffset
Inner.GetNameYOffset, Inner.GetRaidMarkerPos = GetNameYOffset, GetRaidMarkerPos
Inner.GetRaidMarkerSize, Inner.GetRareEliteIconSize = GetRaidMarkerSize, GetRareEliteIconSize
Inner.GetShowCastIcon, Inner.GetShowClassPower = GetShowCastIcon, GetShowClassPower
Inner.GetSideAuraXOffset, Inner.GetSlotOffsets = GetSideAuraXOffset, GetSlotOffsets
Inner.GetStackSpacingScale, Inner.GetTargetScale = GetStackSpacingScale, GetTargetScale
Inner.GetTextSlot, Inner.GetTextSlotColor = GetTextSlot, GetTextSlotColor
Inner.GetTextSlotOffsets, Inner.GetTextSlotSize = GetTextSlotOffsets, GetTextSlotSize
Inner.IsBorderEnabled, Inner.IsComboHealthText = IsBorderEnabled, IsComboHealthText
Inner.PANDEMIC_GLOW_STYLES = PANDEMIC_GLOW_STYLES
Inner.PositionArrowsOutsideAuras = PositionArrowsOutsideAuras
Inner.SetCombinedHealthText = SetCombinedHealthText
Inner.SetClassPowerTopPush = function(frame) GetClassPowerTopPush = frame end
Inner.broken = false
