if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_Quickdraw_View.lua
--
--  State the views share with the secure side, the slot visual, the module
--  font, the icon crop, the slot widget and the PaletteView basics.
--  Reads the earlier Quickdraw files through ns and ns._qdInternals.
-------------------------------------------------------------------------------
local _, mod = ...
local Inner = mod._qdInternals
-- CludesUIQuickdraw.lua or an earlier Quickdraw file failed to load.
if not Inner or Inner.broken then
    return
end
Inner.broken = true

local floor, max = math.floor, math.max
local sin, pi = math.sin, math.pi
local type = type

local PA, QUESTION_MARK, SelectColor = Inner.PA, Inner.QUESTION_MARK, Inner.SelectColor
local USABILITY_TINT = Inner.USABILITY_TINT

-------------------------------------------------------------------------------
--  Palette view  --  the renderer, instanced
--
--  Two instances exist: the live palette and the options-page preview. Sharing
--  one renderer is the whole point of the split -- the preview's entry order,
--  angles and hit test ARE the live palette's, so what the user arranges in the
--  panel is exactly what they steer at in play.
--
--  A view owns its container frame, the center hub, and a pool of MAX_SLOTS
--  slot widgets. It does NOT own interaction: the live palette drives itself from
--  ns.Open/ns.Close, and the preview installs its own scripts on the widgets it
--  gets back from GetSlotWidget.
-------------------------------------------------------------------------------
local views = {} -- every view, live and preview
-- One secure button per BOUND palette, indexed the same way. Declared here
-- rather than in the secure activation section: PaletteView:ArmedClaim reads a
-- claim's armed state off a palette's own button, and that is defined long
-- before the secure activation section builds any of them.
local secureButtons = {}

-- A held key whose up-event never reaches us (alt-tab, /reload prompt, a
-- taxi takeoff) would otherwise leave the palette on screen forever.
local OPEN_TIMEOUT = 30

-- The same backstop for a LATCHED palette (Toggle Menu Open), which has no key
-- held and is meant to sit there while the player decides. Long enough not to
-- pull the menu out from under that, short enough that one forgotten in a bank
-- does not hold the Select key -- which may well be a mouse button -- for the
-- rest of the session. See the confirm binding in SNIPPET_PRE.
local LATCH_TIMEOUT = 120

-- The mouse-button token the Select key's click arrives under. The palette's own
-- keybind clicks the same button as "LeftButton" (SetOverrideBindingClick's
-- default), so this is the whole of what tells a confirm click apart from a
-- palette-key click inside the snippet, which gets `button` and nothing else.
--
-- A real button name rather than an invented token: RegisterForClicks("AnyDown",
-- "AnyUp") covers it for certain, and the button has EnableMouse(false), so no
-- actual right-click can ever reach it and be mistaken for a confirm.
local CONFIRM_BUTTON = "RightButton"

-- ESCAPE out of a LATCHED menu, under a token of its own on the same button.
--
-- A held palette sends ESCAPE to the shared cancel button, which only raises a
-- flag -- the teardown then rides the key release that is always coming. A
-- latched menu has no such release, so its ESCAPE has to do the closing itself,
-- and doing it from the cancel button's Lua PostClick would leave the bindings
-- and the gates standing for the whole of any fight it happened during: every
-- one of those calls is protected. Routed HERE it is the palette button's own
-- release, so SNIPPET_POST performs the identical teardown it performs for
-- every other close, inside the sandbox, in combat or out.
local CANCEL_BUTTON = "MiddleButton"

-- Selection is drawn with two cues: the icon border takes the selection
-- color, and the entry grows. No additive glow -- at palette scale it bloomed
-- over the neighbouring entries and made the border it was supposed to
-- emphasise harder to read. Border weights are PHYSICAL pixels through the
-- suite's PP border system (PP.CreateBorder on each widget's bhost,
-- PP.UpdateBorder per state in ApplySlotVisual): idle and selected both 2,
-- the armed parent one heavier, drawn INSET over the icon's own edge and
-- crisp at any scale chain -- which a hand-stretched texture ring never was.
local SEL_BORDER = 2
local IDLE_BORDER = 2

-- The entry an ARMED claim hangs off. Selection says where the cursor is; this
-- says which nest is live, and the two part company the moment the cursor moves
-- on into the children -- the entry it came in through has to go on saying so,
-- because it is the only thing on screen that names the nest the release will
-- fire out of.
--
-- Derived from the selection color rather than from a setting of its own: the
-- same hue lifted toward white and drawn a pixel thicker. That reads as "more
-- than selected" at icon size while still sitting next to the selection color,
-- rather than introducing a second color the user would have to learn.
local ARM_BORDER = 3
local ARM_LIFT = 0.55

-- The magnification a selected entry is drawn at: 1, i.e. none -- reverted
-- off with the rest of the selection effects, pending the user's own
-- animation pass. Every call site multiplies by this, so it is the single
-- switch to bring the zoom back (SIZE-based, never scale -- see the note
-- above ApplySlotVisual).
local function SelectedZoom()
    return 1
end

-- Magnification is applied to the entry's SIZE, never its scale. SetPoint
-- offsets are read in the widget's own scaled space, so scaling an entry also
-- multiplies the offset it is anchored at -- and in the arc that offset carries
-- the radius, so selecting an entry threw it outward, out from under the very
-- cursor that had selected it, and the two states then flickered against each
-- other. Growing it in place moves nothing.
--
-- widget.baseSize is the unzoomed size the layout wants, published by whichever
-- geometry pass last placed the entry. Every steered layout rewrites its sizes
-- each frame and applies the zoom itself as it goes; this is what carries the
-- zoom across a selection CHANGE, and it is the whole of the answer on a view
-- that never steers -- the options preview, which draws a static arc.
--
-- armed marks the entry an armed claim hangs off, which may or may not also be
-- the selected one. The zoom stays a selection cue alone: an armed parent the
-- cursor has already left is not what a release would fire.
-- widget.usability is the state PaintCell last read for this cell (see
-- SlotUsability), applied here rather than there because these three branches
-- rewrite the icon's tint on every selection change and would erase it.
local function ApplySlotVisual(widget, selected, armed)
    -- The editor's centred "+" cell is drawn as the suite's picker add
    -- button: dark plate, thin gray border, accent "+" at 0.6 alpha, and on
    -- hover a doubled accent border with the "+" at full alpha -- not as an
    -- entry, which it is not. No zoom either: the add button holds its size
    -- under the cursor.
    if widget.isPlaceholder then
        local ar, ag, ab = 0.298, 0.788, 0.941
        if CludesUI.ResolveActiveAccent then
            ar, ag, ab = CludesUI.ResolveActiveAccent()
        end
        if selected then
            CludesUI.PP.UpdateBorder(widget.bhost, 2, ar, ag, ab, 1)
        else
            CludesUI.PP.UpdateBorder(widget.bhost, 1, 0.3, 0.3, 0.3, 0.5)
        end
        widget.bg:SetVertexColor(0.08, 0.08, 0.08, 0.6)
        widget.plus:SetTextColor(ar, ag, ab, selected and 1 or 0.6)
        if widget.baseSize then
            widget:SetSize(widget.baseSize, widget.baseSize)
        end
        return
    end

    local red, green, blue = SelectColor(widget.view:P())
    -- The unusable tint MULTIPLIES whatever the selection state asked for, so
    -- an out-of-range entry the cursor is on still reads as the selected one.
    local tint = USABILITY_TINT[widget.usability or ""]
    local ur, ug, ub = 1, 1, 1
    if tint then
        ur, ug, ub = tint[1], tint[2], tint[3]
    end
    widget.icon:SetDesaturated(tint ~= nil and tint[4] or false)
    local t = armed and ARM_BORDER or selected and SEL_BORDER or IDLE_BORDER
    local base = widget.baseSize
    if base then
        local z = selected and SelectedZoom() or 1
        widget:SetSize(base * z, base * z)
    end
    if armed then
        local lr = red + (1 - red) * ARM_LIFT
        local lg = green + (1 - green) * ARM_LIFT
        local lb = blue + (1 - blue) * ARM_LIFT
        CludesUI.PP.UpdateBorder(widget.bhost, t, lr, lg, lb, 1)
        widget.bg:SetVertexColor(red * 0.22, green * 0.22, blue * 0.22, 0.9)
        widget.icon:SetVertexColor(ur, ug, ub)
        widget.label:SetTextColor(lr, lg, lb)
    elseif selected then
        CludesUI.PP.UpdateBorder(widget.bhost, t, red, green, blue, 1)
        widget.bg:SetVertexColor(red * 0.22, green * 0.22, blue * 0.22, 0.9)
        widget.icon:SetVertexColor(ur, ug, ub)
        widget.label:SetTextColor(red, green, blue)
    else
        CludesUI.PP.UpdateBorder(widget.bhost, t, 0, 0, 0, 0.9)
        -- Plate opacity is FIXED -- 0.65 idle, 0.9 selected and armed above
        -- (the Background Opacity setting was removed).
        widget.bg:SetVertexColor(0.05, 0.05, 0.06, 0.65)
        -- Full brightness at idle: the old 0.72 dim was a selection cue, and
        -- selection speaks through the border and the connector line now.
        widget.icon:SetVertexColor(ur, ug, ub)
        widget.label:SetTextColor(0.75, 0.75, 0.75)
    end
end

-- The suite's font, on every string the palette draws.
--
-- The Blizzard font object each string is created from stays the source of its
-- SIZE: the layout is tuned against those sizes, and a re-font is meant to
-- change the typeface and the outline, nothing else. iconText marks the strings
-- that sit ON an icon, which follow the suite's "Outline Icon Text" switch
-- rather than the plain outline mode.
local FONT_KEY = "quickdraw"
local fontStrings = {}

local function ApplyModuleFont(fontStr)
    local size = fontStr.eqdFontSize
    if not size or not CludesUI.GetFontPath then
        return
    end
    -- Snapped to whole physical pixels. A font height is given in the string's
    -- own units and drawn at that height TIMES its effective scale, so a
    -- palette scaled to anything but 1 asks for a fractional pixel height --
    -- and a glyph rasterised between two pixels reads soft and stair-stepped
    -- while the icon art beside it, which is a texture and resamples cleanly,
    -- does not. That is the whole of the pixelated-count report: the icons
    -- were never the problem. PP.perfect is one physical pixel in WoW's
    -- 768-based coordinates, which is what turns a height into pixels and
    -- back. Whole pixels, and never rounded away to nothing.
    local Pix = CludesUI.PP
    local eff = fontStr.GetEffectiveScale and fontStr:GetEffectiveScale()
    if Pix and Pix.perfect and Pix.perfect > 0 and eff and eff > 0 then
        size = max(1, floor(size * eff / Pix.perfect + 0.5)) * Pix.perfect / eff
    end
    local flags
    if fontStr.eqdIconText and CludesUI.GetIconTextOutlineFlag then
        flags = CludesUI.GetIconTextOutlineFlag(FONT_KEY)
    else
        flags = CludesUI.GetFontOutlineFlag(FONT_KEY) or ""
    end
    -- Runtime SetShadowOffset no longer renders on 12.x; the shadow has to be
    -- carried by a FontObject, primed BEFORE the typeface call.
    if CludesUI.PrimeFontShadow then
        local useShadow = flags == "" and CludesUI.GetFontUseShadow()
        CludesUI.PrimeFontShadow(fontStr, useShadow and true or false)
    end
    fontStr:SetFont(CludesUI.GetFontPath(FONT_KEY), size, flags)
end

-- Called once per string, right after it is created from its Blizzard font
-- object, and again for every string whenever the font settings change.
local function AdoptFontString(fontStr, iconText)
    local _, size = fontStr:GetFont()
    fontStr.eqdFontSize = size
    fontStr.eqdIconText = iconText or nil
    fontStrings[#fontStrings + 1] = fontStr
    ApplyModuleFont(fontStr)
end

local function RefreshFonts()
    for index = 1, #fontStrings do
        ApplyModuleFont(fontStrings[index])
    end
end

-- The icon crop, per PAINT rather than per widget: 8% per side (user-tuned
-- past the Action Bars 5.5% default) trims the baked border square action
-- icons carry. The marker textures carry none -- their art runs to the
-- texture's own edge with transparency around it -- so the crop cut into
-- the marker shape itself; they draw at the full rect instead. Keyed off
-- the TEXTURE rather than the slot kind, so a nested menu entry borrowing
-- its first child's marker icon stays whole too. Shared with the options
-- picker's rows, which draw the same icons at list size.
local function ApplyIconCrop(texture, iconTex)
    -- Atlas-backed icons already have their own UVs and should not be cropped.
    if type(iconTex) == "table" and iconTex.atlas then
        texture:SetTexCoord(0, 1, 0, 1)
        return
    end

    if
        type(iconTex) == "string"
        and (
            iconTex:find("RaidTargetingIcon", 1, true)
            or iconTex:find("UI-GroupLoot-Pass-Up", 1, true)
            -- The interface panel glyphs, which are drawn to the edge of their
            -- own square the way the marker textures are. The crop is sized
            -- for the border every spell icon carries and would cut into these.
            or iconTex:find("micromenu", 1, true)
        )
    then
        texture:SetTexCoord(0, 1, 0, 1)
    else
        texture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
end
mod.ApplyIconCrop = ApplyIconCrop

-- ns-hosted, NOT a file-scope local: as one file the module's main chunk sat
-- at the Lua 5.1 200-local cap and this function was the 200th -- hosting it
-- on ns restored the last slot of headroom. Paint-frequency callers; the ns
-- lookup is free there.
function mod.SetIconTexture(texture, iconTex)
    if type(iconTex) == "table" and iconTex.atlas then
        texture:SetAtlas(iconTex.atlas, true)
    else
        texture:SetTexture(iconTex or QUESTION_MARK)
    end
end

local function CreateSlotWidget(view, index)
    local wid = CreateFrame("Button", nil, view.frame, "BackdropTemplate")
    wid.index = index
    -- Our frame, so the backref is safe to carry. ApplySlotVisual reads the
    -- selection color through it: the color keys are per-menu appearance, and
    -- the widget is the only argument that function gets.
    wid.view = view

    wid.bg = wid:CreateTexture(nil, "BACKGROUND")
    wid.bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    wid.bg:SetAllPoints(wid)

    wid.icon = wid:CreateTexture(nil, "ARTWORK")
    wid.icon:SetAllPoints(wid)
    -- The crop is applied per paint -- see ApplyIconCrop.
    wid.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    wid.cd = CreateFrame("Cooldown", nil, wid, "CooldownFrameTemplate")
    wid.cd:SetAllPoints(wid.icon)
    wid.cd:SetHideCountdownNumbers(false)
    wid.cd:SetDrawEdge(false)

    -- The suite's pixel-perfect border system, INSET: snap-managed strips at
    -- exactly borderSize PHYSICAL pixels whatever the scale chain (the
    -- hand-stretched ring this replaces never rendered crisp), overlaying
    -- the icon's own edge from a host raised above the cooldown swirl.
    -- Per-state weight and color go through PP.UpdateBorder in
    -- ApplySlotVisual; the strips track the widget's rect, so a resized
    -- entry keeps its border without any re-anchor.
    wid.bhost = CreateFrame("Frame", nil, wid)
    wid.bhost:SetAllPoints(wid)
    wid.bhost:SetFrameLevel(wid:GetFrameLevel() + 5)
    CludesUI.PP.CreateBorder(wid.bhost, 0, 0, 0, 0.9, 2, "OVERLAY", 7)

    -- Stack size or charges, in the corner an action button writes them in.
    -- Its text may be a SECRET value (see SlotCount), so it is SHOWN and
    -- HIDDEN rather than written and cleared: a FontString carrying secret
    -- text refuses text access to tainted callers, and a refused clear would
    -- leave the previous entry's number standing.
    wid.count = wid:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    wid.count:SetPoint("BOTTOMRIGHT", wid, "BOTTOMRIGHT", -1, 2)
    -- Held on BOTH sides, which is the whole width clamp: anchored by one
    -- corner alone a wide count grows until it runs off the icon it belongs
    -- to, and a three-digit stack did. The text cannot be measured to shrink
    -- it instead -- it may be a secret value, and a secret FontString refuses
    -- text access to a tainted caller -- so the width is decided in advance
    -- and the client fits the number into it.
    wid.count:SetPoint("BOTTOMLEFT", wid, "BOTTOMLEFT", 1, 2)
    wid.count:SetJustifyH("RIGHT")
    -- One line whatever it holds: a count wide enough to need the clamp above
    -- would otherwise wrap onto a second line and climb up the icon.
    if wid.count.SetWordWrap then
        wid.count:SetWordWrap(false)
    end
    wid.count:Hide()
    AdoptFontString(wid.count, true)

    -- "This world marker is on the ground right now", in the corner the count
    -- does not use. Shown only by PaletteView:MarkerPip, which is also what
    -- sizes and colors it, and which moves it onto a host frame the first time
    -- the widget holds a marker entry (see there); created here unconditionally
    -- because a widget is reused for whatever entry the next open puts in it.
    -- It draws under the border host.
    wid.markerPip = wid:CreateTexture(nil, "OVERLAY", nil, 7)
    wid.markerPip:SetTexture("Interface\\Buttons\\WHITE8X8")
    wid.markerPip:SetPoint("TOPLEFT", wid, "TOPLEFT", 2, -2)
    wid.markerPip:Hide()

    -- "This entry opens a menu", in the corner nothing else uses. Without it a
    -- nested entry is drawn exactly like a plain one until it arms, which is
    -- why the nest used to be previewed faintly instead -- and a preview drawn
    -- over the open nest's own children is what that cost.
    wid.nestDots = {}
    for skinData = 1, 3 do
        local t = wid:CreateTexture(nil, "OVERLAY", nil, 7)
        t:SetTexture("Interface\\Buttons\\WHITE8X8")
        t:Hide()
        wid.nestDots[skinData] = t
    end

    wid.label = wid:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    AdoptFontString(wid.label)
    wid.label:SetPoint("TOP", wid, "BOTTOM", 0, -2)
    wid.label:SetWidth(96)
    wid.label:SetWordWrap(false)

    -- The "+" affordance for an interactive view's trailing placeholder entry.
    -- Created unconditionally; Layout is what decides whether it is ever shown.
    -- Drawn as the suite's picker add button (22pt "+", nudged 1px up) --
    -- ApplySlotVisual's placeholder branch is what colors it as one.
    wid.plus = wid:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    AdoptFontString(wid.plus)
    wid.plus.eqdFontSize = 22
    ApplyModuleFont(wid.plus)
    wid.plus:SetPoint("CENTER", 0, 1)
    wid.plus:SetText("+")
    wid.plus:Hide()

    wid:EnableMouse(false)
    return wid
end

local PaletteView = {}
local PaletteViewMeta = { __index = PaletteView }

-- radius, iconSize, deadZone for this view: the geometry the view was created
-- with when there is one (the options preview fits its own), else the view's
-- own palette -- radius and iconSize are per-menu appearance. The 24 is the
-- dead zone, hardcoded: release inside it cancels, and near the centre the
-- pointer's angle is too unstable to select by.
-- radius, icon size, dead zone. The radius is the ARC's, and it is worked out
-- rather than read: Menu Radius is a MINIMUM, and a ring holding more entries
-- than fit at that distance grows until they no longer touch. That is what
-- lets a menu hold more than the twelve a fixed radius could seat, and it
-- leaves every existing menu exactly where it was -- a count that fits at the
-- setting's own value never reaches the floor.
--
-- shownOverride names the count to measure for, which a caller working out the
-- geometry of a palette this view is not currently drawn as must pass: the
-- view's own shownCount still describes whatever was laid out last. Same
-- reason GridDims takes one.
function PaletteView:Geom(shownOverride)
    if self.opts.geom then
        return self.opts.geom()
    end
    local p = self:P()
    if not p then
        return 100, 40, 24
    end
    local radius, iconSize = p.radius or 100, p.iconSize or 40
    if self:LayoutMode() == "ARC" then
        local isShown = max(1, shownOverride or self.shownCount or 1)
        if isShown > 1 then
            -- The chord between two neighbouring entries is 2R sin(step/2).
            -- Holding that to the separation two entries need and solving for R
            -- gives the smallest ring they do not overlap on. A half-step at or
            -- past a quarter turn is left alone: entries that far apart cannot
            -- crowd, and the sine is on its way back down.
            --
            -- The separation is not one pitch. Entries are SQUARES, and two
            -- axis-aligned squares clear each other only once their centres are
            -- a full icon apart along x or along y -- so a pair whose chord
            -- runs diagonally needs iconSize * root 2 between centres, which is
            -- more than a pitch at the shipped sizes. A ring sized on the pitch
            -- alone therefore still touched at the four diagonals, and only
            -- there, which is exactly what a sixteen-entry ring showed.
            local half = self:ArcGeom(isShown) * 0.5
            if half > 0 and half < pi * 0.5 then
                local need = max(iconSize + (p.fanGap or 10), iconSize * 2 ^ 0.5)
                radius = max(radius, need / (2 * sin(half)))
            end
        end
    end
    return radius, iconSize, 24
end

-- The profile as THIS view's palette sees it: its own appearance overrides in
-- front of the profile's values. Every geometry pass reads through here rather
-- than through P(), which is what makes two palettes able to be drawn as two
-- different layouts.
--
-- appIndex is a temporary override for a caller measuring a palette this view
-- is not currently laid out for -- PushPalette does exactly that for every
-- bound palette in turn while the view still holds whatever was last drawn.
function PaletteView:P()
    return PA(self.appIndex or self.paletteIndex)
end

function PaletteView:GetFrame()
    return self.frame
end
function PaletteView:GetPaletteIndex()
    return self.paletteIndex
end
function PaletteView:GetSelection()
    return self.selection
end
function PaletteView:SlotCount()
    return self.slotCount
end
function PaletteView:ShownCount()
    return self.shownCount
end
function PaletteView:GetSlotWidget(index)
    return self.widgets[index]
end

-- ARC | FAN | GRID. A view may pin its own mode (the options preview
-- pins one so the page can show either without changing what the user plays
-- with); everything else follows the profile.
function PaletteView:LayoutMode()
    local p = self:P()
    return self.opts.layout or (p and p.layout) or "ARC"
end

-- Which way a fan runs. Every axis-dependent decision in the file reads this
-- one predicate, so a strip is one layout with an orientation rather than two
-- layouts that happen to share every setting. Meaningless outside a fan, where
-- callers do not ask.
function PaletteView:FanHoriz()
    local p = self:P()
    return not p or p.fanOrientation ~= "VERTICAL"
end

function PaletteView:IsFan()
    return self:LayoutMode() ~= "ARC"
end

function PaletteView:IsGrid()
    return self:LayoutMode() == "GRID"
end

-- The lattice spacing entries are placed on: one icon plus the gap between two
-- of them. The grid, both strips and a nested arc all measure from this.
function PaletteView:Pitch()
    local p = self:P()
    local _, iconSize = self:Geom()
    return iconSize + ((p and p.fanGap) or 10)
end

Inner.AdoptFontString, Inner.ApplyIconCrop = AdoptFontString, ApplyIconCrop
Inner.ApplyModuleFont, Inner.ApplySlotVisual = ApplyModuleFont, ApplySlotVisual
Inner.CANCEL_BUTTON, Inner.CONFIRM_BUTTON = CANCEL_BUTTON, CONFIRM_BUTTON
Inner.CreateSlotWidget, Inner.LATCH_TIMEOUT = CreateSlotWidget, LATCH_TIMEOUT
Inner.OPEN_TIMEOUT, Inner.PaletteView, Inner.PaletteViewMeta = OPEN_TIMEOUT, PaletteView, PaletteViewMeta
Inner.RefreshFonts, Inner.secureButtons, Inner.SelectedZoom = RefreshFonts, secureButtons, SelectedZoom
Inner.views = views
Inner.broken = false
