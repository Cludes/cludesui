if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_UICore.lua
--  Always-resident UI primitives consumed by BOTH runtime code (bags, meters,
--  skins, minimap, login popups) and the options surface: widget tooltip,
--  disabled-tooltip wrapper, styled buttons, accent/theme/profile-accent
--  system, pooled context menu. Lives in the parent, before
--  CludesUI_Widgets.lua, so runtime callers keep working when the options
--  surface is LoadOnDemand.
-------------------------------------------------------------------------------

local Pix = CludesUI.PanelPP
local SolidTex = CludesUI.SolidTex
local MakeFont = CludesUI.MakeFont
local MakeBorder = CludesUI.MakeBorder
local CLUDES_GREEN = CludesUI.CLUDES_GREEN

-- Button visual constants
local BTN_BG_R = CludesUI.BTN_BG_R
local BTN_BG_G = CludesUI.BTN_BG_G
local BTN_BG_B = CludesUI.BTN_BG_B
local BTN_BG_A = CludesUI.BTN_BG_A
local BTN_BG_HA = CludesUI.BTN_BG_HA
local BTN_BRD_A = CludesUI.BTN_BRD_A
local BTN_BRD_HA = CludesUI.BTN_BRD_HA
local BTN_TXT_A = CludesUI.BTN_TXT_A
local BTN_TXT_HA = CludesUI.BTN_TXT_HA

-------------------------------------------------------------------------------
--  Styled Buttons
-------------------------------------------------------------------------------

-- Style a button frame with bg/border/label + hover scripts.
-- colours = { bg_r,bg_g,bg_b,bg_a, bg_hr,bg_hg,bg_hb,bg_ha,
--             brd_r,brd_g,brd_b,brd_a, brd_hr,brd_hg,brd_hb,brd_ha,
--             txt_r,txt_g,txt_b,txt_a, txt_hr,txt_hg,txt_hb,txt_ha }
-- square (optional): the square outline, for a window that is square by design.
local function MakeStyledButton(btn, textValue, fontSize, colours, onClick, square)
    local c = colours
    local backdrop = SolidTex(btn, "BACKGROUND", c[1], c[2], c[3], c[4])
    backdrop:SetAllPoints()
    local brd
    if square then
        brd = MakeBorder(btn, c[9], c[10], c[11], c[12], Pix)
    else
        brd = CludesUI.MakeRoundedBorder(btn, c[9], c[10], c[11], c[12], backdrop)
    end
    local labelFS = MakeFont(btn, fontSize, nil, c[17], c[18], c[19])
    -- The resting alpha lives in the text colour, as the hover scripts below set it
    -- (a region alpha on top would multiply with it after the first hover).
    labelFS:SetTextColor(c[17], c[18], c[19], c[20])
    labelFS:SetPoint("CENTER")
    labelFS:SetText(CludesUI.L(textValue))
    btn:SetScript("OnEnter", function()
        labelFS:SetTextColor(c[21], c[22], c[23], c[24])
        brd:SetColor(c[13], c[14], c[15], c[16])
        backdrop:SetColorTexture(c[5], c[6], c[7], c[8])
    end)
    btn:SetScript("OnLeave", function()
        labelFS:SetTextColor(c[17], c[18], c[19], c[20])
        brd:SetColor(c[9], c[10], c[11], c[12])
        backdrop:SetColorTexture(c[1], c[2], c[3], c[4])
    end)
    btn:SetScript("OnClick", function()
        if onClick then
            onClick()
        end
    end)
    return backdrop, brd, labelFS
end

-- Pre-built colour arrays for the two button styles
local WB_COLOURS = { -- Button hover style
    BTN_BG_R,
    BTN_BG_G,
    BTN_BG_B,
    BTN_BG_A,
    BTN_BG_R,
    BTN_BG_G,
    BTN_BG_B,
    BTN_BG_HA,
    1,
    1,
    1,
    BTN_BRD_A,
    1,
    1,
    1,
    BTN_BRD_HA,
    1,
    1,
    1,
    BTN_TXT_A,
    1,
    1,
    1,
    BTN_TXT_HA,
}
local RB_COLOURS = {
    BTN_BG_R,
    BTN_BG_G,
    BTN_BG_B,
    BTN_BG_A,
    BTN_BG_R,
    BTN_BG_G,
    BTN_BG_B,
    BTN_BG_HA,
    1,
    1,
    1,
    BTN_BRD_A,
    1,
    1,
    1,
    BTN_BRD_HA,
    1,
    1,
    1,
    BTN_TXT_A,
    1,
    1,
    1,
    BTN_TXT_HA,
}

CludesUI.MakeStyledButton = MakeStyledButton
CludesUI.WB_COLOURS = WB_COLOURS
CludesUI.RB_COLOURS = RB_COLOURS

-------------------------------------------------------------------------------
--  One-time tip callout
-------------------------------------------------------------------------------
-- A dark box with the accent border, a message, an Okay button and an arrow
-- pointing at what it explains (the options sidebar's Unlock Mode tip, Unlock
-- Mode's own first-open tip, the bag sidebar's category tip). Built hidden:
-- the caller anchors (and, on UIParent, scales) it and shows it, faded in by
-- CludesUI.ShowTipCallout. Okay hides it, then runs opts.onOkay (where the
-- caller stores its seen flag).
-- opts: width, height (nil = fit the content: textTop, the text, gap, the
-- button and btnBottom), text (already translated, so the call site keeps its
-- literal key for the locale extractor),
-- onOkay, arrow ("top", the default: the box sits below its target; "bottom":
-- the box sits above it; "left": the box sits right of it), arrowOffset (px
-- along that edge from its centre), pp (default PanelPP), strata (default FULLSCREEN_DIALOG; false
-- keeps the parent's), level (default 200), font (a path; default the panel
-- font), fontFlags (with font; default none), fontSize (12), textTop (17),
-- textInset (30), spacing (6), gap (12, text to button with a fitted height),
-- bgAlpha (1), btnW (86), btnH (26), btnBottom (13), btnFontSize (11).
local TIP_BG_R, TIP_BG_G, TIP_BG_B = 0.062, 0.070, 0.082
local TIP_ARROW = 16

local function TipArrowTex(holderFrame, drawLayer, flyout, size, red, green, blue, a)
    local tex = holderFrame:CreateTexture(nil, drawLayer, nil, flyout)
    tex:SetSize(size, size)
    tex:SetPoint("CENTER")
    tex:SetColorTexture(red, green, blue, a)
    tex:SetRotation(math.rad(45))
    if tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(false)
        tex:SetTexelSnappingBias(0)
    end
    return tex
end

function CludesUI.BuildTipCallout(hostFrame, options)
    local pp = options.pp or Pix
    local strata = options.strata
    if strata == nil then
        strata = "FULLSCREEN_DIALOG"
    end
    local accent = CludesUI.CLUDES_GREEN
    local ar, ag, ab = accent.r, accent.g, accent.b
    local bgA = options.bgAlpha or 1
    local wid = options.width

    local tipText = CreateFrame("Frame", nil, hostFrame)
    if strata then
        tipText:SetFrameStrata(strata)
    end
    tipText:SetFrameLevel(options.level or 200)
    tipText:SetWidth(wid)
    tipText:EnableMouse(true)
    tipText:Hide()
    SolidTex(tipText, "BACKGROUND", TIP_BG_R, TIP_BG_G, TIP_BG_B, bgA):SetAllPoints()
    MakeBorder(tipText, ar, ag, ab, 0.25, pp)

    -- The arrow: a rotated square whose inner half the box edge clips away
    local off = options.arrowOffset or 0
    local clip = CreateFrame("Frame", nil, tipText)
    if strata then
        clip:SetFrameStrata(strata)
    end
    clip:SetFrameLevel(tipText:GetFrameLevel() + 10)
    clip:SetClipsChildren(true)
    local holderFrame = CreateFrame("Frame", nil, clip)
    holderFrame:SetFrameLevel(clip:GetFrameLevel() + 1)
    holderFrame:SetSize(TIP_ARROW + 4, TIP_ARROW + 4)
    if options.arrow == "left" then
        clip:SetSize(TIP_ARROW, TIP_ARROW * 2)
        clip:SetPoint("RIGHT", tipText, "LEFT", 1, off)
        holderFrame:SetPoint("CENTER", clip, "RIGHT", 0, 0)
    elseif options.arrow == "bottom" then
        clip:SetSize(TIP_ARROW * 2, TIP_ARROW)
        clip:SetPoint("TOP", tipText, "BOTTOM", off, 1)
        holderFrame:SetPoint("CENTER", clip, "TOP", 0, 0)
    else
        clip:SetSize(TIP_ARROW * 2, TIP_ARROW)
        clip:SetPoint("BOTTOM", tipText, "TOP", off, -1)
        holderFrame:SetPoint("CENTER", clip, "BOTTOM", 0, 0)
    end
    TipArrowTex(holderFrame, "ARTWORK", 7, TIP_ARROW + 2, ar, ag, ab, 0.18)
    TipArrowTex(holderFrame, "OVERLAY", 6, TIP_ARROW, TIP_BG_R, TIP_BG_G, TIP_BG_B, bgA)

    local size = options.fontSize or 12
    local msg
    if options.font then
        msg = tipText:CreateFontString(nil, "OVERLAY")
        msg:SetFont(options.font, size, options.fontFlags or "")
        msg:SetTextColor(1, 1, 1, 0.85)
    else
        msg = MakeFont(tipText, size, nil, 1, 1, 1, 0.85)
    end
    local textTop = options.textTop or 17
    msg:SetPoint("TOP", tipText, "TOP", 0, -textTop)
    msg:SetWidth(wid - (options.textInset or 30))
    msg:SetJustifyH("CENTER")
    msg:SetSpacing(options.spacing or 6)
    msg:SetText(options.text)

    local btnH, btnBottom = options.btnH or 26, options.btnBottom or 13
    local hgt = options.height
    if not hgt then
        hgt = math.ceil(textTop + msg:GetStringHeight() + (options.gap or 12) + btnH + btnBottom)
    end
    pp.Size(tipText, wid, hgt)

    local success = CreateFrame("Button", nil, tipText)
    success:SetSize(options.btnW or 86, btnH)
    success:SetPoint("BOTTOM", tipText, "BOTTOM", 0, btnBottom)
    local onOkay = options.onOkay
    MakeStyledButton(success, "Okay", options.btnFontSize or 11, RB_COLOURS, function()
        tipText:Hide()
        if onOkay then
            onOkay()
        end
    end)
    return tipText
end

-- Shows a tip callout with a 0.3 s fade in (its OnUpdate ends with the fade).
local function TipFadeIn(self, dt)
    local t = self._fadeT + dt
    if t >= 0.3 then
        self:SetAlpha(1)
        self:SetScript("OnUpdate", nil)
        return
    end
    self._fadeT = t
    self:SetAlpha(t / 0.3)
end
function CludesUI.ShowTipCallout(tipText)
    tipText._fadeT = 0
    tipText:SetAlpha(0)
    tipText:Show()
    tipText:SetScript("OnUpdate", TipFadeIn)
end

-- Global disabled-widget tooltip: "This option requires ___ to be enabled". requirement = human-readable name ("Show Class Power", "a non-None slot"). state = "enabled" (default) or "disabled" picks the trailing verb.
local function DisabledTooltip(requirement, state)
    -- Already a whole sentence: skip the wrapper but still translate it (the
    -- catalog keys whole sentences; L() is identity on English/missing key).
    if type(requirement) == "string" and requirement:find("^This option") then
        return CludesUI.L(requirement)
    end
    local verb = (state == "disabled") and "disabled" or "enabled"
    -- Positional template so wrapper sentence, requirement noun and verb each localize independently (translator controls word order).
    return CludesUI.Lf("This option requires %1$s to be %2$s", CludesUI.L(requirement), CludesUI.L(verb))
end
CludesUI.DisabledTooltip = DisabledTooltip

-------------------------------------------------------------------------------
--  Shared Tooltip  (single frame, lazily created, reused by all widgets)
-------------------------------------------------------------------------------
local tipFrame
-- The region the tooltip shows for (weak: never keeps it alive). The options page
-- pool reads it to drop the tooltip of a region it reset under the cursor.
local tooltipOwner = setmetatable({}, { __mode = "v" })
function CludesUI._WidgetTooltipOwner()
    return tooltipOwner[1]
end

local function GetTooltipFrame()
    if not tipFrame then
        tipFrame = CreateFrame("Frame", nil, UIParent)
        tipFrame:SetFrameStrata("TOOLTIP")
        tipFrame:SetFrameLevel(200)
        tipFrame:SetSize(250, 40)
        local backdrop = tipFrame:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        tipFrame.bg = backdrop
        MakeBorder(tipFrame, 1, 1, 1, 0.15, Pix)
        -- The panel font as a font family: the tooltip also shows friends' names
        -- and notes, whose scripts the panel font may lack.
        tipFrame.text = tipFrame:CreateFontString(nil, "OVERLAY")
        CludesUI.SetFontFamily(tipFrame.text, CludesUI.EXPRESSWAY, 10, "", false)
        tipFrame.text:SetTextColor(1, 1, 1, 0.80)
        tipFrame.text:SetPoint("TOPLEFT", 8, -8)
        tipFrame.text:SetPoint("TOPRIGHT", -8, -8)
        tipFrame.text:SetWordWrap(true)
        tipFrame.text:SetSpacing(3)
        tipFrame:Hide()
    end
    -- Unified user-customizable background (shared with the Blizzard tooltip reskin via GetTooltipBg), re-applied each call so a settings change shows on the next tooltip. Border is fixed (not customizable).
    tipFrame.bg:SetColorTexture(CludesUI.GetTooltipBg())
    return tipFrame
end

-- True when the anchor lives in the options panel or a registered popup (cog/confirm), so its tooltip rides the user's panel-scale slider. In-game anchors (bags, minimap, meters) stay at scale 1.
local function IsPanelFamilyAnchor(regionFrame)
    local mf = CludesUI._mainFrame
    local pops = CludesUI._popupFrames
    local node = regionFrame
    while node do
        if node == mf then
            return true
        end
        if pops then
            for idx = 1, #pops do
                if pops[idx].popup == node then
                    return true
                end
            end
        end
        node = node:GetParent()
    end
    return false
end

-- opts (optional): { color = {r,g,b}, width = number } overrides text colour / forces width
local function ShowWidgetTooltip(labelText, textValue, options)
    -- Suppress in M+/raid/PvP combat: frame APIs return secret values in tainted execution; opts.force bypasses.
    if not (options and options.force) then
        local _, iType = IsInInstance()
        if
            iType == "party"
            and C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
        then
            return
        end
        if iType == "raid" and InCombatLockdown() then
            return
        end
        if (iType == "pvp" or iType == "arena") and InCombatLockdown() then
            return
        end
    end
    -- text may be a function for dynamic text; resolved after suppression checks so it isn't called when nothing will show.
    if type(textValue) == "function" then
        textValue = textValue()
    end
    local tip = GetTooltipFrame()
    tooltipOwner[1] = labelText
    local MAX_W = 250
    local PAD = 8 -- horizontal padding each side (matches text anchor insets)
    if options and options.width then
        tip:SetWidth(options.width)
    else
        -- Natural single-line width is measured after Show, then clamped to MAX_W
        tip:SetWidth(MAX_W)
    end
    if options and options.color then
        tip.text:SetTextColor(options.color[1], options.color[2], options.color[3], options.color[4] or 0.80)
    else
        tip.text:SetTextColor(1, 1, 1, 0.80)
    end
    if options and options.justify then
        tip.text:SetJustifyH(options.justify)
    else
        tip.text:SetJustifyH("CENTER")
    end
    tip.text:SetText(CludesUI.L(textValue))
    -- Scale must be set before anchoring: the cursor branch divides by the tooltip's effective scale (reset to 1 in HideWidgetTooltip).
    local ttScaleMult = options and options.scale
    if not ttScaleMult then
        ttScaleMult = 1
        local us = CludesUIDB and CludesUIDB.panelScale
        if us and us ~= 1 and labelText and labelText.GetParent and IsPanelFamilyAnchor(labelText) then
            ttScaleMult = us
        end
    end
    tip:SetScale(ttScaleMult)
    tip:ClearAllPoints()
    if options and options.anchorPoint then
        -- Custom anchor: opts.anchorPoint on tooltip -> opts.anchorTo on label
        tip:SetPoint(
            options.anchorPoint,
            labelText,
            options.anchorTo or options.anchorPoint,
            options.anchorX or 0,
            options.anchorY or 0
        )
    elseif options and options.anchor == "cursor" then
        local scale = tip:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        tip:SetPoint("BOTTOM", UIParent, "BOTTOMLEFT", curX / scale, curY / scale + 4)
    elseif options and options.anchor == "below" then
        tip:SetPoint("TOP", labelText, "BOTTOM", 0, -4)
    elseif options and options.anchor == "left" then
        tip:SetPoint("RIGHT", labelText, "LEFT", -4, 0)
    elseif options and options.anchor == "right" then
        tip:SetPoint("LEFT", labelText, "RIGHT", 4, 0)
    else
        tip:SetPoint("BOTTOM", labelText, "TOP", 0, 4)
    end
    -- Show at alpha 0 BEFORE measuring: font geometry must be computed on a visible frame (GetStringHeight is wrong on hidden frames).
    tip:SetAlpha(0)
    tip:Show()
    -- Auto-size: natural text width + padding, capped at MAX_W
    if not (options and options.width) then
        local sw = tip.text:GetStringWidth()
        if issecretvalue and issecretvalue(sw) then
            tip:SetWidth(MAX_W)
        else
            local naturalW = sw + PAD * 2
            tip:SetWidth(math.min(naturalW, MAX_W))
        end
    end
    tip:SetHeight(10)
    local textH = tip.text:GetStringHeight()
    if issecretvalue and issecretvalue(textH) then
        tip:SetHeight(26)
    else
        tip:SetHeight(textH + 16)
    end
    -- Clamp to screen edges; skipped when frame metrics are secret (tainted M+)
    local ttScale = tip:GetEffectiveScale()
    local _ttLeft = tip:GetLeft()
    local _ttRight = tip:GetRight()
    local _isv = issecretvalue
    if not (_isv and (_isv(ttScale) or _isv(_ttLeft) or _isv(_ttRight))) then
        local screenW = GetScreenWidth() * UIParent:GetEffectiveScale()
        local ttLeft = (_ttLeft or 0) * ttScale
        local ttRight = (_ttRight or 0) * ttScale
        if ttLeft < 0 then
            local point, relTo, relPt, px, py = tip:GetPoint(1)
            if point then
                tip:SetPoint(point, relTo, relPt, (px or 0) - ttLeft / ttScale, py or 0)
            end
        elseif ttRight > screenW then
            local point, relTo, relPt, px, py = tip:GetPoint(1)
            if point then
                tip:SetPoint(point, relTo, relPt, (px or 0) - (ttRight - screenW) / ttScale, py or 0)
            end
        end
        local screenH = GetScreenHeight() * UIParent:GetEffectiveScale()
        local ttTop = (tip:GetTop() or 0) * ttScale
        local ttBottom = (tip:GetBottom() or 0) * ttScale
        if ttBottom < 0 then
            local point, relTo, relPt, px, py = tip:GetPoint(1)
            if point then
                tip:SetPoint(point, relTo, relPt, px or 0, (py or 0) - ttBottom / ttScale)
            end
        elseif ttTop > screenH then
            local point, relTo, relPt, px, py = tip:GetPoint(1)
            if point then
                tip:SetPoint(point, relTo, relPt, px or 0, (py or 0) - (ttTop - screenH) / ttScale)
            end
        end
    end
    -- Cancel an in-progress fade-out so its OnFinished doesn't hide us
    if tip._fadeOutAG then
        tip._fadeOutAG:Stop()
    end
    if tip._fadeAG then
        tip._fadeAG:Stop()
    end
    if not tip._fadeAG then
        tip._fadeAG = tip:CreateAnimationGroup()
        tip._fadeIn = tip._fadeAG:CreateAnimation("Alpha")
        tip._fadeIn:SetDuration(0.25)
        tip._fadeIn:SetSmoothing("OUT")
    end
    tip._fadeIn:SetFromAlpha(0)
    tip._fadeIn:SetToAlpha(1)
    tip._fadeAG:SetScript("OnFinished", function()
        tip:SetAlpha(1)
    end)
    tip._fadeAG:Play()
end

local function HideWidgetTooltip(instant)
    -- Never shown yet: nothing to hide, and nothing is built for it.
    local tip = tipFrame
    tooltipOwner[1] = nil
    if not (tip and tip:IsShown()) then
        return
    end
    if tip._fadeOutAG then
        tip._fadeOutAG:Stop()
    end
    if tip._fadeAG then
        tip._fadeAG:Stop()
    end
    if instant then
        tip:SetAlpha(0)
        tip:Hide()
        tip:SetScale(1)
        return
    end
    -- Fade out; the scale reset must wait until the fade completes, or the still-fading tooltip visibly resizes whenever panel scale ~= 1 (ShowWidgetTooltip re-sets the scale before anchoring anyway).
    if not tip._fadeOutAG then
        tip._fadeOutAG = tip:CreateAnimationGroup()
        tip._fadeOut = tip._fadeOutAG:CreateAnimation("Alpha")
        tip._fadeOut:SetDuration(0.25)
        tip._fadeOut:SetSmoothing("IN")
    end
    tip._fadeOut:SetFromAlpha(tip:GetAlpha())
    tip._fadeOut:SetToAlpha(0)
    tip._fadeOutAG:SetScript("OnFinished", function()
        tip:SetAlpha(0)
        tip:Hide()
        tip:SetScale(1)
    end)
    tip._fadeOutAG:Play()
end

CludesUI.ShowWidgetTooltip = ShowWidgetTooltip
CludesUI.HideWidgetTooltip = HideWidgetTooltip

-- Runs setup once: at PLAYER_LOGIN, or right away when the player is already
-- in (the options load on demand, after login).
function CludesUI.AtLogin(setup)
    local listener = CreateFrame("Frame")
    listener:RegisterEvent("PLAYER_LOGIN")
    listener:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_LOGIN")
        setup()
    end)
    if IsLoggedIn() then
        listener:GetScript("OnEvent")(listener)
    end
end

-- As AtLogin, for an options file's module registration: skipped when the
-- module registry does not exist by then.
function CludesUI.AtOptionsLogin(setup)
    CludesUI.AtLogin(function()
        if not CludesUI or not CludesUI.RegisterModule then
            return
        end
        setup()
    end)
end

-- The player's class colour as r, g, b (white when it cannot be read): the
-- getValue of the options' "Class Colored" swatches.
function CludesUI.PlayerClassRGB()
    local _, classFile = UnitClass("player")
    local cc = classFile and CludesUI.GetClassColor(classFile)
    if cc then
        return cc.r, cc.g, cc.b
    end
    return 1, 1, 1
end

-- Gives a widget a fixed hover tooltip, in place of any hover scripts it had. The show and hide go through CludesUI at hover
-- time, as a hand-written pair of scripts would.
function CludesUI.HoverTip(widget, text)
    widget:SetScript("OnEnter", function()
        CludesUI.ShowWidgetTooltip(widget, text)
    end)
    widget:SetScript("OnLeave", function()
        CludesUI.HideWidgetTooltip()
    end)
end

-------------------------------------------------------------------------------
--  Theme / Accent / Per-Profile Accent
-------------------------------------------------------------------------------

-- Theme API -- exposed so General Options can read/write
CludesUI.DEFAULT_ACCENT =
    { r = CludesUI.DEFAULT_ACCENT_R, g = CludesUI.DEFAULT_ACCENT_G, b = CludesUI.DEFAULT_ACCENT_B }

CludesUI.GetAccentColor = function()
    return CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b
end

--- Active theme name (default per client: CludesUI.DEFAULT_THEME)
CludesUI.GetActiveTheme = function()
    return CludesUIDB and CludesUIDB.activeTheme or CludesUI.DEFAULT_THEME
end

--- Internal: resolve the accent color for a given theme name
local function ResolveThemeColor(skinName)
    skinName = CludesUI._ResolveFactionTheme(skinName)
    if skinName == "Class Colored" then
        local clr = CludesUI.GetRawClassColor(CludesUI._playerClass)
        if clr then
            return clr.r, clr.g, clr.b
        end
        return CludesUI.DEFAULT_ACCENT_R, CludesUI.DEFAULT_ACCENT_G, CludesUI.DEFAULT_ACCENT_B
    elseif skinName == "Custom Color" then
        local sa = CludesUIDB and CludesUIDB.accentColor
        return sa and sa.r or CludesUI.DEFAULT_ACCENT_R,
            sa and sa.g or CludesUI.DEFAULT_ACCENT_G,
            sa and sa.b or CludesUI.DEFAULT_ACCENT_B
    else
        local preset = CludesUI.THEME_PRESETS[skinName]
        if preset then
            return preset.r, preset.g, preset.b
        end
        return CludesUI.DEFAULT_ACCENT_R, CludesUI.DEFAULT_ACCENT_G, CludesUI.DEFAULT_ACCENT_B
    end
end
CludesUI.ResolveThemeColor = ResolveThemeColor

--- Internal: snap accent to all registered one-time elements (no transition). Colour objects are reused to avoid per-tick allocations.
local _gradStart = CreateColor(0, 0, 0, 0)
local _gradEnd = CreateColor(0, 0, 0, 0)

local function UpdateAccentElements(red, green, blue)
    for _, record in ipairs(CludesUI._accentElements) do
        if record.type == "solid" and record.obj then
            record.obj:SetColorTexture(red, green, blue, record.a or 1)
        elseif record.type == "gradient" and record.obj then
            record.obj:SetColorTexture(red, green, blue, 1)
            _gradStart.r, _gradStart.g, _gradStart.b, _gradStart.a = red, green, blue, record.startA or 0.15
            _gradEnd.r, _gradEnd.g, _gradEnd.b, _gradEnd.a = red, green, blue, 0
            record.obj:SetGradient("HORIZONTAL", _gradStart, _gradEnd)
        elseif record.type == "vertex" and record.obj then
            record.obj:SetVertexColor(red, green, blue, 1)
        elseif record.type == "callback" and record.fn then
            record.fn(red, green, blue)
        end
    end
end

--- Internal: apply accent instantly (for color picker dragging, resets, etc.)
local function ApplyAccentLive(red, green, blue)
    -- Canonical colour table updated in place, then registered one-time elements
    CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b = red, green, blue
    UpdateAccentElements(red, green, blue)

    -- The cached confirm popup repaints its accent parts
    CludesUI._InvalidateConfirmPopup()

    -- Fast path only; a full rebuild would churn memory
    CludesUI:RefreshPage()
end

--- SetActiveTheme: persists and applies with an animated transition. Changes only the options panel background; accent colour is independent (accent swatch / class colour toggle).
CludesUI.SetActiveTheme = function(skinName)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    CludesUIDB.activeTheme = skinName
    CLUDES_GREEN._themeEnabled = true
    local red, green, blue = ResolveThemeColor(skinName)

    if CludesUI._applyThemeBG then
        CludesUI._applyThemeBG(skinName, red, green, blue)
    end
end

--- SetAccentColor: persists accent color (per-profile) and applies live.
CludesUI.SetAccentColor = function(red, green, blue)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    -- Persist on the active profile; the global root stays frozen as fallback.
    CludesUI.SetActiveProfileAccent({ r = red, g = green, b = blue }, false)
    ApplyAccentLive(red, green, blue)
end

--- Applies accent live without persisting (custom/class accent mode switches).
CludesUI.ApplyAccentColorLive = function(red, green, blue)
    ApplyAccentLive(red, green, blue)
end

-------------------------------------------------------------------------------
--  Per-profile UI accent color: lives per-profile as `cuiAccent`. Resolution
--  order: current profile's cuiAccent -> frozen global root -> theme color.
--  The global keys CludesUIDB.customAccentColor / useClassAccentColor stay
--  in SavedVariables permanently as that fallback and are NEVER written at
--  runtime, so profiles without cuiAccent keep their existing accent until
--  edited. The CUI Options Theme (activeTheme / panel background) is separate and global.
-------------------------------------------------------------------------------
function CludesUI.GetActiveProfileData()
    local saved = CludesUIDB
    if not saved or not saved.profiles then
        return nil
    end
    return saved.profiles[saved.activeProfile or "Default"]
end

-- Writer used by the accent swatch. `custom` and `useClass` are each optional; pass nil to leave unchanged.
function CludesUI.SetActiveProfileAccent(custom, useClass)
    local saved = CludesUIDB
    if not saved then
        return
    end
    saved.profiles = saved.profiles or {}
    local label = saved.activeProfile or "Default"
    local p = saved.profiles[label]
    if not p then
        p = {}
        saved.profiles[label] = p
    end
    p.cuiAccent = p.cuiAccent or {}
    if custom ~= nil then
        p.cuiAccent.custom = custom
    end
    if useClass ~= nil then
        p.cuiAccent.useClass = useClass
    end
end

-- Swatch display helper: CURRENT profile's accent state, falling back to the frozen global root. `~= nil` on the bool so profile useClass=false correctly overrides a global useClass=true.
function CludesUI.GetActiveAccentState()
    local p = CludesUI.GetActiveProfileData()
    local accent = p and p.cuiAccent
    local useClass
    if accent and accent.useClass ~= nil then
        useClass = accent.useClass
    else
        useClass = (CludesUIDB and CludesUIDB.useClassAccentColor) or false
    end
    local custom = (accent and accent.custom) or (CludesUIDB and CludesUIDB.customAccentColor)
    return useClass, custom
end

-- Accent for a given profile table. Returns useClass(bool), r, g, b. Order: profile cuiAccent -> frozen global root -> theme color (falling back to the default accent), which keeps a non-default theme with no custom accent looking unchanged.
function CludesUI.ResolveProfileAccent(profileData)
    local themeR, themeG, themeB = ResolveThemeColor(CludesUI.GetActiveTheme())
    local accent = profileData and profileData.cuiAccent
    -- 1) per-profile
    if accent and accent.useClass then
        local color = CludesUI.GetRawClassColor(CludesUI._playerClass)
        if color then
            return true, color.r, color.g, color.b
        end
    end
    if accent and accent.custom then
        local ca = accent.custom
        return false, ca.r or themeR, ca.g or themeG, ca.b or themeB
    end
    -- 2) frozen global root -- ONLY when the profile has no explicit cuiAccent. An explicit per-profile opt-out (useClass=false, no custom yet) must NOT fall through to the global class color; it drops to the global custom/theme terminal below, matching the displayed Custom swatch state.
    if (not accent) and CludesUIDB and CludesUIDB.useClassAccentColor then
        local color = CludesUI.GetRawClassColor(CludesUI._playerClass)
        if color then
            return true, color.r, color.g, color.b
        end
    end
    local gca = CludesUIDB and CludesUIDB.customAccentColor
    if gca then
        return false, gca.r or themeR, gca.g or themeG, gca.b or themeB
    end
    -- 3) theme color
    return false, themeR, themeG, themeB
end

-- Live accent RGB for the active profile (used at login / on profile swap).
function CludesUI.ResolveActiveAccent()
    local _, red, green, blue = CludesUI.ResolveProfileAccent(CludesUI.GetActiveProfileData())
    return red, green, blue
end

-- Single live re-apply entrypoint: re-resolves the active profile's accent and applies it to CLUDES_GREEN + all registered elements without persisting.
function CludesUI.RefreshAccent()
    local red, green, blue = CludesUI.ResolveActiveAccent()
    ApplyAccentLive(red, green, blue)
end

--- Class color for the current player
CludesUI.GetPlayerClassColor = function()
    local clr = CludesUI.GetRawClassColor(CludesUI._playerClass)
    if clr then
        return clr.r, clr.g, clr.b
    end
    return CludesUI.DEFAULT_ACCENT_R, CludesUI.DEFAULT_ACCENT_G, CludesUI.DEFAULT_ACCENT_B
end

--- Clears the saved custom accent, reverting to the theme default.
CludesUI.ResetAccentColor = function()
    if CludesUIDB then
        CludesUIDB.accentColor = nil
    end
    local skinName = CludesUI.GetActiveTheme()
    local red, green, blue = ResolveThemeColor(skinName)
    ApplyAccentLive(red, green, blue)
end

--- Wipes all style/theme settings back to defaults; called by the global "Reset to Defaults" button before ReloadUI().
CludesUI.ResetTheme = function()
    if not CludesUIDB then
        return
    end
    CludesUIDB.accentColor = nil
    CludesUIDB.activeTheme = nil
end

-------------------------------------------------------------------------------
--  ShowContextMenu(anchor, items, opts)
--  Shared pooled menu: the M+ Run Summary picker, the WoW Forever threat meter,
--  the Macros page. Pops up at the cursor.
--  items = { { text = "Foo", onClick = fn, isDisabled = fn? }, ... }
--  Opt-in item forms:
--    "---"               a separator line
--    isActive = true     accent label on a highlight while not hovered
--    tooltip = "..."     widget tooltip while hovered
--    children = { ... }  a submenu of items, opened on hover (arrow on the row)
--    isInput = true      a number box: getValue() fills it, Enter hands
--                        setValue(v) the whole number, floored at min (or 1)
--    icon = texture      a cropped 16px icon before the label
--    noLoc = true        the label as given (no L())
--    desc = "..."        a small grey line under the label (as given, no L())
--  opts (optional): below = true hangs the menu off `anchor`'s bottom-left edge
--  instead of the cursor (the dropdown placement of the options widgets);
--  minWidth widens the menu to the anchor's width so it reads as a dropdown.
--  above = true opens it upward, right edges aligned with `anchor` (growing
--  up from the cursor without one). look = "meter" is the Damage Meters header
--  menu's look: 22px rows, 11px plain (shadowless) labels, no inner padding,
--  the context-menu background and the Blizz UI Enhanced popup-menu border.
--  look = "meterForever" is its WoW Forever variant: the panel in WoW
--  Forever's dropdown art and gold lit labels (the meter look's panel on a
--  client without the art). fontKey sets the labels in that module's font,
--  through ApplyModuleFont unless the look keeps plain labels (else the
--  global font). scaleToAnchor = true gives the menu the anchor's effective
--  scale, for a list under a field of the options panel at its Window Scale
--  (a menu without children: submenus keep scale 1). pickOnDown = true makes
--  rows act on the press, so a pick lands before a focused edit box drops its
--  focus on the mouse down. noPoll = true leaves out the click-outside poll,
--  for a list its owner closes itself (one under an edit box, closed by the
--  box's focus loss).
--  Behavior: click-outside-to-dismiss (polled ~10hz unless noPoll); a second
--  call from the same anchor while its menu is open closes it (toggle);
--  auto-closes on combat entry so insecure clicks can't taint protected paths
--  while lockdown is active. One menu is open at a time: ContextMenuOwner()
--  returns its anchor, CloseContextMenu() closes it.
-------------------------------------------------------------------------------
local CTX_ARROW = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow.png"
-- Row metrics and dressing per look. Each look keeps its own panels: the
-- popup-menu border replaces a panel's own border for good.
local CTX_LOOKS = {
    default = {
        rowH = 26,
        sepH = 7,
        pad = 4,
        size = 12,
        minW = 140,
        textPad = 40,
        left = 10,
        right = -10,
    },
    meter = {
        rowH = 22,
        sepH = 7,
        pad = 0,
        size = 11,
        minW = 100,
        textPad = 50,
        left = 8,
        right = -18,
        noWrap = true,
        ctxBg = true,
        popupBorder = true,
        plainFont = true,
    },
    -- atlas: the panel's art in place of its fill and borders (drawn past
    -- its edges); lit: the hovered and active label colour.
    meterForever = {
        rowH = 22,
        sepH = 7,
        pad = 0,
        size = 11,
        minW = 100,
        textPad = 50,
        left = 8,
        right = -18,
        noWrap = true,
        ctxBg = true,
        popupBorder = true,
        plainFont = true,
        atlas = "common-dropdown-bg",
        lit = { r = 1, g = 0.82, b = 0 },
    },
}
local _ctxPanels = {} -- look -> its top-level panel
local _ctxOpen -- the top-level panel on screen, if any
local CtxShowSub

local function CtxRoot(panelFrame)
    return panelFrame._root or panelFrame
end

-- Lit: hovered or active.
local function CtxPaint(line, lit)
    line._hl:SetColorTexture(1, 1, 1, lit and (CludesUI.DD_ITEM_HL_A or 0.08) or 0)
    local ACC = lit and (line._panel._look.lit or CludesUI.CLUDES_GREEN)
    if ACC then
        line._lbl:SetTextColor(ACC.r, ACC.g, ACC.b, 1)
    else
        line._lbl:SetTextColor(1, 1, 1, 1)
    end
end

local function CtxRowEnter(line)
    local flyout = line._panel._sub
    if line._disabled then
        if flyout then
            flyout:Hide()
        end
        return
    end
    local entry = line._item
    CtxPaint(line, true)
    if entry.tooltip then
        CtxRoot(line._panel)._tip = true
        CludesUI.ShowWidgetTooltip(line, entry.tooltip)
    end
    if entry.children then
        CtxShowSub(line, entry.children)
    elseif flyout then
        flyout:Hide()
    end
end

local function CtxRowLeave(line)
    if line._disabled then
        return
    end
    local entry = line._item
    if entry.tooltip then
        CtxRoot(line._panel)._tip = nil
        CludesUI.HideWidgetTooltip()
    end
    CtxPaint(line, entry.isActive)
    -- A submenu stays open while the pointer moved into it.
    local flyout = line._panel._sub
    if flyout and entry.children and not (flyout:IsShown() and flyout:IsMouseOver()) then
        flyout:Hide()
    end
end

local function CtxRowClick(line)
    local entry = line._item
    if line._disabled or entry.children then
        return
    end
    CtxRoot(line._panel):Hide()
    if entry.onClick then
        entry.onClick()
    end
end

-- pickOnDown menus act on the press: a focused edit box drops its focus on
-- a mouse down outside it, before the row's click could land.
local function CtxRowDown(line, btnFrame)
    if btnFrame == "LeftButton" and CtxRoot(line._panel)._pickOnDown then
        CtxRowClick(line)
    end
end

local function CtxBoxCommit(checkBox)
    local entry = checkBox:GetParent()._item
    local val = math.max(entry.min or 1, math.floor(checkBox:GetNumber() + 0.5))
    checkBox:SetNumber(val)
    if entry.setValue then
        entry.setValue(val)
    end
    checkBox:ClearFocus()
end

local function CtxBoxEscape(checkBox)
    checkBox:ClearFocus()
end

-- Combat closes a menu: the event is registered only while it is shown.
local function CtxPanelShown(self)
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function CtxPanelHidden(self)
    self:SetScript("OnUpdate", nil)
    -- Hidden along with UIParent (Alt-Z, a cinematic): a styled look closes
    -- for real; the default look stays shown and keeps its combat close.
    if self:IsShown() and self._look ~= CTX_LOOKS.default then
        self:Hide()
    end
    if not self:IsShown() then
        self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    end
    self._owner = nil
    self._src = nil
    local rowList = self._items
    for idx = 1, #rowList do
        local checkBox = rowList[idx]._box
        if checkBox then
            checkBox:ClearFocus()
        end
    end
    if self._sub then
        self._sub:Hide()
    end
    if _ctxOpen == self then
        _ctxOpen = nil
    end
    if self._tip then
        self._tip = nil
        CludesUI.HideWidgetTooltip()
    end
end

-- Unregister first: hiding a panel that is already invisible fires no OnHide.
local function CtxPanelEvent(self)
    self:UnregisterEvent("PLAYER_REGEN_DISABLED")
    self:Hide()
end

-- Throttled click-outside poll (~10hz), set on the top-level panel while shown.
local function CtxPoll(self, dt)
    self._elapsed = self._elapsed + dt
    if self._elapsed < 0.1 then
        return
    end
    self._elapsed = 0
    if self:IsMouseOver() or not IsMouseButtonDown("LeftButton") then
        return
    end
    -- A click on the owner is left to the owner: its OnClick reaches
    -- ShowContextMenu with the menu still open and toggles it closed.
    local ownerFrame = self._owner
    if ownerFrame and ownerFrame.IsMouseOver and ownerFrame:IsMouseOver() then
        return
    end
    local flyout = self._sub
    while flyout and flyout:IsShown() do
        if flyout:IsMouseOver() then
            return
        end
        flyout = flyout._sub
    end
    self:Hide()
end

local function CtxNewPanel(lookName, level)
    local RS = CludesUI.RESKIN or {}
    local p = CreateFrame("Frame", nil, UIParent)
    p:Hide()
    p:SetFrameStrata("FULLSCREEN_DIALOG")
    p:SetFrameLevel(200 + level * 10)
    p:SetClampedToScreen(true)
    p:EnableMouse(true)
    local backdrop = p:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(
        RS.BG_R or 0.067,
        RS.BG_G or 0.067,
        RS.BG_B or 0.067,
        lookName.ctxBg and (RS.CTX_ALPHA or 0.95) or (RS.QT_ALPHA or 0.97)
    )
    p._bg = backdrop
    local PP_L = CludesUI.PP
    if lookName.atlas and C_Texture.GetAtlasInfo(lookName.atlas) then
        local art = p:CreateTexture(nil, "BACKGROUND", nil, -1)
        art:SetAtlas(lookName.atlas)
        art:SetPoint("TOPLEFT", p, "TOPLEFT", -10, 7)
        art:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 10, -13)
        art:SetAlpha(0.925)
        backdrop:SetColorTexture(0, 0, 0, 0)
        p._art = art
    elseif PP_L and PP_L.CreateBorder then
        PP_L.CreateBorder(p, 1, 1, 1, RS.BRD_ALPHA or 0.18, 1)
    end
    p._look, p._level = lookName, level
    p._items = {}
    p._elapsed = 0
    p:SetScript("OnShow", CtxPanelShown)
    p:SetScript("OnHide", CtxPanelHidden)
    p:SetScript("OnEvent", CtxPanelEvent)
    return p
end

local function CtxRow(panelFrame, idx)
    local line = panelFrame._items[idx]
    if line then
        return line
    end
    local lookName = panelFrame._look
    line = CreateFrame("Button", nil, panelFrame)
    local highlight = line:CreateTexture(nil, "BACKGROUND", nil, 1)
    highlight:SetAllPoints()
    line._hl = highlight
    local labelFS = line:CreateFontString(nil, "OVERLAY")
    labelFS:SetPoint("RIGHT", line, "RIGHT", lookName.right, 0) -- LEFT: per item in CtxLayout
    labelFS:SetJustifyH("LEFT")
    if lookName.noWrap then
        labelFS:SetWordWrap(false)
    end
    line._lbl = labelFS
    line._panel = panelFrame
    line:SetScript("OnEnter", CtxRowEnter)
    line:SetScript("OnLeave", CtxRowLeave)
    line:SetScript("OnClick", CtxRowClick)
    line:SetScript("OnMouseDown", CtxRowDown)
    panelFrame._items[idx] = line
    return line
end

-- Separator line, submenu arrow, number box and item icon: made on a row's
-- first need.
local function CtxSep(line)
    local sep = line._sep
    if not sep then
        sep = line:CreateTexture(nil, "ARTWORK")
        sep:SetHeight(1)
        sep:SetPoint("LEFT", line, "LEFT", 6, 0)
        sep:SetPoint("RIGHT", line, "RIGHT", -6, 0)
        sep:SetColorTexture(1, 1, 1, 0.12)
        line._sep = sep
    end
    return sep
end

local function CtxArrow(line)
    local arrowTex = line._arrow
    if not arrowTex then
        arrowTex = line:CreateTexture(nil, "ARTWORK")
        arrowTex:SetTexture(CTX_ARROW)
        arrowTex:SetSize(19, 19)
        arrowTex:SetPoint("RIGHT", line, "RIGHT", -2, 0)
        arrowTex:SetRotation(math.pi / 2)
        line._arrow = arrowTex
    end
    return arrowTex
end

local function CtxBox(line, fontFile, outline)
    local checkBox = line._box
    if not checkBox then
        checkBox = CreateFrame("EditBox", nil, line)
        checkBox:SetSize(50, 18)
        checkBox:SetPoint("RIGHT", line, "RIGHT", -8, 0)
        checkBox:SetFrameLevel(line:GetFrameLevel() + 3)
        checkBox:SetFont(fontFile, 10, outline)
        checkBox:SetTextColor(1, 1, 1, 0.9)
        checkBox:SetJustifyH("CENTER")
        local backdrop = checkBox:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0, 0, 0, 0.4)
        checkBox:SetAutoFocus(false)
        checkBox:SetNumeric(true)
        checkBox:SetMaxLetters(5)
        checkBox:SetScript("OnEnterPressed", CtxBoxCommit)
        checkBox:SetScript("OnEscapePressed", CtxBoxEscape)
        line._box = checkBox
    end
    checkBox:SetFont(fontFile, 10, outline)
    return checkBox
end

-- the x on a row with onRemove: its own button, so the row's click still picks
local function CtxRemove(line)
    local removeBtn = line._rm
    if not removeBtn then
        removeBtn = CreateFrame("Button", nil, line)
        removeBtn:SetSize(16, 16)
        removeBtn:SetPoint("RIGHT", line, "RIGHT", -4, 0)
        removeBtn:SetFrameLevel(line:GetFrameLevel() + 2)
        removeBtn.icon = removeBtn:CreateTexture(nil, "OVERLAY")
        removeBtn.icon:SetAllPoints()
        removeBtn.icon:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-close.png")
        removeBtn.icon:SetAlpha(0.45)
        -- the row stays lit under its x, and the menu closing takes the x's tip with it
        removeBtn:SetScript("OnEnter", function(self)
            self.icon:SetAlpha(1)
            local r = self:GetParent()
            CtxPaint(r, true)
            local tipText = r._item.removeTip
            if tipText then
                CtxRoot(r._panel)._tip = true
                CludesUI.ShowWidgetTooltip(self, tipText)
            end
        end)
        removeBtn:SetScript("OnLeave", function(self)
            self.icon:SetAlpha(0.45)
            local r = self:GetParent()
            CtxRoot(r._panel)._tip = nil
            CludesUI.HideWidgetTooltip()
            CtxPaint(r, r._item.isActive)
        end)
        removeBtn:SetScript("OnClick", function(self)
            local r = self:GetParent()
            local func = r._item.onRemove
            CludesUI.HideWidgetTooltip()
            CtxRoot(r._panel):Hide()
            func()
        end)
        line._rm = removeBtn
    end
    return removeBtn
end

local function CtxIcon(line)
    local icon = line._icon
    if not icon then
        icon = line:CreateTexture(nil, "ARTWORK")
        icon:SetSize(16, 16)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        line._icon = icon
    end
    return icon
end

-- the small line under a label, made on first need
local function CtxDesc(line)
    local d = line._desc
    if not d then
        d = line:CreateFontString(nil, "OVERLAY")
        d:SetJustifyH("LEFT")
        d:SetWordWrap(false)
        line._desc = d
    end
    return d
end

local function CtxLayout(panelFrame, itemList, minW, fontKey)
    local lookName = panelFrame._look
    if
        lookName.popupBorder
        and not panelFrame._art
        and CludesUI._applyBlizzardConfiguredBorder
        and C_AddOns.IsAddOnLoaded("CludesUIBlizzardSkin")
    then
        pcall(CludesUI._applyBlizzardConfiguredBorder, panelFrame, "popupMenu", 1)
    end
    local L, size = CludesUI.L, lookName.size
    local fontFile, outline
    if fontKey then
        fontFile, outline = CludesUI.GetFontPath(fontKey), CludesUI.GetFontOutlineFlag(fontKey)
    else
        fontFile = (CludesUI.GetFontPath()) or STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
        outline = (CludesUI.GetFontOutlineFlag()) or ""
    end

    -- Hide pooled rows past the current item count
    local rowList = panelFrame._items
    for idx = 1, #rowList do
        rowList[idx]:Hide()
    end

    local mfs = panelFrame._measureFS
    if not mfs then
        mfs = panelFrame:CreateFontString(nil, "OVERLAY")
        panelFrame._measureFS = mfs
    end
    mfs:SetFont(fontFile, size, outline)
    local widest = 0
    local iconW = 0
    for _, entry in ipairs(itemList) do
        if type(entry) == "table" then
            mfs:SetText(entry.noLoc and entry.text or L(entry.text or ""))
            local wid = mfs:GetStringWidth() or 0
            if entry.onRemove then
                wid = wid + 20
            end
            if wid > widest then
                widest = wid
            end
            if entry.desc then
                mfs:SetFont(fontFile, size - 2, outline)
                mfs:SetText(entry.desc)
                wid = mfs:GetStringWidth() or 0
                if wid > widest then
                    widest = wid
                end
                mfs:SetFont(fontFile, size, outline)
            end
            if entry.icon then
                iconW = 22
            end
        end
    end
    mfs:SetText("")
    mfs:Hide()

    local pad = lookName.pad
    local width = math.max(minW or lookName.minW, widest + lookName.textPad + iconW)
    local posY = pad
    for idx, entry in ipairs(itemList) do
        local line = CtxRow(panelFrame, idx)
        local labelFS = line._lbl
        -- A row keeps the shadow a module font primed it with; clear it on
        -- the plain path.
        if fontKey and not lookName.plainFont then
            CludesUI.ApplyModuleFont(labelFS, fontFile, size, fontKey, outline)
            line._primed = true
        else
            if line._primed then
                CludesUI.PrimeFontShadow(labelFS, false)
                line._primed = nil
            end
            labelFS:SetFont(fontFile, size, outline)
        end
        line._hl:SetColorTexture(1, 1, 1, 0)
        if line._sep then
            line._sep:Hide()
        end
        if line._arrow then
            line._arrow:Hide()
        end
        if line._box then
            line._box:Hide()
        end
        if line._icon then
            line._icon:Hide()
        end
        if line._rm then
            line._rm:Hide()
        end
        if line._desc then
            line._desc:Hide()
        end
        local desc = type(entry) == "table" and entry.desc
        -- The label starts past the item's icon.
        labelFS:SetPoint(
            "LEFT",
            line,
            "LEFT",
            lookName.left + ((type(entry) == "table" and entry.icon) and 22 or 0),
            desc and 6 or 0
        )
        labelFS:SetPoint("RIGHT", line, "RIGHT", lookName.right, desc and 6 or 0)
        local hgt = desc and lookName.rowH + 10 or lookName.rowH
        if entry == "---" then
            hgt = lookName.sepH
            line._item, line._disabled = nil, true
            labelFS:SetText("")
            CtxSep(line):Show()
            line:EnableMouse(false)
        else
            line._item = entry
            labelFS:SetText(entry.noLoc and entry.text or L(entry.text or ""))
            if desc then
                local d = CtxDesc(line)
                d:SetFont(fontFile, size - 2, outline)
                d:SetPoint("TOPLEFT", labelFS, "BOTTOMLEFT", 0, -3)
                d:SetPoint("RIGHT", line, "RIGHT", lookName.right, 0)
                d:SetText(desc)
                d:SetTextColor(1, 1, 1, (entry.isDisabled and entry.isDisabled()) and 0.25 or 0.5)
                d:Show()
            end
            if entry.icon then
                local ic = CtxIcon(line)
                ic:SetPoint("LEFT", line, "LEFT", lookName.left, 0)
                ic:SetTexture(entry.icon)
                ic:Show()
            end
            if entry.isInput then
                line._disabled = true
                labelFS:SetTextColor(1, 1, 1, 1)
                line:EnableMouse(false)
                local checkBox = CtxBox(line, fontFile, outline)
                checkBox:SetNumber(entry.getValue and entry.getValue() or 0)
                checkBox:Show()
            else
                local disabled = entry.isDisabled and entry.isDisabled()
                line._disabled = disabled
                line:EnableMouse(true)
                if entry.children then
                    local arrowTex = CtxArrow(line)
                    arrowTex:SetVertexColor(1, 1, 1, disabled and 0.2 or 0.75)
                    arrowTex:Show()
                end
                if disabled then
                    labelFS:SetTextColor(0.4, 0.4, 0.4, 0.5)
                else
                    CtxPaint(line, entry.isActive)
                end
                if entry.onRemove and not disabled then
                    CtxRemove(line):Show()
                end
            end
        end
        line:SetSize(width - pad * 2, hgt)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", panelFrame, "TOPLEFT", pad, -posY)
        line:Show()
        posY = posY + hgt
    end
    panelFrame:SetSize(width, posY + pad)
end

-- Beside the row, flipped to its left when it would run off the screen.
CtxShowSub = function(line, children)
    local hostFrame = line._panel
    local flyout = hostFrame._sub
    if not flyout then
        flyout = CtxNewPanel(hostFrame._look, hostFrame._level + 1)
        flyout._root = CtxRoot(hostFrame)
        hostFrame._sub = flyout
    end
    -- Already showing this row's items: nothing changes while a menu is open.
    if flyout:IsShown() and flyout._src == children and flyout._srcRow == line then
        return
    end
    CtxLayout(flyout, children, nil, CtxRoot(hostFrame)._fontKey)
    flyout._src, flyout._srcRow = children, line
    flyout:ClearAllPoints()
    local right, screen = line:GetRight(), UIParent:GetRight()
    if right and screen and right + flyout:GetWidth() > screen then
        flyout:SetPoint("TOPRIGHT", line, "TOPLEFT", 0, 0)
    else
        flyout:SetPoint("TOPLEFT", line, "TOPRIGHT", 0, 0)
    end
    flyout:Show()
end

local function ShowContextMenu(anchor, itemList, options)
    -- Toggle: the owner's click while its own menu is open closes it.
    if anchor and _ctxOpen and _ctxOpen._owner == anchor then
        _ctxOpen:Hide()
        return
    end
    local lookName = CTX_LOOKS[options and options.look] or CTX_LOOKS.default
    local panelFrame = _ctxPanels[lookName]
    if not panelFrame then
        panelFrame = CtxNewPanel(lookName, 0)
        _ctxPanels[lookName] = panelFrame
    end
    if _ctxOpen and _ctxOpen ~= panelFrame then
        _ctxOpen:Hide()
    end
    if panelFrame._sub then
        panelFrame._sub:Hide()
    end
    panelFrame._owner = anchor
    panelFrame._fontKey = options and options.fontKey
    panelFrame._pickOnDown = options and options.pickOnDown
    -- The menu takes the anchor's effective scale (scaleToAnchor) or scale 1,
    -- before the layout and the cursor placement; a new scale snaps its border
    -- again. The applied scale is remembered: GetScale reads back a float32,
    -- which most ratios never equal.
    local menuScale = (options and options.scaleToAnchor and anchor)
            and anchor:GetEffectiveScale() / UIParent:GetEffectiveScale()
        or 1
    if (panelFrame._menuScale or 1) ~= menuScale then
        panelFrame._menuScale = menuScale
        panelFrame:SetScale(menuScale)
        CludesUI.PP.SetBorderSize(panelFrame, 1)
    end

    CtxLayout(panelFrame, itemList, options and options.minWidth, panelFrame._fontKey)

    panelFrame:ClearAllPoints()
    if options and options.below and anchor then
        -- Dropdown placement: under the anchor, left edges aligned (screen
        -- clamping still applies).
        panelFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    elseif options and options.above and anchor then
        panelFrame:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", 0, 0)
    else
        -- Position at cursor
        local scale = panelFrame:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        panelFrame:SetPoint(
            (options and options.above) and "BOTTOMLEFT" or "TOPLEFT",
            UIParent,
            "BOTTOMLEFT",
            curX / scale,
            curY / scale
        )
    end
    _ctxOpen = panelFrame
    panelFrame:Show()

    if options and options.noPoll then
        panelFrame:SetScript("OnUpdate", nil) -- the owner closes it
    else
        panelFrame._elapsed = 0
        panelFrame:SetScript("OnUpdate", CtxPoll)
    end
end

CludesUI.ShowContextMenu = ShowContextMenu

-- The open menu's anchor (nil when none is open or it sits at the cursor).
function CludesUI.ContextMenuOwner()
    return _ctxOpen and _ctxOpen._owner
end

function CludesUI.CloseContextMenu()
    if _ctxOpen then
        _ctxOpen:Hide()
    end
end

-------------------------------------------------------------------------------
--  Unit display names. WoW Forever characters carry a surname, which
--  UnitName hands back as its second value (retail: the realm), and
--  Blizzard's own frames show "First Last". Pass UnitName's two returns in:
--      CludesUI.WithSurname(UnitName(unit))
--  Retail gets the first value back unchanged. A secret name (protected
--  content) comes back as is, first name only: it cannot be inspected or
--  joined. Your own surname follows Blizzard's show-surname preference unless
--  ignorePreference is set.
--  Joined names are cached per name pair, so repaints build no strings.
-------------------------------------------------------------------------------
do
    local IS_FOREVER = CludesUI.IS_FOREVER == true
    local SEP = Constants
            and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR
        or " "
    local joined = {} -- [name][surname] = the display string

    function CludesUI.WithSurname(label, surname, ignorePreference)
        if not IS_FOREVER then
            return label
        end
        if issecretvalue(label) or issecretvalue(surname) then
            return label
        end
        if type(label) ~= "string" or type(surname) ~= "string" or surname == "" then
            return label
        end
        local PI = C_PlayerInfo
        if not ignorePreference and PI and PI.ShouldDisplaySurname and not PI.ShouldDisplaySurname() then
            local myName, mySurname = (UnitNameUnmodified or UnitName)("player")
            if label == myName and surname == mySurname then
                return label
            end
        end
        local line = joined[label]
        if not line then
            line = {}
            joined[label] = line
        end
        local full = line[surname]
        if not full then
            local tail = SEP .. surname
            -- Some units already carry it in the first value.
            full = (label:sub(-#tail) == tail) and label or (label .. tail)
            line[surname] = full
        end
        return full
    end

    -- True for your own unit on WoW Forever while Blizzard's "My Surname" (UnitSurnameOwn)
    -- is off, when your name is your first name alone: the [name:last] and [target:last]
    -- tags show nothing for it, so "[name:first] [name:last]" reads as the first name.
    function CludesUI.OwnSurnameHidden(unitToken)
        if not IS_FOREVER or not unitToken then
            return false
        end
        local PI = C_PlayerInfo
        if not (PI and PI.ShouldDisplaySurname) or PI.ShouldDisplaySurname() then
            return false
        end
        local isMe = UnitIsUnit(unitToken, "player")
        if issecretvalue(isMe) then
            return false
        end
        return isMe == true
    end

    -- Name Format, on every client:
    --     CludesUI.ShortName(name, mode)
    -- "first" / "last" keep one word, "abbr" turns every word but the last into
    -- an initial ("Illidan Stormrage" -> "I. Stormrage") and a number (a
    -- Character Count) keeps that many characters. Any other mode, nil and
    -- "full" included, keeps the whole name, as does a secret or non-string
    -- name. Words split at spaces and at the surname separator. Each mode caches
    -- 256 names, so repaints build no strings.
    --     CludesUI.IsNameFormat(mode)
    -- True for a mode that changes names (a module keys its own per-mode
    -- tables on these).
    --     CludesUI.Utf8Prefix(text, n)
    -- The first n characters of a plain string, or the string itself when it
    -- has n or fewer.
    do
        local floor = math.floor
        local short = { first = {}, last = {}, abbr = {} } -- [mode][name] = short form
        local total = { first = 0, last = 0, abbr = 0 }
        local sepPat = (SEP ~= " " and SEP ~= "") and SEP:gsub("%W", "%%%0") or nil

        local function Utf8Prefix(textValue, num)
            local bytes, idx, chars = #textValue, 1, 0
            while idx <= bytes do
                if chars == num then
                    return textValue:sub(1, idx - 1)
                end
                local b = textValue:byte(idx)
                idx = idx + ((b < 128 and 1) or (b < 224 and 2) or (b < 240 and 3) or 4)
                chars = chars + 1
            end
            return textValue
        end
        CludesUI.Utf8Prefix = Utf8Prefix

        local function IsCount(modeName)
            return type(modeName) == "number" and modeName >= 1 and modeName == floor(modeName)
        end
        function CludesUI.IsNameFormat(modeName)
            return short[modeName] ~= nil or IsCount(modeName)
        end

        function CludesUI.ShortName(label, modeName)
            if issecretvalue(label) or type(label) ~= "string" then
                return label
            end
            local cache = short[modeName]
            if not cache then
                -- A Character Count gets its cache on first use.
                if not IsCount(modeName) then
                    return label
                end
                cache = {}
                short[modeName], total[modeName] = cache, 0
            end
            local s = cache[label]
            if s then
                return s
            end
            local words = sepPat and label:gsub(sepPat, " ") or label
            if modeName == "first" then
                s = words:match("^%s*(%S+)")
            elseif modeName == "last" then
                s = words:match("(%S+)%s*$")
            elseif modeName == "abbr" then
                local parts = {}
                for word in words:gmatch("%S+") do
                    parts[#parts + 1] = word
                end
                if #parts >= 2 then
                    for idx = 1, #parts - 1 do
                        parts[idx] = Utf8Prefix(parts[idx], 1) .. "."
                    end
                    s = table.concat(parts, " ")
                end
            else
                -- No trailing space where the cut lands between two words.
                s = Utf8Prefix(words, modeName):match("^(.-)%s*$")
            end
            s = s or label
            if total[modeName] >= 256 then
                wipe(cache)
                total[modeName] = 0
            end
            cache[label] = s
            total[modeName] = total[modeName] + 1
            return s
        end

        -- The Name Format a unit's name takes:
        --     mode = CludesUI.UnitNameFormat(mode, unit)
        -- WoW Forever: First Name and Last Name part a character's name from
        -- its surname, so they shape players' names only; a mob's, an NPC's or
        -- a pet's name stays whole ("Rot Hide Gnoll" never reads "Rot"). Any
        -- other mode, and a nil unit (an options preview), comes back as given.
        -- Retail returns every mode as given: its player names are one word,
        -- so there these two modes only ever shorten other names.
        function CludesUI.UnitNameFormat(modeName, unitToken)
            if IS_FOREVER and unitToken and (modeName == "first" or modeName == "last") then
                local isPlayer = UnitIsPlayer(unitToken)
                if issecretvalue(isPlayer) or not isPlayer then
                    return nil
                end
            end
            return modeName
        end

        -- The Name Format choices, for every dropdown that sets one:
        --     values, order, getValue, setValue = CludesUI.NameFormatMenu(get, set, opts)
        -- get() returns the saved value; set(v) receives "first", "last",
        -- "full", "abbr" or a number. The Character Count entry opens a number
        -- popup and saves the number, which the dropdown then reads as "N
        -- Characters". A pick goes through setValue. opts (optional): onSaved
        -- runs after a count is saved, for a control the page refresh does not
        -- reach; enemies, for a text that can show enemy names, warns on retail
        -- that the game keeps those whole in restricted content (a popup after
        -- a pick, a red line in the count popup). Options pages only.
        --     CludesUI.NameFormatCogRow(get, set, opts)
        -- A settings-cog dropdown row over the same; "full" arrives as nil.
        -- opts.label replaces the row's "Name Format", opts.tooltip shows on
        -- its dropdown.
        local LABELS = { first = "First Name", last = "Last Name", full = "Full Name", abbr = "Abbreviated" }
        local ORDER = { "full", "first", "last", "abbr", "custom" }
        local MAX_COUNT = 99
        -- Wide enough for "Character Count" and its pencil on one line.
        local MENU_W = 160
        -- A saved count's label, made when a dropdown reads it.
        local COUNT_LABEL = {
            __index = function(_, key)
                if IsCount(key) then
                    return CludesUI.Lf("%1$d Characters", key)
                end
            end,
        }
        local function ParseCount(textValue)
            local num = tonumber(textValue)
            if num and num <= MAX_COUNT and IsCount(num) then
                return num
            end
        end
        local function EnemyNote()
            return CludesUI.L(
                "Enemies' names will still show their full names in restricted content (M+/Raid)."
            )
        end
        function CludesUI.NameFormatMenu(get, set, options)
            local onSaved = options and options.onSaved
            local warn = options and options.enemies and not CludesUI.IS_FOREVER
            local function Edit()
                local current = get()
                CludesUI:ShowInputPopup({
                    title = CludesUI.L("Character Count"),
                    message = CludesUI.L("Names show at most this many characters."),
                    redWarning = warn and EnemyNote() or nil,
                    placeholder = "1 - " .. MAX_COUNT,
                    initialText = IsCount(current) and tostring(current) or "",
                    numeric = true,
                    maxLetters = #tostring(MAX_COUNT),
                    validate = function(textValue)
                        if not ParseCount(textValue) then
                            return CludesUI.Lf("Enter a number from %1$d to %2$d.", 1, MAX_COUNT)
                        end
                    end,
                    onConfirm = function(textValue)
                        local num = ParseCount(textValue)
                        if not num then
                            return
                        end
                        set(num)
                        if onSaved then
                            onSaved()
                        end
                        CludesUI:RefreshPage()
                    end,
                })
            end
            local function SetValue(val)
                local old = get()
                set(val)
                if warn and val ~= "full" and val ~= old then
                    CludesUI:ShowConfirmPopup({
                        title = "Name Format",
                        message = EnemyNote(),
                        confirmText = "Okay",
                        hideCancel = true,
                    })
                end
            end
            local values = CludesUI.TextTags.MenuValues(LABELS, Edit, {
                text = "Character Count",
                selected = function()
                    return IsCount(get())
                end,
            })
            return setmetatable(values, COUNT_LABEL),
                ORDER,
                function()
                    return get() or "full"
                end,
                SetValue
        end
        CludesUI.NAME_FORMAT_MENU_W = MENU_W
        function CludesUI.NameFormatCogRow(get, set, options)
            local values, sequence, getValue, setValue = CludesUI.NameFormatMenu(get, function(val)
                set((val ~= "full") and val or nil)
            end, options)
            return {
                type = "dropdown",
                label = options and options.label or "Name Format",
                tooltip = options and options.tooltip,
                values = values,
                order = sequence,
                ddWidth = MENU_W,
                get = getValue,
                set = setValue,
            }
        end
    end
end

-------------------------------------------------------------------------------
--  Threat % text paint (WoW Forever only; nil on retail, where no caller runs).
--      CludesUI.PaintThreatPct(fs, pct, status, isTanking, colorByThreat)
--  Pass UnitDetailedThreatSituation's first three returns. The percent can be
--  secret and goes straight to SetFormattedText. Colour: white when
--  colorByThreat is off; the status colour while status is readable; else the
--  isTanking fold between the has-aggro and low-threat colours; else white.
--  Only the plain white mode is remembered per font string (never a value).
--      CludesUI.PaintThreatGap(fs, text, ahead, colorOn, aheadC, behindC)
--  The Threat Gap text: the formatted gap in aheadC or behindC by who leads,
--  or white while colorOn is off (the same white memory).
-------------------------------------------------------------------------------
if CludesUI.IS_FOREVER then
    local aggR, aggG, aggB, lowR, lowG, lowB, fold
    local white -- [fs] = true while its last paint was plain white (weak keys)

    local function PaintWhite(fontStr)
        if not white then
            white = setmetatable({}, { __mode = "k" })
        end
        if white[fontStr] then
            return
        end
        white[fontStr] = true
        fontStr:SetTextColor(1, 1, 1)
    end

    function CludesUI.PaintThreatPct(fontStr, pct, status, isTanking, colorByThreat)
        fontStr:SetFormattedText("%.0f%%", pct)
        if not colorByThreat then
            return PaintWhite(fontStr)
        end
        if type(status) == "number" and not issecretvalue(status) then
            fontStr:SetTextColor(GetThreatStatusColor(status))
        elseif type(isTanking) == "boolean" then
            if not fold then
                aggR, aggG, aggB = GetThreatStatusColor(3)
                lowR, lowG, lowB = GetThreatStatusColor(0)
                fold = C_CurveUtil.EvaluateColorValueFromBoolean
            end
            fontStr:SetTextColor(
                fold(isTanking, aggR, lowR),
                fold(isTanking, aggG, lowG),
                fold(isTanking, aggB, lowB)
            )
        else
            return PaintWhite(fontStr)
        end
        if white and white[fontStr] then
            white[fontStr] = nil
        end
    end

    function CludesUI.PaintThreatGap(fontStr, textValue, ahead, colorOn, aheadC, behindC)
        fontStr:SetText(textValue)
        if not colorOn then
            return PaintWhite(fontStr)
        end
        local color = ahead and aheadC or behindC
        fontStr:SetTextColor(color.r, color.g, color.b)
        if white and white[fontStr] then
            white[fontStr] = nil
        end
    end
end -- IS_FOREVER

-------------------------------------------------------------------------------
--  Controller support: ConsolePort interop and Blizzard's native gamepad
--  pointer. This header is the one comment in the suite that names that addon;
--  call sites say "controller cursor". The public cursor API of the addon is
--  the only thing used (its `ConsolePort` global, looked up live on every call
--  so load order never matters). Mouse/keyboard players pay one table lookup
--  or one C call at an edge that already runs (open, show, click, Escape):
--  nothing here registers an event, runs an OnUpdate or ticker, creates a
--  frame or writes SavedVariables unless a controller signal is present or
--  a feature follows PadConnected() through WatchPad (its three events stay
--  registered only while a watcher exists).
--    PadCP()                the controller UI addon's API table, or nil
--    PadNative()            Blizzard's gamepad is the active input right now
--    PadInUse()             PadCP() or PadNative(): the controller signal
--    PadConnected()         gamepad support is on and a controller is
--                           connected (not the last input: no mouse flicker)
--    PadModeOn()            what the controller hides follow: WoW Forever's
--                           Gamepad interface style, elsewhere PadConnected()
--    WatchPad(owner, fn)    fn(padOn) once per burst of PadModeOn() edges
--    UnwatchPad(owner)      stop following; the last one drops the events
--    PadGamepadUI()         WoW Forever's Gamepad interface style is on
--    RaiseGamePadCursor()   gamepad pointer on at a user-requested open
--    RegisterPadFrame(f)    a NAMED, hidden window root we own joins the
--                           controller cursor, once (never HUD frames)
--    PadHint(f, attr, v)    controller-cursor node attribute on OUR frame
--    PadCursorShown()       the controller cursor is on screen
--    PadFocus(node)         move the controller cursor onto node
--    OverlayParent()        parent for nameless screen-level overlays
--    TrackOverlay(f)        keep the overlay layer shown while f is
-------------------------------------------------------------------------------
do
    local IS_FOREVER = CludesUI.IS_FOREVER == true

    local function PadCP()
        local cp = _G.ConsolePort
        if type(cp) == "table" and cp.AddInterfaceCursorFrame then
            return cp
        end
    end

    -- The active-device query Blizzard documents beside GAME_PAD_ACTIVE_CHANGED;
    -- false while the mouse or keyboard was the last input.
    local function PadNative()
        return IsUsingGamepad() and C_GamePad.IsEnabled() or false
    end

    local function PadInUse()
        return PadCP() ~= nil or PadNative()
    end

    -- Connected, not in use: gamepad support is on (the GamePadEnable CVar)
    -- and a device reports a raw state, so touching the mouse never changes
    -- it. Read live; a feature that follows it registers through WatchPad
    -- below, never on the device events itself.
    local function PadConnected()
        if not C_GamePad.IsEnabled() then
            return false
        end
        for _, ident in ipairs(C_GamePad.GetAllDeviceIDs()) do
            if C_GamePad.GetDeviceRawState(ident) then
                return true
            end
        end
        return false
    end

    -- Forever's Gamepad interface style replaces the free pointer with D-pad
    -- navigation; read live (no event), false on retail. It gates what a
    -- controller cannot drive. A hook of ours on a Blizzard frame is no reason
    -- to stand down under it (the style's navigation runs its entry points
    -- securely and calls frame callbacks through securecallfunction), but a
    -- Blizzard menu whose owner drives a gamepad binding group is never opened
    -- from addon code there (the Minimap's tracking button).
    local function PadGamepadUI()
        if not IS_FOREVER then
            return false
        end
        local style, types = C_InputInterfaceStyle, Enum.InputDeviceInterfaceType
        return style ~= nil and types ~= nil and style.GetCurrentStyle() == types.Gamepad
    end

    -- What the controller hides (Global Settings > Gamepad) follow. On WoW
    -- Forever its Gamepad interface style: Blizzard's own gamepad bars and cast
    -- bar show only under it, so a controller left connected during keyboard and
    -- mouse play hides nothing. Elsewhere a connected controller.
    local function PadModeOn()
        if IS_FOREVER then
            return PadGamepadUI()
        end
        return PadConnected()
    end

    CludesUI.PadCP = PadCP
    CludesUI.PadNative = PadNative
    CludesUI.PadInUse = PadInUse
    CludesUI.PadConnected = PadConnected
    CludesUI.PadGamepadUI = PadGamepadUI
    CludesUI.PadModeOn = PadModeOn

    -- Following PadModeOn(): one shared watcher for every feature that hides
    -- or shows something with the controller. Its frame is built at the first
    -- WatchPad and holds its events only while at least one watcher exists:
    -- GAME_PAD_CONNECTED / GAME_PAD_DISCONNECTED and the GamePadEnable
    -- CVAR_UPDATE, or on WoW Forever the interface style's
    -- INPUT_DEVICE_INTERFACE_TRANSITION (the style reads right one frame later,
    -- when the flush runs). Edges come in bursts (a reconnect is DISCONNECTED
    -- then CONNECTED, a second pad adds its own, the CVar can land beside them),
    -- so a burst arms ONE flush next frame that reads PadModeOn() once and calls
    -- every watcher's fn(padOn). WatchPad never calls fn itself: the caller
    -- reads PadModeOn() when it starts watching. Watching again replaces fn.
    do
        -- The style transition, where the client knows it (an unknown event
        -- name errors at registration).
        local STYLE_EVENT = IS_FOREVER
                and not (C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(
                    "INPUT_DEVICE_INTERFACE_TRANSITION"
                ))
                and "INPUT_DEVICE_INTERFACE_TRANSITION"
            or nil
        local watchers, watchFrame, flushArmed, flushOwners

        local function FlushPad()
            flushArmed = nil
            if next(watchers) == nil then
                return
            end
            -- Snapshot first: a watcher may watch or unwatch while this runs.
            local num = 0
            for ownerFrame in pairs(watchers) do
                num = num + 1
                flushOwners[num] = ownerFrame
            end
            local enabled = PadModeOn()
            -- One failing watcher must not stop the rest (or strand the
            -- snapshot slots): report it and carry on.
            for idx = 1, num do
                local func = watchers[flushOwners[idx]]
                flushOwners[idx] = nil
                if func then
                    local success, err = pcall(func, enabled)
                    if not success then
                        geterrorhandler()(err)
                    end
                end
            end
        end

        local function OnPadEdge(_, evt, label)
            -- CVAR_UPDATE fires for every cvar, dozens of times at login.
            if evt == "CVAR_UPDATE" and label ~= "GamePadEnable" then
                return
            end
            if flushArmed then
                return
            end
            flushArmed = true
            C_Timer.After(0, FlushPad)
        end

        function CludesUI.WatchPad(ownerFrame, func)
            if ownerFrame == nil or not func then
                return
            end
            if not watchFrame then
                watchers, flushOwners = {}, {}
                watchFrame = CreateFrame("Frame")
                watchFrame:SetScript("OnEvent", OnPadEdge)
            end
            if next(watchers) == nil then
                if IS_FOREVER then
                    if STYLE_EVENT then
                        watchFrame:RegisterEvent(STYLE_EVENT)
                    end
                else
                    watchFrame:RegisterEvent("GAME_PAD_CONNECTED")
                    watchFrame:RegisterEvent("GAME_PAD_DISCONNECTED")
                    watchFrame:RegisterEvent("CVAR_UPDATE")
                end
            end
            watchers[ownerFrame] = func
        end

        function CludesUI.UnwatchPad(ownerFrame)
            if not watchers or ownerFrame == nil or watchers[ownerFrame] == nil then
                return
            end
            watchers[ownerFrame] = nil
            if next(watchers) == nil then
                watchFrame:UnregisterAllEvents()
            end
        end
    end

    -- Blizzard's own open-edge call (ShowUIPanel, the pause menu, single bags).
    -- Never turned off here: Back/Escape (CloseAllWindows) owns that edge. The
    -- controller UI addon drives the pointer itself, so it is left alone then.
    function CludesUI.RaiseGamePadCursor()
        if not CanAutoSetGamePadCursorControl(true) then
            return
        end
        if PadCP() or PadGamepadUI() then
            return
        end
        SetGamePadCursorControl(true)
    end

    -- Registration is remembered by name in the addon's saved data, so only
    -- stable global names; register once, while hidden, after the frame's last
    -- SetScript of OnShow/OnHide (the addon hooks those). Never remove one.
    local padRoots
    local POOL = CludesUI._Pool -- the core's pool table (CludesUI_PixelPerfect.lua)
    function CludesUI.RegisterPadFrame(frame)
        if not frame or not frame:GetName() then
            return
        end
        -- The addon hooks OnShow/OnHide once, and so does the escape-close
        -- registration (RegisterEscapeClose): on a frame of the options page pool
        -- those scripts survive the pool's resets, with or without the addon, so
        -- the code that dresses the frame sets them on its first dress only (dev
        -- mode reports a later one).
        if POOL and POOL.ExemptScripts then
            POOL.ExemptScripts(frame, "OnShow", "OnHide")
        end
        local cp = PadCP()
        if not cp then
            return
        end
        if not padRoots then
            padRoots = {}
        end
        if padRoots[frame] then
            return
        end
        padRoots[frame] = true
        cp:AddInterfaceCursorFrame(frame)
    end

    -- nodeignore / nodepass / nodepriority / hidekeyboard ... (v nil = true)
    function CludesUI.PadHint(frame, attr, val)
        if not frame or not PadCP() then
            return
        end
        if frame:IsProtected() and InCombatLockdown() then
            return
        end
        if val == nil then
            val = true
        end
        frame:SetAttribute(attr, val)
    end

    -- A hand-built modal popup of ours (a named dimmer over its panel) joins the
    -- controller cursor and answers controller Back from its first open with a
    -- controller in use; until then nothing is registered or hooked. The panel
    -- stays a blocker without being a cursor stop, closeBtn is what the
    -- controller's cancel button presses, and onEscape (nil = hide the dimmer) is
    -- what Back runs. Call it just before the dimmer's Show (the Cooldown
    -- Manager's popups, the Talent Conditions picker).
    function CludesUI.PadPopupOpen(dimmer, panelFrame, closeBtn, onEscape)
        if dimmer._padReg or not CludesUI.PadInUse() then
            return
        end
        dimmer._padReg = true
        CludesUI.PadHint(panelFrame, "nodepass")
        if closeBtn then
            panelFrame.CloseButton = closeBtn
        end
        CludesUI.RegisterEscapeClose(dimmer, { padOnly = true, onEscape = onEscape })
    end

    function CludesUI.PadCursorShown()
        local cp = PadCP()
        return (cp and cp:IsCursorActive()) and true or false
    end

    -- Only while the cursor is already on screen; a no-op otherwise.
    function CludesUI.PadFocus(node)
        local cp = PadCP()
        if cp and node then
            cp:SetCursorNodeIfActive(node)
        end
    end

    -- Overlay layer: nameless screen-level overlays (dropdown lists, cog
    -- popups, click-away catchers) cannot join the controller cursor, so while
    -- the controller UI addon is loaded they hang off one named full-screen
    -- layer that is shown exactly while one of them is. Without it the parent
    -- is UIParent and nothing else happens. Show/Hide/SetShown are post-hooked
    -- on the overlay (not OnShow: a child of a hidden layer never fires it, and
    -- dropdowns SetScript their OnShow/OnHide later).
    local drawLayer, overlayOpen, overlayTracked

    local function OverlaySync(frame)
        if frame:IsShown() and frame:GetParent() == drawLayer then
            overlayOpen[frame] = true
        else
            overlayOpen[frame] = nil
        end
        if next(overlayOpen) then
            if not drawLayer:IsShown() then
                drawLayer:Show()
            end
        elseif drawLayer:IsShown() then
            drawLayer:Hide()
        end
    end

    function CludesUI.OverlayParent()
        if drawLayer then
            return drawLayer
        end
        if not PadCP() then
            return UIParent
        end
        drawLayer = CreateFrame("Frame", "CludesUI_PadOverlayLayer", UIParent)
        drawLayer:SetAllPoints(UIParent)
        drawLayer:Hide()
        overlayOpen, overlayTracked = {}, {}
        CludesUI._overlayLayer = drawLayer
        CludesUI.RegisterPadFrame(drawLayer)
        return drawLayer
    end

    -- Every frame parented to OverlayParent() must be tracked (create it
    -- hidden, then call this after its scripts are set). No-op for any frame
    -- not parented to the layer.
    function CludesUI.TrackOverlay(frame)
        if not drawLayer or not frame or overlayTracked[frame] or frame:GetParent() ~= drawLayer then
            return
        end
        overlayTracked[frame] = true
        hooksecurefunc(frame, "Show", OverlaySync)
        hooksecurefunc(frame, "Hide", OverlaySync)
        hooksecurefunc(frame, "SetShown", OverlaySync)
        OverlaySync(frame)
    end
end
