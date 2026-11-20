if CUI_CLIENT_BLOCKED then
    return
end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CludesUI_Widgets_PageParts.lua
--  Shared page parts: unlock placeholder, max duration and sound dropdown
--  data, the Global Settings rows and module card, and the manager-page
--  parts. Read at load by the Fonts and Textures options files, so it
--  loads before them.
-------------------------------------------------------------------------------
local CludesUI = _G.CludesUI
-- Page reuse: the frames this file builds go through the options frame pool
-- (CludesUI_FramePool.lua, loaded first in this addon), which hands a kept
-- page its previous build's frames back reset to new; on any other parent it
-- creates as before.
local CreateFrame = CludesUI._Pool.CreateFrame

-------------------------------------------------------------------------------
--  BuildUnlockPlaceholder
--  Reusable overlay that mirrors the unlock mode mover style. Shows accent-colored text (default "Move in
--  Unlock Mode") and opens unlock mode on click.
--  opts = {
--      parent   = frame,          -- parent frame to overlay
--      text     = "...",          -- optional, defaults to "Move in Unlock Mode"
--      level    = number,         -- optional frame level override
--      onClick  = function,       -- optional custom click handler (default: toggle unlock mode)
--  }
--  Returns the placeholder frame.
-------------------------------------------------------------------------------
function CludesUI.BuildUnlockPlaceholder(options)
    local hostFrame = options.parent
    local brandGreen = CludesUI.CLUDES_GREEN
    local ar, ag, ab = brandGreen.r, brandGreen.g, brandGreen.b

    local f = CreateFrame("Button", nil, hostFrame)
    f:SetAllPoints(hostFrame)
    if options.level then
        f:SetFrameLevel(options.level)
    else
        f:SetFrameLevel(hostFrame:GetFrameLevel() + 10)
    end
    f:EnableMouse(true)
    f:RegisterForClicks("LeftButtonUp")

    -- Dark background matching unlock mode movers
    local backdrop = f:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(0.088, 0.098, 0.111, 0.95)
    f._bg = backdrop

    -- Accent border at 60% alpha
    f._brd = CludesUI.MakeBorder(f, ar, ag, ab, 0.6)

    -- White centered label matching unlock mode mover style
    local fontFile = (CludesUI.GetFontPath("extras"))
        or "Interface\\AddOns\\CludesUI\\media\\fonts\\Expressway.TTF"
    local labelText = f:CreateFontString(nil, "OVERLAY")
    labelText:SetFont(fontFile, 10, "OUTLINE, SLUG")
    labelText:SetText(CludesUI.L(options.text or "Move in Layout Mode"))
    labelText:SetTextColor(1, 1, 1, 0.9)
    labelText:SetPoint("CENTER")
    f._label = labelText

    -- Hover: accent text + brighten border
    local brd = f._brd
    f:SetScript("OnEnter", function()
        labelText:SetTextColor(ar, ag, ab, 1)
        if brd then
            brd:SetColor(ar, ag, ab, 0.85)
        end
    end)
    f:SetScript("OnLeave", function()
        labelText:SetTextColor(1, 1, 1, 0.9)
        if brd then
            brd:SetColor(ar, ag, ab, 0.6)
        end
    end)

    -- Click: open unlock mode (or custom handler)
    f:SetScript("OnClick", options.onClick or function()
        if CludesUI.ToggleUnlockMode then
            CludesUI:ToggleUnlockMode()
        end
    end)

    return f
end

-- Debuff "Max Duration" dropdown spec for a DualRow slot: Unlimited (nil, the
-- consumer adds nothing to its candidate filters) or Custom, which opens the
-- standard input popup for a whole number of seconds and then reads back as
-- "Custom (Ns)". get/set move the stored seconds (nil = unlimited); apply
-- re-drives the display. Shared by the Raid Frames Debuff Manager (base grid
-- and grid tiles) and Player Aura Bars debuff bars.
function CludesUI.MaxDurationDropdown(get, set, apply)
    local L = CludesUI.L
    local current = get()
    local values = {
        unlimited = L("Unlimited"),
        custom = current and (L("Custom") .. " (" .. tostring(current) .. "s)") or (L("Custom") .. "..."),
    }
    return {
        type = "dropdown",
        text = "Max Duration",
        tooltip = "Only show debuffs whose full duration is at most this many seconds. Combines with the filters; Unlimited applies no cap.",
        values = values,
        order = { "unlimited", "custom" },
        getValue = function()
            return get() and "custom" or "unlimited"
        end,
        setValue = function(val)
            if val == "unlimited" then
                if get() ~= nil then
                    set(nil)
                    if apply then
                        apply()
                    end
                end
                CludesUI:RefreshPage(true)
                return
            end
            local nowTime = get()
            CludesUI:ShowInputPopup({
                title = L("Max Duration"),
                message = L("Enter the maximum debuff duration in seconds:"),
                placeholder = nowTime and tostring(nowTime) or "30",
                confirmText = L("Apply"),
                cancelText = L("Cancel"),
                onConfirm = function(textValue)
                    local num = tonumber(textValue or "")
                    if num and num > 0 then
                        num = math.floor(num)
                        if num ~= get() then
                            set(num)
                            if apply then
                                apply()
                            end
                        end
                    end
                    CludesUI:RefreshPage(true)
                end,
                onCancel = function()
                    CludesUI:RefreshPage(true)
                end,
            })
        end,
    }
end

-- Sound dropdown data for a DualRow slot or a cog row: a fresh values table
-- (a click-to-preview speaker icon on every playable row) and the order list.
-- paths / names / order are a catalogue from BuildAlertSoundTables(); left out,
-- they are the Quality of Life alert-sound catalogue (just "None" while it is
-- absent). A path is a sound file or a SoundKit id.
-- Sound preview icon for every sound picker and play button. WoW Forever has no
-- common-icon-sound atlases; its dropdown speaker stands in for both states.
CludesUI.SOUND_ICON_ATLAS = C_Texture.GetAtlasInfo("common-icon-sound") and "common-icon-sound"
    or "common-dropdown-icon-sound-on"
CludesUI.SOUND_ICON_PRESSED_ATLAS = C_Texture.GetAtlasInfo("common-icon-sound-pressed")
        and "common-icon-sound-pressed"
    or CludesUI.SOUND_ICON_ATLAS

function CludesUI.BuildSoundDropdownValues(paths, nameList, sequence)
    paths = paths or CludesUI._groupDeathSoundPaths or {}
    nameList = nameList or CludesUI._groupDeathSoundNames or { none = "None" }
    sequence = sequence or CludesUI._groupDeathSoundOrder or { "none" }
    local values = {}
    for keyName, val in pairs(nameList) do
        values[keyName] = val
    end
    values._menuOpts = {
        itemHeight = 26,
        maxTextWidthPct = 0.8,
        searchable = true,
        iconAtlas = function(key)
            if key == "none" or not paths[key] then
                return nil
            end
            return CludesUI.SOUND_ICON_ATLAS
        end,
        iconPressedAtlas = function(key)
            if key == "none" or not paths[key] then
                return nil
            end
            return CludesUI.SOUND_ICON_PRESSED_ATLAS
        end,
        iconOnClick = function(key)
            CludesUI.PlaySoundPath(paths[key])
        end,
        iconTooltip = function()
            return "Preview Sound"
        end,
    }
    return values, sequence
end

-------------------------------------------------------------------------------
--  Global Settings > Fonts / Textures: shared row helpers and module card
-------------------------------------------------------------------------------

-- Fresh table per call: DualRow configs must never be shared across rows.
function CludesUI.BlankRowCfg()
    return { type = "label", text = "" }
end

function CludesUI.ModuleNS(folder)
    return CludesUI._ModuleNS and CludesUI._ModuleNS[folder]
end

-- Custom link row: label on the left, an Open Settings button on the right,
-- jumping to the module page that owns a selection-bound settings family.
-- opts.warn: the label in the warning red, for a setting there that overrides
-- this page. Returns the next y and the row; row:Relink(label, module, page,
-- section, highlight) aims the same row at another setting.
function CludesUI.BuildLinkRow(hostFrame, cursorY, labelText, module, page, section, highlight, options)
    local Pix = CludesUI.PanelPP
    local ROW_H = 40
    local row = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(row, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, ROW_H)
    Pix.Point(row, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, cursorY)
    row._skipRowDivider = true
    CludesUI.RowBg(row, hostFrame)

    local labelFS = CludesUI.MakeFont(row, 13, nil, 1, 1, 1)
    labelFS:SetAlpha(0.9)
    labelFS:SetPoint("LEFT", row, "LEFT", 20, 0)
    labelFS:SetText(CludesUI.L(labelText))
    if options and options.warn then
        labelFS:SetTextColor(0.9, 0.3, 0.3)
    end

    local button = CreateFrame("Button", nil, row)
    Pix.Size(button, 122, 26)
    button:SetPoint("RIGHT", row, "RIGHT", -20, 0)
    button:SetFrameLevel(row:GetFrameLevel() + 2)
    CludesUI.MakeStyledButton(button, "Open Settings", 11, CludesUI.WB_COLOURS, function()
        CludesUI:NavigateToElementSettings(module, page, section, nil, highlight)
    end)
    function row:Relink(l, m, p, s, height)
        labelFS:SetText(CludesUI.L(l))
        module, page, section, highlight = m, p, s, height
    end

    return cursorY - ROW_H, row
end

-- A row of action cards across the page (icon, title, a short description;
-- the whole card is the click). cards[i] = { icon, title, desc, onClick,
-- accent, hero, iconSize, sizeAlso, pulse } -- accent { r, g, b } tints the icon
-- (and a box's top edge), the theme accent when nil; iconSize (px) draws art
-- that fills more of its canvas smaller, centred in the same slot (the text
-- never moves). By default the cards are equal boxes side by side across
-- opts.width (a fraction of the content width, centred). opts.inline lays
-- them out in ONE line instead: plain text buttons with a thin divider
-- between items, each as wide as its text (sizeAlso { title, desc } also fits
-- the other text a card can switch to), the texts shrinking together when the
-- line would not fit opts.width, centred; a hero card there is a button in
-- the equal cards' boxed look. opts.footer (px, inline) leaves that much free
-- under the line for the caller (a link). Returns the new y and the card
-- buttons (in cards order); card:SetCardContent(icon, title, desc) swaps all
-- three in place. An equal card built with pulse = true also takes
-- card:SetPulse(on): a breathing accent outline for an action that wants
-- attention now, animated only while the card shows.
local function BuildInlineRow(hostFrame, cursorY, cards, availW, fullW, footer)
    local Pix = CludesUI.PanelPP
    local L = CludesUI.L
    local ROW_H, ICON, DIV_GAP, DIV_H = 60, 26, 24, 40
    local TITLE_SZ, DESC_SZ, DESC_GAP = 13, 11, 4
    -- Plain items, and the boxed hero in the equal cards' values (left pad,
    -- icon-to-text gap, right pad, alphas, outline).
    local GAP, ICON_A, TITLE_A, DESC_A = 14, 0.75, 0.9, 0.45
    local BOX_L, BOX_GAP, BOX_R, BOX_ICON_A, BOX_DESC_A, BOX_BRD_A = 24, 20, 14, 0.6, 0.35, 0.12
    local num = #cards
    local blockH = ROW_H + (footer or 0)
    local rowFrame = CreateFrame("Frame", nil, hostFrame)

    -- Build each item and measure its text: the wider of its two lines, over
    -- every text it can show.
    local parts, built, sumText, fixed = {}, {}, 0, (num - 1) * (DIV_GAP * 2 + 1)
    for idx = 1, num do
        local specInfo = cards[idx]
        local boxed = specInfo.hero and true or false
        local p = {
            boxed = boxed,
            padL = boxed and BOX_L or 0,
            gap = boxed and BOX_GAP or GAP,
            padR = boxed and BOX_R or 0,
            iconA = boxed and BOX_ICON_A or ICON_A,
            descA = boxed and BOX_DESC_A or DESC_A,
        }
        local cardFrame = CreateFrame("Button", nil, rowFrame)
        cardFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 2)
        local icon = cardFrame:CreateTexture(nil, "ARTWORK")
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end
        icon:SetAlpha(p.iconA)
        local titleFs = CludesUI.MakeFont(cardFrame, TITLE_SZ, nil, 1, 1, 1, TITLE_A)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        local descFs = CludesUI.MakeFont(cardFrame, DESC_SZ, nil, 1, 1, 1, p.descA)
        descFs:SetJustifyH("LEFT")
        descFs:SetWordWrap(true)
        descFs:SetMaxLines(2)
        function cardFrame:SetCardContent(iconPath, cardTitle, cardDesc)
            icon:SetTexture(iconPath)
            titleFs:SetText(L(cardTitle))
            descFs:SetText(L(cardDesc))
        end
        local wid = 0
        local function Measure(t, d)
            titleFs:SetText(L(t))
            descFs:SetText(L(d))
            wid = math.max(wid, math.ceil(titleFs:GetStringWidth()), math.ceil(descFs:GetStringWidth()))
        end
        if specInfo.sizeAlso then
            Measure(specInfo.sizeAlso[1], specInfo.sizeAlso[2])
        end
        Measure(specInfo.title, specInfo.desc)
        cardFrame:SetCardContent(specInfo.icon, specInfo.title, specInfo.desc)
        p.card, p.icon, p.titleFs, p.descFs, p.textW = cardFrame, icon, titleFs, descFs, wid
        parts[idx] = p
        sumText = sumText + wid
        fixed = fixed + p.padL + ICON + p.gap + p.padR
        built[idx] = cardFrame
    end

    local scale = 1
    if sumText > 0 and fixed + sumText > availW then
        scale = math.max(0, availW - fixed) / sumText
    end
    local totalW = fixed
    for idx = 1, num do
        parts[idx].textW = math.floor(parts[idx].textW * scale)
        totalW = totalW + parts[idx].textW
    end
    Pix.Size(rowFrame, totalW, blockH)
    Pix.Point(
        rowFrame,
        "TOPLEFT",
        hostFrame,
        "TOPLEFT",
        CludesUI.CONTENT_PAD + math.floor((fullW - totalW) / 2),
        cursorY
    )

    local posX = 0
    for idx = 1, num do
        local specInfo, p = cards[idx], parts[idx]
        local cardFrame, icon, titleFs, descFs, boxed = p.card, p.icon, p.titleFs, p.descFs, p.boxed
        if idx > 1 then
            local div = rowFrame:CreateTexture(nil, "ARTWORK")
            div:SetColorTexture(1, 1, 1, 0.10)
            div:SetWidth(1)
            div:SetHeight(DIV_H)
            Pix.Point(div, "TOPLEFT", rowFrame, "TOPLEFT", posX + DIV_GAP, -math.floor((ROW_H - DIV_H) / 2))
            posX = posX + DIV_GAP * 2 + 1
        end
        local wid = p.padL + ICON + p.gap + p.textW + p.padR
        Pix.Size(cardFrame, wid, ROW_H)
        Pix.Point(cardFrame, "TOPLEFT", rowFrame, "TOPLEFT", posX, 0)
        posX = posX + wid

        local iconSz = specInfo.iconSize or ICON
        icon:SetSize(iconSz, iconSz)
        Pix.Point(icon, "LEFT", cardFrame, "LEFT", p.padL + math.floor((ICON - iconSz) / 2), 0)
        Pix.Point(titleFs, "TOPLEFT", cardFrame, "LEFT", p.padL + ICON + p.gap, ICON / 2 + 2)
        titleFs:SetWidth(p.textW)
        Pix.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -DESC_GAP)
        descFs:SetWidth(p.textW)

        -- The equal cards' box: dark fill, thin outline, an accent top edge.
        local backdrop, brd, accentLine
        if boxed then
            brd = CludesUI.MakeRoundedCard(cardFrame, BOX_BRD_A, 0.50, 2)
            backdrop, accentLine = brd.bg, brd.accent
        end
        -- The accent is read at paint time, so an accent change repaints it.
        local function Paint(hover)
            local ac = specInfo.accent or CludesUI.CLUDES_GREEN
            icon:SetVertexColor(ac.r, ac.g, ac.b)
            if boxed then
                accentLine:SetColorTexture(ac.r, ac.g, ac.b, 0.6)
                if hover then
                    backdrop:SetColorTexture(0.100, 0.110, 0.124, 0.50)
                else
                    backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.50)
                end
                brd:SetColor(1, 1, 1, hover and (BOX_BRD_A + 0.10) or BOX_BRD_A)
            end
        end
        Paint(false)
        if not specInfo.accent then
            CludesUI.RegisterWidgetRefresh(function()
                Paint(cardFrame:IsMouseOver())
            end)
        end
        -- The labels' resting alpha is their text colour's (MakeFont), so the
        -- hover moves that alpha, never the region's: a leave puts back exactly
        -- the look a new card has.
        cardFrame:SetScript("OnEnter", function()
            Paint(true)
            icon:SetAlpha(boxed and (BOX_ICON_A + 0.25) or 1)
            titleFs:SetTextColor(1, 1, 1, 1)
            if not boxed then
                descFs:SetTextColor(1, 1, 1, DESC_A + 0.15)
            end
        end)
        cardFrame:SetScript("OnLeave", function()
            Paint(false)
            icon:SetAlpha(p.iconA)
            titleFs:SetTextColor(1, 1, 1, TITLE_A)
            descFs:SetTextColor(1, 1, 1, p.descA)
        end)
        if specInfo.onClick then
            cardFrame:SetScript("OnClick", specInfo.onClick)
        end
    end
    return cursorY - blockH, built
end

function CludesUI.BuildActionCardRow(hostFrame, cursorY, cards, options)
    local Pix = CludesUI.PanelPP
    local L = CludesUI.L
    local num = #cards
    local fullW = hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2
    local totalW = (options and options.width) and math.floor(fullW * options.width) or fullW
    if options and options.inline then
        return BuildInlineRow(hostFrame, cursorY, cards, totalW, fullW, options.footer)
    end

    local CARD_H, CARD_GAP = 66, 14
    local M = {
        icon = 26,
        iconX = 24,
        title = 13,
        titleGap = 20,
        titleY = 2,
        desc = 11,
        descGap = 4,
        descA = 0.35,
        pad = 14,
    }
    local leftX = CludesUI.CONTENT_PAD + math.floor((fullW - totalW) / 2)
    local cardW = math.floor((totalW - CARD_GAP * (num - 1)) / num)

    local rowFrame = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(rowFrame, totalW, CARD_H)
    Pix.Point(rowFrame, "TOPLEFT", hostFrame, "TOPLEFT", leftX, cursorY)

    local built = {}
    for idx = 1, num do
        local specInfo = cards[idx]
        local ac = specInfo.accent or CludesUI.CLUDES_GREEN
        local cardFrame = CreateFrame("Button", nil, rowFrame)
        Pix.Size(cardFrame, cardW, CARD_H)
        Pix.Point(cardFrame, "TOPLEFT", rowFrame, "TOPLEFT", (idx - 1) * (cardW + CARD_GAP), 0)
        cardFrame:SetFrameLevel(rowFrame:GetFrameLevel() + 2)

        local BRD_A = 0.12
        -- Card look with the accent top edge (CludesUI_RoundedCorners.lua).
        local brd = CludesUI.MakeRoundedCard(cardFrame, BRD_A, 0.50, 2)
        local backdrop = brd.bg
        brd.accent:SetColorTexture(ac.r, ac.g, ac.b, 0.6)

        local ICON_A, TITLE_A = 0.6, 0.9
        local icon = cardFrame:CreateTexture(nil, "ARTWORK")
        icon:SetVertexColor(ac.r, ac.g, ac.b)
        icon:SetAlpha(ICON_A)
        if icon.SetSnapToPixelGrid then
            icon:SetSnapToPixelGrid(false)
            icon:SetTexelSnappingBias(0)
        end

        -- Icon on the left, title and description to its right.
        local iconSz = specInfo.iconSize or M.icon
        icon:SetSize(iconSz, iconSz)
        Pix.Point(icon, "LEFT", cardFrame, "LEFT", M.iconX + math.floor((M.icon - iconSz) / 2), 0)
        local titleFs = CludesUI.MakeFont(cardFrame, M.title, nil, 1, 1, 1, TITLE_A)
        -- Off the icon slot, not the icon, so every card's text lines up.
        Pix.Point(titleFs, "TOPLEFT", cardFrame, "LEFT", M.iconX + M.icon + M.titleGap, M.icon / 2 + M.titleY)
        Pix.Point(titleFs, "RIGHT", cardFrame, "RIGHT", -M.pad, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetWordWrap(false)
        local descFs = CludesUI.MakeFont(cardFrame, M.desc, nil, 1, 1, 1, M.descA)
        Pix.Point(descFs, "TOPLEFT", titleFs, "BOTTOMLEFT", 0, -M.descGap)
        Pix.Point(descFs, "RIGHT", cardFrame, "RIGHT", -M.pad, 0)
        descFs:SetJustifyH("LEFT")
        -- Two lines at most: a narrow card is short of room in longer languages.
        descFs:SetWordWrap(true)
        descFs:SetMaxLines(2)

        function cardFrame:SetCardContent(iconPath, cardTitle, cardDesc)
            icon:SetTexture(iconPath)
            titleFs:SetText(L(cardTitle))
            descFs:SetText(L(cardDesc))
        end
        cardFrame:SetCardContent(specInfo.icon, specInfo.title, specInfo.desc)

        -- The pulse outline is built with the card whenever it is asked for,
        -- so a kept page hands it back in order; it stays hidden until
        -- SetPulse turns it on, and its fade plays only while it shows.
        local pulse
        if specInfo.pulse then
            pulse = CreateFrame("Frame", nil, cardFrame)
            pulse:SetAllPoints(cardFrame)
            pulse:SetFrameLevel(cardFrame:GetFrameLevel() + 3)
            pulse:EnableMouse(false)
            pulse:Hide()
            pulse._ring = CludesUI.MakeRoundedBorder(pulse, ac.r, ac.g, ac.b, 1, nil, nil, nil, 2)
            local breathe = pulse:CreateAnimationGroup()
            breathe:SetLooping("BOUNCE")
            local fade = breathe:CreateAnimation("Alpha")
            fade:SetFromAlpha(1)
            fade:SetToAlpha(0.2)
            fade:SetDuration(0.9)
            fade:SetSmoothing("IN_OUT")
            pulse:SetScript("OnShow", function()
                breathe:Play()
            end)
            pulse:SetScript("OnHide", function()
                breathe:Stop()
            end)
        end
        function cardFrame:SetPulse(on)
            if not pulse then
                return
            end
            if on then
                local live = specInfo.accent or CludesUI.CLUDES_GREEN
                pulse._ring:SetColor(live.r, live.g, live.b, 1)
            end
            pulse:SetShown(on and true or false)
        end

        -- The title's resting alpha is its text colour's (as BuildInlineRow's).
        cardFrame:SetScript("OnEnter", function()
            backdrop:SetColorTexture(0.100, 0.110, 0.124, 0.50)
            brd:SetColor(1, 1, 1, BRD_A + 0.10)
            titleFs:SetTextColor(1, 1, 1, 1)
            icon:SetAlpha(ICON_A + 0.25)
        end)
        cardFrame:SetScript("OnLeave", function()
            backdrop:SetColorTexture(0.062, 0.070, 0.082, 0.50)
            brd:SetColor(1, 1, 1, BRD_A)
            titleFs:SetTextColor(1, 1, 1, TITLE_A)
            icon:SetAlpha(ICON_A)
        end)
        if specInfo.onClick then
            cardFrame:SetScript("OnClick", specInfo.onClick)
        end
        built[idx] = cardFrame
    end
    return cursorY - CARD_H, built
end

-- Note row: a dim aside (inside a card when its module is disabled, under a
-- row). opts.banner: the section banner look (row background, brighter text,
-- up to two lines), for a note the player must read before the rows below.
function CludesUI.BuildNoteRow(hostFrame, cursorY, textValue, options)
    local banner = options and options.banner
    local ROW_H = banner and 40 or 34
    -- The search prebuild only indexes rows: same y advance, no frames.
    if CludesUI._prebuilding then
        return cursorY - ROW_H
    end
    local Pix = CludesUI.PanelPP
    local row = CreateFrame("Frame", nil, hostFrame)
    Pix.Size(row, hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2, ROW_H)
    Pix.Point(row, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, cursorY)
    row._skipRowDivider = true
    if banner then
        CludesUI.RowBg(row, hostFrame)
    end
    local labelFS = CludesUI.MakeFont(row, 12, nil, 1, 1, 1)
    labelFS:SetAlpha(banner and 0.6 or 0.45)
    labelFS:SetPoint("LEFT", row, "LEFT", 20, 0)
    if banner then
        labelFS:SetPoint("RIGHT", row, "RIGHT", -20, 0)
        labelFS:SetJustifyH("LEFT")
        labelFS:SetWordWrap(true)
        labelFS:SetMaxLines(2)
    end
    labelFS:SetText(CludesUI.L(textValue))
    return cursorY - ROW_H
end

local MC_ARROW_DOWN = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-down3.png"
local MC_ARROW_UP = "Interface\\AddOns\\CludesUI\\media\\icons\\cui-arrow-up3.png"
local MC_HEADER_H = 54
local MC_CARD_GAP = 14

-- One expandable module card (adapted from the Window Skins card). opts:
-- enabled, expanded (session table keyed by tile.key), descW,
-- glyph(hdr, enabled) builds the left glyph, headerDD(hdr) -> dd or nil,
-- searchDesc: what search indexes (and the header's section name carries) in
-- place of tile.desc, for a card whose description is live (a count);
-- noSearch: the header is no search entry (a card that holds no settings).
-- A disabled module's card is inert: dimmed header, tag and tooltip only.
-- Sets tile._hdr and tile._descFS (the header and its description line)
-- before tile.buildContent runs, for content that updates the header.
function CludesUI.BuildModuleCard(hostFrame, cursorY, W, tile, options)
    local Pix = CludesUI.PanelPP
    local ACC = CludesUI.CLUDES_GREEN
    local L = CludesUI.L
    local enabled = options.enabled
    local expanded = enabled and options.expanded[tile.key]
    local cardTop = cursorY
    local brd

    -- Explicit size + single TOPLEFT anchor (the widget contract; see the
    -- Window Skins card for why a second point would zero the width).
    local cardW = hostFrame:GetWidth() - CludesUI.CONTENT_PAD * 2
    local heading = CreateFrame("Button", nil, hostFrame)
    Pix.Size(heading, cardW, MC_HEADER_H)
    Pix.Point(heading, "TOPLEFT", hostFrame, "TOPLEFT", CludesUI.CONTENT_PAD, cursorY)
    heading:SetFrameLevel(hostFrame:GetFrameLevel() + 3)

    -- The header is its own pseudo-section, so searching the module name
    -- lands on the card; each page's deep-link pre-hook expands cards first.
    local sDesc = options.searchDesc
    if sDesc == nil then
        sDesc = tile.desc or ""
    end
    local searchName = tile.display .. " " .. sDesc
    if not options.noSearch then
        heading._isSectionHeader = true
        heading._sectionName = searchName
        local searchNameLoc = L(tile.display) .. " " .. L(sDesc)
        if searchNameLoc ~= searchName then
            heading._sectionNameLoc = searchNameLoc
        end
    end
    if CludesUI._RegisterSearchEntry and not options.noSearch then
        local titleLoc = L(tile.display)
        local descSearch = sDesc
        local descLoc = L(sDesc)
        if descLoc ~= descSearch then
            descSearch = descSearch .. " " .. descLoc
        end
        CludesUI._RegisterSearchEntry(
            tile.display,
            titleLoc ~= tile.display and titleLoc or nil,
            descSearch,
            CludesUI._buildingModule,
            CludesUI._buildingPage,
            searchName,
            nil,
            nil,
            true
        )
    end

    -- The header hover fill sits on the card (built below), inside its corners.
    local hbg

    options.glyph(heading, enabled)

    local title = CludesUI.MakeFont(heading, 14, nil, 1, 1, 1, 0.9)
    Pix.Point(title, "TOPLEFT", heading, "TOPLEFT", 50, -12)
    title:SetText(L(tile.display))

    local desc = CludesUI.MakeFont(heading, 11, nil, 1, 1, 1, 0.42)
    Pix.Point(desc, "TOPLEFT", title, "BOTTOMLEFT", 0, -4)
    desc:SetWidth(options.descW)
    desc:SetJustifyH("LEFT")
    desc:SetWordWrap(false)
    desc:SetText(L(tile.desc or ""))
    tile._hdr, tile._descFS = heading, desc

    if not enabled then
        title:SetAlpha(0.4)
        desc:SetAlpha(0.22)
    end

    local chev
    if enabled then
        chev = heading:CreateTexture(nil, "OVERLAY")
        Pix.Size(chev, 16, 16)
        Pix.Point(chev, "RIGHT", heading, "RIGHT", -16, 0)
        chev:SetTexture(expanded and MC_ARROW_UP or MC_ARROW_DOWN)
        chev:SetAlpha(0.45)
        if expanded then
            chev:SetVertexColor(ACC.r, ACC.g, ACC.b)
        end
    end

    local dropdown = enabled and options.headerDD and options.headerDD(heading)

    local strip
    -- The title's resting alpha is its text colour's (MakeFont), so the hover
    -- moves that alpha: a leave puts back exactly the look a new card has.
    local function ApplyHeaderHover()
        hbg:SetColorTexture(1, 1, 1, 0.05)
        title:SetTextColor(1, 1, 1, 1)
        if chev then
            chev:SetAlpha(0.85)
        end
        if brd then
            brd:SetColor(1, 1, 1, 0.22)
        end
    end
    local function ClearHeaderHover()
        if heading:IsMouseOver() then
            return
        end
        hbg:SetColorTexture(0, 0, 0, 0)
        title:SetTextColor(1, 1, 1, 0.9)
        if chev then
            chev:SetAlpha(0.45)
        end
        if brd then
            brd:SetColor(1, 1, 1, expanded and 0.16 or 0.12)
        end
    end
    if enabled then
        heading:SetScript("OnEnter", ApplyHeaderHover)
        heading:SetScript("OnLeave", ClearHeaderHover)
        if dropdown then
            dropdown:HookScript("OnEnter", ApplyHeaderHover)
            dropdown:HookScript("OnLeave", ClearHeaderHover)
        end
        heading:SetScript("OnClick", function()
            options.expanded[tile.key] = not options.expanded[tile.key]
            CludesUI:RefreshPage(true)
        end)
    else
        local tag = CludesUI.MakeFont(heading, 11, nil, 1, 1, 1)
        tag:SetAlpha(0.3)
        Pix.Point(tag, "RIGHT", heading, "RIGHT", -16, 0)
        tag:SetText(L("Module Disabled"))
        heading:SetScript("OnEnter", function(self)
            CludesUI.ShowWidgetTooltip(
                self,
                CludesUI.Lf("Enable %1$s to edit these settings.", L(tile.display))
            )
        end)
        heading:SetScript("OnLeave", function()
            CludesUI.HideWidgetTooltip()
        end)
    end

    cursorY = cursorY - MC_HEADER_H

    if expanded then
        local div = heading:CreateTexture(nil, "ARTWORK")
        div:SetColorTexture(1, 1, 1, 0.07)
        div:SetHeight(1)
        Pix.Point(div, "BOTTOMLEFT", heading, "BOTTOMLEFT", 1, 0)
        Pix.Point(div, "BOTTOMRIGHT", heading, "BOTTOMRIGHT", -1, 0)
        Pix.DisablePixelSnap(div)

        cursorY = cursorY - 8
        cursorY = tile.buildContent(hostFrame, cursorY, W, tile)
        cursorY = cursorY - 8
    end

    -- Card background + border spanning header and expanded content (header
    -- child so inline search re-flows it with the header; see WS card notes).
    local backdrop = CreateFrame("Frame", nil, heading)
    backdrop:SetFrameLevel(hostFrame:GetFrameLevel())
    Pix.Size(backdrop, cardW, cardTop - cursorY)
    Pix.Point(backdrop, "TOPLEFT", heading, "TOPLEFT", 0, 0)
    brd = CludesUI.MakeRoundedCard(backdrop, expanded and 0.16 or 0.12)
    hbg = backdrop:CreateTexture(nil, "BACKGROUND", nil, 1)
    hbg:SetAllPoints(heading)
    hbg:SetColorTexture(0, 0, 0, 0)
    brd:Clip(hbg)

    strip = backdrop:CreateTexture(nil, "ARTWORK")
    brd:Clip(strip)
    strip:SetWidth(2)
    if enabled then
        strip:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.7)
    else
        strip:SetColorTexture(1, 1, 1, 0.10)
    end
    Pix.Point(strip, "TOPLEFT", heading, "TOPLEFT", 1, -1)
    Pix.Point(strip, "BOTTOMLEFT", heading, "BOTTOMLEFT", 1, 1)
    if strip.SetSnapToPixelGrid then
        strip:SetSnapToPixelGrid(false)
        strip:SetTexelSnappingBias(0)
    end
    -- The accent parts follow a live accent change (it refreshes the shown page).
    if enabled then
        CludesUI.RegisterWidgetRefresh(function()
            strip:SetColorTexture(ACC.r, ACC.g, ACC.b, 0.7)
            if chev and expanded then
                chev:SetVertexColor(ACC.r, ACC.g, ACC.b)
            end
        end)
    end

    return cursorY - MC_CARD_GAP
end

-------------------------------------------------------------------------------
--  Manager-page parts (Buff Manager, Debuff Manager, Player Aura Bars)
-------------------------------------------------------------------------------
-- Sidebar tile. opts: width, fontPath, title, subtitle | subtitleFn, icon | iconFn
-- (the Fn forms re-read on every page widget refresh) | iconApply(tex) (paints
-- the icon itself, no crop), statusDot ({ r, g, b }: 8px dot, top right, left of
-- the toggle pill when shown), posText, selected,
-- enabled, showToggle, dimmed, inheritedTooltip,
-- onSelect(), onToggle(newState), onDelete(), onEdit(), onContext(tile),
-- height (66), textRight (-52), titleUnclamped, editSize (16), editTooltip,
-- editSnap (keep pixel snapping on the pencil). Returns height, tile.
function CludesUI.BuildManagerTile(parentFrame, cursorY, options)
    local fontFile = options.fontPath
    local Pix = CludesUI.PanelPP
    local TILE_H = options.height or 66
    local IR, IG, IB = 0.55, 0.72, 1
    local tile = CreateFrame("Button", nil, parentFrame)
    tile:SetSize(options.width, TILE_H)
    tile:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", 0, cursorY)
    tile:SetFrameLevel(parentFrame:GetFrameLevel() + 1)

    local backdrop = tile:CreateTexture(nil, "BACKGROUND")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(1, 1, 1, options.selected and 0.06 or 0)

    if options.selected then
        local accent = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        accent:SetSize(2, TILE_H)
        accent:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        if options.inheritedTooltip then
            accent:SetColorTexture(IR, IG, IB, 1)
        else
            local ac = CludesUI.CLUDES_GREEN
            accent:SetColorTexture(ac.r, ac.g, ac.b, 1)
        end
    elseif options.inheritedTooltip then
        local edge = tile:CreateTexture(nil, "ARTWORK", nil, 2)
        edge:SetSize(2, TILE_H)
        edge:SetPoint("TOPLEFT", tile, "TOPLEFT", 0, 0)
        edge:SetColorTexture(IR, IG, IB, 0.45)
    end

    local textX = 12
    local titleY = -10
    -- A status dot beside the toggle pill pushes the text further in.
    local textRight = options.textRight or ((options.showToggle and options.statusDot) and -60 or -52)

    if options.icon or options.iconFn or options.iconApply then
        local ICON_SZ = 36
        local iconFrame = CreateFrame("Frame", nil, tile)
        iconFrame:SetSize(ICON_SZ, ICON_SZ)
        iconFrame:SetPoint("TOPLEFT", tile, "TOPLEFT", 8, -8)
        iconFrame:SetFrameLevel(tile:GetFrameLevel() + 1)
        local iconTex = iconFrame:CreateTexture(nil, "ARTWORK")
        iconTex:SetAllPoints()
        if options.iconApply then
            options.iconApply(iconTex)
        else
            iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            iconTex:SetTexture(options.iconFn and options.iconFn() or options.icon)
        end
        if options.iconFn then
            CludesUI.RegisterWidgetRefresh(function()
                iconTex:SetTexture(options.iconFn())
            end)
        end
        local iconBdr = CreateFrame("Frame", nil, iconFrame)
        iconBdr:SetAllPoints()
        iconBdr:SetFrameLevel(iconFrame:GetFrameLevel() + 1)
        Pix.CreateBorder(iconBdr, 0, 0, 0, 0.6, 1)
        textX = 8 + ICON_SZ + 8
        titleY = -8
    end

    local title = tile:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontFile, 13, "")
    title:SetPoint("TOPLEFT", tile, "TOPLEFT", textX, titleY)
    if not options.posText and not options.titleUnclamped then
        title:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
    end
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)
    title:SetText(options.title or "")
    if options.inheritedTooltip then
        title:SetTextColor(IR, IG, IB)
    else
        title:SetTextColor(1, 1, 1)
    end

    if options.posText then
        local posFS = tile:CreateFontString(nil, "OVERLAY")
        posFS:SetPoint("LEFT", title, "RIGHT", 4, 0)
        posFS:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        posFS:SetFont(fontFile, 11, "")
        posFS:SetJustifyH("LEFT")
        posFS:SetWordWrap(false)
        posFS:SetText(options.posText)
        posFS:SetTextColor(0.75, 0.75, 0.75, 0.65)
    end

    if options.subtitle or options.subtitleFn then
        local subMenu = tile:CreateFontString(nil, "OVERLAY")
        subMenu:SetFont(fontFile, 11, "")
        subMenu:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
        subMenu:SetPoint("RIGHT", tile, "RIGHT", textRight, 0)
        subMenu:SetJustifyH("LEFT")
        subMenu:SetWordWrap(false)
        subMenu:SetText(options.subtitleFn and options.subtitleFn() or options.subtitle)
        if options.inheritedTooltip then
            subMenu:SetTextColor(IR, IG, IB, 0.55)
        else
            subMenu:SetTextColor(0.4, 0.4, 0.4)
        end
        -- Re-read on every non-force RefreshPage (a full rebuild would close
        -- an open checkbox dropdown in the detail pane).
        if options.subtitleFn then
            CludesUI.RegisterWidgetRefresh(function()
                subMenu:SetText(options.subtitleFn())
            end)
        end
    end

    tile:SetScript("OnEnter", function()
        if not options.selected then
            backdrop:SetColorTexture(1, 1, 1, 0.04)
        end
        if options.inheritedTooltip then
            CludesUI.ShowWidgetTooltip(tile, options.inheritedTooltip)
        end
    end)
    tile:SetScript("OnLeave", function()
        backdrop:SetColorTexture(1, 1, 1, options.selected and 0.06 or 0)
        if options.inheritedTooltip then
            CludesUI.HideWidgetTooltip()
        end
    end)
    tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    tile:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            if options.onContext then
                options.onContext(tile)
            end
            return
        end
        if options.onSelect then
            options.onSelect()
        end
    end)

    if options.showToggle then
        local toggleH = 16
        local toggleBtn = CreateFrame("Button", nil, tile)
        toggleBtn:SetSize(32, toggleH)
        toggleBtn:SetPoint("TOPRIGHT", tile, "TOPRIGHT", -8, -8)
        toggleBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        -- Inherited rows: the pill is the per-spec control and stays
        -- full-brightness when the row dims.
        if options.inheritedTooltip and toggleBtn.SetIgnoreParentAlpha then
            toggleBtn:SetIgnoreParentAlpha(true)
        end
        -- Pill and knob on a pixel layer, as the settings toggle draws them.
        local on = options.enabled and true or false
        local L = CludesUI.MakePixelLayer(toggleBtn, CludesUI.TogglePillFit)
        local toggleBg = L._frame:CreateTexture(nil, "BACKGROUND")
        toggleBg:SetAllPoints(L._frame)
        local toggleKnob = L._frame:CreateTexture(nil, "ARTWORK")
        L.track, L.knob, L.pad = toggleBg, toggleKnob, 2
        L.apply = function()
            local pad = L.padPx
            toggleKnob:ClearAllPoints()
            toggleKnob:SetPoint("TOPLEFT", L._frame, "TOPLEFT", on and (L.wp - pad - L.d) or pad, -pad)
        end
        L:Fit()
        if on then
            local acr, acg, acb = CludesUI.ResolveActiveAccent()
            toggleBg:SetVertexColor(acr, acg, acb, 1)
            toggleKnob:SetVertexColor(1, 1, 1, 1)
        else
            toggleBg:SetVertexColor(0.25, 0.25, 0.25, 1)
            toggleKnob:SetVertexColor(0.5, 0.5, 0.5, 1)
        end
        toggleBtn:SetScript("OnClick", function()
            if options.onToggle then
                options.onToggle(not options.enabled)
            end
        end)
    end

    local delBtn
    if options.onDelete then
        delBtn = CreateFrame("Button", nil, tile)
        delBtn:SetSize(16, 16)
        delBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        delBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local delTex = delBtn:CreateTexture(nil, "OVERLAY")
        delTex:SetAllPoints()
        CludesUI.SetDeleteIcon(delTex)
        delTex:SetDesaturated(true)
        delTex:SetVertexColor(0.75, 0.75, 0.75)
        delBtn:SetAlpha(0.5)
        delBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
        end)
        delBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
        end)
        delBtn:SetScript("OnClick", function()
            options.onDelete()
        end)
    end

    -- Rename pencil beside the trash.
    if options.onEdit then
        local editSize = options.editSize or 16
        local editBtn = CreateFrame("Button", nil, tile)
        editBtn:SetSize(editSize, editSize)
        if delBtn then
            editBtn:SetPoint("RIGHT", delBtn, "LEFT", -4, 0)
        else
            editBtn:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", -8, 6)
        end
        editBtn:SetFrameLevel(tile:GetFrameLevel() + 2)
        local editTex = editBtn:CreateTexture(nil, "OVERLAY")
        editTex:SetAllPoints()
        if not options.editSnap and editTex.SetSnapToPixelGrid then
            editTex:SetSnapToPixelGrid(false)
            editTex:SetTexelSnappingBias(0)
        end
        editTex:SetTexture("Interface\\AddOns\\CludesUI\\media\\icons\\cui-edit.png")
        editBtn:SetAlpha(0.5)
        local tipText = options.editTooltip
        editBtn:SetScript("OnEnter", function(self)
            self:SetAlpha(0.9)
            if tipText then
                CludesUI.ShowWidgetTooltip(self, tipText)
            end
        end)
        editBtn:SetScript("OnLeave", function(self)
            self:SetAlpha(0.5)
            if tipText then
                CludesUI.HideWidgetTooltip()
            end
        end)
        editBtn:SetScript("OnClick", function()
            options.onEdit()
        end)
    end

    local sep = tile:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("BOTTOMLEFT", tile, "BOTTOMLEFT", 0, 0)
    sep:SetPoint("BOTTOMRIGHT", tile, "BOTTOMRIGHT", 0, 0)
    sep:SetColorTexture(1, 1, 1, 0.04)

    if options.statusDot then
        local dot = tile:CreateTexture(nil, "ARTWORK")
        Pix.Size(dot, 8, 8)
        -- Left of the toggle pill when the tile has one.
        Pix.Point(dot, "TOPRIGHT", tile, "TOPRIGHT", options.showToggle and -46 or -12, -14)
        dot:SetTexture("Interface\\Common\\CommonMaskCircle")
        dot:SetVertexColor(options.statusDot[1], options.statusDot[2], options.statusDot[3], 1)
    end

    if options.dimmed then
        tile:SetAlpha(0.55)
    end

    return TILE_H, tile
end

-- Full-page cover over a manager page (override-session notice or the PAB
-- enable prompt). opts: fontPath, width, title, text, sub, buttonLabel.
-- Returns ov, btn (btn only with buttonLabel; the caller sets its OnClick).
function CludesUI.BuildActivationOverlay(outerRoot, options)
    local fontFile = options.fontPath
    local shade = CreateFrame("Frame", nil, outerRoot)
    shade:SetAllPoints(outerRoot)
    shade:SetFrameLevel(outerRoot:GetFrameLevel() + 60)
    shade:EnableMouse(true)
    shade._searchIgnore = true
    local backdrop = shade:CreateTexture(nil, "OVERLAY")
    backdrop:SetAllPoints()
    backdrop:SetColorTexture(17 / 255, 15 / 255, 12 / 255, 0.98)
    local title = shade:CreateFontString(nil, "OVERLAY")
    title:SetFont(fontFile, 15, "")
    title:SetPoint("CENTER", shade, "CENTER", 0, 60)
    title:SetTextColor(1, 1, 1, 0.9)
    title:SetText(options.title)
    local body = shade:CreateFontString(nil, "OVERLAY")
    body:SetFont(fontFile, 13, "")
    body:SetPoint("TOP", title, "BOTTOM", 0, -14)
    body:SetWidth(math.floor(options.width * 0.7))
    body:SetJustifyH("CENTER")
    body:SetTextColor(1, 1, 1, 0.56)
    body:SetText(options.text or "")
    local subMenu
    if options.sub then
        subMenu = shade:CreateFontString(nil, "OVERLAY")
        subMenu:SetFont(fontFile, 12, "")
        subMenu:SetPoint("TOP", body, "BOTTOM", 0, -8)
        subMenu:SetWidth(math.floor(options.width * 0.7))
        subMenu:SetJustifyH("CENTER")
        subMenu:SetTextColor(1, 1, 1, 0.45)
        subMenu:SetText(options.sub)
    end
    if not options.buttonLabel then
        return shade
    end
    local button = CreateFrame("Button", nil, shade)
    button:SetSize(240, 28)
    button:SetPoint("TOP", subMenu or body, "BOTTOM", 0, -22)
    local backdrop = CludesUI.SolidTex(button, "BACKGROUND", 0.10, 0.10, 0.11, 0.9)
    backdrop:SetAllPoints(button)
    local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.22, backdrop)
    local labelFS = CludesUI.MakeFont(button, 12, nil, 1, 1, 1, 0.85)
    labelFS:SetPoint("CENTER")
    labelFS:SetText(options.buttonLabel)
    local brandGreen = CludesUI.CLUDES_GREEN
    button:SetScript("OnEnter", function()
        brd:SetColor(brandGreen.r, brandGreen.g, brandGreen.b, 0.9)
    end)
    button:SetScript("OnLeave", function()
        brd:SetColor(1, 1, 1, 0.22)
    end)
    return shade, button
end

-- Filter-editor popup button (dark bg, 1px border, accent border on hover).
function CludesUI.BuildPopupButton(hostFrame, wid, height, labelText, onClick)
    local button = CreateFrame("Button", nil, hostFrame)
    button:SetSize(wid, height)
    button:SetFrameLevel(hostFrame:GetFrameLevel() + 2)
    local backdrop = CludesUI.SolidTex(button, "BACKGROUND", 0, 0, 0, 0.5)
    backdrop:SetAllPoints()
    local brd = CludesUI.MakeRoundedBorder(button, 1, 1, 1, 0.25, backdrop)
    local labelFS = CludesUI.MakeFont(button, 12, nil, 1, 1, 1)
    labelFS:SetAlpha(0.6)
    labelFS:SetPoint("CENTER")
    labelFS:SetText(CludesUI.L(labelText))
    local accR, accG, accB = CludesUI.GetAccentColor()
    button:SetScript("OnEnter", function()
        labelFS:SetAlpha(0.9)
        brd:SetColor(accR, accG, accB, 0.6)
    end)
    button:SetScript("OnLeave", function()
        labelFS:SetAlpha(0.6)
        brd:SetColor(1, 1, 1, 0.25)
    end)
    button:SetScript("OnClick", onClick)
    return button
end

-------------------------------------------------------------------------------
--  Rested Indicator row
--  The player frame's rest marker (ZZZ text, or Blizzard's animated rest
--  icon), drawn by Unit Frames from account-wide keys. Quality of Life's
--  EXTRAS row and its mirror in the Unit Frames player EXTRAS are this one
--  toggle and cog, so both pages show the same settings, whichever of the
--  two modules is loaded.
--  RestedIndicatorCfg()            -> a fresh toggle config for a DualRow slot
--  BuildRestedIndicatorCog(region) -> its inline cog on that slot's region
-------------------------------------------------------------------------------
local function RestPlayerFrame()
    return _G["CludesUIUnitFrames_Player"]
end
local function RestUpdate()
    local popFrame = RestPlayerFrame()
    if popFrame and popFrame._restUpdate then
        popFrame._restUpdate()
    end
end
local function RestPlace()
    local popFrame = RestPlayerFrame()
    if popFrame and popFrame._restPlace then
        popFrame._restPlace()
    end
end
local function RestSet(key, val)
    if not CludesUIDB then
        CludesUIDB = {}
    end
    CludesUIDB[key] = val
end
local function RestOff()
    return not CludesUIDB or CludesUIDB.showRestedIndicator ~= true
end

function CludesUI.RestedIndicatorCfg()
    return {
        type = "toggle",
        text = "Rested Indicator",
        tooltip = "Displays a ZZZ indicator on your player frame when you are in a resting area.",
        getValue = function()
            if not CludesUIDB then
                return true
            end
            return CludesUIDB.showRestedIndicator == true
        end,
        setValue = function(val)
            RestSet("showRestedIndicator", val)
            RestUpdate()
            CludesUI:RefreshPage()
        end,
    }
end

-- Animated, Size, X / Y Offset; greyed while the indicator is off. Builds
-- nothing during the search pre-build.
function CludesUI.BuildRestedIndicatorCog(regionFrame)
    if CludesUI._prebuilding then
        return
    end
    return CludesUI.BuildInlineCog(regionFrame, {
        title = "Rested Indicator",
        rows = {
            {
                type = "toggle",
                label = "Animated",
                tooltip = "Shows the animated rest icon from Blizzard's player frame instead of the ZZZ text.",
                get = function()
                    return CludesUIDB and CludesUIDB.restedIndicatorAnimated == true or false
                end,
                set = function(val)
                    RestSet("restedIndicatorAnimated", val)
                    RestUpdate()
                end,
            },
            {
                type = "slider",
                label = "Size",
                min = 12,
                max = 64,
                step = 1,
                disabled = function()
                    return not (CludesUIDB and CludesUIDB.restedIndicatorAnimated == true)
                end,
                disabledTooltip = "Animated",
                get = function()
                    return (CludesUIDB and CludesUIDB.restedIndicatorAnimatedSize) or 24
                end,
                set = function(val)
                    RestSet("restedIndicatorAnimatedSize", val)
                    RestPlace()
                end,
            },
            {
                type = "slider",
                label = "X Offset",
                min = -50,
                max = 50,
                step = 1,
                get = function()
                    return (CludesUIDB and CludesUIDB.restedIndicatorXOffset) or 0
                end,
                set = function(val)
                    RestSet("restedIndicatorXOffset", val)
                    RestPlace()
                end,
            },
            {
                type = "slider",
                label = "Y Offset",
                min = -50,
                max = 50,
                step = 1,
                get = function()
                    return (CludesUIDB and CludesUIDB.restedIndicatorYOffset) or 0
                end,
                set = function(val)
                    RestSet("restedIndicatorYOffset", val)
                    RestPlace()
                end,
            },
        },
        gap = 9,
        disabled = RestOff,
        disabledTooltip = "Rested Indicator",
    })
end
