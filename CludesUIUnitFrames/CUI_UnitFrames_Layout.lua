if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_UnitFrames_Layout.lua
--
--  Mini frame donor and boss getters, text slot widths, the bottom text bar,
--  frame position, bar clip, border layout, frame dimensions and the health
--  bar, published through I for the files that load after this one. Reads
--  earlier files through ns and ns._internals; db is set through I.dbSetters.
-------------------------------------------------------------------------------
local _, mod = ...

local issecretvalue = issecretvalue
local Pix = CludesUI.PP

local Inner = mod._internals
local GetSettingsForUnit, UnitToSettingsKey, unitSettingsKey =
    Inner.GetSettingsForUnit, Inner.UnitToSettingsKey, Inner.unitSettingsKey
local SetFSFont, ApplyDarkTheme, SpecHasClassPower =
    Inner.SetFSFont, Inner.ApplyDarkTheme, Inner.SpecHasClassPower
local ApplyHealthBarTexture, ApplyHealthBarAlpha = Inner.ApplyHealthBarTexture, Inner.ApplyHealthBarAlpha
local ApplyClassIconTexture, ResolveRestrictedClassColor =
    Inner.ApplyClassIconTexture, Inner.ResolveRestrictedClassColor
local saved
Inner.dbSetters[#Inner.dbSetters + 1] = function(val)
    saved = val
end

-- A main frame a mini frame can take its look from: the key of a pick
-- ("player" always; "target" / "focus" while that frame is enabled and
-- Visibility does not keep it off screen entirely), else nil.
local function DonorPick(p, pick)
    if pick == "player" then
        return "player"
    end
    if pick == "target" or pick == "focus" then
        local s = p[pick]
        if p.enabledFrames[pick] ~= false and s and mod.VisEffective(s) ~= "never" then
            return pick
        end
    end
    return nil
end

-- The donor of a mini frame, the source of its inherited border, bar texture
-- and hover highlight: the main frame its Copy Look From picks (lookSource
-- "target" / "focus" / "player") while that frame can lend its look, else
-- Automatic (focus > target > player; boss frames always). Returns the key;
-- ns.GetMiniDonorSettings returns its settings table.
function mod.UF_MiniDonorKey(unitKey)
    local p = saved.profile
    local own = unitKey and p[unitKey]
    return DonorPick(p, own and own.lookSource) or DonorPick(p, "focus") or DonorPick(p, "target") or "player"
end
function mod.GetMiniDonorSettings(unitKey)
    return saved.profile[mod.UF_MiniDonorKey(unitKey)]
end
local GetMiniDonorSettings = mod.GetMiniDonorSettings

-- The frame a mini frame's auras take their look from (the pet's Copy Auras
-- From, auraSource, no default): its pick while that frame can lend its look,
-- else the frame its Copy Look From uses. Returns the key.
function mod.UF_MiniAuraSourceKey(unitKey)
    local p = saved.profile
    local own = p[unitKey]
    return DonorPick(p, own and own.auraSource) or mod.UF_MiniDonorKey(unitKey)
end

-- The two live tables behind a mini frame's aura settings view
-- (CUI_UnitFrames_AuraContainers.lua): its own and its aura source's, plus
-- that source's key. Read on every call: a profile switch, import or layer
-- paint can replace either table.
function mod.UF_MiniAuraTables(unitKey)
    local p = saved.profile
    local key = mod.UF_MiniAuraSourceKey(unitKey)
    return p[unitKey], p[key], key
end

-- The settings whose border keys paint the boss frames' unified border (and
-- its normal colour between hover / target recolours): the boss table's own
-- once its Border Style leaves "Inherit (Main Frames)" (borderCustom), else the
-- mini frame donor's. Boss1-5 share the one boss table.
function mod.UF_BossBorderSettings()
    local s = saved.profile.boss
    if s and s.borderCustom == true then
        return s
    end
    return GetMiniDonorSettings()
end

function mod.UF_BossAuraBorderAboveEffects(s)
    return s.auraBorderAboveEffects == true
        and not mod.UF_Blizz()
        and not s.auraBorderBehind
        and not s.auraBorderBehindUnitFrame
        and (s.auraBorderSize or 1) > 0
        and s.auraBorderTexture ~= nil
        and s.auraBorderTexture ~= "solid"
        and s.auraBorderTexture ~= ""
end

-- Boss "Simple Debuff Display" mode: "none"|"left"|"right". Tolerates legacy booleans
-- (true/nil="left", false="none") so existing/imported profiles read correctly with no
-- migration pass. "left"/"right" both force the frame-height-matched single column;
-- only the side differs.
function mod.GetBossSimpleDebuffMode(s)
    local val = s and s.simpleDebuffs
    if val == "none" or val == "left" or val == "right" then
        return val
    end
    if val == false then
        return "none"
    end
    return "left" -- nil or legacy true
end

-- Boss Simple Debuff Display X/Y offsets: dedicated simpleDebuffOffsetX/Y if set, else
-- the regular debuff offsets, so existing offsets carry over as simple-mode defaults
-- (zero-migration view; import-safe). Once the cog is edited, dedicated keys take over.
function mod.GetBossSimpleDebuffOffset(s)
    if not s then
        return 0, 0
    end
    local posX = s.simpleDebuffOffsetX
    if posX == nil then
        posX = s.debuffOffsetX or 0
    end
    local posY = s.simpleDebuffOffsetY
    if posY == nil then
        posY = s.debuffOffsetY or 0
    end
    return posX, posY
end

-- Boss "Simple Buff Display" mode: "none"|"left"|"right". Defaults OFF
-- (nil/false/unknown -> "none"); a stray boolean true reads as "left" (symmetry with the debuff resolver).
function mod.GetBossSimpleBuffMode(s)
    local val = s and s.simpleBuffs
    if val == "none" or val == "left" or val == "right" then
        return val
    end
    if val == true then
        return "left"
    end
    return "none"
end

-- Boss Simple Buff Display X/Y offsets. Mirrors ns.GetBossSimpleDebuffOffset
-- (simpleBuffOffsetX/Y if set, else regular buff offsets; zero-migration, import-safe).
function mod.GetBossSimpleBuffOffset(s)
    if not s then
        return 0, 0
    end
    local posX = s.simpleBuffOffsetX
    if posX == nil then
        posX = s.buffOffsetX or 0
    end
    local posY = s.simpleBuffOffsetY
    if posY == nil then
        posY = s.buffOffsetY or 0
    end
    return posX, posY
end

-- Boss aura icon spacing, in PHYSICAL pixels. Simple modes use dedicated keys
-- (simpleBuffSpacing/simpleDebuffSpacing); regular auras use buffSpacing/debuffSpacing.
-- No legacy equivalent, so every variant defaults to 1 independently. Callers convert
-- to coordinate space with PP.FromPixels for physical-pixel-perfect gaps at any scale.
-- (0 and negatives are truthy in Lua, so `or 1` only fills nil.)
function mod.GetBossBuffSpacing(s, simpleOn)
    if simpleOn then
        return (s and s.simpleBuffSpacing) or 1
    end
    return (s and s.buffSpacing) or 1
end
function mod.GetBossDebuffSpacing(s, simpleOn)
    if simpleOn then
        return (s and s.simpleDebuffSpacing) or 1
    end
    return (s and s.debuffSpacing) or 1
end

-- Per-slot Width % of the slot's computed clamp width (100 = normal truncation,
-- above 100 grants extra room). Applied by the position code to the slot
-- FontString's width box.
local function SlotWidthMul(prefs, prefixText)
    return (prefs[prefixText .. "WidthPct"] or 100) / 100
end

-- Build the per-slot "Name > Target" indicator tag. The separator is hex-encoded
-- per byte so any user-typed character (commas, parens, multibyte symbols)
-- survives the tag brackets; color rides as "class" or rrggbb hex (default white).
-- (The old content-key -> tag-string mapping lived here; text zones now
-- resolve through ns.ContentToZone and the engine text painter.)

-- Estimated pixel width per text content type, for name truncation. Flat
-- assumptions matching the nameplate system.
local UF_TEXT_PADDING = 10
local ufTextWidths = {
    both = 75, -- "132 K | 86%"
    bothdash = 75, -- "132 K - 86%"
    perhpnum = 75, -- "86% | 132 K"
    perhpnumdash = 75, -- "86% - 132 K"
    curhpshort = 38, -- "132 K"
    healthshort = 38,
    curmaxhp = 75, -- "132 K / 150 K"
    curmaxpp = 75, -- "132 K / 150 K"
    perhp = 38, -- "86%"
    perhpnosign = 30, -- "86"
    perpp = 38, -- "86%"
    curpp = 38, -- "132"
    curhp_curpp = 75, -- "132 K | 132"
    perhp_perpp = 75, -- "86% | 86%"
    absorb = 38, -- "12.3 K"
    level = 24, -- "80" / "??"
}
-- customFmt: the slot's <prefix>CustomFormat, read for content "custom" only,
-- estimated from the schema widths. Names count 0 like the Name content, except
-- on the right slot (isRight), whose estimate cuts the left text: there a name
-- keeps the schema's width so a long target name is not overlapped.
local function NoNameWidth(key)
    if key == "name" or key == "target" then
        return 0
    end
end
local function EstimateUFTextWidth(contentFrame, customFmt, isRight)
    if contentFrame == "custom" then
        local TT, category = CludesUI.TextTags, mod.UF_TextTags
        local parsed = TT.Parse(category, customFmt)
        if not parsed then
            return UF_TEXT_PADDING
        end
        return TT.EstimateWidth(category, parsed, not isRight and NoNameWidth or nil) + UF_TEXT_PADDING
    end
    return (ufTextWidths[contentFrame] or 0) + UF_TEXT_PADDING
end
mod.UF_EstimateTextWidth = EstimateUFTextWidth

-- Content that shows a power value, for the text bar's Power Colored mode: the
-- power presets, or a custom format with a power tag (customFmt, read for
-- "custom" only). The parse is cached, so the per-update call stays a lookup.
function mod.UF_IsPowerContent(contentFrame, customFmt)
    if
        contentFrame == "perpp"
        or contentFrame == "curpp"
        or contentFrame == "curmaxpp"
        or contentFrame == "curhp_curpp"
        or contentFrame == "perhp_perpp"
    then
        return true
    end
    if contentFrame ~= "custom" then
        return false
    end
    local parsed = CludesUI.TextTags.Parse(mod.UF_TextTags, customFmt)
    return parsed ~= nil and parsed.reads.pp == true
end

-- Apply class color to a FontString based on the unit.
local function ApplyClassColor(fontStr, unitToken, useClassColor, customR, customG, customB)
    if not fontStr then
        return
    end
    if useClassColor and unitToken then
        -- Class color for players (and AI party members), reaction color for NPCs,
        -- matching the health bar and the custom Enemy Colors override. Shared
        -- with the cui-tgtname tag via ns.ResolveUnitNameColor.
        local r, g, b = mod.ResolveUnitNameColor(unitToken)
        if r then
            fontStr:SetTextColor(r, g, b)
            return
        end
        -- ResolveUnitNameColor returns nil for a SECRET class token (identity-restricted
        -- units: focus-target, ToT) since it can't be used as a table key; the
        -- [cui-tgtcol] hex-escape tag it also feeds recovers a secret hex on its own
        -- and passes it through SetFormattedText. SetTextColor accepts secrets
        -- directly, so recover the real color here the same way the health bar does:
        -- the user's custom color when the unit matches a group member, else Blizzard's.
        if UnitIsPlayer(unitToken) or (UnitInPartyIsAI and UnitInPartyIsAI(unitToken)) then
            local _, classFile = UnitClass(unitToken)
            if issecretvalue(classFile) then
                local success, sr, sg, scrollBar = ResolveRestrictedClassColor(unitToken, classFile)
                if success then
                    fontStr:SetTextColor(sr, sg, scrollBar)
                    return
                end
            end
        end
    end
    fontStr:SetTextColor(customR or 1, customG or 1, customB or 1)
end

-- Recolours every text slot on a frame from its settings: the four text
-- positions, then the bottom text bar with its power colour re-applied last so
-- power-coloured slots win (class -> power, same order as ApplyBTBTextPositions).
-- Shared by the target/focus-changed updater and the text painter's UNIT_FACTION
-- branch (the painter only renders strings; colour lives here). `s` optional:
-- resolved strictly from the unit token, so an unmapped token recolours nothing.
-- On ns for the 200-locals cap.
function mod.UF_RecolorTexts(widget, unitToken, s)
    if not widget or not unitToken then
        return
    end
    if not s then
        local k = unitSettingsKey[unitToken]
        s = k and saved.profile[k]
    end
    if not s then
        return
    end
    if widget.LeftText and s.leftTextClassColor ~= nil then
        ApplyClassColor(
            widget.LeftText,
            unitToken,
            s.leftTextClassColor,
            s.leftTextColorR,
            s.leftTextColorG,
            s.leftTextColorB
        )
    end
    if widget.RightText and s.rightTextClassColor ~= nil then
        ApplyClassColor(
            widget.RightText,
            unitToken,
            s.rightTextClassColor,
            s.rightTextColorR,
            s.rightTextColorG,
            s.rightTextColorB
        )
    end
    if widget.CenterText and s.centerTextClassColor ~= nil then
        ApplyClassColor(
            widget.CenterText,
            unitToken,
            s.centerTextClassColor,
            s.centerTextColorR,
            s.centerTextColorG,
            s.centerTextColorB
        )
    end
    if widget.ExtraText and s.extraTextClassColor ~= nil then
        ApplyClassColor(
            widget.ExtraText,
            unitToken,
            s.extraTextClassColor,
            s.extraTextColorR,
            s.extraTextColorG,
            s.extraTextColorB
        )
    end
    local btb = widget._btb
    if btb then
        if btb.LeftText then
            ApplyClassColor(
                btb.LeftText,
                unitToken,
                s.btbLeftClassColor,
                s.btbLeftColorR,
                s.btbLeftColorG,
                s.btbLeftColorB
            )
        end
        if btb.RightText then
            ApplyClassColor(
                btb.RightText,
                unitToken,
                s.btbRightClassColor,
                s.btbRightColorR,
                s.btbRightColorG,
                s.btbRightColorB
            )
        end
        if btb.CenterText then
            ApplyClassColor(
                btb.CenterText,
                unitToken,
                s.btbCenterClassColor,
                s.btbCenterColorR,
                s.btbCenterColorG,
                s.btbCenterColorB
            )
        end
        if btb._applyBTBPowerColors then
            btb._applyBTBPowerColors(s)
        end
    end
end

-- Colors changed (CludesUI.ApplyColorsToOUF): texts are colored once when set,
-- so the class-colored ones repaint here with the new palette.
CludesUI._UFRecolorAllTexts = function()
    local frameList = Inner.frames
    if not (frameList and saved) then
        return
    end
    for unitToken in pairs(unitSettingsKey) do
        if frameList[unitToken] then
            mod.UF_RecolorTexts(frameList[unitToken], unitToken)
        end
    end
end

-- Bottom text bar frame: below the health+power area, above the castbar.
local function CreateBottomTextBar(widget, unitToken, prefs, anchorFrame, xOffset, overrideWidth)
    local btbH = prefs.bottomTextBarHeight or 16
    local btbPos = prefs.btbPosition or "bottom"
    local isDetached = (btbPos == "detached_top" or btbPos == "detached_bottom")
    local btbW = isDetached and (prefs.btbWidth or 0) or 0
    local totalWidth = (btbW > 0 and isDetached) and btbW or (overrideWidth or prefs.frameWidth)

    local btb = CreateFrame("Frame", nil, widget)
    Pix.Size(btb, totalWidth, btbH)
    btb._isDetached = isDetached

    if btbPos == "top" then
        Pix.Point(btb, "BOTTOMLEFT", widget.Health or anchorFrame, "TOPLEFT", xOffset or 0, 0)
    elseif btbPos == "detached_top" then
        btb:SetPoint("BOTTOM", widget, "TOP", prefs.btbX or 0, 15 + (prefs.btbY or 0))
    elseif btbPos == "detached_bottom" then
        btb:SetPoint("TOP", widget, "BOTTOM", prefs.btbX or 0, -15 + (prefs.btbY or 0))
    else -- "bottom"
        Pix.Point(btb, "TOPLEFT", anchorFrame, "BOTTOMLEFT", xOffset or 0, 0)
    end

    local bgc = prefs.btbBgColor or { r = 0.2, g = 0.2, b = 0.2 }
    local bga = prefs.btbBgOpacity or 1.0
    local bg = btb:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(bgc.r, bgc.g, bgc.b, bga)
    btb.bg = bg

    -- Text overlay, above the unified border at frame+10.
    local textOvr = CreateFrame("Frame", nil, btb)
    textOvr:SetAllPoints()
    textOvr:SetFrameLevel(widget:GetFrameLevel() + 15)

    local leftFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(leftFS, prefs.btbLeftSize or 11)
    leftFS:SetWordWrap(false)
    leftFS:SetTextColor(1, 1, 1)
    btb.LeftText = leftFS

    local rightFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(rightFS, prefs.btbRightSize or 11)
    rightFS:SetWordWrap(false)
    rightFS:SetTextColor(1, 1, 1)
    btb.RightText = rightFS

    local centerFS = textOvr:CreateFontString(nil, "OVERLAY")
    SetFSFont(centerFS, prefs.btbCenterSize or 11)
    centerFS:SetWordWrap(false)
    centerFS:SetTextColor(1, 1, 1)
    btb.CenterText = centerFS

    btb._textOverlay = textOvr

    local function ApplyBTBTextTags(lc, rc, cc)
        mod.SetTextZone(widget, leftFS, lc, "btbLeft", prefs)
        mod.SetTextZone(widget, rightFS, rc, "btbRight", prefs)
        mod.SetTextZone(widget, centerFS, cc, "btbCenter", prefs)
        mod.UF_PaintText(widget, widget._cuiUnit or unitToken)
    end

    -- Power-color override for power-content text. Mirrors the power bar text
    -- logic: the unit's own power type, white when the token cannot resolve.
    -- ApplyBTBPowerColors re-applies all three slots; it runs at layout time AND
    -- continuously from the power element's PostUpdateColor, so the color survives
    -- tag updates and power-type changes. The per-slot early-out (no power-color
    -- flag) keeps it ~free when unused.
    local function ApplyBTBPowerColor(fontStr, contentKey, usePowerColor, customFmt)
        if not fontStr or not usePowerColor then
            return
        end
        if mod.UF_IsPowerContent(contentKey, customFmt) then
            -- Secret-safe per-unit power color: player resolves via the clean
            -- string token; non-player units recover it from the clean integer
            -- power type instead of falling back to white.
            local r, g, b = CludesUI.ResolveUnitPowerColor(unitToken)
            if r then
                fontStr:SetTextColor(r, g, b)
            else
                fontStr:SetTextColor(1, 1, 1)
            end
        end
    end
    local function ApplyBTBPowerColors(s)
        ApplyBTBPowerColor(leftFS, s.btbLeftContent or "none", s.btbLeftPowerColor, s.btbLeftCustomFormat)
        ApplyBTBPowerColor(rightFS, s.btbRightContent or "none", s.btbRightPowerColor, s.btbRightCustomFormat)
        ApplyBTBPowerColor(
            centerFS,
            s.btbCenterContent or "none",
            s.btbCenterPowerColor,
            s.btbCenterCustomFormat
        )
    end

    local function ApplyBTBTextPositions(s)
        local lc = s.btbLeftContent or "none"
        local rc = s.btbRightContent or "none"
        local cc = s.btbCenterContent or "none"
        local lsz = s.btbLeftSize or 11
        local rsz = s.btbRightSize or 11
        local csz = s.btbCenterSize or 11

        SetFSFont(leftFS, lsz)
        leftFS:ClearAllPoints()
        if lc ~= "none" then
            leftFS:SetJustifyH("LEFT")
            Pix.Point(leftFS, "LEFT", textOvr, "LEFT", 5 + (s.btbLeftX or 0), s.btbLeftY or 0)
            Pix.Width(leftFS, totalWidth * 0.9 * SlotWidthMul(s, "btbLeft"))
            leftFS:Show()
        else
            leftFS:Hide()
        end

        SetFSFont(rightFS, rsz)
        rightFS:ClearAllPoints()
        if rc ~= "none" then
            rightFS:SetJustifyH("RIGHT")
            Pix.Point(rightFS, "RIGHT", textOvr, "RIGHT", -5 + (s.btbRightX or 0), s.btbRightY or 0)
            Pix.Width(rightFS, totalWidth * 0.9 * SlotWidthMul(s, "btbRight"))
            rightFS:Show()
        else
            rightFS:Hide()
        end

        SetFSFont(centerFS, csz)
        centerFS:ClearAllPoints()
        if cc ~= "none" then
            centerFS:SetJustifyH("CENTER")
            Pix.Point(centerFS, "CENTER", textOvr, "CENTER", s.btbCenterX or 0, s.btbCenterY or 0)
            Pix.Width(centerFS, totalWidth * 0.9 * SlotWidthMul(s, "btbCenter"))
            centerFS:Show()
        else
            centerFS:Hide()
        end

        ApplyClassColor(
            leftFS,
            unitToken,
            s.btbLeftClassColor,
            s.btbLeftColorR,
            s.btbLeftColorG,
            s.btbLeftColorB
        )
        ApplyClassColor(
            rightFS,
            unitToken,
            s.btbRightClassColor,
            s.btbRightColorR,
            s.btbRightColorG,
            s.btbRightColorB
        )
        ApplyClassColor(
            centerFS,
            unitToken,
            s.btbCenterClassColor,
            s.btbCenterColorR,
            s.btbCenterColorG,
            s.btbCenterColorB
        )
        -- Power color: after class color, and re-applied continuously from the
        -- power element's PostUpdateColor (btb._applyBTBPowerColors).
        ApplyBTBPowerColors(s)
    end

    ApplyBTBTextTags(
        prefs.btbLeftContent or "none",
        prefs.btbRightContent or "none",
        prefs.btbCenterContent or "none"
    )
    ApplyBTBTextPositions(prefs)

    btb._applyBTBTextTags = ApplyBTBTextTags
    btb._applyBTBTextPositions = ApplyBTBTextPositions
    btb._applyBTBPowerColors = ApplyBTBPowerColors

    -- Class icon overlay on a high-level frame so it renders above the border.
    local classIconHolder = CreateFrame("Frame", nil, widget)
    classIconHolder:SetAllPoints(textOvr)
    classIconHolder:SetFrameLevel(widget:GetFrameLevel() + 12)
    local classIconTex = classIconHolder:CreateTexture(nil, "ARTWORK")
    classIconTex:SetTexCoord(0, 1, 0, 1)
    classIconTex:Hide()
    btb.ClassIcon = classIconTex

    local function ApplyBTBClassIcon(s)
        local look = s.btbClassIcon or "none"
        if look == "none" then
            classIconTex:Hide()
            return
        end
        local _, classToken = UnitClass(unitToken)
        if issecretvalue(classToken) or not classToken then
            classIconTex:Hide()
            return
        end
        if not ApplyClassIconTexture(classIconTex, classToken, look) then
            classIconTex:Hide()
            return
        end
        local sz = s.btbClassIconSize or 14
        Pix.Size(classIconTex, sz, sz)
        classIconTex:ClearAllPoints()
        local loc = s.btbClassIconLocation or "left"
        local ox = s.btbClassIconX or 0
        local oy = s.btbClassIconY or 0
        if loc == "center" then
            Pix.Point(classIconTex, "CENTER", textOvr, "CENTER", ox, oy)
        elseif loc == "right" then
            Pix.Point(classIconTex, "RIGHT", textOvr, "RIGHT", -3 + ox, oy)
        else
            Pix.Point(classIconTex, "LEFT", textOvr, "LEFT", 3 + ox, oy)
        end
        classIconTex:Show()
    end

    ApplyBTBClassIcon(prefs)
    btb._applyBTBClassIcon = ApplyBTBClassIcon

    return btb
end

-- Positioning is handled by Unlock Mode.

local function ApplyFramePosition(widget, unitToken)
    if not widget or not saved.profile.positions[unitToken] then
        return
    end
    local place = saved.profile.positions[unitToken]
    -- UIParent offsets read in the frame's own scale (identity outside Frame Scale).
    local posX, posY = mod.UF_ScaledOffsets(widget, place.x, place.y)
    -- Snap to the physical pixel grid for deterministic positions across reloads.
    -- CENTER-anchored frames use SnapCenterForDim with actual width/height (preserves
    -- the +0.5 center offset odd-pixel-dimension frames need for whole-pixel edges);
    -- plain SnapForES rounds the center to whole pixels, forcing edges to half pixels
    -- and causing 1px drift on save/exit, spec swap, or profile change.
    local PPa = CludesUI and CludesUI.PP
    if PPa and posX and posY then
        local es = widget:GetEffectiveScale()
        local isCenterAnchor = (place.point == "CENTER" or place.point == nil)
            and (place.relPoint == "CENTER" or place.relPoint == nil)
        if isCenterAnchor and PPa.SnapCenterForDim then
            local fw = widget:GetWidth() or 0
            local fh = widget:GetHeight() or 0
            posX = PPa.SnapCenterForDim(posX, fw, es)
            posY = PPa.SnapCenterForDim(posY, fh, es)
        elseif PPa.SnapForES then
            posX = PPa.SnapForES(posX, es)
            posY = PPa.SnapForES(posY, es)
        end
    end
    widget:ClearAllPoints()
    widget:SetPoint(place.point, UIParent, place.relPoint or place.point, posX, posY)
end

-- Clip container for health + power bars: prevents sub-pixel overflow at UI scales
-- where independent pixel-snapping pushes edges 1px out. Inset by the border
-- thickness so the GPU cannot render bar pixels outside the border.
local function EnsureBarClip(widget)
    if widget._barClip then
        return widget._barClip
    end
    local clip = CreateFrame("Frame", nil, widget)
    clip:SetAllPoints(widget)
    clip:SetClipsChildren(true)
    clip:SetFrameLevel(widget:GetFrameLevel())
    clip:EnableMouse(false)
    widget._barClip = clip
    return clip
end

local function ReparentBarsToClip(widget, powerPosition, prefs)
    local clip = EnsureBarClip(widget)
    if widget.Health and widget.Health:GetParent() ~= clip then
        widget.Health:SetParent(clip)
    end
    if widget.Power then
        local detached = (powerPosition == "detached_top" or powerPosition == "detached_bottom")
        if detached then
            if widget.Power:GetParent() == clip then
                widget.Power:SetParent(widget)
            end
        else
            if widget.Power:GetParent() ~= clip then
                widget.Power:SetParent(clip)
            end
        end
        -- SetParent resets frame level, so re-assert after every reparent.
        if detached then
            -- Detached bars reparent onto `frame` itself (not the bar clip), which also
            -- holds the border at frame:GetFrameLevel()+10 (CreateUnifiedBorder/
            -- UpdatePowerBorder). hpLevel+2 would sit under that and let the border
            -- render over a detached power bar dragged onto its edge, so match
            -- CreatePowerBar's detached offset instead.
            widget.Power:SetFrameLevel(widget:GetFrameLevel() + 12)
        else
            -- Power bar must render above the absorb overlay (health level + 1).
            local hpLevel = widget.Health and widget.Health:GetFrameLevel() or clip:GetFrameLevel()
            widget.Power:SetFrameLevel(hpLevel + 2)
        end
        -- Reparent/SetFrameLevel leave the border and text overlay at stale
        -- absolute levels; re-apply after the final level is set.
        if prefs then
            mod.UpdatePowerBorder(widget.Power, prefs)
        end
    end
end

-- Recalculate every element size after a frame scale change so the stack stays
-- pixel-perfect inside the border. PixelUtil rounds each element independently, so
-- their sum can exceed the frame's snapped total by 1px at some scales; overflow is
-- trimmed off the last element after re-snapping.
local function UpdateBordersForScale(widget, unitToken)
    if not widget then
        return
    end
    local prefs = GetSettingsForUnit(unitToken)
    if not prefs then
        return
    end
    local borderSize = prefs.borderSize or 1

    -- 1) Main frame border textures.
    if widget.unifiedBorder then
        local bc = prefs.borderColor or { r = 0, g = 0, b = 0 }
        local textureKey = prefs.borderTexture or "solid"
        CludesUI.ApplyBorderStyle(
            widget.unifiedBorder,
            borderSize,
            bc.r,
            bc.g,
            bc.b,
            prefs.borderAlpha or 1,
            textureKey,
            prefs.borderTextureOffset,
            prefs.borderTextureOffsetY,
            prefs.borderTextureShiftX,
            prefs.borderTextureShiftY,
            "unitframes",
            borderSize,
            nil,
            CludesUI.BorderPx(prefs.borderSizePx, borderSize, textureKey)
        )
    end

    -- 2) Gather layout info.
    local ppPos = mod.UF_PowerPos(prefs)
    local ppIsAtt = (ppPos == "below" or ppPos == "above")
    local ppIsDet = (ppPos == "detached_top" or ppPos == "detached_bottom")
    local ph = prefs.powerHeight or 6
    -- Mini frames (pet/tot/focustarget) have no power bar: no power height.
    -- The exception is a WoW Forever pet off Blizzard Style, which has its own.
    local isMini = (unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget")
    local miniNoPower = isMini and not (unitToken == "pet" and mod.UF_PetHasPower and not mod.UF_Blizz())
    local powerH = (ppIsAtt and not miniNoPower) and ph or 0

    local btbPos = prefs.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbH = (prefs.bottomTextBar and btbIsAtt) and (prefs.bottomTextBarHeight or 16) or 0

    local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    if isMini and pStyle == "detached" then
        pStyle = "attached"
    end
    local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
    local isAttached = pStyle == "attached"
    -- Use the side the frame was actually built with, so frames like the pet that
    -- hard-code "left" are not treated as "right".
    local pSide = CludesUI._ufPortraitSide[widget] or prefs.portraitSide or "right"
    local effectiveSide = pSide
    if isAttached and pSide == "top" then
        effectiveSide = "right"
    end

    -- Class power above adds height (player only, only if the spec has a resource).
    local cpAboveH = 0
    if unitToken == "player" and SpecHasClassPower() then
        local cpSt = prefs.classPowerStyle or "none"
        if mod.UF_ForeverCPStyle then
            cpSt = mod.UF_ForeverCPStyle(cpSt)
        end
        local cpPo = (cpSt == "modern") and (prefs.classPowerPosition or "top") or "none"
        if cpSt == "modern" and cpPo == "above" then
            local cpSizeAdj = prefs.classPowerSize or 8
            cpAboveH = math.max(3, math.floor(cpSizeAdj * 0.375))
        end
    end

    local barHeight = prefs.healthHeight + powerH + cpAboveH
    local expectedFrameH = barHeight + btbH
    local pSideSnap = prefs.portraitSide or "left"
    local isInsideSnap = pSideSnap == "insideleft"
        or pSideSnap == "insideright"
        or pSideSnap == "insidecenter"
    local pSizeAdj = prefs.portraitSize or 0
    if not isAttached and not isInsideSnap then
        pSizeAdj = pSizeAdj + 10
    end
    local adjPortraitH = barHeight + pSizeAdj
    if adjPortraitH < 8 then
        adjPortraitH = 8
    end

    local expectedFrameW
    if not showPortrait or not isAttached then
        expectedFrameW = prefs.frameWidth
    else
        expectedFrameW = adjPortraitH + prefs.frameWidth
    end

    -- 3) Re-snap the frame itself.
    Pix.Size(widget, expectedFrameW, expectedFrameH)
    local snappedFrameW = widget:GetWidth()
    local snappedFrameH = widget:GetHeight()

    -- 4) Re-snap portrait and health bar (width axis).
    local healthTargetW = prefs.frameWidth
    if widget.Portrait and widget.Portrait.backdrop and showPortrait and isAttached and not isInsideSnap then
        Pix.Size(widget.Portrait.backdrop, adjPortraitH, adjPortraitH)
        local snappedPortW = widget.Portrait.backdrop:GetWidth()
        local snappedPortH = widget.Portrait.backdrop:GetHeight()
        -- Trim portrait width if it + health would exceed the frame.
        if snappedPortW + healthTargetW > snappedFrameW + 0.01 then
            Pix.Width(widget.Portrait.backdrop, snappedFrameW - healthTargetW)
            snappedPortW = widget.Portrait.backdrop:GetWidth()
        end
        -- Trim portrait height to frame height on overflow.
        if snappedPortH > snappedFrameH + 0.01 then
            Pix.Height(widget.Portrait.backdrop, snappedFrameH)
        end
    end

    -- 5) Re-snap health bar height and re-anchor to the snapped portrait width.
    if widget.Health then
        Pix.Height(widget.Health, prefs.healthHeight)
        -- Keep the health bar flush against the snapped portrait edge.
        if showPortrait and isAttached and widget.Portrait and widget.Portrait.backdrop then
            local snappedPortW = widget.Portrait.backdrop:GetWidth()
            local newXOff = (effectiveSide == "left") and snappedPortW or 0
            local newRightInset = (effectiveSide == "right") and snappedPortW or 0
            widget.Health._xOffset = newXOff
            widget.Health._rightInset = newRightInset
        end
    end

    -- 6) Re-snap power bar.
    if widget.Power and ppPos ~= "none" then
        local pw = prefs.frameWidth
        if ppIsDet and (prefs.powerWidth or 0) > 0 then
            pw = prefs.powerWidth
        end
        Pix.Size(widget.Power, pw, ph)
        if ppIsAtt and widget.Health then
            -- Height: health + power must not exceed the bar area.
            local snappedHealthH = widget.Health:GetHeight()
            local snappedPowerH = widget.Power:GetHeight()
            local expectedBarH = prefs.healthHeight + ph
            if snappedHealthH + snappedPowerH > expectedBarH + 0.01 then
                Pix.Height(widget.Power, snappedPowerH - (snappedHealthH + snappedPowerH - expectedBarH))
            end
            -- Width: match the health bar exactly.
            local snappedHealthW = widget.Health:GetWidth()
            local snappedPowerW = widget.Power:GetWidth()
            if math.abs(snappedPowerW - snappedHealthW) > 0.01 then
                Pix.Width(widget.Power, snappedHealthW)
            end
        elseif not ppIsDet then
            -- Non-attached non-detached should not happen; trim width to frame.
            local snappedPowerW = widget.Power:GetWidth()
            if snappedPowerW > snappedFrameW + 0.01 then
                Pix.Width(widget.Power, snappedFrameW)
            end
        end
    end

    -- 7) Re-snap BTB.
    if widget.BottomTextBar and prefs.bottomTextBar and btbIsAtt then
        Pix.Size(widget.BottomTextBar, expectedFrameW, prefs.bottomTextBarHeight or 16)
        local snappedBtbW = widget.BottomTextBar:GetWidth()
        local snappedBtbH = widget.BottomTextBar:GetHeight()
        -- Width: trim to frame width.
        if snappedBtbW > snappedFrameW + 0.01 then
            Pix.Width(widget.BottomTextBar, snappedFrameW)
        end
        -- Height: the full stack must fit inside the frame height.
        local usedH = cpAboveH
        if widget.Health then
            usedH = usedH + widget.Health:GetHeight()
        end
        if widget.Power and ppIsAtt then
            usedH = usedH + widget.Power:GetHeight()
        end
        if usedH + snappedBtbH > snappedFrameH + 0.01 then
            Pix.Height(widget.BottomTextBar, snappedBtbH - (usedH + snappedBtbH - snappedFrameH))
        end
    end

    -- 8) Castbar: re-snap background width + border textures.
    if widget.Castbar then
        local castbarBg = widget.Castbar:GetParent()
        if castbarBg then
            -- Trim castbar bg width to the frame width, only when the user has no
            -- custom width (castbarWidth > 0 = custom). Use the settings resolved
            -- from this function's unit parameter, NOT frame._cuiUnit: boss preview
            -- swaps frame._cuiUnit to "player", which has no castbarWidth, and the
            -- trim would eat the boss castbar's custom width while previewing.
            local cbW = castbarBg:GetWidth()
            local hasCustomW = (prefs.castbarWidth or 0) > 0
            -- (A holder on the Blizzard Style aura block reads back secret: no trim.)
            if not hasCustomW and not issecretvalue(cbW) and cbW > snappedFrameW + 0.01 then
                Pix.Width(castbarBg, snappedFrameW)
            end
            -- Re-snap border textures.
            if Pix.GetBorders(castbarBg) then
                Pix.SetBorderSize(castbarBg, 1)
                widget.Castbar:ClearAllPoints()
                Pix.Point(widget.Castbar, "TOPLEFT", castbarBg, "TOPLEFT", 0, 0)
                Pix.Point(widget.Castbar, "BOTTOMRIGHT", castbarBg, "BOTTOMRIGHT", 0, 0)
            end
        end
    end

    -- 9) Inset the clip container by a quarter of a physical pixel (sub-pixel, invisible),
    -- guaranteeing the GPU clips any StatusBar texture rounding past the frame edge.
    -- A quarter, not a half: an edge exactly on a pixel centre hits the rasteriser's
    -- tie rule and the bar covers one more column/row on one side than the other,
    -- which shows as an uneven border wherever the bar sits over it (Show Behind).
    -- Skip the inset on the portrait side so the health bar stays flush with the
    -- portrait (which anchors to the frame, not _barClip).
    if widget._barClip and widget.Health then
        local es = widget:GetEffectiveScale()
        local clipInset = es > 0 and (Pix.perfect / es) * 0.25 or Pix.mult * 0.25
        local clipL, clipR = clipInset, clipInset
        if showPortrait and isAttached and widget.Portrait and widget.Portrait.backdrop then
            if effectiveSide == "left" then
                clipL = 0
            elseif effectiveSide == "right" then
                clipR = 0
            end
        end
        widget._barClip:ClearAllPoints()
        widget._barClip:SetPoint("TOPLEFT", widget, "TOPLEFT", clipL, -clipInset)
        widget._barClip:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -clipR, clipInset)
        -- Preserve the health bar's logical top while the clip trims its edges.
        -- Cancel the clip's Y inset after snapping; the bar keeps its full height,
        -- so inheriting that inset would move centered text down by the inset.
        local xOff = widget.Health._xOffset or 0
        local rInset = widget.Health._rightInset or 0
        local topOff = widget.Health._topOffset or 0
        widget.Health:ClearAllPoints()
        widget.Health:SetPoint("TOPLEFT", widget._barClip, "TOPLEFT", xOff, Pix.Scale(-topOff) + clipInset)
        widget.Health:SetPoint("RIGHT", widget._barClip, "RIGHT", -rInset, 0)
        Pix.Height(widget.Health, prefs.healthHeight)
    end

    -- Blizzard Style: the stock geometry is re-asserted over everything above
    -- (a reload runs its own sweep after the per-unit re-anchors instead).
    if mod.UF_Blizz() and not mod._ufReloadSweep then
        mod.UF_ApplyBlizzardLayout(widget, unitToken)
    end
    if prefs.portraitSeparator or widget._portraitSeparator then
        mod.UpdatePortraitSeparator(
            widget,
            widget.Portrait and widget.Portrait.backdrop,
            prefs,
            effectiveSide,
            showPortrait and isAttached,
            mod.UF_Blizz(),
            nil,
            unitToken:match("^boss%d$") and mod.UF_BossBorderSettings()
                or (unitToken == "targettarget" and GetMiniDonorSettings(unitToken) or nil)
        )
    end
end

-- All sizing is width/height based; positioning is owned by Unlock Mode.

local function GetFrameDimensions(unitToken, settingsOnly)
    -- Blizzard Style frames are the stock size (settingsOnly: the size the
    -- CludesUI look builds from the unit's settings, whatever the style).
    if not settingsOnly and mod.UF_Blizz() then
        local G = mod.UF_BLIZZ[mod.UF_BlizzKind(unitToken)]
        if G then
            return G.w, G.h
        end
    end
    local prefs = GetSettingsForUnit(unitToken)
    local pStyle = prefs.portraitStyle or saved.profile.portraitStyle or "attached"
    local miniUnit = unitToken == "pet"
        or unitToken == "targettarget"
        or unitToken == "focustarget"
        or (unitToken and unitToken:match("^boss%d$"))
    if miniUnit and pStyle == "detached" then
        pStyle = "attached"
    end
    local showPortrait = pStyle ~= "none" and prefs.showPortrait ~= false
    local isAttached = pStyle == "attached"
    local pSizeAdj = prefs.portraitSize or 0
    local btbPos = prefs.btbPosition or "bottom"
    local btbIsAtt = (btbPos == "top" or btbPos == "bottom")
    local btbExtra = (prefs.bottomTextBar and btbIsAtt) and (prefs.bottomTextBarHeight or 16) or 0
    local powerPos = prefs.powerPosition or "below"
    local powerIsAtt = (powerPos == "below" or powerPos == "above")
    local powerExtra = powerIsAtt and (prefs.powerHeight or 6) or 0

    if not isAttached then
        pSizeAdj = pSizeAdj + 10
    end
    -- Snap returned dimensions to the physical pixel grid so width-matching and
    -- the cog display agree with the rendered frame size.
    local snap = Pix.Snap
    if unitToken == "player" or unitToken == "target" then
        local ptH = prefs.healthHeight + powerExtra
        local adjPH = ptH + pSizeAdj
        if adjPH < 8 then
            adjPH = 8
        end
        local pSide = prefs.portraitSide or (unitToken == "player" and "left" or "right")
        if isAttached and pSide == "top" then
            pSide = (unitToken == "player") and "left" or "right"
        end
        local wid = (showPortrait and isAttached) and (adjPH + prefs.frameWidth) or prefs.frameWidth
        return snap(wid), snap(ptH + btbExtra)
    elseif unitToken == "focus" then
        local pH = powerIsAtt and (prefs.powerHeight or 6) or 0
        local barH = prefs.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then
            adjPH = 8
        end
        local wid = (showPortrait and isAttached) and (adjPH + prefs.frameWidth) or prefs.frameWidth
        return snap(wid), snap(barH + btbExtra)
    elseif unitToken == "pet" or unitToken == "targettarget" or unitToken == "focustarget" then
        -- A WoW Forever pet stacks its attached power bar with the health bar,
        -- and a shown portrait squares that stack off beside the bar
        -- (StyleSimpleFrame), so it is part of the width here as on the other
        -- frames: the unlock setter subtracts the same square, and a size this
        -- reports must come back as itself through it (an override layer
        -- banks it and hands it to the setter on every apply).
        local miniPowerH = (unitToken == "pet" and mod.UF_PetHasPower) and powerExtra or 0
        local barH = prefs.healthHeight + miniPowerH
        local wid = showPortrait and (barH + prefs.frameWidth) or prefs.frameWidth
        return snap(wid), snap(barH)
    elseif unitToken:match("^boss") then
        local pH = powerIsAtt and (prefs.powerHeight or 6) or 0
        local barH = prefs.healthHeight + pH
        local adjPH = barH + pSizeAdj
        if adjPH < 8 then
            adjPH = 8
        end
        local wid = (showPortrait and isAttached) and (adjPH + prefs.frameWidth) or prefs.frameWidth
        return snap(wid), snap(barH)
    end
    return 150, 30
end

-- Fill-texture rotation, DERIVED -- never set on its own, so it cannot go stale against
-- the bar's axis or a texture swap. Two texture families need opposite treatment on a
-- vertical bar: stretch textures (shield.tga, striped3, blizzard, WHITE8X8, every
-- health texture) are one image scaled to the fill rect, authored wide-and-short, so on
-- a tall bar they must be ROTATED or they smear; tiled textures (stripedReversed, the
-- large* stripe sets, striped-maxhp, modern absorb) repeat at native pixel size on both
-- axes and already read correctly at any bar shape, so rotating them fights the tiling
-- and must NOT happen. Tiling is read back off the live fill texture rather than passed
-- in, so this stays correct no matter which style function last touched the bar.
function mod.ApplyFillRotation(barFrame)
    if not (barFrame and barFrame.SetRotatesTexture) then
        return
    end
    local vert = barFrame.GetOrientation and barFrame:GetOrientation() == "VERTICAL"
    local fillTex = barFrame.GetStatusBarTexture and barFrame:GetStatusBarTexture()
    local tiled = fillTex
        and (
            (fillTex.GetHorizTile and fillTex:GetHorizTile())
            or (fillTex.GetVertTile and fillTex:GetVertTile())
        )
    barFrame:SetRotatesTexture((vert and not tiled) and true or false)
end

-- Vertical health fill. SetOrientation drives the fill AXIS; healthReverseFill still
-- flips direction WITHIN that axis (horizontal: left-right/right-left; vertical:
-- bottom-top/top-bottom). On ns so the options preview paints the same way.
function mod.ApplyHealthOrientation(barFrame, prefs)
    if not barFrame then
        return
    end
    local vert = (prefs and prefs.healthVerticalFill) and true or false
    barFrame:SetOrientation(vert and "VERTICAL" or "HORIZONTAL")
    mod.ApplyFillRotation(barFrame)
    return vert
end

local function CreateHealthBar(widget, unitToken, height, xOffset, prefs, rightInset)
    height = height or prefs.healthHeight
    xOffset = xOffset or 0
    rightInset = rightInset or 0

    -- Power bar "above" pushes the health bar down by the power bar height.
    local ppPos = mod.UF_PowerPos(prefs)
    local powerAboveOff = (ppPos == "above") and (prefs.powerHeight or 0) or 0

    local healthBar = CreateFrame("StatusBar", nil, widget)
    healthBar:SetFrameStrata(widget:GetFrameStrata())
    healthBar:SetFrameLevel(widget:GetFrameLevel() + 2)
    -- Two-point horizontal anchoring: width derives from the frame, so it can
    -- never exceed the frame boundary regardless of pixel-snapping rounding.
    Pix.Point(healthBar, "TOPLEFT", widget, "TOPLEFT", xOffset, -powerAboveOff)
    Pix.Point(healthBar, "RIGHT", widget, "RIGHT", -rightInset, 0)
    Pix.Height(healthBar, height)
    healthBar._xOffset = xOffset -- class power repositioning
    healthBar._rightInset = rightInset -- class power repositioning
    healthBar._topOffset = powerAboveOff -- SnapLayout re-anchoring
    healthBar:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    healthBar:GetStatusBarTexture():SetHorizTile(false)

    local bg = healthBar:CreateTexture(nil, "BACKGROUND")
    Pix.Point(bg, "TOPLEFT", healthBar, "TOPLEFT", 0, 0)
    Pix.Point(bg, "BOTTOMRIGHT", healthBar, "BOTTOMRIGHT", 0, 0)
    bg:SetColorTexture(0, 0, 0, 0.5)
    healthBar.bg = bg

    healthBar.colorClass = true
    healthBar.colorReaction = true
    healthBar.colorTapped = true
    healthBar.colorDisconnected = true
    healthBar._cuiUnitKey = UnitToSettingsKey(unitToken)

    ApplyHealthBarTexture(healthBar, UnitToSettingsKey(unitToken))
    ApplyHealthBarAlpha(healthBar, UnitToSettingsKey(unitToken))
    healthBar:SetReverseFill(prefs.healthReverseFill and true or false)
    mod.ApplyHealthOrientation(healthBar, prefs)
    ApplyDarkTheme(healthBar, unitToken)

    -- Smooth bar interpolation (opt-in).
    if prefs.smoothBars then
        healthBar.smoothing = Enum
            and Enum.StatusBarInterpolation
            and Enum.StatusBarInterpolation.ExponentialEaseOut
    end

    return healthBar
end

Inner.SlotWidthMul, Inner.EstimateUFTextWidth, Inner.ApplyClassColor =
    SlotWidthMul, EstimateUFTextWidth, ApplyClassColor
Inner.CreateBottomTextBar, Inner.ApplyFramePosition = CreateBottomTextBar, ApplyFramePosition
Inner.ReparentBarsToClip, Inner.UpdateBordersForScale = ReparentBarsToClip, UpdateBordersForScale
Inner.GetFrameDimensions, Inner.CreateHealthBar = GetFrameDimensions, CreateHealthBar
