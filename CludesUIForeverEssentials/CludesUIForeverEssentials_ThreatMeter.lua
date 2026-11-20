if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
if not (CludesUI and CludesUI.IS_FOREVER) then
    return
end
-------------------------------------------------------------------------------
--  CludesUIForeverEssentials_ThreatMeter.lua  (WoW Forever only)
--  Threat on your target (or focus) for everyone in the group, one bar each,
--  sorted by threat, with an optional pull aggro line and a warning sound. The
--  data comes from the ThreatData file and the window chrome (header buttons,
--  menus, lock, grip, drag and snapping) from the Window file, both listed
--  before this one. A fixed-size window: rows past what fits scroll with the
--  mouse wheel.
-------------------------------------------------------------------------------
local ADDON_NAME, module = ...
local mod = module.ThreatMeter
local CUI = CludesUI
local Look = mod.Look
-- The options page pool's table (made by the core, filled in place when the
-- options addon loads): the settings preview reads a dress generation from
-- it at call time.
local POOL = CUI._Pool

local UPDATE_DELAY = 0.2
local FOLLOW_INTERVAL = 0.5
local PREVIEW_SECONDS = 10
local MIN_W, MIN_H = mod.MIN_W, mod.MIN_H
local UNLOCK_KEY = "CUI_ThreatMeter"
local BORDER_KEY = "threatmeter"
CUI.RegisterBorderDefaults(BORDER_KEY, CUI.BORDER_DEFAULTS_BARS)
mod.BORDER_KEY = BORDER_KEY

-- Forward declarations (window scripts and the unlock element call these).
local RequestUpdate, Repaint, CreateWindow

-------------------------------------------------------------------------------
--  Settings: CludesUIDB.threatMeter, account-wide. Read() never creates the
--  table and Get() falls back to DEFAULTS, so nothing is written until the
--  user changes something (Cfg() is the write accessor). Default tables are
--  shared: callers read them, and writers assign a new table.
--  position is { point, relPoint, x, y } (unlock mode and the default) or
--  { x, y } (a header drag or grip resize: the top-left corner from the
--  screen's bottom-left). onlyWithThreat = false keeps the meter on screen
--  while it has nothing to list.
-------------------------------------------------------------------------------
local DEFAULTS = {
    enabled = false,
    source = "target",
    focusEnabled = false,
    pets = true,
    width = 320,
    height = 210,
    barHeight = 18,
    fontSize = 11,
    barSpacing = 2,
    position = { point = "CENTER", relPoint = "CENTER", x = 400, y = -100 },
    locked = false,
    snapDisabled = false,
    onlyWithThreat = true,
    growUp = false,
    showHeader = true,
    pullBar = true,
    pullColor = { r = 0, g = 0.55, b = 0 },
    showValue = true,
    showPercent = true,
    percentMode = "pull",
    warnSound = false,
    warnSoundKey = "none",
    warnAt = 80,
    warnSkipTank = true,
    playerColorOn = false,
    playerColor = { r = 0.8, g = 0.1, b = 0.1 },
    showPlayerMarker = true,
    tankColorOn = false,
    tankColor = { r = 0.1, g = 0.6, b = 0.1 },
    font = "__global",
    outlineMode = "__global",
}

-- Appearance groups, stored under appearance[group] (the Damage Meters shape).
local STYLE_DEFAULTS = {
    bars = {
        barTexture = "atrocity",
        iconStyle = "blizzard",
        classIconZoom = 0.06,
        iconZoom = 0,
        iconSeparator = false,
        leftTextOffsetX = 0,
        leftTextOffsetY = 0,
        rightTextOffsetX = 0,
        rightTextOffsetY = 0,
    },
    header = {
        hdrHeight = 22,
        hdrFontSize = 11,
        hdrBgColor = { r = 0.106, g = 0.106, b = 0.106 },
        hdrBgAlpha = 1,
        hdrTextUseAccent = true,
        hdrTextColor = { r = 1, g = 1, b = 1 },
        hdrTextOffX = 0,
        hdrTextOffY = 0,
        hdrBottomBorderSize = 0,
        hdrBottomSeparator = false,
        hdrBottomBorderColor = { r = 0, g = 0, b = 0, a = 1 },
    },
    colors = {
        showClassColor = true,
        barColorUseAccent = true,
        barColor = { r = 0.35, g = 0.55, b = 0.8 },
        barFillAlpha = 1,
        bgR = 0,
        bgG = 0,
        bgB = 0,
        bgAlpha = 0.75,
        bgTexture = "none",
        barBgR = 0,
        barBgG = 0,
        barBgB = 0,
        barBgAlpha = 0.045,
        barBgUseClassColor = false,
        leftTextUseClassColor = false,
        rightTextUseClassColor = false,
        rightTextUseThreatGradient = false,
        leftTextColor = { r = 1, g = 1, b = 1 },
        rightTextColor = { r = 1, g = 1, b = 1 },
    },
    borders = {
        windowBorderTexture = "solid",
        windowBorderSize = 0,
        windowBorderSizePx = false,
        windowBorderColor = { r = 0, g = 0, b = 0, a = 1 },
        windowBorderIncludeHeader = true,
        borderTexture = "solid",
        borderSize = 0,
        borderSizePx = false,
        barSeparators = false,
        borderR = 0,
        borderG = 0,
        borderB = 0,
        borderA = 1,
        borderTextureOffset = false,
        borderTextureShiftX = 0,
        borderTextureShiftY = 0,
        borderTextureOffsetY = false,
    },
}

local _NOCFG = {}
local function Read()
    return CludesUIDB and CludesUIDB.threatMeter or _NOCFG
end

local function Cfg()
    if not CludesUIDB then
        return {}
    end
    CludesUIDB.threatMeter = CludesUIDB.threatMeter or {}
    return CludesUIDB.threatMeter
end

local Get

local function Triplet(red, green, blue)
    if red == nil then
        return nil
    end
    return { r = red, g = green or 0, b = blue or 0 }
end

-- Earlier versions saved these settings under other names (and scales). A
-- read falls through to the old key while the new one is unset; nothing is
-- migrated and the old keys are never removed.
local LEGACY = {
    position = function(cfg)
        return cfg.pos
    end,
    pets = function(cfg)
        if cfg.ignorePets ~= nil then
            return not cfg.ignorePets
        end
    end,
    fontSize = function(cfg)
        return cfg.textSize
    end,
    barSpacing = function(cfg)
        return cfg.spacing
    end,
    playerColor = function(cfg)
        return Triplet(cfg.playerR, cfg.playerG, cfg.playerB)
    end,
    tankColor = function(cfg)
        return Triplet(cfg.tankR, cfg.tankG, cfg.tankB)
    end,
    pullColor = function(cfg)
        return Triplet(cfg.pullR, cfg.pullG, cfg.pullB)
    end,
    -- A chosen bar count becomes a window tall enough to show that many rows.
    height = function(cfg)
        local num = cfg.maxBars
        if type(num) ~= "number" then
            return nil
        end
        local gap = Get("barSpacing")
        local headerFrame = Get("showHeader") and mod.GetStyleValue("header", "hdrHeight") or 0
        return headerFrame + num * (Get("barHeight") + gap) - gap
    end,
}
local LEGACY_STYLE = {
    bars = {
        barTexture = function(cfg)
            return cfg.texture
        end,
    },
    colors = {
        bgAlpha = function(cfg)
            return cfg.bgA
        end,
        barFillAlpha = function(cfg)
            if type(cfg.barOpacity) == "number" then
                return cfg.barOpacity / 100
            end
        end,
    },
    borders = {
        windowBorderSize = function(cfg)
            return cfg.borderSize
        end,
        windowBorderColor = function(cfg)
            if cfg.borderR == nil then
                return nil
            end
            return { r = cfg.borderR, g = cfg.borderG or 0, b = cfg.borderB or 0, a = 1 }
        end,
    },
}

Get = function(key)
    local c = Read()
    local val = c[key]
    if val == nil then
        local legacy = LEGACY[key]
        if legacy then
            val = legacy(c)
        end
        if val == nil then
            val = DEFAULTS[key]
        end
    end
    return val
end

function mod.GetStyleValue(group, key)
    local c = Read()
    local val
    local ap = c.appearance
    if type(ap) == "table" and type(ap[group]) == "table" then
        val = ap[group][key]
    end
    if val == nil then
        local legacy = LEGACY_STYLE[group]
        legacy = legacy and legacy[key]
        if legacy then
            val = legacy(c)
        end
        if val == nil then
            val = STYLE_DEFAULTS[group][key]
        end
    end
    return val
end

-- Writes into the real saved appearance[group] table (created on first write)
-- and restyles. Callers whose toggle gates other rows refresh the page.
function mod.SetStyleValues(group, values)
    local cfg = Cfg()
    local ap = cfg.appearance
    if type(ap) ~= "table" then
        ap = {}
        cfg.appearance = ap
    end
    local saved = ap[group]
    if type(saved) ~= "table" then
        saved = {}
        ap[group] = saved
    end
    for key, value in pairs(values) do
        saved[key] = CUI.Lite.DeepCopy(value)
    end
    mod.ApplyStyle()
end

function mod.SetStyleValue(group, key, value)
    local cfg = Cfg()
    local ap = cfg.appearance
    if type(ap) ~= "table" then
        ap = {}
        cfg.appearance = ap
    end
    local saved = ap[group]
    if type(saved) ~= "table" then
        saved = {}
        ap[group] = saved
    end
    saved[key] = CUI.Lite.DeepCopy(value)
    mod.ApplyStyle()
end

mod.Get, mod.Cfg, mod.Read = Get, Cfg, Read

-------------------------------------------------------------------------------
--  Look (Global Settings > Style): "cui", "blizzard" or "classic", from the
--  account-wide flags useBlizzardStyle / useClassicStyle (Classic wins when
--  both are set). Read on the first call once the settings exist and kept
--  for the session: the art is set up once, so a flag the Style page writes
--  takes effect after the reload it asks for. On the addon's namespace,
--  where the Style page looks it up.
-------------------------------------------------------------------------------
local styleKey, forever
function module.TM_Style()
    if not styleKey then
        if not CludesUIDB then
            return "cui"
        end
        local c = Read()
        styleKey = (c.useClassicStyle and "classic") or (c.useBlizzardStyle and "blizzard") or "cui"
        -- Blizzard Style's WoW Forever variant, latched with it: the sibling
        -- flag the Style page writes together with the Blizzard one.
        forever = styleKey == "blizzard" and c.useForeverStyle == true
    end
    return styleKey
end
mod.TM_Style = module.TM_Style

-- True when the meter draws the WoW Forever variant this session (TM_Style
-- still reads "blizzard" then).
function module.TM_Forever()
    if not styleKey then
        module.TM_Style()
    end
    return forever == true
end

-- A stock look's one-time defaults on the account table c, once each (the
-- stamps; the controls stay the user's afterwards): Blizzard Style's lighter
-- background (WoW Forever's a little stronger, under its bronze frame),
-- Classic WoW UI's near-black window, the game's own bar fill and a
-- quarter-black bar track. The Style page runs them on the switch (a reload
-- follows; isForever for the WoW Forever variant); the login runs Classic's
-- for a table that arrived already switched.
function module.TM_SeedStock(cfg, key, isForever)
    if key == "blizzard" then
        if cfg.blizzBgAlphaSeeded then
            return
        end
        cfg.blizzBgAlphaSeeded = true
    elseif key == "classic" then
        if cfg.classicSeeded then
            return
        end
        cfg.classicSeeded = true
    else
        return
    end
    local ap = cfg.appearance
    if type(ap) ~= "table" then
        ap = {}
        cfg.appearance = ap
    end
    local colors = ap.colors
    if type(colors) ~= "table" then
        colors = {}
        ap.colors = colors
    end
    if key == "blizzard" then
        colors.bgAlpha = isForever and 0.65 or 0.4
        return
    end
    local barList = ap.bars
    if type(barList) ~= "table" then
        barList = {}
        ap.bars = barList
    end
    colors.bgR, colors.bgG, colors.bgB = 16 / 255, 16 / 255, 16 / 255
    barList.barTexture = "blizzard"
    colors.barBgR, colors.barBgG, colors.barBgB, colors.barBgAlpha = 0, 0, 0, 0.25
    colors.barBgUseClassColor = false
end

-- The header menus: the shared context menu in the look's menu art, opening
-- upward from the header button.
local MENU_OPTS = { above = true, look = "meter", fontKey = "essentials" }

-- The look's painters go in once, before the first surface is built.
local lookReady
local function EnsureLook()
    if lookReady then
        return
    end
    lookReady = true
    mod.UseLook(module.TM_Style(), module.TM_Forever())
    MENU_OPTS.look = Look.menuLook
end

local function TrackedUnit()
    if Get("focusEnabled") and Get("source") == "focus" then
        return "focus"
    end
    return "target"
end
mod.GetTrackedUnit = TrackedUnit

function mod.SetFocusEnabled(enabled)
    local cfg = Cfg()
    cfg.focusEnabled = enabled
    if not enabled and cfg.source == "focus" then
        cfg.source = nil
    end
end

mod.DisplayValues = {
    none = "None",
    value = "Threat Value",
    relative = "Tank %",
    pull = "Pull %",
    value_relative = "Threat Value + Tank %",
    value_pull = "Threat Value + Pull %",
}
mod.DisplayOrder = { "none", "value", "relative", "pull", "value_relative", "value_pull" }

function mod.GetDisplayedValue()
    local value, percent = Get("showValue"), Get("showPercent")
    if not percent then
        return value and "value" or "none"
    end
    local pull = Get("percentMode") == "pull"
    if value then
        return pull and "value_pull" or "value_relative"
    end
    return pull and "pull" or "relative"
end

function mod.SetDisplayedValue(val)
    if not mod.DisplayValues[val] then
        return
    end
    local cfg = Cfg()
    cfg.showValue = val == "value" or val == "value_relative" or val == "value_pull"
    cfg.showPercent = val ~= "none" and val ~= "value"
    if cfg.showPercent then
        cfg.percentMode = val:find("pull", 1, true) and "pull" or "relative"
    end
end

-- No maximum: a grip drag stops at the screen's edge instead.
local function ClampW(wid)
    return math.max(MIN_W, wid)
end
local function ClampH(hgt)
    return math.max(MIN_H, hgt)
end

-------------------------------------------------------------------------------
--  Media: bar textures and the warning sound list, built on first use.
-------------------------------------------------------------------------------
local textures
function mod.BarTextures()
    if not textures then
        local nameList, sequence
        textures, nameList, sequence = CUI.BuildBarTextureTables(true)
        -- The game's own bar fill, second in the list (Classic WoW UI seeds it).
        textures.blizzard = "Interface\\TargetingFrame\\UI-StatusBar"
        nameList.blizzard = "Blizzard"
        table.insert(sequence, 2, "blizzard")
        CUI.AppendSharedMediaTextures(nameList, sequence, nil, textures)
        mod.BarTextureNames, mod.BarTextureOrder = nameList, sequence
    end
    return textures
end

local soundPaths, soundNames, soundOrder
function mod.Sounds()
    if not soundPaths then
        soundPaths, soundNames, soundOrder = CUI.BuildAlertSoundTables()
        CUI.AppendSharedMediaSounds(soundPaths, soundNames, soundOrder)
    end
    return soundPaths, soundNames, soundOrder
end

function mod.PlaySoundKey(key)
    CUI.PlaySoundPath(mod.Sounds()[key])
end

-------------------------------------------------------------------------------
--  Style memo: every setting the paint reads, resolved once. A settings write
--  clears it (ApplyStyle); a global font, outline, accent or colour-palette
--  (class colours) change rebuilds it.
--  Frames and rows stamp the table they were painted with, so a new table
--  restyles each of them once.
-------------------------------------------------------------------------------
local cachedStyle
local CLASS_ICON_DIR = "Interface\\AddOns\\CludesUI\\media\\icons\\class-full\\"

local function Style()
    local font = CUI.GetFontPath("essentials")
    local outline = CUI.GetFontOutlineFlag("essentials")
    local accent = CUI.CLUDES_GREEN
    local colorGen = CUI._dmGen
    local dm = cachedStyle
    if
        dm
        and dm.globalFont == font
        and dm.globalOutline == outline
        and dm.colorGen == colorGen
        and dm.accentR == accent.r
        and dm.accentG == accent.g
        and dm.accentB == accent.b
    then
        return dm
    end
    dm = {}
    for group, defaultSet in pairs(STYLE_DEFAULTS) do
        for key in pairs(defaultSet) do
            dm[key] = mod.GetStyleValue(group, key)
        end
    end
    dm.barHeight, dm.barSpacing, dm.fontSize = Get("barHeight"), Get("barSpacing"), Get("fontSize")
    dm.showHeader, dm.growUp = Get("showHeader"), Get("growUp")
    -- The look is latched for the session before the window is built. A
    -- look's header band may add a rail under the configured height; the
    -- title and buttons rise by half of it to stay centred above it.
    local rail = dm.showHeader and Look.HeaderRail(dm.hdrHeight) or 0
    dm.headerHeight = dm.showHeader and dm.hdrHeight + rail or 0
    dm.hdrLift = rail / 2
    dm.inset = Look.inset
    dm.iconSize = Look.IconSize(22)
    dm.focusEnabled, dm.tracked = Get("focusEnabled"), TrackedUnit()
    dm.pullColor, dm.playerColor, dm.tankColor = Get("pullColor"), Get("playerColor"), Get("tankColor")
    dm.playerColorOn, dm.tankColorOn = Get("playerColorOn"), Get("tankColorOn")
    dm.showPlayerMarker = Get("showPlayerMarker")
    local showValue, showPercent = Get("showValue"), Get("showPercent")
    dm.showValue, dm.showPercent = showValue, showPercent
    dm.pullPercent = Get("percentMode") == "pull"
    dm.nameFormat = Get("nameFormat")
    -- The widest value text a row realistically shows; the first row painted
    -- with this style measures it in the row font to size the value column.
    local sampleValue = CUI.AbbreviateNumber(888888)
    dm.valueSample = showValue and showPercent and (sampleValue .. "  888%")
        or (showValue and sampleValue or (showPercent and "888%" or nil))
    local fontKey, outlineMode = Get("font"), Get("outlineMode")
    dm.textFont = fontKey ~= "__global" and CUI.ResolveFontName(fontKey) or nil
    if outlineMode == "outline" then
        dm.textFlag = CUI.SlugFlag("OUTLINE, SLUG")
    elseif outlineMode == "thick" then
        dm.textFlag = CUI.SlugFlag("THICKOUTLINE, SLUG")
    elseif outlineMode == "none" then
        dm.textFlag = ""
    end
    dm.texturePath = CUI.ResolveTexturePath(mod.BarTextures(), dm.barTexture, "Interface\\Buttons\\WHITE8X8")
    if dm.bgTexture ~= "none" and not Look.stock then
        dm.bgTexturePath = CUI.ResolveTexturePath(mod.BarTextures(), dm.bgTexture, nil)
    end
    if not Look.stock then
        dm.barSeparatorsOn = dm.barSeparators
            and dm.borderSize > 0
            and CUI.GetBorderCompanion(dm.borderTexture, "sepH") ~= nil
        dm.headerSeparatorOn = dm.hdrBottomSeparator
            and dm.showHeader
            and dm.windowBorderIncludeHeader ~= false
            and dm.windowBorderSize > 0
            and CUI.GetBorderCompanion(dm.windowBorderTexture, "sepH") ~= nil
        dm.iconSeparatorOn = dm.iconSeparator
            and dm.iconStyle ~= "none"
            and dm.borderSize > 0
            and CUI.GetBorderCompanion(dm.borderTexture, "sepV") ~= nil
    end
    if dm.iconStyle ~= "none" and dm.iconStyle ~= "blizzard" then
        dm.iconPath = CLASS_ICON_DIR .. dm.iconStyle .. ".tga"
    end
    dm.accent = accent
    dm.globalFont, dm.globalOutline, dm.colorGen = font, outline, colorGen
    dm.accentR, dm.accentG, dm.accentB = accent.r, accent.g, accent.b
    cachedStyle = dm
    return dm
end

-- nil textFont / textFlag leave the module's font and outline to
-- ApplyModuleFontFamily. The title and rows show players' and mobs' names, so
-- every text here takes a font family (Cyrillic, Korean and Chinese names draw in
-- the client's own faces); every font write to them goes through here.
local function Font(fontStr, dim, dm)
    CUI.ApplyModuleFontFamily(fontStr, dm.textFont, dim, "essentials", dm.textFlag)
end

local function PaintText(fontStr, color)
    fontStr:SetTextColor(color.r, color.g, color.b)
end

-- The window border takes the plain border defaults (as the Damage Meters
-- window does), the bars this meter's own. A stock look draws neither.
local function Border(targetUnit, dm, window)
    local dim, texture, exact, red, green, blue, a
    if window then
        local color = dm.windowBorderColor
        dim, texture, exact = dm.windowBorderSize, dm.windowBorderTexture, dm.windowBorderSizePx
        red, green, blue, a = color.r or 0, color.g or 0, color.b or 0, color.a or 1
    else
        dim, texture, exact = dm.borderSize, dm.borderTexture, dm.borderSizePx
        red, green, blue, a = dm.borderR, dm.borderG, dm.borderB, dm.borderA
    end
    dim = (Look.stock or (not window and dm.barSeparatorsOn)) and 0 or (dim or 0)
    local px = dim > 0 and CUI.BorderPx(exact, dim, texture) or nil
    if window then
        CUI.ApplyBorderStyle(targetUnit, dim, red, green, blue, a, texture, nil, nil, nil, nil, nil, nil, nil, px)
        return
    end
    CUI.ApplyBorderStyle(
        targetUnit,
        dim,
        red,
        green,
        blue,
        a,
        texture,
        dm.borderTextureOffset or nil,
        dm.borderTextureOffsetY or nil,
        dm.borderTextureShiftX or nil,
        dm.borderTextureShiftY or nil,
        BORDER_KEY,
        dim,
        nil,
        px
    )
end

-- A size in physical pixels, in UI units.
local function PhysicalPixels(val)
    local Pix = CUI.PP
    return Pix.Scale((val or 0) * Pix.mult)
end

-- Separator art draws above the window border, clipped inside the window.
local function PlaceSeparators(hostRegion)
    local s, dm = hostRegion.surface, hostRegion.style
    local Pix, es = CUI.PP, hostRegion:GetEffectiveScale()
    local function Place(texture, key, dim, exact, posY, red, green, blue, a)
        local px = CUI.BorderPx(exact, dim, key)
        local thick = CUI.BorderCompanionThickness(key, dim, px, es)
        local lead = Pix.SnapForES(thick * 2 / CUI.GetBorderCompanion(key, "sepSize"), es)
        local bottom = Pix.SnapForES(posY - lead, es)
        if bottom <= -s:GetHeight() + dm.inset then
            texture:Hide()
            return
        end
        texture:SetTexture(CUI.GetBorderCompanion(key, "sepH"))
        texture:SetTexCoord(0, 1, 1, 0)
        texture:SetVertexColor(red, green, blue, a)
        texture:ClearAllPoints()
        texture:SetPoint("BOTTOMLEFT", s, "TOPLEFT", dm.inset, bottom)
        texture:SetPoint("BOTTOMRIGHT", s, "TOPRIGHT", -dm.inset, bottom)
        texture:SetHeight(thick)
        texture:Show()
    end
    if dm.headerSeparatorOn then
        if not hostRegion.headerLine then
            hostRegion.headerLine = hostRegion.art:CreateTexture(nil, "OVERLAY")
            Pix.DisablePixelSnap(hostRegion.headerLine)
        end
        local color = dm.windowBorderColor
        Place(
            hostRegion.headerLine,
            dm.windowBorderTexture,
            dm.windowBorderSize,
            dm.windowBorderSizePx,
            -dm.inset - dm.headerHeight,
            color.r or 0,
            color.g or 0,
            color.b or 0,
            color.a or 1
        )
    elseif hostRegion.headerLine then
        hostRegion.headerLine:Hide()
    end
    local num = dm.barSeparatorsOn and hostRegion.count or 0
    for index = 1, num do
        local texture = hostRegion.lines[index]
        if not texture then
            texture = hostRegion.art:CreateTexture(nil, "OVERLAY")
            Pix.DisablePixelSnap(texture)
            hostRegion.lines[index] = texture
        end
        local posY = -dm.inset - dm.headerHeight - index * (dm.barHeight + dm.barSpacing) + dm.barSpacing / 2
        Place(
            texture,
            dm.borderTexture,
            dm.borderSize,
            dm.borderSizePx,
            posY,
            dm.borderR,
            dm.borderG,
            dm.borderB,
            dm.borderA
        )
    end
    for index = num + 1, #hostRegion.lines do
        hostRegion.lines[index]:Hide()
    end
    num = dm.iconSeparatorOn and hostRegion.count or 0
    for index = 1, num do
        local rowFrame, texture = s.rows[index], hostRegion.iconLines[index]
        if not texture then
            texture = hostRegion.art:CreateTexture(nil, "OVERLAY", nil, 1)
            Pix.DisablePixelSnap(texture)
            hostRegion.iconLines[index] = texture
        end
        if rowFrame._iconWidth and rowFrame._iconWidth > 0 then
            CUI.PlaceBorderDividerV(
                texture,
                rowFrame.fill,
                false,
                false,
                dm.borderTexture,
                dm.borderSize,
                CUI.BorderPx(dm.borderSizePx, dm.borderSize, dm.borderTexture),
                es
            )
            local slotIndex = dm.growUp and (hostRegion.count - index + 1) or index
            local above = slotIndex == 1 and hostRegion.headerLine or hostRegion.lines[slotIndex - 1]
            local below = hostRegion.lines[slotIndex]
            local topY, bottom = 0, 0
            -- The flipped horizontal strip's solid stroke spans texels 3-7 of 32.
            if above and above:IsShown() then
                topY = Pix.SnapForES(
                    math.max(0, above:GetHeight() / 32 - (slotIndex == 1 and 0 or dm.barSpacing / 2)),
                    es
                )
            end
            if below and below:IsShown() then
                bottom = Pix.SnapForES(math.max(0, below:GetHeight() * 3 / 32 - dm.barSpacing / 2), es)
            end
            topY = topY - Pix.perfect / es
            if topY + bottom >= dm.barHeight then
                texture:Hide()
            else
                local lead = Pix.SnapForES(
                    texture:GetWidth() * 2 / CUI.GetBorderCompanion(dm.borderTexture, "sepSize"),
                    es
                )
                texture:SetPoint("TOPLEFT", rowFrame.fill, "TOPLEFT", -lead, -topY)
                texture:SetPoint("BOTTOMLEFT", rowFrame.fill, "BOTTOMLEFT", -lead, bottom)
            end
            texture:SetVertexColor(dm.borderR, dm.borderG, dm.borderB, dm.borderA)
        else
            texture:Hide()
        end
    end
    for index = num + 1, #hostRegion.iconLines do
        hostRegion.iconLines[index]:Hide()
    end
end

local function SyncSeparators(s, dm, total, iconsChanged)
    local hostRegion = s.separators
    if not dm.headerSeparatorOn and not dm.barSeparatorsOn and not dm.iconSeparatorOn then
        if hostRegion and hostRegion.style then
            hostRegion:Hide()
            hostRegion.style = nil
            CUI.RegisterPxReapply(hostRegion, nil)
        end
        return
    end
    if not hostRegion then
        hostRegion = CreateFrame("Frame", nil, s)
        hostRegion:SetAllPoints()
        hostRegion:SetClipsChildren(true)
        hostRegion:EnableMouse(false)
        hostRegion.art = CreateFrame("Frame", nil, hostRegion)
        hostRegion.art:SetAllPoints()
        hostRegion.art:EnableMouse(false)
        hostRegion.surface, hostRegion.lines, hostRegion.iconLines = s, {}, {}
        s.separators = hostRegion
    end
    local scale, height = hostRegion:GetEffectiveScale(), s:GetHeight()
    local strata, level = s:GetFrameStrata(), s.border:GetFrameLevel() + 2
    if
        hostRegion.style == dm
        and hostRegion.count == total
        and hostRegion.scale == scale
        and hostRegion.height == height
        and hostRegion.strata == strata
        and hostRegion.level == level
        and not iconsChanged
    then
        return
    end
    hostRegion.style, hostRegion.count, hostRegion.scale, hostRegion.height = dm, total, scale, height
    hostRegion.strata, hostRegion.level = strata, level
    hostRegion:SetFrameStrata(strata)
    hostRegion:SetFrameLevel(level)
    hostRegion.art:SetFrameLevel(level + 1)
    hostRegion:Show()
    PlaceSeparators(hostRegion)
    CUI.RegisterPxReapply(
        hostRegion,
        (
            (dm.headerSeparatorOn and dm.windowBorderSizePx)
            or (dm.barSeparatorsOn and dm.borderSizePx)
            or dm.iconSeparatorOn
        )
                and PlaceSeparators
            or nil
    )
end

-------------------------------------------------------------------------------
--  Surface: the live meter and the options preview share this structure,
--  the chrome paint and the row renderer.
-------------------------------------------------------------------------------
-- The Damage Meters window layout: the header across the top (inset under a
-- stock look), its buttons from the right edge with the title running up to
-- the leftmost one (the engine truncates it: a mob name can be secret), the
-- window background below the header, and the window border above the
-- header. A look that clips the rows gets their clip fitted below the header
-- inside the inset. The live window reports the border's reach to size
-- matching.
local function ApplyChrome(dm, cfg)
    if cfg._style == dm then
        return
    end
    cfg._style = dm
    local headerFrame, inset = cfg.header, dm.inset
    headerFrame:ClearAllPoints()
    headerFrame:SetPoint("TOPLEFT", cfg, "TOPLEFT", inset, -inset)
    headerFrame:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -inset, -inset)
    headerFrame:SetHeight(dm.showHeader and dm.headerHeight or 0.001)
    headerFrame:SetShown(dm.showHeader)
    local area = cfg.rowArea
    if area then
        area:ClearAllPoints()
        area:SetPoint("TOPLEFT", cfg, "TOPLEFT", inset, -inset - dm.headerHeight)
        area:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", -inset, inset)
    end
    local backdrop = dm.hdrBgColor
    Look.HeaderBg(headerFrame.bg, backdrop.r, backdrop.g, backdrop.b, dm.hdrBgAlpha, dm.bgR, dm.bgG, dm.bgB)
    if not Look.HeaderLine(headerFrame.line) then
        local dim, lineTex = dm.hdrBottomBorderSize or 0, dm.hdrBottomBorderColor
        headerFrame.line:SetHeight(PhysicalPixels(dim))
        headerFrame.line:SetColorTexture(lineTex.r or 0, lineTex.g or 0, lineTex.b or 0, lineTex.a or 1)
        headerFrame.line:SetShown(dim > 0 and not Look.stock and not dm.headerSeparatorOn)
    end
    Font(cfg.title, dm.hdrFontSize, dm)
    -- A look may colour the accented title its own way (WoW Forever's gold).
    PaintText(cfg.title, dm.hdrTextUseAccent ~= false and (Look.titleColor or dm.accent) or dm.hdrTextColor)
    local source = cfg.sourceBtn
    Font(source.label, dm.hdrFontSize, dm)
    source.label:SetText(dm.tracked == "focus" and CludesUI.L("Focus") or CludesUI.L("Target"))
    source:SetShown(dm.focusEnabled)
    local leftmost = mod.LayoutHeaderButtons(cfg, dm.iconSize, dm.hdrLift)
    local ty = dm.hdrTextOffY + dm.hdrLift
    cfg.title:ClearAllPoints()
    cfg.title:SetPoint("LEFT", headerFrame, "LEFT", 6 + dm.hdrTextOffX, ty)
    if leftmost then
        cfg.title:SetPoint("RIGHT", leftmost, "LEFT", -6, dm.hdrTextOffY)
    else
        cfg.title:SetPoint("RIGHT", headerFrame, "RIGHT", -6, ty)
    end
    cfg.bg:ClearAllPoints()
    cfg.bg:SetPoint("TOPLEFT", cfg, "TOPLEFT", 0, -dm.headerHeight)
    cfg.bg:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", 0, 0)
    cfg.bg:SetVertexColor(1, 1, 1, 1)
    if dm.bgTexturePath then
        cfg.bg:SetTexture(dm.bgTexturePath)
        cfg.bg:SetVertexColor(dm.bgR, dm.bgG, dm.bgB, dm.bgAlpha)
    else
        Look.WindowBg(cfg.bg, dm.bgR, dm.bgG, dm.bgB, dm.bgAlpha)
    end
    local border = cfg.border
    border:ClearAllPoints()
    if dm.windowBorderIncludeHeader == false then
        border:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, 0)
    else
        border:SetPoint("TOPLEFT", cfg, "TOPLEFT", 0, 0)
    end
    border:SetPoint("BOTTOMRIGHT", cfg, "BOTTOMRIGHT", 0, 0)
    border:SetFrameLevel(headerFrame:GetFrameLevel() + 4)
    Border(border, dm, true)
    if cfg.unlockKey then
        CUI.MatchPadChanged(cfg.unlockKey)
    end
end

-- live: the meter window (header buttons take the mouse and show tooltips);
-- otherwise the settings preview, whose header only shows them.
local function CreateSurface(hostFrame, name, live)
    EnsureLook()
    local surface = CreateFrame("Frame", name, hostFrame)
    surface.rows = {}
    surface.hdrBtns = {}
    surface.bg = surface:CreateTexture(nil, "BACKGROUND")
    surface.border = CreateFrame("Frame", nil, surface)
    surface.border:EnableMouse(false)
    -- A look that clips the rows parents them to a frame of their own, fitted
    -- to the row area by ApplyChrome.
    if Look.clipRows then
        surface.rowArea = CreateFrame("Frame", nil, surface)
        surface.rowArea:SetClipsChildren(true)
    end
    local headerFrame = CreateFrame("Frame", nil, surface)
    surface.header = headerFrame
    headerFrame:SetFrameLevel(surface:GetFrameLevel() + 5)
    headerFrame.bg = headerFrame:CreateTexture(nil, "BACKGROUND")
    headerFrame.bg:SetAllPoints()
    headerFrame.line = headerFrame:CreateTexture(nil, "OVERLAY", nil, 7)
    headerFrame.line:SetPoint("BOTTOMLEFT")
    headerFrame.line:SetPoint("BOTTOMRIGHT")
    surface.title = headerFrame:CreateFontString(nil, "OVERLAY")
    surface.title:SetJustifyH("LEFT")
    surface.title:SetWordWrap(false)
    -- Rightmost first.
    surface.settingsBtn =
        mod.MakeHeaderButton(surface, "settings", "dm_settings.png", live and CludesUI.L("Settings") or nil)
    surface.sourceBtn =
        mod.MakeHeaderTextButton(surface, "source", live and CludesUI.L("Tracked Unit") or nil)
    if not live then
        surface.settingsBtn:EnableMouse(false)
        surface.sourceBtn:EnableMouse(false)
    end
    -- Fonts are set before any text is.
    ApplyChrome(Style(), surface)
    return surface
end

local function MakeRow(index, surface, rowList)
    -- Inside the look's row clip when it has one (placed on the surface all
    -- the same).
    local rowFrame = CreateFrame("Frame", nil, surface.rowArea or surface)
    rowFrame.fill = CreateFrame("StatusBar", nil, rowFrame)
    rowFrame.fill:SetAllPoints()
    rowFrame.fill:SetMinMaxValues(0, 100)
    rowFrame.border = CreateFrame("Frame", nil, rowFrame)
    rowFrame.border:SetAllPoints()
    rowFrame.border:SetFrameLevel(rowFrame.fill:GetFrameLevel() + 1)
    -- Border styling hides its frame when the border size is zero, so the text
    -- gets its own always-visible parent above that frame.
    rowFrame.text = CreateFrame("Frame", nil, rowFrame)
    rowFrame.text:SetAllPoints()
    rowFrame.text:SetFrameLevel(rowFrame.border:GetFrameLevel() + 1)
    rowFrame.classIcon = rowFrame.text:CreateTexture(nil, "ARTWORK")
    rowFrame.petIcon = rowFrame.text:CreateTexture(nil, "ARTWORK")
    rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
    rowFrame.bg:SetAllPoints()
    rowFrame.label = rowFrame.text:CreateFontString(nil, "OVERLAY")
    rowFrame.label:SetJustifyH("LEFT")
    rowFrame.label:SetWordWrap(false)
    rowFrame.value = rowFrame.text:CreateFontString(nil, "OVERLAY")
    rowFrame.value:SetJustifyH("RIGHT")
    -- Your own row: a thin white stripe on the bar's left edge.
    rowFrame.self = rowFrame.fill:CreateTexture(nil, "OVERLAY")
    rowFrame.self:SetPoint("TOPLEFT")
    rowFrame.self:SetPoint("BOTTOMLEFT")
    rowFrame.self:SetWidth(2)
    rowFrame.self:SetColorTexture(1, 1, 1, 0.95)
    rowList[index] = rowFrame
    return rowFrame
end

local BLIZZARD_CLASS_ICONS = "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES"
local PET_ICON = CUI.ClientIcon(132161)

local function IconCoords(glyph, leftX, right, topY, bottom, zoom)
    local dx, dy = (right - leftX) * zoom, (bottom - topY) * zoom
    glyph:SetTexCoord(leftX + dx, right - dx, topY + dy, bottom - dy)
end

-- Class icon (none for a pet) plus the pet icon; returns the width they take.
local function RowIcons(rowFrame, classFile, isPet, dm)
    rowFrame.classIcon:Hide()
    rowFrame.petIcon:Hide()
    local style = dm.iconStyle
    if style == "none" then
        return 0
    end
    if isPet then
        classFile = nil
    end
    local dim, posX = dm.barHeight, 0
    local coords
    if style == "blizzard" then
        -- Threat units give no reliable specialization, so this is the class art.
        coords = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
        if coords then
            rowFrame.classIcon:SetTexture(BLIZZARD_CLASS_ICONS)
            local zoom = dm.classIconZoom + (1 - 2 * dm.classIconZoom) * dm.iconZoom
            IconCoords(rowFrame.classIcon, coords[1], coords[2], coords[3], coords[4], zoom)
        end
    else
        coords = classFile and CUI.CLASS_ICON_SPRITE_COORDS[classFile]
        if coords then
            rowFrame.classIcon:SetTexture(dm.iconPath)
            IconCoords(rowFrame.classIcon, coords[1], coords[2], coords[3], coords[4], dm.iconZoom)
        end
    end
    if coords then
        rowFrame.classIcon:SetSize(dim, dim)
        rowFrame.classIcon:ClearAllPoints()
        rowFrame.classIcon:SetPoint("LEFT", rowFrame, "LEFT", posX, 0)
        rowFrame.classIcon:Show()
        posX = posX + dim + 2
    end
    if isPet then
        rowFrame.petIcon:SetTexture(PET_ICON)
        IconCoords(rowFrame.petIcon, 0.06, 0.94, 0.06, 0.94, dm.iconZoom)
        rowFrame.petIcon:SetSize(dim, dim)
        rowFrame.petIcon:ClearAllPoints()
        rowFrame.petIcon:SetPoint("LEFT", rowFrame, "LEFT", posX, 0)
        rowFrame.petIcon:Show()
        posX = posX + dim + 2
    end
    return posX
end

-- Paints one row, touching only what changed since its last paint: the style
-- (fonts, texture, borders), the entry's identity (unit or sample, roster
-- generation: class, icons, own stripe, name), who holds aggro (colours), and
-- the numbers (fill and value text).
local function PaintRow(rowFrame, e, dm, topY, gen)
    local restyle = rowFrame._style ~= dm
    if restyle then
        Font(rowFrame.label, dm.fontSize, dm)
        Font(rowFrame.value, dm.fontSize, dm)
        rowFrame.fill:SetStatusBarTexture(dm.texturePath)
        Border(rowFrame.border, dm, false)
        if not dm.valueWidth then
            local wid = 0
            if dm.valueSample then
                rowFrame.value:SetText(dm.valueSample)
                wid = math.ceil(rowFrame.value:GetUnboundedStringWidth()) + 2
            end
            dm.valueWidth = wid
        end
        rowFrame.value:SetWidth(dm.valueWidth)
        Look.RowStyled(rowFrame, dm)
        rowFrame._style = dm
    end
    if restyle or rowFrame._key ~= e.key or rowFrame._gen ~= gen then
        rowFrame._key, rowFrame._gen = e.key, gen
        local classFile = e.class
        if e.unit then
            classFile = mod.ClassOf(e.unit)
        end
        local isPet = e.isPet == true
        if restyle or rowFrame._class ~= classFile or rowFrame._isPet ~= isPet then
            -- The texts sit inside the fill wherever the look seats it.
            rowFrame._iconWidth = RowIcons(rowFrame, classFile, isPet, dm)
            local leftX, right = Look.SeatFill(rowFrame, rowFrame._iconWidth, dm)
            rowFrame.value:ClearAllPoints()
            rowFrame.value:SetPoint("RIGHT", -5 - right + dm.rightTextOffsetX, dm.rightTextOffsetY)
            rowFrame.label:ClearAllPoints()
            rowFrame.label:SetPoint("LEFT", leftX + 5 + dm.leftTextOffsetX, dm.leftTextOffsetY)
            rowFrame.label:SetPoint("RIGHT", rowFrame.value, "LEFT", -5, 0)
            rowFrame._class, rowFrame._isPet = classFile, isPet
        end
        rowFrame._own = e.own == true
        rowFrame.self:SetShown(rowFrame._own and dm.showPlayerMarker)
        rowFrame._aggro, rowFrame._name = nil, nil
        rowFrame._valueThreat = nil
        if not e.unit then
            -- A preview row: the Name Format reaches your own sample name.
            local name = e.pull and CludesUI.L("Pull Aggro") or e.name
            if e.own and dm.nameFormat then
                name = CUI.ShortName(name, dm.nameFormat)
            end
            rowFrame.label:SetText(name)
        end
    end
    -- A live name is re-read (it can arrive after the roster does). A secret
    -- name goes straight to the font string and cannot be compared. The Name
    -- Format (dm.nameFormat, so a change restyles every row) shortens a
    -- player's name; a pet keeps its own and a secret passes whole.
    if e.unit then
        local name = CUI.WithSurname(UnitName(e.unit))
        if dm.nameFormat and not e.isPet then
            name = CUI.ShortName(name, dm.nameFormat)
        end
        if issecretvalue(name) then
            rowFrame.label:SetText(name)
            rowFrame._name = nil
        elseif name ~= rowFrame._name then
            rowFrame.label:SetText(name or e.unit)
            rowFrame._name = name
        end
    end
    local aggro = e.tanking == true
    if rowFrame._aggro ~= aggro then
        rowFrame._aggro = aggro
        local classFile = rowFrame._class
        local color = classFile and RAID_CLASS_COLORS[classFile] and CUI.GetClassColor(classFile)
        local fillTex
        if e.pull then
            fillTex = dm.pullColor
        elseif rowFrame._own and dm.playerColorOn then
            fillTex = dm.playerColor
        elseif aggro and dm.tankColorOn then
            fillTex = dm.tankColor
        elseif dm.showClassColor ~= false and color then
            fillTex = color
        elseif dm.barColorUseAccent ~= false then
            fillTex = dm.accent
        else
            fillTex = dm.barColor
        end
        rowFrame.fill:SetStatusBarColor(fillTex.r, fillTex.g, fillTex.b, dm.barFillAlpha)
        local backdrop = dm.barBgUseClassColor and color
        Look.RowBg(
            rowFrame.bg,
            backdrop and backdrop.r or dm.barBgR,
            backdrop and backdrop.g or dm.barBgG,
            backdrop and backdrop.b or dm.barBgB,
            dm.barBgAlpha
        )
        PaintText(rowFrame.label, dm.leftTextUseClassColor and color or dm.leftTextColor)
        if not dm.rightTextUseThreatGradient then
            PaintText(rowFrame.value, dm.rightTextUseClassColor and color or dm.rightTextColor)
        end
    end
    if dm.rightTextUseThreatGradient and (dm.showValue or dm.showPercent) then
        local pct = math.max(0, math.min(100, e.scaled or 0))
        if rowFrame._valueThreat ~= pct then
            rowFrame._valueThreat = pct
            local t = pct / 50
            rowFrame.value:SetTextColor(math.min(1, t), math.min(1, 2 - t), 0)
        end
    end
    -- Every bar shares one scale: raw threat against the top of the whole list.
    local fillValue = topY > 0 and e.raw * 100 / topY or 0
    if rowFrame._fill ~= fillValue then
        rowFrame._fill = fillValue
        rowFrame.fill:SetValue(fillValue)
    end
    -- The pull line shows its threat value; alone, its percent (Pull %: 100,
    -- Tank %: where the line sits against the tank's threat).
    local raw = dm.showValue and e.raw or nil
    local pct
    if dm.showPercent and not (e.pull and raw) then
        if dm.pullPercent then
            pct = e.scaled
        else
            pct = e.rawPct
        end
    end
    if restyle or rowFrame._vRaw ~= raw or rowFrame._vPct ~= pct then
        rowFrame._vRaw, rowFrame._vPct = raw, pct
        if raw and pct then
            rowFrame.value:SetFormattedText("%s  %.0f%%", CUI.AbbreviateNumber(raw), pct)
        elseif raw then
            rowFrame.value:SetText(CUI.AbbreviateNumber(raw))
        elseif pct then
            rowFrame.value:SetFormattedText("%.0f%%", pct)
        else
            rowFrame.value:SetText("")
        end
    end
end

local function RenderRows(cfg, entries, first, total, dm, topY)
    local rowList, gen = cfg.rows, mod.rosterGen
    local step, inset = dm.barHeight + dm.barSpacing, dm.inset
    local iconsChanged
    for index = 1, total do
        local rowFrame = rowList[index] or MakeRow(index, cfg, rowList)
        local slotPos = dm.growUp and (total - index) or (index - 1)
        local posY = -inset - dm.headerHeight - slotPos * step
        if rowFrame._y ~= posY or rowFrame._style ~= dm then
            -- Both anchors share the top edge: a vertical-centre anchor to the
            -- window would overconstrain the height.
            rowFrame:ClearAllPoints()
            rowFrame:SetPoint("TOPLEFT", cfg, "TOPLEFT", inset, posY)
            rowFrame:SetPoint("TOPRIGHT", cfg, "TOPRIGHT", -inset, posY)
            rowFrame:SetHeight(dm.barHeight)
            rowFrame._y = posY
        end
        local iconWidth = rowFrame._iconWidth
        PaintRow(rowFrame, entries[index + first], dm, topY, gen)
        if iconWidth ~= rowFrame._iconWidth then
            iconsChanged = true
        end
    end
    local isShown = cfg._count or #rowList
    for index = total + 1, isShown do
        rowList[index]:Hide()
    end
    for index = isShown + 1, total do
        rowList[index]:Show()
    end
    cfg._count = total
    SyncSeparators(cfg, dm, total, iconsChanged)
end

-------------------------------------------------------------------------------
--  Preview group (options header, unlock mode, /cuitm test): a tank holding
--  aggro, you (ranged: you pull at 130% of the tank's threat) and a few others,
--  through the same pull line and sort as live data. Built once per Include
--  Pets / pull bar pair.
-------------------------------------------------------------------------------
local DEMO_TANK = 12000
local DEMO = {
    { class = "WARRIOR", raw = 12000, tank = true },
    { own = true, raw = 10080, reach = 1.3 },
    { class = "ROGUE", raw = 8040, reach = 1.1 },
    { class = "HUNTER", raw = 5160, reach = 1.3 },
    { class = "HUNTER", raw = 3120, reach = 1.1, isPet = true },
    { class = "PRIEST", raw = 2160, reach = 1.3 },
}
local demoList, demoEntries, demoPull = {}, {}, {}
local demoPets, demoPullBar

local function DemoEntry(index, cfg)
    local e = {
        key = cfg,
        raw = cfg.raw,
        order = index,
        pull = false,
        isPet = cfg.isPet == true,
        own = cfg.own == true,
        tanking = cfg.tank == true,
    }
    e.scaled = cfg.tank and 100 or cfg.raw * 100 / (DEMO_TANK * cfg.reach)
    e.rawPct = cfg.raw * 100 / DEMO_TANK
    if cfg.own then
        local _, classFile = UnitClass("player")
        e.class, e.name = classFile, CUI.WithSurname(UnitName("player"))
    elseif cfg.tank then
        e.class, e.name = cfg.class, CludesUI.L("Tank")
    elseif cfg.isPet then
        e.class, e.name = cfg.class, CludesUI.L("Pet")
    else
        e.class = cfg.class
        e.name = (LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[cfg.class]) or cfg.class
    end
    return e
end

local function DemoList()
    local pets, pullBar = Get("pets"), Get("pullBar")
    if demoPets == pets and demoPullBar == pullBar then
        return demoList
    end
    demoPets, demoPullBar = pets, pullBar
    wipe(demoList)
    local me
    for index, s in ipairs(DEMO) do
        if pets or not s.isPet then
            local e = demoEntries[index]
            if not e then
                e = DemoEntry(index, s)
                demoEntries[index] = e
            end
            if e.own then
                me = e
            end
            demoList[#demoList + 1] = e
        end
    end
    if pullBar and mod.FillPullEntry(demoPull, me, DEMO_TANK) then
        demoList[#demoList + 1] = demoPull
    end
    table.sort(demoList, mod.ByThreat)
    return demoList
end

-------------------------------------------------------------------------------
--  Options preview: its own surface in the page's content header, drawn with
--  the live meter's style and renderer. No threat reads, no saved writes.
-------------------------------------------------------------------------------
local settingsPreview
-- parent -> the dress its size hook was made for: the options page pool
-- (CludesUI_FramePool.lua) resets a kept header root before each build,
-- which drops the hook, so a new dress (Pool.Gen) hooks again; a plain frame
-- (no Gen) is hooked once.
local hookedParents = setmetatable({}, { __mode = "k" })

local function RefreshPreview(self)
    local hostFrame = self:GetParent()
    if not hostFrame then
        return
    end
    local dm = Style()
    local entries = DemoList()
    local num = #entries
    local width = ClampW(Get("width"))
    local height = 2 * dm.inset + dm.headerHeight + num * dm.barHeight + math.max(0, num - 1) * dm.barSpacing
    self:SetSize(width, height)
    local pw = hostFrame:GetWidth()
    local available = (pw > 0 and pw) or self.availableWidth or width + 40
    self:SetScale(math.min(1, math.max(100, available - 40) / width))
    self:ClearAllPoints()
    self:SetPoint("CENTER", hostFrame, "CENTER", 0, 0)
    ApplyChrome(dm, self)
    RenderRows(self, entries, 0, num, dm, entries[1].raw)
    self.previewHeight = height * self:GetScale() + 30
    if self.onHeightChanged then
        self.onHeightChanged(self.previewHeight)
    end
end

local function RefreshSettingsPreview()
    if settingsPreview and settingsPreview:IsVisible() then
        RefreshPreview(settingsPreview)
    end
end

function mod.CreateSettingsPreview(hostFrame, availableWidth, onHeightChanged)
    local view = settingsPreview
    if not view then
        view = CreateSurface(hostFrame)
        settingsPreview = view
        view.title:SetFormattedText(CludesUI.L("Threat - %s"), CludesUI.L("Training Dummy"))
        view.Refresh = RefreshPreview
        view:SetScript("OnShow", RefreshPreview)
    end
    -- Frames outlive a page rebuild, so the surface is reused.
    view.availableWidth, view.onHeightChanged = availableWidth, onHeightChanged
    view:SetParent(hostFrame)
    local dress = POOL.Gen and POOL.Gen(hostFrame) or true
    if hookedParents[hostFrame] ~= dress then
        hookedParents[hostFrame] = dress
        local lastWidth
        hostFrame:HookScript("OnSizeChanged", function(_, width)
            if width == lastWidth then
                return
            end
            lastWidth = width
            if settingsPreview:GetParent() == hostFrame and settingsPreview:IsVisible() then
                RefreshPreview(settingsPreview)
            end
        end)
    end
    RefreshPreview(view)
    view:Show()
    return view
end

-------------------------------------------------------------------------------
--  Live meter
-------------------------------------------------------------------------------
local widget, events, pendingUpdate, followTicker, previewUntil
local chrome -- the window's lock / grip / drag handle (AttachChrome)
local mobUnit -- the mob token the last pass resolved, nil when none
local threatOn -- the two threat events are registered
local flagsUnit -- the tracked unit UNIT_FLAGS is registered for
local shownList -- the list on screen (the mouse wheel repaints it)
local titleStamp -- the mob GUID (or the preview) the title shows
local warned, warnedMob
local offset = 0 -- rows scrolled past
local DEMO_STAMP, EMPTY_STAMP, EMPTY = {}, {}, {}
local visState = {}

-- A tank does not want to be warned about holding aggro: tank role, or, while nobody
-- in the group has that role, Bear or Dire Bear Form or Defensive Stance.
local function PlayerIsTank()
    if UnitGroupRolesAssigned("player") == "TANK" then
        return true
    end
    if CUI.GroupHasTankRole() then
        return false
    end
    return CUI.ForeverTankForm()
end

-- Plays once when your pull percent reaches the threshold on a mob; re-arms
-- when it drops back below, and for each new mob.
local function CheckWarning(me, unitGuid)
    if not Get("warnSound") then
        warned, warnedMob = false, nil
        return
    end
    if unitGuid ~= warnedMob then
        warned, warnedMob = false, unitGuid
    end
    local over = me
        and not me.tanking
        and me.scaled >= Get("warnAt")
        and not (Get("warnSkipTank") and PlayerIsTank())
    if over and not warned then
        mod.PlaySoundKey(Get("warnSoundKey"))
    end
    warned = over and true or false
end

local function Flag(val)
    return not issecretvalue(val) and val == true
end

-- Visibility; "in combat" also counts your pet's and the watched mob's combat.
function mod.IsVisible(cfg, status)
    if cfg.visibilityMatch ~= "any" and CUI.CheckVisibilityOptions(cfg) then
        return false
    end
    local result = CUI.EvalVisibilityExtended(cfg, "visibility", status, CUI.VIS_CAPS_DEFAULT)
    if result ~= nil then
        return result == true
    end
    if cfg.visibility == "in_combat" then
        return status.inCombat
    end
    if cfg.visibility == "out_of_combat" then
        return not status.inCombat
    end
    return CUI.EvalVisibility(cfg) == true
end

-- mob is nil for the empty header (Only With Threat off).
local function Visible(mob)
    local status = visState
    status.inCombat = InCombatLockdown()
        or (Get("pets") and Flag(UnitAffectingCombat("pet")))
        or (mob ~= nil and Flag(UnitAffectingCombat(mob)))
    status.inRaid = IsInRaid()
    status.inParty = not status.inRaid and GetNumSubgroupMembers() > 0
    return mod.IsVisible(Read(), status)
end

-- The two threat events fire for every unit in every fight nearby, so they are
-- registered only while a mob resolves. Every way a mob can start resolving
-- (target, focus, their target, attackable flags) stays registered with the
-- meter on, and a resolved mob keeps them while the meter hides empty, so the
-- threat that fills it is always received.
local function SetThreatEvents(on)
    if on == threatOn then
        return
    end
    threatOn = on
    if on then
        events:RegisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    else
        events:UnregisterEvent("UNIT_THREAT_LIST_UPDATE")
        events:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
    end
end

-- No threat event names a derived token (targettarget), so while the meter
-- follows what a friendly unit is fighting and that mob has no nameplate or
-- boss token, nothing reports its threat moving. Re-read on a short interval
-- in that one case, and only in combat.
local function SetFollow(on)
    if on then
        if not followTicker then
            followTicker = C_Timer.NewTicker(FOLLOW_INTERVAL, RequestUpdate)
        end
    elseif followTicker then
        followTicker:Cancel()
        followTicker = nil
    end
end

local function Paint(entries, dm)
    local step = dm.barHeight + dm.barSpacing
    local area = widget:GetHeight() - 2 * dm.inset - dm.headerHeight
    local slack = 2 * CUI.PP.perfect / widget:GetEffectiveScale()
    local capacity = math.floor((area + dm.barSpacing + slack) / step)
    if capacity < 1 then
        capacity = 1
    end
    local num = #entries
    local maxOffset = num - capacity
    if maxOffset < 0 then
        maxOffset = 0
    end
    if offset > maxOffset then
        offset = maxOffset
    end
    local total = num - offset
    if total > capacity then
        total = capacity
    end
    RenderRows(widget, entries, offset, total, dm, num > 0 and entries[1].raw or 0)
end

local function Show(entries, dm, stamp, mob)
    ApplyChrome(dm, widget)
    if stamp == nil or stamp ~= titleStamp then
        if stamp ~= nil then
            offset = 0
        end
        titleStamp = stamp
        if mob then
            widget.title:SetFormattedText(CludesUI.L("Threat - %s"), CUI.WithSurname(UnitName(mob)))
        else
            widget.title:SetText(CludesUI.L("Threat Meter"))
        end
    end
    shownList = entries
    Paint(entries, dm)
    widget:Show()
end

local function Empty()
    warned, warnedMob = false, nil
    shownList = nil
    widget:Hide()
end

-- Only With Threat off: the header over an empty bar area, titled with the
-- mob when one resolves (stamp: its GUID, EMPTY_STAMP without a mob).
local function ShowEmpty(dm, stamp, mob)
    warned, warnedMob = false, nil
    Show(EMPTY, dm, stamp, mob)
end

Repaint = function()
    if shownList and widget and widget:IsShown() then
        Paint(shownList, Style())
    end
end

local function Update()
    pendingUpdate = false
    if not (widget and events) then
        return
    end
    if not Get("enabled") then
        SetFollow(false)
        Empty()
        return
    end
    local dm = Style()
    local tracked = TrackedUnit()
    if tracked ~= flagsUnit then
        events:RegisterUnitEvent("UNIT_FLAGS", "pet", tracked)
        flagsUnit = tracked
    end
    if previewUntil and GetTime() >= previewUntil then
        previewUntil = nil
    end
    -- Preview rows while previewing or while unlock mode is open. Combat lifts
    -- unlock mode and real rows show there; it comes back a moment after
    -- combat with no edge of its own, so the open session out of combat is the
    -- test (the combat-end pass already sees it).
    if previewUntil or (CUI:IsUnlockModeActive() and not InCombatLockdown()) then
        mobUnit = nil
        SetThreatEvents(false)
        SetFollow(false)
        warned, warnedMob = false, nil
        Show(DemoList(), dm, DEMO_STAMP, nil)
        return
    end
    local mob = mod.ResolveSource(tracked)
    mobUnit = mob
    SetThreatEvents(mob ~= nil)
    -- Only With Threat (the default) hides the meter while nothing is listed;
    -- with it off the header stays up whenever the visibility settings allow.
    local keep = Get("onlyWithThreat") == false
    if not (mob or keep) or not Visible(mob) then
        SetFollow(false)
        Empty()
        return
    end
    if not mob then
        SetFollow(false)
        ShowEmpty(dm, EMPTY_STAMP, nil)
        return
    end
    SetFollow(mob ~= tracked and InCombatLockdown())
    local me, tankRaw = mod.Collect(mob, Get("pets"))
    local entries = mod.list
    if #entries == 0 and not keep then
        Empty()
        return
    end
    local unitGuid = UnitGUID(mob)
    if issecretvalue(unitGuid) then
        unitGuid = nil
    end
    if #entries == 0 then
        ShowEmpty(dm, unitGuid, mob)
        return
    end
    CheckWarning(me, unitGuid)
    if Get("pullBar") then
        mod.AddPullEntry(me, tankRaw)
    end
    mod.Sort()
    Show(entries, dm, unitGuid, mob)
end

-- Threat updates arrive per unit, so a raid pull is a burst; one redraw per
-- short window covers the whole burst.
RequestUpdate = function()
    if pendingUpdate then
        return
    end
    pendingUpdate = true
    C_Timer.After(UPDATE_DELAY, Update)
end

-- Resets run before the pending check so a burst never swallows them. Then each
-- unit event is probed: a threat-list change counts only for the mob shown (a
-- secret comparison counts as a match), a threat-situation or pet change only
-- for a unit the meter lists, a target or flags change only for the tracked
-- unit (or the pet). Combat, zone and roster edges also reach the meter through
-- the shared visibility dispatcher.
local function OnEvent(_, evt, unitToken)
    if evt == "GROUP_ROSTER_UPDATE" then
        mod.RosterChanged()
    elseif evt == "PLAYER_TARGET_CHANGED" or evt == "PLAYER_FOCUS_CHANGED" then
        if (evt == "PLAYER_FOCUS_CHANGED") ~= (TrackedUnit() == "focus") then
            return
        end
        offset = 0
        warned, warnedMob = false, nil
    end
    if pendingUpdate then
        return
    end
    if evt == "UNIT_THREAT_LIST_UPDATE" then
        local mob = mobUnit
        if not mob then
            return
        end
        if unitToken ~= mob then
            local same = UnitIsUnit(unitToken, mob)
            if not issecretvalue(same) and not same then
                return
            end
        end
    elseif evt == "UNIT_THREAT_SITUATION_UPDATE" then
        if not (mod.MEMBER_UNITS[unitToken] or (mod.PET_UNITS[unitToken] and Get("pets"))) then
            return
        end
    elseif evt == "UNIT_PET" then
        if not (mod.MEMBER_UNITS[unitToken] and Get("pets")) then
            return
        end
    elseif evt == "UNIT_TARGET" or evt == "UNIT_FLAGS" then
        if unitToken == "pet" then
            if not Get("pets") then
                return
            end
        elseif unitToken ~= TrackedUnit() then
            return
        end
    end
    RequestUpdate()
end

-- The grip owns the anchor while it is held.
local function SetSavedPoint()
    if chrome and chrome.resizing then
        return
    end
    local p = Get("position")
    widget:ClearAllPoints()
    if type(p) == "table" and p.point then
        widget:SetPoint(p.point, UIParent, p.relPoint or p.point, p.x or 0, p.y or 0)
    elseif type(p) == "table" and p.x and p.y then
        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.x, p.y)
    else
        p = DEFAULTS.position
        widget:SetPoint(p.point, UIParent, p.relPoint, p.x, p.y)
    end
end

-- The saved spot, then the unlock-mode anchor when the meter has one.
local function Position()
    if chrome and chrome.resizing then
        return
    end
    SetSavedPoint()
    CUI.ReapplyOwnAnchor(UNLOCK_KEY)
end

-- A resize keeps the top-left corner. A saved point-format spot (unlock
-- mode's, or the default) is rewritten as that corner first: a size change
-- re-applies a saved centre, which would pull the window back mid-drag.
local function PinPosition(leftX, topY)
    local p = Get("position")
    if leftX and topY and type(p) == "table" and p.point then
        Cfg().position = { x = leftX, y = topY }
    end
end

-- A header drag: the corner is the saved spot, and it replaces any unlock-mode
-- anchor on the meter (elements anchored to the meter follow it).
local function SaveMove(leftX, topY)
    Cfg().position = { x = leftX, y = topY }
    local anchors = CludesUIDB and CludesUIDB.unlockAnchors
    if anchors then
        anchors[UNLOCK_KEY] = nil
    end
    CUI.ScheduleSettleReapply()
end

-- Unlock mode owns the position while it is open (a first build still places
-- the frame, so its mover has a spot to start from).
local function ApplyGeometry(firstBuild)
    if chrome and chrome.resizing then
        return
    end
    widget:SetSize(ClampW(Get("width")), ClampH(Get("height")))
    if firstBuild or not CUI._unlockActive then
        Position()
    end
end

function mod.Apply()
    cachedStyle = nil
    if Get("enabled") then
        if not widget then
            CreateWindow()
        end
        if not events then
            events = CreateFrame("Frame")
            events:SetScript("OnEvent", OnEvent)
        end
        events:RegisterEvent("PLAYER_TARGET_CHANGED")
        events:RegisterEvent("PLAYER_FOCUS_CHANGED")
        events:RegisterEvent("GROUP_ROSTER_UPDATE")
        events:RegisterEvent("UNIT_PET")
        events:RegisterUnitEvent("UNIT_TARGET", "target", "focus")
        flagsUnit = nil
        -- The roster memos missed every change made while the meter was off.
        mod.RosterChanged()
        CUI.UnregisterVisibilityUpdater(RequestUpdate)
        CUI.RegisterVisibilityUpdater(RequestUpdate)
        -- A reset may have cleared the lock.
        chrome.SyncLock()
        ApplyGeometry()
        RequestUpdate()
    else
        if events then
            events:UnregisterAllEvents()
        end
        threatOn, flagsUnit, mobUnit, previewUntil = false, nil, nil, nil
        CUI.UnregisterVisibilityUpdater(RequestUpdate)
        SetFollow(false)
        warned, warnedMob = false, nil
        shownList = nil
        if widget then
            widget:Hide()
        end
    end
    -- A reset also reaches a Damage Meters Threat window (ThreatFeed file).
    mod.FeedChanged()
    RefreshSettingsPreview()
end

function mod.ApplyStyle()
    cachedStyle = nil
    if widget and Get("enabled") then
        RequestUpdate()
    end
    mod.FeedChanged()
    RefreshSettingsPreview()
end

-- The value column is sized from a formatted sample (Style), so a Number Format
-- change restyles.
CUI.RegisterNumberFormatCallback(function()
    mod.ApplyStyle()
end)

-- Ten seconds of preview rows on the live meter.
function mod.Preview()
    if not (widget and Get("enabled")) then
        return false
    end
    previewUntil = GetTime() + PREVIEW_SECONDS
    RequestUpdate()
    C_Timer.After(PREVIEW_SECONDS, RequestUpdate)
    return true
end

-------------------------------------------------------------------------------
--  Header menus. Independent of the load-on-demand options addon, so they also
--  work in combat before the settings window has ever opened. A change
--  restyles the meter and refreshes an open settings page. They are the
--  shared context menu in the Damage Meters look (MENU_OPTS).
-------------------------------------------------------------------------------
local function OpenSettings()
    CUI:NavigateToElementSettings("CludesUIForeverEssentials", "Threat")
end

local function Changed()
    mod.ApplyStyle()
    CUI:RefreshPage()
end

local function SetSource(unitToken)
    Cfg().source = unitToken
    offset = 0
    Changed()
end

local function SourceItems()
    local tracked = TrackedUnit()
    return {
        {
            text = CludesUI.L("Target"),
            isActive = tracked == "target",
            onClick = function()
                SetSource("target")
            end,
        },
        {
            text = CludesUI.L("Focus"),
            isActive = tracked == "focus",
            onClick = function()
                SetSource("focus")
            end,
        },
    }
end

-- The menu's Width and Height boxes keep the top-left corner, as the grip does.
local function ResizeTo(width, height, key)
    local leftX, topY = mod.WindowCorner(widget)
    PinPosition(leftX, topY)
    widget:SetSize(width, height)
    if leftX then
        widget:ClearAllPoints()
        widget:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", leftX, topY)
    end
    local dim = key == "width" and widget:GetWidth() or widget:GetHeight()
    Cfg()[key] = math.floor(dim + 0.5)
end

-- What the list shows (tracked unit, displayed value, pets), appended to
-- `items`. Also the head of a Damage Meters Threat window's settings menu.
local function DataItems(itemList)
    if Get("focusEnabled") then
        itemList[#itemList + 1] = { text = CludesUI.L("Tracked Unit"), children = SourceItems() }
    end
    local isShown, values = mod.GetDisplayedValue(), {}
    for _, key in ipairs(mod.DisplayOrder) do
        local value = key
        values[#values + 1] = {
            text = CludesUI.L(mod.DisplayValues[value]),
            isActive = isShown == value,
            onClick = function()
                mod.SetDisplayedValue(value)
                Changed()
            end,
        }
    end
    itemList[#itemList + 1] = { text = CludesUI.L("Displayed Value"), children = values }
    -- The options page's label: checked while pets are left out.
    itemList[#itemList + 1] = {
        text = CludesUI.L("Ignore Pets"),
        isActive = not Get("pets"),
        onClick = function()
            Cfg().pets = not Get("pets")
            Changed()
        end,
    }
    return itemList
end
mod.DataMenuItems = DataItems

local function ShowQuickMenu(anchorFrame)
    local itemList = DataItems({})
    itemList[#itemList + 1] = {
        text = CludesUI.L("Warning Sound"),
        isActive = Get("warnSound") == true,
        onClick = function()
            Cfg().warnSound = not Get("warnSound")
            Changed()
        end,
    }
    itemList[#itemList + 1] = "---"
    itemList[#itemList + 1] = {
        text = CludesUI.L("Width"),
        isInput = true,
        min = MIN_W,
        getValue = function()
            return math.floor(widget:GetWidth() + 0.5)
        end,
        setValue = function(val)
            ResizeTo(math.max(MIN_W, val), widget:GetHeight(), "width")
        end,
    }
    itemList[#itemList + 1] = {
        text = CludesUI.L("Height"),
        isInput = true,
        min = MIN_H,
        getValue = function()
            return math.floor(widget:GetHeight() + 0.5)
        end,
        setValue = function(val)
            ResizeTo(widget:GetWidth(), math.max(MIN_H, val), "height")
        end,
    }
    local snapOff = Get("snapDisabled") == true
    itemList[#itemList + 1] = {
        text = snapOff and CludesUI.L("Enable Snapping") or CludesUI.L("Disable Snapping"),
        onClick = function()
            Cfg().snapDisabled = (not snapOff) or nil
        end,
    }
    itemList[#itemList + 1] =
        { text = CludesUI.L("Settings"), isDisabled = InCombatLockdown, onClick = OpenSettings }
    CUI.ShowContextMenu(anchorFrame, itemList, MENU_OPTS)
end

local function ShowSourceMenu(anchorFrame)
    CUI.ShowContextMenu(anchorFrame, SourceItems(), MENU_OPTS)
end

-------------------------------------------------------------------------------
--  Window: the Damage Meters window's controls (Window file): header drag,
--  corner grip, lock icon, snapping. The mouse wheel scrolls rows; a height
--  change repaints them for the rows that now fit.
-------------------------------------------------------------------------------
CreateWindow = function()
    widget = CreateSurface(UIParent, "CludesUIThreatMeterFrame", true)
    mod.frame = widget
    widget.unlockKey = UNLOCK_KEY
    widget:Hide()
    widget:SetFrameStrata("MEDIUM")
    widget:SetClampedToScreen(true)
    widget:SetMovable(true)
    -- Motion only (the hover fade): clicks on the bar area reach the world.
    widget:EnableMouseMotion(true)
    widget.settingsBtn.onClick = ShowQuickMenu
    widget.sourceBtn.onClick = ShowSourceMenu
    chrome = mod.AttachChrome(widget, {
        IsLocked = function()
            return Get("locked") == true
        end,
        SetLocked = function(locked)
            Cfg().locked = locked or nil
        end,
        SnapDisabled = function()
            return Get("snapDisabled") == true
        end,
        CanMove = function()
            return not CUI._unlockActive
        end,
        PinPosition = PinPosition,
        SaveMove = SaveMove,
        SaveSize = function(width, height)
            local cfg = Cfg()
            cfg.width, cfg.height = width, height
        end,
    })
    widget:EnableMouseWheel(true)
    widget:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, offset - delta * 2)
        Repaint()
    end)
    local lastHeight
    widget:HookScript("OnSizeChanged", function(_, _, height)
        if height == lastHeight then
            return
        end
        lastHeight = height
        Repaint()
    end)
    -- An accent change repaints the title and accent-coloured bars.
    CUI.RegAccent({
        type = "callback",
        fn = function()
            if widget:IsShown() then
                RequestUpdate()
            end
            RefreshSettingsPreview()
        end,
    })
    ApplyGeometry(true)
end

-------------------------------------------------------------------------------
--  Unlock mode. Registered at login whatever the enable state (an element
--  anchored to the meter keeps its link while the meter is off); nothing is
--  built while the meter is off, and the size reads the settings until it is.
--  A size set outside unlock mode (a width or height match) is not saved.
-------------------------------------------------------------------------------
local function SetUnlockSize(key, val, low)
    if not widget then
        return
    end
    val = CUI.PP.Snap(math.max(low, val or low))
    if key == "width" then
        widget:SetWidth(val)
    else
        widget:SetHeight(val)
    end
    if CUI._unlockActive then
        Cfg()[key] = math.floor(val + 0.5)
    end
end

-- How far a textured window border reaches past the window, so size matching
-- lines up with what is on screen. nil for a solid border or a stock look.
local function WindowBorderPad()
    if Look.stock then
        return nil
    end
    local dim = mod.GetStyleValue("borders", "windowBorderSize") or 0
    local texture = mod.GetStyleValue("borders", "windowBorderTexture") or "solid"
    if dim <= 0 or texture == "solid" then
        return nil
    end
    local color = mod.GetStyleValue("borders", "windowBorderColor")
    local l, region, t, b = CUI.BorderReach(
        dim,
        texture,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        CUI.BorderPx(mod.GetStyleValue("borders", "windowBorderSizePx"), dim, texture),
        nil,
        color and color.a or 1
    )
    if not l then
        return nil
    end
    if mod.GetStyleValue("borders", "windowBorderIncludeHeader") == false and Get("showHeader") then
        t = t - mod.GetStyleValue("header", "hdrHeight")
    end
    local pw = (l > 0 and l or 0) + (region > 0 and region or 0)
    local ph = (t > 0 and t or 0) + (b > 0 and b or 0)
    if pw <= 0 and ph <= 0 then
        return nil
    end
    return pw, ph
end

local function RegisterUnlock()
    CUI:RegisterUnlockElements({
        CUI.MakeUnlockElement({
            key = UNLOCK_KEY,
            label = "Threat Meter",
            group = "Forever Tools",
            order = 731,
            isHidden = function()
                return not Get("enabled")
            end,
            getFrame = function()
                if not Get("enabled") then
                    return nil
                end
                if not widget then
                    CreateWindow()
                end
                return widget
            end,
            getSize = function()
                if widget then
                    return widget:GetSize()
                end
                return ClampW(Get("width")), ClampH(Get("height"))
            end,
            getMatchPad = WindowBorderPad,
            setWidth = function(_, wid)
                SetUnlockSize("width", wid, MIN_W)
            end,
            setHeight = function(_, hgt)
                SetUnlockSize("height", hgt, MIN_H)
            end,
            savePos = function(_, anchorPoint, relPoint, posX, posY)
                if not anchorPoint then
                    return
                end
                Cfg().position =
                    { point = anchorPoint, relPoint = relPoint or anchorPoint, x = posX, y = posY }
                if widget and not CUI._unlockActive then
                    SetSavedPoint()
                end
            end,
            -- A copy; a dragged corner reads as TOPLEFT of the screen's
            -- BOTTOMLEFT (never re-applied on a size change, unlike a centre).
            loadPos = function()
                local p = Get("position")
                if type(p) ~= "table" then
                    return nil
                end
                if p.point then
                    return { point = p.point, relPoint = p.relPoint or p.point, x = p.x or 0, y = p.y or 0 }
                end
                if p.x and p.y then
                    return { point = "TOPLEFT", relPoint = "BOTTOMLEFT", x = p.x, y = p.y }
                end
            end,
            clearPos = function()
                local c = Read()
                if c ~= _NOCFG then
                    c.position, c.pos = nil, nil
                end
                if widget then
                    SetSavedPoint()
                end
            end,
            applyPos = function()
                if not Get("enabled") then
                    return
                end
                if not widget then
                    CreateWindow()
                end
                SetSavedPoint()
            end,
        }),
    }, ADDON_NAME)
    -- The border was painted before the element existed: record its reach.
    CUI.MatchPadChanged(UNLOCK_KEY)
end

-- Opening or closing unlock mode swaps between preview and real rows.
local function OnUnlockModeChanged()
    if widget and Get("enabled") then
        RequestUpdate()
    end
end

-- Options-page and reset entry points.
CUI._ThreatMeter = {
    Get = Get,
    Cfg = Cfg,
    Read = Read,
    Apply = mod.Apply,
    ApplyStyle = mod.ApplyStyle,
    ApplyPosition = function()
        if widget then
            Position()
        end
    end,
    Preview = mod.Preview,
    Sounds = mod.Sounds,
}

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function(self)
    self:UnregisterAllEvents()
    if module.TM_Style() == "classic" then
        module.TM_SeedStock(Cfg(), "classic")
    end
    EnsureLook()
    mod.Apply()
    RegisterUnlock()
    CUI:RegisterUnlockModeListener(UNLOCK_KEY, OnUnlockModeChanged)
end)

-------------------------------------------------------------------------------
--  /cuitm
-------------------------------------------------------------------------------
-- Chat feedback; nothing prints in combat.
local function Say(message)
    if InCombatLockdown() then
        return
    end
    CUI.Print(CUI.COLOR_CODES.BRAND .. "CludesUI:|r " .. message)
end

SLASH_CLUDESUITHREAT1 = "/cuitm"
SlashCmdList.CLUDESUITHREAT = function(input)
    local cmd = (input or ""):lower():match("^%s*(.-)%s*$")
    if cmd == "test" then
        if not mod.Preview() then
            Say(CludesUI.L("Enable the threat meter first."))
        end
    elseif cmd == "target" or cmd == "focus" then
        Cfg().source = Get("focusEnabled") and cmd or "target"
        offset = 0
        mod.ApplyStyle()
        CUI:RefreshPage()
    elseif cmd == "show" or cmd == "hide" then
        Cfg().enabled = cmd == "show"
        mod.Apply()
        CUI:RefreshPage()
    elseif cmd == "pets" then
        local pets = not Get("pets")
        Cfg().pets = pets
        mod.ApplyStyle()
        CUI:RefreshPage()
        Say(pets and CludesUI.L("Pets shown") or CludesUI.L("Pets hidden"))
    elseif cmd == "reset" then
        -- The older keys too: a saved bar count would otherwise size the window.
        local c = Read()
        if c ~= _NOCFG then
            c.position, c.pos, c.width, c.height, c.maxBars = nil, nil, nil, nil, nil
        end
        mod.Apply()
    else
        Say("/cuitm test, target, focus, show, hide, pets, reset")
    end
end
