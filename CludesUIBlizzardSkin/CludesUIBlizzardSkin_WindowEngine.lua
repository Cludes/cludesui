if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUIBlizzardSkin_WindowEngine.lua
--  Shared engine for the Blizzard Window Skins system: style-aware window
--  shells (CludesUI atlas style vs Modern flat color), the primitive
--  skinners every window pack builds from, and per-window boot orchestration
--  for load-on-demand Blizzard addons.
--
--  Style model (per window, chosen on the Blizzard Window Skins options page):
--    "cui"    -> the dungeons-and-raids shell: modern_blizz atlas backdrop
--                (cover-fit) + black overlay, full opacity.
--    "modern" -> identical skin, but the shell backdrop is a flat user-set
--                color + opacity (one global Modern color, applied live).
--    "off"    -> the window pack never runs (reload-gated).
--  CUI vs Modern differ ONLY in the shell backdrop; every other element
--  (buttons, tabs, borders, insets) is identical. cui<->modern applies LIVE
--  via RefreshStyles(); only off<->on needs a reload.
--
--  Safety rules (hard requirements, see CLAUDE.md):
--   - Per-frame state lives in a weak-keyed EXTERNAL table (FFD); we never
--     write custom keys onto Blizzard frames.
--   - Visual-only: SetAlpha(0) on textures. Never Hide/Show/SetParent a
--     Blizzard frame, never EnableMouse walks, never SetScript on Blizzard
--     frames (HookScript/hooksecurefunc only).
--   - No reads of protected/secret data anywhere in the skin path.
--   - Each window pack is pcall-isolated: one window breaking can never stop
--     the others from skinning.
--   - Zero cost when a window is off: hooks install only for enabled windows.
-------------------------------------------------------------------------------
local ADDON_NAME, mod = ...
local CUI = CludesUI
local issecretvalue = issecretvalue or function()
    return false
end

local Skin = {}
mod.WSkin = Skin

-- Weak-keyed external state (prevents tainting Blizzard frames) ---------------
local FFD, GetFFD = CludesUI.NewFrameData()
Skin.GetFFD = GetFFD
Skin.FFD = FFD

-- Completion is separate from reentrancy: a failed setup can retry, while
-- a synchronous hook cannot enter the same control's unfinished setup.
local setupInProgress = setmetatable({}, { __mode = "k" })
function Skin.CompleteSetup(widget, key, applyFn, ...)
    local skinData = GetFFD(widget)
    if skinData[key] or setupInProgress[widget] then
        return
    end
    setupInProgress[widget] = true
    local success, err = pcall(applyFn, widget, skinData, ...)
    setupInProgress[widget] = nil
    if not success then
        error(err, 0)
    end
    skinData[key] = true
end

-------------------------------------------------------------------------------
--  Theme tokens. Matches the dungeons-and-raids reskin so every window reads
--  as one family. Accent tracks the user's live accent color.
-------------------------------------------------------------------------------
local Theme = {}
Skin.Theme = Theme
local function ResolveTheme()
    local ACC = (CUI and CUI.CLUDES_GREEN) or { r = 0.298, g = 0.788, b = 0.941 }
    Theme.accR, Theme.accG, Theme.accB = ACC.r or 0.298, ACC.g or 0.788, ACC.b or 0.941
    -- Neutral dark grays (no color cast): panel/button/dropdown fill and the
    -- darker nested-inset variant.
    Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA = 0.08, 0.08, 0.08, 0.92
    Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA = 0.04, 0.04, 0.04, 0.85
    Theme.brdR, Theme.brdG, Theme.brdB, Theme.brdA = 0.2, 0.2, 0.2, 1
    Theme.fontPath = (CUI.GetFontPath("blizzardSkin")) or STANDARD_TEXT_FONT
    Theme.fontFlag = (CUI.GetFontOutlineFlag("blizzardSkin")) or ""
    -- Drop shadow only in no-outline mode, honoring the user's shadow toggle.
    Theme.fontShadow = (Theme.fontFlag == "")
        and (not (CUI and CUI.GetFontUseShadow) or CUI.GetFontUseShadow("blizzardSkin"))
end
Skin.ResolveTheme = ResolveTheme

local function SolidTex(hostFrame, layer, red, green, blue, a, sublevel)
    local tex = hostFrame:CreateTexture(nil, layer, nil, sublevel)
    tex:SetColorTexture(red, green, blue, a)
    return tex
end
Skin.SolidTex = SolidTex

local function AddBorder(widget, red, green, blue, a, layer, sublevel)
    if GetFFD(widget).border then
        return
    end
    local Pix = CUI and (CUI.PanelPP or CUI.PP)
    if Pix and Pix.CreateBorder then
        -- BORDER/-7 strips with the container demoted to the skinned frame's own
        -- level: at equal frame levels regions interleave by draw layer, so text
        -- and content on the frame render above the border (at the default +1
        -- container level, frame level beats every layer and the border covers
        -- bar text -- XP/reputation bar labels). Demotion is window-engine-only
        -- on purpose: every other CreateBorder consumer keeps the +1 contract.
        -- layer/sublevel put the strips lower still, for a frame sitting at its
        -- parent's level under art the parent draws (flag carrier panels).
        local c = Pix.CreateBorder(
            widget,
            red or Theme.brdR,
            green or Theme.brdG,
            blue or Theme.brdB,
            a or Theme.brdA,
            1,
            layer or "BORDER",
            sublevel or -7
        )
        if c and c.SetFrameLevel then
            c:SetFrameLevel(widget:GetFrameLevel())
        end
        GetFFD(widget).border = true
    end
end
Skin.AddBorder = AddBorder

-------------------------------------------------------------------------------
--  Modern style storage. The enable booleans + style names live in the options
--  system; the engine only resolves the ONE global Modern backdrop color
--  (default #111111 at 97% opacity).
-------------------------------------------------------------------------------
local MODERN_FALLBACK = { r = 0.067, g = 0.067, b = 0.067, a = 0.97 }
function Skin.GetModernBG()
    local saved = CludesUIDB
    local color = saved and saved.blizzWindowModernDefault
    if not (color and color.r) then
        color = MODERN_FALLBACK
    end
    return color.r or MODERN_FALLBACK.r,
        color.g or MODERN_FALLBACK.g,
        color.b or MODERN_FALLBACK.b,
        color.a or MODERN_FALLBACK.a
end

function Skin.GetStyle(winKey)
    if CUI and CUI.GetBlizzWindowStyle then
        return CUI.GetBlizzWindowStyle(winKey)
    end
    return "cui"
end

-------------------------------------------------------------------------------
--  FadeRegions: alpha-out every direct texture region on a frame (+ NineSlice).
--  `keep` is a set of texture objects to leave alone. Visual-only, no Hide().
-------------------------------------------------------------------------------
-- Walks GetRegions' returns directly: every global Restrip (each loot open,
-- mail and calendar updates) runs this for every registered frame, so it must
-- not allocate.
local function FadeTextures(keep, ...)
    for idx = 1, select("#", ...) do
        local region = (select(idx, ...))
        if region and region.IsObjectType and region:IsObjectType("Texture") and not (keep and keep[region]) then
            region:SetAlpha(0)
        end
    end
end
local function FadeRegions(widget, keep)
    if not widget or widget:IsForbidden() then
        return
    end
    FadeTextures(keep, widget:GetRegions())
    if widget.NineSlice then
        FadeRegions(widget.NineSlice, keep)
    end
end
Skin.FadeRegions = FadeRegions

-- NineSlice pieces get re-shown/re-laid-out by Blizzard on some updates; alpha
-- each named piece as well as the container so a relayout cannot resurrect it.
local NINESLICE_PIECES = {
    "TopLeftCorner",
    "TopRightCorner",
    "BottomLeftCorner",
    "BottomRightCorner",
    "TopEdge",
    "BottomEdge",
    "LeftEdge",
    "RightEdge",
    "Center",
}
local function FadeNineSlice(nsl)
    if not nsl then
        return
    end
    FadeRegions(nsl)
    for _, keyName in ipairs(NINESLICE_PIECES) do
        local p = nsl[keyName]
        if p and p.SetAlpha then
            p:SetAlpha(0)
        end
    end
    if nsl.SetAlpha then
        nsl:SetAlpha(0)
    end
end
Skin.FadeNineSlice = FadeNineSlice

-------------------------------------------------------------------------------
--  Restrip registry: frames Blizzard repaints get re-faded on demand. Every
--  texture the engine itself created is protected via the frame's FFD entry.
-------------------------------------------------------------------------------
local _restrip = {}
local _windowRestrips = {}
local registrationWindow

-- Attribute registrations to a window while running its setup or a late
-- control callback. Restore the previous owner even when a callback fails.
function Skin.WindowCallback(winKey, func)
    return function(...)
        if Skin.GetStyle(winKey) == "off" then
            return
        end
        local previous = registrationWindow
        registrationWindow = winKey
        local success, err = pcall(func, ...)
        registrationWindow = previous
        if not success then
            error(err, 0)
        end
    end
end

local function Register(widget, keep)
    if not widget then
        return
    end
    _restrip[widget] = keep or true
    if registrationWindow then
        local frameList = _windowRestrips[registrationWindow]
        if not frameList then
            frameList = {}
            _windowRestrips[registrationWindow] = frameList
        end
        frameList[widget] = true
    end
end
Skin.Register = Register

local PROTECT_KEYS = {
    "bg",
    "bgOverlay",
    "modernBg",
    "hover",
    "selBar",
    "rightShade",
    "fill",
    "x",
    "topBar",
    "bottomBar",
    "arrow",
    "caret",
}
local function Restrip(winKey)
    local frameList = winKey and _windowRestrips[winKey] or _restrip
    if winKey and not _windowRestrips[winKey] then
        return
    end
    for widget in pairs(frameList) do
        local keep = _restrip[widget]
        if widget and not widget:IsForbidden() then
            local keyName = (type(keep) == "table") and keep or nil
            local skinData = FFD[widget]
            if skinData then
                keyName = keyName or {}
                for _, key in ipairs(PROTECT_KEYS) do
                    if skinData[key] then
                        keyName[skinData[key]] = true
                    end
                end
            end
            FadeRegions(widget, keyName)
        end
    end
end
Skin.Restrip = Restrip

-------------------------------------------------------------------------------
--  Style-aware window shell. Creates BOTH backdrop variants on the frame and
--  shows the one matching the window's current style:
--    cui    -> modern_blizz atlas (cover-fit) + black 0.62 overlay
--    modern -> flat user color + opacity
--  All shells register here so RefreshStyles() can live-swap and recolor.
-------------------------------------------------------------------------------
local _shells = {} -- winKey -> { frame = f } (strong: permanent frames)

local BG_ASPECT = 561 / 433
local BASE_L, BASE_R, BASE_T, BASE_B = 0.25, 1, 0, 0.75
local BASE_U, BASE_V = BASE_R - BASE_L, BASE_B - BASE_T

local function ApplyShellStyle(winKey)
    local record = _shells[winKey]
    if not record then
        return
    end
    -- a window's own background color/opacity: the backdrop fades with the
    -- opacity, the tint takes the color (CUI._ShellLooks[winKey] returns both)
    local look = CUI and CUI._ShellLooks and CUI._ShellLooks[winKey]
    local tint, opacity
    if look then
        tint, opacity = look()
    end
    opacity = (opacity or 100) / 100
    for widget in pairs(record) do
        local skinData = FFD[widget]
        if skinData then
            local style = Skin.GetStyle(winKey)
            if style == "modern" then
                if skinData.bg then
                    skinData.bg:SetAlpha(0)
                end
                if skinData.bgOverlay then
                    skinData.bgOverlay:SetAlpha(0)
                end
                if skinData.modernBg then
                    local red, green, blue, a = Skin.GetModernBG()
                    if tint then
                        red, green, blue, a = tint.r, tint.g, tint.b, tint.a or a
                    end
                    skinData.modernBg:SetColorTexture(red, green, blue, a)
                    -- Re-raise the region alpha too: a foreign restrip pass may
                    -- have zeroed it (color alpha and region alpha multiply).
                    skinData.modernBg:SetAlpha(opacity)
                end
            else
                if skinData.bg then
                    skinData.bg:SetAlpha(opacity)
                end
                -- Region alpha is show/hide only; the darken strength lives in
                -- the overlay's color alpha (they multiply).
                if skinData.bgOverlay then
                    if tint then
                        skinData.bgOverlay:SetColorTexture(tint.r, tint.g, tint.b, tint.a or 0.62)
                    end
                    skinData.bgOverlay:SetAlpha(opacity)
                end
                if skinData.modernBg then
                    skinData.modernBg:SetColorTexture(0, 0, 0, 0)
                end
            end
        end
    end
end

-- Outside painters that follow a window's style (the Friends module's own
-- window chrome) repaint on the same live refresh as the shells.
local _styleCallbacks = {}
function Skin.OnStylesChanged(func)
    _styleCallbacks[#_styleCallbacks + 1] = func
end

-- Re-resolve every registered shell (style switches + Modern color edits apply
-- live; no reload). Exposed on CludesUI so the options page can call it.
function Skin.RefreshStyles()
    for winKey in pairs(_shells) do
        ApplyShellStyle(winKey)
    end
    for _, func in ipairs(_styleCallbacks) do
        pcall(func)
    end
end
if CUI then
    CUI._WSkinRefreshStyles = Skin.RefreshStyles
end

-- Attach the style system to a frame that ALREADY has an atlas shell built.
-- Pass the shell's atlas texture + black overlay explicitly when they live in
-- another file's own state table (Character Sheet, Inspect, LFG shell).
function Skin.AdoptShell(winKey, widget, atlasTex, overlayTex)
    if not widget then
        return
    end
    local skinData = GetFFD(widget)
    if atlasTex then
        skinData.bg = atlasTex
    end
    if overlayTex then
        skinData.bgOverlay = overlayTex
    end
    if not skinData.modernBg then
        skinData.modernBg = widget:CreateTexture(nil, "BACKGROUND", nil, -6)
        skinData.modernBg:SetColorTexture(0, 0, 0, 0)
        skinData.modernBg:SetAllPoints(widget)
    end
    local record = _shells[winKey]
    if not record then
        record = {}
        _shells[winKey] = record
    end
    record[widget] = true
    ApplyShellStyle(winKey)
end

-- Cover-fit the shell backdrop into a fw x fh rect: native aspect 561x433,
-- centred crop of the overflow, never stretched. Pure, no hooks: Shell calls
-- it from its size hook; the Friends module calls it when it paints.
function Skin.CoverFit(texture, fw, fh)
    -- SECRECY TEST FIRST. `fw == 0` is itself a COMPARISON, so on a frame
    -- whose size is secret (any window sized from widget content -- the
    -- delve picker and the choice windows both are) it throws before a
    -- later issecretvalue guard could reject it:
    --   "attempt to compare local 'fw' (a secret number value)"
    if issecretvalue(fw) or issecretvalue(fh) then
        return
    end
    if not fw or fw == 0 or not fh or fh == 0 then
        return
    end
    local fa = fw / fh
    if fa > BG_ASPECT then
        local visV = BASE_V * (BG_ASPECT / fa)
        local trimV = (BASE_V - visV) / 2
        texture:SetTexCoord(BASE_L, BASE_R, BASE_T + trimV, BASE_B - trimV)
    else
        local visU = BASE_U * (fa / BG_ASPECT)
        local trimU = (BASE_U - visU) / 2
        texture:SetTexCoord(BASE_L + trimU, BASE_R - trimU, BASE_T, BASE_B)
    end
end

-- Full shell build for a window pack: fade Blizzard art, lay both backdrop
-- variants, border it, apply the current style. opts.noBorder skips the frame
-- border (for frames whose rect extends past their visible panel).
function Skin.Shell(winKey, widget, options)
    if not widget or widget:IsForbidden() then
        return
    end
    local skinData = GetFFD(widget)
    local keep = {}
    for _, key in ipairs(PROTECT_KEYS) do
        if skinData[key] then
            keep[skinData[key]] = true
        end
    end
    FadeRegions(widget, keep)
    Register(widget, true)
    if not skinData.bg then
        local backdrop = widget:CreateTexture(nil, "BACKGROUND", nil, -8)
        backdrop:SetTexture("Interface\\AddOns\\CludesUI\\media\\modern_blizz.png")
        backdrop:SetAllPoints(widget)
        skinData.bg = backdrop
        local overlayFrame = widget:CreateTexture(nil, "BACKGROUND", nil, -7)
        overlayFrame:SetColorTexture(0, 0, 0, 0.62)
        overlayFrame:SetAllPoints(widget)
        skinData.bgOverlay = overlayFrame

        -- Cover-fit: crop the atlas so it fills the frame without stretching.
        local function UpdateBgTexCoords()
            Skin.CoverFit(backdrop, widget:GetSize())
        end
        -- One script hook instead of three setter hooks: it also fires for
        -- anchor-driven resizes the setters never saw.
        widget:HookScript("OnSizeChanged", UpdateBgTexCoords)
        UpdateBgTexCoords()

        -- Black top bar behind the window title. Sits above both style backdrops
        -- (-8/-7/-6) and below all content and the border overlay. opts.noTopBar skips
        -- it for shells with no title row of their own (loot toasts and other small
        -- popups), where a 25px bar would just be a dark stripe across the top.
        if not (options and options.noTopBar) then
            local topBar = widget:CreateTexture(nil, "BACKGROUND", nil, -5)
            topBar:SetColorTexture(0, 0, 0, 0.5)
            topBar:SetPoint("TOPLEFT")
            topBar:SetPoint("TOPRIGHT")
            topBar:SetHeight(25)
            skinData.topBar = topBar
        end
        -- Matching bar along the BOTTOM, opt-in via opts.bottomBar (pass a
        -- number for a height other than the top bar's 25). For windows that
        -- carry a footer strip -- a currency row, a total, an action bar --
        -- so it reads as a deliberate band rather than content floating on
        -- the backdrop. Same layer and color as the top bar, so the two match.
        local bb = options and options.bottomBar
        if bb then
            local bottomBar = widget:CreateTexture(nil, "BACKGROUND", nil, -5)
            bottomBar:SetColorTexture(0, 0, 0, 0.5)
            bottomBar:SetPoint("BOTTOMLEFT")
            bottomBar:SetPoint("BOTTOMRIGHT")
            bottomBar:SetHeight(type(bb) == "number" and bb or 25)
            skinData.bottomBar = bottomBar
        end
    end
    if not (options and options.noBorder) then
        Skin.AtlasBorder(widget)
    end
    Skin.AdoptShell(winKey, widget)
end

-- Window border: AdventureMap_TopBorder is a complete window-frame atlas
-- (1002x668, transparent middle). It stretches to the window's size and lays
-- over the backdrop, replacing the 1px line border on shells. Falls back to
-- the 1px border if the atlas is ever missing.
local BORDER_ATLAS = "AdventureMap_TopBorder"
function Skin.AtlasBorder(widget)
    if not widget or widget:IsForbidden() then
        return
    end
    local skinData = GetFFD(widget)
    if skinData.atlasBorder then
        return
    end
    skinData.atlasBorder = true
    local details = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(BORDER_ATLAS)
    if not details then
        AddBorder(widget)
        return
    end

    local ov = CreateFrame("Frame", nil, widget)
    ov:SetAllPoints(widget)
    ov:SetFrameLevel(widget:GetFrameLevel() + 6)
    skinData.atlasBorderFrame = ov

    local texture = ov:CreateTexture(nil, "OVERLAY", nil, 7)
    texture:SetAtlas(BORDER_ATLAS)
    texture:SetAllPoints(ov)
end

-------------------------------------------------------------------------------
--  Primitive skinners. All idempotent (guarded via FFD), all visual-only.
-------------------------------------------------------------------------------

-- Flat solid panel. opts.noBg = strip only; opts.inset = darker nested fill;
-- opts.noBorder = skip border; opts.shade = translucent black content wash.
function Skin.Panel(widget, options)
    if not widget or widget:IsForbidden() then
        return
    end
    options = options or {}
    local skinData = GetFFD(widget)
    local keep = {}
    if skinData.bg then
        keep[skinData.bg] = true
    end
    FadeRegions(widget, keep)
    Register(widget, true)
    if not skinData.bg and not options.noBg then
        local red, green, blue, a = Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA
        if options.inset then
            red, green, blue, a = Theme.insetR, Theme.insetG, Theme.insetB, Theme.insetA
        end
        if options.shade then
            red, green, blue, a = 0, 0, 0, 0.25
        end
        local backdrop = widget:CreateTexture(nil, "BACKGROUND", nil, -6)
        backdrop:SetColorTexture(red, green, blue, a)
        backdrop:SetAllPoints(widget)
        skinData.bg = backdrop
    end
    if not options.noBorder then
        AddBorder(widget)
    end
end

-- Strip an InsetFrameTemplate child (Bg + rounded NineSlice box) so it blends
-- into the shell instead of showing a nested box.
function Skin.Inset(inset)
    if not inset or inset:IsForbidden() then
        return
    end
    FadeRegions(inset)
    if inset.Bg then
        inset.Bg:SetAlpha(0)
    end
    if inset.NineSlice then
        FadeNineSlice(inset.NineSlice)
    end
    Register(inset, true)
end

-- size (optional): the size to set; otherwise the string keeps its own (12 if none).
-- A string already on one of our font families keeps it (WSkin.FontFamily), so a
-- region walk never pins a name text that took a family.
function Skin.Font(fontStr, red, green, blue, size)
    if not fontStr or not fontStr.GetFont or (fontStr.IsForbidden and fontStr:IsForbidden()) then
        return
    end
    local fo = fontStr.GetFontObject and fontStr:GetFontObject()
    if fo and CUI._fontFamilySet[fo] then
        return Skin.FontFamily(fontStr, red, green, blue, size)
    end
    local _, current = fontStr:GetFont()
    if current and issecretvalue(current) then
        return
    end
    -- 12.0.7: shadows only render from a FontObject, never from instance
    -- SetShadowOffset. Prime BEFORE SetFont (SetFont then restores the face).
    CUI.PrimeFontShadow(fontStr, Theme.fontShadow)
    fontStr:SetFont(Theme.fontPath, size or current or 12, Theme.fontFlag or "")
    if red then
        fontStr:SetTextColor(red, green, blue or red)
    end
end

-- WSkin.Font for a text that shows other players' writing (names, group titles,
-- comments): the house font as a font family, which draws the scripts that font
-- lacks. A string given a family takes every later font write through here,
-- never through WSkin.Font (a plain SetFont pins the face for good).
function Skin.FontFamily(fontStr, red, green, blue, size)
    if not fontStr or not fontStr.GetFont or (fontStr.IsForbidden and fontStr:IsForbidden()) then
        return
    end
    local _, current = fontStr:GetFont()
    if current and issecretvalue(current) then
        return
    end
    CUI.SetFontFamily(fontStr, Theme.fontPath, size or current or 12, Theme.fontFlag or "", Theme.fontShadow)
    if red then
        fontStr:SetTextColor(red, green, blue or red)
    end
end

-- Force a FontString readable-white without touching its font file.
function Skin.White(fontStr, red, green, blue)
    if fontStr and fontStr.SetTextColor then
        fontStr:SetTextColor(red or 1, green or 1, blue or 1)
    end
end

-- Generic action button -> flat dark block with a subtle white hover.
-- keepKeys preserves named regions (e.g. {"Icon"}).
local function ApplyButton(button, skinData, keepKeys)
    local keep = {}
    if skinData.bg then
        keep[skinData.bg] = true
    end
    if skinData.hover then
        keep[skinData.hover] = true
    end
    if keepKeys then
        for _, keyName in ipairs(keepKeys) do
            local region = button[keyName]
            if region then
                keep[region] = true
            end
        end
    end
    FadeRegions(button, keep)
    for _, getter in ipairs({
        "GetNormalTexture",
        "GetPushedTexture",
        "GetDisabledTexture",
        "GetHighlightTexture",
    }) do
        local func = button[getter]
        local t = func and func(button)
        if t and not keep[t] then
            t:SetAlpha(0)
        end
    end
    for _, keyName in ipairs({ "Left", "Middle", "Right", "LeftSeparator", "RightSeparator" }) do
        local region = button[keyName]
        if region and not keep[region] and region.SetAlpha then
            region:SetAlpha(0)
        end
    end

    local fillTex = skinData.bg
    if not fillTex then
        fillTex = button:CreateTexture(nil, "BACKGROUND")
        skinData.bg = fillTex
    end
    fillTex:SetColorTexture(Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fillTex:SetAllPoints(button)
    AddBorder(button)

    local hover = skinData.hover
    if not hover then
        hover = button:CreateTexture(nil, "HIGHLIGHT")
        skinData.hover = hover
    end
    hover:SetColorTexture(1, 1, 1, 0.1)
    hover:SetAllPoints(button)

    -- Label font stays Blizzard's (color-only text policy).
    Register(button, keep)
end

function Skin.Button(button, keepKeys)
    if not button or button:IsForbidden() then
        return
    end
    Skin.CompleteSetup(button, "skinned", ApplyButton, keepKeys)
end

-- Force a button's label white (color only, font untouched). Many action
-- buttons render their enabled text in Blizzard gold; this is opt-in per call
-- (WSkin.Button leaves labels alone). Buttons re-apply their font object when
-- re-enabled, so re-white on every OnEnable as well as now.
function Skin.WhiteButtonLabel(button)
    if not button or (button.IsForbidden and button:IsForbidden()) then
        return
    end
    local labelText = button.Text or (button.GetFontString and button:GetFontString())
    if not labelText then
        return
    end
    Skin.White(labelText)
    local skinData = GetFFD(button)
    if not skinData.whiteHook then
        skinData.whiteHook = true
        if button.HookScript then
            button:HookScript("OnEnable", function()
                Skin.White(labelText)
            end)
        end
    end
end

-- Like WhiteButtonLabel, but the label mirrors the native enabled/disabled states:
-- white when clickable, gray when not (a plain white label leaves a disabled button
-- reading as active, since our color write overrides the disabled-font gray).
function Skin.StateButtonLabel(button)
    if not button or (button.IsForbidden and button:IsForbidden()) then
        return
    end
    local labelText = button.Text or (button.GetFontString and button:GetFontString())
    if not labelText then
        return
    end
    local skinData = GetFFD(button)
    if skinData.stateHook then
        return
    end
    skinData.stateHook = true
    local function reflect()
        if button:IsEnabled() then
            Skin.White(labelText)
        else
            labelText:SetTextColor(0.5, 0.5, 0.5)
        end
    end
    if button.HookScript then
        button:HookScript("OnEnable", reflect)
        button:HookScript("OnDisable", reflect)
    end
    reflect()
end

-- Search / input box -> near-black block, border, art gone.
-- opts.padInput = widen left + inset the text; opts.noBorder = skip border.
function Skin.EditBox(editField, options)
    if not editField or editField:IsForbidden() then
        return
    end
    local skinData = GetFFD(editField)
    if skinData.bg then
        return
    end
    FadeRegions(editField)
    for _, keyName in ipairs({ "Left", "Right", "Middle", "Mid" }) do
        local region = editField[keyName]
        if region and region.SetAlpha then
            region:SetAlpha(0)
        end
    end
    if options and options.padInput and CludesUI._WSkinPadInput then
        CludesUI._WSkinPadInput(editField)
    end
    local fillTex = SolidTex(editField, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fillTex:SetAllPoints(editField)
    skinData.bg = fillTex
    -- Same border as WSkin.Button (theme defaults).
    if not (options and options.noBorder) then
        AddBorder(editField)
    end
end

-- Checkbox -> dark block + accent tick. opts.stockCheck leaves the checkmark
-- color to Blizzard (windows where check tint carries meaning, e.g. the
-- addon list's enabled states). opts.hover: a white hover wash of that alpha
-- over the box (the highlight texture is cleared).
function Skin.Checkbox(cb, options)
    if not cb or cb:IsForbidden() then
        return
    end
    local skinData = GetFFD(cb)
    if skinData.skinned then
        return
    end
    skinData.skinned = true
    if cb.SetNormalTexture then
        cb:SetNormalTexture("")
    end
    if cb.SetPushedTexture then
        cb:SetPushedTexture("")
    end
    if cb.SetHighlightTexture then
        cb:SetHighlightTexture("")
    end
    -- Some checkbox templates draw the box border as a separate region rather
    -- than the Normal texture, so fade every existing texture except the
    -- checkmark before laying down our own flat box. (No-op for plain
    -- checkboxes: they carry nothing beyond Normal/Pushed/Highlight/Checked.)
    local checked = cb.GetCheckedTexture and cb:GetCheckedTexture()
    local dchecked = cb.GetDisabledCheckedTexture and cb:GetDisabledCheckedTexture()
    local regionList = { cb:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region ~= checked and region ~= dchecked and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    local fillTex = SolidTex(cb, "BACKGROUND", 0.02, 0.02, 0.02, 1)
    fillTex:SetPoint("TOPLEFT", 4, -4)
    fillTex:SetPoint("BOTTOMRIGHT", -4, 4)
    skinData.bg = fillTex
    if options and options.hover then
        local hover = SolidTex(cb, "HIGHLIGHT", 1, 1, 1, options.hover)
        hover:SetPoint("TOPLEFT", 4, -4)
        hover:SetPoint("BOTTOMRIGHT", -4, 4)
        skinData.hover = hover
    end
    -- Border rides the checkbox frame by default; when the frame is larger
    -- than its visible box (opts.borderInset), put the border on an inset
    -- child so it hugs the actual box instead of sitting proud of it.
    local bi = options and options.borderInset
    if bi and bi > 0 then
        local bh = CreateFrame("Frame", nil, cb)
        bh:SetPoint("TOPLEFT", bi, -bi)
        bh:SetPoint("BOTTOMRIGHT", -bi, bi)
        bh:SetFrameLevel(cb:GetFrameLevel() + 1)
        AddBorder(bh, 0.25, 0.25, 0.25, 1)
        skinData.borderHost = bh
    else
        AddBorder(cb, 0.25, 0.25, 0.25, 1)
    end
    if checked and not (options and options.stockCheck) then
        checked:SetVertexColor(Theme.accR, Theme.accG, Theme.accB, 1)
    end
end

-- Modern dropdown / legacy selector -> flat block. Nil-guarded per template.
function Skin.Dropdown(dropdown)
    if not dropdown or dropdown:IsForbidden() then
        return
    end
    local skinData = GetFFD(dropdown)
    if skinData.skinned then
        return
    end
    skinData.skinned = true
    FadeRegions(dropdown)
    local name = dropdown.GetName and dropdown:GetName()
    if name then
        for _, suffix in ipairs({ "Left", "Middle", "Right" }) do
            local region = _G[name .. suffix]
            if region and region.SetAlpha then
                region:SetAlpha(0)
            end
        end
    end
    if dropdown.Background then
        dropdown.Background:SetAlpha(0)
    end
    if dropdown.Texture then
        dropdown.Texture:SetAlpha(0)
    end
    local fillTex = SolidTex(dropdown, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    fillTex:SetAllPoints(dropdown)
    skinData.bg = fillTex
    AddBorder(dropdown, 0.25, 0.25, 0.25, 1)
    -- Slight lighten on hover.
    local hover = SolidTex(dropdown, "HIGHLIGHT", 1, 1, 1, 0.05)
    hover:SetAllPoints(dropdown)
    skinData.hover = hover
    -- Our own arrow on the right (Blizzard's is faded with the rest).
    -- Sized to the atlas's native 62x44 aspect.
    local arrowTex = dropdown:CreateTexture(nil, "OVERLAY")
    arrowTex:SetAtlas("Azerite-PointingArrow")
    arrowTex:SetSize(14, 10)
    arrowTex:SetPoint("RIGHT", dropdown, "RIGHT", -6, 0)
    skinData.arrow = arrowTex
    -- Label recolored white; the font itself stays Blizzard's.
    local label = dropdown.Text or (dropdown.GetFontString and dropdown:GetFontString())
    if label then
        Skin.White(label)
    end
end

-- AH-style click-to-sort header bar over a list's HeaderContainer: a 50% near-
-- black strip spanning the LIST's own width and riding the header row, column
-- 3-slice art flattened to invisible plates with white labels and a
-- full-strip-height hover. Re-run from the list's refresh / OnShow hook since
-- columns pool and rebuild. No wash dependency (unlike the AH pack's own
-- wash-relative seating) -- the strip spans the list rect directly.
function Skin.SortHeaderBar(entries)
    local hc = entries and entries.HeaderContainer
    if not hc then
        return
    end
    local partData = GetFFD(entries)
    if not partData.strip then
        local sTex = entries:CreateTexture(nil, "BACKGROUND", nil, 1)
        sTex:SetColorTexture(0.02, 0.02, 0.02, 0.5)
        sTex:SetHeight(24)
        partData.strip = sTex
        partData.fill = sTex -- protected key so a Restrip never fades our own strip
    end
    partData.strip:SetAlpha(1)
    local ll0, lr0 = entries:GetLeft(), entries:GetRight()
    local hl0 = hc:GetLeft()
    if ll0 and lr0 and hl0 then
        partData.strip:ClearAllPoints()
        partData.strip:SetPoint("TOPLEFT", hc, "TOPLEFT", ll0 - hl0, 2)
        partData.strip:SetPoint("TOPRIGHT", hc, "TOPLEFT", lr0 - hl0, 2)
    end
    local children = { hc:GetChildren() }
    for idx = 1, #children do
        local colour = children[idx]
        if colour and colour.GetObjectType and colour:GetObjectType() == "Button" then
            local hd = GetFFD(colour)
            if not hd.bg then
                for _, k2 in ipairs({ "Left", "Middle", "Right" }) do
                    local t2 = colour[k2]
                    if t2 and t2.SetTexture then
                        t2:SetTexture("")
                    end
                end
                Skin.FadeRegions(colour)
                local backdrop = SolidTex(colour, "BACKGROUND", 0.02, 0.02, 0.02, 0)
                backdrop:SetPoint("TOPLEFT", 1, -1)
                backdrop:SetPoint("BOTTOMRIGHT", -1, 1)
                hd.bg = backdrop
                local hoverTex = SolidTex(colour, "HIGHLIGHT", 1, 1, 1, 0.1)
                hoverTex:SetAllPoints(colour)
                hd.hover = hoverTex
            end
            local fontStr = colour.GetFontString and colour:GetFontString()
            if fontStr then
                Skin.White(fontStr)
            end
            local strip = partData.strip
            if hd.hover and strip and strip.GetTop then
                local st, sbot = strip:GetTop(), strip:GetBottom()
                local ct, cbot = colour:GetTop(), colour:GetBottom()
                if st and sbot and ct and cbot then
                    hd.hover:ClearAllPoints()
                    hd.hover:SetPoint("TOPLEFT", colour, "TOPLEFT", 0, st - ct)
                    hd.hover:SetPoint("BOTTOMRIGHT", colour, "BOTTOMRIGHT", 0, sbot - cbot)
                end
            end
        end
    end
end

-- MinimalScrollBar -> strip track/arrows; the thumb becomes a slim 5px white
-- strip centered in the thumb's hit area (the house scrollbar look).
-- keepSteppers leaves the up/down arrows as Blizzard draws them; only the
-- track art and the thumb change, in place.
function Skin.ScrollBar(scrollBar, keepSteppers)
    if not scrollBar or scrollBar:IsForbidden() then
        return
    end
    local skinData = GetFFD(scrollBar)
    if skinData.skinned then
        return
    end
    skinData.skinned = true
    if not keepSteppers then
        for _, keyName in ipairs({ "Back", "Forward" }) do
            local button = scrollBar[keyName]
            if button then
                FadeRegions(button)
                if button.Texture then
                    button.Texture:SetAlpha(0)
                end
            end
        end
    end
    local track = scrollBar.Track
    if track then
        FadeRegions(track)
    end
    local thumb = (track and track.Thumb) or (scrollBar.GetThumb and scrollBar:GetThumb())
    if thumb and not GetFFD(thumb).bg then
        FadeRegions(thumb)
        local t = SolidTex(thumb, "ARTWORK", 1, 1, 1, 0.3)
        t:SetPoint("TOP", thumb, "TOP", 0, 0)
        t:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
        t:SetWidth(4)
        GetFFD(thumb).bg = t
    end
end

-- Recursively flatten any MinimalScrollBar under a frame. Shallow + one-time
-- (guarded per bar); used at skin time only, never in per-update hooks.
function Skin.ScrollBarsIn(widget, depth)
    depth = depth or 0
    if not widget or depth > 7 or widget:IsForbidden() then
        return
    end
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        local childFrame = children[idx]
        if childFrame and not Skin.IsForeignFrame(childFrame, widget) then
            if childFrame.Track and (childFrame.Back or childFrame.Forward) then
                Skin.ScrollBar(childFrame)
            end
            Skin.ScrollBarsIn(childFrame, depth + 1)
        end
    end
end

-- Close (X) button -> strip art, draw the house close glyph.
function Skin.CloseButton(button)
    if not button or button:IsForbidden() then
        return
    end
    local skinData = GetFFD(button)
    if skinData.x then
        return
    end
    if button.SetNormalTexture then
        button:SetNormalTexture("")
    end
    if button.SetPushedTexture then
        button:SetPushedTexture("")
    end
    if button.SetHighlightTexture then
        button:SetHighlightTexture("")
    end
    if button.SetDisabledTexture then
        button:SetDisabledTexture("")
    end
    FadeRegions(button)
    local posX = button:CreateTexture(nil, "OVERLAY")
    posX:SetAtlas("uitools-icon-close")
    posX:SetSize(14, 14)
    posX:SetPoint("CENTER", -2, 0)
    posX:SetVertexColor(1, 1, 1, 0.75)
    skinData.x = posX
    button:HookScript("OnEnter", function()
        if skinData.x then
            skinData.x:SetVertexColor(1, 1, 1, 1)
        end
    end)
    button:HookScript("OnLeave", function()
        if skinData.x then
            skinData.x:SetVertexColor(1, 1, 1, 0.75)
        end
    end)
end

-- Active-filter reset "X": strips Blizzard's glyph, draws house
-- uitools-icon-close above the dropdown border (white 0.9->1 on hover).
-- `host` = the dropdown it rides (frame-level layering); idempotent via FFD.x.
-- The window packs' filter dropdowns and the Group Finder's search filter.
function Skin.FilterResetX(rb, owner)
    if not rb or rb:IsForbidden() then
        return
    end
    local regionData = GetFFD(rb)
    if regionData.x then
        return
    end
    local regionList = { rb:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture" }) do
        local t = rb[getter] and rb[getter](rb)
        if t and t.SetAlpha then
            t:SetAlpha(0)
        end
    end
    if owner then
        rb:SetFrameLevel(owner:GetFrameLevel() + 5)
    end
    local posX = rb:CreateTexture(nil, "OVERLAY", nil, 7)
    posX:SetAtlas("uitools-icon-close", false)
    posX:SetSize(10, 10)
    posX:SetPoint("CENTER", rb, "CENTER", 0, 0)
    posX:SetVertexColor(1, 1, 1, 0.9)
    regionData.x = posX
    rb:HookScript("OnEnter", function()
        posX:SetVertexColor(1, 1, 1, 1)
    end)
    rb:HookScript("OnLeave", function()
        posX:SetVertexColor(1, 1, 1, 0.9)
    end)
end

-- Refresh button -> strip its art and draw the house white UI-RefreshButton
-- glyph (desaturated, white at 0.9, full on hover). The Group Finder, Auction
-- House, crafting orders and WoW Forever Looking For Group refresh buttons.
function Skin.RefreshGlyph(rb)
    if not rb or rb:IsForbidden() then
        return
    end
    local skinData = GetFFD(rb)
    if skinData.refreshGlyph then
        return
    end
    if not (C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo("UI-RefreshButton")) then
        return
    end
    local regionList = { rb:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region.IsObjectType and region:IsObjectType("Texture") then
            region:SetAlpha(0)
        end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        local t = rb[getter] and rb[getter](rb)
        if t and t.SetAlpha then
            t:SetAlpha(0)
        end
    end
    local glyph = rb:CreateTexture(nil, "OVERLAY")
    glyph:SetAtlas("UI-RefreshButton", false)
    glyph:SetSize(16, 16)
    glyph:SetPoint("CENTER")
    glyph:SetDesaturated(true)
    glyph:SetVertexColor(1, 1, 1, 0.9)
    skinData.refreshGlyph = glyph
    rb:HookScript("OnEnter", function()
        glyph:SetVertexColor(1, 1, 1, 1)
    end)
    rb:HookScript("OnLeave", function()
        glyph:SetVertexColor(1, 1, 1, 0.9)
    end)
end

-- Page-nav / arrow button -> flat block with a house arrow texture
-- (falls back to a text glyph for unmapped characters).
local PAGE_ARROWS = {
    ["<"] = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-left.png",
    [">"] = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-right.png",
}
function Skin.PageButton(button, ch, size)
    if not button or button:IsForbidden() then
        return
    end
    local skinData = GetFFD(button)
    if skinData.block then
        return
    end
    skinData.block = true
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture", "GetHighlightTexture" }) do
        local func = button[getter]
        local t = func and func(button)
        if t and t.SetAlpha then
            t:SetAlpha(0)
        end
    end
    local backdrop = SolidTex(button, "BACKGROUND", Theme.bgR, Theme.bgG, Theme.bgB, Theme.bgA)
    backdrop:SetAllPoints(button)
    skinData.bg = backdrop
    AddBorder(button)
    local texture = PAGE_ARROWS[ch]
    if texture then
        local arrowTex = button:CreateTexture(nil, "OVERLAY")
        arrowTex:SetTexture(texture)
        local s = size or 14
        arrowTex:SetSize(s, s)
        arrowTex:SetPoint("CENTER")
        arrowTex:SetAlpha(0.9)
        skinData.arrow = arrowTex
    else
        local fontStr = button:CreateFontString(nil, "OVERLAY")
        fontStr:SetFont(Theme.fontPath, size or 14, Theme.fontFlag or "")
        fontStr:SetPoint("CENTER")
        fontStr:SetText(ch)
        fontStr:SetTextColor(1, 1, 1, 0.9)
        skinData.arrow = fontStr
    end
    local hover = SolidTex(button, "HIGHLIGHT", 1, 1, 1, 0.1)
    hover:SetAllPoints(button)
    skinData.hover = hover
    -- Disabled (can't page further) -> whole block at half opacity.
    local function reflect()
        button:SetAlpha(button:IsEnabled() and 1 or 0.5)
    end
    button:HookScript("OnEnable", reflect)
    button:HookScript("OnDisable", reflect)
    reflect()
end

-- Find PrevPageButton/NextPageButton anywhere shallow under a frame.
function Skin.PagingIn(widget, depth)
    depth = depth or 0
    if not widget or depth > 8 or not widget.GetChildren or widget:IsForbidden() then
        return
    end
    if depth > 0 and Skin.IsForeignFrame(widget) then
        return
    end
    if widget.PrevPageButton then
        Skin.PageButton(widget.PrevPageButton, "<")
    end
    if widget.NextPageButton then
        Skin.PageButton(widget.NextPageButton, ">")
    end
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        Skin.PagingIn(children[idx], depth + 1)
    end
end

-- 1px black frame around a texture region (squared icons).
function Skin.BorderRegion(hostFrame, regionFrame)
    if not (hostFrame and regionFrame) then
        return
    end
    local skinData = GetFFD(regionFrame)
    if skinData.bordered then
        return
    end
    skinData.bordered = true
    local function line()
        local tex = hostFrame:CreateTexture(nil, "OVERLAY")
        tex:SetColorTexture(0, 0, 0, 1)
        return tex
    end
    local top, bottom, left, right = line(), line(), line(), line()
    top:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", -1, 1)
    top:SetPoint("TOPRIGHT", regionFrame, "TOPRIGHT", 1, 1)
    top:SetHeight(1)
    bottom:SetPoint("BOTTOMLEFT", regionFrame, "BOTTOMLEFT", -1, -1)
    bottom:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", 1, -1)
    bottom:SetHeight(1)
    left:SetPoint("TOPLEFT", regionFrame, "TOPLEFT", -1, 1)
    left:SetPoint("BOTTOMLEFT", regionFrame, "BOTTOMLEFT", -1, -1)
    left:SetWidth(1)
    right:SetPoint("TOPRIGHT", regionFrame, "TOPRIGHT", 1, 1)
    right:SetPoint("BOTTOMRIGHT", regionFrame, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(1)
end

-------------------------------------------------------------------------------
--  SQUARE QUALITY BORDERS for item tiles.
--
--  Blizzard's own quality ring, `IconBorder`, is ROUNDED. Every pack that
--  squares an icon therefore strips it -- it defeats the square crop
--  underneath and reads as the "border that keeps coming back" -- and until
--  now nothing replaced it, which left reward tiles with no rarity cue at all.
--
--  This draws the same 1px square edge the LOOT WINDOW already ships:
--  PP.CreateBorder, whose strips are integer physical thickness and immune to
--  pixel snapping, so no side can round away to 0 at a fractional UI scale.
--  A plain 4-texture border does round away, which is why this does not simply
--  extend WSkin.BorderRegion above.
--
--  The COLOR is read back off Blizzard's ring rather than re-derived from an
--  itemID. Deriving it would mean C_Item quality lookups on items whose data
--  may not be cached yet -- an async load, a second source of truth, and a
--  guaranteed drift from whatever Blizzard decided. The ring already holds the
--  answer: shown iff the quality has a color, vertex-colored to it.
-------------------------------------------------------------------------------

-- Uncommon and up ONLY, matched to what the loot window already shipped so the
-- surfaces cannot drift apart. Poor and common rings are achromatic (grey,
-- white) while every quality from green up is saturated, so a CHROMA test
-- sorts them with no item-quality lookup at all. Returns nil for "no rarity to
-- show", which the caller renders as the ordinary black edge.
local QUALITY_CHROMA = 0.1
function Skin.RingQuality(ring)
    if not (ring and ring.IsShown and ring.GetVertexColor) then
        return
    end
    -- SHOWN, not alpha: the packs alpha these rings to 0 to hide the rounded
    -- art, and Blizzard drives visibility with SetShown. Testing alpha here
    -- would read our own edit and call every item common.
    if not ring:IsShown() then
        return
    end
    local red, green, blue = ring:GetVertexColor()
    if type(red) ~= "number" or type(green) ~= "number" or type(blue) ~= "number" then
        return
    end
    if (math.max(red, green, blue) - math.min(red, green, blue)) <= QUALITY_CHROMA then
        return
    end
    return red, green, blue
end

-- Tiles whose border follows Blizzard's ring, so the hook below knows which
-- buttons are its business. Weak: a pooled tile going away takes its entry.
local _qTiles = setmetatable({}, { __mode = "k" })
local _qHooked = false

local function PaintQuality(button)
    local owner = _qTiles[button]
    if not owner then
        return
    end
    local Pix = CUI and (CUI.PanelPP or CUI.PP)
    if not (Pix and Pix.SetBorderColor) then
        return
    end
    -- The border stays up on an EMPTY slot, black, and that is deliberate.
    --
    -- It was briefly hidden when the icon was (Blizzard hides an item button's
    -- icon when the slot is empty), on the theory that a grid of empty outlined
    -- boxes looked broken. The opposite turned out to be true in game: those
    -- boxes ARE the slot -- they show where an item can be dropped -- and with
    -- them gone the trade window read as having no item slots at all. Empty is
    -- black, filled is the rarity.
    local red, green, button = Skin.RingQuality(button.IconBorder)
    -- No rarity -> BLACK, not hidden: every other icon in the suite carries a
    -- 1px black edge, so a common drop should look like the rest of them
    -- rather than like a tile that lost its border.
    Pix.SetBorderColor(owner, red or 0, green or 0, button or 0, 1)
end

-- Runs inside Blizzard's call stack, from bag and bank updates as well as ours.
-- The registry test comes FIRST so an unrelated item button costs one weak
-- table lookup and nothing else, and the paint is pcall'd so a throw here can
-- never surface as an error inside their update.
--
-- Painting immediately is correct, unlike the widget-bar covers: hooksecurefunc
-- runs AFTER the original, and SetItemButtonQuality has already shown and
-- vertex-colored the ring by the time it returns, so there is nothing to wait
-- for.
local function OnItemButtonQuality(button)
    if not _qTiles[button] then
        return
    end
    pcall(PaintQuality, button)
end

-- Give `icon` a square 1px border on `owner`, colored by item quality.
--
-- With no explicit color the border FOLLOWS Blizzard's ring, repainting
-- whenever SetItemButtonQuality touches the button -- which is what makes
-- pooled tiles correct without any pack having to guess when Blizzard
-- repopulates them. Pass r,g,b for surfaces that have no ring to read
-- (the loot roll popups carry quality in an ATLAS NAME instead).
function Skin.QualityBorder(ownerFrame, iconTex, red, green, blue)
    if not (ownerFrame and iconTex) then
        return
    end
    -- Same hazard as every other frame-creating helper here: CreateFrame on a
    -- forbidden owner THROWS, and callers are pcall-isolated per WINDOW, so an
    -- unguarded throw takes out the rest of that window's pass rather than one
    -- icon's border.
    if ownerFrame.IsForbidden and ownerFrame:IsForbidden() then
        return
    end
    if iconTex.IsForbidden and iconTex:IsForbidden() then
        return
    end
    local Pix = CUI and (CUI.PanelPP or CUI.PP)
    if not (Pix and Pix.CreateBorder) then
        -- Older CludesUI without the pixel-perfect border API: fall back to
        -- the plain black edge rather than leaving the tile with nothing.
        Skin.BorderRegion(ownerFrame, iconTex)
        return
    end
    local skinData = GetFFD(ownerFrame)
    local owner = skinData.qBorder
    if not owner then
        -- Its OWN frame, anchored to the ICON rather than the button: the
        -- button rect is larger than its icon on most of these templates, and
        -- PP.CreateBorder spans whatever frame it is handed.
        owner = CreateFrame("Frame", nil, ownerFrame)
        -- ONE PIXEL OUTSIDE the icon, not on its edge. Sitting exactly on the
        -- rect put the strips on the same pixels the icon draws, so the icon
        -- won and the border looked like it was being clipped through --
        -- visible on any icon with light content at the edge. Outset by 1 it
        -- rings the icon and nothing can overlap it.
        owner:SetPoint("TOPLEFT", iconTex, "TOPLEFT", -1, 1)
        owner:SetPoint("BOTTOMRIGHT", iconTex, "BOTTOMRIGHT", 1, -1)
        -- ...and well clear of the button's own layers. Item buttons stack
        -- icon, overlays, quest markers and an alert frame, and some templates
        -- raise their own level (trade calls RaiseFrameLevelByTwo).
        if ownerFrame.GetFrameLevel then
            owner:SetFrameLevel(ownerFrame:GetFrameLevel() + 6)
        end
        Pix.CreateBorder(owner, 0, 0, 0, 1, 1, "OVERLAY", 7)
        skinData.qBorder = owner
    end
    if red then
        _qTiles[ownerFrame] = nil
        if Pix.SetBorderColor then
            Pix.SetBorderColor(owner, red, green, blue, 1)
        end
        return
    end
    _qTiles[ownerFrame] = owner

    -- TWO ways Blizzard sets a quality, and one of them the global hook below
    -- cannot see.
    --
    -- The global SetItemButtonQuality delegates to `button:SetItemButtonQuality`
    -- whenever the button has that method -- so a caller that invokes the
    -- METHOD directly never passes through the global at all. MerchantFrame is
    -- exactly that caller (`self.ItemButton:SetItemButtonQuality(...)`), which
    -- is why a vendor tile would otherwise sit on a stale color forever while
    -- quest rewards and loot worked fine.
    --
    -- Hooking the instance covers both routes at once: the global's own
    -- delegation lands here too. Marked in FFD, since a pooled tile is
    -- re-skinned on every pass and must not stack hooks.
    if type(ownerFrame.SetItemButtonQuality) == "function" and not skinData.qMethodHook then
        skinData.qMethodHook = true
        pcall(hooksecurefunc, ownerFrame, "SetItemButtonQuality", OnItemButtonQuality)
    end
    -- Still needed for buttons with NO method, where the global does the work
    -- itself (SetItemButtonQuality_Base).
    if not _qHooked and type(_G.SetItemButtonQuality) == "function" then
        _qHooked = true
        hooksecurefunc("SetItemButtonQuality", OnItemButtonQuality)
    end
    PaintQuality(ownerFrame)
end

-- One quest-style reward tile: drop the parchment name plate and every ring
-- stacked on the icon, white the name, square the icon and give it the rarity
-- border.
--
-- Lives here rather than in a pack because THREE places need the identical
-- treatment -- the NPC quest window, the map/quest-log rewards frame, and the
-- lazy-creation hook on QuestInfo_GetRewardButton -- and WindowPacks has no
-- headroom for another file-scope local.
--
-- NameFrame is the box round the name; IconBorder is the ROUNDED quality ring,
-- stripped because it defeats the square crop, with its colour read back onto
-- the square border by SquareIcon's `quality` flag.
local REWARD_TILE_ART = { "NameFrame", "IconBorder", "IconOverlay", "IconOverlay2", "IconBorder2" }
function Skin.QuestRewardTile(button)
    if not button or (button.IsForbidden and button:IsForbidden()) then
        return
    end
    -- parentKey OR global name. LargeItemButtonTemplate declares these with
    -- both (`name="$parentNameFrame" parentKey="NameFrame"`), but the small
    -- quest template and the trade window's own tiles declare the same art
    -- with NO parentKey -- and a lookup that only tries the key silently finds
    -- nothing and leaves the plate up.
    local num = button.GetName and button:GetName()
    for idx = 1, #REWARD_TILE_ART do
        local keyName = REWARD_TILE_ART[idx]
        local t = button[keyName] or (num and _G[num .. keyName])
        if t and t.SetAlpha and t.IsObjectType and t:IsObjectType("Texture") then
            t:SetAlpha(0)
        end
    end
    if button.Name and button.Name.SetTextColor then
        button.Name:SetTextColor(1, 1, 1)
    end
    Skin.SquareIcon(button.Icon, button, true)
end

-- Every reward tile under `frame`, named or not.
--
-- RewardButtons alone is NOT enough. A /framestack over the "may have
-- additional rewards" tile shows it as `MapQuestInfoRewardsFrame.<hex>` -- an
-- ANONYMOUS child. QuestInfo_GetRewardButton NAMES the buttons it creates
-- ($parentQuestInfoItem1...), so an unnamed tile did not come from there and
-- is never in RewardButtons; it comes from one of the frame's own pools.
--
-- So the named list is walked first and then the CHILDREN, with anything
-- carrying a reward tile's shape treated as one. Every probe is pcall'd: a
-- quest rewards frame can hold widget-backed children whose field access
-- throws, and one of those must not take the pass down.
local function LooksLikeRewardTile(frame)
    return (frame.NameFrame ~= nil) or (frame.Icon ~= nil)
end
-- Children as a TABLE, passed BY ARGUMENT to pcall. The obvious spelling,
-- pcall(function() return { f:GetChildren() } end), allocates a fresh CLOSURE
-- on every call -- the exact thing this file's own KidsOf helpers exist to
-- avoid, and this runs on every quest display.
local function RewardKids(frame)
    return { frame:GetChildren() }
end
function Skin.QuestRewardTiles(widget)
    if not widget or (widget.IsForbidden and widget:IsForbidden()) then
        return
    end
    local rb = widget.RewardButtons
    if rb then
        for idx = 1, #rb do
            Skin.QuestRewardTile(rb[idx])
        end
    end
    if not widget.GetChildren then
        return
    end
    local okKids, kids = pcall(RewardKids, widget)
    if not okKids or not kids then
        return
    end
    for idx = 1, #kids do
        local ch = kids[idx]
        local okShape, isTile = pcall(LooksLikeRewardTile, ch)
        if okShape and isTile then
            Skin.QuestRewardTile(ch)
        end
    end
end

-- Item button icons. The newer item button code (WoW Forever's today; retail's
-- may follow) undoes a one-time square in two ways, both handled here so every
-- SquareIcon caller, ours and the skinning API's, gets the same square icon:
--  - ItemButtonMixin:PostOnLoad rounds the icon's corners with the button's own
--    Mask (the normal and pushed textures' too). A corner rounding, not a shape,
--    so SquareIcon drops it (Unround) and squares the icon as on retail.
--  - SetItemButtonTexture resets the icon's tex coords on every call. SquareIcon
--    records the button's own icon (Keep) and post-hooks the setter, global and
--    method (QualityBorder's two routes), to square it again once the coords read
--    full. An atlas (the empty slot art) keeps its own coords, and on a client
--    whose setter keeps the crop the hook only reads it.
-- Weak: a pooled button going away takes its entry; the hook tests the registry
-- first, so an unrelated item button costs one table lookup.
local ItemCrop = { tiles = setmetatable({}, { __mode = "k" }), hooked = false }

-- The texture SetItemButtonTexture paints: Blizzard's GetItemButtonIconTexture,
-- which errors on an unnamed button without an icon key.
function ItemCrop.OwnIcon(button)
    local num = button.GetName and button:GetName()
    return button.Icon or button.icon or (num and _G[num .. "IconTexture"])
end

-- Remove `only` from tex's masks, or every mask when `only` is nil.
function ItemCrop.DropMasks(texture, only)
    if not (texture and texture.GetNumMaskTextures and texture.RemoveMaskTexture) then
        return
    end
    for idx = texture:GetNumMaskTextures(), 1, -1 do
        local m = texture:GetMaskTexture(idx)
        if m and (not only or m == only) then
            texture:RemoveMaskTexture(m)
        end
    end
end

-- The stock rounding only: an item button's own Mask as the icon's one mask.
-- Any other mask is a shape, and the icon stays native.
function ItemCrop.Unround(button, iconTex)
    if button.IsForbidden and button:IsForbidden() then
        return
    end
    local m = button.Mask
    if
        not (
            m
            and type(button.SetItemButtonTexture) == "function"
            and iconTex.GetNumMaskTextures
            and iconTex:GetNumMaskTextures() == 1
            and iconTex:GetMaskTexture(1) == m
        )
    then
        return
    end
    ItemCrop.DropMasks(iconTex, m)
    ItemCrop.DropMasks(button.GetNormalTexture and button:GetNormalTexture(), m)
    ItemCrop.DropMasks(button.GetPushedTexture and button:GetPushedTexture(), m)
end

function ItemCrop.OnTexture(button)
    local iconTex = ItemCrop.tiles[button]
    if not iconTex then
        return
    end
    local l, _, _, _, region = iconTex:GetTexCoord()
    if l == 0 and region == 1 then
        pcall(iconTex.SetTexCoord, iconTex, 0.08, 0.92, 0.08, 0.92)
    end
end

function ItemCrop.Keep(button, iconTex)
    if ItemCrop.tiles[button] == iconTex then
        return
    end
    if (button.IsForbidden and button:IsForbidden()) or ItemCrop.OwnIcon(button) ~= iconTex then
        return
    end
    ItemCrop.tiles[button] = iconTex
    local skinData = GetFFD(button)
    if type(button.SetItemButtonTexture) == "function" and not skinData.cropMethodHook then
        skinData.cropMethodHook = true
        pcall(hooksecurefunc, button, "SetItemButtonTexture", ItemCrop.OnTexture)
    end
    -- Buttons with no method (quest reward tiles) go through the global alone.
    if not ItemCrop.hooked and type(_G.SetItemButtonTexture) == "function" then
        ItemCrop.hooked = true
        hooksecurefunc("SetItemButtonTexture", ItemCrop.OnTexture)
    end
end

-- Square an icon texture (crop the baked bevel) and optionally border it.
--
-- `quality` true asks for the rarity-colored border above instead of the plain
-- black one. Routed through here rather than called alongside it so the MASK
-- GUARDS below stay the single authority: a masked icon renders as a shape,
-- and a square border drawn round it is exactly as wrong as a square crop.
-- An item button's own icon is the exception both ways (ItemCrop above): its
-- stock corner rounding goes, and its crop survives SetItemButtonTexture. The
-- button is `parent`, else the icon's own parent.
--
-- Returns true when the crop actually happened, so a caller that needs to
-- border a masked-icon surface itself can tell whether it may.
function Skin.SquareIcon(iconTex, hostFrame, quality)
    if not iconTex or not iconTex.SetTexCoord then
        return
    end
    local button = hostFrame or (iconTex.GetParent and iconTex:GetParent())
    if button then
        ItemCrop.Unround(button, iconTex)
    end
    -- A texture with a MaskTexture rejects SetTexCoord outright (hard Lua
    -- error, e.g. the special first-catch loot toast masks its icon). Leave
    -- masked icons fully native -- no crop, and no square border drawn
    -- around what the mask renders as a shape.
    if iconTex.GetNumMaskTextures and iconTex:GetNumMaskTextures() > 0 then
        return
    end
    -- The count sees only AddMaskTexture masks; a legacy SetMask() mask is
    -- invisible to it and still rejects SetTexCoord (field: fishing loot
    -- toast on a build that already carried the count guard). The call
    -- itself is the only reliable probe -- on rejection the icon stays
    -- native, same as the counted case.
    if not pcall(iconTex.SetTexCoord, iconTex, 0.08, 0.92, 0.08, 0.92) then
        return
    end
    if button then
        ItemCrop.Keep(button, iconTex)
    end
    if hostFrame then
        if quality then
            Skin.QualityBorder(hostFrame, iconTex)
        else
            Skin.BorderRegion(hostFrame, iconTex)
        end
    end
    return true
end

-- The house item slot (bag, bank and inventory buttons of the ItemButton family;
-- the public skinning API's S.ItemButton): the icon square-cropped on a dark
-- plate, a square 1px border in the item's rarity color (black when common or
-- empty; it follows SetItemButtonQuality, QualityBorder above) and a flat hover.
-- Faded: the slot frame art (NormalTexture) and the round quality ring
-- (IconBorder, whose color drives the square border). Every mask goes, so a
-- round template squares too: the icon's, the normal and pushed textures' and
-- the overlays' that sit on the icon. Everything functional stays as it is:
-- count, cooldown, the search, context and profession overlays, the quest, junk
-- and upgrade marks, the new item glow, the pushed art.
-- opts.icon: the icon texture when it is not the button's Icon / icon /
-- <name>IconTexture. A re-call repaints the rarity border and nothing else.
local ITEM_SLOT_OVERLAYS = { "searchOverlay", "ItemContextOverlay", "IconOverlay", "IconOverlay2" }
function Skin.ItemButton(button, options)
    if not button or (button.IsForbidden and button:IsForbidden()) then
        return
    end
    local iconTex = (options and options.icon) or ItemCrop.OwnIcon(button)
    if not (iconTex and iconTex.SetTexCoord) then
        return
    end
    local skinData = GetFFD(button)
    if not skinData.itemSlot then
        skinData.itemSlot = true
        local nt = button.GetNormalTexture and button:GetNormalTexture()
        ItemCrop.DropMasks(iconTex)
        ItemCrop.DropMasks(nt)
        ItemCrop.DropMasks(button.GetPushedTexture and button:GetPushedTexture())
        for idx = 1, #ITEM_SLOT_OVERLAYS do
            ItemCrop.DropMasks(button[ITEM_SLOT_OVERLAYS[idx]])
        end
        if nt then
            nt:SetAlpha(0)
        end
        if button.IconBorder and button.IconBorder.SetAlpha then
            button.IconBorder:SetAlpha(0)
        end
        if not Theme.insetR then
            ResolveTheme()
        end
        local backing = button:CreateTexture(nil, "BACKGROUND", nil, -7)
        backing:SetColorTexture(Theme.insetR, Theme.insetG, Theme.insetB, 1)
        backing:SetAllPoints(iconTex)
        local ht = button.GetHighlightTexture and button:GetHighlightTexture()
        if ht then
            ht:SetColorTexture(1, 1, 1, 0.08)
            ht:ClearAllPoints()
            ht:SetAllPoints(iconTex)
        end
    end
    Skin.SquareIcon(iconTex, button, true)
end

-- Remove a PortraitFrameTemplate's corner portrait.
function Skin.RemovePortrait(widget)
    if not widget then
        return
    end
    local pc = widget.PortraitContainer
    if pc then
        FadeRegions(pc)
        Register(pc, true)
        if pc.portrait and pc.portrait.SetAlpha then
            pc.portrait:SetAlpha(0)
        end
    end
    if widget.portrait and widget.portrait.SetAlpha then
        widget.portrait:SetAlpha(0)
    end
end

-------------------------------------------------------------------------------
--  Tabs. One shared PanelTemplates hook keeps selection state fresh across all
--  skinned tabs (bottom tabs and TabSystem top tabs both flow through here).
-------------------------------------------------------------------------------
local _skinnedTabs = setmetatable({}, { __mode = "k" })

local TAB_BG = { 0.068, 0.056, 0.052 }
local TAB_BG_DARK = { 0.03, 0.03, 0.03 }

local function TabIsSelected(tabBtn)
    -- FFD override first: windows with nonstandard tab systems (auction house
    -- displayMode) sync selection into FFD themselves -- never onto the Blizzard tab.
    local od = FFD[tabBtn]
    if od and od.selOverride ~= nil then
        return od.selOverride
    end
    -- The tab system's selectedTabID is authoritative. Pool-rebuilt tab rows
    -- (housing content tabs) can carry a stale isSelected=false after their
    -- system re-inits them, so the per-button flag is only a fallback.
    local hostFrame = tabBtn:GetParent()
    if hostFrame and hostFrame.selectedTabID ~= nil and tabBtn.tabID ~= nil then
        return hostFrame.selectedTabID == tabBtn.tabID
    end
    if tabBtn.isSelected ~= nil then
        return tabBtn.isSelected and true or false
    end
    if hostFrame and PanelTemplates_GetSelectedTab and tabBtn.GetID then
        local success, s = pcall(PanelTemplates_GetSelectedTab, hostFrame)
        if success and s ~= nil then
            return s == tabBtn:GetID()
        end
    end
    return false
end

local function UpdateTabVisual(tabBtn)
    local skinData = FFD[tabBtn]
    if not skinData or not skinData.underline then
        return
    end
    local sel = TabIsSelected(tabBtn)
    if skinData.label then
        skinData.label:SetTextColor(1, 1, 1, sel and 1 or 0.5)
    end
    skinData.underline:SetShown(sel and Skin.AccentBarShown())
    -- darkActive tabs deepen the fill when selected instead of the additive
    -- lighten wash.
    if skinData.activeHL then
        skinData.activeHL:SetShown(sel and not skinData.darkActive)
    end
    if skinData.bg and skinData.darkActive then
        local c = sel and TAB_BG_DARK or TAB_BG
        skinData.bg:SetColorTexture(c[1], c[2], c[3], 1)
    end
end

local function UpdateAllTabs()
    for tabBtn in pairs(_skinnedTabs) do
        if not tabBtn:IsForbidden() then
            UpdateTabVisual(tabBtn)
        end
    end
end
Skin.UpdateAllTabs = UpdateAllTabs

-- Visual selection only; nil returns to the native tab system's selection.
-- Keep the override outside the frame so Blizzard's tab state stays untouched.
function Skin.SetTabSelection(tabBtn, selected)
    if not tabBtn or tabBtn:IsForbidden() then
        return
    end
    GetFFD(tabBtn).selOverride = selected
    UpdateTabVisual(tabBtn)
end

local _tabHooked = false
local function EnsureTabHooks()
    if _tabHooked then
        return
    end
    _tabHooked = true
    if PanelTemplates_SetTab then
        hooksecurefunc("PanelTemplates_SetTab", UpdateAllTabs)
    end
    if PanelTemplates_UpdateTabs then
        hooksecurefunc("PanelTemplates_UpdateTabs", UpdateAllTabs)
    end
end

-- Tab -> the dungeons-and-raids tab pattern, copied exactly: native art
-- cleared permanently (SetTexture, so tabs never need a re-strip pass), flat
-- dark block, our own 11px label mirroring Blizzard's text, a faint additive
-- wash + a pixel-perfect full-width accent underline on the active tab.
-- Works for PanelTabButtonTemplate and TabSystem buttons.
function Skin.Tab(tabBtn, options)
    if not tabBtn or tabBtn:IsForbidden() then
        return
    end
    local skinData = GetFFD(tabBtn)
    if options and options.darkActive then
        skinData.darkActive = true
    end
    if skinData.bg then
        UpdateTabVisual(tabBtn)
        if skinData.label and skinData.blizLabel and skinData.blizLabel.GetText then
            skinData.label:SetText(skinData.blizLabel:GetText() or "")
        end
        return
    end
    skinData.skinned = true -- keeps the generic ButtonsIn sweep off skinned tabs
    -- TabSystem windows swap tabs with no PanelTemplates call, and keybind /
    -- programmatic swaps never click a tab either -- every one of those paths funnels
    -- through the system's SetTabVisuallySelected (it is also the writer of the
    -- selectedTabID field TabIsSelected reads). Hook it once per tab system so the
    -- underline tracks selection from every path (field report: swapping PlayerSpells
    -- tabs via keybind while the frame was open left the underline on the old tab).
    local sys = tabBtn:GetParent()
    if sys and not sys:IsForbidden() and type(sys.SetTabVisuallySelected) == "function" then
        local partData = GetFFD(sys)
        if not partData.visSelHooked then
            partData.visSelHooked = true
            hooksecurefunc(sys, "SetTabVisuallySelected", UpdateAllTabs)
        end
    end
    -- Icon tabs carry their label in Icon; retain its clipping mask as well.
    local regionList = { tabBtn:GetRegions() }
    for jdx = 1, #regionList do
        local region = regionList[jdx]
        if region and region ~= tabBtn.Icon and region ~= tabBtn.IconMask and region:IsObjectType("Texture") then
            region:SetTexture("")
            if region.SetAtlas then
                region:SetAtlas("")
            end
        end
    end
    for _, keyName in ipairs({ "Left", "Middle", "Right", "LeftDisabled", "MiddleDisabled", "RightDisabled" }) do
        if tabBtn[keyName] and tabBtn[keyName].SetTexture then
            tabBtn[keyName]:SetTexture("")
        end
    end
    local highlight = tabBtn.GetHighlightTexture and tabBtn:GetHighlightTexture()
    if highlight then
        highlight:SetTexture("")
    end

    skinData.bg = SolidTex(tabBtn, "BACKGROUND", 0.068, 0.056, 0.052, 1)
    skinData.bg:SetAllPoints()

    local activeHL = tabBtn:CreateTexture(nil, "ARTWORK", nil, -6)
    activeHL:SetAllPoints()
    activeHL:SetColorTexture(1, 1, 1, 0.02)
    activeHL:SetBlendMode("ADD")
    activeHL:Hide()
    skinData.activeHL = activeHL

    local blizLabel = tabBtn.Text or (tabBtn.GetFontString and tabBtn:GetFontString())
    local labelText = (blizLabel and blizLabel.GetText and blizLabel:GetText()) or ""
    if blizLabel and blizLabel.SetTextColor then
        blizLabel:SetTextColor(0, 0, 0, 0)
    end
    if tabBtn.SetPushedTextOffset then
        tabBtn:SetPushedTextOffset(0, 0)
    end

    local label = tabBtn:CreateFontString(nil, "OVERLAY")
    label:SetFont(Theme.fontPath, 11, Theme.fontFlag or "")
    label:SetPoint("CENTER", tabBtn, "CENTER", 0, 0)
    label:SetText(labelText)
    skinData.label = label
    skinData.blizLabel = blizLabel
    -- Mirror the live Blizzard text onto our label. Read it back off the (hidden)
    -- original after each write so dynamic updates land -- some labels carry a trailing
    -- count like "Public Orders (4)" set via SetFormattedText or a direct
    -- FontString:SetText, neither of which routes through the button's SetText.
    local function SyncLabel()
        if skinData.label and skinData.blizLabel and skinData.blizLabel.GetText then
            skinData.label:SetText(skinData.blizLabel:GetText() or "")
        end
    end
    hooksecurefunc(tabBtn, "SetText", SyncLabel)
    if blizLabel then
        hooksecurefunc(blizLabel, "SetText", SyncLabel)
        if blizLabel.SetFormattedText then
            hooksecurefunc(blizLabel, "SetFormattedText", SyncLabel)
        end
    end

    local underline = tabBtn:CreateTexture(nil, "OVERLAY", nil, 6)
    if CUI and CUI.PanelPP and CUI.PanelPP.DisablePixelSnap then
        CUI.PanelPP.DisablePixelSnap(underline)
        underline:SetHeight(CUI.PanelPP.mult or 1)
    else
        underline:SetHeight(1)
    end
    underline:SetPoint("BOTTOMLEFT", tabBtn, "BOTTOMLEFT", 0, 0)
    underline:SetPoint("BOTTOMRIGHT", tabBtn, "BOTTOMRIGHT", 0, 0)
    -- Color resolves from the Global Options accent-bar setting; the engine's
    -- looks refresh (not per-texture accent registration) keeps it current.
    local ur, ug, ub = Skin.AccentBarColor()
    underline:SetColorTexture(ur, ug, ub, 1)
    underline:Hide()
    skinData.underline = underline

    _skinnedTabs[tabBtn] = true
    EnsureTabHooks()
    -- TabSystem buttons do not flow through PanelTemplates_SetTab; refresh all
    -- skinned tabs one frame after any tab click.
    tabBtn:HookScript("OnClick", function()
        if C_Timer then
            C_Timer.After(0, UpdateAllTabs)
        else
            UpdateAllTabs()
        end
    end)
    UpdateTabVisual(tabBtn)
end

-- Force a row of skinned tabs to a uniform one-physical-pixel seam. Each Blizzard tab
-- template bakes in its own transparent art padding + anchor offsets, so once the art
-- is replaced by an edge-to-edge flat block the raw frame gaps (2-5px on some
-- templates) show through as inconsistent spacing. Re-chain each tab to the previous
-- tab's right edge + 1px, matching the tight seam a TabSystem produces. The first tab
-- keeps Blizzard's seat; because the chain is relative, it reflows automatically when
-- Blizzard resizes a tab. `tabs` is an ordered (left-to-right) array;
-- nil/missing/hidden entries are skipped so a conditionally-hidden tab (group finder,
-- encounter journal) never leaves a gap in the chain.
function Skin.NormalizeTabRow(tabs)
    if not tabs then
        return
    end
    -- One physical pixel in the TAB's own coordinate space. Blizzard windows
    -- run at UIParent scale, NOT the CUI options-panel scale, so PanelPP.mult
    -- is the wrong multiplier -- it lands the gap between 1 and 2 physical
    -- pixels and rounds inconsistently. PP.perfect (= 1 physical pixel at
    -- scale 1) divided by the tab's effective scale is exact at any scale.
    local Pix = CUI and CUI.PP
    -- Shave a few px off every skinned tab's height, ONCE per tab (guarded in
    -- the WSkin FFD so repeated re-skins never shrink it cumulatively). Applied
    -- here so every window's bottom tab row gets the same shorter profile.
    local TAB_TRIM_H = 2
    local prev
    for idx = 1, #tabs do
        local t = tabs[idx]
        if t and t.IsForbidden and not t:IsForbidden() and (not t.IsShown or t:IsShown()) then
            local skinData = GetFFD(t)
            if not skinData.heightTrimmed and t.SetHeight and t.GetHeight then
                skinData.heightTrimmed = true
                local hgt = t:GetHeight() or 0
                if hgt > TAB_TRIM_H then
                    t:SetHeight(hgt - TAB_TRIM_H)
                end
            end
            if prev then
                local gap = (Pix and Pix.mult) or 1
                local es = t.GetEffectiveScale and t:GetEffectiveScale()
                -- Bound-check es: a corrupted near-zero scale (left behind by
                -- another addon) would blow this up into a huge, wrong gap.
                if Pix and Pix.perfect and es and es > 0.1 and es < 10 then
                    gap = Pix.perfect / es
                end
                t:ClearAllPoints()
                t:SetPoint("LEFT", prev, "RIGHT", gap, 0)
            end
            prev = t
        end
    end
end

-- Flatten every Button child of a TabSystemTemplate.
function Skin.TabSystem(tsys, options)
    if not tsys then
        return
    end
    -- Programmatic tab switches (SetTab) never pass through the
    -- PanelTemplates hooks or a tab's OnClick; repaint on them directly.
    local skinData = GetFFD(tsys)
    if tsys.SetTab and not skinData.setTabHook then
        skinData.setTabHook = true
        hooksecurefunc(tsys, "SetTab", UpdateAllTabs)
    end
    local children = { tsys:GetChildren() }
    for idx = 1, #children do
        local childFrame = children[idx]
        if childFrame and childFrame.GetObjectType and childFrame:GetObjectType() == "Button" then
            Skin.Tab(childFrame, options)
        end
    end
end

-------------------------------------------------------------------------------
--  Global look settings (Blizzard Window Skins -> Global Options). Central
--  CludesUIDB keys, nil = defaults: accent bar shown + accent colored, bar
--  fills accent at full opacity, links accent colored. Accent-mode elements
--  re-resolve from the LIVE accent color; a RegAccent callback keeps them in
--  sync on accent changes, and RefreshLooks() applies option edits live.
-------------------------------------------------------------------------------
local function LiveAccent()
    local ACC = CUI and CUI.CLUDES_GREEN
    if ACC then
        return ACC.r or 0.298, ACC.g or 0.788, ACC.b or 0.941
    end
    return 0.298, 0.788, 0.941
end

function Skin.AccentBarShown()
    local c = CludesUIDB and CludesUIDB.blizzWinAccentBar
    return not (c and c.enabled == false)
end

-- Custom mode with no stored color resolves to WHITE -- the same fallback
-- the custom swatch displays. (Requiring a stored color made a fresh switch
-- to custom silently fall back to accent until the picker first saved one.)
function Skin.AccentBarColor()
    local c = CludesUIDB and CludesUIDB.blizzWinAccentBar
    if c and c.useCustom then
        local colour = c.color
        if colour then
            return colour.r or 1, colour.g or 1, colour.b or 1
        end
        return 1, 1, 1
    end
    return LiveAccent()
end

function Skin.BarFillColor()
    local c = CludesUIDB and CludesUIDB.blizzWinBarFill
    local a = (c and c.alpha) or 0.95
    if c and c.useCustom then
        local colour = c.color
        if colour then
            return colour.r or 1, colour.g or 1, colour.b or 1, a
        end
        return 1, 1, 1, a
    end
    local red, green, blue = LiveAccent()
    return red * 0.8, green * 0.8, blue * 0.8, a
end

function Skin.LinkColor()
    local c = CludesUIDB and CludesUIDB.blizzWinLinks
    if c and c.useCustom then
        local colour = c.color
        if colour then
            return colour.r or 1, colour.g or 1, colour.b or 1
        end
        return 1, 1, 1
    end
    return LiveAccent()
end

function Skin.LinkColorHex()
    local red, green, blue = Skin.LinkColor()
    return string.format(
        "%02x%02x%02x",
        math.floor(red * 255 + 0.5),
        math.floor(green * 255 + 0.5),
        math.floor(blue * 255 + 0.5)
    )
end

-- Bar fills (flat accent progress bars) + tab underlines owned by files
-- outside the engine register here so option edits and accent changes
-- recolor them without a reload.
local _fillBars = setmetatable({}, { __mode = "k" })
local _extUnderlines = setmetatable({}, { __mode = "k" })
local _lookCallbacks = {}

function Skin.ApplyBarFill(barFrame)
    if not barFrame or not barFrame.SetStatusBarColor then
        return
    end
    _fillBars[barFrame] = true
    local red, green, blue, a = Skin.BarFillColor()
    barFrame:SetStatusBarColor(red, green, blue, a)
end

function Skin.RegisterAccentUnderline(texture)
    if texture then
        _extUnderlines[texture] = true
    end
end

function Skin.OnLooksChanged(func)
    _lookCallbacks[#_lookCallbacks + 1] = func
end

function Skin.RefreshLooks()
    local ur, ug, ub = Skin.AccentBarColor()
    for tabBtn in pairs(_skinnedTabs) do
        local skinData = FFD[tabBtn]
        if skinData and skinData.underline then
            skinData.underline:SetColorTexture(ur, ug, ub, 1)
        end
        if not tabBtn:IsForbidden() then
            UpdateTabVisual(tabBtn)
        end
    end
    for texture in pairs(_extUnderlines) do
        texture:SetColorTexture(ur, ug, ub, 1)
    end
    local br, bgr, bb, ba = Skin.BarFillColor()
    for barFrame in pairs(_fillBars) do
        if barFrame.SetStatusBarColor and not barFrame:IsForbidden() then
            barFrame:SetStatusBarColor(br, bgr, bb, ba)
        end
    end
    for _, func in ipairs(_lookCallbacks) do
        pcall(func)
    end
end
if CUI then
    CUI._WSkinRefreshLooks = Skin.RefreshLooks
end
CUI.RegAccent({
    type = "callback",
    fn = function()
        Skin.RefreshLooks()
    end,
})

-------------------------------------------------------------------------------
--  Targeted art sweeps. Used at SKIN TIME (or debounced repaint hooks), never
--  per-frame-update. Depth-capped; icons/models/our textures always survive.
-------------------------------------------------------------------------------
-- Content subtrees a window pack wants left alone (backgrounds that ARE the
-- content, e.g. the Adventure Guide Tutorials pane). Every recursive art
-- sweep skips an exempt frame and everything under it.
function Skin.ExemptArt(widget)
    if widget then
        GetFFD(widget).artExempt = true
    end
end
function Skin.IsArtExempt(widget)
    local skinData = FFD[widget]
    return skinData and skinData.artExempt or false
end

-- Frame provenance: is this frame Blizzard's, or was it parented into the window by
-- another addon? Every recursive DISCOVERY sweep (art fades, button flattening,
-- control/scrollbar/paging finds) skips foreign frames and their whole subtree, so
-- third-party panels riding a Blizzard window keep their own look. Explicit primitive
-- calls (WSkin.Button(frame), Panel, ...) stay ungated: naming a frame is opting in.
--
-- The signal: Blizzard's secure code leaves SECURE references behind -- a named frame's
-- global, or the parentKey slot on its parent -- while frames created by any addon
-- leave tainted ones. issecurevariable reads taint without spreading it, so the whole
-- check is side-effect free. Frames with no name and no reference on their parent
-- (pooled list rows) stay treated as Blizzard's; only confirmed-foreign verdicts cache
-- (a frame could gain its addon-written reference key after we first see it).
local _foreign = setmetatable({}, { __mode = "k" })

function Skin.IsForeignFrame(widget, hostFrame)
    if _foreign[widget] then
        return true
    end
    local name = widget.GetName and widget:GetName()
    if name and _G[name] == widget then
        if issecurevariable(name) then
            return false
        end
        _foreign[widget] = true
        return true
    end
    hostFrame = hostFrame or (widget.GetParent and widget:GetParent())
    if not hostFrame then
        return false
    end
    local insecureRef = false
    for keyName, val in pairs(hostFrame) do
        if type(keyName) == "string" and not issecretvalue(val) and val == widget then
            if issecurevariable(hostFrame, keyName) then
                return false
            end
            insecureRef = true
        end
    end
    if insecureRef then
        _foreign[widget] = true
        return true
    end
    return false
end

local BG_ART_KEYS = {
    "CustomBG",
    "InfoBackground",
    "BackgroundTexture",
    "DungeonBackground",
    "Background",
    "background",
    "Bg",
    "bg",
    "WaterMark",
    "Watermark",
    "BackgroundOverlay",
    "Backplate",
    "CategoriesBG",
    "BackgroundTile",
    "TopFiligree",
    "BottomFiligree",
    "FilligreeOverlay",
    "BorderTopLeft",
    "BorderTopMiddle",
    "BorderTopRight",
    "BorderLeftMiddle",
    "BorderRightMiddle",
    "BorderBottomLeft",
    "BorderBottomMiddle",
    "BorderBottomRight",
}
function Skin.FadeKeyedArt(widget, depth)
    depth = depth or 0
    if not widget or depth > 6 or widget:IsForbidden() then
        return
    end
    if Skin.IsArtExempt(widget) then
        return
    end
    if depth > 0 and Skin.IsForeignFrame(widget) then
        return
    end
    for _, key in ipairs(BG_ART_KEYS) do
        local t = widget[key]
        if t and t.IsObjectType and t:IsObjectType("Texture") then
            t:SetAlpha(0)
        end
    end
    if not widget.GetChildren then
        return
    end
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        Skin.FadeKeyedArt(children[idx], depth + 1)
    end
end

local ART_KEYWORDS = {
    "background",
    "corner",
    "parchment",
    "watermark",
    "shadow",
    "divider",
    "nineslice",
    "wood",
    "metal",
    "modelbackground",
    "-bg",
    "bg-",
    "frametexture",
    "sheen",
    "plaque",
    "tile",
    "marble",
    "stone",
    "filigree",
}
local function texIsIcon(hay)
    return hay and (hay:find("interface\\icons", 1, true) or hay:find("interface/icons", 1, true))
end
local function texHay(texture)
    local atlas = texture.GetAtlas and texture:GetAtlas()
    if atlas and not issecretvalue(atlas) then
        return atlas:lower()
    end
    local file = texture.GetTexture and texture:GetTexture()
    if type(file) == "string" then
        return file:lower()
    end
    return nil
end
Skin.TexHay = texHay
Skin.TexIsIcon = texIsIcon

-- Alpha decorative art under a frame by keyword, keeping icons and our own
-- textures. Depth-capped; call at skin time or from debounced hooks only.
function Skin.FadeArtIn(widget, depth)
    depth = depth or 0
    if not widget or depth > 9 or not widget.GetRegions or widget:IsForbidden() then
        return
    end
    if Skin.IsArtExempt(widget) then
        return
    end
    if depth > 0 and Skin.IsForeignFrame(widget) then
        return
    end
    local mybg = FFD[widget] and FFD[widget].bg
    local regionList = { widget:GetRegions() }
    for idx = 1, #regionList do
        local region = regionList[idx]
        if region and region ~= mybg and region.IsObjectType and region:IsObjectType("Texture") and (region:GetAlpha() or 0) > 0 then
            local hay = texHay(region)
            if hay and not texIsIcon(hay) then
                for _, kw in ipairs(ART_KEYWORDS) do
                    if hay:find(kw, 1, true) then
                        region:SetAlpha(0)
                        break
                    end
                end
            end
        end
    end
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        Skin.FadeArtIn(children[idx], depth + 1)
    end
end

-- Flatten classic 3-slice buttons (Left+Middle+Right) under a frame. Never
-- touches icon buttons. One-time per button; call at skin time.
function Skin.ButtonsIn(widget, depth)
    depth = depth or 0
    if not widget or depth > 9 or not widget.GetChildren or widget:IsForbidden() then
        return
    end
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        local childFrame = children[idx]
        if childFrame and not Skin.IsForeignFrame(childFrame, widget) then
            if
                childFrame.GetObjectType
                and childFrame:GetObjectType() == "Button"
                and not GetFFD(childFrame).skinned
                and not GetFFD(childFrame).x
                and childFrame.Left
                and childFrame.Middle
                and childFrame.Right
            then
                Skin.Button(childFrame)
            end
            Skin.ButtonsIn(childFrame, depth + 1)
        end
    end
end

-- Search boxes and filter/sort dropdowns are created with a parentKey and no
-- global name, so they are found by their parent's field name. EditBoxes get
-- the input treatment, everything else the flat dropdown block + house arrow.
local CONTROL_KEYS = {
    "SearchBox",
    "searchBox",
    "FilterDropdown",
    "FilterButton",
    "TypeDropdown",
    "Dropdown",
    "ClassDropdown",
    "WeaponDropdown",
}
function Skin.ControlsIn(widget, depth)
    depth = depth or 0
    if not widget or depth > 9 or not widget.GetChildren or widget:IsForbidden() then
        return
    end
    if depth > 0 and Skin.IsForeignFrame(widget) then
        return
    end
    for _, key in ipairs(CONTROL_KEYS) do
        local el = widget[key]
        if el and el.IsObjectType and el.GetObjectType then
            if el:IsObjectType("EditBox") then
                Skin.EditBox(el)
            else
                Skin.Dropdown(el)
            end
        end
    end
    local children = { widget:GetChildren() }
    for idx = 1, #children do
        Skin.ControlsIn(children[idx], depth + 1)
    end
end

-- Common chrome for a framed panel: close button, search/filter controls,
-- page nav, scroll bars.
function Skin.CommonChrome(widget, prefixText, explicitControls)
    if widget.CloseButton then
        Skin.CloseButton(widget.CloseButton)
    end
    -- Newer templates hang the X off the title bar (or name it ClosePanelButton)
    -- instead of putting it on the frame -- the loot window is one of them, and
    -- it kept Blizzard's red X until these two paths were added.
    if widget.TitleContainer and widget.TitleContainer.CloseButton then
        Skin.CloseButton(widget.TitleContainer.CloseButton)
    end
    if widget.ClosePanelButton then
        Skin.CloseButton(widget.ClosePanelButton)
    end
    if prefixText then
        local cb = _G[prefixText .. "CloseButton"]
        if cb then
            Skin.CloseButton(cb)
        end
    end
    if not explicitControls then
        Skin.ControlsIn(widget)
        Skin.PagingIn(widget)
        Skin.ScrollBarsIn(widget)
    end
    -- Re-center the title: PortraitFrameTemplate anchors it relative to the
    -- (removed) portrait + close button, so it lands a few px off the frame's
    -- true center. Center it on the shell top bar instead. One-shot.
    local skinData = GetFFD(widget)
    if not skinData.titleCentered and skinData.topBar then
        local titleText = (widget.TitleContainer and widget.TitleContainer.TitleText)
            or widget.TitleText
            or (prefixText and _G[prefixText .. "TitleText"])
        if titleText and titleText.ClearAllPoints then
            skinData.titleCentered = true
            titleText:ClearAllPoints()
            titleText:SetPoint("CENTER", skinData.topBar, "CENTER", 0, 0)
            if titleText.SetJustifyH then
                titleText:SetJustifyH("CENTER")
            end
        end
    end
end

-- One-time re-skin hook on a frame's Show (visual repaint catch-all).
function Skin.HookShow(widget, func)
    local skinData = GetFFD(widget)
    if skinData.showHook then
        return
    end
    skinData.showHook = true
    widget:HookScript("OnShow", func)
end

-- A common-sidetab side tab (the WoW Forever Looking For Group and Progress
-- Legacy windows): the gold frame and glow go, the icon stays. A black copy of
-- the hover art is the idle border; hover (gold) and active (soft white) draw over it.
function Skin.SideTab(tabBtn)
    if not tabBtn then
        return
    end
    if tabBtn.Background then
        tabBtn.Background:SetAlpha(0)
    end
    if tabBtn.TabGlow then
        tabBtn.TabGlow:SetAlpha(0)
    end
    local st = tabBtn.SelectedTexture
    if not st then
        return
    end
    local skinData = GetFFD(tabBtn)
    if not skinData.tabBorder then
        local button = tabBtn:CreateTexture(nil, "OVERLAY", nil, -1)
        button:SetAtlas("common-sidetab-hover")
        button:SetAllPoints(st)
        button:SetVertexColor(0, 0, 0)
        skinData.tabBorder = button
    end
    st:SetVertexColor(0.90, 0.90, 0.92)
end

-- Debounce: collapse many hook fires in one frame into a single pass.
function Skin.Debounce(func)
    if registrationWindow then
        func = Skin.WindowCallback(registrationWindow, func)
    end
    local pending = false
    return function()
        if pending then
            return
        end
        pending = true
        if C_Timer then
            C_Timer.After(0, function()
                pending = false
                func()
            end)
        else
            pending = false
            func()
        end
    end
end

-------------------------------------------------------------------------------
--  Per-window boot. Packs register { key, addons = {...}, apply = fn } and the
--  engine applies them when their Blizzard addon loads (or at login for ones
--  already loaded). Gated on the window style ("off" = never runs) and
--  pcall-isolated so one pack can never break another.
-------------------------------------------------------------------------------
local _windows = {}

local function WindowOn(winKey)
    return Skin.GetStyle(winKey) ~= "off"
end

local function TryApply(record)
    if not WindowOn(record.key) then
        return
    end
    if not Theme.fontPath then
        ResolveTheme()
    end
    local success, err = pcall(record.apply)
    if not success and err then
        -- Surface through the normal error pipeline (respects scriptErrors)
        -- without stopping the other window packs.
        geterrorhandler()(err)
    end
end

function Skin.RegisterWindow(record)
    _windows[#_windows + 1] = record
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(_, evt, name)
    if evt == "PLAYER_LOGIN" then
        ResolveTheme()
        for _, record in ipairs(_windows) do
            -- Immediate windows (no LoD addon) and any LoD addon that is
            -- already loaded get skinned now.
            local ready = true
            if record.addons then
                for addon in pairs(record.addons) do
                    if not (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded(addon)) then
                        ready = false
                        break
                    end
                end
            end
            if ready then
                TryApply(record)
            end
        end
        Skin.RefreshStyles()
    elseif evt == "ADDON_LOADED" then
        for _, record in ipairs(_windows) do
            if record.addons and record.addons[name] then
                TryApply(record)
            end
        end
    end
end)
