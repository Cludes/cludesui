if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets.lua -- Shared Widget Helpers + Widget Factory
--  Constants & utilities live in CludesUI.lua.
--  DEFERRED: body runs on first CludesUI:EnsureLoaded() call, not at load.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
CludesUI._deferredInits[#CludesUI._deferredInits + 1] = function()
    -- The options page pool (CludesUI_FramePool.lua): a frame made here under a
    -- pool host (a kept menu, a reused page) is handed out again by the pool, reset
    -- to fresh; anywhere else this is the plain CreateFrame. Every pool function is
    -- captured once here, never read through the public slot later.
    local Pool = CludesUI._Pool
    local CreateFrame = Pool.CreateFrame
    local PoolKept, PoolOwned, PoolAttach = Pool.Kept, Pool.Owned, Pool.Attach
    -- Dress generation of a pooled object (nil when it is not pooled): code that runs
    -- after a setter which may rebuild the page, or later from a timer, compares it
    -- with the generation it started on and stands down once the object was dressed
    -- again for another use.
    local PoolGen = Pool.Gen
    local Pix = CludesUI.PanelPP
    local isRussian = GetLocale() == "ruRU"

    -- Utility functions (used heavily)
    local SolidTex = CludesUI.SolidTex
    local MakeFont = CludesUI.MakeFont
    local MakeRoundedBorder = CludesUI.MakeRoundedBorder
    local DisablePixelSnap = CludesUI.DisablePixelSnap
    local RowBg = CludesUI.RowBg
    local lerp = CludesUI.lerp
    local MakeDropdownArrow = CludesUI.MakeDropdownArrow
    local RegisterWidgetRefresh = CludesUI.RegisterWidgetRefresh
    local RegAccent = CludesUI.RegAccent

    -- Visual constants (used in hot paths)
    local EXPRESSWAY = CludesUI.EXPRESSWAY
    local CLUDES_GREEN = CludesUI.CLUDES_GREEN
    local CONTENT_PAD = CludesUI.CONTENT_PAD
    local DARK_BG = CludesUI.DARK_BG
    local BORDER_COLOR = CludesUI.BORDER_COLOR
    local TEXT_WHITE = CludesUI.TEXT_WHITE
    local TEXT_DIM = CludesUI.TEXT_DIM
    local MEDIA_PATH = CludesUI.MEDIA_PATH
    local CS = CludesUI.CS

    -- Numeric constants (used frequently in widget builders)
    local TEXT_WHITE_R = CludesUI.TEXT_WHITE_R
    local TEXT_WHITE_G = CludesUI.TEXT_WHITE_G
    local TEXT_WHITE_B = CludesUI.TEXT_WHITE_B
    local TEXT_DIM_R = CludesUI.TEXT_DIM_R
    local TEXT_DIM_G = CludesUI.TEXT_DIM_G
    local TEXT_DIM_B = CludesUI.TEXT_DIM_B
    local TEXT_DIM_A = CludesUI.TEXT_DIM_A
    local BORDER_R = CludesUI.BORDER_R
    local BORDER_G = CludesUI.BORDER_G
    local BORDER_B = CludesUI.BORDER_B
    local ROW_BG_ODD = CludesUI.ROW_BG_ODD
    local ROW_BG_EVEN = CludesUI.ROW_BG_EVEN

    -- Slider constants (packed into table to reduce upvalue count)
    local SL = {
        TRACK_R = CludesUI.SL_TRACK_R,
        TRACK_G = CludesUI.SL_TRACK_G,
        TRACK_B = CludesUI.SL_TRACK_B,
        TRACK_A = CludesUI.SL_TRACK_A,
        FILL_A = CludesUI.SL_FILL_A,
        INPUT_R = CludesUI.SL_INPUT_R,
        INPUT_G = CludesUI.SL_INPUT_G,
        INPUT_B = CludesUI.SL_INPUT_B,
        INPUT_A = CludesUI.SL_INPUT_A,
        INPUT_BRD_A = CludesUI.SL_INPUT_BRD_A,
        MW_INPUT_BOOST = CludesUI.MW_INPUT_ALPHA_BOOST,
        MW_TRACK_BOOST = CludesUI.MW_TRACK_ALPHA_BOOST,
    }

    -- Toggle constants (packed into table to reduce upvalue count)
    local TG = {
        OFF_R = CludesUI.TG_OFF_R,
        OFF_G = CludesUI.TG_OFF_G,
        OFF_B = CludesUI.TG_OFF_B,
        OFF_A = CludesUI.TG_OFF_A,
        ON_A = CludesUI.TG_ON_A,
        KNOB_OFF_R = CludesUI.TG_KNOB_OFF_R,
        KNOB_OFF_G = CludesUI.TG_KNOB_OFF_G,
        KNOB_OFF_B = CludesUI.TG_KNOB_OFF_B,
        KNOB_OFF_A = CludesUI.TG_KNOB_OFF_A,
        KNOB_ON_R = CludesUI.TG_KNOB_ON_R,
        KNOB_ON_G = CludesUI.TG_KNOB_ON_G,
        KNOB_ON_B = CludesUI.TG_KNOB_ON_B,
        KNOB_ON_A = CludesUI.TG_KNOB_ON_A,
    }

    -- Checkbox constants (packed into table to reduce upvalue count)
    local CB = {
        BOX_R = CludesUI.CB_BOX_R,
        BOX_G = CludesUI.CB_BOX_G,
        BOX_B = CludesUI.CB_BOX_B,
        BRD_A = CludesUI.CB_BRD_A,
        ACT_BRD_A = CludesUI.CB_ACT_BRD_A,
    }

    -- The toggle's and slider's shapes on a pixel layer (packed into a table to
    -- reduce the upvalue count). CludesUI draws them square: each piece is a
    -- plain white fill coloured through its vertex colour, so the track, knob,
    -- fill and thumb are sharp rectangles placed in whole pixels. Each fit sizes
    -- its pieces for the layer's scale and sets one again only when its size moved.
    local function SquareArt(texture)
        texture:SetColorTexture(1, 1, 1, 1)
    end
    local PX = {
        Layer = CludesUI.MakePixelLayer,
        Pill = SquareArt,
        Circle = SquareArt,
    }
    -- Toggle: the track's width and height, the knob's pad and size (two pads
    -- off the height keep its parity, so the knob sits centred on a whole
    -- pixel); L.apply re-places the knob.
    function PX.ToggleFit(L, keyName)
        local wid, height = L.parent:GetSize()
        local hp, wp = math.floor(height * keyName + 0.5), math.floor(wid * keyName + 0.5)
        local pad = math.max(1, math.floor(L.pad * keyName + 0.5))
        if hp == L.hp and wp == L.wp and pad == L.padPx then
            return
        end
        L.hp, L.wp, L.padPx = hp, wp, pad
        local d = math.max(2, hp - 2 * pad)
        L.d = d
        PX.Pill(L.track, hp)
        PX.Circle(L.knob, d)
        L.knob:SetSize(d, d)
        L.apply()
    end
    -- Slider: the track and fill pills' height and the thumb's circle (its
    -- texture and the blocker behind it, on the thumb in the track's units).
    function PX.SliderFit(L, keyName)
        local height = math.floor(L.trackRef:GetHeight() * keyName + 0.5)
        if height ~= L.hp then
            L.hp = height
            PX.Pill(L.track, height)
            PX.Pill(L.fill, height)
        end
        local d = math.floor(L.thumbRef:GetWidth() * keyName + 0.5)
        if d ~= L.d then
            L.d = d
            PX.Circle(L.thumb, d)
            PX.Circle(L.blocker, d)
        end
    end

    -------------------------------------------------------------------------------

    --  BuildToggleControl(parent, frameLevel, getValue, setValue, opts)
    --  Toggle switch (track + knob) with animated on/off transition.
    --  Returns: toggle (Button), applyVisual (fn), snapToState (fn)
    --  opts: .sizeRatio  multiplier on track/knob sizes (default 1.0)
    --        .noAnim     snap instead of animate (used by cog popup)
    --        .offColors  {trackR,trackG,trackB,trackA, knobR,knobG,knobB,knobA}
    --        .onColors   {trackA, knobR,knobG,knobB,knobA}  (track RGB = accent)
    -------------------------------------------------------------------------------
    local function BuildToggleControl(hostFrame, frameLevel, getValue, setValue, options)
        -- Spec Overrides auto-capture: report every write + host frame for slot attribution during an active Editing-as session.
        -- The slot is read BEFORE the setter runs: a setter that rebuilds the page may dress this frame again for another slot.
        do
            local _s = setValue
            setValue = function(...)
                local snap = CludesUI._SOAttribution(hostFrame)
                _s(...)
                CludesUI._NotifySettingWrite(hostFrame, snap)
            end
        end
        do
            local _r = setValue
            setValue = function(...)
                _r(...)
                CludesUI._settingsChanged = true
            end
        end
        options = options or {}
        local RealPP = CludesUI.PP

        local TOGGLE_W, TOGGLE_H = 40, 20
        local KNOB_PAD = 2

        if options.sizeRatio and options.sizeRatio ~= 1 then
            local r = options.sizeRatio
            TOGGLE_W = math.floor(TOGGLE_W * r + 0.5)
            TOGGLE_H = math.floor(TOGGLE_H * r + 0.5)
        end

        local offTR = options.offColors and options.offColors[1] or TG.OFF_R
        local offTG = options.offColors and options.offColors[2] or TG.OFF_G
        local offTB = options.offColors and options.offColors[3] or TG.OFF_B
        local offTA = options.offColors and options.offColors[4] or TG.OFF_A
        local offKR = options.offColors and options.offColors[5] or TG.KNOB_OFF_R
        local offKG = options.offColors and options.offColors[6] or TG.KNOB_OFF_G
        local offKB = options.offColors and options.offColors[7] or TG.KNOB_OFF_B
        local offKA = options.offColors and options.offColors[8] or TG.KNOB_OFF_A
        local onTA = options.onColors and options.onColors[1] or TG.ON_A
        local onKR = options.onColors and options.onColors[2] or TG.KNOB_ON_R
        local onKG = options.onColors and options.onColors[3] or TG.KNOB_ON_G
        local onKB = options.onColors and options.onColors[4] or TG.KNOB_ON_B
        local onKA = options.onColors and options.onColors[5] or TG.KNOB_ON_A

        local toggle = CreateFrame("Button", nil, hostFrame)
        RealPP.Size(toggle, TOGGLE_W, TOGGLE_H)
        toggle:SetFrameLevel(frameLevel)

        -- The track (a pill) and the knob (a circle) are white art on a pixel
        -- layer, coloured through their vertex colour: round edges crisp at every
        -- Window Scale, the knob placed in whole pixels (PX.ToggleFit sizes them).
        local L = PX.Layer(toggle, PX.ToggleFit)
        local layer = L._frame
        local tBg = layer:CreateTexture(nil, "BACKGROUND")
        tBg:SetAllPoints(layer)
        local knob = layer:CreateTexture(nil, "ARTWORK")
        L.track, L.knob, L.pad = tBg, knob, KNOB_PAD

        local animFrac = getValue() and 1 or 0
        local animTarget = animFrac
        local ANIM_DUR = 0.075

        -- OFF = the knob one pad in from the left edge, ON = one pad in from the
        -- right, in whole pixels between them.
        local function ApplyVisual(p)
            local pad = L.padPx
            if pad then
                knob:ClearAllPoints()
                knob:SetPoint(
                    "TOPLEFT",
                    layer,
                    "TOPLEFT",
                    math.floor(lerp(pad, L.wp - pad - L.d, p) + 0.5),
                    -pad
                )
            end
            tBg:SetVertexColor(
                lerp(offTR, CLUDES_GREEN.r, p),
                lerp(offTG, CLUDES_GREEN.g, p),
                lerp(offTB, CLUDES_GREEN.b, p),
                lerp(offTA, onTA, p)
            )
            knob:SetVertexColor(
                lerp(offKR, onKR, p),
                lerp(offKG, onKG, p),
                lerp(offKB, onKB, p),
                lerp(offKA, onKA, p)
            )
        end
        L.apply = function()
            ApplyVisual(animFrac)
        end
        L:Fit()
        ApplyVisual(animFrac)

        -- The click handlers stand down after the setter when it rebuilt the page and
        -- this toggle was dressed again for another use (the rebuild painted it).
        if options.noAnim then
            toggle:SetScript("OnClick", function()
                local value = not getValue()
                local g = PoolGen(toggle)
                setValue(value)
                if PoolGen(toggle) ~= g then
                    return
                end
                animFrac = value and 1 or 0
                animTarget = animFrac
                ApplyVisual(animFrac)
            end)
        else
            local function AnimOnUpdate(self, elapsed)
                local dir = (animTarget == 1) and 1 or -1
                animFrac = animFrac + dir * (elapsed / ANIM_DUR)
                if (dir == 1 and animFrac >= 1) or (dir == -1 and animFrac <= 0) then
                    animFrac = animTarget
                    self:SetScript("OnUpdate", nil)
                end
                ApplyVisual(animFrac)
            end
            toggle:SetScript("OnClick", function()
                local value = not getValue()
                local g = PoolGen(toggle)
                setValue(value)
                if PoolGen(toggle) ~= g then
                    return
                end
                animTarget = value and 1 or 0
                toggle:SetScript("OnUpdate", AnimOnUpdate)
            end)
        end

        local function SnapToState()
            local value = getValue() and 1 or 0
            animFrac = value
            animTarget = value
            ApplyVisual(value)
            toggle:SetScript("OnUpdate", nil)
        end

        return toggle, ApplyVisual, SnapToState
    end

    -------------------------------------------------------------------------------

    --  BuildCheckboxControl(parent, frameLevel) -- box + border + checkmark texture
    --  Returns: box (Frame), check (Texture), boxBorder, applyVisual (fn)
    --  applyVisual(isOn, isHovering) updates colors/visibility.
    -------------------------------------------------------------------------------
    local function BuildCheckboxControl(hostFrame, frameLevel)
        local RealPP = CludesUI.PP
        local BOX_SZ = 18
        local BOX_PAD = 2

        local boxFrame = CreateFrame("Frame", nil, hostFrame)
        RealPP.Size(boxFrame, BOX_SZ, BOX_SZ)
        boxFrame:SetFrameLevel(frameLevel)

        local boxBg = SolidTex(boxFrame, "BACKGROUND", CB.BOX_R, CB.BOX_G, CB.BOX_B, 1)
        DisablePixelSnap(boxBg)
        boxBg:SetAllPoints()
        local boxBorder = MakeRoundedBorder(boxFrame, BORDER_R, BORDER_G, BORDER_B, CB.BRD_A, boxBg)

        local check = SolidTex(boxFrame, "ARTWORK", CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
        DisablePixelSnap(check)
        RealPP.SetInside(check, boxFrame, BOX_PAD, BOX_PAD)
        -- The outline's radius less the inset, so the fill's corners follow it.
        CludesUI.RoundBody(boxFrame, check, 2)

        local function ApplyVisual(isOn, isHovering)
            check:SetColorTexture(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
            if isOn then
                check:Show()
                boxBg:SetColorTexture(CB.BOX_R, CB.BOX_G, CB.BOX_B, 1)
                boxBorder:SetColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, CB.ACT_BRD_A)
            else
                check:Hide()
                local a = isHovering and 1 or 0.8
                boxBg:SetColorTexture(CB.BOX_R, CB.BOX_G, CB.BOX_B, 1 * a)
                boxBorder:SetColor(BORDER_R, BORDER_G, BORDER_B, CB.BRD_A * a)
            end
        end

        return boxFrame, check, boxBorder, ApplyVisual
    end

    -- Button constants
    local BTN_BG_R = CludesUI.BTN_BG_R
    local BTN_BG_G = CludesUI.BTN_BG_G
    local BTN_BG_B = CludesUI.BTN_BG_B
    local BTN_BG_A = CludesUI.BTN_BG_A
    local BTN_BG_HA = CludesUI.BTN_BG_HA
    local BTN_BRD_A = CludesUI.BTN_BRD_A
    local BTN_BRD_HA = CludesUI.BTN_BRD_HA
    local BTN_TXT_A = CludesUI.BTN_TXT_A
    local BTN_TXT_HA = CludesUI.BTN_TXT_HA

    -- Dropdown constants
    local DD_BG_R = CludesUI.DD_BG_R
    local DD_BG_G = CludesUI.DD_BG_G
    local DD_BG_B = CludesUI.DD_BG_B
    local DD_BG_A = CludesUI.DD_BG_A
    local DD_BG_HA = CludesUI.DD_BG_HA
    local DD_BRD_A = CludesUI.DD_BRD_A
    local DD_BRD_HA = CludesUI.DD_BRD_HA
    local DD_TXT_A = CludesUI.DD_TXT_A
    local DD_TXT_HA = CludesUI.DD_TXT_HA
    local DD_ITEM_HL_A = CludesUI.DD_ITEM_HL_A
    local DD_ITEM_SEL_A = CludesUI.DD_ITEM_SEL_A

    -- Layout constants
    local DUAL_ITEM_W = CludesUI.DUAL_ITEM_W
    local DUAL_GAP = CludesUI.DUAL_GAP
    local TRIPLE_ITEM_W = CludesUI.TRIPLE_ITEM_W
    local TRIPLE_GAP = CludesUI.TRIPLE_GAP

    -------------------------------------------------------------------------------
    --  Shared Widget Helpers  (reduce duplication across widget factories)
    -------------------------------------------------------------------------------

    -- MakeStyledButton + WB_COLOURS/RB_COLOURS live in CludesUI_UICore.lua (runtime login popups use them too).
    local MakeStyledButton = CludesUI.MakeStyledButton
    local WB_COLOURS = CludesUI.WB_COLOURS
    local RB_COLOURS = CludesUI.RB_COLOURS

    -- Widget tooltip system lives in CludesUI_UICore.lua.
    local ShowWidgetTooltip, HideWidgetTooltip = CludesUI.ShowWidgetTooltip, CludesUI.HideWidgetTooltip

    -- Global search index registration for ONE setting. Single-setting rows go via TagOptionRow; multi-slot rows (DualRow, TripleRow, offset rows, wide button rows) call this once per slot so every result is exactly one setting, never a concatenated row label. No-op until the optional CludesUI_GlobalSearch.lua defines it.
    local function IndexSlotForSearch(hostFrame, labelText, tooltipText)
        if not CludesUI._RegisterSearchEntry then
            return
        end
        if not labelText or labelText == "" then
            return
        end
        local sectionName = hostFrame._currentSection and hostFrame._currentSection._sectionName
        local loc = CludesUI.L(labelText)
        -- Some pages show different content per internal selector (CDM bar / action bar / unit); see _buildingSelector.
        local sel = CludesUI._buildingSelector
        CludesUI._RegisterSearchEntry(
            labelText,
            loc ~= labelText and loc or nil,
            type(tooltipText) == "string" and tooltipText or nil,
            CludesUI._buildingModule,
            CludesUI._buildingPage,
            sectionName,
            sel and sel.setter,
            sel and sel.key
        )
    end

    -- Search metadata: tag a row frame so inline search can find it. Combined multi-slot label stays on the FRAME (page search matches whole rows, then narrows to slots); multiSlot=true skips global indexing here because the caller indexes each slot via IndexSlotForSearch.
    local function TagOptionRow(widget, hostFrame, labelText, tooltipText, multiSlot)
        widget._isOptionRow = true
        widget._labelText = labelText
        -- Bilingual search: store the localized label only when it differs from the English key (nil on enUS).
        local _loc = CludesUI.L(labelText)
        if _loc ~= labelText then
            widget._labelTextLoc = _loc
        end
        widget._sectionHeader = hostFrame._currentSection
        if not multiSlot then
            IndexSlotForSearch(hostFrame, labelText, tooltipText)
        end
    end

    -- Disabled-widget tooltip wrapper lives in CludesUI_UICore.lua.
    local DisabledTooltip = CludesUI.DisabledTooltip

    -- Final disabled-tooltip string for a widget cfg (or cog-popup row / inline sub-config); nil = nothing to show. Honors:
    --   cfg.disabledTooltip -- string OR fn returning requirement text/sentence
    --   cfg.rawTooltip      -- bool OR fn; true => verbatim, skip the wrapper
    --   cfg.requireState    -- "enabled" (default) or "disabled", OR fn returning one; wrapper verb
    local function ResolveDisabledTip(rowConf)
        local tt = rowConf.disabledTooltip
        if type(tt) == "function" then
            tt = tt()
        end
        if tt == nil then
            return nil
        end
        local raw = rowConf.rawTooltip
        if type(raw) == "function" then
            raw = raw()
        end
        -- rawTooltip skips the wrapper sentence, not the translation.
        if raw then
            return CludesUI.L(tt)
        end
        local status = rowConf.requireState
        if type(status) == "function" then
            status = status()
        end
        return DisabledTooltip(tt, status)
    end
    -- Shared with hand-placed controls that explain a site's lock the way its widgets do.
    CludesUI.ResolveDisabledTip = ResolveDisabledTip

    -- Disabled-tooltip overlay on a control frame (slider region, toggle, swatch): shows tooltip centered when hovered while disabled.
    local function AddControlDisabledTooltip(controlAnchor, rowConf)
        if not rowConf.disabledTooltip or not rowConf.disabled then
            return
        end
        local hostFrame = controlAnchor:GetParent()
        local hitArea = CreateFrame("Frame", nil, hostFrame)
        hitArea:SetAllPoints(controlAnchor)
        local baseLevel = controlAnchor.GetFrameLevel and controlAnchor:GetFrameLevel()
            or hostFrame:GetFrameLevel()
        hitArea:SetFrameLevel(baseLevel + 10)
        hitArea:SetMouseClickEnabled(false)
        hitArea:SetMouseMotionEnabled(false)
        hitArea:SetScript("OnEnter", function()
            if rowConf.disabled() then
                local tt = ResolveDisabledTip(rowConf)
                if tt then
                    ShowWidgetTooltip(controlAnchor, tt)
                end
            end
        end)
        hitArea:SetScript("OnLeave", function()
            HideWidgetTooltip()
        end)
        local function UpdateMouse()
            local off = rowConf.disabled()
            hitArea:SetMouseClickEnabled(off and true or false)
            hitArea:SetMouseMotionEnabled(off and true or false)
        end
        RegisterWidgetRefresh(UpdateMouse)
        UpdateMouse()
    end

    local function DDText(value)
        if type(value) == "table" then
            return value.text
        end
        return value
    end

    -- Display label for a dropdown, handling subnav children: top-level key with a subnav -> 'ParentText: ChildText'; a subnav child key -> search all values for its parent; else DDText(values[curKey]) or tostring(curKey).
    local function DDResolveLabel(values, sequence, curKey)
        -- Localize the visible label only; raw-key fallback is data. Data dropdowns (profile/spell lists) opt out via _noLoc.
        local noLoc = values and values._noLoc
        local function TR(s)
            if noLoc or type(s) ~= "string" then
                return s
            end
            return CludesUI.L(s)
        end
        -- Direct top-level match (non-subnav)
        local direct = values[curKey]
        if direct and type(direct) ~= "table" then
            return TR(direct)
        end
        if direct and type(direct) == "table" and not direct.subnav then
            return TR(direct.text)
        end
        -- curKey might be a subnav child  search all values for a parent with subnav
        for _, parentKey in ipairs(sequence) do
            local preview = values[parentKey]
            if type(preview) == "table" and preview.subnav then
                local sv = preview.subnav.values
                if sv and sv[curKey] then
                    return TR(preview.text) .. " - " .. TR(sv[curKey])
                end
            end
        end
        -- SharedMedia keys ("sm:<name>") whose provider isn't loaded are absent from `values`; show the clean media name, never the raw "sm:" key.
        if type(curKey) == "string" then
            local smName = curKey:match("^sm:(.+)")
            if smName then
                return smName
            end
        end
        return tostring(curKey)
    end

    local function IsDividerKey(itemKey)
        return type(itemKey) == "string" and itemKey:match("^%-%-%-") ~= nil
    end

    -- Build a dropdown popup menu + item buttons; returns { menu, menuItems, refresh }. ddBtn = button the menu hangs off; menuW = menu pixel width; order = key array; values = { key = displayName } (displayName: string or { text=..., note=... }); ddLbl = label FontString updated on selection; style = "wide"/"regular" (WD_ vs RD_ colours).
    local DD_MAX_HEIGHT = 200

    -- A menu row's background (_menuOpts.background): the texture at 0.45, over
    -- an optional solid base layer, tiled on request, tinted by the look's
    -- tint (its alpha riding the colour write: one alpha channel per texture)
    -- or else by the menu's backgroundVertexColor. look = { base = {r,g,b},
    -- tint = {r,g,b}, tile = true }, so a row can mirror a compound fill.
    local function MenuRowBackground(entry, path, look, vertexColor)
        if look and look.base then
            local b = look.base
            local baseTex = entry:CreateTexture(nil, "BACKGROUND", nil, 0)
            baseTex:SetAllPoints()
            baseTex:SetColorTexture(b[1], b[2], b[3], 1)
            baseTex:SetAlpha(0.45)
        end
        local tile = look and look.tile and "REPEAT" or nil
        local texture = entry:CreateTexture(nil, "BACKGROUND", nil, 1)
        texture:SetAllPoints()
        texture:SetTexture(path, tile, tile)
        if tile then
            texture:SetHorizTile(true)
            texture:SetVertTile(true)
        end
        texture:SetAlpha(0.45)
        if look and look.tint then
            local tbl = look.tint
            texture:SetVertexColor(tbl[1], tbl[2], tbl[3], 0.45)
        elseif vertexColor then
            local vr, vg, vb = vertexColor()
            if vr then
                texture:SetVertexColor(vr, vg, vb, 1)
            end
        end
    end

    -- After a pick, once the menu has fully closed, every widget re-reads its
    -- value: the setter may have changed another dropdown (e.g. moved a text
    -- off the slot this one took).
    local function RefreshWidgetsNextFrame()
        C_Timer.After(0, function()
            local refreshList = CludesUI._widgetRefreshList
            if refreshList then
                for ri = 1, #refreshList do
                    refreshList[ri]()
                end
            end
        end)
    end

    local function BuildDropdownMenu(
        dropdownBtn,
        menuW,
        sequence,
        values,
        getValue,
        setValue,
        dropCaption,
        style,
        disabledValuesFn
    )
        do
            local _r = setValue
            setValue = function(...)
                -- Spec Overrides auto-capture (see BuildToggleControl): dropdown button sits inside the host slot's region.
                local snap = CludesUI._SOAttribution(dropdownBtn)
                -- The slot's Apply to link stays a few seconds after the pick (read before
                -- the setter, which may rebuild the page).
                CludesUI._SyncPickNotice(dropdownBtn)
                _r(...)
                CludesUI._settingsChanged = true
                CludesUI._NotifySettingWrite(dropdownBtn, snap)
            end
        end
        local isWide = (style == "wide")
        -- Localize visible item captions only; data dropdowns opt out via _noLoc.
        local _noLoc = values and values._noLoc
        local function TR(s)
            if _noLoc or type(s) ~= "string" then
                return s
            end
            return CludesUI.L(s)
        end
        -- Menu bg/border: same colours for both styles (DD_BTN with menu-specific alpha)
        local _menuOpts = values._menuOpts
        local _moIcon = _menuOpts and _menuOpts.icon
        local _moIconAtlas = _menuOpts and _menuOpts.iconAtlas
        local _moIconPressedAtlas = _menuOpts and _menuOpts.iconPressedAtlas
        local _moIconOnClick = _menuOpts and _menuOpts.iconOnClick
        local _moIconTooltip = _menuOpts and _menuOpts.iconTooltip
        local _moBackground = _menuOpts and _menuOpts.background
        local _moBgVertexColor = _menuOpts and _menuOpts.backgroundVertexColor
        local _moItemH = _menuOpts and _menuOpts.itemHeight or 26
        local _moMaxTextPct = _menuOpts and _menuOpts.maxTextWidthPct
        local _moOnItemHover = _menuOpts and _menuOpts.onItemHover
        local _moOnItemLeave = _menuOpts and _menuOpts.onItemLeave
        -- Caption font override ({ path, size, flags }) and native atlas icon colours, so a
        -- menu can match the UI it opens from (e.g. the CDM options' own flyouts).
        local _moLabelFont = _menuOpts and _menuOpts.labelFont
        local _moIconNative = _menuOpts and _menuOpts.iconNativeColor
        -- Optional in-menu search box (_menuOpts.searchable): filter field hides non-matching items and repositions the rest. Flat lists only (no subnav, no dividers).
        local _moSearchable = _menuOpts and _menuOpts.searchable
        -- Unless a menu says otherwise, a plain list of 15 or more entries (no
        -- dividers or flyouts, which the search cannot lay out) gets the box too:
        -- fonts, textures and other long lists are typed into instead of scrolled.
        if _moSearchable == nil and #sequence >= 15 then
            _moSearchable = true
            for _, itemKey in ipairs(sequence) do
                local dn = values[itemKey]
                if IsDividerKey(itemKey) or (type(dn) == "table" and dn.subnav) then
                    _moSearchable = false
                    break
                end
            end
        end
        local SEARCH_H = 26
        -- The search field is the list's flush first row (inside the 1 unit border,
        -- a divider as its last unit); the rows below keep their 4-unit top gap.
        local searchPad = _moSearchable and (SEARCH_H + 4) or 0
        local searchBox, searchPlaceholder
        local searchResetScroll -- assigned inside the scrolling branch; nil otherwise
        local padInit, padStepSync, padReveal -- controller helpers: padInit (scrolling branch only) builds the other two on first use
        local mBgR, mBgG, mBgB, mBgA = DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_HA
        local mBrR, mBrG, mBrB, mBrA = 1, 1, 1, DD_BRD_A
        -- Parent to a caller-supplied frame (a scaled popup) when given so the menu INHERITS its scale and layers within it -- no manual scale matching, nested dropdowns don't render giant/behind. Else UIParent (the controller-cursor overlay layer while one is loaded), so page dropdowns escape the scroll-frame clip.
        -- One menu frame per dropdown button for the session (the pool's kept frame): a populate after _invalidateMenu,
        -- or under a button the pool dressed again, gets that frame back reset to fresh and builds on it exactly as on a
        -- new one; its items, search box and scroll parts are pooled under it (the file's CreateFrame).
        local dropMenu =
            PoolKept(dropdownBtn, "ddMenu", "Frame", (_menuOpts and _menuOpts.parent) or CludesUI.OverlayParent())
        -- Spec Overrides auto-capture: edits through this menu attribute to the slot whose dropdown opened it.
        dropMenu._cuiOptionsPopup = true
        -- Controller cursor: the list blocks what is under it but is not a stop itself.
        CludesUI.PadHint(dropMenu, "nodepass")
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(200)
        dropMenu:SetClampedToScreen(true)
        dropMenu:SetClipsChildren(true)
        dropMenu:EnableMouse(true)
        dropMenu:SetSize(menuW, 10)
        -- Anchor: default opens downward; _menuOpts.anchor opens left/right so it can't sit behind controls below it.
        if _menuOpts and _menuOpts.anchor == "LEFT" then
            dropMenu:SetPoint("TOPRIGHT", dropdownBtn, "TOPLEFT", -4, 0)
        elseif _menuOpts and _menuOpts.anchor == "RIGHT" then
            dropMenu:SetPoint("TOPLEFT", dropdownBtn, "TOPRIGHT", 4, 0)
        else
            dropMenu:SetPoint("TOPLEFT", dropdownBtn, "BOTTOMLEFT", 0, -2)
        end
        dropMenu:Hide()
        local menuBg = SolidTex(dropMenu, "BACKGROUND", mBgR, mBgG, mBgB, mBgA)
        menuBg:SetAllPoints()
        dropMenu._ddBrd = MakeRoundedBorder(dropMenu, mBrR, mBrG, mBrB, mBrA, menuBg, nil, true)
        -- House look: an accent cap along the list's top edge.
        do
            local cap = dropMenu:CreateTexture(nil, "OVERLAY", nil, 7)
            cap:SetPoint("TOPLEFT")
            cap:SetPoint("TOPRIGHT")
            cap:SetHeight(2)
            local color = CludesUI.CLUDES_GREEN
            cap:SetColorTexture(color.r, color.g, color.b, 0.9)
        end
        -- Escape closes the open list first (the newest open window), not the
        -- whole settings window behind it. Registered on every build: the page
        -- pool drops the registration when it hands this frame out again.
        if CludesUI.RegisterEscapeClose then
            CludesUI.RegisterEscapeClose(dropMenu)
        end

        if _moSearchable then
            -- Options panel is Expressway-locked by design; CludesUI.EXPRESSWAY is locale-aware (CJK/Cyrillic get the system glyph font). The user's global font intentionally never restyles the settings UI.
            local fontFile = (_moLabelFont and _moLabelFont[1])
                or CludesUI.EXPRESSWAY
                or "Fonts\\FRIZQT__.TTF"
            searchBox = CreateFrame("EditBox", nil, dropMenu)
            searchBox:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 1, -1)
            searchBox:SetPoint("TOPRIGHT", dropMenu, "TOPRIGHT", -1, -1)
            searchBox:SetHeight(searchPad - 1)
            searchBox:SetFrameLevel(dropMenu:GetFrameLevel() + 4)
            searchBox:SetFont(fontFile, 11, "")
            searchBox:SetTextColor(1, 1, 1, 0.9)
            searchBox:SetJustifyH("LEFT")
            searchBox:SetAutoFocus(false)
            searchBox:SetMaxLetters(30)
            -- Text at the row labels' x (rows sit 1 unit in, labels 10 into a row).
            searchBox:SetTextInsets(10, 10, 0, 0)
            local sDiv = searchBox:CreateTexture(nil, "ARTWORK")
            sDiv:SetHeight(1)
            sDiv:SetPoint("BOTTOMLEFT", searchBox, "BOTTOMLEFT", 0, 0)
            sDiv:SetPoint("BOTTOMRIGHT", searchBox, "BOTTOMRIGHT", 0, 0)
            sDiv:SetColorTexture(1, 1, 1, 0.10)
            searchPlaceholder = searchBox:CreateFontString(nil, "OVERLAY")
            searchPlaceholder:SetFont(fontFile, 11, "")
            searchPlaceholder:SetTextColor(0.5, 0.5, 0.5, 0.6)
            searchPlaceholder:SetPoint("LEFT", searchBox, "LEFT", 10, 0)
            searchPlaceholder:SetText(CludesUI.L("Search..."))
            searchBox:SetScript("OnEscapePressed", function(self)
                self:ClearFocus()
            end)
        end

        -- Items are always parented here; becomes the scroll child if scrolling is needed.
        local innerHolder = CreateFrame("Frame", nil, dropMenu)
        innerHolder:SetWidth(menuW)
        innerHolder:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, 0)

        local menuItems = {}
        local menuH = 4
        -- A row at the list's current depth (mH), inset 1 from each side.
        local function MenuRow(height)
            local entry = CreateFrame("Button", nil, innerHolder)
            entry:SetHeight(height)
            entry:SetPoint("TOPLEFT", innerHolder, "TOPLEFT", 1, -menuH)
            entry:SetPoint("TOPRIGHT", innerHolder, "TOPRIGHT", -1, -menuH)
            entry:SetFrameLevel(dropMenu:GetFrameLevel() + 2)
            return entry
        end
        for _, itemKey in ipairs(sequence) do
            -- Keys beginning with "---" insert a thin separator line
            if IsDividerKey(itemKey) then
                local div = innerHolder:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetColorTexture(1, 1, 1, 0.10)
                div:SetPoint("TOPLEFT", innerHolder, "TOPLEFT", 1, -menuH - 4)
                div:SetPoint("TOPRIGHT", innerHolder, "TOPRIGHT", -1, -menuH - 4)
                menuH = menuH + 9
            else
                local dn = values[itemKey]
                if dn then
                    -- SUBNAV PARENT: render with arrow, hover flyout
                    if type(dn) == "table" and dn.subnav then
                        local sn = dn.subnav
                        local parentText = dn.text or tostring(itemKey)
                        local entry = MenuRow(26)
                        local itemText = MakeFont(entry, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                        itemText:SetAlpha(1)
                        itemText:SetPoint("LEFT", entry, "LEFT", isWide and 12 or 10, 0)
                        itemText:SetText(TR(parentText))
                        local arrowTex = entry:CreateTexture(nil, "ARTWORK")
                        arrowTex:SetSize(10, 10)
                        arrowTex:SetPoint("RIGHT", entry, "RIGHT", -8, 0)
                        arrowTex:SetTexture(MEDIA_PATH .. "icons/right-arrow.png")
                        arrowTex:SetAlpha(0.7)
                        local iHl = SolidTex(entry, "ARTWORK", 1, 1, 1, 1)
                        iHl:SetAlpha(0)
                        iHl:SetAllPoints()
                        entry._key = itemKey
                        entry._label = itemText
                        entry._highlight = iHl
                        entry._isSubnavParent = true
                        entry._subnavChildKeys = {}
                        if sn.order then
                            for _, ck in ipairs(sn.order) do
                                entry._subnavChildKeys[ck] = true
                            end
                        end
                        menuItems[#menuItems + 1] = entry

                        -- Owned by the menu (screen-level, not its child): handed out again by order at each populate.
                        local subMenu = PoolOwned(dropMenu, "flyout", "Frame", CludesUI.OverlayParent())
                        subMenu:SetFrameStrata("FULLSCREEN_DIALOG")
                        subMenu:SetFrameLevel(dropMenu:GetFrameLevel() + 10)
                        subMenu:SetClampedToScreen(true)
                        subMenu:SetSize(menuW, 10)
                        subMenu:Hide()
                        local flyBg = SolidTex(subMenu, "BACKGROUND", mBgR, mBgG, mBgB, mBgA)
                        flyBg:SetAllPoints()
                        MakeRoundedBorder(subMenu, mBrR, mBrG, mBrB, mBrA, flyBg, nil, true)
                        entry._flyout = subMenu
                        if not dropMenu._flyouts then
                            dropMenu._flyouts = {}
                        end
                        dropMenu._flyouts[#dropMenu._flyouts + 1] = subMenu
                        -- Controller cursor: not a stop; Cancel clicks the dropdown button, closing the whole list.
                        if CludesUI.PadCP() then
                            CludesUI.PadHint(subMenu, "nodepass")
                            subMenu.CloseButton = dropdownBtn
                        end

                        -- Declared before the children: under the controller cursor they keep the flyout open too.
                        local flyoutTimer
                        -- The delayed close checks below run only while the flyout still has this dress (a later
                        -- populate of the menu hands the same flyout out again).
                        local function CloseFlyoutLater(delay)
                            local g = PoolGen(subMenu)
                            flyoutTimer = C_Timer.NewTimer(delay, function()
                                if PoolGen(subMenu) ~= g then
                                    return
                                end
                                if not subMenu:IsMouseOver() and not entry:IsMouseOver() then
                                    subMenu:Hide()
                                end
                                flyoutTimer = nil
                            end)
                        end
                        local fH, fW = 4, menuW
                        -- This populate's rows (the flyout also keeps idle rows an earlier populate parked).
                        local flyRows = {}
                        entry._flyoutRows = flyRows
                        for _, childKey in ipairs(sn.order) do
                            local childText = sn.values[childKey]
                            if childText then
                                local ci = CreateFrame("Button", nil, subMenu)
                                flyRows[#flyRows + 1] = ci
                                ci:SetHeight(sn.itemHeight or 26)
                                ci:SetPoint("TOPLEFT", subMenu, "TOPLEFT", 1, -fH)
                                ci:SetPoint("TOPRIGHT", subMenu, "TOPRIGHT", -1, -fH)
                                ci:SetFrameLevel(subMenu:GetFrameLevel() + 2)
                                local cLbl =
                                    MakeFont(ci, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                                cLbl:SetAlpha(1)
                                cLbl:SetPoint("LEFT", ci, "LEFT", 10, 0)
                                cLbl:SetText(TR(childText))
                                cLbl:SetJustifyH("LEFT")
                                local rowW = cLbl:GetStringWidth() + 22
                                if sn.icon then
                                    local iconPath, l, r, t, b = sn.icon(childKey)
                                    if iconPath then
                                        local iconTex = ci:CreateTexture(nil, "ARTWORK")
                                        local icoSz = (sn.itemHeight or 26) - 8
                                        iconTex:SetSize(icoSz, icoSz)
                                        iconTex:SetPoint("RIGHT", ci, "RIGHT", -6, 0)
                                        iconTex:SetTexture(iconPath)
                                        if l then
                                            iconTex:SetTexCoord(l, r, t, b)
                                        end
                                        cLbl:SetPoint("RIGHT", iconTex, "LEFT", -4, 0)
                                        rowW = rowW + icoSz + 4
                                    end
                                end
                                if rowW > fW then
                                    fW = rowW
                                end
                                local cHl = SolidTex(ci, "ARTWORK", 1, 1, 1, 1)
                                cHl:SetAlpha(0)
                                cHl:SetAllPoints()
                                ci._key = childKey
                                ci._label = cLbl
                                ci._highlight = cHl
                                ci:SetScript("OnEnter", function()
                                    cLbl:SetTextColor(1, 1, 1, 1)
                                    cHl:SetAlpha(DD_ITEM_HL_A)
                                    -- Controller cursor: the hidden pointer is never over the flyout, so a child
                                    -- keeps it open itself (the mouse path relies on IsMouseOver instead).
                                    if flyoutTimer and CludesUI.PadCursorShown() then
                                        flyoutTimer:Cancel()
                                        flyoutTimer = nil
                                    end
                                end)
                                ci:SetScript("OnLeave", function()
                                    cLbl:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                                    local current = getValue()
                                    cHl:SetAlpha(ci._key == current and DD_ITEM_SEL_A or 0)
                                    -- Controller cursor: leaving a child starts the same close check the parent row
                                    -- uses; the next child or the parent row cancels it.
                                    if CludesUI.PadCursorShown() then
                                        if flyoutTimer then
                                            flyoutTimer:Cancel()
                                        end
                                        CloseFlyoutLater(0.25)
                                    end
                                end)
                                ci:SetScript("OnClick", function()
                                    -- The label write stands down when onSelect rebuilt the page and the
                                    -- label was dressed again for another use; the list always closes.
                                    local g = PoolGen(dropCaption)
                                    if sn.onSelect then
                                        sn.onSelect(childKey)
                                    end
                                    if PoolGen(dropCaption) == g then
                                        dropCaption:SetText(TR(parentText) .. ": " .. TR(childText))
                                    end
                                    subMenu:Hide()
                                    dropMenu:Hide()
                                    RefreshWidgetsNextFrame()
                                end)
                                fH = fH + (sn.itemHeight or 26)
                            end
                        end
                        subMenu:SetSize(fW, fH + 4)

                        entry:SetScript("OnEnter", function()
                            itemText:SetTextColor(1, 1, 1, 1)
                            arrowTex:SetAlpha(1)
                            iHl:SetAlpha(DD_ITEM_HL_A)
                            if flyoutTimer then
                                flyoutTimer:Cancel()
                                flyoutTimer = nil
                            end
                            -- Close the previous flyout now; its delayed close would leave it under this one.
                            for _, fo in ipairs(dropMenu._flyouts) do
                                if fo ~= subMenu then
                                    fo:Hide()
                                end
                            end
                            subMenu:ClearAllPoints()
                            subMenu:SetPoint("TOPLEFT", entry, "TOPRIGHT", 2, 0)
                            subMenu:Show()
                            subMenu:SetScale(dropMenu:GetScale())
                        end)
                        entry:SetScript("OnLeave", function()
                            itemText:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                            arrowTex:SetAlpha(0.7)
                            local current = getValue()
                            local isChild = entry._subnavChildKeys[current]
                            iHl:SetAlpha(isChild and DD_ITEM_SEL_A or 0)
                            -- Delay hide so the mouse can travel to the flyout
                            CloseFlyoutLater(0.25)
                        end)
                        -- Keep the flyout alive while the mouse is over it
                        subMenu:SetScript("OnEnter", function()
                            if flyoutTimer then
                                flyoutTimer:Cancel()
                                flyoutTimer = nil
                            end
                        end)
                        subMenu:SetScript("OnLeave", function()
                            CloseFlyoutLater(0.15)
                        end)
                        CludesUI.TrackOverlay(subMenu)
                        dropMenu:HookScript("OnHide", function()
                            subMenu:Hide()
                        end)
                        entry:SetScript("OnClick", function() end) -- no-op, subnav only
                        menuH = menuH + 26
                    else
                        -- Annotated labels: dn = string or { text=..., note=..., font=..., action=fn }.
                        -- An action row runs its callback and closes the menu WITHOUT selecting a
                        -- value (the "Edit ..." entry pinned above a "---" divider); accent-colored.
                        local mainText, noteText, itemFont, dnAction = dn, nil, nil, nil
                        if type(dn) == "table" then
                            mainText, noteText, itemFont, dnAction = dn.text, dn.note, dn.font, dn.action
                        end
                        local entry = MenuRow(_moItemH)
                        if _moBackground then
                            local bgPath, bgLook = _moBackground(itemKey)
                            if bgPath then
                                MenuRowBackground(entry, bgPath, bgLook, _moBgVertexColor)
                            end
                        end
                        local itemText = MakeFont(entry, 13, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                        if _moLabelFont then
                            itemText:SetFont(_moLabelFont[1], _moLabelFont[2] or 13, _moLabelFont[3] or "")
                        end
                        if itemFont then
                            itemText:SetFont(itemFont, 13, "")
                        end
                        itemText:SetAlpha(1)
                        itemText:SetPoint("LEFT", entry, "LEFT", isWide and 12 or 10, 0)
                        itemText:SetJustifyH("LEFT")
                        if _moMaxTextPct then
                            itemText:SetWordWrap(false)
                            itemText:SetWidth(menuW * _moMaxTextPct)
                        end
                        itemText:SetText(TR(mainText))
                        if dnAction then
                            local ACC = CludesUI.CLUDES_GREEN
                            itemText:SetTextColor(ACC.r, ACC.g, ACC.b, 0.8)
                            entry._isAction = true -- Refresh keeps the accent across menu opens
                        elseif _menuOpts and _menuOpts.labelColor then
                            -- Optional .labelColor(key) -> r, g, b[, a]: the label's idle colour;
                            -- hover shows the same hue at full alpha, Refresh restores it.
                            local lr, lg, lb, la = _menuOpts.labelColor(itemKey)
                            if lr then
                                entry._lblColor = { lr, lg, lb, la or 1 }
                                itemText:SetTextColor(lr, lg, lb, la or 1)
                            end
                        end
                        -- Optional icon, three sources: _menuOpts.icon(key) -> texture path (+ texcoord); .iconAtlas(key) -> atlas name; .iconPressedAtlas(key) -> pressed-state atlas. With .iconOnClick the icon becomes a clickable Button on its own frame level so clicks don't reach the item's OnClick.
                        local _haveAtlas = _moIconAtlas and _moIconAtlas(itemKey) or nil
                        local _iconPath, _il, _ir, _it, _ib
                        if _moIcon and not _haveAtlas then
                            _iconPath, _il, _ir, _it, _ib = _moIcon(itemKey)
                        end
                        if _haveAtlas or _iconPath then
                            -- Optional, both icon kinds: .iconSize(key) -> edge length (default row
                            -- height - 8), .iconColor(key) -> r, g, b[, a] idle tint (hover: alpha 1),
                            -- .iconInset -> right inset, number or fn(key). Unset, the inset is 6;
                            -- with .iconClearScroll it moves clear of the scrollbar when the menu scrolls.
                            local icoSz = (_menuOpts and _menuOpts.iconSize and _menuOpts.iconSize(itemKey))
                                or (_moItemH - 8)
                            local icoInset = _menuOpts and _menuOpts.iconInset
                            if type(icoInset) == "function" then
                                icoInset = icoInset(itemKey)
                            end
                            entry._icoClearScroll = icoInset == nil and _menuOpts and _menuOpts.iconClearScroll
                                or nil
                            icoInset = icoInset or 6
                            if _menuOpts and _menuOpts.iconColor then
                                local cr, cg, checkBtn, ca = _menuOpts.iconColor(itemKey)
                                if cr then
                                    entry._icoColor = { cr, cg, checkBtn, ca or 1 }
                                end
                            end
                            local iconHolder = entry._icoColor
                            if _moIconOnClick then
                                local iconButton = CreateFrame("Button", nil, entry)
                                iconButton:SetSize(icoSz, icoSz)
                                iconButton:SetPoint("RIGHT", entry, "RIGHT", -icoInset, 0)
                                entry._icon = iconButton
                                iconButton:SetFrameLevel(entry:GetFrameLevel() + 2)
                                if _haveAtlas then
                                    iconButton:SetNormalAtlas(_haveAtlas)
                                    local pressedAtlas = _moIconPressedAtlas and _moIconPressedAtlas(itemKey)
                                    if pressedAtlas then
                                        iconButton:SetPushedAtlas(pressedAtlas)
                                    end
                                    iconButton:SetHighlightAtlas(_haveAtlas)
                                    -- Atlas icons carry an intrinsic colour that SetVertexColor
                                    -- only scales, so each state is desaturated and tinted
                                    -- #929292 first (unless the menu keeps native colours),
                                    -- then takes the row's icon colour at alpha a.
                                    local function GreyAtlas(texture, a)
                                        if not texture then
                                            return
                                        end
                                        if not _moIconNative then
                                            if texture.SetDesaturated then
                                                texture:SetDesaturated(true)
                                            end
                                            texture:SetVertexColor(0.573, 0.573, 0.573, 1)
                                        end
                                        if iconHolder then
                                            texture:SetVertexColor(iconHolder[1], iconHolder[2], iconHolder[3], a)
                                        end
                                    end
                                    GreyAtlas(iconButton:GetNormalTexture(), iconHolder and iconHolder[4])
                                    GreyAtlas(iconButton:GetPushedTexture(), 1)
                                    local hlTex = iconButton:GetHighlightTexture()
                                    GreyAtlas(hlTex, 1)
                                    if hlTex then
                                        hlTex:SetAlpha(0.4)
                                    end
                                else
                                    local iconTex = iconButton:CreateTexture(nil, "ARTWORK")
                                    iconTex:SetAllPoints()
                                    iconTex:SetTexture(_iconPath)
                                    if _il then
                                        iconTex:SetTexCoord(_il, _ir, _it, _ib)
                                    end
                                    if iconHolder then
                                        iconTex:SetVertexColor(iconHolder[1], iconHolder[2], iconHolder[3], iconHolder[4])
                                    else
                                        iconTex:SetVertexColor(0.8, 0.8, 0.8, 1)
                                    end
                                    iconButton._ico = iconTex
                                end
                                -- A texture icon lights on hover: its own colour at full
                                -- alpha, or white over the resting light grey.
                                local function PaintIcon(hot)
                                    local iconTex = iconButton._ico
                                    if not iconTex then
                                        return
                                    end
                                    if iconHolder then
                                        iconTex:SetVertexColor(iconHolder[1], iconHolder[2], iconHolder[3], hot and 1 or iconHolder[4])
                                    elseif hot then
                                        iconTex:SetVertexColor(1, 1, 1, 1)
                                    else
                                        iconTex:SetVertexColor(0.8, 0.8, 0.8, 1)
                                    end
                                end
                                iconButton:SetScript("OnEnter", function()
                                    PaintIcon(true)
                                    if _moIconTooltip then
                                        ShowWidgetTooltip(iconButton, _moIconTooltip(itemKey))
                                    end
                                end)
                                iconButton:SetScript("OnLeave", function()
                                    PaintIcon(false)
                                    if _moIconTooltip then
                                        HideWidgetTooltip()
                                    end
                                end)
                                iconButton:SetScript("OnClick", function()
                                    _moIconOnClick(itemKey)
                                end)
                                itemText:SetPoint("RIGHT", iconButton, "LEFT", -4, 0)
                            else
                                local iconTex = entry:CreateTexture(nil, "ARTWORK")
                                -- _menuOpts.iconWidth(key) allows non-square icons; default square.
                                iconTex:SetSize(
                                    (_menuOpts and _menuOpts.iconWidth and _menuOpts.iconWidth(itemKey)) or icoSz,
                                    icoSz
                                )
                                iconTex:SetPoint("RIGHT", entry, "RIGHT", -icoInset, 0)
                                entry._icon, entry._icoTex = iconTex, iconTex
                                if _haveAtlas then
                                    iconTex:SetAtlas(_haveAtlas)
                                else
                                    iconTex:SetTexture(_iconPath)
                                    if _il then
                                        iconTex:SetTexCoord(_il, _ir, _it, _ib)
                                    end
                                end
                                if iconHolder then
                                    iconTex:SetVertexColor(iconHolder[1], iconHolder[2], iconHolder[3], iconHolder[4])
                                end
                                itemText:SetPoint("RIGHT", iconTex, "LEFT", -4, 0)
                            end
                        end
                        local iNote -- annotation: smaller font, 75% alpha, same colour
                        if noteText then
                            iNote = MakeFont(entry, 11, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                            iNote:SetAlpha(0.75)
                            iNote:SetPoint("LEFT", itemText, "RIGHT", 4, 0)
                            iNote:SetText(TR(noteText))
                        end
                        -- Hover and selection wash in the accent colour (house look).
                        local iHl = SolidTex(
                            entry,
                            "ARTWORK",
                            CludesUI.CLUDES_GREEN.r,
                            CludesUI.CLUDES_GREEN.g,
                            CludesUI.CLUDES_GREEN.b,
                            1
                        )
                        iHl:SetAlpha(0)
                        iHl:SetAllPoints()
                        entry._key, entry._label, entry._highlight, entry._note = itemKey, itemText, iHl, iNote
                        -- Full display name for the dropdown button label
                        entry._displayName = noteText and (mainText .. " " .. noteText) or mainText
                        menuItems[#menuItems + 1] = entry
                        -- Lit: the label (its own hue, if any) and note in full white
                        -- and the icon's tint at full alpha, over the hover wash. At
                        -- rest: the accent for an action row, else the label's own
                        -- colour or the dim text, the selection wash on the current pick.
                        local function Paint(hot)
                            local lc, ic = entry._lblColor, entry._icoColor
                            if hot then
                                if lc then
                                    itemText:SetTextColor(lc[1], lc[2], lc[3], 1)
                                else
                                    itemText:SetTextColor(1, 1, 1, 1)
                                end
                            elseif dnAction then
                                local ACC = CludesUI.CLUDES_GREEN
                                itemText:SetTextColor(ACC.r, ACC.g, ACC.b, 0.8)
                            elseif lc then
                                itemText:SetTextColor(lc[1], lc[2], lc[3], lc[4])
                            else
                                itemText:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                            end
                            if ic and entry._icoTex then
                                entry._icoTex:SetVertexColor(ic[1], ic[2], ic[3], hot and 1 or ic[4])
                            end
                            if iNote then
                                if hot then
                                    iNote:SetTextColor(1, 1, 1, 1)
                                else
                                    iNote:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                                end
                            end
                            if hot then
                                iHl:SetAlpha(DD_ITEM_HL_A)
                            else
                                iHl:SetAlpha((entry._key == getValue()) and DD_ITEM_SEL_A or 0)
                            end
                        end
                        entry:SetScript("OnEnter", function()
                            if disabledValuesFn then
                                local dv = disabledValuesFn(itemKey)
                                if dv then
                                    -- A string return doubles as the tooltip text
                                    if type(dv) == "string" then
                                        ShowWidgetTooltip(entry, dv)
                                    end
                                    return
                                end
                            end
                            Paint(true)
                            -- Second arg (item frame) is additive: (key)-only handlers ignore it; others use it to anchor tooltips.
                            if _moOnItemHover then
                                _moOnItemHover(itemKey, entry)
                            end
                        end)
                        entry:SetScript("OnLeave", function()
                            if disabledValuesFn and disabledValuesFn(itemKey) then
                                HideWidgetTooltip()
                                return
                            end
                            Paint(false)
                            if _moOnItemLeave then
                                _moOnItemLeave(itemKey, entry)
                            end
                        end)
                        entry:SetScript("OnClick", function()
                            if disabledValuesFn and disabledValuesFn(itemKey) then
                                return
                            end
                            if dnAction then
                                dropMenu:Hide()
                                dnAction()
                                return
                            end
                            -- The label write stands down when the setter rebuilt the page and the label was
                            -- dressed again for another use (the rebuild painted it); the list always closes.
                            local g = PoolGen(dropCaption)
                            setValue(itemKey)
                            if PoolGen(dropCaption) == g then
                                dropCaption:SetText(TR(mainText))
                            end
                            dropMenu:Hide()
                            RefreshWidgetsNextFrame()
                        end)
                        menuH = menuH + _moItemH
                    end -- subnav if/else
                end -- if dn
            end -- divider else
        end -- for order

        local totalContentH = menuH + 3
        innerHolder:SetHeight(totalContentH)

        ---------------------------------------------------------------------------
        --  Scrollable dropdown: content over DD_MAX_HEIGHT is wrapped in a ScrollFrame with a thin custom scrollbar + smooth scrolling.
        ---------------------------------------------------------------------------
        if totalContentH > (_menuOpts and _menuOpts.maxHeight or DD_MAX_HEIGHT) then
            dropMenu:SetHeight((_menuOpts and _menuOpts.maxHeight or DD_MAX_HEIGHT) + searchPad)

            local scroller = CreateFrame("ScrollFrame", nil, dropMenu)
            -- inset: the controller step strips' height (0 without them). An edge
            -- the scroll area would touch keeps 1 unit, so a scrolled row's text
            -- (no mask takes a font string) stops at the border instead of
            -- running over it.
            local function PlaceScroll(inset)
                local topY = searchPad + inset
                scroller:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, -(topY > 0 and topY or 1))
                scroller:SetPoint("BOTTOMRIGHT", dropMenu, "BOTTOMRIGHT", 0, inset > 0 and inset or 1)
            end
            PlaceScroll(0)
            scroller:SetFrameLevel(dropMenu:GetFrameLevel() + 1)
            scroller:EnableMouseWheel(true)
            scroller:SetScrollChild(innerHolder)
            innerHolder:SetWidth(menuW)
            -- The track below sits 4-8px in from the right: icons of a menu with
            -- .iconClearScroll move to 10 so they clear it; an explicit .iconInset stays.
            for idx = 1, #menuItems do
                local entry = menuItems[idx]
                if entry._icon and entry._icoClearScroll then
                    entry._icon:ClearAllPoints()
                    entry._icon:SetPoint("RIGHT", entry, "RIGHT", -10, 0)
                end
            end

            -- Thin scrollbar track (4px, right side; matches main panel style)
            local menuRail = CreateFrame("Frame", nil, scroller)
            menuRail:SetWidth(4)
            menuRail:SetPoint("TOPRIGHT", scroller, "TOPRIGHT", -4, -4)
            menuRail:SetPoint("BOTTOMRIGHT", scroller, "BOTTOMRIGHT", -4, 4)
            menuRail:SetFrameLevel(scroller:GetFrameLevel() + 2)
            SolidTex(menuRail, "BACKGROUND", 1, 1, 1, 0.02):SetAllPoints()

            local menuKnob = CreateFrame("Button", nil, menuRail)
            menuKnob:SetWidth(4)
            menuKnob:SetFrameLevel(menuRail:GetFrameLevel() + 1)
            menuKnob:EnableMouse(true)
            menuKnob:RegisterForDrag("LeftButton")
            menuKnob:SetScript("OnDragStart", function() end)
            menuKnob:SetScript("OnDragStop", function() end)
            SolidTex(menuKnob, "ARTWORK", 1, 1, 1, 0.27):SetAllPoints()
            -- Controller cursor: it scrolls the list to the selected row itself; the pointer-drag thumb is no stop.
            CludesUI.PadHint(menuKnob, "nodeignore")

            -- Smooth scroll state (per-dropdown, isolated from main panel)
            local ddScrollTarget = 0
            local ddSmoothing = false
            local SCROLL_STEP = 40
            local SMOOTH_SPEED = 12

            -- Parentless; owned by the menu, so each populate hands the same one out again.
            local ddSmoothFrame = PoolOwned(dropMenu, "smooth", "Frame")
            ddSmoothFrame:Hide()

            local function UpdateDDThumb()
                local maxScroll = CludesUI.SafeScrollRange(scroller)
                if maxScroll <= 0 then
                    menuRail:Hide()
                    return
                end
                menuRail:Show()
                local trackH = menuRail:GetHeight()
                local visH = scroller:GetHeight()
                local ratio = visH / (visH + maxScroll)
                local thumbH = math.max(20, trackH * ratio)
                menuKnob:SetHeight(thumbH)
                local scrollRatio = (tonumber(scroller:GetVerticalScroll()) or 0) / maxScroll
                local maxTravel = trackH - thumbH
                menuKnob:ClearAllPoints()
                menuKnob:SetPoint("TOP", menuRail, "TOP", 0, -(scrollRatio * maxTravel))
            end

            -- A scroll position held inside the list's range.
            local function Clamp(pos)
                return math.max(0, math.min(CludesUI.SafeScrollRange(scroller), pos))
            end
            -- Straight to pos, no easing (the target follows so a later wheel
            -- starts from there).
            local function JumpTo(pos)
                ddScrollTarget = pos
                scroller:SetVerticalScroll(pos)
                UpdateDDThumb()
            end
            local function StopSmooth()
                ddSmoothing = false
                ddSmoothFrame:Hide()
            end
            -- Where a new step starts: the easing's target while one runs.
            local function StepBase()
                return ddSmoothing and ddScrollTarget or scroller:GetVerticalScroll()
            end

            -- Lets the search filter snap back to the top after the list changes.
            searchResetScroll = function()
                JumpTo(0)
            end

            -- The easing: each frame closes part of the gap to the target, and
            -- lands on it once under a third of a unit away.
            ddSmoothFrame:SetScript("OnUpdate", function(_, elapsed)
                local current = scroller:GetVerticalScroll()
                ddScrollTarget = Clamp(ddScrollTarget)
                local diff = ddScrollTarget - current
                if math.abs(diff) < 0.3 then
                    JumpTo(ddScrollTarget)
                    StopSmooth()
                    return
                end
                scroller:SetVerticalScroll(Clamp(current + diff * math.min(1, SMOOTH_SPEED * elapsed)))
                UpdateDDThumb()
            end)

            local function DDSmoothScrollTo(target)
                ddScrollTarget = Clamp(target)
                if not ddSmoothing then
                    ddSmoothing = true
                    ddSmoothFrame:Show()
                end
            end

            scroller:SetScript("OnMouseWheel", function(self, delta)
                if CludesUI.SafeScrollRange(self) <= 0 then
                    return
                end
                DDSmoothScrollTo(StepBase() - delta * SCROLL_STEP)
            end)
            scroller:SetScript("OnScrollRangeChanged", UpdateDDThumb)

            -- Controller helpers, built by the first open that runs with a controller
            -- (menu._padOpen), so a list never opened with one carries none of them.
            padInit = function()
                padInit = nil
                -- The gamepad-driven pointer has no mouse wheel: one step strip above
                -- and one below the list, built the first time that pointer drives the
                -- menu and shown only while it does; the list gives up their height
                -- only then.
                local PAD_STEP_H = 16
                local padUp, padDown
                local function PadStepClick(self)
                    DDSmoothScrollTo(StepBase() + self._dir * SCROLL_STEP)
                end
                local function MakePadStep(dir, edge, cursorY)
                    local widget = CreateFrame("Button", nil, dropMenu)
                    widget:SetHeight(PAD_STEP_H)
                    widget:SetPoint(edge .. "LEFT", dropMenu, edge .. "LEFT", 1, cursorY)
                    widget:SetPoint(edge .. "RIGHT", dropMenu, edge .. "RIGHT", -1, cursorY)
                    widget:SetFrameLevel(dropMenu:GetFrameLevel() + 3)
                    widget._dir = dir
                    local highlight = SolidTex(widget, "ARTWORK", 1, 1, 1, 1)
                    highlight:SetAllPoints()
                    highlight:SetAlpha(0)
                    local arrowTex = widget:CreateTexture(nil, "OVERLAY")
                    arrowTex:SetSize(18, 18)
                    arrowTex:SetPoint("CENTER")
                    arrowTex:SetTexture(MEDIA_PATH .. "icons/cui-arrow.png")
                    if dir < 0 then
                        arrowTex:SetRotation(math.pi)
                    end
                    arrowTex:SetAlpha(0.6)
                    widget:SetScript("OnEnter", function()
                        highlight:SetAlpha(DD_ITEM_HL_A)
                        arrowTex:SetAlpha(1)
                    end)
                    widget:SetScript("OnLeave", function()
                        highlight:SetAlpha(0)
                        arrowTex:SetAlpha(0.6)
                    end)
                    widget:SetScript("OnClick", PadStepClick)
                    -- The controller cursor scrolls the list by itself; the strips serve the pointer.
                    CludesUI.PadHint(widget, "nodeignore")
                    return widget
                end
                padStepSync = function(show)
                    if not padUp then
                        if not show then
                            return
                        end
                        padUp = MakePadStep(-1, "TOP", -searchPad)
                        padDown = MakePadStep(1, "BOTTOM", 0)
                    end
                    padUp:SetShown(show)
                    padDown:SetShown(show)
                    PlaceScroll(show and PAD_STEP_H or 0)
                end

                -- Controller cursor: scroll the row it is about to land on into view;
                -- true when that row is inside the visible list afterwards.
                padReveal = function(entry)
                    local topY, itTop = innerHolder:GetTop(), entry:GetTop()
                    if not (topY and itTop) then
                        return false
                    end
                    StopSmooth()
                    JumpTo(Clamp((topY - itTop) - (scroller:GetHeight() - entry:GetHeight()) / 2))
                    local sTop, sBot, iTop, iBot = scroller:GetTop(), scroller:GetBottom(), entry:GetTop(), entry:GetBottom()
                    return (sTop and sBot and iTop and iBot and iBot < sTop and iTop > sBot) and true or false
                end
            end

            -- Thumb drag: the scroll moves by the cursor's travel as a share of
            -- the thumb's free travel. While it runs the menu ignores clicks
            -- outside it (menu._ddThumbDragging), so a drag past its edge does
            -- not close it.
            local ddDragging = false
            local ddDragStartY, ddDragStartScroll
            local function EndThumbDrag(knob)
                ddDragging = false
                dropMenu._ddThumbDragging = false
                knob:SetScript("OnUpdate", nil)
            end

            menuKnob:SetScript("OnMouseDown", function(self, btnFrame)
                if btnFrame ~= "LeftButton" then
                    return
                end
                ddDragging = true
                dropMenu._ddThumbDragging = true
                StopSmooth()
                local _, cursorY = GetCursorPosition()
                ddDragStartY = cursorY / self:GetEffectiveScale()
                ddDragStartScroll = scroller:GetVerticalScroll()
                self:SetScript("OnUpdate", function(self2)
                    if not IsMouseButtonDown("LeftButton") then
                        EndThumbDrag(self2)
                        return
                    end
                    local _, curY = GetCursorPosition()
                    local deltaY = ddDragStartY - curY / self2:GetEffectiveScale()
                    local maxTravel = menuRail:GetHeight() - self2:GetHeight()
                    if maxTravel <= 0 then
                        return
                    end
                    local maxScroll = CludesUI.SafeScrollRange(scroller)
                    JumpTo(Clamp(ddDragStartScroll + (deltaY / maxTravel) * maxScroll))
                end)
            end)
            menuKnob:SetScript("OnMouseUp", function(self, btnFrame)
                if btnFrame ~= "LeftButton" then
                    return
                end
                EndThumbDrag(self)
            end)

            dropMenu:HookScript("OnHide", function()
                ddSmoothing = false
                ddSmoothFrame:Hide()
                ddScrollTarget = 0
                scroller:SetVerticalScroll(0)
            end)

            dropMenu:HookScript("OnShow", function()
                ddScrollTarget = 0
                scroller:SetVerticalScroll(0)
                UpdateDDThumb()
            end)
        else
            dropMenu:SetHeight(totalContentH + searchPad)
            if searchPad > 0 then
                innerHolder:ClearAllPoints()
                innerHolder:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, -searchPad)
                innerHolder:SetPoint("BOTTOMRIGHT", dropMenu, "BOTTOMRIGHT", 0, 0)
            else
                innerHolder:SetAllPoints(dropMenu)
            end
        end

        -- Optional search filter, wired once items/container/scroll helpers exist. Matches visible label text (any locale).
        if searchBox then
            local function ApplySearchFilter(raw)
                local q = strlower(strtrim(raw or ""))
                if searchPlaceholder then
                    searchPlaceholder:SetShown(q == "")
                end
                local visIdx = 0
                for _, entry in ipairs(menuItems) do
                    local name = (entry._label and entry._label:GetText()) or entry._displayName or ""
                    if q == "" or strfind(strlower(tostring(name)), q, 1, true) then
                        entry:Show()
                        entry:ClearAllPoints()
                        entry:SetPoint("TOPLEFT", innerHolder, "TOPLEFT", 1, -(4 + visIdx * _moItemH))
                        entry:SetPoint("TOPRIGHT", innerHolder, "TOPRIGHT", -1, -(4 + visIdx * _moItemH))
                        visIdx = visIdx + 1
                    else
                        entry:Hide()
                    end
                end
                innerHolder:SetHeight(math.max(1, 4 + visIdx * _moItemH + 3))
                if searchResetScroll then
                    searchResetScroll()
                end
            end
            searchBox:SetScript("OnTextChanged", function(self)
                ApplySearchFilter(self:GetText())
            end)
            -- Focus the dropdown search on open (not under the controller cursor: focus
            -- would pop its on-screen keyboard over the list; its Special press focuses).
            local function FocusSearch()
                searchBox:SetText("")
                ApplySearchFilter("")
                if not CludesUI.PadCursorShown() then
                    searchBox:SetFocus()
                end
            end
            dropMenu._focusSearch = FocusSearch
            dropMenu:HookScript("OnShow", FocusSearch)
            dropMenu:HookScript("OnHide", function()
                searchBox:SetText("")
                searchBox:ClearFocus()
            end)
        end

        local function Refresh()
            local current = getValue()
            for _, entry in ipairs(menuItems) do
                local off = disabledValuesFn and disabledValuesFn(entry._key)
                -- Subnav parent: highlight if cur is one of its child keys
                if entry._isSubnavParent then
                    local isChild = entry._subnavChildKeys and entry._subnavChildKeys[current]
                    entry._highlight:SetAlpha(isChild and DD_ITEM_SEL_A or 0)
                    entry._label:SetAlpha(1)
                    entry._label:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
                    local rowList = entry._flyoutRows
                    if rowList then
                        for idx = 1, #rowList do
                            local childFrame = rowList[idx]
                            childFrame._highlight:SetAlpha(childFrame._key == current and DD_ITEM_SEL_A or 0)
                        end
                    end
                else
                    entry._highlight:SetAlpha((entry._key == current and not off) and DD_ITEM_SEL_A or 0)
                    entry._label:SetAlpha(1)
                    if entry._isAction then
                        local ACC = CludesUI.CLUDES_GREEN
                        entry._label:SetTextColor(ACC.r, ACC.g, ACC.b, 0.8)
                    elseif entry._lblColor then
                        local lc = entry._lblColor
                        entry._label:SetTextColor(lc[1], lc[2], lc[3], off and 0.18 or lc[4])
                    else
                        entry._label:SetTextColor(
                            TEXT_DIM_R,
                            TEXT_DIM_G,
                            TEXT_DIM_B,
                            off and 0.18 or TEXT_DIM_A
                        )
                    end
                    if entry._note then
                        entry._note:SetAlpha(1)
                        entry._note:SetTextColor(
                            TEXT_DIM_R,
                            TEXT_DIM_G,
                            TEXT_DIM_B,
                            off and 0.12 or (TEXT_DIM_A * 0.75)
                        )
                    end
                end
            end
        end

        -- Controller open edge, run by the menu's OnShow (WireDropdownScripts): the
        -- no-wheel step strips for the gamepad-driven pointer, then the controller
        -- cursor onto the selected row (the first row when none is), scrolled into
        -- view. Mouse and keyboard stop at the first gate, unless strips an earlier
        -- controller open showed must be put away.
        dropMenu._padOpen = function()
            if not padStepSync and not CludesUI.PadInUse() then
                return
            end
            if padInit then
                padInit()
            end
            local cursor = CludesUI.PadCursorShown()
            -- The controller cursor scrolls the list itself, so the strips are for the pointer only.
            if padStepSync then
                padStepSync(not cursor and CludesUI.PadNative())
            end
            if not cursor then
                return
            end
            local current, target = getValue(), nil
            for idx = 1, #menuItems do
                local entry = menuItems[idx]
                if entry:IsShown() then
                    if not target then
                        target = entry
                    end
                    if entry._key == current or (entry._subnavChildKeys and entry._subnavChildKeys[current]) then
                        target = entry
                        break
                    end
                end
            end
            -- A row still clipped by the list (its range not laid out yet) cannot take
            -- the cursor: fall back to the first drawn stop in the list.
            if target and padReveal and not padReveal(target) then
                target = nil
            end
            CludesUI.PadFocus(target or dropMenu)
        end
        return dropMenu, menuItems, Refresh
    end

    -- CludesUI.SeatDropdownMenu(menu): a list hangs off its button, so a button
    -- on a half pixel (a centred header dropdown) put every row and caption on one
    -- too. Call after the list's scale is set: nudges its anchor so its top left
    -- corner lands on a whole screen pixel. The caller's own offsets stay the base,
    -- so repeated opens never drift.
    do
        local floor, abs = math.floor, math.abs
        function CludesUI.SeatDropdownMenu(dropMenu)
            if dropMenu:GetNumPoints() ~= 1 then
                return
            end
            local pt, relTo, rpt, posX, cursorY = dropMenu:GetPoint(1)
            -- Not the offsets this function set (read back as floats): the caller
            -- anchored the list again, so those are the new base.
            local sx, sy = dropMenu._seatedX, dropMenu._seatedY
            if not sx or abs(posX - sx) > 0.01 or abs(cursorY - sy) > 0.01 then
                dropMenu._seatX, dropMenu._seatY = posX, cursorY
            end
            posX, cursorY = dropMenu._seatX, dropMenu._seatY
            dropMenu:SetPoint(pt, relTo, rpt, posX, cursorY)
            local l, t = dropMenu:GetLeft(), dropMenu:GetTop()
            local keyName = dropMenu:GetEffectiveScale() / CludesUI.PP.perfect
            if l and t and keyName > 0 and not (issecretvalue(l) or issecretvalue(t)) then
                l, t = l * keyName, t * keyName
                posX, cursorY = posX + (floor(l + 0.5) - l) / keyName, cursorY + (floor(t + 0.5) - t) / keyName
                dropMenu:SetPoint(pt, relTo, rpt, posX, cursorY)
            end
            dropMenu._seatedX, dropMenu._seatedY = posX, cursorY
        end
    end

    -- Wire OnEnter/OnLeave/OnClick/OnShow/OnHide for a dropdown button + menu. s = { bg_r..a, bg_hr..ha, brd_r..a, brd_hr..ha, txt_r..a, txt_hr..ha } (24 values)
    -- ddBtn._valueDimA, when set, holds the value text at that alpha in both states (a greyed-out current value stays greyed under the cursor).
    local function WireDropdownScripts(dropdownBtn, dropCaption, backdrop, brd, dropMenu, refresh, cfg, keepClickHandler)
        local function ApplyNormal()
            dropCaption:SetTextColor(cfg[17], cfg[18], cfg[19], dropdownBtn._valueDimA or cfg[20])
            brd:SetColor(cfg[9], cfg[10], cfg[11], cfg[12])
            backdrop:SetColorTexture(cfg[1], cfg[2], cfg[3], cfg[4])
        end
        local function ApplyHover()
            dropCaption:SetTextColor(cfg[21], cfg[22], cfg[23], dropdownBtn._valueDimA or cfg[24])
            brd:SetColor(cfg[13], cfg[14], cfg[15], cfg[16])
            backdrop:SetColorTexture(cfg[5], cfg[6], cfg[7], cfg[8])
        end
        dropdownBtn:SetScript("OnEnter", function()
            ApplyHover()
            if dropdownBtn._ttText and not dropMenu:IsShown() then
                ShowWidgetTooltip(dropdownBtn, dropdownBtn._ttText, dropdownBtn._ttOpts)
            end
        end)
        dropdownBtn:SetScript("OnLeave", function()
            if not dropMenu:IsShown() then
                ApplyNormal()
                if dropdownBtn._ttText then
                    HideWidgetTooltip()
                end
            end
        end)
        -- keepClickHandler: caller owns OnClick/OnHide (BuildDropdownControl's lazy-menu path). Overwriting OnClick
        -- here would (a) pin this menu instance forever so _invalidateMenu could never rebuild -- clicks would Show()
        -- the orphaned menu, rendering behind everything since SetParent(nil) resets strata -- and (b) wipe any
        -- HookScripts callers attached to OnClick, since SetScript discards existing hooks.
        if not keepClickHandler then
            dropdownBtn:SetScript("OnClick", function()
                if dropdownBtn._ttText then
                    HideWidgetTooltip()
                end
                if dropMenu:IsShown() then
                    dropMenu:Hide()
                else
                    dropMenu:Show()
                end
            end)
            dropdownBtn:HookScript("OnHide", function()
                dropMenu:Hide()
            end)
        end
        -- Controller cursor: its Cancel press clicks the dropdown button, which closes the list.
        if CludesUI.PadCP() then
            dropMenu.CloseButton = dropdownBtn
        end
        dropMenu:SetScript("OnShow", function(self)
            -- Detect custom parenting via GetParent(); _menuOpts is out of scope here. The
            -- controller-cursor overlay layer covers UIParent 1:1, so it counts as UIParent.
            local mp = dropMenu:GetParent()
            if mp ~= UIParent and mp ~= CludesUI._overlayLayer then
                -- Scaled popup parent: scale is inherited, leave at 1 (nothing to match, nothing to go stale).
                self:SetScale(1)
            else
                -- On UIParent: match the panel's effective scale by walking GetScale() up to UIParent (always current); the button's GetEffectiveScale ratio can be stale right after the popup is (re)built.
                local cfg, f = 1, dropdownBtn
                while f and f ~= UIParent do
                    cfg = cfg * (f:GetScale() or 1)
                    f = f:GetParent()
                end
                self:SetScale(cfg)
            end
            -- Seat the list, then its outline: the outline's layer fit on its own
            -- show, before this scale and seat.
            CludesUI.SeatDropdownMenu(self)
            if self._ddBrd then
                self._ddBrd:Fit()
            end
            -- Track the open menu globally so popups don't treat clicks on it (which can extend outside the popup/panel) as a dismissing outside click.
            CludesUI._openDropdownMenu = self
            ApplyHover()
            refresh()
            -- This SetScript replaces BuildDropdownMenu's OnShow hook, so drive its search auto-focus directly.
            if dropMenu._focusSearch then
                dropMenu._focusSearch()
            end
            -- Controller open edge (step strips, cursor into the list); returns at once without one.
            if dropMenu._padOpen then
                dropMenu._padOpen()
            end
            self:SetScript("OnUpdate", function(frame)
                local flyoverFlyout = false
                if frame._flyouts then
                    for _, fo in ipairs(frame._flyouts) do
                        if fo:IsShown() and fo:IsMouseOver() then
                            flyoverFlyout = true
                            break
                        end
                    end
                end
                if
                    not frame:IsMouseOver()
                    and not dropdownBtn:IsMouseOver()
                    and not flyoverFlyout
                    and not frame._ddThumbDragging
                    and IsMouseButtonDown("LeftButton")
                then
                    frame:Hide()
                    return
                end
                -- Close when the button's bottom edge leaves the visible scroll area (skipped for buttons outside the scroll child, e.g. content header dropdowns).
                local scrollFrame = CludesUI._scrollFrame
                if scrollFrame then
                    -- Ancestor check cached on the button (runs once per menu open)
                    if dropdownBtn._inScrollChild == nil then
                        local scrollChild = scrollFrame.GetScrollChild and scrollFrame:GetScrollChild()
                        local found = false
                        if scrollChild then
                            local p = dropdownBtn:GetParent()
                            while p do
                                if p == scrollChild then
                                    found = true
                                    break
                                end
                                p = p:GetParent()
                            end
                        end
                        dropdownBtn._inScrollChild = found
                    end
                    if dropdownBtn._inScrollChild then
                        local sfTop = scrollFrame:GetTop()
                        local sfBot = scrollFrame:GetBottom()
                        local btnBot = dropdownBtn:GetBottom()
                        if sfTop and sfBot and btnBot then
                            if btnBot < sfBot or btnBot > sfTop then
                                frame:Hide()
                            end
                        end
                    end
                end
            end)
        end)
        dropMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
            if CludesUI._openDropdownMenu == self then
                CludesUI._openDropdownMenu = nil
            end
            if self._flyouts then
                for _, fo in ipairs(self._flyouts) do
                    fo:Hide()
                end
            end
            if dropdownBtn:IsMouseOver() then
                ApplyHover()
                if dropdownBtn._ttText then
                    ShowWidgetTooltip(dropdownBtn, dropdownBtn._ttText, dropdownBtn._ttOpts)
                end
            else
                ApplyNormal()
                if dropdownBtn._ttText then
                    HideWidgetTooltip()
                end
            end
            -- Controller cursor: back onto the dropdown button (a no-op once that is hidden too).
            if CludesUI.PadCursorShown() then
                CludesUI.PadFocus(dropdownBtn)
            end
        end)
        -- A no-op unless the menu sits on the controller-cursor overlay layer.
        CludesUI.TrackOverlay(dropMenu)
    end

    -- Pre-built colour arrays for the two dropdown styles
    local WD_DD_COLOURS = {
        DD_BG_R,
        DD_BG_G,
        DD_BG_B,
        DD_BG_A,
        DD_BG_R,
        DD_BG_G,
        DD_BG_B,
        DD_BG_HA,
        1,
        1,
        1,
        DD_BRD_A,
        1,
        1,
        1,
        DD_BRD_HA,
        1,
        1,
        1,
        DD_TXT_A,
        1,
        1,
        1,
        DD_TXT_HA,
    }
    local RD_DD_COLOURS = {
        DD_BG_R,
        DD_BG_G,
        DD_BG_B,
        DD_BG_A,
        DD_BG_R,
        DD_BG_G,
        DD_BG_B,
        DD_BG_HA,
        1,
        1,
        1,
        DD_BRD_A,
        1,
        1,
        1,
        DD_BRD_HA,
        1,
        1,
        1,
        DD_TXT_A,
        1,
        1,
        1,
        DD_TXT_HA,
    }

    -- The drift checks a slider drag held back (CludesUI._deferredDriftChecks),
    -- after a drag that ended without its release (BuildSliderCore's EndDragOnRecycle):
    -- run on the next frame, after the page pass or the pool reset that ended the
    -- drag, unless another drag began meanwhile (its own end runs them).
    local driftDrainQueued = false
    local function DrainDriftChecks()
        driftDrainQueued = false
        if CludesUI._sliderDragging then
            return
        end
        local checks = CludesUI._deferredDriftChecks
        if not checks then
            return
        end
        CludesUI._deferredDriftChecks = nil
        for func in pairs(checks) do
            func()
        end
    end
    local function QueueDriftDrain()
        if driftDrainQueued then
            return
        end
        driftDrainQueued = true
        C_Timer.After(0, DrainDriftChecks)
    end

    -- The final writes owed by drags a hide cut short (BuildSliderCore's EndDragOnHide):
    -- one hidden one-shot frame runs them once the pass that hid the track is over,
    -- later in the same frame. A write that cuts another drag short queues it in the
    -- other set, for the next run.
    local dragFinishes, dragFinishesSpare, dragFinisher = {}, {}, nil
    local function RunDragFinishes(self)
        self:Hide()
        local q = dragFinishes
        dragFinishes, dragFinishesSpare = dragFinishesSpare, q
        for func in pairs(q) do
            q[func] = nil
            func()
        end
    end
    local function QueueDragFinish(func)
        dragFinishes[func] = true
        if not dragFinisher then
            dragFinisher = CreateFrame("Frame")
            dragFinisher:Hide()
            dragFinisher:SetScript("OnUpdate", RunDragFinishes)
        end
        dragFinisher:Show()
    end

    -- Slider core (track + fill + thumb + input + drag logic). Returns: trackFrame, valBox, RefreshSlider, thumb
    local function BuildSliderCore(
        hostFrame,
        trackW,
        trackH,
        thumbSz,
        inputW,
        inputH,
        inputFontSz,
        inputAlpha,
        minVal,
        maxVal,
        step,
        getValue,
        setValue,
        isMultiWidget,
        snapPoints,
        valueSnap
    )
        -- Every write: Spec Overrides auto-capture (see BuildToggleControl: the
        -- slot is read before the setter runs), then the settings-changed mark.
        do
            local write = setValue
            setValue = function(...)
                local snap = CludesUI._SOAttribution(hostFrame)
                write(...)
                CludesUI._NotifySettingWrite(hostFrame, snap)
                CludesUI._settingsChanged = true
            end
        end
        -- Multi-widget overrides: brighter track alpha, boosted input alpha
        local trkR, trkG, trkB, trkA = SL.TRACK_R, SL.TRACK_G, SL.TRACK_B, SL.TRACK_A
        if isMultiWidget then
            trkA = math.min(1, trkA + SL.MW_TRACK_BOOST)
            inputAlpha = math.min(1, inputAlpha + SL.MW_INPUT_BOOST)
        end

        local trackBar = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(trackBar, trackW, 20)
        trackBar:SetFrameLevel(hostFrame:GetFrameLevel() + 1)

        -- trackDark and trackFill only measure, never draw (the drag reads
        -- trackDark's left edge, the thumb rides trackFill's right edge); the
        -- pills on a pixel layer draw them, round-ended and crisp at every Window
        -- Scale, the fill's right end under the thumb.
        local trackDark = SolidTex(trackBar, "BACKGROUND", 0, 0, 0, 0)
        Pix.Size(trackDark, trackW, trackH)
        Pix.Point(trackDark, "CENTER", trackBar, "CENTER", 0, 0)

        local trackFill = SolidTex(trackBar, "BORDER", 0, 0, 0, 0)
        Pix.Height(trackFill, trackH)
        Pix.Point(trackFill, "LEFT", trackDark, "LEFT", 0, 0)

        local L = PX.Layer(trackBar, PX.SliderFit)
        local trackPill = L._frame:CreateTexture(nil, "BACKGROUND")
        trackPill:SetAllPoints(trackDark)
        trackPill:SetVertexColor(trkR, trkG, trkB, trkA)
        local fillPill = L._frame:CreateTexture(nil, "BORDER")
        fillPill:SetPoint("TOPLEFT", trackDark, "TOPLEFT", 0, 0)
        fillPill:SetPoint("BOTTOMRIGHT", trackFill, "BOTTOMRIGHT", 0, 0)
        fillPill:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, SL.FILL_A)

        local knob = CreateFrame("Button", nil, trackBar)
        Pix.Size(knob, thumbSz, thumbSz)
        knob:SetFrameLevel(trackBar:GetFrameLevel() + 2)
        knob:EnableMouse(true)
        Pix.Point(knob, "CENTER", trackFill, "RIGHT", 0, 0)
        -- Opaque blocker behind the thumb hides the track fill line; SetIgnoreParentAlpha keeps it solid when the slider grays out at 0.3.
        local thumbBlockerFrame = CreateFrame("Frame", nil, knob)
        thumbBlockerFrame:SetAllPoints()
        thumbBlockerFrame:SetFrameLevel(knob:GetFrameLevel())
        thumbBlockerFrame:SetIgnoreParentAlpha(true)
        local thumbBlocker = thumbBlockerFrame:CreateTexture(nil, "BACKGROUND")
        thumbBlocker:SetAllPoints()
        thumbBlocker:SetVertexColor(DARK_BG.r, DARK_BG.g, DARK_BG.b, 1)
        -- The thumb and its blocker are circles (white art, vertex colour).
        local thumbTex = knob:CreateTexture(nil, "ARTWORK")
        thumbTex:SetAllPoints()
        thumbTex:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
        L.track, L.fill, L.thumb, L.blocker = trackPill, fillPill, thumbTex, thumbBlocker
        L.trackRef, L.thumbRef = trackDark, knob
        L:Fit()

        local valueBox = CreateFrame("EditBox", nil, hostFrame)
        Pix.Size(valueBox, inputW, inputH)
        valueBox:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
        valueBox:SetAutoFocus(false)
        valueBox:SetNumeric(false)
        valueBox:SetMaxLetters(6)
        valueBox:SetJustifyH("CENTER")
        valueBox:SetFont(EXPRESSWAY, inputFontSz, "")
        valueBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
        local valBg = SolidTex(valueBox, "BACKGROUND", SL.INPUT_R, SL.INPUT_G, SL.INPUT_B, inputAlpha)
        valBg:SetAllPoints()
        MakeRoundedBorder(valueBox, BORDER_R, BORDER_G, BORDER_B, SL.INPUT_BRD_A, valBg)

        local function FormatVal(value)
            if step >= 1 then
                return tostring(math.floor(value + 0.5))
            elseif step < 0.1 then
                return string.format("%.2f", value)
            else
                return string.format("%.1f", value)
            end
        end

        -- Snap ANCHORED AT MIN, not at zero: the values a slider may land on are
        -- min, min + step, min + 2*step... A zero-anchored snap only agrees when
        -- min is itself a multiple of the step, and a slider whose min is not --
        -- an odd-count one like min 1, step 2 -- landed on the evens with its own
        -- minimum unreachable. Identical for every slider whose min IS a multiple
        -- of its step, which is all the rest of them. valueSnap (optional) then maps
        -- a grid value onto the values the setting allows (a range with a gap, such
        -- as 0 then 30 to 180): the drag, a typed value and the shown number all land
        -- on an allowed value.
        local function SnapStep(value)
            local snappedValue = minVal + math.floor((value - minVal) / step + 0.5) * step
            snappedValue = math.max(minVal, math.min(maxVal, snappedValue))
            if valueSnap then
                snappedValue = valueSnap(snappedValue)
            end
            return snappedValue
        end

        local currentVal = getValue()
        local function UpdateSliderVisual(val)
            local ratio = math.max(0, math.min(1, (val - minVal) / (maxVal - minVal)))
            trackFill:SetWidth(math.max(1, math.floor(trackW * ratio + 0.5)))
            local snappedValue = SnapStep(val)
            if not valueBox:HasFocus() then
                valueBox:SetText(FormatVal(snappedValue))
            end
        end
        UpdateSliderVisual(currentVal)

        local isDragging = false
        local rawDragVal = currentVal
        local lastSnapped = currentVal
        local lastCommitX = nil
        local stepped = ((maxVal - minVal) / step) < 20
        local dragScale, dragTrackLeft -- frozen at drag start to avoid feedback loops

        local function HalfStepPx()
            local range = maxVal - minVal
            if range <= 0 or step <= 0 then
                return 4
            end
            return math.max(2, (trackW / (range / step)) * 0.7)
        end

        -- The value under a cursor this far along the track, pulled onto a
        -- declared snap point within its threshold.
        local function ValueAt(cursorX)
            local ratio = math.max(0, math.min(1, cursorX / trackW))
            local value = math.max(minVal, math.min(maxVal, minVal + ratio * (maxVal - minVal)))
            if snapPoints then
                for _, sp in ipairs(snapPoints) do
                    local pt, threshold = sp[1], sp[2] or (step * 5)
                    if math.abs(value - pt) <= threshold then
                        return pt
                    end
                end
            end
            return value
        end

        -- A drag holds the slider-drag count up (refreshes and drift checks
        -- wait for it to drop), the track's hide and the pool's reset end it,
        -- and the track's OnUpdate follows the cursor.
        local EndDragOnRecycle, EndDragOnHide
        local function StartDrag()
            isDragging = true
            CludesUI._sliderDragging = (CludesUI._sliderDragging or 0) + 1
            trackBar._cuiOnRecycle = EndDragOnRecycle
            trackBar:SetScript("OnHide", EndDragOnHide)
        end
        local function StopDrag()
            isDragging = false
            trackBar:SetScript("OnUpdate", nil)
            trackBar:SetScript("OnHide", nil)
            trackBar._cuiOnRecycle = nil
            dragScale = nil
            dragTrackLeft = nil
            lastCommitX = nil
            CludesUI._sliderDragging = math.max(0, (CludesUI._sliderDragging or 1) - 1)
            if CludesUI._sliderDragging == 0 then
                CludesUI._sliderDragging = nil
            end
        end

        -- Every write below may run a setter that rebuilds the page and dresses this slider
        -- again for another use (the options page pool): what follows the write stands down
        -- then, as the rebuild already painted the slider. Write answers whether the
        -- slider still has the dress it wrote from.
        local function Write(value)
            local g = PoolGen(trackBar)
            setValue(value)
            return PoolGen(trackBar) == g
        end
        local function CommitSnap()
            local snappedValue = SnapStep(rawDragVal)
            if not Write(snappedValue) then
                return
            end
            currentVal = snappedValue
            rawDragVal = snappedValue
            lastSnapped = snappedValue
            UpdateSliderVisual(snappedValue)
        end

        -- The track stops showing mid-drag (a forced refresh dropped or rebuilt the page,
        -- the page reuse parked the track or reset it for another use, the settings
        -- window closed), so the release never arrives: the drag ends here as EndDrag
        -- ends it, minus the final write (every step was written while dragging; a plain
        -- hide owes that write, see EndDragOnHide). _cuiOnRecycle (run by the pool's
        -- reset) and, through EndDragOnHide, the track's OnHide point here only while a
        -- drag runs; the drift checks the drag held back run on the next frame.
        function EndDragOnRecycle()
            if not isDragging then
                return
            end
            StopDrag()
            if not CludesUI._sliderDragging and CludesUI._deferredDriftChecks then
                QueueDriftDrain()
            end
        end

        -- A plain hide (the settings window closed, the page left or dropped) ends the
        -- drag the same way and still owes it EndDrag's final write: setters that hold
        -- work back while a drag runs (reload prompts, a full reload) do it then. The
        -- write runs once the pass that hid the track is over (QueueDragFinish), unless
        -- the pool dressed the track again meanwhile (a pool reset ends the drag through
        -- _cuiOnRecycle, with no write) or a new drag began.
        local hideGen
        local function FinishHiddenDrag()
            if isDragging or PoolGen(trackBar) ~= hideGen then
                return
            end
            CommitSnap()
        end
        function EndDragOnHide()
            if not isDragging then
                return
            end
            EndDragOnRecycle()
            hideGen = PoolGen(trackBar)
            QueueDragFinish(FinishHiddenDrag)
        end

        local function SliderOnUpdate(self)
            -- Safety: stop the drag if the button released while a modifier key stole the event
            if not IsMouseButtonDown("LeftButton") then
                StopDrag()
                CommitSnap()
                return
            end
            local es = dragScale or self:GetEffectiveScale()
            local posX = select(1, GetCursorPosition()) / es
            local leftX = dragTrackLeft or trackDark:GetLeft()
            if not leftX then
                return
            end
            local cursorX = posX - leftX
            rawDragVal = ValueAt(cursorX)
            local snappedValue = SnapStep(rawDragVal)
            local halfPx = HalfStepPx()
            local shouldCommit = snappedValue ~= lastSnapped
                and (lastCommitX == nil or math.abs(cursorX - lastCommitX) >= halfPx)
            if shouldCommit then
                -- (not dragging: the write rebuilt the page and its hide ended the drag)
                if not Write(snappedValue) or not isDragging then
                    return
                end
                currentVal = snappedValue
                lastSnapped = snappedValue
                lastCommitX = cursorX
                UpdateSliderVisual(stepped and snappedValue or rawDragVal)
            else
                -- lastSnapped for the visual prevents flicker at step boundaries
                UpdateSliderVisual(stepped and lastSnapped or rawDragVal)
            end
        end

        local function BeginDrag()
            StartDrag()
            dragScale = trackBar:GetEffectiveScale()
            dragTrackLeft = trackDark:GetLeft()
            local posX = select(1, GetCursorPosition()) / dragScale
            local leftX = dragTrackLeft
            if leftX then
                local cursorX = posX - leftX
                rawDragVal = ValueAt(cursorX)
                local snappedValue = SnapStep(rawDragVal)
                UpdateSliderVisual(stepped and snappedValue or rawDragVal)
                if not Write(snappedValue) or not isDragging then
                    return
                end
                currentVal = snappedValue
                lastSnapped = snappedValue
                lastCommitX = cursorX
            end
            trackBar:SetScript("OnUpdate", SliderOnUpdate)
        end

        local function EndDrag()
            StopDrag()
            CommitSnap() -- final setValue runs with _sliderDragging cleared Snap() rounds
            if not CludesUI._sliderDragging then
                -- Deferred drift checks fire once every slider has finished dragging
                if CludesUI._deferredDriftChecks then
                    local checks = CludesUI._deferredDriftChecks
                    CludesUI._deferredDriftChecks = nil
                    for func in pairs(checks) do
                        func()
                    end
                end
                -- Re-evaluate widget state (sync icons, disabled overlays) once drag fully ends. Fast path: no page rebuild.
                CludesUI:RefreshPage()
            end
        end

        -- Re-entrancy guard: ClearFocus() below fires OnEditFocusLost, which re-enters CommitInput and would double the refresh sweep.
        local committingInput = false

        local function CommitInput()
            if committingInput then
                return
            end
            committingInput = true
            local raw = tonumber(valueBox:GetText())
            local changed = false
            if raw then
                raw = math.max(minVal, math.min(maxVal, raw))
                local snappedValue = SnapStep(raw)
                changed = snappedValue ~= currentVal
                if not Write(snappedValue) then
                    -- Dressed again by a rebuild the setter ran: its box lost focus there.
                    committingInput = false
                    return
                end
                currentVal = snappedValue
                rawDragVal = snappedValue
                UpdateSliderVisual(snappedValue)
            else
                valueBox:SetText(FormatVal(currentVal))
            end
            valueBox:ClearFocus()
            committingInput = false
            -- Typing must re-evaluate widget state exactly as EndDrag does, or the refresh sweep misses the change ("Apply to: All" sync indicator, disabled overlays). Only when the value changed (untouched box stays free); deferred while any slider is mid-drag to match EndDrag's once-per-drag refresh.
            if changed and not CludesUI._sliderDragging and CludesUI.RefreshPage then
                CludesUI:RefreshPage()
            end
        end

        valueBox:SetScript("OnEnterPressed", function()
            CommitInput()
        end)
        valueBox:SetScript("OnEscapePressed", function()
            valueBox:SetText(FormatVal(currentVal))
            valueBox:ClearFocus()
        end)
        valueBox:SetScript("OnEditFocusLost", function()
            CommitInput()
            valueBox:SetTextColor(TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B, TEXT_DIM_A)
        end)
        valueBox:SetScript("OnEditFocusGained", function()
            valueBox:SetTextColor(1, 1, 1, 1)
            valueBox:HighlightText()
        end)
        -- Up / Down in the box step the typed value by the slider's step (Shift:
        -- ten steps), within its range; Enter or leaving the box applies it.
        valueBox:SetScript("OnArrowPressed", function(self, itemKey)
            if itemKey ~= "UP" and itemKey ~= "DOWN" then
                return
            end
            local base = tonumber(self:GetText()) or currentVal
            local delta = (itemKey == "UP" and 1 or -1) * step * (IsShiftKeyDown() and 10 or 1)
            self:SetText(FormatVal(SnapStep(math.max(minVal, math.min(maxVal, base + delta)))))
        end)
        -- EditBox can fail to render SetText text right after becoming visible; nudging cursor position forces a re-render.
        valueBox:SetScript("OnShow", function()
            if not valueBox:HasFocus() then
                valueBox:SetText(FormatVal(currentVal))
                valueBox:SetCursorPosition(0)
            end
        end)

        local padNudged = false -- controller cursor press in progress (see OnMouseDown)
        trackBar:EnableMouse(true)
        trackBar:RegisterForDrag("LeftButton")
        trackBar:SetScript("OnDragStart", function() end) -- swallow drag so parent window doesn't move
        trackBar:SetScript("OnDragStop", function() end)
        trackBar:SetScript("OnMouseDown", function(_, btnFrame)
            if knob._sliderDisabled then
                return
            end
            -- Controller cursor: its press runs this track's mouse scripts with no mouse
            -- button down, so the hidden pointer's position means nothing. Such a press
            -- nudges one step instead (left click up, right click down) and its release
            -- is swallowed.
            if CludesUI.PadCursorShown() and not IsMouseButtonDown(btnFrame) then
                padNudged = true
                -- One step, or on through values a valueSnap maps back onto the
                -- current one, to the next allowed value that way.
                local dir = btnFrame == "RightButton" and -step or step
                local probe, value = currentVal, currentVal
                for _ = 1, 1000 do
                    probe = probe + dir
                    value = SnapStep(probe)
                    if value ~= currentVal or probe <= minVal or probe >= maxVal then
                        break
                    end
                end
                if value ~= currentVal then
                    if not Write(value) then
                        return
                    end
                    currentVal = value
                    rawDragVal = value
                    lastSnapped = value
                    UpdateSliderVisual(value)
                    -- Same widget-state refresh a typed value gets (CommitInput).
                    if not CludesUI._sliderDragging then
                        CludesUI:RefreshPage()
                    end
                end
                return
            end
            if btnFrame == "LeftButton" then
                BeginDrag()
            end
        end)
        -- A release ends only a drag this dress began: on a track the pool dressed
        -- again under a held button, the release of the earlier press does nothing.
        trackBar:SetScript("OnMouseUp", function(_, btnFrame)
            if padNudged then
                padNudged = false
                return
            end
            if knob._sliderDisabled then
                return
            end
            if btnFrame == "LeftButton" and isDragging then
                EndDrag()
            end
        end)
        -- Controller cursor: the track is the one stop; the pointer-drag thumb is skipped.
        CludesUI.PadHint(knob, "nodeignore")
        knob._sliderDisabled = false
        knob:RegisterForDrag("LeftButton")
        knob:SetScript("OnDragStart", function() end)
        knob:SetScript("OnDragStop", function() end)
        knob:SetScript("OnMouseDown", function(self, btnFrame)
            if self._sliderDisabled then
                return
            end
            if btnFrame == "LeftButton" then
                StartDrag()
                rawDragVal = currentVal
                trackBar:SetScript("OnUpdate", SliderOnUpdate)
            end
        end)
        knob:SetScript("OnMouseUp", function(self, btnFrame)
            if self._sliderDisabled then
                return
            end
            if btnFrame == "LeftButton" and isDragging then
                EndDrag()
            end
        end)

        -- Re-read the getter, update the visual, and re-apply the accent colour (theme may have changed on another tab).
        local function RefreshSlider()
            local value = getValue()
            if value then
                currentVal = value
                rawDragVal = value
                UpdateSliderVisual(value)
            end
            fillPill:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, SL.FILL_A)
            thumbTex:SetVertexColor(CLUDES_GREEN.r, CLUDES_GREEN.g, CLUDES_GREEN.b, 1)
        end
        RegisterWidgetRefresh(RefreshSlider)

        return trackBar, valueBox, RefreshSlider, knob
    end

    -------------------------------------------------------------------------------
    --  Pixel-unit sliders (cfg.pixel = true): saved value stays in WoW coordinate units (profile format unchanged);
    --  slider displays/edits whole physical screen pixels, so "1" is one on-screen pixel at any resolution/UI scale.
    --  min/max convert at build time so the physical range is unchanged (identity at pixel-perfect scale, PP.mult ==
    --  1). Supports both getValue/setValue (row configs) and get/set (cog popup rows) accessor conventions. Returns
    --  cfg untouched when the flag is off, so callers can pass every cfg through unconditionally.
    -------------------------------------------------------------------------------
    local function PixelizeSliderCfg(rowConf)
        -- Convert against the GAME screen grid (CludesUI.PP), not this file's panel-scale PanelPP: saved values live in UIParent coordinate units.
        local gamePP = CludesUI.PP
        if not (rowConf and rowConf.pixel and gamePP) then
            return rowConf
        end
        local px = {}
        for keyName, value in pairs(rowConf) do
            px[keyName] = value
        end
        px.min, px.max = gamePP.ToPixels(rowConf.min or 0), gamePP.ToPixels(rowConf.max or 0)
        -- A declared step of 1 means "finest available", not "one coordinate unit", so it must stay 1 px: converting it like min/max rounds 1 coord to 2 px whenever mult <= 2/3 (e.g. 4K at 0.71 uiScale), making odd pixel values unreachable. Only coarse steps (> 1 coordinate unit) convert, keeping their physical coarseness.
        local st = rowConf.step or 1
        px.step = st > 1 and math.max(1, math.floor(st / (gamePP.mult or 1) + 0.5)) or 1
        local get, set = rowConf.getValue or rowConf.get, rowConf.setValue or rowConf.set
        local pxGet = get
            and function()
                local value = get()
                return value and gamePP.ToPixels(value)
            end
        local pxSet = set and function(value)
            return set(gamePP.FromPixels(value))
        end
        if rowConf.getValue then
            px.getValue = pxGet
        end
        if rowConf.get then
            px.get = pxGet
        end
        if rowConf.setValue then
            px.setValue = pxSet
        end
        if rowConf.set then
            px.set = pxSet
        end
        return px
    end

    -------------------------------------------------------------------------------
    --  Border Size in pixels (the one control every bordered surface uses). Builds a
    --  DualRow slider cfg over a surface's legacy size key and its "<key>Px" companion
    --  (see CludesUI.BorderPx in CludesUI.lua). The slider SHOWS the pixels on
    --  screen: the exact size when one is set and still paired with the legacy step +
    --  texture, else the legacy size (solid = the step; textured = its edge at UIParent
    --  scale, 0 = hidden). It WRITES only on a real change: solid 0-4 keeps writing the
    --  legacy key alone (clearing a set exact size with false); anything else writes
    --  the nearest legacy step (old builds, legacy syncs and overrides keep working)
    --  and the exact size beside it. The range is the same on both styles, so a style
    --  pick never needs the row rebuilt.
    --  spec: getStep() -> number step (labels mapped by the caller), setStep(step),
    --        getTex() -> texture key, getPx() -> raw *Px value, setPx(v), apply()
    --        (refresh/render after a write), plus any cfg fields to pass through
    --        (disabled, disabledTooltip, requireState, rawTooltip, tooltip, text).
    -------------------------------------------------------------------------------
    function CludesUI.BorderPxSliderCfg(specInfo)
        local gamePP = CludesUI.PP
        local mult = (gamePP and gamePP.mult) or 1
        -- The largest legacy edge (Strong = 32 units) must stay reachable at any UI
        -- scale, to the next multiple of 8.
        local maxPx = math.max(32, math.ceil(32 / mult))
        maxPx = math.ceil(maxPx / 8) * 8
        local function Shown()
            local step, texture = specInfo.getStep(), specInfo.getTex()
            local px = CludesUI.BorderPx(specInfo.getPx(), step, texture)
            if px then
                return px
            end
            return CludesUI.BorderLegacyPx(step, texture)
        end
        local rowConf = {
            type = "slider",
            text = specInfo.text or "Border Size",
            min = 0,
            max = specInfo.max or maxPx,
            step = 1,
            getValue = Shown,
            setValue = function(value)
                value = math.floor(value + 0.5)
                if value == Shown() then
                    return
                end -- a click that changed nothing
                local texture = specInfo.getTex()
                local solid = not texture or texture == "" or texture == "solid"
                if solid and value <= 4 then
                    specInfo.setStep(value)
                    if specInfo.getPx() then
                        specInfo.setPx(false)
                    end
                else
                    local step = CludesUI.BorderPxStep(value, texture)
                    if value <= 0 then
                        specInfo.setStep(0)
                        if specInfo.getPx() then
                            specInfo.setPx(false)
                        end
                    else
                        specInfo.setStep(step)
                        specInfo.setPx(CludesUI.BorderPxString(value, step, texture))
                    end
                end
                if specInfo.apply then
                    specInfo.apply()
                end
            end,
        }
        for keyName, value in pairs(specInfo) do
            if
                rowConf[keyName] == nil
                and keyName ~= "getStep"
                and keyName ~= "setStep"
                and keyName ~= "getTex"
                and keyName ~= "getPx"
                and keyName ~= "setPx"
                and keyName ~= "apply"
                and keyName ~= "max"
            then
                rowConf[keyName] = value
            end
        end
        return rowConf
    end

    -------------------------------------------------------------------------------
    --  Border Width Offset | Border Height Offset: the textured border's outward offsets as their
    --  own DualRow (shown only while a textured style is selected; the caller builds
    --  the row conditionally). Each slider SHOWS what is drawn: the stored override
    --  when one is set, else the texture's default for the surface's registry row,
    --  scaled to an active exact size exactly as ApplyBorderStyle scales it. It
    --  compares in whole slider units: it WRITES nothing on a click that changes
    --  nothing, writes nil (follow the default again) when the value lands on the
    --  default the slider shows, and stores an override otherwise -- so the
    --  per-texture defaults keep seeding the value. With no exact size the shown
    --  default is the registry's own whole number.
    --  spec: addonKey (nil = the renderer passes none: global per-texture defaults),
    --        getTex(), getStep() (the numeric step the renderer passes), getSizeKey()
    --        (the registry sizeKey the renderer passes), getPx() (raw companion),
    --        getX()/setX(v), getY()/setY(v), apply(), plus pass-through cfg fields.
    --  Returns leftCfg, rightCfg.
    -------------------------------------------------------------------------------
    function CludesUI.BorderOffsetRowCfgs(specInfo)
        local function Defaults()
            local texture = specInfo.getTex()
            local dx, dy
            if specInfo.addonKey then
                dx, dy = CludesUI.GetBorderDefaults(specInfo.addonKey, texture, specInfo.getSizeKey())
            else
                dx = CludesUI.GetBorderTextureDefaultOffset(texture)
                dy = CludesUI.GetBorderTextureDefaultOffsetY(texture)
            end
            -- An active exact size scales the step's defaults (ApplyBorderStyle's rule).
            local px = CludesUI.BorderPx(specInfo.getPx(), specInfo.getStep(), texture)
            if px then
                local PPg = CludesUI.PP
                local EM = CludesUI.BORDER_EDGE_MAP
                local f = (px * PPg.mult) / (EM[specInfo.getStep()] or EM[1])
                return PPg.Snap(dx * f), PPg.Snap(dy * f)
            end
            return dx, dy
        end
        local lo, hi = specInfo.min or -25, specInfo.max or 25
        -- A value as the slider shows it (SnapStep: whole units, clamped).
        local function Unit(posX)
            return math.max(lo, math.min(hi, math.floor(posX + 0.5)))
        end
        local function Make(textValue, get, set, pick)
            local rowConf = {
                type = "slider",
                text = textValue,
                min = lo,
                max = hi,
                step = 1,
                getValue = function()
                    local value = get()
                    if value ~= nil then
                        return value
                    end
                    return Unit(pick(Defaults()))
                end,
                setValue = function(value)
                    value = Unit(value)
                    local current = get()
                    local def = Unit(pick(Defaults()))
                    if value == (current ~= nil and Unit(current) or def) then
                        return
                    end
                    if value == def then
                        set(nil)
                    else
                        set(value)
                    end
                    if specInfo.apply then
                        specInfo.apply()
                    end
                end,
            }
            for keyName, val in pairs(specInfo) do
                if
                    rowConf[keyName] == nil
                    and keyName ~= "addonKey"
                    and keyName ~= "getTex"
                    and keyName ~= "getStep"
                    and keyName ~= "getSizeKey"
                    and keyName ~= "getPx"
                    and keyName ~= "getX"
                    and keyName ~= "setX"
                    and keyName ~= "getY"
                    and keyName ~= "setY"
                    and keyName ~= "apply"
                    and keyName ~= "min"
                    and keyName ~= "max"
                then
                    rowConf[keyName] = val
                end
            end
            return rowConf
        end
        return Make("Border Width Offset", specInfo.getX, specInfo.setX, function(posX)
            return posX
        end),
            Make("Border Height Offset", specInfo.getY, specInfo.setY, function(_, cursorY)
                return cursorY
            end)
    end

    -- The same two offsets as rows of an inline cog's popup (BuildInlineCog rows);
    -- spec as above, its disabled / disabledTooltip carried onto both rows.
    function CludesUI.BorderOffsetCogRows(specInfo)
        local function Row(rowConf)
            return {
                type = "slider",
                label = rowConf.text,
                min = rowConf.min,
                max = rowConf.max,
                step = rowConf.step,
                get = rowConf.getValue,
                set = rowConf.setValue,
                disabled = rowConf.disabled,
                disabledTooltip = rowConf.disabledTooltip,
            }
        end
        local posX, cursorY = CludesUI.BorderOffsetRowCfgs(specInfo)
        return Row(posX), Row(cursorY)
    end

    -------------------------------------------------------------------------------
    --  WIDGET FACTORY
    -------------------------------------------------------------------------------
    local WidgetFactory = {}
    CludesUI.Widgets = WidgetFactory
    CludesUI._font = EXPRESSWAY
    CludesUI.CONTENT_PAD = CONTENT_PAD

    CludesUI.DD_STYLE = {
        BG_R = DD_BG_R,
        BG_G = DD_BG_G,
        BG_B = DD_BG_B,
        BG_A = DD_BG_A,
        BG_HA = DD_BG_HA,
        BRD_A = DD_BRD_A,
        BRD_HA = DD_BRD_HA,
        TXT_A = DD_TXT_A,
        TXT_HA = DD_TXT_HA,
        ITEM_HL_A = DD_ITEM_HL_A,
        ITEM_SEL_A = DD_ITEM_SEL_A,
    }

    -------------------------------------------------------------------------------
    --  Section cards: every section is drawn as its own panel, a raised body with a
    --  header band, from its heading down to the next heading on the same parent
    --  (or, for the last one, the lowest row on it once the page is built). The
    --  pieces are textures on the parent, under every row. They hide while a
    --  settings search is filtering the page, which moves and hides rows, and come
    --  back when it clears.
    -------------------------------------------------------------------------------
    local CARD = {
        INSET = 14, -- the card's edge outside the rows, left and right
        TOP = 10, -- the card's top below its heading frame's top
        GAP = 2, -- the card's bottom above the next heading frame's top
        BODY_A = 0.025,
        BAND_A = 0.035,
        EDGE_A = 0.10,
        open = {}, -- parent -> the card still waiting for its bottom
        all = setmetatable({}, { __mode = "k" }), -- every card, for the search toggle
    }

    -- A card with an on/off box in its header (SectionHeader's enable) dims its
    -- rows while off: every row placed on the parent between the heading and the
    -- card's end. A cue only; the rows stay usable.
    local function CardDimRows(cardFrame)
        if not (cardFrame.enable and cardFrame.bottomY) then
            return
        end
        local enabled = cardFrame.enable.getValue() and true or false
        local hostFrame = cardFrame.frame:GetParent()
        for _, childFrame in ipairs({ hostFrame:GetChildren() }) do
            if childFrame ~= cardFrame.frame and childFrame:GetNumPoints() > 0 then
                local point, relTo, relPoint, _, cursorY = childFrame:GetPoint(1)
                if
                    relTo == hostFrame
                    and point == "TOPLEFT"
                    and relPoint == "TOPLEFT"
                    and cursorY
                    and not (issecretvalue and issecretvalue(cursorY))
                    and cursorY < cardFrame.y
                    and cursorY > cardFrame.bottomY
                then
                    childFrame:SetAlpha(enabled and 1 or 0.35)
                end
            end
        end
    end

    -- bottomY: where the card ends, as an offset from the parent's TOPLEFT (the
    -- frame of reference every heading and row is placed in).
    local function CardSetBottom(cardFrame, bottomY)
        cardFrame.bottomY = bottomY
        for _, texture in ipairs(cardFrame.bottomed) do
            texture:ClearAllPoints()
        end
        local body, l, r, b = cardFrame.body, cardFrame.edgeL, cardFrame.edgeR, cardFrame.edgeB
        local dy = bottomY - cardFrame.y
        body:SetPoint("TOPLEFT", cardFrame.frame, "TOPLEFT", -CARD.INSET, -CARD.TOP)
        body:SetPoint("TOPRIGHT", cardFrame.frame, "TOPRIGHT", CARD.INSET, -CARD.TOP)
        body:SetPoint("BOTTOMLEFT", cardFrame.frame, "TOPLEFT", -CARD.INSET, dy)
        body:SetPoint("BOTTOMRIGHT", cardFrame.frame, "TOPRIGHT", CARD.INSET, dy)
        l:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
        l:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
        r:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
        r:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
        b:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", 0, 0)
    end

    local function BuildSectionCard(hostFrame, widget, cursorY)
        local function Tex(subMenu, a)
            local tex = hostFrame:CreateTexture(nil, "BACKGROUND", nil, subMenu)
            tex:SetColorTexture(1, 1, 1, a)
            return tex
        end
        -- gen: the heading's pool generation. The pool hands a rebuilt page the
        -- same objects again, so a card is live only while its heading is still
        -- on the dress it was built for.
        local cardFrame = { frame = widget, y = cursorY, gen = PoolGen(widget) }
        cardFrame.body = Tex(-6, CARD.BODY_A)
        cardFrame.band = Tex(-5, CARD.BAND_A)
        cardFrame.edgeL = Tex(-4, 0)
        cardFrame.edgeR = Tex(-4, 0)
        cardFrame.edgeT = Tex(-4, 0)
        cardFrame.edgeB = Tex(-4, 0)
        cardFrame.divider = Tex(-4, 0)
        for _, keyName in ipairs({ "edgeL", "edgeR", "edgeT", "edgeB", "divider" }) do
            cardFrame[keyName]:SetColorTexture(BORDER_COLOR.r, BORDER_COLOR.g, BORDER_COLOR.b, CARD.EDGE_A)
        end
        cardFrame.edgeL:SetWidth(1)
        cardFrame.edgeR:SetWidth(1)
        cardFrame.edgeT:SetHeight(1)
        cardFrame.edgeB:SetHeight(1)
        cardFrame.divider:SetHeight(1)
        -- The band runs from the card's top to the heading frame's bottom edge,
        -- with a divider under it; the top edge closes the card.
        cardFrame.band:SetPoint("TOPLEFT", cardFrame.body, "TOPLEFT", 0, 0)
        cardFrame.band:SetPoint("TOPRIGHT", cardFrame.body, "TOPRIGHT", 0, 0)
        cardFrame.band:SetPoint("BOTTOM", widget, "BOTTOM", 0, 0)
        cardFrame.divider:SetPoint("TOPLEFT", cardFrame.band, "BOTTOMLEFT", 0, 0)
        cardFrame.divider:SetPoint("TOPRIGHT", cardFrame.band, "BOTTOMRIGHT", 0, 0)
        cardFrame.edgeT:SetPoint("TOPLEFT", cardFrame.body, "TOPLEFT", 0, 0)
        cardFrame.edgeT:SetPoint("TOPRIGHT", cardFrame.body, "TOPRIGHT", 0, 0)
        cardFrame.bottomed = { cardFrame.body, cardFrame.edgeL, cardFrame.edgeR, cardFrame.edgeB }
        cardFrame.pieces = {
            cardFrame.body,
            cardFrame.band,
            cardFrame.edgeL,
            cardFrame.edgeR,
            cardFrame.edgeT,
            cardFrame.edgeB,
            cardFrame.divider,
        }
        -- Until it is closed, a card ends just under its own heading.
        CardSetBottom(cardFrame, cursorY - 50)
        -- A heading that hides (a section folded away) takes its card with it.
        widget:HookScript("OnHide", function()
            if PoolGen(widget) ~= cardFrame.gen then
                return
            end
            for _, tex in ipairs(cardFrame.pieces) do
                tex:Hide()
            end
        end)
        widget:HookScript("OnShow", function()
            if CARD.searching or PoolGen(widget) ~= cardFrame.gen then
                return
            end
            for _, tex in ipairs(cardFrame.pieces) do
                tex:Show()
            end
        end)
        CARD.all[cardFrame] = true
        return cardFrame
    end

    -- The lowest point (in parent TOPLEFT offsets) of the rows placed on parent.
    local function LowestRowOffset(hostFrame)
        local lowest
        for _, childFrame in ipairs({ hostFrame:GetChildren() }) do
            local num = childFrame:GetNumPoints()
            if num and num > 0 and childFrame:IsShown() then
                local point, relTo, relPoint, _, cursorY = childFrame:GetPoint(1)
                local height = childFrame:GetHeight()
                if
                    relTo == hostFrame
                    and point == "TOPLEFT"
                    and relPoint == "TOPLEFT"
                    and cursorY
                    and height
                    and not (issecretvalue and (issecretvalue(cursorY) or issecretvalue(height)))
                then
                    local bottom = cursorY - height
                    if not lowest or bottom < lowest then
                        lowest = bottom
                    end
                end
            end
        end
        return lowest
    end

    -- Called by the panel once a page is built: each parent's last card ends
    -- below the lowest row on it.
    -- Protected: a card is decoration, and a failure here must never stop the
    -- page it sits on from opening.
    function CludesUI._CloseSectionCards()
        local open = CARD.open
        CARD.open = {}
        for hostFrame, cardFrame in pairs(open) do
            pcall(function()
                local lowest = LowestRowOffset(hostFrame)
                if lowest then
                    CardSetBottom(cardFrame, lowest - 10)
                    CardDimRows(cardFrame)
                end
            end)
        end
    end

    -- Called by the panel's settings search: cards hide while a query filters the
    -- page and come back (for headings still shown) when it clears.
    function CludesUI._SetSectionCardsShown(isShown)
        CARD.searching = not isShown or nil
        for cardFrame in pairs(CARD.all) do
            if PoolGen(cardFrame.frame) ~= cardFrame.gen then
                CARD.all[cardFrame] = nil -- its heading was dressed again: not ours now
            else
                local enabled = isShown and cardFrame.frame:IsShown()
                for _, tex in ipairs(cardFrame.pieces) do
                    tex:SetShown(enabled)
                end
            end
        end
    end

    -- Section header  (e.g. "APPEARANCE", "KEY BINDING TEXT"). tooltip (optional):
    -- shown while the title is hovered. Each one opens a section card (above).
    -- enable (optional, opt-in): { getValue, setValue, tooltip } puts an on/off
    -- box at the right of the card's header, for a section with a master switch
    -- (which then needs no row of its own); the card's rows dim while it is off.
    function WidgetFactory:SectionHeader(hostFrame, textValue, yOffset, tooltip, enable)
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, 40)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)

        -- The card's title: white capitals in its header band.
        local label = MakeFont(widget, 13, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b, 0.92)
        Pix.Point(label, "BOTTOMLEFT", widget, "BOTTOMLEFT", 0, 9)
        label:SetText(CludesUI.L(textValue):upper())
        widget._label = label

        -- Title tooltip: a hit frame round the title, as a row label's; clicks
        -- pass through.
        if tooltip then
            local hitArea = CreateFrame("Frame", nil, widget)
            hitArea:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitArea:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitArea:SetScript("OnEnter", function()
                ShowWidgetTooltip(label, tooltip)
            end)
            hitArea:SetScript("OnLeave", function()
                HideWidgetTooltip()
            end)
            hitArea:SetMouseClickEnabled(false)
        end

        -- The section's card: the one before it on this parent ends above this
        -- heading, and this one stays open until the next heading or the page end.
        -- Protected, and tolerant of a heading placed without an offset: a card is
        -- decoration and must never stop its page from building.
        pcall(function()
            local cy = tonumber(yOffset) or 0
            local prev = CARD.open[hostFrame]
            if prev then
                CardSetBottom(prev, cy - CARD.GAP)
                CardDimRows(prev)
            end
            local cardFrame = BuildSectionCard(hostFrame, widget, cy)
            CARD.open[hostFrame] = cardFrame
            if type(enable) == "table" and enable.getValue and enable.setValue then
                cardFrame.enable = enable
                local button = CreateFrame("Button", nil, widget)
                button:SetSize(18, 18)
                button:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", 0, 6)
                button:SetFrameLevel(widget:GetFrameLevel() + 2)
                local boxFrame, _, _, apply = BuildCheckboxControl(button, button:GetFrameLevel() + 1)
                boxFrame:SetAllPoints(button)
                boxFrame:EnableMouse(false)
                -- "On" / "Off" beside the box, so a bare box in a header reads as a switch.
                local status = MakeFont(widget, 11, nil, TEXT_DIM_R, TEXT_DIM_G, TEXT_DIM_B)
                status:SetPoint("RIGHT", button, "LEFT", -6, 0)
                local function Paint(hover)
                    local enabled = enable.getValue() and true or false
                    apply(enabled, hover)
                    status:SetText(CludesUI.L(enabled and "On" or "Off"))
                    status:SetAlpha(enabled and 0.9 or 0.6)
                end
                button:SetScript("OnEnter", function()
                    Paint(true)
                    if enable.tooltip then
                        ShowWidgetTooltip(button, enable.tooltip)
                    end
                end)
                button:SetScript("OnLeave", function()
                    Paint(false)
                    HideWidgetTooltip()
                end)
                button:SetScript("OnClick", function()
                    local g = PoolGen(widget)
                    enable.setValue(not enable.getValue())
                    CludesUI._settingsChanged = true
                    -- A setter that rebuilt the page dressed this heading again: its new build paints.
                    if PoolGen(widget) ~= g then
                        return
                    end
                    Paint(true)
                    CardDimRows(cardFrame)
                end)
                RegisterWidgetRefresh(function()
                    if PoolGen(widget) ~= cardFrame.gen then
                        return
                    end
                    Paint(false)
                    CardDimRows(cardFrame)
                end)
                Paint(false)
                widget._enableBox = button
            end
            if CARD.searching then
                for _, tex in ipairs(cardFrame.pieces) do
                    tex:Hide()
                end
            end
        end)

        -- Restart the alternating row counter so each section begins fresh
        CludesUI._rowCounters[hostFrame] = 0

        -- Search metadata: mark as section header and track it on the parent
        widget._isSectionHeader = true
        widget._sectionName = textValue
        -- Bilingual search: localized name, set only when it differs (nil on enUS).
        local _snLoc = CludesUI.L(textValue)
        if _snLoc ~= textValue then
            widget._sectionNameLoc = _snLoc
        end
        hostFrame._currentSection = widget

        -- Global search index hook (see TagOptionRow); no-op without the optional CludesUI_GlobalSearch.lua. Trailing true marks this a SECTION so results render as "Section: Title Case" instead of an option row.
        if CludesUI._RegisterSearchEntry then
            local sel = CludesUI._buildingSelector
            CludesUI._RegisterSearchEntry(
                textValue,
                widget._sectionNameLoc,
                nil,
                CludesUI._buildingModule,
                CludesUI._buildingPage,
                textValue,
                sel and sel.setter,
                sel and sel.key,
                true
            )
        end

        return widget, 40
    end

    -- A dropdown button whose menu is built on its first click (BuildDropdownControl,
    -- W:WideDropdown): light hover scripts until then, and a click that builds the
    -- menu (build() -> menu, refresh) and wires it; WireDropdownScripts then replaces
    -- the hover scripts and keeps this OnClick and OnHide. s = the button's colour
    -- array (RD_DD_COLOURS / WD_DD_COLOURS). Returns drop(): forgets the built menu
    -- (hidden), so the next click builds it again; true when there was one.
    local function WireLazyDropdown(dropdownBtn, dropCaption, backdrop, brd, cfg, build)
        local dropMenu
        local function ApplyNormal()
            dropCaption:SetTextColor(cfg[17], cfg[18], cfg[19], dropdownBtn._valueDimA or cfg[20])
            brd:SetColor(cfg[9], cfg[10], cfg[11], cfg[12])
            backdrop:SetColorTexture(cfg[1], cfg[2], cfg[3], cfg[4])
        end
        local function ApplyHover()
            dropCaption:SetTextColor(cfg[21], cfg[22], cfg[23], dropdownBtn._valueDimA or cfg[24])
            brd:SetColor(cfg[13], cfg[14], cfg[15], cfg[16])
            backdrop:SetColorTexture(cfg[5], cfg[6], cfg[7], cfg[8])
        end
        dropdownBtn:SetScript("OnEnter", function()
            ApplyHover()
            if dropdownBtn._ttText then
                ShowWidgetTooltip(dropdownBtn, dropdownBtn._ttText, dropdownBtn._ttOpts)
            end
        end)
        dropdownBtn:SetScript("OnLeave", function()
            if not (dropMenu and dropMenu:IsShown()) then
                ApplyNormal()
            end
            if dropdownBtn._ttText then
                HideWidgetTooltip()
            end
        end)
        dropdownBtn:SetScript("OnClick", function()
            if dropdownBtn._ttText then
                HideWidgetTooltip()
            end
            if not dropMenu then
                local refresh
                dropMenu, refresh = build()
                -- keepClickHandler=true: this OnClick survives, so after drop() the next click builds the menu again.
                WireDropdownScripts(dropdownBtn, dropCaption, backdrop, brd, dropMenu, refresh, cfg, true)
            end
            if dropMenu:IsShown() then
                dropMenu:Hide()
            else
                dropMenu:Show()
            end
        end)
        dropdownBtn:HookScript("OnHide", function()
            if dropMenu then
                dropMenu:Hide()
            end
        end)
        return function()
            if not dropMenu then
                return false
            end
            dropMenu:Hide()
            dropMenu = nil
            return true
        end
    end

    -- Fully wired dropdown control (button + bg + border + label + arrow + menu). Returns ddBtn, ddLbl so the caller can position it and register a refresh. Menu is built lazily on first click to cut initial allocation.
    local function BuildDropdownControl(
        hostFrame,
        ddW,
        fLevel,
        values,
        sequence,
        getValue,
        setValue,
        disabledValuesFn
    )
        local dropdownBtn = CreateFrame("Button", nil, hostFrame)
        Pix.Size(dropdownBtn, ddW, 30)
        dropdownBtn:SetFrameLevel(fLevel)
        local ddBg = SolidTex(dropdownBtn, "BACKGROUND", DD_BG_R, DD_BG_G, DD_BG_B, DD_BG_A)
        ddBg:SetAllPoints()
        local ddBrd = MakeRoundedBorder(dropdownBtn, 1, 1, 1, DD_BRD_A, ddBg)
        -- The value's resting alpha is the text colour's, the channel the hover
        -- colours (RD_DD_COLOURS) write, so a hover and leave land back on it.
        local dropCaption = MakeFont(dropdownBtn, 13, nil, 1, 1, 1, DD_TXT_A)
        dropCaption:SetJustifyH("LEFT")
        dropCaption:SetWordWrap(false)
        dropCaption:SetMaxLines(1)
        dropCaption:SetPoint("LEFT", dropdownBtn, "LEFT", 12, 0)
        local arrowTex = MakeDropdownArrow(dropdownBtn, 12, Pix)
        dropCaption:SetPoint("RIGHT", arrowTex, "LEFT", -5, 0)
        if not sequence then
            sequence = {}
            for itemKey in pairs(values) do
                sequence[#sequence + 1] = itemKey
            end
        end
        dropCaption:SetText(DDResolveLabel(values, sequence, getValue()))

        -- The menu is built on the first click (WireLazyDropdown); after _invalidateMenu() the next click builds it again.
        local dropMenu = WireLazyDropdown(dropdownBtn, dropCaption, ddBg, ddBrd, RD_DD_COLOURS, function()
            -- A local _: a global _ would hold the menu's item list, and through it the page the menu was opened from.
            local m, _, r = BuildDropdownMenu(
                dropdownBtn,
                ddW,
                sequence,
                values,
                getValue,
                setValue,
                dropCaption,
                "regular",
                disabledValuesFn
            )
            dropdownBtn._ddMenu = m
            dropdownBtn._ddRefresh = r
            return m, r
        end)
        -- Public: invalidate the cached menu so the next click rebuilds from the current `order`/`values`. For dropdowns whose options change at runtime (e.g. one listing the spells currently on a CDM bar).
        -- The menu frame itself stays this button's (the pool's kept frame): the next click populates the same frame again.
        dropdownBtn._invalidateMenu = function()
            if dropMenu() then
                dropdownBtn._ddMenu = nil
                dropdownBtn._ddRefresh = nil
            end
            -- Refresh the label too, in case the selection's label changed
            dropCaption:SetText(DDResolveLabel(values, sequence, getValue()))
        end

        -- Public: refresh only the displayed label from getValue, without rebuilding/invalidating the menu. Safe while the menu is wired/open, unlike _invalidateMenu (nils the cached menu, breaks the wired click). Use when an external change can alter what getValue returns (e.g. crosshair size showing "Custom" after a cog edit).
        dropdownBtn._refreshLabel = function()
            dropCaption:SetText(DDResolveLabel(values, sequence, getValue()))
        end

        return dropdownBtn, dropCaption
    end

    -- Bound a row label between its left inset and the control so overflow ellipsizes instead of running into the control (or off the row, for checkboxes). When truncated, the full label surfaces on hover: folded into the description tooltip when there is one, alone otherwise. Returns the hover text (nil if none) and whether it truncated.
    local function ClampRowLabel(label, rightFrame, rightPoint, gap, textValue, tooltip)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetMaxLines(1)
        label:SetPoint("RIGHT", rightFrame, rightPoint, -(gap or 12), 0)

        local truncated = false
        local nw, bw = label:GetStringWidth(), label:GetWidth()
        if not (issecretvalue and (issecretvalue(nw) or issecretvalue(bw))) then
            truncated = (nw or 0) > (bw or 0) + 0.5
        end

        if truncated and tooltip then
            -- Both parts pre-localized; the composite is not a catalog key, so ShowWidgetTooltip's L() leaves it untouched.
            return CludesUI.L(textValue) .. "\n" .. CludesUI.L(tooltip), true
        elseif truncated then
            return textValue, true
        end
        return tooltip, false
    end

    -- Label hover region (motion only, clicks pass through); created only when there is something to show.
    local function AttachLabelHover(hostFrame, label, hoverText)
        if not hoverText then
            return
        end
        local hitArea = CreateFrame("Frame", nil, hostFrame)
        hitArea:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
        hitArea:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
        hitArea:SetScript("OnEnter", function()
            ShowWidgetTooltip(label, hoverText)
        end)
        hitArea:SetScript("OnLeave", function()
            HideWidgetTooltip()
        end)
        hitArea:SetMouseClickEnabled(false)
        return hitArea
    end

    -- Deferred label clamp for row-half regions (DualRow / TripleRow). Half-region labels get their RIGHT edge
    -- bounded against the leftmost inline item (region._lastInline) or the control itself; runs one frame deferred
    -- because cogs/swatches/eyeballs attach AFTER the row builder returns. Overflowing labels then ellipsize instead
    -- of running under the controls; full text surfaces on hover: folded into the label tooltip when the row has one
    -- (hitFrames read region._labelTruncated via LabelTooltipText), else a plain reveal hover here.
    local _labelClampQueue, _labelClampQueued = {}, false
    -- Each queued region's dress generation (options page pool): a region dressed again
    -- before the flush is left to its new dress, which queues it again if it clamps.
    local _labelClampGen = {}
    local function _FlushLabelClamps()
        _labelClampQueued = false
        for idx = 1, #_labelClampQueue do
            local regionFrame = _labelClampQueue[idx]
            local gen = _labelClampGen[idx]
            _labelClampQueue[idx] = nil
            _labelClampGen[idx] = nil
            -- Hole-tolerant: an aborted earlier flush (a hard error mid-queue)
            -- can leave gaps; a nil entry must never take the whole pass down.
            local label = regionFrame and PoolGen(regionFrame) == gen and regionFrame._label
            local bound = regionFrame and (regionFrame._lastInline or regionFrame._control)
            if label and bound and label:IsShown() then
                local truncated = false
                local ll, bl, sw = label:GetLeft(), bound:GetLeft(), label:GetStringWidth()
                -- A row label menu's arrow (BuildRowLabelMenu) sits right after the text: keep its room too.
                local arrowTex = regionFrame._labelArrow
                local reserve = arrowTex and (6 + arrowTex:GetWidth()) or 0
                -- Not every inline item registers as _lastInline (a page's own cog
                -- or preview icon): the leftmost shown frame in the row right of
                -- the label's start bounds it too, so label and hint stop short of it.
                local extra = 0
                if ll and bl and not (issecretvalue and (issecretvalue(ll) or issecretvalue(bl))) then
                    for _, childFrame in ipairs({ regionFrame:GetChildren() }) do
                        if childFrame:IsShown() then
                            local cl = childFrame:GetLeft()
                            if
                                cl
                                and not (issecretvalue and issecretvalue(cl))
                                and cl > ll + 20
                                and cl < bl
                            then
                                extra = math.max(extra, bl - cl)
                            end
                        end
                    end
                    bl = bl - extra
                end
                if
                    ll
                    and bl
                    and sw
                    and not (issecretvalue and (issecretvalue(ll) or issecretvalue(bl) or issecretvalue(sw)))
                then
                    truncated = sw + reserve > (bl - 12 - ll) + 0.5
                    -- A row hint (DualRow) runs up to the control, cut with an ellipsis past it.
                    if regionFrame._hint then
                        regionFrame._hint:SetWidth(math.max(40, bl - 12 - ll))
                    end
                end
                -- Bound ONLY when overflowing: a right anchor stretches the rect and displaces label-edge-anchored subtitles on short labels.
                if truncated then
                    -- A label raised for a hint line (region._labelDY) keeps that height.
                    label:SetPoint("RIGHT", bound, "LEFT", -12 - reserve - extra, regionFrame._labelDY or 0)
                    -- The arrow was placed at the full text width: follow the cut label instead.
                    if arrowTex then
                        arrowTex:ClearAllPoints()
                        arrowTex:SetPoint("LEFT", label, "RIGHT", 6, -1)
                    end
                end
                regionFrame._labelTruncated = truncated
                if truncated and not regionFrame._labelHasHit and not regionFrame._labelRevealHit then
                    regionFrame._labelRevealHit = AttachLabelHover(regionFrame, label, label:GetText())
                end
            end
        end
    end
    local function QueueLabelClamp(regionFrame)
        if not regionFrame._label then
            return
        end
        local num = #_labelClampQueue + 1
        _labelClampQueue[num] = regionFrame
        _labelClampGen[num] = PoolGen(regionFrame)
        if not _labelClampQueued then
            _labelClampQueued = true
            C_Timer.After(0, _FlushLabelClamps)
        end
    end

    -- Label hover tooltip: prepend full label text when truncated (composite isn't a catalog key, so L() leaves it alone).
    local function LabelTooltipText(regionFrame, label, tipText)
        if regionFrame._labelTruncated then
            return (label:GetText() or "") .. "\n" .. CludesUI.L(tipText)
        end
        return tipText
    end

    -- An option row: the content width at yOffset, height tall, with the row
    -- background and the search tag for its label and tooltip.
    local function OptionRow(hostFrame, yOffset, height, textValue, tooltip)
        local widget = CreateFrame("Frame", nil, hostFrame)
        Pix.Size(widget, hostFrame:GetWidth() - CONTENT_PAD * 2, height)
        Pix.Point(widget, "TOPLEFT", hostFrame, "TOPLEFT", CONTENT_PAD, yOffset)
        RowBg(widget, hostFrame)
        TagOptionRow(widget, hostFrame, textValue, tooltip)
        return widget
    end

    -- Toggle switch  (pill-shaped, teal when ON, dark when OFF, animated)
    function WidgetFactory:Toggle(hostFrame, textValue, yOffset, getValue, setValue, tooltip)
        local ROW_H = 50
        local widget = OptionRow(hostFrame, yOffset, ROW_H, textValue, tooltip)
        local label = MakeFont(widget, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
        label:SetPoint("LEFT", widget, "LEFT", 20, 0)
        label:SetText(CludesUI.L(textValue))

        local toggle, _, tgSnap = BuildToggleControl(widget, widget:GetFrameLevel() + 1, getValue, setValue)
        toggle:SetPoint("RIGHT", widget, "RIGHT", -20, 0)

        AttachLabelHover(widget, label, (ClampRowLabel(label, toggle, "LEFT", 12, textValue, tooltip)))

        RegisterWidgetRefresh(tgSnap)

        -- Spec Overrides capture: see DualRow BuildHalf.
        widget._captureCfg = { type = "toggle", text = textValue, getValue = getValue, setValue = setValue }

        return widget, ROW_H
    end

    -- Slider with teal fill bar
    function WidgetFactory:Slider(
        hostFrame,
        textValue,
        yOffset,
        minVal,
        maxVal,
        step,
        getValue,
        setValue,
        tooltip,
        pixel
    )
        local ROW_H = 50
        local widget = OptionRow(hostFrame, yOffset, ROW_H, textValue, tooltip)
        local label = MakeFont(widget, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        Pix.Point(label, "LEFT", widget, "LEFT", 20, 0)
        label:SetText(CludesUI.L(textValue))
        local scfg = PixelizeSliderCfg({
            pixel = pixel,
            min = minVal,
            max = maxVal,
            step = step,
            getValue = getValue,
            setValue = setValue,
        })
        local trackBar, valueBox = BuildSliderCore(
            widget,
            320,
            4,
            14,
            40,
            26,
            13,
            SL.INPUT_A,
            scfg.min,
            scfg.max,
            scfg.step,
            scfg.getValue,
            scfg.setValue
        )
        Pix.Point(valueBox, "RIGHT", widget, "RIGHT", -20, 0)
        Pix.Point(trackBar, "RIGHT", valueBox, "LEFT", -16, 0)
        AttachLabelHover(widget, label, (ClampRowLabel(label, trackBar, "LEFT", 12, textValue, tooltip)))
        -- Spec Overrides capture: see DualRow BuildHalf.
        widget._captureCfg = {
            type = "slider",
            text = textValue,
            min = minVal,
            max = maxVal,
            step = step,
            getValue = getValue,
            setValue = setValue,
        }
        return widget, ROW_H
    end

    -- Dropdown  (optional 'order' is an array of keys for display order)
    function WidgetFactory:Dropdown(
        hostFrame,
        textValue,
        yOffset,
        values,
        getValue,
        setValue,
        sequence,
        tooltip
    )
        local ROW_H = 50
        local widget = OptionRow(hostFrame, yOffset, ROW_H, textValue, tooltip)
        local label = MakeFont(widget, 14, nil, TEXT_WHITE_R, TEXT_WHITE_G, TEXT_WHITE_B)
        label:SetAlpha(1)
        Pix.Point(label, "LEFT", widget, "LEFT", 20, 0)
        label:SetText(CludesUI.L(textValue))
        local dropdownBtn, dropCaption = BuildDropdownControl(
            widget,
            200,
            widget:GetFrameLevel() + 1,
            values,
            sequence,
            getValue,
            setValue
        )
        Pix.Point(dropdownBtn, "RIGHT", widget, "RIGHT", -20, 0)
        local hoverText = ClampRowLabel(label, dropdownBtn, "LEFT", 12, textValue, tooltip)
        if hoverText then
            local hitFrame = CreateFrame("Frame", nil, widget)
            hitFrame:SetPoint("TOPLEFT", label, "TOPLEFT", -5, 5)
            hitFrame:SetPoint("BOTTOMRIGHT", label, "BOTTOMRIGHT", 5, -5)
            hitFrame:SetScript("OnEnter", function()
                if not (dropdownBtn._ddMenu and dropdownBtn._ddMenu:IsShown()) then
                    ShowWidgetTooltip(label, hoverText)
                end
            end)
            hitFrame:SetScript("OnLeave", function()
                HideWidgetTooltip()
            end)
            hitFrame:SetMouseClickEnabled(false)
            dropdownBtn._ttText = hoverText
        end
        RegisterWidgetRefresh(function()
            dropCaption:SetText(DDResolveLabel(values, sequence, getValue()))
        end)
        return widget, ROW_H
    end

    -- Checkbox (small square box with checkmark, label to the right)
    function WidgetFactory:Checkbox(hostFrame, textValue, yOffset, getValue, setValue, tooltip)
        do
            local _r = setValue
            setValue = function(...)
                _r(...)
                CludesUI._settingsChanged = true
            end
        end
        local ROW_H = 36
        local widget = OptionRow(hostFrame, yOffset, ROW_H, textValue, tooltip)

        local button = CreateFrame("Button", nil, widget)
        Pix.Size(button, hostFrame:GetWidth() - CONTENT_PAD * 2, ROW_H)
        button:SetAllPoints(widget)

        local boxFrame, check, boxBorder, cbApply = BuildCheckboxControl(button, widget:GetFrameLevel() + 1)
        Pix.Point(boxFrame, "LEFT", button, "LEFT", 20, 0)

        local label = MakeFont(button, 14, nil, TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b)
        label:SetPoint("LEFT", boxFrame, "RIGHT", 10, 0)
        label:SetText(CludesUI.L(textValue))

        AttachLabelHover(button, label, (ClampRowLabel(label, button, "RIGHT", 20, textValue, tooltip)))

        local isHovering = false

        local function ApplyVisual()
            local enabled = getValue()
            cbApply(enabled, isHovering)
            if enabled then
                label:SetTextColor(TEXT_WHITE.r, TEXT_WHITE.g, TEXT_WHITE.b, 1)
            else
                local a = isHovering and 1 or 0.8
                label:SetTextColor(TEXT_WHITE.r * a, TEXT_WHITE.g * a, TEXT_WHITE.b * a, a)
            end
        end
        ApplyVisual()

        button:SetScript("OnClick", function()
            local value = not getValue()
            -- Stands down when the setter rebuilt the page and dressed this row again (the rebuild painted it).
            local g = PoolGen(button)
            setValue(value)
            if PoolGen(button) ~= g then
                return
            end
            ApplyVisual()
        end)

        button:SetScript("OnEnter", function()
            isHovering = true
            ApplyVisual()
        end)
        button:SetScript("OnLeave", function()
            isHovering = false
            ApplyVisual()
        end)

        RegisterWidgetRefresh(ApplyVisual)

        return widget, ROW_H
    end

    -- Global search prebuild: the frameless index pass (CludesUI_GlobalSearch.lua)
    -- builds every page against absorber rows, which take any call and hand back
    -- another absorber for any key. A control built on one indexes nothing, so its
    -- builder returns this stand-in instead of building it: an absorber that takes
    -- the control's calls and serves as its refresh function. Nil for a real parent
    -- and outside the pass.
    local function PrebuildStandIn(hostFrame)
        if not CludesUI._prebuilding or type(hostFrame) ~= "table" then
            return nil
        end
        if type(hostFrame.GetObjectType) == "function" then
            return nil
        end
        return hostFrame.prebuildStandIn
    end

    -- Helpers the other CludesUI_Widgets_*.lua files share; not public API.
    CludesUI._widgetInternals = {
        PrebuildStandIn = PrebuildStandIn,
        SL = SL,
        TagOptionRow = TagOptionRow,
        DDResolveLabel = DDResolveLabel,
        IndexSlotForSearch = IndexSlotForSearch,
        AddControlDisabledTooltip = AddControlDisabledTooltip,
        PixelizeSliderCfg = PixelizeSliderCfg,
        QueueLabelClamp = QueueLabelClamp,
        LabelTooltipText = LabelTooltipText,
        WireLazyDropdown = WireLazyDropdown,
    }

    -------------------------------------------------------------------------------
    --  Exports  (widget helpers CludesUI table for CludesUI_Presets.lua)
    -------------------------------------------------------------------------------
    CludesUI.DDText = DDText
    CludesUI.BuildDropdownMenu = BuildDropdownMenu
    CludesUI.WireDropdownScripts = WireDropdownScripts
    CludesUI.WD_DD_COLOURS = WD_DD_COLOURS
    CludesUI.RD_DD_COLOURS = RD_DD_COLOURS
    --------------------------------------------------------------------------------
    --  Preview click-to-navigate kit (options pages with a clickable preview)
    --------------------------------------------------------------------------------
    -- MakeSettingGlow: returns play(target, holdWhile). Each returned function shows
    -- one glow at a time, reparented on each play, so its new glow cancels its last
    -- one. opts: color {r,g,b} (read on first play), thickness (number or function,
    -- default 2), noSnap. holdWhile pulses while it returns true and the target
    -- is visible, then plays the normal 0.75s fade.
    -- The glow frames are shared by every play function with the same look: a glow
    -- whose fade ended goes back to its look's free list, off its target, and the
    -- next play of that look takes it, so a page built again makes no new ones (a
    -- glow still showing is never taken). On a target of the options page pool the
    -- glow rides along as the target's attachment and the target's reset frees it;
    -- such a glow only ever serves pool targets, so its pool record follows it.
    do
        local freeGlows = {} -- look key -> free glow frames (hidden, parentless)

        local function FreeGlow(glowTex)
            if glowTex._settingGlowFree then
                return
            end
            glowTex:Hide()
            glowTex:SetScript("OnUpdate", nil)
            glowTex:SetParent(nil)
            glowTex._settingGlowFree = true
            local entries = freeGlows[glowTex._settingGlowKey]
            entries[#entries + 1] = glowTex
        end

        local function TakeGlow(itemKey, red, green, blue, px, noSnap)
            local entries = freeGlows[itemKey]
            if not entries then
                entries = {}
                freeGlows[itemKey] = entries
            end
            local num = #entries
            if num > 0 then
                local glowTex = entries[num]
                entries[num] = nil
                glowTex._settingGlowFree = nil
                return glowTex
            end
            local glowTex = CreateFrame("Frame")
            local function MkEdge()
                local tex = glowTex:CreateTexture(nil, "OVERLAY", nil, 7)
                tex:SetColorTexture(red, green, blue, 1)
                if noSnap and tex.SetSnapToPixelGrid then
                    tex:SetSnapToPixelGrid(false)
                    tex:SetTexelSnappingBias(0)
                end
                return tex
            end
            local topY, bot, lft, rgt = MkEdge(), MkEdge(), MkEdge(), MkEdge()
            topY:SetHeight(px)
            topY:SetPoint("TOPLEFT")
            topY:SetPoint("TOPRIGHT")
            bot:SetHeight(px)
            bot:SetPoint("BOTTOMLEFT")
            bot:SetPoint("BOTTOMRIGHT")
            lft:SetWidth(px)
            lft:SetPoint("TOPLEFT", topY, "BOTTOMLEFT")
            lft:SetPoint("BOTTOMLEFT", bot, "TOPLEFT")
            rgt:SetWidth(px)
            rgt:SetPoint("TOPRIGHT", topY, "BOTTOMRIGHT")
            rgt:SetPoint("BOTTOMRIGHT", bot, "TOPRIGHT")
            glowTex._settingGlowKey = itemKey
            return glowTex
        end

        CludesUI.MakeSettingGlow = function(options)
            local token = {} -- this function's mark on the glow it holds
            local mine, look, lookPool, cr, cg, checkBtn, px
            return function(targetFrame, holdWhile)
                if not targetFrame then
                    return
                end
                if not look then
                    local color = options.color
                    cr, cg, checkBtn = color.r, color.g, color.b
                    px = options.thickness or 2
                    if type(px) == "function" then
                        px = px()
                    end
                    look = cr .. "|" .. cg .. "|" .. checkBtn .. "|" .. px .. (options.noSnap and "|n" or "|s")
                    lookPool = look .. "|pool"
                end
                local tgen = PoolGen(targetFrame)
                local itemKey = tgen and lookPool or look
                local glowTex = mine
                if glowTex and glowTex._settingGlowOwner == token then
                    if glowTex._settingGlowKey ~= itemKey then
                        -- serves the other kind of target: the last glow ends here
                        FreeGlow(glowTex)
                        glowTex = nil
                    elseif glowTex._settingGlowFree then
                        local entries = freeGlows[itemKey]
                        for idx = #entries, 1, -1 do
                            if entries[idx] == glowTex then
                                table.remove(entries, idx)
                                break
                            end
                        end
                        glowTex._settingGlowFree = nil
                    end
                else
                    glowTex = nil
                end
                if not glowTex then
                    glowTex = TakeGlow(itemKey, cr, cg, checkBtn, px, options.noSnap)
                    glowTex._settingGlowOwner = token
                    mine = glowTex
                end
                glowTex:SetParent(targetFrame)
                if tgen then
                    PoolAttach(targetFrame, glowTex, nil, FreeGlow)
                end
                glowTex:SetAllPoints(targetFrame)
                glowTex:SetFrameLevel(targetFrame:GetFrameLevel() + 5)
                glowTex:SetAlpha(1)
                glowTex:Show()
                local elapsed = 0
                glowTex:SetScript("OnUpdate", function(self, dt)
                    -- The target was dressed again for another use: this glow is over.
                    if tgen and PoolGen(targetFrame) ~= tgen then
                        FreeGlow(self)
                        return
                    end
                    elapsed = elapsed + dt
                    if holdWhile then
                        if targetFrame:IsVisible() and holdWhile() then
                            self:SetAlpha(0.35 + 0.65 * math.abs(math.sin(elapsed * 3)))
                            return
                        end
                        -- Released: restart the clock so the fade plays from full alpha.
                        holdWhile, elapsed = nil, 0
                    end
                    if elapsed >= 0.75 then
                        FreeGlow(self)
                        return
                    end
                    self:SetAlpha(1 - elapsed / 0.75)
                end)
            end
        end
    end

    -- CreatePreviewHitOverlay: clickable button over a preview element that calls
    -- navigate(key). opts (per call): hlAnchor, hlBehindText, parent, showWith.
    -- style (per page): container = draw the hover border on a child frame (and
    -- hlBehindText adds a frame at element level+1); tightText = AB text sizing.
    -- Returns btn, hlBase, hlCont (the last two only with style.container).
    CludesUI.CreatePreviewHitOverlay = function(
        element,
        navigate,
        itemKey,
        isText,
        frameLevelOverride,
        options,
        style
    )
        local tight = style and style.tightText
        local anchor = isText and element:GetParent() or element
        if not anchor.CreateTexture then
            anchor = anchor:GetParent()
        end
        local button = CreateFrame("Button", nil, anchor)
        if isText then
            local minS, pad = tight and 1 or 4, tight and 2 or 4
            local function ResizeToText()
                local success, tw, th = pcall(function()
                    local wid = element:GetStringWidth() or 0
                    local hh = element:GetStringHeight() or 0
                    if wid < minS then
                        wid = minS
                    end
                    if hh < minS then
                        hh = minS
                    end
                    return wid, hh
                end)
                if not success then
                    tw = 40
                    th = 12
                end
                button:SetSize(tw + pad, th + pad)
            end
            ResizeToText()
            local justify = element:GetJustifyH()
            if justify == "RIGHT" then
                button:SetPoint("RIGHT", element, "RIGHT", tight and 0 or 2, 0)
            elseif justify == "CENTER" then
                button:SetPoint("CENTER", element, "CENTER", tight and -1 or 0, 0)
            else
                button:SetPoint("LEFT", element, "LEFT", -2, 0)
            end
            button:SetScript("OnShow", function()
                ResizeToText()
            end)
            button._resizeToText = ResizeToText
        else
            button:SetAllPoints(options and options.hlAnchor or element)
        end
        -- opts.parent hosts the button outside a SetClipsChildren ancestor (which
        -- blocks mouse to descendants); opts.showWith re-ties its visibility.
        if options and options.parent then
            button:SetParent(options.parent)
        end
        button:SetFrameLevel(frameLevelOverride or (anchor:GetFrameLevel() + 20))
        button:RegisterForClicks("LeftButtonDown")
        local color = CludesUI.CLUDES_GREEN
        local hlBase, hlCont, brd
        if style and style.container then
            if options and options.hlBehindText then
                hlBase = CreateFrame("Frame", nil, element)
                hlBase:SetAllPoints()
                hlBase:SetFrameLevel(element:GetFrameLevel() + 1)
            else
                hlBase = (options and options.hlAnchor) or button
            end
            hlCont = CreateFrame("Frame", nil, hlBase)
            hlCont:SetAllPoints()
            hlCont:SetFrameLevel(hlBase:GetFrameLevel() + 1)
            brd = CludesUI.PP.CreateBorder(hlCont, color.r, color.g, color.b, 1, 2, "OVERLAY", 7)
        else
            local hlTarget = (options and options.hlBehindText) and element
                or (options and options.hlAnchor)
                or button
            brd = CludesUI.PP.CreateBorder(hlTarget, color.r, color.g, color.b, 1, 2, "OVERLAY", 7)
        end
        brd:Hide()
        button:SetScript("OnEnter", function()
            brd:Show()
        end)
        button:SetScript("OnLeave", function()
            brd:Hide()
        end)
        button:SetScript("OnMouseDown", function()
            navigate(itemKey)
        end)
        local sw = options and options.showWith
        if sw then
            sw:HookScript("OnShow", function()
                button:Show()
            end)
            sw:HookScript("OnHide", function()
                button:Hide()
            end)
            button:SetShown(sw:IsShown())
        end
        return button, hlBase, hlCont
    end

    -- DismissPreviewHint: first preview click marks the hint dismissed and fades
    -- it out over 0.3s while the content header shrinks back to headerBaseH.
    -- startY: fallback hint offset. The header shrinks by hintH, the height the
    -- hint added, so it lands exactly on headerBaseH.
    CludesUI.DismissPreviewHint = function(hint, headerBaseH, hintH, startY)
        if (CludesUIDB and CludesUIDB.previewHintDismissed) or not (hint and hint:IsShown()) then
            return
        end
        CludesUIDB = CludesUIDB or {}
        CludesUIDB.previewHintDismissed = true
        local _, anchorTo, _, _, y0 = hint:GetPoint(1)
        y0 = y0 or startY
        anchorTo = anchorTo or hint:GetParent()
        local startHeaderH = headerBaseH + hintH
        local steps = 0
        local ticker
        -- A hint of the options page pool that is dressed again mid-fade (its header was
        -- rebuilt) belongs to the new build: the fade stops and leaves it, and the header, alone.
        local g = PoolGen(hint)
        ticker = C_Timer.NewTicker(0.016, function()
            if PoolGen(hint) ~= g then
                ticker:Cancel()
                return
            end
            -- The hint's page was left mid-fade (the panel is up and the hint is not
            -- visible): the hint still fades out, but the header showing now is
            -- another page's and keeps its height (the hint's page sets its own on
            -- return). A closed or folded panel shows no other page meanwhile.
            local ownHeader = hint:IsVisible() or not CludesUI:IsShown() or CludesUI._panelCollapsed
            steps = steps + 1
            local progress = steps * 0.016 / 0.3
            if progress >= 1 then
                hint:Hide()
                ticker:Cancel()
                if ownHeader and headerBaseH > 0 then
                    CludesUI:SetContentHeaderHeightSilent(headerBaseH)
                end
                return
            end
            hint:SetAlpha(0.45 * (1 - progress))
            hint:ClearAllPoints()
            hint:SetPoint("BOTTOM", anchorTo, "BOTTOM", 0, y0 + progress * 12)
            local hh = startHeaderH - hintH * progress
            if ownHeader and hh > 0 then
                CludesUI:SetContentHeaderHeightSilent(hh)
            end
        end)
    end

    CludesUI.BuildSliderCore = BuildSliderCore
    CludesUI.BuildDropdownControl = BuildDropdownControl
    CludesUI.BuildToggleControl = BuildToggleControl
    CludesUI.BuildCheckboxControl = BuildCheckboxControl
    -- The toggle's pixel-layer fit for hand-built pills: L.track, L.knob, L.pad
    -- (units), L.apply places the knob from L.padPx, L.wp and L.d.
    CludesUI.TogglePillFit = PX.ToggleFit

    -------------------------------------------------------------------------------
    --  ShowPickMenu: the pick-one context menu (right-click "Add To" on manager
    --  tiles). A dark popup at the cursor with icon + label rows: disabled rows
    --  dim and take no clicks, the list scrolls past maxHeight, and the menu
    --  closes on a pick or on any click outside it (a full-screen catcher under
    --  it). One shared frame and row list, dressed again for every open.
    --  opts = { title, fontPath, items = { { key, label, icon, disabled } },
    --           onPick(key), width (default 230), maxHeight (default 320) }
    -------------------------------------------------------------------------------
    local PICK_ROW_H = 24

    local function BuildPickMenu()
        local dropMenu = CreateFrame("Frame", nil, CludesUI.OverlayParent())
        dropMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        dropMenu:SetFrameLevel(220)
        dropMenu:EnableMouse(true)
        dropMenu:SetClampedToScreen(true)
        local backdrop = dropMenu:CreateTexture(nil, "BACKGROUND")
        backdrop:SetAllPoints()
        backdrop:SetColorTexture(0.067, 0.067, 0.067, 0.98)
        MakeRoundedBorder(dropMenu, 1, 1, 1, 0.2, backdrop, nil, true)

        -- Shown and hidden with the menu, just under it.
        local catcher = CreateFrame("Button", nil, CludesUI.OverlayParent())
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(210)
        catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        catcher:SetScript("OnClick", function()
            dropMenu:Hide()
        end)
        catcher:Hide()
        dropMenu._catcher = catcher
        dropMenu:SetScript("OnHide", function(self)
            self._catcher:Hide()
            -- Controller cursor: back onto the tile that opened it (set only under that cursor).
            local opener = self._padOpener
            if opener then
                self._padOpener = nil
                if CludesUI.PadCursorShown() then
                    CludesUI.PadFocus(opener)
                end
            end
        end)
        dropMenu:SetScript("OnShow", function(self)
            self._catcher:Show()
        end)
        -- Controller cursor: on its overlay layer the menu is created hidden, so the
        -- layer shows only with it; the menu and its catcher block what they cover
        -- without being stops, and Cancel clicks the catcher (closing the menu).
        if CludesUI.PadCP() then
            dropMenu:Hide()
            CludesUI.PadHint(dropMenu, "nodepass")
            CludesUI.PadHint(catcher, "nodepass")
            dropMenu.CloseButton = catcher
            CludesUI.TrackOverlay(catcher)
            CludesUI.TrackOverlay(dropMenu)
        end

        local title = dropMenu:CreateFontString(nil, "OVERLAY")
        title:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 10, -7)
        title:SetTextColor(0.6, 0.6, 0.6)
        dropMenu._title = title

        -- The list: two rows a wheel notch, held inside the list's height.
        local scroll = CreateFrame("ScrollFrame", nil, dropMenu)
        scroll:SetClipsChildren(true)
        dropMenu._scroll = scroll
        local list = CreateFrame("Frame", nil, scroll)
        scroll:SetScrollChild(list)
        dropMenu._child = list
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel", function(self, delta)
            local maxS = math.max(0, dropMenu._child:GetHeight() - self:GetHeight())
            self:SetVerticalScroll(
                math.max(0, math.min(maxS, self:GetVerticalScroll() - delta * PICK_ROW_H * 2))
            )
        end)
        dropMenu._rows = {}
        return dropMenu
    end

    -- Row idx of the list: a hover wash (none on a disabled row), the icon and
    -- the label; a click on an enabled row closes the menu and reports its key.
    local function BuildPickRow(dropMenu, idx)
        local line = CreateFrame("Button", nil, dropMenu._child)
        line:SetHeight(PICK_ROW_H)
        line:SetPoint("TOPLEFT", dropMenu._child, "TOPLEFT", 0, -(idx - 1) * PICK_ROW_H)
        line:SetPoint("RIGHT", dropMenu._child, "RIGHT", 0, 0)
        local hov = line:CreateTexture(nil, "BACKGROUND")
        hov:SetAllPoints()
        hov:SetColorTexture(1, 1, 1, 0)
        line._hov = hov
        local iconTex = line:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(16, 16)
        iconTex:SetPoint("LEFT", line, "LEFT", 8, 0)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        line._icon = iconTex
        local labelFS = line:CreateFontString(nil, "OVERLAY")
        labelFS:SetPoint("RIGHT", line, "RIGHT", -8, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(false)
        line._lbl = labelFS
        line:SetScript("OnEnter", function(self)
            if not self._disabled then
                self._hov:SetColorTexture(1, 1, 1, 0.07)
            end
        end)
        line:SetScript("OnLeave", function(self)
            self._hov:SetColorTexture(1, 1, 1, 0)
        end)
        line:SetScript("OnClick", function(self)
            if self._disabled then
                return
            end
            dropMenu:Hide()
            if dropMenu._onPick then
                dropMenu._onPick(self._key)
            end
        end)
        return line
    end

    -- Dress a row for one item: the label clears the icon when there is one.
    local function DressPickRow(line, entry, fontFile)
        line._key = entry.key
        line._disabled = entry.disabled and true or false
        line._hov:SetColorTexture(1, 1, 1, 0)
        local caption = line._lbl
        caption:SetFont(fontFile, 12, "")
        caption:SetText(entry.label or tostring(entry.key))
        caption:ClearAllPoints()
        caption:SetPoint("RIGHT", line, "RIGHT", -8, 0)
        if entry.icon then
            line._icon:SetTexture(entry.icon)
            line._icon:Show()
            caption:SetPoint("LEFT", line, "LEFT", 30, 0)
        else
            line._icon:Hide()
            caption:SetPoint("LEFT", line, "LEFT", 10, 0)
        end
        if entry.disabled then
            line:SetAlpha(0.35)
            caption:SetTextColor(0.7, 0.7, 0.7)
        else
            line:SetAlpha(1)
            caption:SetTextColor(0.9, 0.9, 0.9)
        end
        line:Show()
    end

    function CludesUI.ShowPickMenu(anchor, options)
        options = options or {}
        local fontFile = options.fontPath or "Fonts\\FRIZQT__.TTF"
        local width = options.width or 230
        local itemList = options.items or {}

        local dropMenu = CludesUI._pickMenu
        if not dropMenu then
            dropMenu = BuildPickMenu()
            CludesUI._pickMenu = dropMenu
        end

        -- A title band only when there is a title.
        local titleH = 6
        if options.title then
            dropMenu._title:SetFont(fontFile, 11, "")
            dropMenu._title:SetText(options.title)
            dropMenu._title:Show()
            titleH = 24
        else
            dropMenu._title:Hide()
        end

        local listH = #itemList * PICK_ROW_H
        dropMenu:SetSize(width, titleH + math.min(listH, options.maxHeight or 320) + 8)
        dropMenu._scroll:ClearAllPoints()
        dropMenu._scroll:SetPoint("TOPLEFT", dropMenu, "TOPLEFT", 0, -titleH)
        dropMenu._scroll:SetPoint("BOTTOMRIGHT", dropMenu, "BOTTOMRIGHT", 0, 6)
        dropMenu._child:SetSize(width, math.max(listH, 1))
        dropMenu._scroll:SetVerticalScroll(0)

        local rowList = dropMenu._rows
        for idx, entry in ipairs(itemList) do
            local line = rowList[idx]
            if not line then
                line = BuildPickRow(dropMenu, idx)
                rowList[idx] = line
            end
            DressPickRow(line, entry, fontFile)
        end
        for idx = #itemList + 1, #rowList do
            rowList[idx]:Hide()
        end
        dropMenu._onPick = options.onPick

        -- Context-menu convention: open at the cursor (clamped on screen).
        -- Controller cursor: the hidden pointer is not on the tile, so open at
        -- the tile and put the cursor into the list.
        local scale = UIParent:GetEffectiveScale()
        local curX, curY = GetCursorPosition()
        dropMenu:ClearAllPoints()
        local padCursor = CludesUI.PadCursorShown()
        if padCursor and anchor then
            dropMenu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
        else
            dropMenu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", curX / scale + 2, curY / scale + 2)
        end
        dropMenu:Show()
        if padCursor then
            dropMenu._padOpener = anchor
            CludesUI.PadFocus(dropMenu)
        end
    end

    -------------------------------------------------------------------------------
    --  SharedMedia helpers: append LSM fonts/textures to dropdown tables
    --  Called from each options file after building its local font/texture tables.
    -------------------------------------------------------------------------------

    -- Eagerly build the SM font name->path lookup so ResolveFontName works immediately after deferred init (before any options page is opened).
    do
        local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
        if LSM then
            local smFonts = LSM:HashTable("font")
            if smFonts then
                local lut = {}
                for name, filePath in pairs(smFonts) do
                    lut[name] = filePath
                end
                CludesUI._smFontPaths = lut
            end
        end
    end
end -- end deferred init
