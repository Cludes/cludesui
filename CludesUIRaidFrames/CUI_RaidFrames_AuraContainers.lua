if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-- CUI_RaidFrames_AuraContainers.lua
-- 12.1 aura containers for raid/party/extra unit buttons.
--
-- Buttons are always created OUT OF COMBAT (headers pre-create via startingIndex;
-- extra-frame builds are combat-gated); containers build at StyleButton time and
-- re-point on OnAttributeChanged("unit"). Visuals anchor to the health bar, sizes
-- come from live-scaled proxies (never raw db.profile), state lives in external FFD.

local _, mod = ...

local AK -- CludesUI.AuraKit, resolved at first use
-- Born in this module's main chunk, so the aura containers it builds bill this
-- module (AuraKit's shared build scheduler).
local AKWorker = CludesUI.AuraKit.NewBuildWorker()
-- The engine's own null binding: the AuraContainer intrinsic is born on unitToken
-- "none" (Blizzard_AuraContainer.xml KeyValues). A button with no unit attribute
-- yet has to land back on that, never on "player" -- that is a unit whose auras
-- really do stream, so an unbound container renders the local player's buffs onto
-- whoever the button later shows.
local NO_UNIT = "none"
local FALLBACK_FONT = "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"

-- Marks debuff rendering as container-owned; the legacy UpdateDebuffs body
-- early-returns on this flag (single gate covering all seven call sites).
mod.RFC_OwnsDebuffs = true
mod.RFC_OwnsDefensives = true
mod.RFC_OwnsDispel = true

local SATED_DEBUFFS = {
    [57723] = true,
    [57724] = true,
    [80354] = true,
    [95809] = true,
    [160455] = true,
    [264689] = true,
    [390435] = true,
}
local ALWAYS_HIDE_DEBUFFS = { [1254550] = true, [308312] = true }
-- Shared with the Debuff Manager file (same exclude semantics there).
mod.RFC_SatedDebuffs = SATED_DEBUFFS
mod.RFC_AlwaysHideDebuffs = ALWAYS_HIDE_DEBUFFS

-- "raid" preset = union RAID|RAID_IN_COMBAT via negation-chained groups; presets
-- enable groups by COUNT, never swap containers (group set is fixed). "cc" declares
-- FIRST so it leads the row, carries the CC glow, and shows under any preset; every
-- other group negates CROWD_CONTROL so a CC aura never doubles. Lazy groups declare
-- ON DEMAND (combat-legal): each AddAuraGroup eagerly allocates a 10-button engine
-- batch (anti-fingerprint floor), so default users get 2 groups not 5. Groups are
-- add-only -- switching away zeroes counts live, never frees frames.
local DEBUFF_GROUPS = {
    { key = "cc", filter = { "HARMFUL", "CROWD_CONTROL" } },
    { key = "all", filter = { "HARMFUL", "!CROWD_CONTROL" } },
    { key = "raid", filter = { "HARMFUL", "RAID", "!CROWD_CONTROL" }, lazy = true },
    { key = "raidcombat", filter = { "HARMFUL", "RAID_IN_COMBAT", "!RAID", "!CROWD_CONTROL" }, lazy = true },
    { key = "dispellable", filter = { "HARMFUL", "RAID_PLAYER_DISPELLABLE", "!CROWD_CONTROL" }, lazy = true },
}
-- Which lazy debuff groups each filter preset needs declared.
local DEBUFF_PRESET_GROUPS = {
    raid = { "raid", "raidcombat" },
    dispellable = { "dispellable" },
}
local DEBUFF_GROUP_BY_KEY = {}
for i = 1, #DEBUFF_GROUPS do
    DEBUFF_GROUP_BY_KEY[DEBUFF_GROUPS[i].key] = DEBUFF_GROUPS[i]
end

-- "Dispellable Debuff Location" (RETIRED, see DispLocActive) routed dispellable
-- debuffs to their own container via complementary dispel-type candidate filters
-- (engine-legal on friendly harmful auras, not identity-gated). Magic/Curse/Disease/
-- Poison/Bleed is the full harmful typed set (Enrage is buff-only).
local DISPLOC_TYPES = { Magic = true, Curse = true, Disease = true, Poison = true, Bleed = true }

local function DispelIconsOn(s)
    -- Retired with the Auras tab (Dispellable now routes via a Debuff Manager tile).
    -- Constant false keeps every consumer (shell gating, config, shown state,
    -- candidate excludes, fingerprints) uniformly inert.
    return false
end

-- Button class is unknown at shell time (party stamps _isParty after StyleButton),
-- so query every settings source: an unneeded shell just ends up a cheap hidden
-- group-less container, but a MISSING shell can't be created in combat at all.
local function DispLocAnyActive()
    if mod._scaledProfile and DispelIconsOn(mod._scaledProfile) then return true end
    if mod._scaledPartyProxy and DispelIconsOn(mod._scaledPartyProxy) then return true end
    if mod._scaledExtraProxy and DispelIconsOn(mod._scaledExtraProxy) then return true end
    return false
end

-- Effective icon size at the split anchor (0 = match Debuff Size; scaled proxies
-- bake indicator scale into both keys, and 0 scales to 0, so the sentinel survives).
local function DispelIconSize(cfg)
    local val = cfg.dispellableDebuffSize
    if val and val > 0 then return mod.RFC_SnapSize(val) end
    return mod.RFC_DebuffSize(cfg)
end

-- Groups the location container needs for the active preset (all on-demand, split
-- is opt-in); cc rides along so dispellable CC keeps its glow at the split anchor.
local function DispLocGroupWanted(cfg, keyName)
    local preset = cfg.debuffFilter or "all"
    if preset == "none" then return false end
    if keyName == "cc" then return true end
    if keyName == "all" then return preset == "all" end
    if keyName == "raid" or keyName == "raidcombat" then return preset == "raid" end
    return preset == "dispellable" -- key == "dispellable"
end

local registry = {} -- array of buttons with containers (iterate for reload)
mod._rfcRegistry = registry -- DEBUG: /cuidm dump reads this; remove with the slash

local function ScaleProxy(d)
    if d._isParty then return mod._scaledPartyProxy end
    if d._isExtra then return mod._scaledExtraProxy end
    return mod._scaledProfile
end

local function StyleKeyOf(d)
    if d._isParty then return "rf:debuff:party" end
    if d._isExtra then return "rf:debuff:extra" end
    return "rf:debuff:raid"
end

-- Debuff text: duration centered, stack bottom-right, via the shared icon-text font
-- pipeline. DM EFFECTS (style.fxList, per-filter blocks): category comes from d.dmCat
-- (stamped at group declare) or the cc style's ccGroup marker for cc-group buttons;
-- boss/role matches either check, FIRST match wins. A Match All or Icon Effect split
-- record stamps a category LIST: the first block matching any of them wins. A block may add an Icon Glow
-- (rides button visibility, remaps to FlipBook under restriction, params cached) and/or
-- a Border override (own PP host one level above the style border, so equal-or-larger
-- size covers it).
local function DmFxBlockFor(entries, category)
    if not (entries and category) then return nil end
    local multi = type(category) == "table"
    for i = 1, #entries do
        local f = entries[i].filters
        if f then
            if multi then
                for jdx = 1, #category do
                    if f[category[jdx]] then return entries[i] end
                end
            elseif f[category] or (category == "bossrole" and (f.boss or f.role)) then
                return entries[i]
            end
        end
    end
end

local DM_GLOW_SPEC = {}
-- Engine glow families the DM and BM Icon Glow menus offer (Pixel and the
-- flipbooks, no Blizzard Border): a prewarm builds only these.
local ICON_GLOW_NEED = { ants = true, flip = true }
local function ApplyDmFx(btnFrame, d, look)
    local category = d.dmCat
    if not category and look.ccGroup then category = "cc" end
    local e = look.fxList and DmFxBlockFor(look.fxList, category) or nil

    -- Icon Glow (engine host): C-side animations only, identical in and out of secret.
    local Glows = CludesUI.Glows
    local specInfo = e and Glows.SpecFromPrefix(DM_GLOW_SPEC, e, "glow", 1.0, 0.776, 0.376)
    local governor = d.dmFxgHost
    local sz = look.width or 18
    if specInfo then
        if not governor then
            governor = CreateFrame("Frame", nil, btnFrame)
            governor:SetAllPoints(btnFrame)
            -- Layer ladder: style border(+1) < fx border(+2) < glow(+3) < dispel
            -- ring(+4) < text(+5); dispel recolor must always win over borders/glows.
            -- stackCarrier matches AuraKit's ladder so text never drops onto the ring.
            local base = (d.borderHost and d.borderHost:GetFrameLevel()) or (btnFrame:GetFrameLevel() + 1)
            governor:SetFrameLevel(base + 3)
            if d.stackCarrier then d.stackCarrier:SetFrameLevel(base + 5) end
            governor:EnableMouse(false)
            d.dmFxgHost = governor
            Glows.PrewarmEngineHost(governor, sz, look.height or sz, ICON_GLOW_NEED)
            -- The button runs the glow's animations itself (only while it
            -- shows an aura), where the client can.
            Glows.BindEngineHost(governor, btnFrame, d)
        end
        -- A bound host glows on every button. Without that (WoW Forever) the
        -- animation plays while hidden too: only buttons the group can ever
        -- show run one.
        if Glows.IsEngineHostBound(governor) or CludesUI.AuraKit.ButtonCanShow(btnFrame) then
            governor:Show()
            Glows.StartSpecGlow(governor, specInfo, sz, look.height or sz, "engine")
        else
            if governor._cuiGlowActive then Glows.StopGlow(governor) end
            governor:Hide()
        end
    elseif governor then
        if governor._cuiGlowActive then Glows.StopGlow(governor) end
        governor:Hide()
    end

    -- Border override
    local Pix = CludesUI.PP
    local bSize = (e and e.borderSize) or 0
    if bSize > 0 and Pix then
        local host = d.dmFxBdr
        if not host then
            host = CreateFrame("Frame", nil, btnFrame)
            host:SetAllPoints(btnFrame)
            local base = (d.borderHost and d.borderHost:GetFrameLevel()) or (btnFrame:GetFrameLevel() + 1)
            host:SetFrameLevel(base + 1)
            host:EnableMouse(false)
            Pix.CreateBorder(host, 0, 0, 0, 1, 1)
            d.dmFxBdr = host
        end
        local bc = e.borderColor or { r = 0, g = 0, b = 0 }
        Pix.UpdateBorder(host, bSize, bc.r or 0, bc.g or 0, bc.b or 0, 1)
        host:Show()
    elseif d.dmFxBdr then
        d.dmFxBdr:Hide()
    end
end
-- Exported for the DM record/group extraInits: the style applier runs BEFORE
-- extraInit at button creation (dmCat isn't stamped yet), so the stamping extraInit
-- re-arms effects inside the creation window -- the only context guaranteeing legal
-- subtree writes.
mod.RFC_ApplyDmFx = ApplyDmFx

local function ApplyRFDebuffText(btnFrame, d, look)
    -- Restyles hit every button, so expensive setters are change-guarded (SetFont
    -- costs real time even with identical values; mouse-motion is engine-wrapped).
    -- Font key = path|size, so an outline-only toggle slips through until the next
    -- size-touching reload (accepted).
    if btnFrame.SetMouseMotionEnabled then
        local motion = not look.noTooltips
        if d.rfMotion ~= motion then
            d.rfMotion = motion
            btnFrame:SetMouseMotionEnabled(motion)
        end
    end
    local filePath = (CludesUI.GetFontPath("raidFrames")) or FALLBACK_FONT
    if d.duration then
        -- Always font the string even hidden: the engine SetText()s every registered
        -- duration string on display updates, and an unfonted FontString hard-errors.
        local fontKey = filePath .. "|" .. (look.durSize or 8)
        if d.rfDurFont ~= fontKey then
            d.rfDurFont = fontKey
            CludesUI.ApplyIconTextFont(d.duration, filePath, look.durSize or 8, "raidFrames")
        end
        local color = look.durColor
        d.duration:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        -- Anchor change-guarded, stamp AFTER the calls: SetPoint against the button
        -- is policed under the 12.1 aura-secret restriction, so unchanged offsets must
        -- make zero button-touching calls to keep restyles live in-instance.
        local aKey = (look.durOffX or 0) .. "|" .. (look.durOffY or 0)
        if d.rfDurAnchor ~= aKey then
            d.duration:ClearAllPoints()
            d.duration:SetPoint("CENTER", btnFrame, "CENTER", look.durOffX or 0, look.durOffY or 0)
            d.rfDurAnchor = aKey
        end
        d.duration:SetShown(not look.hideDurationText)
    end
    if d.stack then
        d.stack:SetShown(look.showStacks ~= false)
        local fontKey = filePath .. "|" .. (look.stackSize or 8)
        if d.rfStackFont ~= fontKey then
            d.rfStackFont = fontKey
            CludesUI.ApplyIconTextFont(d.stack, filePath, look.stackSize or 8, "raidFrames")
        end
        local color = look.stackColor
        d.stack:SetTextColor(color and color.r or 1, color and color.g or 1, color and color.b or 1)
        local sKey = (look.stackOffX or 0) .. "|" .. (look.stackOffY or 0)
        if d.rfStackAnchor ~= sKey then
            d.stack:ClearAllPoints()
            d.stack:SetPoint("BOTTOMRIGHT", btnFrame, "BOTTOMRIGHT", look.stackOffX or 0, look.stackOffY or 0)
            d.rfStackAnchor = sKey
        end
    end
    -- DM Effects: per-filter blocks (flag only on DM styles; the extra
    -- clauses tear existing visuals down when the blocks turn off).
    if look.fxList or d.dmFxgHost or d.dmFxBdr then ApplyDmFx(btnFrame, d, look) end
    -- DM Square grid tiles: flat color block covering the spell icon (swipe/border/
    -- texts render above as usual). Flag only exists on square tile styles = zero
    -- cost elsewhere.
    if look.squareColor then
        local texture = d.dmSqTex
        if not texture then
            texture = btnFrame:CreateTexture(nil, "ARTWORK", nil, 3)
            texture:SetAllPoints(btnFrame)
            d.dmSqTex = texture
        end
        local color = look.squareColor
        texture:SetColorTexture(color.r or 1, color.g or 0.35, color.b or 0.35, color.a or 1)
        texture:Show()
    elseif d.dmSqTex then
        d.dmSqTex:Hide()
    end
end

local function ColorParts(color, dr, dg, saved)
    if not color then return dr, dg, saved end
    return color.r or color[1] or dr, color.g or color[2] or dg, color.b or color[3] or saved
end

-- Settings fingerprints. Every engine setter (group counts, candidate filters,
-- layouts, slot filter strings) costs real engine work even when unchanged
-- (candidate re-eval, parse-filter rebuilds) -- re-driving all of them per button on
-- unrelated changes froze the client in raids. Reload paths fingerprint what each
-- subsystem actually reads and skip calls whose inputs are unchanged.
local function FP(...)
    local num = select("#", ...)
    local tbl = {}
    for i = 1, num do
        local val = select(i, ...)
        -- Numbers round to 2 decimals: scaled sizes carry float noise that
        -- would otherwise flip fingerprints on every pass.
        if type(val) == "number" then
            tbl[i] = string.format("%.2f", val)
        else
            tbl[i] = tostring(val)
        end
    end
    return table.concat(tbl, "|")
end

local function CK(c)
    local red, green, blue = ColorParts(c, 0, 0, 0)
    return string.format("%.3f,%.3f,%.3f", red, green, blue)
end

-- Shared by buff icons, debuff grids and their previews. Unset styles keep the
-- original PP border path; explicit styles use AuraKit's unit-frame border inputs.
-- into: a table to fill instead of a new one, for a caller that applies it at once
-- (the previews' tickers); a style keeps its own.
function mod.RFC_AuraBorder(cfg, prefixText, into)
    local px = cfg[prefixText .. "Size"] or 1
    if px <= 0 then return nil end
    local color = cfg[prefixText .. "Color"]
    local red, green, blue = ColorParts(color, 0, 0, 0)
    local texture = cfg[prefixText .. "Texture"]
    local tbl = into or {}
    tbl[1], tbl[2], tbl[3], tbl[4] = red, green, blue, color and color.a or 1
    tbl.size, tbl.texture = px, texture
    tbl.edgePx = CludesUI.BorderPx(cfg[prefixText .. "SizePx"], px, texture or "solid")
    tbl.offsetX, tbl.offsetY = cfg[prefixText .. "TextureOffset"], cfg[prefixText .. "TextureOffsetY"]
    tbl.shiftX, tbl.shiftY = cfg[prefixText .. "TextureShiftX"], cfg[prefixText .. "TextureShiftY"]
    return tbl
end

function mod.RFC_AuraBorderFP(cfg, prefixText)
    if
        not cfg[prefixText .. "Texture"]
        and not cfg[prefixText .. "SizePx"]
        and not (cfg[prefixText .. "Color"] and cfg[prefixText .. "Color"].a)
    then
        return false
    end
    return FP(
        cfg[prefixText .. "Texture"],
        cfg[prefixText .. "SizePx"],
        cfg[prefixText .. "TextureOffset"],
        cfg[prefixText .. "TextureOffsetY"],
        cfg[prefixText .. "TextureShiftX"],
        cfg[prefixText .. "TextureShiftY"],
        cfg[prefixText .. "DispelTextured"],
        cfg[prefixText .. "Color"] and cfg[prefixText .. "Color"].a
    )
end

-- Owned hosts only (bare buff squares and previews); normal icons use AuraKit.
function mod.RFC_ApplyAuraBorder(host, status, border, cooldownLevel)
    if not host then return end
    if not border then
        CludesUI.ApplySecretSafeBorderStyle(host, status, 0, 0, 0, 0, 0, "solid")
        host:Hide()
        return
    end
    if border.texture or border.edgePx then host:SetFrameLevel(cooldownLevel + 1) end
    CludesUI.ApplySecretSafeBorderStyle(
        host,
        status,
        border.size,
        border[1],
        border[2],
        border[3],
        border[4],
        border.texture or "solid",
        border.offsetX,
        border.offsetY,
        border.shiftX,
        border.shiftY,
        "unitframes",
        border.size,
        nil,
        border.edgePx
    )
    host:Show()
end

local pvBorder = {} -- reused by every preview border (applied at once)
function mod.RFC_PreviewAuraBorder(icon, host, s, prefixText)
    mod.RFC_ApplyAuraBorder(
        host,
        host,
        mod.RFC_AuraBorder(s, prefixText, pvBorder),
        (icon._cooldown or icon):GetFrameLevel()
    )
end

-- A Class-mode glow draws the palette's class colour, so that colour is an
-- input of every glow print (a Colors page edit must restyle); "" for every
-- other mode. The colour last printed feeds the colours-changed hook below
-- RFC_ReloadAll. On ns: the Debuff Manager's prints use it too.
function mod.RF_GlowClassFP(mode, classFlag)
    local G = CludesUI.Glows
    if G.DeriveColorMode(mode, classFlag) ~= "class" then return "" end
    local red, green, blue = G.ResolveColor("class")
    mod._rfGlowClassR, mod._rfGlowClassG, mod._rfGlowClassB = red, green, blue
    return string.format("cc%.3f,%.3f,%.3f", red, green, blue)
end

-- Aura icon sizes on whole physical pixels: a fractional button leaves the
-- unsnapped border off the snapped icon's far edge. Styles, flow layouts, row
-- widths and fingerprints all read the size here so they agree. Memoized until
-- the next RFC_ReloadAll. On ns (local cap).
do
    local cache = {}
    function mod.RFC_SnapSize(val)
        local r = cache[val]
        if not r then
            r = mod.PixelSnap(val)
            if r <= 0 then r = val end -- under half a pixel: keep the raw size
            cache[val] = r
        end
        return r
    end
    function mod.RFC_ResetSnap() wipe(cache) end
end
function mod.RFC_DebuffSize(cfg) return mod.RFC_SnapSize(cfg.debuffSize or 18) end

-- sizeOverride: the dispellable-location styles reuse the whole debuff
-- style with only the physical size swapped (see DispLocSize).
local function BuildDebuffStyle(cfg, sizeOverride)
    local border = mod.RFC_AuraBorder(cfg, "debuffBorder")
    local px = sizeOverride and mod.RFC_SnapSize(sizeOverride) or mod.RFC_DebuffSize(cfg)
    -- Engine dispel-border extras: ring thickness in PHYSICAL pixels + the user
    -- palette as the engine tint map (AuraKit registers both; helper resolved at
    -- call time, declared below). -1 = follow icon's own Border thickness, 0 = recolor off.
    local dpx = cfg.dispelIconBorderSize or 2
    if dpx == -1 then dpx = border and (border.edgePx or border.size) or 0 end
    local dcMap, dcFP
    if mod.RFC_DispelBorderColorMap then
        dcMap, dcFP = mod.RFC_DispelBorderColorMap(cfg)
    end
    return {
        width = px,
        height = px,
        iconCrop = true,
        iconZoom = cfg.debuffIconZoom or 0.08,
        border = border,
        -- Dispellable debuffs get the engine dispel-type border over the
        -- static one (dispelName is secret in 12.1; see AuraKit).
        dispelBorder = true,
        dispelBorderTexture = cfg.debuffBorderDispelTextured == true
                and border
                and border.texture ~= "solid"
                and border.texture ~= ""
                and border.texture
            or nil,
        dispelBorderPx = dpx,
        dispelColorMap = dcMap,
        dispelColorFP = dcFP,
        cooldownReverse = true,
        hideSwipe = (cfg.debuffShowSwipe == false),
        noDefaultFonts = true,
        hideDurationText = not cfg.debuffShowDurText,
        durSize = cfg.debuffDurTextSize,
        durColor = cfg.debuffDurTextColor,
        durOffX = cfg.debuffDurTextOffsetX,
        durOffY = cfg.debuffDurTextOffsetY,
        showStacks = cfg.debuffShowStacks ~= false,
        stackSize = cfg.debuffStacksTextSize,
        stackColor = cfg.debuffStacksTextColor,
        stackOffX = cfg.debuffStacksOffsetX,
        stackOffY = cfg.debuffStacksOffsetY,
        -- 5-state tooltip mode: true/nil=hidden, false=shown, "combat"=hidden in
        -- combat, "cursor"=shown at cursor, "modifier"=shown only while the Use
        -- Modifier cog's key is held. Style-side, "modifier" renders as plain
        -- Shown; the gating is the DM file's tooltip eater -- a secure unit
        -- sub-button over the debuff band that takes the hover and hides while
        -- the key is held (button-surface writes are refused while auras are
        -- secret, so nothing here can gate at runtime). Raw key already in DebuffStyleFP.
        noTooltips = not (
                cfg.debuffHideTooltips == false
                or cfg.debuffHideTooltips == "combat"
                or cfg.debuffHideTooltips == "cursor"
                or cfg.debuffHideTooltips == "modifier"
            ),
        tooltipCombatHide = cfg.debuffHideTooltips == "combat",
        tooltipAnchor = (cfg.debuffHideTooltips == "cursor") and "cursor" or nil,
        -- Base DM Effects (per-filter blocks); tile styles override this
        -- after the build with their own (or nil).
        fxList = (mod.DM_FxList and mod.DM_FxList()) or nil,
        applyExtra = ApplyRFDebuffText,
    }
end

-- Crowd-control group style: plain debuff style + a marker the DM per-filter Icon
-- Effects use to ID cc-group buttons (that group stamps no category via extraInit).
-- The dedicated CC Debuff Glow is RETIRED (DM Icon Effects glow supersedes it).
local function BuildDebuffCCStyle(s, sizeOverride)
    local state = BuildDebuffStyle(s, sizeOverride)
    state.ccGroup = true
    return state
end
-- Shared with the Debuff Manager: custom tiles render with the debuff style at
-- their own size.
mod.RFC_BuildDebuffStyle = BuildDebuffStyle
-- CC flavor too: a per-filter Icon Effects Size moves crowd control onto a
-- sized record variant, which must keep the cc marker.
mod.RFC_BuildDebuffCCStyle = BuildDebuffCCStyle

-- Container anchoring mirrors DebuffGridPoint: the flow's start corner sits on the
-- same corner of the health bar; CENTER growth anchors the edge-midpoint there so
-- each row centers on it.
local CORNERS = {
    topleft = "TOPLEFT",
    top = "TOP",
    topright = "TOPRIGHT",
    left = "LEFT",
    center = "CENTER",
    right = "RIGHT",
    bottomleft = "BOTTOMLEFT",
    bottom = "BOTTOM",
    bottomright = "BOTTOMRIGHT",
}

local function FlowDir(token)
    local FD = AnchorUtil.FlowDirection
    if token == "LEFT" then return FD.Left end
    if token == "UP" then return FD.Up end
    if token == "DOWN" then return FD.Down end
    return FD.Right
end

-- Shared by AnchorDebuffContainer/AnchorDispLocContainer. CENTER growth pins
-- the container's top/bottom edge to match the position's OWN vertical side
-- (not wrap direction -- pinning by wrap put every CENTER-grown container's
-- edge on the bottom whenever Position was "top", since wrap defaults to "UP"
-- and isn't exposed on either options pane) so rows grow away from the
-- anchored edge; other growth directions anchor directly at the corner.
local function ResolveFlowAnchor(place, corner, growDir, wrap)
    if growDir == "CENTER" then
        local edge = (place:find("top", 1, true) and "TOP")
            or (place:find("bottom", 1, true) and "BOTTOM")
            or ((wrap == "DOWN") and "TOP" or "BOTTOM")
        return edge, edge .. "LEFT", "RIGHT", (edge == "TOP") and "DOWN" or "UP"
    elseif growDir == "UP" or growDir == "DOWN" then
        -- Vertical primary growth renders as a single column per row-width;
        -- multi-column vertical fill order differs from legacy (row-major).
        return corner, corner, (wrap == "LEFT") and "LEFT" or "RIGHT", growDir
    end
    return corner, corner, growDir, wrap
end

-- The debuff row's pin: the flow's start point on the health frame plus the
-- cell geometry the row is laid out with. AnchorDebuffContainer pins the
-- container here (same math below); the Debuff Manager's tooltip-modifier
-- eaters pin to the same point with a settings-derived maximum footprint, so
-- their rect never derives from the container's content-driven (secret) size.
function mod.RFC_DebuffPin(cfg)
    local place = cfg.debuffPosition or "bottomright"
    local corner = CORNERS[place] or "BOTTOMRIGHT"
    local growDir = cfg.debuffGrowDirection or "LEFT"
    local point = ResolveFlowAnchor(place, corner, growDir, cfg.debuffWrapDirection or "UP")
    return point,
        corner,
        cfg.debuffOffsetX or 0,
        cfg.debuffOffsetY or 0,
        mod.RFC_DebuffSize(cfg),
        cfg.debuffSpacing or 1,
        cfg.debuffPerRow or 5,
        (growDir == "UP" or growDir == "DOWN")
end

local function AnchorDebuffContainer(boxHolder, healthBar, cfg)
    healthBar = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, cfg) or healthBar -- Uniform Icon Anchoring
    -- Pin math mirrored by ns.RFC_DebuffPin above; keep the two in step.
    local place = cfg.debuffPosition or "bottomright"
    local corner = CORNERS[place] or "BOTTOMRIGHT"
    local growDir = cfg.debuffGrowDirection or "LEFT"
    local wrap = cfg.debuffWrapDirection or "UP"
    local offX = cfg.debuffOffsetX or 0
    local offY = cfg.debuffOffsetY or 0

    local point, anchorPoint, gH, gV = ResolveFlowAnchor(place, corner, growDir, wrap)

    boxHolder:ClearAllPoints()
    boxHolder:SetPoint(point, healthBar, corner, offX, offY)
    AK.SetContainerAnchor(boxHolder, anchorPoint)
    AK.SetContainerGrowth(boxHolder, FlowDir(gH), FlowDir(gV))

    local px = mod.RFC_DebuffSize(cfg)
    local spacing = cfg.debuffSpacing or 1
    local perRow = cfg.debuffPerRow or 5
    local vertical = (growDir == "UP" or growDir == "DOWN")
    local rowWidth = nil
    if vertical and perRow and perRow >= 2 then
        -- Vertical COLUMNS: lines are columns of perRow cells wrapping sideways
        -- (debuffWrapDirection maps the horizontal cross-axis above); below 2 a
        -- single column stands (elseif branch).
        AK.SetContainerAxis(boxHolder, true)
        rowWidth = perRow * px + (perRow - 1) * spacing + 0.4
    elseif vertical then
        AK.SetContainerAxis(boxHolder, false)
        rowWidth = px + 0.4 -- one column; rows advance vertically
    else
        AK.SetContainerAxis(boxHolder, false)
        if perRow and perRow >= 2 then rowWidth = perRow * px + (perRow - 1) * spacing + 0.4 end
    end
    AK.SetContainerRowWidth(boxHolder, rowWidth)
end

-- Dispellable-location anchoring: same flow math as the main debuff container,
-- but position/growth/offsets/size come from the "Dispellable Debuff Location"
-- settings (spacing/wrap/per-row stay shared with the debuff display).
local function AnchorDispLocContainer(boxHolder, healthBar, cfg)
    healthBar = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, cfg) or healthBar -- Uniform Icon Anchoring
    local place = cfg.dispellableDebuffLocation or "bottomright"
    local corner = CORNERS[place] or "BOTTOMRIGHT"
    local growDir = cfg.dispellableDebuffGrowDirection or "RIGHT"
    local wrap = cfg.debuffWrapDirection or "UP"
    local offX = cfg.dispellableDebuffOffsetX or 0
    local offY = cfg.dispellableDebuffOffsetY or 0

    local point, anchorPoint, gH, gV = ResolveFlowAnchor(place, corner, growDir, wrap)

    boxHolder:ClearAllPoints()
    boxHolder:SetPoint(point, healthBar, corner, offX, offY)
    AK.SetContainerAnchor(boxHolder, anchorPoint)
    AK.SetContainerGrowth(boxHolder, FlowDir(gH), FlowDir(gV))

    local px = DispelIconSize(cfg)
    local spacing = cfg.debuffSpacing or 1
    local perRow = cfg.debuffPerRow or 5
    local vertical = (growDir == "UP" or growDir == "DOWN")
    local rowWidth = nil
    if vertical then
        rowWidth = px + 0.4
    elseif perRow and perRow >= 2 then
        rowWidth = perRow * px + (perRow - 1) * spacing + 0.4
    end
    AK.SetContainerRowWidth(boxHolder, rowWidth)
end

------------------------------------------------------------------------------
-- Dispel highlight -> per-type slots. One bare slot per dispel type decorates the
-- health bar (overlay texture, PP border, type icon) from the user palette, engine-
-- driven show/hide. Layer priority Magic > Curse > Disease > Poison > Bleed. The
-- animated clock border on debuff icons is not reproducible.
------------------------------------------------------------------------------

local DISPEL_SLOTS = {
    {
        key = "magic",
        token = "Magic",
        colorKey = "dispelColorMagic",
        atlas = "RaidFrame-Icon-DebuffMagic",
        fallback = { 0.349, 0.475, 1.0 },
        level = 5,
    },
    {
        key = "curse",
        token = "Curse",
        colorKey = "dispelColorCurse",
        atlas = "RaidFrame-Icon-DebuffCurse",
        fallback = { 0.636, 0.0, 0.64 },
        level = 4,
    },
    {
        key = "disease",
        token = "Disease",
        colorKey = "dispelColorDisease",
        atlas = "RaidFrame-Icon-DebuffDisease",
        fallback = { 0.671, 0.384, 0.098 },
        level = 3,
    },
    {
        key = "poison",
        token = "Poison",
        colorKey = "dispelColorPoison",
        atlas = "RaidFrame-Icon-DebuffPoison",
        fallback = { 0.0, 0.706, 0.286 },
        level = 2,
    },
    {
        key = "bleed",
        token = "Bleed",
        colorKey = "dispelColorBleed",
        atlas = "RaidFrame-Icon-DebuffBleed",
        fallback = { 0.75, 0.15, 0.15 },
        level = 1,
    },
}

-- User dispel palette as a SetAuraBorder customDispelColorMap (engine tints our
-- debuff-icon ring with these; C-side validation reconstructs the color objects),
-- plus a fingerprint so palette edits re-register border options. Resolved via ns
-- at call time (BuildDebuffStyle declared above).
function mod.RFC_DispelBorderColorMap(cfg)
    local map, fp = {}, {}
    for i = 1, #DISPEL_SLOTS do
        local defaults = DISPEL_SLOTS[i]
        local color = cfg[defaults.colorKey]
        local red = (color and color.r) or defaults.fallback[1]
        local green = (color and color.g) or defaults.fallback[2]
        local blue = (color and color.b) or defaults.fallback[3]
        map[defaults.token] = CreateColor(red, green, blue, 1)
        fp[#fp + 1] = string.format("%.3f,%.3f,%.3f", red, green, blue)
    end
    return map, table.concat(fp, ";")
end
local GRADIENT_TEXTURE = "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-tb.tga"
local GRADIENT_SHARP_TEXTURE = "Interface\\AddOns\\CludesUI\\media\\textures\\gradient-sharp.tga"

-- RAID_PLAYER_DISPELLABLE knows class and spec dispels only, so it never matches
-- Poison for a shaman whose poison removal is Poison Cleansing Totem (a talent).
-- That slot keeps the plain filter in only-dispellable mode; its include-Poison
-- candidate already narrows it to poison debuffs.
-- The capability is CACHED: IsPlayerSpell can lag both addon load and the trait
-- event that announces a change, so the shaman watcher on bmRegen (below)
-- re-checks on trait and spellbook events and forces a reload on a flip.
-- rfcTotemGen lets a button whose shells baked filters under the old value
-- reconcile at finalize.
local POISON_CLEANSING_TOTEM = 383013
local _, rfcPlayerClass = UnitClass("player")
local rfcTotemKnown = rfcPlayerClass == "SHAMAN" and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
local rfcTotemGen = 0

local function TokenBlindDispel(token) return token == "Poison" and rfcTotemKnown end

local function DispelSlotFilter(cfg, token)
    if cfg.dispelShowAll == false and not TokenBlindDispel(token) then
        return { "HARMFUL", "RAID_PLAYER_DISPELLABLE" }
    end
    return { "HARMFUL" }
end

local function DispelSlotFilters(s)
    local parts = {}
    for i = 1, #DISPEL_SLOTS do
        parts[i] = AK.Filter(unpack(DispelSlotFilter(s, DISPEL_SLOTS[i].token)))
    end
    return parts
end

local function DispelFilterFP(s) return table.concat(DispelSlotFilters(s), ";") end

-- applyExtra for dispel slots. Per-button refs (health, slot definition) come from the
-- creation-time extraInit closure via dd; per-class settings from the shared style.
local function ApplyRFDispelSlot(btnFrame, dropdown, look)
    local healthBar = dropdown.rfHealth
    local defaults = dropdown.rfSlotDef
    if not (look and healthBar and defaults) then return end
    local Pix = CludesUI.PP

    -- Change-guarded, stamped AFTER the call: SetFrameLevel on the slot button is
    -- denied while auras are secret (creation-window calls are legal); a restyle-time
    -- throw defers this key to the restriction-lift re-queue.
    -- health+1: below the absorb shield bars (health+3) so fill/full overlays
    -- never cover the shield, above the heal-absorb/heal-prediction fills
    -- (same level, ARTWORK 2). All slots share this level; the Magic > Curse
    -- > ... priority is encoded in the overlay's ARTWORK sublevel below.
    local lvl = healthBar:GetFrameLevel() + 1
    if dropdown.lvl ~= lvl then
        btnFrame:SetFrameLevel(lvl)
        dropdown.lvl = lvl
    end

    local color = look.typeColors and look.typeColors[defaults.token]
    local red, green, blue = color and color.r or 1, color and color.g or 1, color and color.b or 1
    -- Per-type alpha (0 = user opted this type out of the dispel visuals)
    local typeA = (color and color.a) or 1
    local alpha = (look.opacity or 100) / 100 * typeA

    -- Overlay texture (fill / full / gradient). Sublevel 2+def.level (3..7)
    -- gives higher-priority types the higher sublevel at the shared level.
    -- The fill mode's carrier is a plain texture ANCHORED to the health bar's
    -- fill texture: anchor-derived geometry is the one health-tracking route
    -- that stays legal on aura-slot subtrees (DenyTaintedAccessWhenAurasAreSecret
    -- refuses every tainted WRITE to slot-owned objects while auras are secret
    -- -- a value-fed StatusBar here threw 37x in the field, and OnShow/OnHide
    -- scripts on slot-children never dispatch).
    if not dropdown.overlay then
        dropdown.overlay = btnFrame:CreateTexture(nil, "ARTWORK", nil, 2 + defaults.level)
    end
    local texture = dropdown.overlay
    texture:ClearAllPoints()
    if look.mode == "none" then
        texture:Hide()
    elseif look.mode == "gradient" or look.mode == "gradient_sharp" or look.mode == "gradient_reverse" then
        texture:Show()
        texture:SetAllPoints(healthBar)
        texture:SetTexture(look.mode == "gradient" and GRADIENT_TEXTURE or GRADIENT_SHARP_TEXTURE)
        -- Gradient Sharp Reverse: the sharp texture flipped vertically (bottom-up).
        if look.mode == "gradient_reverse" then
            texture:SetTexCoord(0, 1, 1, 0)
        else
            texture:SetTexCoord(0, 1, 0, 1)
        end
        texture:SetVertexColor(red, green, blue, alpha)
    elseif look.mode == "full" then
        texture:Show()
        texture:SetAllPoints(healthBar)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetColorTexture(red, green, blue, alpha)
        texture:SetVertexColor(1, 1, 1, 1)
    else -- "fill"
        texture:Show()
        local fill = healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture()
        -- The current-health area, off the fill texture's edges (a TOPLEFT-of-bar
        -- pair alone only tracks a left-to-right bar): the fill itself, or under
        -- Inverted Fill the rest of the bar up to the fill's HP edge, so a unit at
        -- full health still shows the wash.
        mod.RF_AnchorCurHealth(texture, healthBar, fill, look.fillVert, look.fillInvert)
        texture:SetTexCoord(0, 1, 0, 1)
        texture:SetColorTexture(red, green, blue, alpha)
        texture:SetVertexColor(1, 1, 1, 1)
    end

    -- Type-colored border around the health bar. One shared level for every type
    -- (unit button + LVL_RAISE - 1, strips + 10): over the base border strips (+9),
    -- under the hover/target/aggro raise (strips +11) and the text band (LVL_TEXT).
    -- The Magic > Curse > ... priority rides the strips' OVERLAY sublevel
    -- (2 + def.level), like the overlay's ARTWORK sublevel above.
    if (look.borderSize or 0) > 0 and Pix then
        if not dropdown.borderHost then
            dropdown.borderHost = CreateFrame("Frame", nil, btnFrame)
            dropdown.borderHost:SetAllPoints(healthBar)
        end
        local ub = dropdown.rfUnitBtn
        local bLvl = (ub and ub:GetFrameLevel() or healthBar:GetFrameLevel() - 2) + mod.LVL_RAISE - 1
        -- Change-guarded, stamped after the writes, like dd.lvl above.
        local relevel = dropdown.bLvl ~= bLvl
        if relevel then dropdown.borderHost:SetFrameLevel(bLvl) end
        if dropdown.borderMade then
            Pix.UpdateBorder(dropdown.borderHost, look.borderSize, red, green, blue, typeA)
        else
            Pix.CreateBorder(
                dropdown.borderHost,
                red,
                green,
                blue,
                typeA,
                look.borderSize,
                "OVERLAY",
                2 + defaults.level
            )
            dropdown.borderMade = true
        end
        if relevel then
            -- The strips' PP container keeps the level it was created at.
            local ppC = Pix.GetBorders(dropdown.borderHost)
            if ppC then ppC:SetFrameLevel(bLvl + 1) end
            dropdown.bLvl = bLvl
        end
        dropdown.borderHost:Show()
    elseif dropdown.borderHost then
        dropdown.borderHost:Hide()
    end

    -- Color Custom Borders: a copy of the unit frame's own border (same style, size,
    -- offsets and exact pixels) in this type's color. It rides the slot's engine
    -- visibility, so it covers the normal border only while the type is present.
    -- Always exactly one level over the base border, never a tie: +9 over the base's
    -- +8 (strips +10 over +9), so the raised hover/target/aggro recolors (ns.LVL_RAISE)
    -- and the inner aggro border stay above it; with Show Behind, pl over the base's
    -- pl - 1, still under the health bar (pl + 2). The base is never raised under Show
    -- Behind, so there the type color also covers those recolors while its type is
    -- present. The
    -- secret-safe renderer needs no size reads and no scripts (scripts never run
    -- under a slot button). Per-type alpha 0 opts the type out, as for the ring.
    local cb = look.customBorder
    local ub = dropdown.rfUnitBtn
    if cb and ub and Pix and typeA > 0 then
        if not dropdown.cbHost then
            -- Published only once anchored: a denied write leaves no half-built host,
            -- and the next restyle simply tries again.
            local host = CreateFrame("Frame", nil, btnFrame)
            host:SetAllPoints(dropdown.rfBorder or ub)
            dropdown.cbState = {}
            dropdown.cbHost = host
        end
        -- Armed before the first write on the host: a draw that throws partway still
        -- leaves the off branch able to clear whatever it drew.
        dropdown.cbOn = true
        local pl = ub:GetFrameLevel()
        local cbLvl = cb.behind and pl or (pl + 9)
        dropdown.cbHost:SetFrameLevel(cbLvl)
        -- A solid copy's strips sit on a PP container whose level is fixed at creation.
        local ppC = Pix.GetBorders(dropdown.cbHost)
        if ppC then ppC:SetFrameLevel(cbLvl + 1) end
        CludesUI.ApplySecretSafeBorderStyle(
            dropdown.cbHost,
            dropdown.cbState,
            cb.size,
            red,
            green,
            blue,
            typeA,
            cb.tex,
            cb.offX,
            cb.offY,
            cb.shX,
            cb.shY,
            "unitframes",
            cb.size,
            nil,
            cb.px
        )
        dropdown.cbHost:Show()
    elseif dropdown.cbOn then
        -- Size 0 hides every piece and drops the UI-scale re-apply registration.
        CludesUI.ApplySecretSafeBorderStyle(dropdown.cbHost, dropdown.cbState, 0, 0, 0, 0, 0, "solid")
        dropdown.cbHost:Hide()
        -- Disarmed only once the hide landed: a denied call re-runs this at the lift.
        dropdown.cbOn = nil
    end

    -- Dispel type icon.
    if look.showIcon then
        if not dropdown.iconHost then
            dropdown.iconHost = CreateFrame("Frame", nil, btnFrame)
            dropdown.icon = dropdown.iconHost:CreateTexture(nil, "ARTWORK")
            dropdown.icon:SetAllPoints(dropdown.iconHost)
        end
        -- Above the aura band (unit button + 13, children to +5, cc-glow
        -- carrier +6): health sits at unit button + 2, so this lands the
        -- type icons at +21..+25 -- packing them onto the same corner as the
        -- debuff grid draws them ON TOP of the debuff icons, keeping the
        -- Magic > Curse > Disease > Poison > Bleed ordering, and staying
        -- under the raid marker band (LVL_MARKER 26).
        dropdown.iconHost:SetFrameLevel(healthBar:GetFrameLevel() + 18 + defaults.level)
        dropdown.icon:SetAtlas(defaults.atlas)
        local px = look.iconSize or 16
        dropdown.iconHost:SetSize(px, px)
        local corner = CORNERS[look.iconPos or "right"] or "RIGHT"
        -- Uniform Icon Anchoring: the type icon is positional (unlike the
        -- overlay/border above, which decorate the bar itself). The Party
        -- Frames kit positions it on the visible party frame.
        local iconAnchor = healthBar._cuiKitRef
            or (look.uniformAnchors and healthBar._cuiUniformRef)
            or healthBar
        dropdown.iconHost:ClearAllPoints()
        dropdown.iconHost:SetPoint(corner, iconAnchor, corner, look.iconOffX or 0, look.iconOffY or 0)
        dropdown.iconHost:Show()
    elseif dropdown.iconHost then
        dropdown.iconHost:Hide()
    end
end

local function BuildDispelStyle(cfg, compact)
    local typeColors = {}
    for i = 1, #DISPEL_SLOTS do
        local defaults = DISPEL_SLOTS[i]
        local color = cfg[defaults.colorKey]
        typeColors[defaults.token] = {
            r = color and color.r or defaults.fallback[1],
            g = color and color.g or defaults.fallback[2],
            b = color and color.b or defaults.fallback[3],
            a = (color and color.a) or 1,
        }
    end
    -- Color Custom Borders: the frame border's own ApplyBorderStyle inputs, so each
    -- type's copy matches it. Only over a custom border (ns.RF_CustomBorderOn): none
    -- under a stock style (the CludesUI border stands down there), a Solid
    -- Border Style or Border Size 0.
    local customBorder
    if not compact and cfg.dispelCustomBorder == true and mod.RF_CustomBorderOn(cfg) then
        local bs = mod.RF_EffBorderSize(cfg)
        local texture = cfg.borderTexture
        customBorder = {
            size = bs,
            tex = texture,
            offX = cfg.borderTextureOffset,
            offY = cfg.borderTextureOffsetY,
            shX = cfg.borderTextureShiftX,
            shY = cfg.borderTextureShiftY,
            px = CludesUI.BorderPx(cfg.borderSizePx, bs, texture),
            behind = cfg.borderBehind and true or false,
        }
    end
    return {
        width = 1,
        height = 1,
        noRegions = true,
        mode = cfg.dispelOverlay or "fill",
        opacity = cfg.dispelOverlayOpacity or 100,
        borderSize = cfg.dispelBorderSize or 0,
        showIcon = cfg.showDispelIcons == true,
        iconSize = cfg.dispelIconSize or 16,
        iconPos = cfg.dispelIconPosition or "right",
        iconOffX = cfg.dispelIconOffsetX or 0,
        iconOffY = cfg.dispelIconOffsetY or 0,
        uniformAnchors = cfg.powerUniformAnchors == true,
        -- The fill wash's anchors follow the fill direction (RF_AnchorCurHealth).
        fillVert = mod.RF_IsVerticalFill(cfg),
        fillInvert = mod.RF_IsInvertedFill(cfg),
        typeColors = typeColors,
        customBorder = customBorder,
        applyExtra = ApplyRFDispelSlot,
    }
end

local function DispelVisible(cfg, d)
    return (cfg.dispelOverlay or "fill") ~= "none"
        or (cfg.dispelBorderSize or 0) > 0
        or cfg.showDispelIcons == true
        or (
            cfg.dispelCustomBorder == true
            and not mod.RF_ButtonCompact(d, cfg)
            and mod.RF_CustomBorderOn(cfg)
        )
end

-- Fingerprints of exact settings each subsystem reads, per class ("rf:debuff:raid"/
-- party/extra -- proxy values differ per class; scaled proxies bake in scale, so
-- scale changes flip these too).
local classFP = {}

local function DebuffStyleFP(cfg, font)
    return FP(
        font,
        cfg.debuffSize,
        mod.RFC_DebuffSize(cfg),
        cfg.debuffIconZoom,
        cfg.debuffBorderSize,
        CK(cfg.debuffBorderColor),
        mod.RFC_AuraBorderFP(cfg, "debuffBorder"),
        cfg.debuffShowSwipe,
        cfg.debuffShowDurText,
        cfg.debuffDurTextSize,
        CK(cfg.debuffDurTextColor),
        cfg.debuffDurTextOffsetX,
        cfg.debuffDurTextOffsetY,
        cfg.debuffShowStacks,
        cfg.debuffStacksTextSize,
        CK(cfg.debuffStacksTextColor),
        cfg.debuffStacksOffsetX,
        cfg.debuffStacksOffsetY,
        cfg.debuffHideTooltips,
        -- Dispel icon ring: thickness + the user palette the engine tints with.
        cfg.dispelIconBorderSize,
        CK(cfg.dispelColorMagic),
        CK(cfg.dispelColorCurse),
        CK(cfg.dispelColorDisease),
        CK(cfg.dispelColorPoison),
        CK(cfg.dispelColorBleed),
        -- Base DM Effects ride the debuff style (BuildDebuffStyle injects
        -- them), so their config is part of this fingerprint.
        (mod.DM_FxFP and mod.DM_FxFP()) or ""
    )
end
-- Shared with the Debuff Manager file: tile styles derive from the debuff
-- style, so their restyle fingerprints must include this exact value.
mod.RFC_DebuffStyleFP = DebuffStyleFP

local function DebuffCfgFP(cfg)
    -- DispLocActive: the split toggles excludeDispelTypes on the MAIN groups'
    -- candidate filters, so flipping it must re-drive the main config too.
    return FP(
        cfg.debuffPosition,
        cfg.debuffGrowDirection,
        cfg.debuffWrapDirection,
        cfg.debuffOffsetX,
        cfg.debuffOffsetY,
        cfg.debuffSize,
        mod.RFC_DebuffSize(cfg),
        cfg.debuffSpacing,
        cfg.debuffPerRow,
        cfg.debuffFilter,
        cfg.debuffCap,
        cfg.hideLustDebuff,
        DispelIconsOn(cfg),
        cfg.powerUniformAnchors,
        (mod.DM_CfgFP and mod.DM_CfgFP()) or ""
    )
end

local function DispLocStyleFP(s, font)
    -- The split styles are the debuff styles with only the size swapped.
    return FP(DebuffStyleFP(s, font), DispelIconSize(s), DispelIconsOn(s))
end

local function DispLocCfgFP(cfg)
    return FP(
        DispelIconsOn(cfg),
        cfg.dispellableDebuffLocation,
        cfg.dispellableDebuffGrowDirection,
        cfg.dispellableDebuffOffsetX,
        cfg.dispellableDebuffOffsetY,
        DispelIconSize(cfg),
        cfg.debuffSpacing,
        cfg.debuffPerRow,
        cfg.debuffWrapDirection,
        cfg.debuffFilter,
        cfg.debuffCap,
        cfg.hideLustDebuff,
        cfg.powerUniformAnchors
    )
end

-- Color key + per-type alpha (the dispel swatches carry an opt-out alpha).
local function CKA(cfg) return CK(cfg) .. "," .. tostring((cfg and cfg.a) or 1) end

local function DispelStyleFP(cfg, keyName)
    local party = keyName == "rf:debuff:party" or keyName == "rf:dispel:party"
    local compact = keyName ~= "rf:debuff:extra"
        and keyName ~= "rf:dispel:extra"
        and mod.RF_CompactOn(cfg, party)
    return FP(
        cfg.dispelOverlay,
        cfg.dispelOverlayOpacity,
        cfg.dispelBorderSize,
        cfg.showDispelIcons,
        cfg.dispelIconSize,
        cfg.dispelIconPosition,
        cfg.dispelIconOffsetX,
        cfg.dispelIconOffsetY,
        CKA(cfg.dispelColorMagic),
        CKA(cfg.dispelColorCurse),
        CKA(cfg.dispelColorDisease),
        CKA(cfg.dispelColorPoison),
        CKA(cfg.dispelColorBleed),
        cfg.powerUniformAnchors,
        compact,
        -- The fill wash follows the fill direction (BuildDispelStyle); the axis
        -- only moves it under Inverted Fill.
        mod.RF_IsInvertedFill(cfg),
        mod.RF_IsInvertedFill(cfg) and mod.RF_IsVerticalFill(cfg),
        -- Color Custom Borders copies the frame border (strata: a strata change
        -- re-stacks child levels), so those inputs count, only while it is on.
        cfg.dispelCustomBorder == true
                and FP(
                    cfg.borderSize,
                    cfg.borderTexture,
                    cfg.borderSizePx,
                    cfg.borderTextureOffset,
                    cfg.borderTextureOffsetY,
                    cfg.borderTextureShiftX,
                    cfg.borderTextureShiftY,
                    cfg.borderBehind,
                    cfg.frameStrata
                )
            or false
    )
end

-- The fingerprint each class's shared styles were built from. A class with no finalized
-- button never reaches ComputeClassFlags, so styles built at login can predate a
-- settings change; PrimeClassFP compares against these and rebuilds what differs.
local builtFP = {}
local function StoreDispelStyle(keyName, s, fp)
    AK.styles[keyName] = BuildDispelStyle(
        s,
        keyName ~= "rf:dispel:extra" and mod.RF_CompactOn(s, keyName == "rf:dispel:party")
    )
    builtFP[keyName] = fp or DispelStyleFP(s, keyName)
end
-- The base debuff style and its cc twin share one fingerprint (DebuffStyleFP).
local function StoreDebuffStyles(lookKey, s, fp)
    local ccKey = lookKey:gsub("debuff", "debuffcc")
    AK.styles[lookKey] = BuildDebuffStyle(s)
    AK.styles[ccKey] = BuildDebuffCCStyle(s)
    builtFP[lookKey] = fp
        or DebuffStyleFP(s, (CludesUI.GetFontPath and CludesUI.GetFontPath("raidFrames")) or "")
    return ccKey
end

-- Stores current fingerprints without restyling. Called at button setup (which just
-- built from these settings) -- otherwise the first post-login settings change would
-- re-drive every subsystem for the class.
local function PrimeClassFP(lookKey, s)
    local state = classFP[lookKey]
    if not state then
        state = {}
        classFP[lookKey] = state
    end
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    local dsfp = DebuffStyleFP(s, font)
    state.debuffStyle = dsfp
    state.debuffCfg = DebuffCfgFP(s)
    state.dispLocStyle = DispLocStyleFP(s, font)
    state.dispLocCfg = DispLocCfgFP(s)
    local dfp = DispelStyleFP(s, lookKey)
    state.dispelStyle = dfp
    state.dispelFilter = DispelFilterFP(s)
    -- The shared styles are the stamps that must not be trusted blindly: rebuild any
    -- built from older settings (see builtFP). One string compare each when current.
    -- (DM tile/sized styles carry their own fingerprints; the dispel filter is per
    -- button and reconciled in the finalize job.)
    if AK and AK.styles[lookKey] and builtFP[lookKey] ~= dsfp then
        local ccKey = StoreDebuffStyles(lookKey, s, dsfp)
        AK.RestyleSoon(lookKey)
        AK.RestyleSoon(ccKey)
        if mod.DM_RefreshSizedStyles then mod.DM_RefreshSizedStyles(lookKey, s) end
    end
    local dispelStyleKey = lookKey:gsub("debuff", "dispel")
    if AK and AK.styles[dispelStyleKey] and builtFP[dispelStyleKey] ~= dfp then
        StoreDispelStyle(dispelStyleKey, s, dfp)
        AK.RestyleSoon(dispelStyleKey)
    end
end

local function ApplyDebuffConfig(boxHolder, d, s)
    -- Debuff Manager (12.1 redesign): while active it owns every group on
    -- this container (legacy preset groups park at 0 inside it).
    if mod.DM_Active and mod.DM_Active() and mod.DM_ApplyDebuffConfig then
        mod.DM_ApplyDebuffConfig(boxHolder, d, s, StyleKeyOf(d))
        return
    end
    -- Legacy preset display is retired: Debuff Manager (default-ON) is the only
    -- renderer, so with it explicitly disabled the debuff row is EMPTY by design.
    -- Park every group (record variants and tile containers park via DM_ParkGroups).
    local declared = d.rfcDebuffGroups or {}
    for key in pairs(declared) do
        CludesUI.AuraKit.SetGroupCap(boxHolder, key, 0)
    end
    if mod.DM_ParkGroups then mod.DM_ParkGroups(boxHolder, declared, d) end
end

-- Config for the dispellable-location container: same preset/cap/exclude semantics
-- as the main debuff config, but every group carries includeDispelTypes plus the
-- split's own element size. Groups are on-demand; an undeclared-but-needed group
-- queues its declaration on the combat-legal live lane and re-applies.
local function ApplyDispLocConfig(boxHolder, d, cfg)
    local isActive = DispelIconsOn(cfg)
    local cap = 0
    if isActive and (cfg.debuffFilter or "all") ~= "none" then cap = cfg.debuffCap or 3 end

    local ex = {}
    for ident in pairs(ALWAYS_HIDE_DEBUFFS) do
        ex[ident] = true
    end
    if cfg.hideLustDebuff ~= false then
        for ident in pairs(SATED_DEBUFFS) do
            ex[ident] = true
        end
    end
    local cand = { excludeSpellIDs = ex, includeDispelTypes = DISPLOC_TYPES }

    local px = DispelIconSize(cfg)
    local layout = {
        elementWidth = px,
        elementHeight = px,
        elementSpacing = cfg.debuffSpacing or 1,
        lineSpacing = cfg.debuffSpacing or 1,
    }

    local declared = d.rfcDispLocGroups or {}
    if isActive then
        local missing = false
        for i = 1, #DEBUFF_GROUPS do
            local group = DEBUFF_GROUPS[i]
            if DispLocGroupWanted(cfg, group.key) and not declared[group.key] then missing = true end
        end
        if missing and not d.rfcDispLocEnsure then
            d.rfcDispLocEnsure = true
            AKWorker:Queue(function()
                d.rfcDispLocEnsure = nil
                local c2 = d.rfcDispLoc
                if not c2 then return end
                local s2 = ScaleProxy(d)
                if not s2 or not DispelIconsOn(s2) then return end
                local lookKey = StyleKeyOf(d)
                local dlStyleKey = lookKey:gsub("debuff", "disploc")
                local dlCCStyleKey = lookKey:gsub("debuff", "disploccc")
                AK.styles[dlStyleKey] = AK.styles[dlStyleKey] or BuildDebuffStyle(s2, DispelIconSize(s2))
                AK.styles[dlCCStyleKey] = AK.styles[dlCCStyleKey]
                    or BuildDebuffCCStyle(s2, DispelIconSize(s2))
                for i = 1, #DEBUFF_GROUPS do
                    local group = DEBUFF_GROUPS[i]
                    if DispLocGroupWanted(s2, group.key) and not d.rfcDispLocGroups[group.key] then
                        AK.AddGroupToContainer(c2, {
                            key = group.key,
                            filter = group.filter,
                            maxFrameCount = 0,
                            style = (group.key == "cc") and dlCCStyleKey or dlStyleKey,
                        })
                        d.rfcDispLocGroups[group.key] = true
                    end
                end
                ApplyDispLocConfig(c2, d, s2)
            end, "rf:disploc-ensure")
        end
    end

    for i = 1, #DEBUFF_GROUPS do
        local group = DEBUFF_GROUPS[i]
        if declared[group.key] then
            CludesUI.AuraKit.SetGroupCap(
                boxHolder,
                group.key,
                DispLocGroupWanted(cfg, group.key) and cap or 0
            )
            boxHolder:SetAuraGroupCandidateFilters(group.key, cand)
            boxHolder:SetAuraGroupLayout(group.key, layout)
        end
    end
end

------------------------------------------------------------------------------
-- BuffManager custom mode -> slots: one slot per tracked spell at a FIXED chain
-- position (no compaction). Icon slots use standard regions; square/bar/effect
-- slots are bare buttons whose extraInit builds custom regions directly. Effects:
-- healthcolor tints the health-fill overlay, bgcolor tints the bar background,
-- border draws the full style set around the unit button (sweep renders fully lit,
-- no ticker under secrecy). framealpha and missing/allPresent/anyMissing show-when
-- are NOT reproducible -- and the obvious workaround is FORBIDDEN BY THE ENGINE:
-- OnShow/OnHide hooks on slot buttons (visibility-edge counting) make the engine's
-- own secret-driven SetShown throw "Cannot be called with secrets due to existing
-- script handlers", failing the whole container build under secrecy (field,
-- 2026-08-14). Never install visibility scripts on engine aura buttons. Effect
-- indicators render presence-driven only.
------------------------------------------------------------------------------

local BM_FRAMELVL = { behindBorders = 7, behindText = 11, medium = 13, high = 14, highest = 15 }
local BM_FRAMELVL_TEXT = 18

local function BmScaleFor(d)
    if d._isParty then return mod._partyBmScale or 1 end
    if d._isExtra then return mod._xfBmScale or 1 end
    return mod._bmScale or 1
end

-- Scaled indicator size on whole physical pixels (see ns.RFC_DebuffSize): one
-- value for the style, the slot SetSize and the chain flow math.
function mod.RFC_BmSize(indicator, iconScale) return mod.RFC_SnapSize((indicator.size or 18) * iconScale) end

local function BmIndicators(d)
    -- Buff Manager v2 (spell -> filter -> indicator): the adapter returns legacy-
    -- shaped indicators with resolved spell unions. d: the button asking; its
    -- frame kind applies each indicator's Show In (party header buttons are party,
    -- also in arena and small-raid party mode; extra and friendly boss frames are
    -- raid). nil d = every indicator.
    return mod.BM2_SpecIndicators(d and (d._isParty and "party" or "raid") or nil)
end

local function BmIncludeMap(spellId, exact)
    local map = { [spellId] = true }
    if mod.BM_PrimaryByAlt then
        for alt, prim in pairs(mod.BM_PrimaryByAlt) do
            if prim == spellId then map[alt] = true end
        end
    end
    -- v2 curated alternates (same buff under talent/rank ids): resolution keeps ONE
    -- entry per buff family, so the family's alt ids must all match the primary's slot.
    -- An exact id (the view's exactSpells) matches its own aura alone, so a
    -- same-named family member stays with the indicator that names it.
    if mod.BM2_PresetAlts and not exact then
        local alts = mod.BM2_PresetAlts[spellId]
        if alts then
            for i = 1, #alts do
                map[alts[i]] = true
            end
        end
    end
    return map
end

-- Own-only is per-INDICATOR (per-spell overrides are retired; legacy ownOnlySpells
-- data collapses via the v2 read-heal). Legacy nil still reads own-only (pre-v2 default).
local function BmEffOwnOnly(indicator)
    if indicator.ownOnly ~= nil then return indicator.ownOnly end
    return true
end

-- Square per-spell color: options swatches write ind.spellColors[spellID] (legacy
-- ind.color is only a fallback). With nil spellID (shared chain-group style), colors
-- are uniform by construction (BmChainMode forces per-spell slots when they differ),
-- so the first spell's resolved entry is representative.
local function BmSquareColor(indicator, spellId)
    local sc = indicator.spellColors
    if sc then
        if spellId then return sc[spellId] or indicator.color end
        for k = 1, #(indicator.spells or {}) do
            local c = sc[indicator.spells[k]]
            if c then return c end
        end
    end
    return indicator.color
end

-- Chain rendering mode for icon/square indicators. "g" = one flow GROUP: active
-- auras compact into first positions like the legacy renderer (engine sort order
-- within the chain -- documented delta vs legacy list order). "s" = fixed per-spell
-- slots (required when per-spell overrides -- size offsets, mixed own-only, mixed
-- square colors -- make a shared group impossible; those keep reserved positions).
-- "-" = not a chain kind.
local function BmChainMode(indicator)
    if indicator.type ~= "icon" and indicator.type ~= "square" then return "-" end
    if indicator.type == "square" and indicator.spellColors then
        -- Mixed per-spell colors: a shared group can't know which spell an engine
        -- button holds, so each spell needs its own slot (only remaining slot-mode
        -- trigger; per-icon size offsets and per-spell own-only are retired).
        local first
        for k = 1, #(indicator.spells or {}) do
            local ck = CK(indicator.spellColors[indicator.spells[k]] or indicator.color)
            if not first then
                first = ck
            elseif ck ~= first then
                return "s"
            end
        end
    end
    return "g"
end
-- (The Party Frames kit's Buff Manager view picks its runs with it.)
mod.RFC_BmChainMode = BmChainMode

-- Own-only state feeds slot filter strings and the chain group's filter,
-- so it is part of the swap signature.
local function BmOwnSig(indicator) return tostring(indicator.ownOnly ~= false) end

-- Pandemic Border is retail only: WoW Forever's buffs may have no refresh window,
-- so a saved choice reads as off there.
local function BmPandemicOn(indicator)
    return indicator.pandemicBorderEnabled == true and not CludesUI.IS_FOREVER
end

-- Structural only: SLOT own-only state is NOT part of the signature -- it maps to
-- slot filter strings, which update live (a swap here would rebuild the container on
-- every own-only toggle). CHAIN groups bake own-only into their declaration-fixed
-- filter string, so their uniform state IS structural and swaps.
local function BmSignature(inds, specKey, mode)
    -- Spec-scoped sentinel: with no indicators the signature still carries the
    -- spec, so a spec change swaps the container.
    if mode == "simple" or not inds then return "simple:" .. tostring(specKey) end
    local parts = { specKey or "?" }
    for i = 1, #inds do
        local indicator = inds[i]
        -- Truthy enabled on purpose (matches legacy lookup gate). framealpha
        -- indicators are deliberately treated as disabled -- fading needs per-aura
        -- presence, secret in combat; options carry the removal notice.
        if indicator.enabled and indicator.type ~= "framealpha" then
            local cmode = BmChainMode(indicator) -- group<->slots transition is structural
            local ownTag = ""
            if cmode == "g" then ownTag = BmEffOwnOnly(indicator) and ":o" or ":a" end
            -- Exact ids narrow the include maps, which slots take at
            -- creation, so they are structural too.
            local exTag = ""
            local ex = indicator.exactSpells
            if ex then
                local sp = indicator.spells or {}
                for k = 1, #sp do
                    if ex[sp[k]] then exTag = exTag .. ":x" .. sp[k] end
                end
            end
            parts[#parts + 1] = tostring(indicator.id or ("x" .. i))
                .. ":"
                .. (indicator.type or "icon")
                .. ":"
                .. table.concat(indicator.spells or {}, "-")
                .. exTag
                .. ":"
                .. tostring(indicator.showWhen or "present")
                .. ":"
                .. cmode
                .. ownTag
                .. (indicator.showOwnAllSpecs and ":s" or "")
                -- Custom Order is structural: it decides the per-spell group
                -- segmentation AND which candidate map each group carries, so
                -- both the flag and the arrangement must swap/retarget.
                .. ((cmode == "g" and indicator.customOrder) and (":ord" .. table.concat(
                    indicator.spellOrder or {},
                    "-"
                )) or "")
                -- Anchor To is structural: the composition decides how many
                -- groups each pool container declares.
                .. ":@"
                .. tostring(indicator.anchorTo or "")
                -- Pandemic regions must be registered in the creation callback.
                .. (((indicator.type or "icon") == "icon" and BmPandemicOn(indicator)) and ":p" or "")
        end
    end
    return table.concat(parts, "|")
end

-- Candidate filters for one slot: chain slots pass their spellID, effect slots pass
-- the indicator's borrow-filtered spell list. Own-only is NOT expressed here: the
-- isFromPlayerOrPlayerPet candidate boolean matches auras cast by ANY player
-- (verified: same-spec allies' buffs pass it), so own-cast filtering rides the
-- PLAYER filter token instead.
local function BuildBmCand(indicator, spellList, spellId)
    local include
    local ex = indicator.exactSpells
    if spellId then
        include = BmIncludeMap(spellId, ex and ex[spellId])
    else
        include = {}
        for k = 1, #(spellList or {}) do
            local spellRef = spellList[k]
            for ident in pairs(BmIncludeMap(spellRef, ex and ex[spellRef])) do
                include[ident] = true
            end
        end
    end
    return { includeSpellIDs = include }
end

-- Filter tokens for one slot/chain group: PLAYER (strictly the local
-- player's casts) when the indicator is own-only.
local function BuildBmFilter(indicator)
    if BmEffOwnOnly(indicator) then return { "HELPFUL", "PLAYER" } end
    return { "HELPFUL" }
end

-- Custom Order (per-indicator opt-in): splits a chain member's single union
-- group into ORDERED segments -- one per-spell group per arranged spell
-- (capped: every group is an eager 10-button engine batch) plus one residual
-- union group for anything unarranged/beyond the cap. The engine's flow
-- layout collapses empty groups, so the run stays gapless while inactive
-- ordered spells simply skip -- exact arranged order without reserved slots.
-- Returns nil for the default single-group behavior (flag off, nothing
-- arranged resolves, or a single spell).
local BM_ORDER_CAP = 10
local function BmSegments(indicator, spellList)
    if not indicator.customOrder or #spellList <= 1 then return nil end
    local present = {}
    for k = 1, #spellList do
        present[spellList[k]] = true
    end
    local ordered, seen = {}, {}
    local so = indicator.spellOrder
    if so then
        -- WoW Forever: an entry saved under a rank alternate orders its
        -- family's primary (the id the resolved list holds). nil elsewhere.
        local ap = mod.BM2_ForeverAltPrimary
        for k = 1, #so do
            local spellRef = so[k]
            if ap then spellRef = ap[spellRef] or spellRef end
            if present[spellRef] and not seen[spellRef] and #ordered < BM_ORDER_CAP then
                seen[spellRef] = true
                ordered[#ordered + 1] = spellRef
            end
        end
    end
    if #ordered == 0 then return nil end
    local segs = {}
    for k = 1, #ordered do
        segs[#segs + 1] = { spellID = ordered[k], count = 1 }
    end
    local residual
    for k = 1, #spellList do
        if not seen[spellList[k]] then
            residual = residual or {}
            residual[#residual + 1] = spellList[k]
        end
    end
    if residual then segs[#segs + 1] = { spells = residual, count = #residual } end
    return segs
end

local function BmColor(color, dr, dg, db2)
    if not color then return dr, dg, db2 end
    return color.r or color[1] or dr, color.g or color[2] or dg, color.b or color[3] or db2
end

-- Cached per config: unchanged settings return the SAME curve object, so
-- the restyle pass can skip the duration-text re-registration.
local bmCurveCache = {}
local function BmThresholdCurve(indicator)
    if not (indicator.thresholdEnabled and C_CurveUtil and C_CurveUtil.CreateColorCurve) then return nil end
    local tr, tg, tb = BmColor(indicator.thresholdColor, 1, 0.25, 0.25)
    local nr, ng, nb = BmColor(indicator.durationTextColor, 1, 1, 1)
    local hash =
        string.format("%d|%.3f,%.3f,%.3f|%.3f,%.3f,%.3f", indicator.threshold or 3, tr, tg, tb, nr, ng, nb)
    local curve = bmCurveCache[hash]
    if curve then return curve end
    curve = C_CurveUtil.CreateColorCurve()
    curve:SetType(Enum.LuaCurveType.Step)
    curve:AddPoint(0, CreateColor(tr, tg, tb))
    curve:AddPoint(indicator.threshold or 3, CreateColor(nr, ng, nb))
    bmCurveCache[hash] = curve
    return curve
end

-- Base frame level = the unit button's (slot -> container -> unit button).
local function BmBaseLevel(btnFrame)
    local boxHolder = btnFrame:GetParent()
    local unitButton = boxHolder and boxHolder:GetParent()
    if unitButton then return unitButton:GetFrameLevel() end
    return 2
end

-- Color curve binds at SetDurationText registration, so a changed threshold needs
-- re-registration on restyle. bmRegistered is set AFTER initial registration (keeps
-- this pass inert during init, since applyExtra runs before it). Curves are cached,
-- so unchanged settings yield the same object and skip the rebind. Schema:
-- textColor = { curve, property }.
local function BmRebindDurationCurve(btnFrame, dropdown, look)
    if dropdown.duration and dropdown.bmRegistered and look.durationColorCurve ~= dropdown.bmCurve then
        local durationOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(), look.durationColorCurve)
        local success, full = AK.SetDurationTextSafe(btnFrame, dropdown.duration, durationOpts)
        -- Stamp only when the requested set actually landed: a denied or degraded
        -- registration must leave the curve unstamped so a retry/next restyle reruns it.
        if success and (full or not look.durationColorCurve) then
            dropdown.bmCurve = look.durationColorCurve
        end
    end
end

-- Display-level Icon Glow (v2 DISPLAY section): a PERMANENT glow on every visible
-- icon of the group, not threshold-gated. Child frame rides button visibility;
-- StartSpecGlow's engine host renders Pixel as the genuine C-side dash march and
-- routes other driver styles to FlipBook so restricted content animates
-- identically; its change signature keeps a steady glow from resetting on restyles.
local BM_GLOW_SPEC = {}
local function ApplyBmIconGlow(btnFrame, dropdown, look)
    local Glows = CludesUI.Glows
    local specInfo = look.bmGlowInd
        and Glows.SpecFromPrefix(BM_GLOW_SPEC, look.bmGlowInd, "displayGlow", 1.0, 0.776, 0.376)
    if specInfo then
        local sz = look.width or 18
        local governor = dropdown.bmGlow
        if not governor then
            governor = CreateFrame("Frame", nil, btnFrame)
            governor:SetAllPoints(btnFrame)
            -- Just above the border, below the duration/stack text.
            if dropdown.stackCarrier then
                governor:SetFrameLevel(dropdown.stackCarrier:GetFrameLevel() - 1)
            else
                governor:SetFrameLevel(btnFrame:GetFrameLevel() + 1)
            end
            governor:EnableMouse(false)
            dropdown.bmGlow = governor
            Glows.PrewarmEngineHost(governor, sz, look.height or sz, ICON_GLOW_NEED)
            -- The button runs the glow's animations itself (only while it
            -- shows an aura), where the client can. A square registers no
            -- icon of its own: built in the creation window, it gets the
            -- hidden one that restarts its glow on a later change here.
            local AKit = CludesUI.AuraKit
            if
                Glows.BindEngineHost(governor, btnFrame, dropdown)
                and look.noRegions
                and AKit.InCreationWindow(btnFrame)
            then
                AKit.EnsureKickIcon(btnFrame, dropdown)
            end
        end
        -- A bound host glows on every button. Without that (WoW Forever) the
        -- animation plays while hidden too: only buttons the group can ever
        -- show run one.
        if Glows.IsEngineHostBound(governor) or CludesUI.AuraKit.ButtonCanShow(btnFrame) then
            Glows.StartSpecGlow(governor, specInfo, sz, look.height or sz, "engine")
        elseif governor._cuiGlowActive then
            Glows.StopGlow(governor)
        end
    elseif dropdown.bmGlow and dropdown.bmGlow._cuiGlowActive then
        Glows.StopGlow(dropdown.bmGlow)
    end
end

local function ApplyBmPandemicBorder(btnFrame, dropdown, look)
    -- Disabled displays allocate nothing. Opted-in chains register every pooled
    -- button at creation; per-member restyles only recolor the child textures.
    if not look.bmPandemicEnabled and not look.bmPandemicRegister and not dropdown.bmPandemic then return end
    -- The slot's extraInit sets bmRegistered right after this first style pass,
    -- so the holder is built and registered only inside the creation window.
    if not dropdown.bmPandemic and not dropdown.bmRegistered and btnFrame.AddPandemicRegion then
        local holderFrame = CreateFrame("Frame", nil, btnFrame)
        holderFrame:SetAllPoints(btnFrame)
        holderFrame:EnableMouse(false)
        holderFrame:Hide()
        dropdown.bmPandemic = holderFrame
        dropdown.bmPandemicEdges = {}
        for i = 1, 4 do
            dropdown.bmPandemicEdges[i] = holderFrame:CreateTexture(nil, "OVERLAY")
        end
        local topY, bottom, leftX, right = unpack(dropdown.bmPandemicEdges)
        topY:SetPoint("TOPLEFT")
        topY:SetPoint("TOPRIGHT")
        bottom:SetPoint("BOTTOMLEFT")
        bottom:SetPoint("BOTTOMRIGHT")
        leftX:SetPoint("TOPLEFT")
        leftX:SetPoint("BOTTOMLEFT")
        right:SetPoint("TOPRIGHT")
        right:SetPoint("BOTTOMRIGHT")
    end
    local holderFrame = dropdown.bmPandemic
    if not holderFrame then return end
    if dropdown.stackCarrier then holderFrame:SetFrameLevel(dropdown.stackCarrier:GetFrameLevel() - 1) end
    local width = look.bmPandemicWidth or 2
    local red, green, blue = BmColor(look.bmPandemicColor, 1, 0.2, 0.2)
    local alpha = look.bmPandemicEnabled and not look.hideIcon and 1 or 0
    local border = look.bmPandemicEnabled and look.bmPandemicTextured and look.border
    if
        border
        and (
            not border.texture
            or border.texture == "solid"
            or border.texture == ""
            or not CludesUI.ResolveBorderTexture(border.texture)
        )
    then
        border = nil
    end
    if border then
        local ring = dropdown.bmPandemicRing
        if not ring then
            ring = CreateFrame("Frame", nil, holderFrame)
            ring:SetPoint("CENTER", holderFrame, "CENTER")
            ring:EnableMouse(false)
            dropdown.bmPandemicRing = ring
        end
        ring:SetFrameLevel(holderFrame:GetFrameLevel())
        if dropdown.bmPandemicW ~= look.width or dropdown.bmPandemicH ~= look.height then
            ring:SetSize(look.width, look.height)
            dropdown.bmPandemicW, dropdown.bmPandemicH = look.width, look.height
        end
        -- The engine owns the holder's visibility; only draw on its child.
        CludesUI.ApplySecretSafeBorderStyle(
            ring,
            ring,
            border.size,
            red,
            green,
            blue,
            alpha,
            border.texture,
            border.offsetX,
            border.offsetY,
            border.shiftX,
            border.shiftY,
            "unitframes",
            border.size,
            nil,
            border.edgePx
        )
    elseif dropdown.bmPandemicRing then
        CludesUI.ApplySecretSafeBorderStyle(
            dropdown.bmPandemicRing,
            dropdown.bmPandemicRing,
            0,
            0,
            0,
            0,
            0,
            "solid"
        )
        dropdown.bmPandemicRing:Hide()
    end
    for i, edge in ipairs(dropdown.bmPandemicEdges) do
        if i <= 2 then
            edge:SetHeight(width)
        else
            edge:SetWidth(width)
        end
        edge:SetColorTexture(red, green, blue, border and 0 or alpha)
    end
    if not dropdown.bmPandemicBound then
        btnFrame:AddPandemicRegion(holderFrame)
        dropdown.bmPandemicBound = true
    end
end

-- Icon text, opacity and frame levels also apply to text-only indicators.
local function ApplyBmIconExtra(btnFrame, dropdown, look)
    ApplyRFDebuffText(btnFrame, dropdown, look)
    -- "Hide Icons" gate: like the hidden swipe (see AuraKit's style pass), a
    -- one-shot SetShown is undone by aura content churn -- the engine's display
    -- update re-shows the registered icon texture when the slot's aura data
    -- refreshes. Same two-layer defense reading a LIVE flag (a hook cannot
    -- uninstall): Show post-hook re-hides, alpha 0 covers engine paths that
    -- re-show outside the hooked Lua method. Hook installs lazily on first hide.
    if dropdown.icon then
        -- Match the unsnapped border strips at fractional icon edges.
        if CludesUI.PP then CludesUI.PP.DisablePixelSnap(dropdown.icon) end
        dropdown.bmHideIcon = look.hideIcon == true
        dropdown.icon:SetShown(not dropdown.bmHideIcon)
        if dropdown.bmHideIcon and not dropdown.bmIconHooked then
            dropdown.bmIconHooked = true
            local icon = dropdown.icon
            hooksecurefunc(icon, "Show", function()
                if dropdown.bmHideIcon then icon:Hide() end
            end)
        end
        local iconA = dropdown.bmHideIcon and 0 or 1
        if dropdown.bmIconAlpha ~= iconA then
            dropdown.icon:SetAlpha(iconA)
            dropdown.bmIconAlpha = iconA
        end
    end
    -- Button-object calls are denied while auras are secret: base level is read ONCE
    -- inside the creation window and cached; alpha/level writes are change-guarded
    -- with the stamp written AFTER the call (a denied write throws, deferring the key
    -- to the restriction-lift re-queue).
    local alpha = look.alpha or 1
    if dropdown.bmAlpha ~= alpha then
        btnFrame:SetAlpha(alpha)
        dropdown.bmAlpha = alpha
    end
    local base = dropdown.bmBase
    if not base then
        base = BmBaseLevel(btnFrame)
        dropdown.bmBase = base
    end
    local lvl = base + (look.levelOffset or 13)
    if dropdown.bmLvl ~= lvl then
        btnFrame:SetFrameLevel(lvl)
        dropdown.bmLvl = lvl
    end
    if dropdown.cooldown then dropdown.cooldown:SetFrameLevel(lvl + 1) end
    if dropdown.borderHost then dropdown.borderHost:SetFrameLevel(lvl + 1) end
    if dropdown.stackCarrier then dropdown.stackCarrier:SetFrameLevel(base + BM_FRAMELVL_TEXT) end
    BmRebindDurationCurve(btnFrame, dropdown, look)
    ApplyBmIconGlow(btnFrame, dropdown, look)
    ApplyBmPandemicBorder(btnFrame, dropdown, look)
end

-- Buff/HoT tooltip gate (profile-root "Hide Buff Tooltips", default hidden). Engine
-- aura buttons render their own tooltip when mouse motion is on, showing the real
-- aura even while secret; effect slots (healthcolor/border) stay motion-off always
-- (they overlay the health bar). 4-state mode: true/nil=hidden, false=shown,
-- "combat"=hidden in combat, "cursor"=shown at cursor.
local function BuffTipMode()
    local p = mod.db and mod.db.profile
    local val = p and p.buffHideTooltips
    if val == nil then val = true end
    return val
end

local function BuffTipsOff()
    local val = BuffTipMode()
    return not (val == false or val == "combat" or val == "cursor")
end

local function BuildBmIconStyle(indicator, iconScale, px)
    local hideIcon = indicator.hideIcon == true
    return {
        width = px,
        height = px,
        iconCrop = true,
        iconZoom = (mod.db and mod.db.profile and mod.db.profile.bmIconZoom) or 0.08,
        hideIcon = hideIcon,
        border = not hideIcon and mod.RFC_AuraBorder(indicator, "indBorder") or nil,
        cooldownReverse = true,
        hideSwipe = hideIcon or (indicator.showDuration == false),
        noDefaultFonts = true,
        hideDurationText = not indicator.showDurationText,
        durSize = indicator.durationTextSize,
        durColor = indicator.durationTextColor,
        durOffX = indicator.durationTextOffsetX,
        durOffY = indicator.durationTextOffsetY,
        durationColorCurve = BmThresholdCurve(indicator),
        showStacks = indicator.showStacks ~= false,
        stackSize = indicator.stacksTextSize,
        stackColor = indicator.stacksTextColor,
        stackOffX = indicator.stacksOffsetX or -1,
        stackOffY = indicator.stacksOffsetY or 2,
        alpha = (indicator.iconOpacity or 100) / 100,
        levelOffset = BM_FRAMELVL[indicator.frameLevel or "medium"] or 13,
        noTooltips = BuffTipsOff(),
        tooltipCombatHide = BuffTipMode() == "combat",
        tooltipAnchor = (BuffTipMode() == "cursor") and "cursor" or nil,
        bmGlowInd = indicator,
        bmPandemicEnabled = BmPandemicOn(indicator),
        bmPandemicTextured = indicator.pandemicBorderTextured == true,
        bmPandemicColor = indicator.pandemicBorderColor,
        bmPandemicWidth = indicator.pandemicBorderWidth or 2,
        applyExtra = ApplyBmIconExtra,
    }
end

-- PP border on a bare-slot host with create-once semantics, so border size
-- can toggle from 0 without a container swap.
local function BmUpdateBorder(dropdown, host, px, red, green, blue, a)
    local Pix = CludesUI.PP
    if not (Pix and host) then return end
    if (px or 0) > 0 then
        if dropdown.bmBorderMade then
            Pix.UpdateBorder(host, px, red, green, blue, a)
        else
            Pix.CreateBorder(host, red, green, blue, a, px, "OVERLAY", 7)
            dropdown.bmBorderMade = true
        end
        host:Show()
    else
        host:Hide()
    end
end

-- Bare-slot styling passes run at init (guarded: regions may not exist yet on the
-- first ApplyStyleToRegions call) and on every Restyle, so square/bar/effect settings
-- live-update like everything else. Each style table carries its indicator as style.ind.
local function BmApplySquare(btnFrame, dropdown, look)
    if not dropdown.tex then return end
    local indicator = look.ind
    local red, green, blue = BmColor(look.sqColor, 76 / 255, 201 / 255, 240 / 255)
    dropdown.tex:SetColorTexture(red, green, blue, 1)
    -- Same hidden-swipe gate as AuraKit's style pass (engine SetCooldown re-shows
    -- a hidden swipe on aura churn; SetDrawSwipe is the persistent style knob
    -- that survives it), needed here too because square cooldowns are created
    -- AFTER the bare-mode style pass runs -- creation would otherwise ship
    -- ungated. Shares the akHideSwipe stamp so the two drivers never fight.
    if dropdown.cooldown then
        local hideSwipe = indicator.showDuration == false
        dropdown.cooldown:SetShown(not hideSwipe)
        if dropdown.akHideSwipe ~= hideSwipe then
            dropdown.akHideSwipe = hideSwipe
            if dropdown.cooldown.SetDrawSwipe then dropdown.cooldown:SetDrawSwipe(not hideSwipe) end
        end
    end
    ApplyRFDebuffText(btnFrame, dropdown, look)
    -- Cached base + change-guarded level: see ApplyBmIconExtra.
    local base = dropdown.bmBase
    if not base then
        base = BmBaseLevel(btnFrame)
        dropdown.bmBase = base
    end
    local lvl = base + (BM_FRAMELVL[indicator.frameLevel or "medium"] or 13)
    if dropdown.bmLvl ~= lvl then
        btnFrame:SetFrameLevel(lvl)
        dropdown.bmLvl = lvl
    end
    -- Once the host was re-anchored for an explicit size (rfBorderSize) it stays on
    -- this path, which keeps that size current; the legacy path below never resizes it.
    if
        indicator.indBorderTexture
        or indicator.indBorderSizePx
        or dropdown._secretBorderEdges
        or dropdown.rfBorderSize
    then
        if dropdown.rfBorderSize ~= look.width then
            if not dropdown.rfBorderSize then
                dropdown.borderHost:ClearAllPoints()
                dropdown.borderHost:SetPoint("CENTER", btnFrame, "CENTER")
            end
            dropdown.borderHost:SetSize(look.width, look.height)
            dropdown.rfBorderSize = look.width
        end
        mod.RFC_ApplyAuraBorder(
            dropdown.borderHost,
            dropdown,
            look.bmBorder,
            dropdown.cooldown:GetFrameLevel()
        )
    else
        local br, bg2, bb = BmColor(indicator.indBorderColor, 0, 0, 0)
        BmUpdateBorder(
            dropdown,
            dropdown.borderHost,
            indicator.indBorderSize or 1,
            br,
            bg2,
            bb,
            indicator.indBorderColor and indicator.indBorderColor.a or 1
        )
    end
    if dropdown.stackCarrier then dropdown.stackCarrier:SetFrameLevel(base + BM_FRAMELVL_TEXT) end
    BmRebindDurationCurve(btnFrame, dropdown, look)
end

local function BmApplyBar(btnFrame, dropdown, look)
    if not dropdown.bar then return end
    -- Bars have no ApplyRFDebuffText pass, so the tooltip motion gate is
    -- applied here (same change-guard as the shared applier).
    if btnFrame.SetMouseMotionEnabled then
        local motion = not look.noTooltips
        if dropdown.rfMotion ~= motion then
            dropdown.rfMotion = motion
            btnFrame:SetMouseMotionEnabled(motion)
        end
    end
    local indicator = look.ind
    local red, green, blue = BmColor(indicator.color, 76 / 255, 201 / 255, 240 / 255)
    dropdown.bar
        :GetStatusBarTexture()
        :SetVertexColor(red, green, blue, (indicator.barColorOpacity or 100) / 100)
    -- Fill AXIS, mirroring what the preview has always done in BM_PlaceBar.
    -- Change-guarded like the frame-level write below: SetOrientation resets the
    -- bar's fill, so calling it on every restyle would visibly stutter a running
    -- bar. Orientation has to be in BmVisualKey for this to run at all -- it
    -- otherwise lives only in the geometry fingerprint, which drives the anchor
    -- pass and never reaches here.
    local isVert = (indicator.orientation or "HORIZONTAL") == "VERTICAL"
    if dropdown.bmBarVert ~= isVert then
        dropdown.bmBarVert = isVert
        dropdown.bar:SetOrientation(isVert and "VERTICAL" or "HORIZONTAL")
    end
    dropdown.bar:SetReverseFill(indicator.reverseFill == true)
    local bgr, bgg, bgb = BmColor(indicator.barBgColor, 0, 0, 0)
    dropdown.barBg:SetColorTexture(bgr, bgg, bgb, (indicator.barBgOpacity or 50) / 100)
    -- Cached base + change-guarded level: see ApplyBmIconExtra.
    local base = dropdown.bmBase
    if not base then
        base = BmBaseLevel(btnFrame)
        dropdown.bmBase = base
    end
    local lvl = base + (BM_FRAMELVL[indicator.frameLevel or "behindBorders"] or 7)
    if dropdown.bmLvl ~= lvl then
        btnFrame:SetFrameLevel(lvl)
        dropdown.bmLvl = lvl
    end
end

-- Textured Background on a Background Color effect: the class's background texture
-- (style.texBgPath, set with the style) under the effect's tint; its style key
-- carries it, so a change restyles.
function mod.RFC_BmTexBg(look, s)
    look.texBgPath, look.texBgVert = mod.RF_TexBgPath(s), mod.RF_IsVerticalFill(s)
end
function mod.RFC_BmTexBgKey(s)
    return "|" .. tostring(mod.RF_TexBgPath(s)) .. (mod.RF_IsVerticalFill(s) and "v" or "")
end
local function BmApplyEffect(btnFrame, dropdown, look)
    local indicator = look.ind
    if indicator.type == "healthcolor" or indicator.type == "bgcolor" then
        if dropdown.tex then
            local red, green, blue = BmColor(indicator.color, 0, 1, 0)
            local a = (indicator.opacity or 100) / 100
            -- healthcolor rides the fill and borrows its texture; bgcolor covers
            -- the bar's background, which is a flat color fill, so it stays flat.
            if indicator.type == "healthcolor" then
                mod.RF_TintOverBarFill(dropdown.tex, dropdown.bmHealthBar, red, green, blue, a)
            else
                mod.RF_TexBgTint(dropdown.tex, look.texBgPath, look.texBgVert)
                dropdown.tex:SetColorTexture(red, green, blue, a)
            end
        end
    elseif indicator.type == "border" then
        -- Full legacy renderer (solid/dashed/textured/sweep) on the border host --
        -- our frame, legal on every restyle. Sweep renders fully lit (no aura-driven
        -- ticker under secrecy); dashed uses the C-side animated ants (w/h from the
        -- unit frame's own rect -- the forbidden host is never measured).
        if dropdown.borderHost and mod.BM_ApplyEffectBorder then
            local red, green, blue = BmColor(indicator.color, 0.30, 0.79, 0.94)
            local host = dropdown.bmFxHost
            local wid, hgt
            if host then
                wid, hgt = host:GetWidth(), host:GetHeight()
            end
            mod.BM_ApplyEffectBorder(
                dropdown.borderHost,
                indicator,
                red,
                green,
                blue,
                (indicator.borderOpacity or 100) / 100,
                wid,
                hgt
            )
            dropdown.borderHost:Show()
        end
    end
end

-- Bare-slot extraInits: region creation only (once per slot button); styling flows
-- through the apply passes above. Squares/bars start mouse-transparent and the apply
-- pass re-drives motion per the buff tooltip setting; effect slots stay transparent
-- always (they overlay the health bar/unit button).
local function BmSquareInit(btnFrame, dropdown, look, indicator, healthBar)
    if btnFrame.SetMouseMotionEnabled then btnFrame:SetMouseMotionEnabled(false) end
    dropdown.tex = btnFrame:CreateTexture(nil, "ARTWORK")
    dropdown.tex:SetAllPoints(btnFrame)

    local cd = CreateFrame("Cooldown", nil, btnFrame, "CooldownFrameTemplate")
    cd:SetAllPoints(btnFrame)
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)
    dropdown.cooldown = cd
    btnFrame:SetDurationCooldown(cd)

    dropdown.borderHost = CreateFrame("Frame", nil, btnFrame)
    dropdown.borderHost:SetAllPoints(btnFrame)
    dropdown.borderHost:SetFrameLevel(btnFrame:GetFrameLevel() + 1)

    -- Duration/stack text, same carrier arrangement as standard icon regions (above
    -- the swipe). Fonts MUST be applied before the engine registrations below.
    dropdown.stackCarrier = CreateFrame("Frame", nil, btnFrame)
    dropdown.stackCarrier:SetAllPoints(btnFrame)
    dropdown.stackCarrier:SetFrameLevel(cd:GetFrameLevel() + 1)
    dropdown.stack = dropdown.stackCarrier:CreateFontString(nil, "OVERLAY")
    dropdown.duration = dropdown.stackCarrier:CreateFontString(nil, "OVERLAY")

    BmApplySquare(btnFrame, dropdown, look)

    btnFrame:SetApplicationCount(dropdown.stack, {})
    local durationOpts = AK.BuildDurationTextOpts(AK.GetDurationFormatter(), look.durationColorCurve)
    local _, full = AK.SetDurationTextSafe(btnFrame, dropdown.duration, durationOpts)
    dropdown.bmRegistered = true
    -- Creation-window registration is always legal; the curve stamp still follows the
    -- full-success rule so a rejected curve half re-binds next restyle, not skipped.
    if full or not look.durationColorCurve then dropdown.bmCurve = look.durationColorCurve end
end

local function BmBarInit(btnFrame, dropdown, look, indicator, healthBar)
    if btnFrame.SetMouseMotionEnabled then btnFrame:SetMouseMotionEnabled(false) end
    local bar = CreateFrame("StatusBar", nil, btnFrame)
    bar:SetAllPoints(btnFrame)
    bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    dropdown.bar = bar
    dropdown.barBg = bar:CreateTexture(nil, "BACKGROUND")
    dropdown.barBg:SetAllPoints(bar)

    -- Fill AXIS. A StatusBar defaults to HORIZONTAL, so a vertical bar rendered
    -- tall and narrow (BmAnchorOneSlot) while still draining sideways until this
    -- landed. Set BEFORE the engine registration below in case the axis is
    -- snapshotted there; BmApplyBar re-drives it for live toggles.
    local initVert = ((look.ind and look.ind.orientation) or "HORIZONTAL") == "VERTICAL"
    bar:SetOrientation(initVert and "VERTICAL" or "HORIZONTAL")
    dropdown.bmBarVert = initVert

    local options = {}
    if Enum.StatusBarInterpolation then options.interpolation = Enum.StatusBarInterpolation.Immediate end
    if Enum.StatusBarTimerDirection then options.direction = Enum.StatusBarTimerDirection.RemainingTime end
    btnFrame:SetDurationBar(bar, options)

    BmApplyBar(btnFrame, dropdown, look)
end

local function BmEffectInit(btnFrame, dropdown, look, indicator, healthBar)
    if btnFrame.SetMouseMotionEnabled then btnFrame:SetMouseMotionEnabled(false) end
    if indicator.type == "healthcolor" then
        -- Level-tied with the health frame (NOT +1): sort against health's own ARTWORK
        -- sublevels (above fill at 0), staying BELOW heal absorb/prediction (health +1)
        -- and shield bars (+3). At +1 this tied heal absorb on strata+level+layer+
        -- sublevel, so paint order fell to creation order and the tint blended over an
        -- opaque heal absorb. Anchored to the current-health area (the fill texture, or
        -- the rest of the bar under Inverted Fill) so missing health never tints.
        btnFrame:SetFrameLevel(healthBar:GetFrameLevel())
        dropdown.bmHealthBar = healthBar -- apply pass borrows this bar's fill texture
        dropdown.tex = btnFrame:CreateTexture(nil, "ARTWORK", nil, 2)
        mod.RF_AnchorCurHealth(
            dropdown.tex,
            healthBar,
            healthBar.GetStatusBarTexture and healthBar:GetStatusBarTexture()
        )
        mod.RF_RegisterBarTint(healthBar, dropdown.tex, nil, "bm")
    elseif indicator.type == "bgcolor" then
        -- Background Color: whole health area, ARTWORK -2 = below fill (sublevel 0)
        -- and healthcolor tint (+2), above the bar's own backdrop -- reads as bg.
        btnFrame:SetFrameLevel(healthBar:GetFrameLevel())
        dropdown.tex = btnFrame:CreateTexture(nil, "ARTWORK", nil, -2)
        dropdown.tex:SetAllPoints(healthBar)
    elseif indicator.type == "border" then
        local unitButton = btnFrame:GetParent() and btnFrame:GetParent():GetParent()
        if unitButton then
            -- Slot button sits AT the unit button's level: legacy renderer
            -- (BM_ApplyEffectBorder) levels the host at parent + LVL_RAISE - 1,
            -- under the hover raise and the text band -- exact live parity.
            btnFrame:SetFrameLevel(unitButton:GetFrameLevel())
            dropdown.borderHost = CreateFrame("Frame", nil, btnFrame)
            -- The Party Frames kit outlines the visible party frame (our
            -- host frame) instead of the whole button box.
            local fxHost = (healthBar and healthBar._cuiKitRef) or unitButton
            dropdown.borderHost:SetAllPoints(fxHost)
            -- OUR secure unit button (or the kit host), outside the forbidden
            -- subtree: apply pass reads its rect for the dashed-style animated
            -- ants (border host is unmeasurable outside this window).
            dropdown.bmFxHost = fxHost
            -- The dashed style's animated ants run on the slot button itself
            -- (only while it shows an aura), where the client can. The slot
            -- registers no icon: a dashed border gets the hidden one that
            -- restarts its march on a later change here.
            if
                CludesUI.Glows.BindEngineHost(dropdown.borderHost, btnFrame, dropdown)
                and indicator.borderStyle == "dashed"
            then
                AK.EnsureKickIcon(btnFrame, dropdown)
            end
        end
    end
    BmApplyEffect(btnFrame, dropdown, look)
end

-- Style factory per indicator kind; size only matters for icon/square,
-- spellID only for square (per-spell color; nil for shared chain styles).
local function BuildBmStyleFor(kindName, indicator, iconScale, px, spellId)
    if kindName == "icon" then return BuildBmIconStyle(indicator, iconScale, px) end
    if kindName == "square" then
        return {
            width = px,
            height = px,
            noRegions = true,
            ind = indicator,
            bmBorder = mod.RFC_AuraBorder(indicator, "indBorder"),
            sqColor = BmSquareColor(indicator, spellId),
            noDefaultFonts = true,
            bmGlowInd = indicator,
            hideSwipe = (indicator.showDuration == false),
            hideDurationText = not indicator.showDurationText,
            durSize = indicator.durationTextSize,
            durColor = indicator.durationTextColor,
            durOffX = indicator.durationTextOffsetX,
            durOffY = indicator.durationTextOffsetY,
            durationColorCurve = BmThresholdCurve(indicator),
            showStacks = indicator.showStacks ~= false,
            stackSize = indicator.stacksTextSize,
            stackColor = indicator.stacksTextColor,
            stackOffX = indicator.stacksOffsetX or -1,
            stackOffY = indicator.stacksOffsetY or 2,
            noTooltips = BuffTipsOff(),
            tooltipCombatHide = BuffTipMode() == "combat",
            tooltipAnchor = (BuffTipMode() == "cursor") and "cursor" or nil,
            -- Squares share the display-level Icon Glow (same overlay child
            -- mechanism; the control sits on the shared icon/square pane).
            applyExtra = function(b, d2, state)
                BmApplySquare(b, d2, state)
                ApplyBmIconGlow(b, d2, state)
            end,
        }
    end
    if kindName == "bar" then
        return {
            width = 1,
            height = 1,
            noRegions = true,
            ind = indicator,
            noTooltips = BuffTipsOff(),
            tooltipCombatHide = BuffTipMode() == "combat",
            tooltipAnchor = (BuffTipMode() == "cursor") and "cursor" or nil,
            applyExtra = BmApplyBar,
        }
    end
    return { width = 1, height = 1, noRegions = true, ind = indicator, applyExtra = BmApplyEffect }
end

-- Geometry for ONE slot button, split out of AnchorBmSlots so each slot's extraInit
-- can self-anchor inside the creation window -- the only place SetSize/SetPoint is
-- legal while auras are secret (12.1 access restriction; BM builds run mid-instance:
-- joiners, in-key reloads). AnchorBmSlots re-runs it OOC on geometry changes.
local function BmAnchorOneSlot(frame, m, healthBar, hugBar, iconScale)
    local indicator = m.ind
    if m.kind == "icon" or m.kind == "square" then
        local px = m.size
        local step = px + (indicator.spacing or 0) * iconScale
        local cursor = (m.k - 1) * step
        local growDir = indicator.growDirection or "RIGHT"
        if growDir == "CENTER" then cursor = cursor - ((m.count - 1) * step) / 2 end
        local gx, gy = 0, 0
        if growDir == "LEFT" then
            gx = -cursor
        elseif growDir == "DOWN" then
            gy = -cursor
        elseif growDir == "UP" then
            gy = cursor
        else
            gx = cursor
        end
        local place = indicator.position or "TOPLEFT"
        frame:SetSize(px, px)
        frame:ClearAllPoints()
        frame:SetPoint(
            place,
            healthBar,
            place,
            (indicator.offsetX or 0) * iconScale + gx,
            (indicator.offsetY or 0) * iconScale + gy
        )
    elseif m.kind == "bar" then
        -- Mirrors the legacy BM_PlaceBar rules onto the slot button.
        local wid = (indicator.barWidth or 30) * iconScale
        local hgt = (indicator.barHeight or 4) * iconScale
        local isVert = (indicator.orientation or "HORIZONTAL") == "VERTICAL"
        local fullW, fullH
        if isVert then
            fullW, fullH = indicator.barFullHeight, indicator.barFullWidth
        else
            fullW, fullH = indicator.barFullWidth, indicator.barFullHeight
        end
        frame:ClearAllPoints()
        if fullW and fullH then
            frame:SetAllPoints(hugBar)
        elseif fullW then
            local place = indicator.position or "TOPLEFT"
            local vEdge = (place:find("BOTTOM", 1, true) and "BOTTOM")
                or (place:find("TOP", 1, true) and "TOP")
                or ""
            local oy = (indicator.offsetY or 0) * iconScale
            frame:SetPoint(vEdge .. "LEFT", healthBar, vEdge .. "LEFT", 0, oy)
            frame:SetPoint(vEdge .. "RIGHT", healthBar, vEdge .. "RIGHT", 0, oy)
            frame:SetHeight(isVert and wid or hgt)
        elseif fullH then
            local place = indicator.position or "TOPLEFT"
            local hEdge = (place:find("RIGHT", 1, true) and "RIGHT")
                or (place:find("LEFT", 1, true) and "LEFT")
                or ""
            local ox = (indicator.offsetX or 0) * iconScale
            frame:SetPoint("TOP" .. hEdge, hugBar, "TOP" .. hEdge, ox, 0)
            frame:SetPoint("BOTTOM" .. hEdge, hugBar, "BOTTOM" .. hEdge, ox, 0)
            frame:SetWidth(isVert and hgt or wid)
        else
            if isVert then
                frame:SetSize(hgt, wid)
            else
                frame:SetSize(wid, hgt)
            end
            frame:SetPoint(
                indicator.position or "TOPLEFT",
                healthBar,
                indicator.position or "TOPLEFT",
                (indicator.offsetX or 0) * iconScale,
                (indicator.offsetY or 0) * iconScale
            )
        end
    else
        -- Effect slots just need to exist somewhere; their regions
        -- anchor to the health bar / unit button themselves.
        frame:SetSize(1, 1)
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", healthBar, "CENTER")
    end
end

-- Builds the slot spec list for the current indicator set plus the group-mode chain
-- indicators (rendered as compacting flow containers).
local function BuildBmSlots(inds, d, healthBar, iconScale, styleBase)
    local slots, metaRec, chains = {}, {}, {}
    for i = 1, #inds do
        local indicator = inds[i]
        if indicator.enabled and indicator.type ~= "framealpha" then
            local spellList = {}
            for k = 1, #(indicator.spells or {}) do
                local spellRef = indicator.spells[k]
                spellList[#spellList + 1] = spellRef
            end
            local kindName = indicator.type or "icon"
            if (kindName == "icon" or kindName == "square") and BmChainMode(indicator) == "g" then
                if #spellList > 0 then
                    chains[#chains + 1] = { ind = indicator, spells = spellList, idx = i }
                end
            elseif kindName == "icon" or kindName == "square" or kindName == "bar" then
                for k = 1, #spellList do
                    local spellId = spellList[k]
                    local px = mod.RFC_BmSize(indicator, iconScale)
                    local slotKey = "bm" .. tostring(indicator.id or ("x" .. i)) .. "_" .. k
                    local lookKey = styleBase .. ":" .. tostring(indicator.id or ("x" .. i)) .. ":" .. k
                    -- Meta entry built FIRST so extraInit closures below can self-
                    -- anchor inside the creation window (post-creation SetPoint/
                    -- SetSize is denied while auras are secret -- 12.1 restriction).
                    local mm = {
                        key = slotKey,
                        styleKey = lookKey,
                        ind = indicator,
                        k = k,
                        count = #spellList,
                        kind = kindName,
                        size = px,
                        spellID = spellId,
                    }
                    local record = {
                        key = slotKey,
                        filter = BuildBmFilter(indicator),
                        candidateFilters = BuildBmCand(indicator, nil, spellId),
                        style = lookKey,
                    }
                    AK.styles[lookKey] = BuildBmStyleFor(kindName, indicator, iconScale, px, spellId)
                    if kindName == "icon" then
                        record.extraInit = function(btn, dropdown, state)
                            dropdown.bmRegistered = true
                            dropdown.bmCurve = state.durationColorCurve
                            local hgt = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, ScaleProxy(d))
                                or healthBar
                            BmAnchorOneSlot(btn, mm, hgt, hgt and (hgt._cuiHealth or hgt), iconScale)
                        end
                    elseif kindName == "square" then
                        record.extraInit = function(btn, dropdown, state)
                            BmSquareInit(btn, dropdown, state, indicator, healthBar)
                            local hgt = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, ScaleProxy(d))
                                or healthBar
                            BmAnchorOneSlot(btn, mm, hgt, hgt and (hgt._cuiHealth or hgt), iconScale)
                        end
                    elseif kindName == "bar" then
                        record.extraInit = function(btn, dropdown, state)
                            BmBarInit(btn, dropdown, state, indicator, healthBar)
                            local hgt = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, ScaleProxy(d))
                                or healthBar
                            BmAnchorOneSlot(btn, mm, hgt, hgt and (hgt._cuiHealth or hgt), iconScale)
                        end
                    end
                    slots[#slots + 1] = record
                    metaRec[#metaRec + 1] = mm
                end
            elseif kindName == "healthcolor" or kindName == "bgcolor" or kindName == "border" then -- effect slots
                -- showWhen is deliberately IGNORED here: only "When Any Present"
                -- is reproducible on 12.1 (see the header note -- the counting
                -- workaround is engine-forbidden), and the pre-heal behavior of
                -- skipping the slot for other stored modes rendered NOTHING
                -- silently (field report). A stale "allPresent"/"missing" config
                -- now renders presence-driven; the options pane offers only the
                -- supported mode.
                local slotKey = "bm" .. tostring(indicator.id or ("x" .. i)) .. "_fx"
                local lookKey = styleBase .. ":" .. tostring(indicator.id or ("x" .. i)) .. ":fx"
                AK.styles[lookKey] = BuildBmStyleFor(kindName, indicator, iconScale, 1)
                if kindName == "bgcolor" then mod.RFC_BmTexBg(AK.styles[lookKey], ScaleProxy(d)) end
                local mm = {
                    key = slotKey,
                    styleKey = lookKey,
                    ind = indicator,
                    kind = kindName,
                    spells = spellList,
                }
                slots[#slots + 1] = {
                    key = slotKey,
                    filter = BuildBmFilter(indicator),
                    candidateFilters = BuildBmCand(indicator, spellList),
                    style = lookKey,
                    extraInit = function(btn, dropdown, state)
                        BmEffectInit(btn, dropdown, state, indicator, healthBar)
                        -- Self-park in the creation window (see icon branch).
                        local hgt = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, ScaleProxy(d))
                            or healthBar
                        BmAnchorOneSlot(btn, mm, hgt, hgt and (hgt._cuiHealth or hgt), iconScale)
                    end,
                }
                metaRec[#metaRec + 1] = mm
            end
        end
    end
    -- Anchor To (icon->icon/square->square): an anchored indicator's group renders
    -- INSIDE its target's container, continuing that run. Declaration-time composition
    -- only -- group count matches unanchored (one per indicator); attached indicators
    -- just lose their own container. Broken links (missing, disabled, type-mismatch,
    -- slot-mode targets, cycles) fall back to the indicator's own position.
    do
        local byId = {}
        for i = 1, #chains do
            local ident = chains[i].ind.id
            if ident ~= nil then byId[ident] = chains[i] end
        end
        local function ResolveRoot(childFrame)
            local seen = { [childFrame] = true }
            local current = childFrame
            while true do
                local tid = current.ind.anchorTo
                if tid == nil then return current end
                local nxt = byId[tid]
                if not nxt or seen[nxt] or (nxt.ind.type or "icon") ~= (childFrame.ind.type or "icon") then
                    return nil
                end
                seen[nxt] = true
                current = nxt
            end
        end
        local roots, attach, anyAnchor = {}, {}, false
        for i = 1, #chains do
            local childFrame = chains[i]
            local root = childFrame.ind.anchorTo and ResolveRoot(childFrame) or childFrame
            if root == nil or root == childFrame then
                roots[#roots + 1] = childFrame
            else
                anyAnchor = true
                local a = attach[root]
                if not a then
                    a = {}
                    attach[root] = a
                end
                a[#a + 1] = childFrame
            end
        end
        if anyAnchor then
            for i = 1, #roots do
                local a = attach[roots[i]]
                if a then
                    table.sort(a, function(posX, posY) return (posX.ind.id or 0) < (posY.ind.id or 0) end)
                    roots[i].members = a
                end
            end
            chains = roots
        end
    end
    return slots, metaRec, chains
end

-- Anchors a chain container so its flow starts at the indicator position and compacts
-- along the grow direction. Rule: the FIRST icon's `pos` corner sits exactly on the
-- same corner of the health bar (icons render INSIDE the frame there), and the chain
-- grows outward -- so the flow's start corner offsets by one element dimension on any
-- axis disagreeing with the position point (half a dimension on centered axes).
-- CENTER growth keeps the run centered on the position point, vertical edge flush.
-- members = array of { ind, count }; members[1] is the ROOT driving position/growth/
-- wrap. Attached members (Anchor To) each contribute one flow group with their own
-- element size and Max Icons cap.
local function AnchorBmChainContainer(boxHolder, healthBar, members, iconScale)
    if not boxHolder then return end
    local indicator = members[1].ind
    local place = indicator.position or "TOPLEFT"
    local growDir = indicator.growDirection or "RIGHT"
    local px = mod.RFC_BmSize(indicator, iconScale)
    local ox = (indicator.offsetX or 0) * iconScale
    local oy = (indicator.offsetY or 0) * iconScale

    local posL = place:find("LEFT", 1, true) ~= nil
    local posR = place:find("RIGHT", 1, true) ~= nil
    local posT = place:find("TOP", 1, true) ~= nil
    local posB = place:find("BOTTOM", 1, true) ~= nil

    local per = tonumber(indicator.iconsPerRow) or 0

    boxHolder:ClearAllPoints()
    local gH, gV
    if growDir == "CENTER" then
        local point = (posT and "TOP") or (posB and "BOTTOM") or "CENTER"
        boxHolder:SetPoint(point, healthBar, place, ox, oy)
        -- Wrapped rows stack away from the anchored edge (simple-grid
        -- convention); the flow origin corner follows the stack direction.
        gH = "RIGHT"
        gV = (per > 0 and posB) and "UP" or "DOWN"
        AK.SetContainerAnchor(boxHolder, (gV == "UP") and "BOTTOMLEFT" or "TOPLEFT")
    else
        gH = (growDir == "LEFT") and "LEFT" or "RIGHT"
        gV = (growDir == "UP") and "UP" or "DOWN"
        -- Wrap away from the anchored edge (simple-grid convention): cross-axis
        -- component only applies once wrapping is on; unwrapped = legacy single-run.
        if per > 0 then
            if growDir == "LEFT" or growDir == "RIGHT" then
                -- (wrapUp: the Party Frames kit's run above a frame.)
                gV = (posB or indicator.wrapUp) and "UP" or "DOWN"
            else
                gH = posR and "LEFT" or "RIGHT"
            end
        end
        -- Flow origin corner = the corner both growth directions point away
        -- from; identical to the old fixed pick for every unwrapped combo.
        local corner = ((gV == "UP") and "BOTTOM" or "TOP") .. ((gH == "LEFT") and "RIGHT" or "LEFT")
        local dx, dy = 0, 0
        if corner:find("LEFT", 1, true) then
            if posR then
                dx = -px
            elseif not posL then
                dx = -px / 2
            end
        else
            if posL then
                dx = px
            elseif not posR then
                dx = px / 2
            end
        end
        if corner:find("TOP", 1, true) then
            if posB then
                dy = px
            elseif not posT then
                dy = px / 2
            end
        else
            if posT then
                dy = -px
            elseif not posB then
                dy = -px / 2
            end
        end
        boxHolder:SetPoint(corner, healthBar, place, ox + dx, oy + dy)
        AK.SetContainerAnchor(boxHolder, corner)
    end
    AK.SetContainerGrowth(boxHolder, FlowDir(gH), FlowDir(gV))
    local spacing = (indicator.spacing or 0) * iconScale
    local vertical = (growDir == "UP" or growDir == "DOWN")
    -- Grid wrap (12.1 feature -- live indicators were always linear runs): Icons Per
    -- Row > 0 caps each line at n cells; vertical orientations flip the flow axis so
    -- lines are COLUMNS (n tall, wrapping sideways). 0/nil = one unbounded line (exact
    -- pre-grid behavior; explicit axis reset keeps pooled containers clean across retargets).
    if per > 0 then
        AK.SetContainerAxis(boxHolder, vertical)
        AK.SetContainerRowWidth(boxHolder, per * px + (per - 1) * spacing + 0.4)
    else
        AK.SetContainerAxis(boxHolder, false)
        AK.SetContainerRowWidth(boxHolder, vertical and (px + 0.4) or nil)
    end

    -- Element size/spacing feed the FLOW math (button SetSize is only physical size),
    -- so geometry changes re-drive group layouts. One layout per group (a Custom
    -- Order member contributes one group per SEGMENT -- see BmSegments; entries then
    -- carry memberIndex/segIndex, plain arrays behave as one segment per member):
    -- anchored members keep their own element size; layoutIndex pins flow order (root
    -- first) so lazily re-declared groups never reorder. Inter-group gap matches the
    -- root's icon spacing so the seam reads as one continuous run.
    local budgets = {}
    for jdx = 1, #members do
        local mm = members[jdx]
        local gk = (jdx == 1) and "chain" or ("chain" .. jdx)
        local msize = mod.RFC_BmSize(mm.ind, iconScale)
        local mi = mm.memberIndex or jdx
        -- Anchored members: Offset X/Y projects onto the run as the gap between
        -- their group and the previous one (only per-group positional lever a shared
        -- flow offers; cross-axis has no engine expression). Sign follows flow
        -- direction, so positive always pushes the member further along the run.
        -- Applies only at a MEMBER boundary; a member's own later segments keep the
        -- plain icon spacing so its run stays continuous.
        local mGap = spacing
        if jdx > 1 and (mm.segIndex or 1) <= 1 and mi > 1 then
            local off
            if vertical then
                off = (mm.ind.offsetY or 0)
                if gV == "DOWN" then off = -off end
            else
                off = (mm.ind.offsetX or 0)
                if gH == "LEFT" then off = -off end
            end
            -- Negative values pull the member back along the run (overlap
            -- is legitimate -- parity with what a free offset could do).
            mGap = spacing + off * iconScale
        end
        boxHolder:SetAuraGroupLayout(gk, {
            elementWidth = msize,
            elementHeight = msize,
            elementSpacing = spacing,
            lineSpacing = spacing,
            groupSpacing = mGap,
            layoutIndex = jdx,
        })
        -- Max Icons: cap each member's groups below its own spell count.
        -- Runs here so both the acquire path and the geometry pass re-drive
        -- it live (the setter is dirty-mark cheap on unchanged values).
        -- Segmented members spend ONE member-wide budget along the arranged
        -- order, so Max Icons means "first N configured" there (which groups
        -- are ACTIVE is secret in combat -- a live first-N-active cap is
        -- inexpressible); trailing segments zero out.
        local cap = mm.count or 0
        if cap > 0 then
            local maxI = tonumber(mm.ind.maxIcons) or 0
            if maxI > 0 then
                local rem = budgets[mi]
                if rem == nil then rem = maxI end
                if cap > rem then cap = rem end
                budgets[mi] = rem - cap
            end
            CludesUI.AuraKit.SetGroupCap(boxHolder, gk, cap)
        end
    end
end

-- Per-styleKey fingerprint of the visual fields each BM style/apply pass
-- reads; restyles run only when one actually changed (styles are shared
-- per class, so the first button's check covers the rest). Primed at
-- container creation so swaps don't trigger a follow-up restyle storm.
local bmStyleFP = {}

-- Per-class fingerprint of own-only state; changes re-drive slot candidate
-- filters live (slots support that) instead of swapping containers.
local bmOwnFP = {}

local function BmVisualKey(kindName, indicator, px, font, spellId)
    -- BmTipsOff joins every interactive kind's key so the "Hide Buff
    -- Tooltips" toggle restyles (the fingerprint guards skip otherwise).
    if kindName == "icon" then
        return FP(
            font,
            px,
            (mod.db and mod.db.profile and mod.db.profile.bmIconZoom) or 0.08,
            indicator.iconOpacity,
            indicator.hideIcon,
            indicator.indBorderSize,
            CK(indicator.indBorderColor),
            mod.RFC_AuraBorderFP(indicator, "indBorder"),
            indicator.pandemicBorderEnabled,
            CK(indicator.pandemicBorderColor),
            indicator.pandemicBorderWidth,
            indicator.pandemicBorderTextured,
            indicator.showDuration,
            indicator.showDurationText,
            indicator.durationTextSize,
            CK(indicator.durationTextColor),
            indicator.durationTextOffsetX,
            indicator.durationTextOffsetY,
            indicator.thresholdEnabled,
            indicator.threshold,
            CK(indicator.thresholdColor),
            indicator.showStacks,
            indicator.stacksTextSize,
            CK(indicator.stacksTextColor),
            indicator.stacksOffsetX,
            indicator.stacksOffsetY,
            indicator.frameLevel,
            tostring(BuffTipMode()),
            indicator.displayGlowType,
            indicator.displayGlowClassColor,
            indicator.displayGlowR,
            indicator.displayGlowG,
            indicator.displayGlowB,
            indicator.displayGlowColorMode,
            indicator.displayGlowLines,
            indicator.displayGlowThickness,
            indicator.displayGlowSpeed,
            indicator.displayGlowBackground,
            indicator.displayGlowBackgroundR,
            indicator.displayGlowBackgroundG,
            indicator.displayGlowBackgroundB,
            mod.RF_GlowClassFP(indicator.displayGlowColorMode, indicator.displayGlowClassColor)
        )
    end
    if kindName == "square" then
        return FP(
            font,
            px,
            CK(BmSquareColor(indicator, spellId)),
            indicator.showDuration,
            indicator.indBorderSize,
            mod.RFC_AuraBorderFP(indicator, "indBorder"),
            CK(indicator.indBorderColor),
            indicator.frameLevel,
            indicator.showDurationText,
            indicator.durationTextSize,
            CK(indicator.durationTextColor),
            indicator.durationTextOffsetX,
            indicator.durationTextOffsetY,
            indicator.thresholdEnabled,
            indicator.threshold,
            CK(indicator.thresholdColor),
            indicator.showStacks,
            indicator.stacksTextSize,
            CK(indicator.stacksTextColor),
            indicator.stacksOffsetX,
            indicator.stacksOffsetY,
            tostring(BuffTipMode()),
            indicator.displayGlowType,
            indicator.displayGlowClassColor,
            indicator.displayGlowR,
            indicator.displayGlowG,
            indicator.displayGlowB,
            indicator.displayGlowColorMode,
            indicator.displayGlowLines,
            indicator.displayGlowThickness,
            indicator.displayGlowSpeed,
            indicator.displayGlowBackground,
            indicator.displayGlowBackgroundR,
            indicator.displayGlowBackgroundG,
            indicator.displayGlowBackgroundB,
            mod.RF_GlowClassFP(indicator.displayGlowColorMode, indicator.displayGlowClassColor)
        )
    end
    if kindName == "bar" then
        -- orientation is the one geometry field that is ALSO a visual: it swaps
        -- the bar's screen axis (BmGeoFP, anchor pass) and its fill axis
        -- (BmApplyBar). The other bar geometry stays out on purpose.
        return FP(
            CK(indicator.color),
            indicator.barColorOpacity,
            indicator.reverseFill,
            indicator.orientation,
            CK(indicator.barBgColor),
            indicator.barBgOpacity,
            indicator.frameLevel,
            tostring(BuffTipMode())
        )
    end
    return FP(
        indicator.type,
        CK(indicator.color),
        indicator.opacity,
        indicator.borderWidth,
        indicator.borderOpacity,
        indicator.borderStyle,
        indicator.borderDashCount,
        indicator.borderWidthPx
    )
end

local function BmOwnKey(metaRec)
    local tbl = {}
    for i = 1, #metaRec do
        tbl[i] = BmOwnSig(metaRec[i].ind)
    end
    return table.concat(tbl, ";")
end

-- Geometry fingerprint over every input AnchorBmSlots reads: slot-button SetSize/
-- SetPoint are engine-wrapped calls, so the anchor pass only reruns on actual changes.
local function BmGeoFP(metaRec, iconScale, cfg)
    -- powerUniformAnchors joins the geometry key: flipping it re-drives the
    -- slot anchor pass (AnchorBmSlots swaps its anchor host on it).
    local t = { tostring(iconScale), tostring(cfg and cfg.powerUniformAnchors or false) }
    for i = 1, #metaRec do
        local meta = metaRec[i]
        local indicator = meta.ind
        t[#t + 1] = FP(
            meta.key,
            meta.size,
            meta.count,
            indicator.spacing,
            indicator.growDirection,
            indicator.position,
            indicator.offsetX,
            indicator.offsetY,
            indicator.barWidth,
            indicator.barHeight,
            indicator.barFullWidth,
            indicator.barFullHeight,
            indicator.orientation,
            indicator.iconsPerRow,
            indicator.maxIcons
        )
    end
    return table.concat(t, ";")
end

-- Anchors icon/square chain slots, chain containers, and bar/effect slots.
local function AnchorBmSlots(d, healthBar, iconScale)
    local frameList = d.rfcBmFrames
    local metaRec = d.rfcBmMeta
    if not metaRec then return end
    healthBar = mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, ScaleProxy(d)) or healthBar -- Uniform Icon Anchoring
    -- Full Width/Height bar pins span the health bar itself; resolve back to
    -- the real bar when the swap above returned the full-height reference.
    local hugBar = healthBar and (healthBar._cuiHealth or healthBar)
    -- Slot-button geometry is denied while auras are secret (12.1 restriction). Chain
    -- CONTAINERS are our frames and always re-anchor; slot buttons skip and report it,
    -- so the caller leaves its geometry fingerprint unstamped for the restriction-lift
    -- sweep to re-enter (fresh builds are unaffected -- every slot self-anchors in its
    -- extraInit).
    local restricted = AK.AurasRestricted()
    local skipped = false
    for i = 1, #metaRec do
        local meta = metaRec[i]
        -- Anchored member metas share their root's container; the root's
        -- meta carries the member list and anchors once for the set.
        if meta.isChain and not meta.anchored then
            AnchorBmChainContainer(
                d.rfcBmChain and d.rfcBmChain[meta.chainKey],
                healthBar,
                meta.members
                    or { { ind = meta.ind, count = meta.count or (meta.ind.spells and #meta.ind.spells) } },
                iconScale
            )
        end
        local f = (not meta.isChain) and frameList and frameList[meta.key] or nil
        if f then
            if restricted then
                skipped = true
            else
                BmAnchorOneSlot(f, meta, healthBar, hugBar, iconScale)
            end
        end
    end
    return skipped
end

-- Chain container POOL: engine frames are never freed, so recreating a chain
-- container on every structural edit permanently leaked its 10-button batch (spec
-- swaps leaked one set per spec). Pool entries persist for the session, keyed by
-- kind + own-variant (own-only needs its own variant since filter strings are
-- declaration-fixed) + ordinal; a "swap" retargets live (candidates, count, layout,
-- anchor, style) with no creation, no leak. Unused entries park at count 0, hidden.
local bmPoolReloadPending = false
local function BmPoolReloadSoon()
    if bmPoolReloadPending then return end
    bmPoolReloadPending = true
    C_Timer.After(0.05, function()
        bmPoolReloadPending = false
        if mod.RFC_ReloadAll then mod.RFC_ReloadAll() end
    end)
end

-- Acquire (or lazily create) the pool entry for one chain SET -- a root chain plus
-- any Anchor To members riding its container as continuation groups -- and retarget
-- it live. Returns the container plus per-member styleKey list, or nil while the
-- shell is still pending on the OOC build queue (shells cannot be created in combat).
local function BmAcquireChain(btnFrame, d, healthBar, childFrame, iconScale, counters)
    local pool = d.rfcBmPool
    if not pool then
        pool = {}
        d.rfcBmPool = pool
    end
    local indicator = childFrame.ind
    local kindName = indicator.type or "icon"
    -- Member list: root first, then the attached chains (already sorted).
    local members = { childFrame }
    if childFrame.members then
        for jdx = 1, #childFrame.members do
            members[#members + 1] = childFrame.members[jdx]
        end
    end
    local ownPat = {}
    for jdx = 1, #members do
        ownPat[jdx] = BmEffOwnOnly(members[jdx].ind) and "o" or "a"
    end
    -- Custom Order: per-member segmentation (nil = single union group).
    local segsBy, anySegs = {}, false
    for jdx = 1, #members do
        local segs = BmSegments(members[jdx].ind, members[jdx].spells)
        if segs then
            segsBy[jdx] = segs
            anySegs = true
        end
    end
    local totalGroups = 0
    for jdx = 1, #members do
        totalGroups = totalGroups + (segsBy[jdx] and #segsBy[jdx] or 1)
    end
    local ck = kindName .. ":" .. table.concat(ownPat)
    local anyPandemic = false
    if kindName == "icon" then
        for jdx = 1, #members do
            anyPandemic = anyPandemic or BmPandemicOn(members[jdx].ind)
        end
        -- A shared engine pool can reuse buttons across members. Register all
        -- buttons in the opted-in container, but keep visibility per member.
        -- Only two variants are needed, regardless of the member enable pattern.
        if anyPandemic then ck = ck .. ":p:" end
    end
    if anySegs then
        -- Segment shape joins the pool key (group sets are add-only, so a
        -- differently-segmented chain needs its own container). The trailing
        -- colon keeps BmParkUnbound's trailing-digit split unambiguous.
        local sc = {}
        for jdx = 1, #members do
            sc[jdx] = tostring(segsBy[jdx] and #segsBy[jdx] or 1)
        end
        ck = ck .. ":" .. table.concat(sc, "-") .. ":"
    end
    local num = (counters[ck] or 0) + 1
    counters[ck] = num
    local poolKey = ck .. num
    local styleBase = StyleKeyOf(d):gsub("debuff", "bmpool") .. ":" .. poolKey

    -- Per-member styles (each group carries its own size/text styling).
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    local styleKeys = {}
    for jdx = 1, #members do
        local mInd = members[jdx].ind
        local sk = (jdx == 1) and styleBase or (styleBase .. ":" .. jdx)
        styleKeys[jdx] = sk
        local msize = mod.RFC_BmSize(mInd, iconScale)
        local vk = BmVisualKey(kindName, mInd, msize, font)
        if bmStyleFP[sk] ~= vk then
            bmStyleFP[sk] = vk
            AK.styles[sk] = BuildBmStyleFor(kindName, mInd, iconScale, msize)
            AK.styles[sk].bmPandemicRegister = anyPandemic
            AK.RestyleSoon(sk)
        end
    end

    local function ChainExtraInit()
        if kindName == "square" then
            return function(btn, dropdown, state) BmSquareInit(btn, dropdown, state, nil, nil) end
        end
        return function(btn, dropdown, state)
            dropdown.bmRegistered = true
            dropdown.bmCurve = state.durationColorCurve
        end
    end
    -- Group keys number SEQUENTIALLY across members' segments ("chain",
    -- "chain2", ...); a member without Custom Order contributes exactly one
    -- group, so the default shape is byte-identical to the pre-segment code.
    local function DeclareGroups(classColor)
        local g = 0
        for jdx = 1, #members do
            local filter
            if ownPat[jdx] == "o" then
                filter = { "HELPFUL", "PLAYER" }
            else
                filter = { "HELPFUL" }
            end
            for _ = 1, (segsBy[jdx] and #segsBy[jdx] or 1) do
                g = g + 1
                AK.AddGroupToContainer(classColor, {
                    key = (g == 1) and "chain" or ("chain" .. g),
                    filter = filter,
                    maxFrameCount = 0,
                    sortMethod = AuraContainerSortMethod and AuraContainerSortMethod.Default or nil,
                    style = styleKeys[jdx],
                    extraInit = ChainExtraInit(),
                    layout = { layoutIndex = g },
                })
            end
        end
    end

    local record = pool[poolKey]
    if record == nil then
        -- Bare early-window shells are variant-agnostic (no group yet):
        -- claim one and complete it right here -- group add + finish are
        -- combat-legal, so chains bind even mid-combat after a reload.
        local shell = d.rfcBmShellPool and table.remove(d.rfcBmShellPool)
        if shell then
            DeclareGroups(shell)
            AK.FinishContainer(shell, btnFrame:GetAttribute("unit") or NO_UNIT)
            record = { container = shell, groups = totalGroups }
            pool[poolKey] = record
        else
            pool[poolKey] = "pending"
            AKWorker:Queue(function()
                local classColor =
                    AK.CreateContainerShell(btnFrame, { point = { "CENTER", healthBar, "CENTER" } })
                DeclareGroups(classColor)
                AK.FinishContainer(classColor, btnFrame:GetAttribute("unit") or NO_UNIT)
                pool[poolKey] = { container = classColor, groups = totalGroups }
                BmPoolReloadSoon() -- rebind the buttons waiting on this shell
            end, "rf:bmpool-shell")
            return nil, styleKeys
        end
    elseif record == "pending" then
        return nil, styleKeys
    end

    local classColor = record.container
    record.parked = nil
    classColor:SetEnabled(true)
    classColor:SetUnit(btnFrame:GetAttribute("unit") or NO_UNIT)
    -- anchorMembers is per-GROUP (one entry per segment); memberIndex/segIndex
    -- let the anchor pass tell member boundaries from intra-member segments.
    local anchorMembers = {}
    local g = 0
    for jdx = 1, #members do
        local mInd, mSpells = members[jdx].ind, members[jdx].spells
        local segs = segsBy[jdx]
        for si = 1, (segs and #segs or 1) do
            g = g + 1
            local gk = (g == 1) and "chain" or ("chain" .. g)
            local seg = segs and segs[si]
            if seg and seg.spellID then
                classColor:SetAuraGroupCandidateFilters(gk, BuildBmCand(mInd, nil, seg.spellID))
            else
                classColor:SetAuraGroupCandidateFilters(
                    gk,
                    BuildBmCand(mInd, (seg and seg.spells) or mSpells)
                )
            end
            anchorMembers[g] = {
                ind = mInd,
                count = (seg and seg.count) or #mSpells,
                memberIndex = jdx,
                segIndex = si,
            }
        end
    end
    AnchorBmChainContainer(
        classColor,
        mod.RF_AnchorHost and mod.RF_AnchorHost(healthBar, ScaleProxy(d)) or healthBar,
        anchorMembers,
        iconScale
    )
    classColor:SetShown(d.rfcAssist ~= false)
    return classColor, styleKeys, anchorMembers
end

-- Parks every pool entry not re-bound by the current pass (count 0 +
-- hidden; the parked flag keeps repeat parks free).
local function ParkUnbound(d, counters)
    local pool = d.rfcBmPool
    if not pool then return end
    for pk, record in pairs(pool) do
        if type(record) == "table" then
            local prefixText, idx = pk:match("^(.-)(%d+)$")
            local bound = prefixText
                and idx
                and counters
                and counters[prefixText]
                and tonumber(idx) <= counters[prefixText]
            if not bound and not record.parked then
                record.parked = true
                for jdx = 1, (record.groups or 1) do
                    CludesUI.AuraKit.SetGroupCap(
                        record.container,
                        (jdx == 1) and "chain" or ("chain" .. jdx),
                        0
                    )
                end
                record.container:SetShown(false)
                -- Visibility is shared with presentation, so a park that rests on
                -- it alone is undone by any later SetShown. IsEnabled is the other
                -- half of the engine's registration test and nothing but us drives
                -- it. Dropping the binding too forces a real reparse on re-acquire:
                -- parking and re-acquiring on the SAME unit used to leave SetUnit a
                -- no-op and restore the caps over whatever was parsed before.
                record.container:SetEnabled(false)
                record.container:SetUnit(NO_UNIT)
            end
        end
    end
end

-- The dispel overlay's slots as AddSlotToContainer specs. They live in the button's
-- debuff container (built once, never swapped), so a member's auras are processed by
-- one container fewer. The assist gate switches them off through their candidate
-- filters (GateDispelSlots), the container itself staying shown for the debuffs. The
-- slots join only while the overlay draws something (DispelVisible): a slot pays its
-- filter check on every aura update even when it renders nothing. Switching the
-- overlay on adds them live (slot adds are combat-legal); switching it off leaves
-- them drawing nothing until the next reload (slots cannot be removed).
local function DispelSlotSpecs(btnFrame, healthBar, d, s)
    local dispelStyleKey = StyleKeyOf(d):gsub("debuff", "dispel")
    if not AK.styles[dispelStyleKey] then StoreDispelStyle(dispelStyleKey, s) end
    local specs = {}
    for i = 1, #DISPEL_SLOTS do
        local defaults = DISPEL_SLOTS[i]
        specs[i] = {
            key = defaults.key,
            filter = DispelSlotFilter(s, defaults.token),
            candidateFilters = { includeDispelTypes = { [defaults.token] = true } },
            style = dispelStyleKey,
            extraInit = function(slotButton, dropdown)
                dropdown.rfHealth = healthBar
                dropdown.rfSlotDef = defaults
                -- Color Custom Borders: the unit button (level base) and its
                -- border frame (geometry) for the per-type border copy.
                dropdown.rfUnitBtn = btnFrame
                dropdown.rfBorder = d.borderFrame
                -- Anchor inside the creation window: SetPoint on the returned
                -- slot button is denied while auras are secret (12.1 access
                -- restriction); shell setup runs on in-instance reloads.
                slotButton:SetPoint("CENTER", healthBar, "CENTER")
                ApplyRFDispelSlot(slotButton, dropdown, AK.styles[dispelStyleKey])
            end,
        }
    end
    return specs
end

local function CreateBmContainer(btnFrame, healthBar, d, unitToken)
    local inds, specKey, mode = BmIndicators(d)
    -- Party Frames kit: every buff icon joins one run right of the frame.
    if d.kit and inds and mod.RF_KitBmView then inds = mod.RF_KitBmView(inds) end
    local sig = BmSignature(inds, specKey, mode)

    if not inds then
        d.rfcBmSig = sig
        ParkUnbound(d, nil) -- custom-side chain pool parks
        return
    end

    local iconScale = BmScaleFor(d)
    local styleBase = StyleKeyOf(d):gsub("debuff", "bm")
    local slots, metaRec, chains = BuildBmSlots(inds, d, healthBar, iconScale, styleBase)

    if #slots > 0 then
        -- Early-window shell when available (slot adds + finish are
        -- combat-legal); fresh creation only as the OOC fallback.
        local boxHolder = d.rfcBmSlotsShell
        d.rfcBmSlotsShell = nil
        local frameList
        if boxHolder then
            frameList = {}
            for i = 1, #slots do
                frameList[slots[i].key] = AK.AddSlotToContainer(boxHolder, slots[i])
            end
            AK.FinishContainer(boxHolder, unitToken)
        else
            boxHolder, frameList = AK.CreateContainer(btnFrame, unitToken, {
                point = { "CENTER", healthBar, "CENTER" },
                slots = slots,
            })
        end
        d.rfcBm = boxHolder
        d.rfcBmFrames = frameList
    end

    -- Group-mode chains render through the persistent per-button POOL: acquired
    -- entries retarget live (no creation, no leak); a chain whose shell is still
    -- building binds on the deferred pool reload (sig stays nil so it re-enters here).
    local counters = {}
    local pendingChains = false
    local chainContainers = nil
    for ci = 1, #chains do
        local childFrame = chains[ci]
        local indicator = childFrame.ind
        local chainKey = tostring(indicator.id or ("x" .. childFrame.idx))
        local px = mod.RFC_BmSize(indicator, iconScale)
        local classColor, styleKeys, anchorMembers =
            BmAcquireChain(btnFrame, d, healthBar, childFrame, iconScale, counters)
        if classColor then
            chainContainers = chainContainers or {}
            chainContainers[chainKey] = classColor
            -- Root meta carries the member list (the geometry pass anchors
            -- the container once for the whole set); each Anchor To member
            -- gets its own meta entry for style/candidate re-drives.
            metaRec[#metaRec + 1] = {
                key = "chain_" .. chainKey,
                styleKey = styleKeys[1],
                ind = indicator,
                kind = indicator.type,
                isChain = true,
                chainKey = chainKey,
                groupKey = "chain",
                size = px,
                count = #childFrame.spells,
                spells = childFrame.spells,
                members = anchorMembers,
            }
            if childFrame.members then
                for jdx = 1, #childFrame.members do
                    local mch = childFrame.members[jdx]
                    metaRec[#metaRec + 1] = {
                        key = "chain_" .. chainKey .. "_m" .. jdx,
                        styleKey = styleKeys[jdx + 1],
                        ind = mch.ind,
                        kind = mch.ind.type,
                        isChain = true,
                        anchored = true,
                        chainKey = chainKey,
                        groupKey = "chain" .. (jdx + 1),
                        size = mod.RFC_BmSize(mch.ind, iconScale),
                        count = #mch.spells,
                        spells = mch.spells,
                    }
                end
            end
        else
            pendingChains = true
        end
    end
    d.rfcBmChain = chainContainers
    ParkUnbound(d, counters)

    d.rfcBmMeta = metaRec
    d.rfcBmSig = sig
    -- Chains whose pool shells are still building bind later through
    -- BmRebindPendingChains (chains-only; never re-churns the slots
    -- container), driven by the deferred pool reload.
    d.rfcBmChainsPending = pendingChains or nil
    AnchorBmSlots(d, healthBar, iconScale)
    d.rfcBmGeo = BmGeoFP(metaRec, iconScale, ScaleProxy(d))

    -- Prime the fingerprint caches with what was just built, so the next
    -- reload after a swap/login compares equal instead of storming.
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    for i = 1, #metaRec do
        local meta = metaRec[i]
        if meta.styleKey then
            bmStyleFP[meta.styleKey] = BmVisualKey(meta.kind, meta.ind, meta.size, font, meta.spellID)
            if meta.kind == "bgcolor" then
                bmStyleFP[meta.styleKey] = bmStyleFP[meta.styleKey] .. mod.RFC_BmTexBgKey(ScaleProxy(d))
            end
        end
    end
    bmOwnFP[StyleKeyOf(d)] = BmOwnKey(metaRec)
end

-- Chains-only rebind for pool shells that finished building after the
-- main pass. Rebuilds the chain view/meta tail; never touches the slots
-- container. Runs from ReloadBm when d.rfcBmChainsPending is set.
local function BmRebindPendingChains(btnFrame, d, classFile)
    if not d.rfcBmChainsPending then return end
    if not classFile.inds or not d.rfcHealth then return end
    local healthBar = d.rfcHealth
    local iconScale = classFile.iscale
    local counters = {}
    local metaRec = {}
    local old = d.rfcBmMeta or {}
    for i = 1, #old do
        if not old[i].isChain then metaRec[#metaRec + 1] = old[i] end
    end
    -- Chain collection + Anchor To composition are BuildBmSlots' job;
    -- re-running it here only re-derives spec tables (slot/style writes
    -- are idempotent -- no containers are touched by the call itself).
    local styleBase = StyleKeyOf(d):gsub("debuff", "bm")
    local _, _, chains = BuildBmSlots(classFile.inds, d, healthBar, iconScale, styleBase)
    local chainContainers = nil
    local pending = false
    for ci = 1, #chains do
        local childFrame = chains[ci]
        local indicator = childFrame.ind
        if #childFrame.spells > 0 then
            local chainKey = tostring(indicator.id or ("x" .. childFrame.idx))
            local px = mod.RFC_BmSize(indicator, iconScale)
            local classColor, styleKeys, anchorMembers =
                BmAcquireChain(btnFrame, d, healthBar, childFrame, iconScale, counters)
            if classColor then
                chainContainers = chainContainers or {}
                chainContainers[chainKey] = classColor
                metaRec[#metaRec + 1] = {
                    key = "chain_" .. chainKey,
                    styleKey = styleKeys[1],
                    ind = indicator,
                    kind = indicator.type,
                    isChain = true,
                    chainKey = chainKey,
                    groupKey = "chain",
                    size = px,
                    count = #childFrame.spells,
                    spells = childFrame.spells,
                    members = anchorMembers,
                }
                if childFrame.members then
                    for jdx = 1, #childFrame.members do
                        local mch = childFrame.members[jdx]
                        metaRec[#metaRec + 1] = {
                            key = "chain_" .. chainKey .. "_m" .. jdx,
                            styleKey = styleKeys[jdx + 1],
                            ind = mch.ind,
                            kind = mch.ind.type,
                            isChain = true,
                            anchored = true,
                            chainKey = chainKey,
                            groupKey = "chain" .. (jdx + 1),
                            size = mod.RFC_BmSize(mch.ind, iconScale),
                            count = #mch.spells,
                            spells = mch.spells,
                        }
                    end
                end
            else
                pending = true
            end
        end
    end
    d.rfcBmChain = chainContainers
    ParkUnbound(d, counters)
    d.rfcBmMeta = metaRec
    d.rfcBmChainsPending = pending or nil
    -- Newly-bound chains default to full alpha; re-drive the trust gate so
    -- the secret range alpha and SetShown state apply immediately instead
    -- of waiting for the next assist sweep.
    if chainContainers then
        d.rfcAssist = nil
        if mod.RFC_ApplyAssistGate then
            mod.RFC_ApplyAssistGate(btnFrame, d, btnFrame:GetAttribute("unit"))
        end
    end
end

local function BmRefreshSizes(metaRec, iconScale)
    for i = 1, #metaRec do
        local meta = metaRec[i]
        if meta.kind == "icon" or meta.kind == "square" then
            meta.size = mod.RFC_BmSize(meta.ind, iconScale)
        end
    end
end

-- Signature/visual/geometry fingerprints are identical for every button of a class,
-- so they compute ONCE per class per reload (a per-button pass rebuilt the same
-- strings 40x in raids). The cls table is cached by the caller for one RFC_ReloadAll pass.
local function BmClassPass(d)
    local classFile = {}
    classFile.inds, classFile.specKey, classFile.mode = BmIndicators(d)
    -- (Same frame-kind filter and kit view as CreateBmContainer, so the
    -- signatures agree.)
    if d.kit and classFile.inds and mod.RF_KitBmView then
        classFile.inds = mod.RF_KitBmView(classFile.inds)
    end
    classFile.sig = BmSignature(classFile.inds, classFile.specKey, classFile.mode)
    classFile.iscale = BmScaleFor(d)
    classFile.styleKey = StyleKeyOf(d)
    classFile.s = ScaleProxy(d)
    return classFile
end

-- Style checks run against the first container-carrying button's metas; AK.Restyle
-- reaches every registered button of the style either way. Own-only changes flag a live
-- candidate-filter re-drive (per button, below) rather than a container swap.
local function BmCheckStyles(classFile, metaRec)
    classFile.stylesChecked = true
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    for i = 1, #metaRec do
        local meta = metaRec[i]
        if meta.styleKey then
            local vk = BmVisualKey(meta.kind, meta.ind, meta.size, font, meta.spellID)
            if meta.kind == "bgcolor" then vk = vk .. mod.RFC_BmTexBgKey(classFile.s) end
            if bmStyleFP[meta.styleKey] ~= vk then
                bmStyleFP[meta.styleKey] = vk
                local previousStyle = AK.styles[meta.styleKey]
                AK.styles[meta.styleKey] =
                    BuildBmStyleFor(meta.kind, meta.ind, classFile.iscale, meta.size, meta.spellID)
                if meta.kind == "bgcolor" then mod.RFC_BmTexBg(AK.styles[meta.styleKey], classFile.s) end
                -- Pool registration applies to every member, including disabled ones.
                AK.styles[meta.styleKey].bmPandemicRegister = previousStyle
                    and previousStyle.bmPandemicRegister
                AK.RestyleSoon(meta.styleKey)
            end
        end
    end
    local ownKey = BmOwnKey(metaRec)
    if bmOwnFP[classFile.styleKey] ~= ownKey then
        bmOwnFP[classFile.styleKey] = ownKey
        classFile.ownDirty = true
    end
end

local function ReloadBm(btnFrame, d, s, classFile)
    if classFile.sig ~= d.rfcBmSig then
        if InCombatLockdown() then
            d.rfcBmPending = true
            return
        end
        -- Release the SLOTS container only (deregisters its buttons from the restyle
        -- registry). Chain POOL persists forever -- engine frames
        -- are never freed, so releasing them leaked batches on every structural edit;
        -- the rebuild retargets them live instead.
        if d.rfcBm then AK.ReleaseContainer(d.rfcBm) end
        d.rfcBm, d.rfcBmFrames, d.rfcBmMeta, d.rfcBmChain = nil, nil, nil, nil
        d.rfcBmSig = nil
        -- Those slot buttons own this bar's Health Bar Color overlays, and engine
        -- frames are never freed (see above), so their registry entries would pile
        -- up one set per rebuild and every later layout pass would walk the dead
        -- ones. The registry is pure cache: the next paint re-adds what is live.
        mod.RF_ClearBarTints(d.rfcHealth, "bm")
        -- Rebuild through the shared scheduler; the job reads live settings
        -- at run time, so rapid consecutive changes converge.
        AKWorker:Queue(function()
            -- Already rebuilt by a peer job: sig restored, OR the slots
            -- container exists (sig may legitimately still be nil while
            -- pool shells are pending -- rebuilding again would orphan it).
            if d.rfcBm or d.rfcBmSig ~= nil then return end
            if InCombatLockdown() then
                d.rfcBmPending = true
                return
            end
            local unitToken = btnFrame:GetAttribute("unit") or NO_UNIT
            CreateBmContainer(btnFrame, d.rfcHealth, d, unitToken)
            -- Fresh/retargeted containers may default shown at alpha 1;
            -- clear the readable state cache and re-drive the trust gate so
            -- SetShown and the secret range alpha re-apply immediately.
            d.rfcAssist = nil
            if mod.RFC_ApplyAssistGate then mod.RFC_ApplyAssistGate(btnFrame, d, unitToken) end
        end, "rf:bm-rebuild")
        return
    end

    BmRebindPendingChains(btnFrame, d, classFile)

    if (d.rfcBm or d.rfcBmChain) and classFile.inds then
        if not classFile.stylesChecked then
            BmRefreshSizes(d.rfcBmMeta, classFile.iscale)
            BmCheckStyles(classFile, d.rfcBmMeta)
            classFile.geo = BmGeoFP(d.rfcBmMeta, classFile.iscale, ScaleProxy(d))
        end
        if d.rfcBmGeo ~= classFile.geo then
            BmRefreshSizes(d.rfcBmMeta, classFile.iscale)
            local skippedSlots = AnchorBmSlots(d, d.rfcHealth, classFile.iscale)
            if skippedSlots then
                -- Slot geometry denied while auras are secret: fingerprint
                -- stays unstamped so the restriction-lift sweep re-runs it.
                mod._rfcLiftDirty = true
            else
                d.rfcBmGeo = classFile.geo
            end
        end
        if classFile.ownDirty then
            for i = 1, #d.rfcBmMeta do
                local m = d.rfcBmMeta[i]
                -- Chain groups carry own-only in their declaration-fixed
                -- group filter string; changing it re-keys BmSignature and
                -- swaps, so only true slots re-drive live here.
                if not m.isChain and d.rfcBm then
                    d.rfcBm:SetAuraSlotFilterString(m.key, AK.Filter(unpack(BuildBmFilter(m.ind))))
                end
            end
        end
    end
end

-- TWO-PHASE construction (a solo login otherwise built the FULL group set for 86
-- buttons, 85 empty, at ~7ms/declaration = ~5.5s; shells cost ~0.26ms each). PHASE A
-- (every styled button):
-- container SHELLS + dispel slots -- the one thing combat cannot create, so mid-combat
-- joiners always find them ready (~2.5ms/button). PHASE B (buttons that HOLD a unit,
-- triggered by assignment): group declarations, BM, finish/config -- rides the
-- combat-legal live lane since shells exist from phase A, so a mid-fight joiner gets
-- debuffs/defensives immediately (BM needs container creation, completes at regen).
-- Shells build SYNCHRONOUSLY from StyleButton: combat has not re-engaged yet even on
-- an in-combat /reload (lockdown reads false), so creation is safe there; expensive
-- group/BM work stays on the worker queue.
local function CreateButtonShells(btnFrame, healthBar, d)
    -- Debuffs: adopt the header-born container when present (secure-side
    -- birth; also covers buttons the header grows mid-combat), else build.
    if not (d.rfcDebuffShell or d.rfcDebuffs) then
        local c = btnFrame.AuraContainer
        if not c then c = AK.CreateContainerShell(btnFrame, { point = { "CENTER", healthBar, "CENTER" } }) end
        -- Legacy aura icons live at button + LVL_AURA (13), above the
        -- health-bar decorations (dispel overlay, shields) and text; the
        -- containers default far lower. Children keep relative levels.
        c:SetFrameLevel(btnFrame:GetFrameLevel() + (mod.LVL_AURA or 13))
        d.rfcDebuffShell = c
        d.rfcDebuffGroups = {}
    end

    -- Dispellable-location container: strictly opt-in -- shell only exists while the
    -- split is enabled somewhere (DispLocAnyActive, since class flags may not be
    -- stamped yet); zero cost otherwise. Enabling mid-session builds via the OOC lane.
    if not (d.rfcDispLocShell or d.rfcDispLoc) and DispLocAnyActive() then
        local c = AK.CreateContainerShell(btnFrame, { point = { "CENTER", healthBar, "CENTER" } })
        c:SetFrameLevel(btnFrame:GetFrameLevel() + (mod.LVL_AURA or 13))
        d.rfcDispLocShell = c
        d.rfcDispLocGroups = {}
    end

    -- Dispel overlay slots, into the debuff shell (DispelSlotSpecs) while the overlay
    -- draws something. NO unit yet: an unbound shell registers no events and parses
    -- nothing; the debuff finish job binds the real unit.
    if d.rfcDebuffShell and not d.rfcDispelInDebuff then
        local s = ScaleProxy(d)
        if s and DispelVisible(s, d) then
            local specs = DispelSlotSpecs(btnFrame, healthBar, d, s)
            for i = 1, #specs do
                AK.AddSlotToContainer(d.rfcDebuffShell, specs[i])
            end
            d.rfcDispelInDebuff = true
            d.rfcTotemGen = rfcTotemGen
            -- The filters baked above, checked at finalize: a setting changed while
            -- this shell waited (raid shells wait for a raid) must not latch.
            d.rfcDispelFilterFP = DispelFilterFP(s)
        end
    end

    -- BuffManager shells, same early-window rule: slots container and a bare pool shell per current-spec chain indicator. With frames
    -- pre-born, ALL remaining BM work (slot adds, declarations, finishes, retargets)
    -- is combat-legal -- BM binds mid-combat after an in-combat /reload, not regen.
    if not d.rfcBmSlotsShell and not d.rfcBm then
        d.rfcBmSlotsShell = AK.CreateContainerShell(btnFrame, { point = { "CENTER", healthBar, "CENTER" } })
    end
    if not d.rfcBmShellPool then
        d.rfcBmShellPool = {}
        local inds = BmIndicators()
        if inds then
            for i = 1, #inds do
                local indicator = inds[i]
                if
                    indicator.enabled
                    and (indicator.type == "icon" or indicator.type == "square")
                    and BmChainMode(indicator) == "g"
                then
                    d.rfcBmShellPool[#d.rfcBmShellPool + 1] =
                        AK.CreateContainerShell(btnFrame, { point = { "CENTER", healthBar, "CENTER" } })
                end
            end
        end
    end
end

-- Debuff phase: group declarations + finish (combat-runnable -- shells exist
-- synchronously from StyleButton, and group declaration on an existing container is
-- combat-legal).
--
-- CLASS AT JOB TIME, NOT QUEUE TIME: the party SELF button carries its unit attribute
-- before StyleButton runs, but party creation stamps d._isParty only after StyleButton
-- returns -- so this phase queues while the button still reads as raid class. Jobs run
-- at least a frame later, so each resolves StyleKeyFor/ProxyFor itself; capturing them
-- at queue time gave the party self frame raid-classed containers.
local function QueueDebuffPhase(btnFrame, healthBar, d)
    if not ScaleProxy(d) then return end
    for i = 1, #DEBUFF_GROUPS do
        local group = DEBUFF_GROUPS[i]
        AKWorker:Queue(function()
            local c = d.rfcDebuffShell
            if not c or d.rfcDebuffGroups[group.key] then return end
            local nowSec = ScaleProxy(d)
            if not nowSec then return end
            -- 12.1 redesign: Debuff Manager owns the debuff row; only the cc group
            -- (its Crowd Control record + glow carrier) is still declared here --
            -- retired preset groups would be permanent parse consumers even parked at 0.
            if group.key ~= "cc" then return end
            if group.lazy then
                local need = DEBUFF_PRESET_GROUPS[nowSec.debuffFilter or "all"]
                local wanted = false
                if need then
                    for k = 1, #need do
                        if need[k] == group.key then wanted = true end
                    end
                end
                if not wanted then return end
            end
            local lookKey = StyleKeyOf(d)
            local ccStyleKey = lookKey:gsub("debuff", "debuffcc")
            -- Prime here too: setup-time priming used the queue-time class,
            -- so a job-resolved class may not have style tables yet.
            if not AK.styles[lookKey] then StoreDebuffStyles(lookKey, nowSec) end
            AK.AddGroupToContainer(c, {
                key = group.key,
                filter = group.filter,
                maxFrameCount = 0,
                style = (group.key == "cc") and ccStyleKey or lookKey,
            })
            d.rfcDebuffGroups[group.key] = true
        end, "rf:debuff-group")
    end
    AKWorker:Queue(function()
        local c = d.rfcDebuffShell
        if not c then return end
        d.rfcDebuffShell = nil
        local unitToken = btnFrame:GetAttribute("unit") or NO_UNIT
        AK.FinishContainer(c, unitToken)
        d.rfcHealth = healthBar
        d.rfcDebuffs = c
        -- The dispel overlay's slots ride this container (DispelSlotSpecs).
        if d.rfcDispelInDebuff then d.rfcDispel = c end
        d.rfcUnit = unitToken
        local nowSec = ScaleProxy(d)
        if nowSec then
            AnchorDebuffContainer(c, healthBar, nowSec)
            ApplyDebuffConfig(c, d, nowSec)
        end
    end, "rf:debuff-finish")
end

-- Dispellable-location phase: mirrors QueueDebuffPhase for the split
-- container. Only queued when its shell exists (the split is opt-in);
-- every group is on-demand via DispLocGroupWanted. Class resolves at JOB
-- time for the same party-self-button reason as QueueDebuffPhase.
local function QueueDispLocPhase(btnFrame, healthBar, d)
    if not ScaleProxy(d) then return end
    for i = 1, #DEBUFF_GROUPS do
        local group = DEBUFF_GROUPS[i]
        AKWorker:Queue(function()
            local c = d.rfcDispLocShell
            if not c or d.rfcDispLocGroups[group.key] then return end
            local nowSec = ScaleProxy(d)
            if not nowSec or not DispelIconsOn(nowSec) or not DispLocGroupWanted(nowSec, group.key) then
                return
            end
            local lookKey = StyleKeyOf(d)
            local dlStyleKey = lookKey:gsub("debuff", "disploc")
            local dlCCStyleKey = lookKey:gsub("debuff", "disploccc")
            AK.styles[dlStyleKey] = AK.styles[dlStyleKey] or BuildDebuffStyle(nowSec, DispelIconSize(nowSec))
            AK.styles[dlCCStyleKey] = AK.styles[dlCCStyleKey]
                or BuildDebuffCCStyle(nowSec, DispelIconSize(nowSec))
            AK.AddGroupToContainer(c, {
                key = group.key,
                filter = group.filter,
                maxFrameCount = 0,
                style = (group.key == "cc") and dlCCStyleKey or dlStyleKey,
            })
            d.rfcDispLocGroups[group.key] = true
        end, "rf:disploc-group")
    end
    AKWorker:Queue(function()
        local c = d.rfcDispLocShell
        if not c then return end
        d.rfcDispLocShell = nil
        local unitToken = btnFrame:GetAttribute("unit") or NO_UNIT
        AK.FinishContainer(c, unitToken)
        d.rfcDispLoc = c
        local nowSec = ScaleProxy(d)
        if nowSec then
            AnchorDispLocContainer(c, healthBar, nowSec)
            ApplyDispLocConfig(c, d, nowSec)
            c:SetShown(DispelIconsOn(nowSec))
        end
    end, "rf:disploc-finish")
end

local function QueueButtonGroups(btnFrame, healthBar, d)
    local s = ScaleProxy(d)
    if not s then
        d.rfcGroupsPending = nil
        return
    end

    -- No style keys captured here: every job resolves its class at run
    -- time (see the QueueDebuffPhase note on the party self button).

    QueueDebuffPhase(btnFrame, healthBar, d)
    if d.rfcDispLocShell then QueueDispLocPhase(btnFrame, healthBar, d) end

    -- BuffManager + finalize: consumes the early-window shells (the shared slots shell
    -- with the dispel overlay's slots, chain shells; slot adds, group declarations,
    -- finishes -- all combat-legal), so it runs mid-combat too. Only pool GROWTH beyond
    -- the pre-born shells falls back to a queued shell job in BmAcquireChain.
    AKWorker:Queue(function()
        d.rfcPending = nil
        d.rfcGroupsPending = nil
        local unitToken = btnFrame:GetAttribute("unit") or NO_UNIT
        CreateBmContainer(btnFrame, healthBar, d, unitToken)
        d.rfcUnit = unitToken
        -- Shells baked the dispel filters (settings + rfcTotemKnown) at build time; if
        -- a totem flip or a settings change landed since, re-apply the current filters
        -- before the fingerprint below is primed as current (which would otherwise
        -- latch the stale filters as already-applied).
        if d.rfcDispel then
            local nowSec = ScaleProxy(d) or s
            if d.rfcTotemGen ~= rfcTotemGen or d.rfcDispelFilterFP ~= DispelFilterFP(nowSec) then
                local parts = DispelSlotFilters(nowSec)
                for i = 1, #DISPEL_SLOTS do
                    d.rfcDispel:SetAuraSlotFilterString(DISPEL_SLOTS[i].key, parts[i])
                end
            end
        end
        d.rfcTotemGen = nil
        d.rfcDispelFilterFP = nil
        -- Everything above was configured from current settings; prime the class
        -- fingerprints so the first reload doesn't re-drive it all (class resolved
        -- here, not at queue time -- party self button).
        PrimeClassFP(StyleKeyOf(d), ScaleProxy(d) or s)
        -- Clear state cached while this button was mid-build (unit assignments run
        -- the gate against partial containers): fresh containers need a full
        -- SetShown/range-alpha pass.
        d.rfcAssist = nil
        -- (ns indirection: the gate is defined below this function.)
        mod.RFC_ApplyAssistGate(btnFrame, d, unitToken)
        registry[#registry + 1] = btnFrame
    end, "rf:bm+finalize")
end
mod.RFC_QueueButtonGroups = QueueButtonGroups -- for the unit-assignment watch

-- Called from StyleButton's tail for every decorated unit button (raid,
-- party, self, extra). Phase A (shells) for everyone; phase B only when
-- the button already holds a unit -- the assignment watch triggers it for
-- later arrivals, so empty raid/party/extra buttons cost shells only.
function mod.RFC_SetupButton(btnFrame, healthBar, d)
    AK = AK or CludesUI.AuraKit
    if not AK or not AK.QueueBuildJob or d.rfcDebuffs or d.rfcPending then return end
    d.rfcPending = true

    local s = ScaleProxy(d)
    if s then
        local lookKey = StyleKeyOf(d)
        if not AK.styles[lookKey] then StoreDebuffStyles(lookKey, s) end
        local dispelStyleKey = lookKey:gsub("debuff", "dispel")
        if not AK.styles[dispelStyleKey] then StoreDispelStyle(dispelStyleKey, s) end
    end

    d.rfcHealthRef = healthBar

    -- Shells synchronously, HERE, in the early load window (see CreateButtonShells):
    -- the one moment container creation is safe on every reload path, combat included.
    CreateButtonShells(btnFrame, healthBar, d)

    local unitToken = btnFrame:GetAttribute("unit")
    if unitToken and UnitExists(unitToken) then
        d.rfcGroupsPending = true
        QueueButtonGroups(btnFrame, healthBar, d)
    end
end

-- Trust gate for helpful spell-ID-filtered containers. The engine SILENTLY SKIPS
-- spell-ID candidate filters for helpful auras on units that fail its identity
-- gate, so an include-list display would degrade to "any buff" there; the gate
-- hides such displays instead (token-only groups -- debuffs, CC -- are unaffected).
-- Degradation is NOT directly queryable, so the non-group probe below approximates
-- it: connected, alive, visible, not phased, assistable. RANGE is deliberately NOT
-- a disqualifier: aura data streams fine for members merely out of 40yd spell
-- range (the unit frame's own oorAlpha fade already dims the containers).
-- Identity APIs can return SECRET booleans under teardown; any secret errors
-- inside the pcall and reads fail-closed.
--
-- GROUP TOKENS NEVER GATE (12.1.0 build 69497+): CanApplyIdentityCandidateFilters
-- short-circuits on `isHelpful and UnitIsPlayerControlledOrGroupMember`, a
-- token-SHAPE test that is unconditionally true for player/partyN/raidN, so a
-- helpful spell-ID filter can no longer degrade on a group frame -- vehicle and
-- cinematic included. Every term below was a heuristic for that degradation, and
-- the liveness terms (connected/alive/visible/unphased) had no dedicated recovery
-- edge of their own: a sweep landing while a member was dead, out of render
-- range, or phased hid that member's buff containers, and only an UNRELATED
-- event (range crossing, roster, flags) could ever re-show them -- field-reported
-- three times as "a buff missing on one player's frame". Staleness while a unit
-- is ghosted is Blizzard parity and is owned by the ghost ticker's regain
-- reparse, so the probe answers true for every group token and the gate can
-- never hide a raid/party/extra display. Friendly Boss slots host bossN, outside
-- the exemption, and clients without the call keep the full probe.
local function AssistProbe(unitToken)
    if UnitIsPlayerControlledOrGroupMember and UnitIsPlayerControlledOrGroupMember(unitToken) then
        return true
    end
    if UnitIsUnit(unitToken, "player") then
        -- UsingVehicle over InVehicle: it is also true during the boarding and
        -- exiting TRANSITIONS, and the filters already degrade while boarding
        -- (field: a second of "any buff" before the seated state landed).
        local probe = UnitUsingVehicle or UnitInVehicle
        if probe("player") then return false end
        -- Cinematics fire UNIT_FACTION for every unit and briefly make even
        -- the LOCAL PLAYER non-assistable (authors-channel consensus
        -- 2026-08-13) -- the engine drops spell-ID filters for self exactly
        -- like the vehicle case. A CLEANLY-false self-assist hides the
        -- filtered displays for the transition; unreadable answers stay
        -- fail-open (the historical self-exemption).
        local okSelf, canSelf = pcall(UnitCanAssist, "player", "player")
        if okSelf and not (issecretvalue and issecretvalue(canSelf)) and canSelf == false then
            return false
        end
        return true
    end
    -- Non-group tokens only from here (bossN slots, pre-69497 clients): the
    -- engine's identity gate can still degrade a helpful spell-ID filter to
    -- "any buff" on these, so hide while the unit is not live or assistable.
    if
        not (
            UnitIsConnected(unitToken)
            and not UnitIsDeadOrGhost(unitToken)
            and UnitIsVisible(unitToken)
            and not UnitPhaseReason(unitToken)
        )
    then
        return false
    end
    -- Evaluated in here so a secret answer errors inside the caller's pcall.
    if not UnitCanAssist("player", unitToken) then return false end
    return true
end

-- NOTE: the range alpha-slaving lane (containers hard-hidden at alpha 0 for
-- out-of-range units via SetAlphaFromBoolean on the range boolean) was REMOVED
-- 2026-08-12: it made buffs and health-color effects vanish for members merely
-- out of 40yd spell range, while aura data still streams for them. The
-- containers are children of the unit button and inherit its oorAlpha range
-- fade, which is the wanted presentation. Do not re-add a range hide here
-- without fresh evidence of out-of-range filter degradation on the live client.

-- The dispel overlay's slots follow the assist gate like the Buff Manager's
-- containers: while the gate hides (only Friendly Boss slots on current clients),
-- an empty dispel-type list makes every slot match nothing. Written only when the
-- gate engages or ends (d.rfcDispelGated tracks it); each write marks the container
-- for one rebuild on its next pass. The engine copies the candidate tables.
local NO_DISPEL_TYPES = { includeDispelTypes = {} }
local function GateDispelSlots(d, hide)
    local c = d.rfcDispel or (d.rfcDispelInDebuff and d.rfcDebuffShell)
    if not (c and c.SetAuraSlotCandidateFilters) or (d.rfcDispelGated or false) == hide then return end
    d.rfcDispelGated = hide or nil
    for i = 1, #DISPEL_SLOTS do
        local defaults = DISPEL_SLOTS[i]
        c:SetAuraSlotCandidateFilters(
            defaults.key,
            hide and NO_DISPEL_TYPES or { includeDispelTypes = { [defaults.token] = true } }
        )
    end
end

local function ApplyAssistGate(btnFrame, d, unitToken)
    -- Group tokens always trust (see AssistProbe): on raid/party/extra buttons
    -- this only ever flips true and re-shows fresh containers. The hide branch
    -- is live for Friendly Boss slots (bossN) and pre-69497 clients only.
    local assist = false
    if unitToken then
        local success, res = pcall(AssistProbe, unitToken)
        if success and res then assist = true end
    end
    -- Same state as last applied: every write below is assist-driven, so re-applying
    -- is redundant (settings changes re-drive via reload paths); keeps event-sweep
    -- watchers near-free.
    if d.rfcAssist == assist then return end
    -- Explicit-false only: the login initialization is nil->true and must NOT
    -- take the regain refresh below (a full-group UpdateAllAuras storm on the
    -- login hot path -- the normal build owns first content).
    local wasDenied = d.rfcAssist == false
    d.rfcAssist = assist
    GateDispelSlots(d, not assist)
    if d.rfcBm then d.rfcBm:SetShown(assist) end
    if d.rfcBmChain then
        for _, classColor in pairs(d.rfcBmChain) do
            classColor:SetShown(assist)
        end
    end
    -- The Debuff Manager takes no part: candidate booleans are never
    -- identity-gated, so its records and tiles render on every unit.
    -- Regain refresh: content parsed during the degraded window is WRONG
    -- ("any buff"), and no aura edge is guaranteed to follow the transition
    -- back (cinematic end, vehicle exit) -- the display would show stale
    -- degraded content until the unit's next real aura change. Force one
    -- reparse of the filtered containers on the explicit false->true flip
    -- (wasDenied: never the login nil->true initialization). Bounded: runs
    -- only on actual transitions, so a cinematic end costs one pass across
    -- the group and a vehicle exit one button.
    if assist and wasDenied then
        if d.rfcBm then d.rfcBm:UpdateAllAuras() end
        if d.rfcBmChain then
            for _, classColor in pairs(d.rfcBmChain) do
                classColor:UpdateAllAuras()
            end
        end
    end
end
mod.RFC_ApplyAssistGate = ApplyAssistGate

-- Per-container binding audit. Every build job reads the button's live unit
-- attribute at its OWN run time and stamps d.rfcUnit, so a reassignment landing
-- between two jobs leaves the containers that finished earlier bound to the
-- previous occupant while d.rfcUnit already reads current -- the d.rfcUnit
-- comparison every reassignment path uses can never see that. A container left
-- on a token that no longer fires UNIT_AURA freezes on whatever it last parsed;
-- SetUnit re-registers and reparses.
local function RebindContainer(c, unitToken)
    if c and c:GetUnit() ~= unitToken then c:SetUnit(unitToken) end
end

local function RepointStale(d, unitToken)
    RebindContainer(d.rfcDebuffs, unitToken)
    RebindContainer(d.rfcDispLoc, unitToken)
    RebindContainer(d.rfcDispel, unitToken)
    RebindContainer(d.rfcBm, unitToken)
    -- Every chain container comes from the pool; a parked one sits on NO_UNIT
    -- deliberately, so leave it there.
    if d.rfcBmPool then
        for _, record in pairs(d.rfcBmPool) do
            if type(record) == "table" and not record.parked then
                RebindContainer(record.container, unitToken)
            end
        end
    end
    -- Debuff Manager tiles keep their own per-container stamp beside the binding;
    -- rebinding them here behind its back would desync the two, so let it re-point.
    -- A parked tile sits on NO_UNIT deliberately (its own apply re-points it).
    if d.dmTiles and mod.DM_OnUnitAssigned then
        for _, c in pairs(d.dmTiles) do
            if not c._dmParked and c:GetUnit() ~= unitToken then
                mod.DM_OnUnitAssigned(d, unitToken)
                break
            end
        end
    end
end
mod.RFC_RepointStale = RepointStale

-- Called from the OnAttributeChanged("unit") watch when the secure header
-- (re)assigns a button. SetUnit re-registers events; the explicit refresh
-- covers assignments where the new unit's auras produce no UNIT_AURA edge.
function mod.RFC_OnUnitAssigned(btnFrame, d, unitToken)
    -- WoW Forever: Missing Buffs follows the button's member (own same-unit early-out).
    if mod.RF_FvMissingUnit then mod.RF_FvMissingUnit(btnFrame, d, unitToken) end
    -- Two-phase: a button receiving its FIRST unit triggers phase B (group
    -- declarations + BM + finish) -- empty buttons only ever carry phase-A shells.
    -- Mid-combat first assignments (raid joiners) work: group jobs ride the live lane
    -- against the pre-built shells.
    if not d.rfcDebuffs and not d.rfcGroupsPending then
        if d.rfcHealthRef then
            d.rfcGroupsPending = true
            QueueButtonGroups(btnFrame, d.rfcHealthRef, d)
        end
        return
    end
    -- The secure header re-sets the SAME unit attribute on every roster re-process.
    -- Containers keep their unit across that and UNIT_AURA drives their content, so a
    -- same-unit re-assignment has nothing to re-drive -- skipping it avoids a raid-wide
    -- UpdateAllAuras storm (full engine reparse of every group/slot on every button).
    -- Assist state can still flip without a unit change; its same-state early-out
    -- keeps that call near-free.
    if d.rfcUnit == unitToken then
        -- No binding audit here: this branch is the roster-reprocess storm path
        -- (every button, every roster/name event, several times at pull start)
        -- and the audit is a per-container read. The 1s sweep owns it instead,
        -- which bounds a stale binding to one second either way.
        ApplyAssistGate(btnFrame, d, unitToken)
        return
    end
    d.rfcUnit = unitToken
    if d.rfcDebuffs then
        d.rfcDebuffs:SetUnit(unitToken)
        d.rfcDebuffs:UpdateAllAuras()
    end
    if d.rfcDispLoc then
        d.rfcDispLoc:SetUnit(unitToken)
        d.rfcDispLoc:UpdateAllAuras()
    end
    -- (The dispel overlay's slots ride d.rfcDebuffs, re-pointed above.)
    if d.rfcBm then
        d.rfcBm:SetUnit(unitToken)
        d.rfcBm:UpdateAllAuras()
    end
    if d.rfcBmChain then
        for _, classColor in pairs(d.rfcBmChain) do
            classColor:SetUnit(unitToken)
            classColor:UpdateAllAuras()
        end
    end
    -- Debuff Manager tile containers re-point with everything else.
    if mod.DM_OnUnitAssigned then mod.DM_OnUnitAssigned(d, unitToken) end
    ApplyAssistGate(btnFrame, d, unitToken)
end

-- Compares fingerprints for one class, restyles what changed (once per
-- class -- styles are shared), and returns which per-button config blocks
-- need re-driving. Empty flags = the reload touches nothing container-side.
local function ComputeClassFlags(lookKey, s)
    local state = classFP[lookKey]
    if not state then
        state = {}
        classFP[lookKey] = state
    end
    local font = (CludesUI.GetFontPath("raidFrames")) or ""
    local flags = {}

    local val = DebuffStyleFP(s, font)
    if state.debuffStyle ~= val then
        state.debuffStyle = val
        local ccStyleKey = StoreDebuffStyles(lookKey, s, val)
        AK.RestyleSoon(lookKey)
        AK.RestyleSoon(ccStyleKey)
        -- DM per-filter sized styles derive from these; a pure style edit
        -- does not flip the config fingerprint, so refresh them here.
        if mod.DM_RefreshSizedStyles then mod.DM_RefreshSizedStyles(lookKey, s) end
    end
    val = DebuffCfgFP(s)
    if state.debuffCfg ~= val then
        state.debuffCfg = val
        flags.debuffCfg = true
    end

    val = DispLocStyleFP(s, font)
    if state.dispLocStyle ~= val then
        state.dispLocStyle = val
        local dlStyleKey = lookKey:gsub("debuff", "disploc")
        -- Only rebuild once the split has ever materialized styles for this
        -- class -- keeps the feature literally zero-cost while unused.
        if DispelIconsOn(s) or AK.styles[dlStyleKey] then
            AK.styles[dlStyleKey] = BuildDebuffStyle(s, DispelIconSize(s))
            AK.RestyleSoon(dlStyleKey)
            local dlCCStyleKey = lookKey:gsub("debuff", "disploccc")
            AK.styles[dlCCStyleKey] = BuildDebuffCCStyle(s, DispelIconSize(s))
            AK.RestyleSoon(dlCCStyleKey)
        end
    end
    val = DispLocCfgFP(s)
    if state.dispLocCfg ~= val then
        state.dispLocCfg = val
        flags.dispLocCfg = true
    end

    val = DispelStyleFP(s, lookKey)
    if state.dispelStyle ~= val then
        state.dispelStyle = val
        local dispelStyleKey = lookKey:gsub("debuff", "dispel")
        StoreDispelStyle(dispelStyleKey, s, val)
        AK.RestyleSoon(dispelStyleKey)
    end
    local parts = DispelSlotFilters(s)
    local dispelFilter = table.concat(parts, ";")
    if state.dispelFilter ~= dispelFilter then
        state.dispelFilter = dispelFilter
        flags.dispelFilter = parts
    end

    return flags
end

-- Called from the tail of ReloadFrames (party mirror path feeds the same registry).
-- Fingerprint-guarded, so unrelated raid settings cost near-zero. Restriction-lift
-- reconciliation: passes that skipped under aura secrecy left fingerprints unstamped,
-- so one FP-guarded ReloadAll at lift re-drives exactly that work (dirty-flag guarded,
-- so idle lift events cost one test). AK is resolved directly here, not via the
-- lazily-assigned file-scope local (still nil at load time) -- the parent addon is a
-- hard dependency and exists by child load.
do
    local AKL = CludesUI and CludesUI.AuraKit
    if AKL and AKL.OnRestrictionLift then
        AKL.OnRestrictionLift(function()
            if mod._rfcLiftDirty then
                mod._rfcLiftDirty = nil
                if mod.RFC_ReloadAll then mod.RFC_ReloadAll() end
            end
        end)
    end
end

function mod.RFC_ReloadAll()
    AK = AK or CludesUI.AuraKit
    if not AK then return end
    mod.RFC_ResetSnap()

    local dirty, clsCache = {}, {}

    for i = 1, #registry do
        local btnFrame = registry[i]
        local d = mod.GetFFD and mod.GetFFD(btnFrame)
        local boxHolder = d and d.rfcDebuffs
        if boxHolder then
            local s = ScaleProxy(d)
            if s then
                local lookKey = StyleKeyOf(d)
                local flags = dirty[lookKey]
                if not flags then
                    flags = ComputeClassFlags(lookKey, s)
                    dirty[lookKey] = flags
                end
                if flags.debuffCfg then
                    AnchorDebuffContainer(boxHolder, d.rfcHealth, s)
                    ApplyDebuffConfig(boxHolder, d, s)
                end
                -- "Shown on Modifier" motion eaters (frames we own; the DM
                -- file builds/flips them -- see its tooltip-modifier section).
                if mod.DM_TipModEnsure then mod.DM_TipModEnsure(btnFrame, d, s) end
                if flags.dispLocCfg then
                    local c2 = d.rfcDispLoc
                    if c2 then
                        AnchorDispLocContainer(c2, d.rfcHealth, s)
                        ApplyDispLocConfig(c2, d, s)
                        c2:SetShown(DispelIconsOn(s))
                    elseif DispelIconsOn(s) and not d.rfcDispLocShell and not d.rfcDispLocBuild then
                        -- Split enabled mid-session: containers can't be created in
                        -- combat, so the shell build rides the OOC lane; groups+finish
                        -- follow the normal phase.
                        d.rfcDispLocBuild = true
                        AKWorker:Queue(function()
                            d.rfcDispLocBuild = nil
                            if d.rfcDispLoc or d.rfcDispLocShell then return end
                            local s2 = ScaleProxy(d)
                            if not s2 or not DispelIconsOn(s2) then return end
                            local healthBar = d.rfcHealth or d.rfcHealthRef
                            if not healthBar then return end
                            local c = AK.CreateContainerShell(
                                btnFrame,
                                { point = { "CENTER", healthBar, "CENTER" } }
                            )
                            c:SetFrameLevel(btnFrame:GetFrameLevel() + (mod.LVL_AURA or 13))
                            d.rfcDispLocShell = c
                            d.rfcDispLocGroups = {}
                            QueueDispLocPhase(btnFrame, healthBar, d)
                        end, "rf:disploc-shell") -- creation combat-legal since 68914
                    end
                end
                -- The dispel overlay's slots ride the debuff container (DispelSlotSpecs):
                -- switched on, they join it live with the current filters; switched
                -- off, they stay and draw nothing until the next reload.
                if not d.rfcDispelInDebuff and DispelVisible(s, d) and d.rfcHealth then
                    local specs = DispelSlotSpecs(btnFrame, d.rfcHealth, d, s)
                    for jdx = 1, #specs do
                        AK.AddSlotToContainer(boxHolder, specs[jdx])
                    end
                    d.rfcDispelInDebuff = true
                    d.rfcDispel = boxHolder
                    -- Joining while the assist gate hides: they start hidden too.
                    if d.rfcAssist == false then GateDispelSlots(d, true) end
                elseif d.rfcDispel and flags.dispelFilter then
                    for jdx = 1, #DISPEL_SLOTS do
                        d.rfcDispel:SetAuraSlotFilterString(DISPEL_SLOTS[jdx].key, flags.dispelFilter[jdx])
                    end
                end
                local classFile = clsCache[lookKey]
                if not classFile then
                    classFile = BmClassPass(d)
                    clsCache[lookKey] = classFile
                end
                ReloadBm(btnFrame, d, s, classFile)
            end
        end
    end
end

-- Colors page edits (swatches, darken, resets, profile switches) all end in
-- ApplyColorsToOUF. Once a Class-mode glow was printed (ns.RF_GlowClassFP), a
-- changed class colour re-runs the fingerprinted reload, which restyles only
-- the glows whose print changed. Calls in one frame (a profile switch can
-- make two) collapse into one check on the next frame: the flush frame stays
-- hidden until a call and hides itself before working.
do
    local flush = CreateFrame("Frame")
    flush:Hide()
    flush:SetScript("OnUpdate", function(self)
        self:Hide()
        local r0 = mod._rfGlowClassR
        if r0 == nil then return end
        local red, green, blue = CludesUI.Glows.ResolveColor("class")
        if red ~= r0 or green ~= mod._rfGlowClassG or blue ~= mod._rfGlowClassB then mod.RFC_ReloadAll() end
    end)
    hooksecurefunc(CludesUI, "ApplyColorsToOUF", function()
        if mod._rfGlowClassR ~= nil then flush:Show() end
    end)
end

-- Full assist-gate sweep over every live button. Per-unit matching is
-- unsafe (UnitIsUnit can return a SECRET boolean during group teardown),
-- and the gate's same-state early-out makes a sweep near-free.
local function SweepAssist()
    for i = 1, #registry do
        local btnFrame = registry[i]
        local d = mod.GetFFD and mod.GetFFD(btnFrame)
        if d and d.rfcDebuffs then
            local unitToken = btnFrame:GetAttribute("unit")
            if unitToken then ApplyAssistGate(btnFrame, d, unitToken) end
        end
    end
end

-- Indicator-set changes (spec swap, add/remove spell, mode toggle) need a container
-- swap, deferred to out-of-combat. Spec changes swap the whole indicator set, so they
-- re-drive the reload directly (the signature check makes a no-change reload cheap).
local bmRegen = CreateFrame("Frame")
bmRegen:RegisterEvent("PLAYER_REGEN_ENABLED")
bmRegen:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
bmRegen:RegisterEvent("PLAYER_ENTERING_WORLD")
-- A new pixel grid invalidates every snapped aura size (see ns.RFC_SnapSize).
-- CUI's own UI Scale (PP.SetUIScale) sets UIParent's scale directly, which fires
-- no UI_SCALE_CHANGED, so it calls this through the global as well.
bmRegen:RegisterEvent("UI_SCALE_CHANGED")
bmRegen:RegisterEvent("DISPLAY_SIZE_CHANGED")
function mod.RFC_PixelGridChanged()
    -- Compact / Grid Mode re-lay their frames once their one pixel has moved.
    mod.RF_CompactScaleChanged()
    if InCombatLockdown() then
        mod._rfcScaleDirty = true
    else
        mod.RFC_ReloadAll()
    end
end
_G._CURF_PixelGridChanged = mod.RFC_PixelGridChanged
-- The poison dispel-slot filter depends on Poison Cleansing Totem being talented
-- (see DispelSlotFilter). Talent edits fire no spec event, and IsPlayerSpell can
-- lag the trait event itself (the spellbook grant lands with SPELLS_CHANGED), so
-- shamans re-check on both; the reload runs only on an actual flip, and a flip
-- seen in combat latches for the regen branch below.
local function RecheckTotem()
    local known = rfcPlayerClass == "SHAMAN" and IsPlayerSpell(POISON_CLEANSING_TOTEM) or false
    if known == rfcTotemKnown then
        mod._rfcTotemDirty = nil
        return
    end
    if InCombatLockdown() then
        mod._rfcTotemDirty = true
        return
    end
    mod._rfcTotemDirty = nil
    rfcTotemKnown = known
    rfcTotemGen = rfcTotemGen + 1
    -- Stale by construction now: force the next compare to re-apply the slot
    -- filters instead of trusting a fingerprint stamped under the old value.
    for _, state in pairs(classFP) do
        state.dispelFilter = nil
    end
    mod.RFC_ReloadAll()
end
if rfcPlayerClass == "SHAMAN" then
    bmRegen:RegisterEvent("TRAIT_CONFIG_UPDATED")
    bmRegen:RegisterEvent("SPELLS_CHANGED")
end
bmRegen:SetScript("OnEvent", function(_, evt, arg1)
    if evt == "PLAYER_SPECIALIZATION_CHANGED" then
        if arg1 == "player" and not InCombatLockdown() then mod.RFC_ReloadAll() end
        return
    end
    if evt == "TRAIT_CONFIG_UPDATED" or evt == "SPELLS_CHANGED" then
        RecheckTotem()
        return
    end
    if evt == "UI_SCALE_CHANGED" or evt == "DISPLAY_SIZE_CHANGED" then
        mod.RFC_PixelGridChanged()
        return
    end
    if evt == "PLAYER_ENTERING_WORLD" then
        -- Assistability can flip on zone transitions without a unit
        -- re-assignment (cross-faction members become assistable inside
        -- instances); re-evaluate the gate for every live button.
        SweepAssist()
        return
    end
    if mod._rfcTotemDirty then RecheckTotem() end
    local any = mod._rfcScaleDirty or false
    mod._rfcScaleDirty = nil
    for i = 1, #registry do
        local d = mod.GetFFD and mod.GetFFD(registry[i])
        if d and d.rfcBmPending then
            d.rfcBmPending = nil
            any = true
        end
    end
    if any then mod.RFC_ReloadAll() end
end)

-- Event-driven gate re-evaluation (no polling): UNIT_PHASE fires exactly
-- when a member's phase/distance relationship to us changes (the eye-icon
-- transitions), UNIT_CONNECTION on connect state, UNIT_IN_RANGE_UPDATE on
-- the range boundary, GROUP_ROSTER_UPDATE on membership churn.
local assistWatch = CreateFrame("Frame")
assistWatch:RegisterEvent("UNIT_PHASE")
assistWatch:RegisterEvent("UNIT_CONNECTION")
assistWatch:RegisterEvent("UNIT_IN_RANGE_UPDATE")
assistWatch:RegisterEvent("GROUP_ROSTER_UPDATE")
-- Vehicle occupancy flips assistability for the occupant (the one state where
-- even the local player's own flags degrade -- see AssistProbe). ENTERING as
-- well as ENTERED: degradation starts with the boarding transition.
assistWatch:RegisterEvent("UNIT_ENTERING_VEHICLE")
assistWatch:RegisterEvent("UNIT_ENTERED_VEHICLE")
assistWatch:RegisterEvent("UNIT_EXITED_VEHICLE")
-- Cinematics (in-world cutscenes included) fire UNIT_FACTION for EVERY unit
-- at start and end while assistability flips -- and UNIT_FLAGS does NOT fire
-- for that transition, so without this edge the gate misses it entirely
-- (authors-channel etrace, 2026-08-13). The coalescer below flattens the
-- all-units burst into one sweep. CINEMATIC_STOP joins it for the
-- addon-cancelled skip path (same trigger set as the PAB and UF player
-- lanes); its faction restore usually fires UNIT_FACTION too, this just
-- closes any ordering gap.
assistWatch:RegisterEvent("UNIT_FACTION")
assistWatch:RegisterEvent("CINEMATIC_STOP")
-- Death/release/resurrection transitions (the alive requirement of the probe)
-- signal through UNIT_FLAGS; chatty in combat, but the coalescer below reduces any
-- burst to one deferred sweep.
assistWatch:RegisterEvent("UNIT_FLAGS")
-- Coalesced: UNIT_IN_RANGE_UPDATE fires continuously in a moving raid (every member
-- crossing the range boundary), and each sweep probes three identity APIs per button.
-- One deferred sweep per burst covers every trigger in the window; a quarter-second
-- of latency is invisible on a display-trust gate.
local assistSweepPending = false
local function AssistSweepDrain()
    assistSweepPending = false
    SweepAssist()
end
assistWatch:SetScript("OnEvent", function(_, evt)
    -- Vehicle and cinematic-skip edges sweep IMMEDIATELY: they are rare (no
    -- storm to coalesce) and the quarter-second defer reads as a visible
    -- flash of degraded "any buff" content on the player's own frame.
    if
        evt == "UNIT_ENTERING_VEHICLE"
        or evt == "UNIT_ENTERED_VEHICLE"
        or evt == "UNIT_EXITED_VEHICLE"
        or evt == "CINEMATIC_STOP"
    then
        SweepAssist()
        return
    end
    if assistSweepPending then return end
    assistSweepPending = true
    C_Timer.After(0.25, AssistSweepDrain)
end)
