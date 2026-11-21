if CUI_CLIENT_BLOCKED then return end -- pre-12.1 client failsafe (CludesUI_ClientGate.lua)
-------------------------------------------------------------------------------
--  CUI_ActionBars_DataBars.lua
--
--  What the XP, Reputation and House Favor bars share: frame, layout, border,
--  text, visibility and unlock mode registration. Loads after the main file
--  and before CUI_ActionBars_XPBar.lua, which calls into it through ns.
-------------------------------------------------------------------------------
local _, mod = ...

local _G = _G
local ipairs, type = ipairs, type
local max = math.max
local InCombatLockdown = InCombatLockdown
local C_Timer_After = C_Timer.After

local ABAR, EAB_VTABLE, BAR_LOOKUP, EXTRA_BARS = mod.EAB, mod.EAB_VTABLE, mod.BAR_LOOKUP, mod.EXTRA_BARS
local ResolveBorderThickness = mod.ResolveBorderThickness
local Inner = mod._internals
local AttachDataBarHoverHooks, dataBarFrames = Inner.AttachDataBarHoverHooks, Inner.dataBarFrames

-------------------------------------------------------------------------------
--  Data Bars (XP, Reputation and House Favor bars): the frame, layout,
--  border, text and visibility all three share. The XP bar's own code is
--  in CUI_ActionBars_XPBar.lua (loaded after this file; called through ns).
-------------------------------------------------------------------------------
-- dataBarFrames is declared in CUI_ActionBars_Secure.lua (imported above).
mod.dataBarFrames = dataBarFrames

-- Reputation and House Favor bar colors (the XP bar's are in
-- CUI_ActionBars_XPBar.lua)
local DATA_BAR_COLORS = {
    favor = { r = 0.85, g = 0.64, b = 0.22 }, -- warm gold (house favor)
    rep = {
        [1] = { r = 0.80, g = 0.20, b = 0.20 }, -- Hated
        [2] = { r = 0.75, g = 0.30, b = 0.15 }, -- Hostile
        [3] = { r = 0.75, g = 0.45, b = 0.15 }, -- Unfriendly
        [4] = { r = 0.80, g = 0.70, b = 0.20 }, -- Neutral
        [5] = { r = 0.30, g = 0.70, b = 0.25 }, -- Friendly
        [6] = { r = 0.25, g = 0.65, b = 0.50 }, -- Honored
        [7] = { r = 0.25, g = 0.50, b = 0.75 }, -- Revered
        [8] = { r = 0.35, g = 0.30, b = 0.80 }, -- Exalted
        [9] = { r = 0.80, g = 0.65, b = 0.20 }, -- Paragon
        [10] = { r = 0.20, g = 0.70, b = 0.85 }, -- Renown
    },
}

-- Data bar textures: the suite's built-in bar texture set + SharedMedia, on ns.
do
    local lookup, nameList, sequence = CludesUI.BuildBarTextureTables()
    CludesUI.AppendSharedMediaTextures(nameList, sequence, nil, lookup)
    mod.dataBarTextures = lookup
    mod.dataBarTextureNames = nameList
    mod.dataBarTextureOrder = sequence
end

function mod.ResolveDataBarTexture(key)
    if key and key ~= "none" then
        local filePath = CludesUI.ResolveTexturePath(mod.dataBarTextures, key, nil)
        if filePath then return filePath end
    end
    return "Interface\\BUTTONS\\WHITE8X8"
end

-- Color mode per bar: nil/reactive = state-driven defaults, "accent" = live
-- accent color, "custom" = stored custom color.
function mod.ResolveDataBarColor(cfg, red, green, blue)
    local mode = cfg and cfg.colorMode
    if mode == "accent" then
        local ACC = CludesUI.CLUDES_GREEN
        if ACC then return ACC.r or red, ACC.g or green, ACC.b or blue end
    elseif mode == "custom" then
        local color = cfg.customColor
        if color then return color.r or 1, color.g or 1, color.b or 1 end
        return 1, 1, 1
    end
    return red, green, blue
end

-- Accent-mode bars repaint live when the user changes the accent color.
CludesUI.RegAccent({
    type = "callback",
    fn = function()
        for _, bk in ipairs({ "XPBar", "RepBar", "FavorBar" }) do
            local frame = dataBarFrames[bk]
            if frame and frame._updateFunc then frame._updateFunc() end
        end
    end,
})

-- Custom Border (the data-bar sections' opt-in). Off: the MakeBorder 1px line
-- stays and nothing here runs past one boolean read. On: an owned host (a
-- child of the holder, built the first time the option is on) draws the
-- chosen style through ApplyBorderStyle like every other CUI border (exact
-- size, pixel-snapped anchors, UI-scale re-apply), and MakeBorder's container
-- hides. Turning it off retires the host with HideBorderStyle BEFORE Hide, so
-- the UI-scale re-apply cannot bring an exact-size backdrop back over the
-- line, then shows MakeBorder again. Levels: host = holder+1 (its solid strips
-- land at holder+2, where MakeBorder's do); the textured backdrop is set again
-- after every ApplyBorderStyle (which resets it to the host's level): holder+2
-- above the fill, the holder's own level with Show Behind. The text host stays
-- above it. A child of the holder, so the mouseover fade carries it; the
-- holder's alpha is never read or written. On ns.
mod.ApplyDataBarBorder = function(holderFrame, cfg)
    local owner = holderFrame._cbHost
    local line = holderFrame._border and holderFrame._border._frame
    if not cfg.customBorder then
        if holderFrame._cbOn then
            holderFrame._cbOn = nil
            CludesUI.HideBorderStyle(owner)
            owner:Hide()
            -- An XP bar art frame keeps the line hidden.
            if line and not holderFrame._xpArtOn then line:Show() end
        end
        return
    end
    local lvl = holderFrame:GetFrameLevel()
    if not owner then
        owner = CreateFrame("Frame", nil, holderFrame)
        owner:SetAllPoints(holderFrame)
        owner:EnableMouse(false)
        holderFrame._cbHost = owner
    end
    owner:SetFrameLevel(lvl + 1)
    if not holderFrame._cbOn then
        holderFrame._cbOn = true
        if line then line:Hide() end
    end
    local texture = cfg.borderTexture or "solid"
    local color = cfg.borderColor
    local sz, px = ResolveBorderThickness(cfg)
    CludesUI.ApplyBorderStyle(
        owner,
        sz,
        color and color.r or 0,
        color and color.g or 0,
        color and color.b or 0,
        color and color.a or 1,
        texture,
        cfg.borderTextureOffset,
        cfg.borderTextureOffsetY,
        cfg.borderTextureShiftX,
        cfg.borderTextureShiftY,
        "actionbars",
        cfg.borderThickness or "thin",
        nil,
        px
    )
    local topY = lvl + 2
    if texture ~= "" and texture ~= "solid" then
        local edge = CludesUI._bdBorderData[owner]
        if edge then
            if cfg.borderBehind then topY = lvl end
            edge:SetFrameLevel(topY)
        end
    end
    local textHost = holderFrame._textHost
    if textHost then
        local wanted = max(lvl + 3, topY + 1)
        if textHost:GetFrameLevel() ~= wanted then textHost:SetFrameLevel(wanted) end
    end
end

-- Places a data bar's readout. Unrotated: inside the bar at its textAnchor
-- edge (4 in from a left or right end), nudged by the offsets. rotateText on
-- a vertical bar turns it to run along the bar (textReadDown: reading down),
-- the offsets turning with it (X along the reading direction, Y across it),
-- placed by its drawn centre: a rotated string pivots about the top centre of
-- its unrotated region, so the anchor is moved back by that displacement.
-- Text Background (showTextBg): on the text itself while unrotated, so it
-- follows every SetText; rotated, an upright box on the holder. _textPost:
-- a rotated placement is measured from the string, so the bar's update
-- re-places it after every SetText.
function mod.DataBarPlaceText(widget, cfg)
    local textValue = widget._text
    local rot = 0
    if cfg.rotateText and cfg.orientation == "VERTICAL" then
        rot = cfg.textReadDown and -math.pi / 2 or math.pi / 2
    end
    -- SetRotation only while rotated, and once more on the way back.
    if rot ~= 0 or widget._textRotated then
        textValue:SetRotation(rot)
        widget._textRotated = (rot ~= 0) or nil
    end
    local anchor = cfg.textAnchor
    local ox, oy = cfg.textOffsetX or 0, cfg.textOffsetY or 0
    local bgOn = cfg.showTextBg
    local backdrop = widget._textBg
    if bgOn and not backdrop then
        backdrop = widget._textHost:CreateTexture(nil, "ARTWORK")
        widget._textBg = backdrop
    end
    textValue:ClearAllPoints()
    if rot == 0 then
        local ap, padX = "CENTER", 0
        if anchor == "top" then
            ap = "TOP"
        elseif anchor == "bottom" then
            ap = "BOTTOM"
        elseif anchor == "left" then
            ap, padX = "LEFT", 4
        elseif anchor == "right" then
            ap, padX = "RIGHT", -4
        end
        textValue:SetPoint(ap, widget._textHost, ap, ox + padX, oy)
        if bgOn then
            -- 3 past the text's ends and 1 above and below it, none past the
            -- edge a top or bottom anchor sets it flush with (the border's).
            backdrop:ClearAllPoints()
            backdrop:SetPoint("TOPLEFT", textValue, "TOPLEFT", -3, ap == "TOP" and 0 or 1)
            backdrop:SetPoint("BOTTOMRIGHT", textValue, "BOTTOMRIGHT", 3, ap == "BOTTOM" and 0 or -1)
        end
        widget._textPost = nil
    else
        -- Drawn box: sw along the bar by sh across it; its centre (vx, vy)
        -- from the holder's centre, inside the border.
        local sw = textValue:GetStringWidth()
        local sh = textValue:GetStringHeight()
        if not sh or sh <= 0 then sh = textValue:GetLineHeight() end
        if not sh or sh <= 0 then sh = cfg.textSize or 9 end
        local vx, vy = 0, 0
        if anchor == "top" or anchor == "bottom" then
            vy = max(0, (cfg.height or 18) / 2 - 1 - 4 - sw / 2)
            if anchor == "bottom" then vy = -vy end
        elseif anchor == "left" or anchor == "right" then
            vx = max(0, (cfg.width or 400) / 2 - 1 - sh / 2)
            if anchor == "left" then vx = -vx end
        end
        local cs, sn = math.cos(rot), math.sin(rot)
        vx = vx + ox * cs - oy * sn
        vy = vy + ox * sn + oy * cs
        local hh = sh / 2
        textValue:SetPoint("CENTER", widget, "CENTER", vx - hh * sn, vy - hh * (1 - cs))
        if bgOn then
            -- No pad across the bar at a left or right anchor, where the
            -- text sits flush with the border.
            backdrop:ClearAllPoints()
            backdrop:SetSize((anchor == "left" or anchor == "right") and sh or sh + 2, sw + 6)
            backdrop:SetPoint("CENTER", widget, "CENTER", vx, vy)
        end
        widget._textPost = true
    end
    if backdrop then
        if bgOn then
            local color = cfg.textBgColor
            backdrop:SetColorTexture(
                color and color.r or 0.06,
                color and color.g or 0.06,
                color and color.b or 0.08,
                color and color.a or 0.9
            )
            backdrop:Show()
        else
            backdrop:Hide()
        end
    end
end

-- A data bar frame's look from its settings: size, texture, orientation, the
-- XP bar's style, text, dividers and Custom Border. Frame-bound only, so the
-- options preview's own frame takes it too; ApplyDataBarLayout adds the live
-- bar's size matching and value update. On ns.
function mod.StyleDataBarFrame(widget, cfg)
    local wid = cfg.width or 400
    local hgt = cfg.height or 18
    local orient = cfg.orientation or "HORIZONTAL"

    -- Centered growth on resize is handled by the centralized unlock mode
    -- position system (NotifyElementResized re-applies CENTER anchor).
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        Pix.Size(widget, wid, hgt)
    else
        widget:SetSize(wid, hgt)
    end

    local texPath = mod.ResolveDataBarTexture(cfg.barTexture)
    widget._bar:SetStatusBarTexture(texPath)
    widget._bar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 4)
    if widget._restedBar then
        widget._restedBar:SetStatusBarTexture(texPath)
        widget._restedBar:GetStatusBarTexture():SetDrawLayer("ARTWORK", 1)
    end

    widget._bar:SetOrientation(orient)
    widget._bar:SetRotatesTexture(orient ~= "HORIZONTAL")
    if widget._restedBar then
        widget._restedBar:SetOrientation(orient)
        widget._restedBar:SetRotatesTexture(orient ~= "HORIZONTAL")
    end

    -- XP bar art style and profession fill (both opt-in; CUI_ActionBars_XPBar.lua).
    if widget._isXP then mod.ApplyXPBarStyle(widget, cfg) end

    -- Per-bar Text Size (default 9) and the readout's placement (anchor,
    -- offsets, rotation, background). Re-applied here so the options take
    -- effect live through the existing ApplyDataBarLayout calls.
    if widget._text then
        -- Read live, not FONT_PATH: that load-time capture misses a standalone's
        -- saved fonts and a login spec-profile switch.
        widget._text:SetFont(
            CludesUI.GetFontPath("actionBars"),
            cfg.textSize or 9,
            CludesUI.GetFontOutlineFlag("actionBars")
        )
        mod.DataBarPlaceText(widget, cfg)
        if widget._isXP then mod.XPBarTextSlots(widget, cfg) end
    end

    -- Dividers (CUI_ActionBars_XPBar.lua): one boolean read while off; a
    -- built host is called to hide.
    if widget._divHost or cfg.showDividers then mod.AB_DataBarDividers(widget, wid, hgt, orient, cfg) end

    -- Custom Border (one boolean read while off).
    mod.ApplyDataBarBorder(widget, cfg)
end

local function ApplyDataBarLayout(barId)
    local widget = dataBarFrames[barId]
    local s = ABAR.db.profile.bars[barId]
    if widget and s then
        mod.StyleDataBarFrame(widget, s)
        -- The Custom Border's reach for width / height matching (value-compared
        -- and deferred; a no-op in unlock mode and before the bar is registered).
        CludesUI.MatchPadChanged(barId)
        if widget._updateFunc then widget._updateFunc() end
    end
    mod.RefreshDataBarPreview(barId)
end
mod.ApplyDataBarLayout = ApplyDataBarLayout

-- An options preview of a data bar repaints after the live bar (one per bar
-- key in ns._dataBarPreview, set by the options; also while Blizzard's bars
-- build no frame of ours). Every options write that repaints the live bar
-- calls it: through ApplyDataBarLayout, or directly after a value-only
-- update (valueOnly: the fill alone changed). On ns.
function mod.RefreshDataBarPreview(barId, valueOnly)
    local pv = mod._dataBarPreview
    local hook = pv and pv[barId]
    if hook then hook(valueOnly) end
end

-- parent: a preview frame for the options (its own parent, no global names,
-- not in dataBarFrames, holder._preview set); nil builds the live bar.
local function CreateDataBarFrame(barId, updateFunc, hostFrame)
    local holderFrame =
        CreateFrame("Frame", not hostFrame and "CludesEAB_" .. barId or nil, hostFrame or UIParent)
    holderFrame:SetSize(400, 18)
    if not hostFrame then holderFrame:SetClampedToScreen(true) end
    holderFrame._preview = hostFrame and true or nil
    holderFrame._isXP = (barId == "XPBar") or nil

    -- Pixel-perfect background
    local backdrop = holderFrame:CreateTexture(nil, "BACKGROUND")
    backdrop:SetColorTexture(0.06, 0.06, 0.08, 0.85)
    local Pix = CludesUI and CludesUI.PP
    if Pix then
        Pix.SetInside(backdrop, holderFrame, 1, 1)
    else
        backdrop:SetPoint("TOPLEFT", 1, -1)
        backdrop:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    holderFrame._bg = backdrop

    -- Pixel-perfect 1px border via MakeBorder
    if CludesUI and CludesUI.MakeBorder then
        holderFrame._border = CludesUI.MakeBorder(holderFrame, 0, 0, 0, 1)
    end

    local barFrame =
        CreateFrame("StatusBar", not hostFrame and "CludesEAB_" .. barId .. "_Bar" or nil, holderFrame)
    barFrame:SetStatusBarTexture("Interface\\BUTTONS\\WHITE8X8")
    if Pix then
        Pix.SetInside(barFrame, holderFrame, 1, 1)
    else
        barFrame:SetPoint("TOPLEFT", 1, -1)
        barFrame:SetPoint("BOTTOMRIGHT", -1, 1)
    end
    barFrame:SetMinMaxValues(0, 1)
    barFrame:SetValue(0)
    barFrame:GetStatusBarTexture():SetDrawLayer("ARTWORK", 4)

    -- Text lives on its own host ABOVE the MakeBorder strips: the border
    -- container renders two levels above the holder, and frame level beats
    -- draw layer, so a string on the bar itself gets cut by the border edges
    -- whenever the glyphs reach them (large Text Size / short bars).
    local textHost = CreateFrame("Frame", nil, barFrame)
    textHost:SetAllPoints(barFrame)
    local edges = holderFrame._border and holderFrame._border.edges
    textHost:SetFrameLevel(
        ((edges and edges.GetFrameLevel and edges:GetFrameLevel()) or holderFrame:GetFrameLevel() + 2) + 1
    )

    -- Kept for Custom Border, which holds it above its own backdrop.
    holderFrame._textHost = textHost

    local textValue = textHost:CreateFontString(nil, "OVERLAY")
    CludesUI.PrimeFontShadow(textValue, CludesUI.GetFontUseShadow("actionBars"))
    local sInit = ABAR.db and ABAR.db.profile and ABAR.db.profile.bars and ABAR.db.profile.bars[barId]
    textValue:SetFont(
        CludesUI.GetFontPath("actionBars"),
        sInit and sInit.textSize or 9,
        CludesUI.GetFontOutlineFlag("actionBars")
    )
    textValue:SetPoint("CENTER", sInit and sInit.textOffsetX or 0, sInit and sInit.textOffsetY or 0)
    textValue:SetTextColor(1, 1, 1, 1)

    holderFrame._bar = barFrame
    holderFrame._text = textValue
    holderFrame._updateFunc = updateFunc

    if not hostFrame then dataBarFrames[barId] = holderFrame end
    return holderFrame
end
-- The XP bar (CUI_ActionBars_XPBar.lua) builds its frame through this too.
mod.CreateDataBarFrame = CreateDataBarFrame

-- Data bars own their content updates, but visibility is shared with the
-- generic non-secure visibility system above. Guard each update callback so a
-- later XP/reputation event cannot re-show a bar that runtime conditions have
-- already hidden (for example `solo` while grouped).
function EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate(barId)
    local widget = dataBarFrames[barId]
    if not widget then return nil, nil end
    local details = BAR_LOOKUP[barId]
    if ABAR.db.profile.useBlizzardDataBars then
        if details then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(
                details,
                widget,
                ABAR.db.profile.bars[barId],
                false,
                true
            )
        else
            widget:Hide()
        end
        return nil, nil
    end

    local s = ABAR.db.profile.bars[barId]
    if not s then return nil, nil end
    if not EAB_VTABLE.ExtraBars.ShouldShowManagedNonSecureBar(s) then
        if details then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(details, widget, s, false, true)
        else
            widget:Hide()
        end
        return nil, s
    end

    return widget, s
end

function EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate(barId, widget, s)
    if not widget or not s then return end

    local details = BAR_LOOKUP[barId]
    if details then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(details, widget, s, true, true)
    else
        widget:Show()
    end
end

-------------------------------------------------------------------------------
--  Reputation Bar
-------------------------------------------------------------------------------
local function UpdateRepBar()
    local widget, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("RepBar")
    if not widget then return end

    local barFrame = widget._bar
    local textValue = widget._text

    local payload = C_Reputation
        and C_Reputation.GetWatchedFactionData
        and C_Reputation.GetWatchedFactionData()
    if not payload or not payload.name then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], widget, s, false, true)
        return
    end

    local name = payload.name
    local reaction = payload.reaction or 4
    local factionID = payload.factionID
    local currentStanding = payload.currentStanding or 0
    local currentReactionThreshold = payload.currentReactionThreshold or 0
    local nextReactionThreshold = payload.nextReactionThreshold or 1
    local standing

    -- Friendship handling (check first friendships override normal standing)
    local isFriendship = false
    if factionID then
        local friendInfo = C_GossipInfo
            and C_GossipInfo.GetFriendshipReputation
            and C_GossipInfo.GetFriendshipReputation(factionID)
        if friendInfo and friendInfo.friendshipFactionID and friendInfo.friendshipFactionID > 0 then
            isFriendship = true
            standing = friendInfo.reaction
            currentReactionThreshold = friendInfo.reactionThreshold or 0
            nextReactionThreshold = friendInfo.nextThreshold or math.huge
            currentStanding = friendInfo.standing or 1
        end
    end

    -- Paragon handling (check before renown max-renown factions become paragon)
    local isParagon = false
    if
        factionID
        and C_Reputation.IsFactionParagonForCurrentPlayer
        and C_Reputation.IsFactionParagonForCurrentPlayer(factionID)
    then
        local paragonVal, paragonThreshold = C_Reputation.GetFactionParagonInfo(factionID)
        if paragonVal and paragonThreshold then
            isParagon = true
            standing = CludesUI.L("Paragon")
            currentStanding = paragonVal % paragonThreshold
            currentReactionThreshold = 0
            nextReactionThreshold = paragonThreshold
            reaction = 9
        end
    end

    -- Renown handling (only if not already paragon or friendship)
    if
        not isParagon
        and not isFriendship
        and factionID
        and C_Reputation.IsMajorFaction
        and C_Reputation.IsMajorFaction(factionID)
    then
        local majorData = C_MajorFactions
            and C_MajorFactions.GetMajorFactionData
            and C_MajorFactions.GetMajorFactionData(factionID)
        if majorData then
            local hasMax = C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionID)
            if hasMax then
                EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(
                    BAR_LOOKUP["RepBar"],
                    widget,
                    s,
                    false,
                    true
                )
                return
            end
            reaction = 10
            standing = CludesUI.L("Renown")
            currentReactionThreshold = 0
            nextReactionThreshold = majorData.renownLevelThreshold
            currentStanding = majorData.renownReputationEarned or 0
        end
    end

    if not standing then standing = _G["FACTION_STANDING_LABEL" .. reaction] or "" end

    local color = DATA_BAR_COLORS.rep[reaction] or DATA_BAR_COLORS.rep[4]
    barFrame:SetStatusBarColor(mod.ResolveDataBarColor(s, color.r, color.g, color.b))

    -- Hide capped / maxed factions (Exalted with no paragon, max friendship, etc.)
    if nextReactionThreshold == math.huge or currentReactionThreshold == nextReactionThreshold then
        EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(BAR_LOOKUP["RepBar"], widget, s, false, true)
        return
    end

    local current = currentStanding - currentReactionThreshold
    local maximum = nextReactionThreshold - currentReactionThreshold
    if maximum <= 0 then maximum = 1 end

    barFrame:SetMinMaxValues(0, maximum)
    barFrame:SetValue(current)

    local pct = (current / maximum) * 100
    -- The tooltip must show the same numbers the bar shows. Recomputing them
    -- from the raw watched-faction payload there breaks on paragon/renown
    -- factions (negative reputation, wrong standing), so stash the resolved
    -- values for the OnEnter handler below.
    widget._tipStanding, widget._tipCurrent, widget._tipMaximum = standing, current, maximum
    textValue:SetText(format("%s: %.0f%% [%s]", name, pct, standing))

    -- Auto-size text if bar is too narrow (too short, for text rotated to
    -- run along a vertical bar)
    local room = (s.rotateText and s.orientation == "VERTICAL") and widget:GetHeight() or widget:GetWidth()
    if textValue:GetStringWidth() > room - 4 then textValue:SetText(format("%.0f%%", pct)) end
    if widget._textPost then mod.DataBarPlaceText(widget, s) end

    EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("RepBar", widget, s)
end

local function CreateRepBar()
    local holderFrame = CreateDataBarFrame("RepBar", UpdateRepBar)
    holderFrame:SetPoint("TOP", UIParent, "TOP", 0, -84)

    -- Tooltip (suppressed under Click Through, as on the XP bar)
    holderFrame:EnableMouse(true)
    holderFrame:SetScript("OnEnter", function(self)
        local conf = ABAR
            and ABAR.db
            and ABAR.db.profile
            and ABAR.db.profile.bars
            and ABAR.db.profile.bars["RepBar"]
        if conf and conf.clickThrough then return end
        local payload = C_Reputation
            and C_Reputation.GetWatchedFactionData
            and C_Reputation.GetWatchedFactionData()
        if not payload or not payload.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(payload.name, 1, 1, 1)
        -- Use the values the bar already resolved (paragon/renown/friendship
        -- aware); fall back to the raw payload only if the bar has not run yet.
        local standing = self._tipStanding
        if not standing or standing == "" then
            standing = _G["FACTION_STANDING_LABEL" .. (payload.reaction or 4)] or ""
        end
        GameTooltip:AddDoubleLine(CludesUI.L("Standing"), standing, 1, 1, 1, 1, 1, 1)
        local current = self._tipCurrent
            or ((payload.currentStanding or 0) - (payload.currentReactionThreshold or 0))
        local maximum = self._tipMaximum
            or ((payload.nextReactionThreshold or 1) - (payload.currentReactionThreshold or 0))
        if maximum <= 0 then maximum = 1 end
        local pct = (current / maximum) * 100
        GameTooltip:AddDoubleLine(
            CludesUI.L("Reputation"),
            format("%s / %s (%.1f%%)", BreakUpLargeNumbers(current), BreakUpLargeNumbers(maximum), pct),
            1,
            1,
            1,
            1,
            1,
            1
        )
        GameTooltip:Show()
    end)
    holderFrame:SetScript("OnLeave", function(self)
        if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
    end)

    -- Events
    local evFrame = mod.TakeShell()
    evFrame:RegisterEvent("UPDATE_FACTION")
    evFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    evFrame:RegisterEvent("QUEST_FINISHED")
    if C_MajorFactions then
        evFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
        evFrame:RegisterEvent("MAJOR_FACTION_UNLOCKED")
    end
    evFrame:SetScript("OnEvent", UpdateRepBar)

    ApplyDataBarLayout("RepBar")
    UpdateRepBar()
end

-------------------------------------------------------------------------------
--  House Favor Bar: Blizzard's "Show as Experience Bar" favor watch renders
--  through StatusTrackingBarManager, which the custom data bars replace --
--  this bar is the house-favor equivalent. The favor API is asynchronous:
--  GetPlayerOwnedHouses() -> PLAYER_HOUSE_LIST_UPDATED (house list) ->
--  GetCurrentHouseLevelFavor(guid) -> HOUSE_LEVEL_FAVOR_UPDATED (level +
--  favor payload); GetHouseLevelFavorForLevel(n) is the only sync read.
-------------------------------------------------------------------------------
-- Block-scoped + ns export: the file-scope local budget is nearly at the
-- Lua 5.1 200 cap. WoW Forever has no housing: there the block never runs,
-- so no bar is built, nothing registers and ns._CreateFavorBar stays nil.
if not CludesUI.IS_FOREVER then
    local favorState -- { level, displayLevel, favor, needed } from the last payload
    local favorEv, favorArmed
    local ArmFavorEvents -- forward: mutual recursion with UpdateFavorBar

    -- No favor requests or repaints inside an active keystone or a raid instance.
    local function FavorBlocked()
        if
            C_ChallengeMode
            and C_ChallengeMode.IsChallengeModeActive
            and C_ChallengeMode.IsChallengeModeActive()
        then
            return true
        end
        local inInst, instType = IsInInstance()
        return (inInst and instType == "raid") and true or false
    end

    -- Zero cost while hidden: events stay unregistered unless the bar can actually show.
    local function FavorWanted()
        if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return false end
        local profile = ABAR.db and ABAR.db.profile
        if not profile or profile.useBlizzardDataBars then return false end
        local s = profile.bars and profile.bars.FavorBar
        return (s and not ABAR.VisibilityCompat.IsNever(s)) and true or false
    end

    local function UpdateFavorBar()
        if ArmFavorEvents then ArmFavorEvents() end
        local widget, s = EAB_VTABLE.ExtraBars.BeginManagedDataBarUpdate("FavorBar")
        if not widget then return end

        local barFrame = widget._bar
        local textValue = widget._text

        -- No house / no data yet / max house level (no next-level requirement).
        local st = favorState
        if not st or not st.needed or st.needed <= 0 then
            EAB_VTABLE.ExtraBars.ApplyManagedNonSecurePresentation(
                BAR_LOOKUP["FavorBar"],
                widget,
                s,
                false,
                true
            )
            return
        end

        local current = st.favor or 0
        if current > st.needed then current = st.needed end
        barFrame:SetMinMaxValues(0, st.needed)
        barFrame:SetValue(current)
        barFrame:SetStatusBarColor(
            mod.ResolveDataBarColor(
                s,
                DATA_BAR_COLORS.favor.r,
                DATA_BAR_COLORS.favor.g,
                DATA_BAR_COLORS.favor.b
            )
        )

        local pct = (current / st.needed) * 100
        textValue:SetText(
            format(CludesUI.L("House Level %d: %d / %d"), st.displayLevel or 1, current, st.needed)
        )

        -- Auto-size text if bar is too narrow (too short, for text rotated to
        -- run along a vertical bar)
        local room = (s.rotateText and s.orientation == "VERTICAL") and widget:GetHeight()
            or widget:GetWidth()
        if textValue:GetStringWidth() > room - 4 then textValue:SetText(format("%.0f%%", pct)) end
        if widget._textPost then mod.DataBarPlaceText(widget, s) end

        EAB_VTABLE.ExtraBars.FinishManagedDataBarUpdate("FavorBar", widget, s)
    end

    local function OnFavorEvent(_, evt, arg1)
        if FavorBlocked() then return end
        if not (C_Housing and C_Housing.GetPlayerOwnedHouses) then return end
        if evt == "PLAYER_ENTERING_WORLD" then
            C_Housing.GetPlayerOwnedHouses()
        elseif evt == "PLAYER_HOUSE_LIST_UPDATED" then
            local details = type(arg1) == "table" and arg1[1]
            local unitGuid = details and details.houseGUID
            if unitGuid and C_Housing.GetCurrentHouseLevelFavor then
                C_Housing.GetCurrentHouseLevelFavor(unitGuid)
            else
                favorState = nil
                UpdateFavorBar()
            end
        elseif evt == "HOUSE_LEVEL_FAVOR_UPDATED" then
            if type(arg1) == "table" and arg1.houseLevel ~= nil then
                local level = arg1.houseLevel or 0
                local needed = C_Housing.GetHouseLevelFavorForLevel
                    and C_Housing.GetHouseLevelFavorForLevel(level + 1)
                favorState = {
                    level = level,
                    displayLevel = level + 1,
                    favor = arg1.houseFavor or 0,
                    needed = needed or 0,
                }
            else
                favorState = nil
            end
            UpdateFavorBar()
        end
    end

    ArmFavorEvents = function()
        local wanted = FavorWanted()
        if wanted and not favorArmed then
            favorArmed = true
            if not favorEv then
                favorEv = mod.TakeShell()
                favorEv:SetScript("OnEvent", OnFavorEvent)
            end
            favorEv:RegisterEvent("PLAYER_ENTERING_WORLD")
            favorEv:RegisterEvent("PLAYER_HOUSE_LIST_UPDATED")
            favorEv:RegisterEvent("HOUSE_LEVEL_FAVOR_UPDATED")
            -- Kick the async chain now; if inside blocked content the next
            -- world-enter re-kicks instead.
            if not FavorBlocked() then C_Housing.GetPlayerOwnedHouses() end
        elseif not wanted and favorArmed then
            favorArmed = false
            if favorEv then favorEv:UnregisterAllEvents() end
        end
    end

    local function CreateFavorBar()
        local holderFrame = CreateDataBarFrame("FavorBar", UpdateFavorBar)
        holderFrame:SetPoint("TOP", UIParent, "TOP", 0, -68)

        -- Tooltip (suppressed under Click Through, as on the XP bar)
        holderFrame:EnableMouse(true)
        holderFrame:SetScript("OnEnter", function(self)
            local conf = ABAR
                and ABAR.db
                and ABAR.db.profile
                and ABAR.db.profile.bars
                and ABAR.db.profile.bars["FavorBar"]
            if conf and conf.clickThrough then return end
            local st = favorState
            if not st or not st.needed or st.needed <= 0 then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(CludesUI.L("House Favor"), 1, 1, 1)
            GameTooltip:AddDoubleLine(
                CludesUI.L("House Level"),
                tostring(st.displayLevel or 1),
                1,
                1,
                1,
                1,
                1,
                1
            )
            local current = math.min(st.favor or 0, st.needed)
            local pct = (current / st.needed) * 100
            GameTooltip:AddDoubleLine(
                CludesUI.L("Favor"),
                format("%s / %s (%.1f%%)", BreakUpLargeNumbers(current), BreakUpLargeNumbers(st.needed), pct),
                1,
                1,
                1,
                1,
                1,
                1
            )
            GameTooltip:AddDoubleLine(
                CludesUI.L("Remaining"),
                BreakUpLargeNumbers(st.needed - current),
                1,
                1,
                1,
                1,
                1,
                1
            )
            GameTooltip:Show()
        end)
        holderFrame:SetScript("OnLeave", function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)

        -- Event registration is handled by ArmFavorEvents (via UpdateFavorBar):
        -- nothing is registered while the bar is hidden.
        ApplyDataBarLayout("FavorBar")
        UpdateFavorBar()
    end

    mod._CreateFavorBar = CreateFavorBar
end -- not IS_FOREVER

-------------------------------------------------------------------------------
--  Register Data Bars with Unlock Mode: same pattern as action bars and
--  Blizzard movable frames -- savePosition/loadPosition/applyPosition/
--  clearPosition callbacks.
-------------------------------------------------------------------------------
local function RegisterDataBarsWithUnlockMode()
    if not CludesUI or not CludesUI.RegisterUnlockElements then return end
    local MK = CludesUI.MakeUnlockElement
    local elements = {}
    local orderBase = 300
    for position, details in ipairs(EXTRA_BARS) do
        -- Only a bar that was built gets a mover (WoW Forever never builds
        -- the House Favor bar).
        if details.isDataBar and dataBarFrames[details.key] then
            local bk = details.key
            elements[#elements + 1] = MK({
                key = bk,
                label = details.label,
                group = "Action Bars",
                order = orderBase + position,
                getFrame = function() return dataBarFrames[bk] end,
                getSize = function()
                    -- Return stored DB values so cog menu shows what the
                    -- user typed, not the pixel-snapped frame size.
                    local cfg = ABAR.db.profile.bars[bk]
                    if cfg then return cfg.width or 400, cfg.height or 18 end
                    return 400, 18
                end,
                -- A Custom Border's textured reach past the bar's edges counts
                -- in size matching (the same arguments ApplyDataBarBorder
                -- paints with). nil while Custom Border is off: MakeBorder's
                -- line and solid strips sit inside the frame.
                getMatchPad = function()
                    local cfg = ABAR.db and ABAR.db.profile and ABAR.db.profile.bars[bk]
                    if not (cfg and cfg.customBorder) then return nil end
                    local sz, px = ResolveBorderThickness(cfg)
                    local color = cfg.borderColor
                    return CludesUI.BorderMatchPad(
                        sz,
                        cfg.borderTexture or "solid",
                        cfg.borderTextureOffset,
                        cfg.borderTextureOffsetY,
                        cfg.borderTextureShiftX,
                        cfg.borderTextureShiftY,
                        "actionbars",
                        cfg.borderThickness or "thin",
                        px,
                        nil,
                        color and color.a or 1
                    )
                end,
                setWidth = function(_, wid)
                    local cfg = ABAR.db.profile.bars[bk]
                    local PPab = CludesUI and CludesUI.PP
                    if cfg then cfg.width = PPab and PPab.Snap(wid) or math.floor(wid + 0.5) end
                    ApplyDataBarLayout(bk)
                end,
                setHeight = function(_, hgt)
                    local cfg = ABAR.db.profile.bars[bk]
                    local PPab = CludesUI and CludesUI.PP
                    if cfg then cfg.height = PPab and PPab.Snap(hgt) or math.floor(hgt + 0.5) end
                    ApplyDataBarLayout(bk)
                end,
                savePos = function(_, anchorPoint, relPoint, posX, posY)
                    if anchorPoint and posX and posY then
                        ABAR.db.profile.barPositions[bk] = {
                            point = anchorPoint,
                            relPoint = relPoint or anchorPoint,
                            x = posX,
                            y = posY,
                        }
                    end
                    if not CludesUI._unlockActive then
                        local widget = dataBarFrames[bk]
                        if widget and anchorPoint and posX and posY then
                            widget:ClearAllPoints()
                            widget:SetPoint(anchorPoint, UIParent, relPoint or anchorPoint, posX, posY)
                        end
                    end
                end,
                loadPos = function()
                    local place = ABAR.db.profile.barPositions[bk]
                    if not place then return nil end
                    local pt = place.point
                    return { point = pt, relPoint = place.relPoint or pt, x = place.x, y = place.y }
                end,
                clearPos = function() ABAR.db.profile.barPositions[bk] = nil end,
                applyPos = function()
                    local place = ABAR.db.profile.barPositions[bk]
                    local widget = dataBarFrames[bk]
                    if not widget then return end
                    widget:ClearAllPoints()
                    if place and place.point then
                        local pt, rpt = place.point, place.relPoint or place.point
                        local px, py = place.x, place.y
                        local PPa = CludesUI and CludesUI.PP
                        if PPa and px and py then
                            local es = widget:GetEffectiveScale()
                            local isCenterAnchor = (pt == "CENTER") and (rpt == "CENTER")
                            if isCenterAnchor and PPa.SnapCenterForDim then
                                px = PPa.SnapCenterForDim(px, widget:GetWidth() or 0, es)
                                py = PPa.SnapCenterForDim(py, widget:GetHeight() or 0, es)
                            elseif PPa.SnapForES then
                                px = PPa.SnapForES(px, es)
                                py = PPa.SnapForES(py, es)
                            end
                        end
                        widget:SetPoint(pt, UIParent, rpt, px or 0, py or 0)
                    else
                        if bk == "XPBar" then
                            widget:SetPoint("TOP", UIParent, "TOP", 0, -100)
                        elseif bk == "RepBar" then
                            widget:SetPoint("TOP", UIParent, "TOP", 0, -84)
                        elseif bk == "FavorBar" then
                            widget:SetPoint("TOP", UIParent, "TOP", 0, -68)
                        end
                    end
                end,
            })
        end
    end
    CludesUI:RegisterUnlockElements(elements, "CludesUIActionBars")
end

function EAB_VTABLE.ExtraBars.CreateManagedDataBarFrames()
    mod.CreateXPBar()
    CreateRepBar()
    if mod._CreateFavorBar then mod._CreateFavorBar() end
end

function EAB_VTABLE.ExtraBars.InitializeDataBarHoverState()
    for _, details in ipairs(EXTRA_BARS) do
        if details.isDataBar then AttachDataBarHoverHooks(details.key) end
    end
end

function EAB_VTABLE.ExtraBars.RestoreSavedDataBarPositions()
    local positions = ABAR.db.profile.barPositions
    if not positions then return end

    for _, details in ipairs(EXTRA_BARS) do
        if details.isDataBar then
            local place = positions[details.key]
            local widget = dataBarFrames[details.key]
            if place and widget and place.point then
                widget:ClearAllPoints()
                widget:SetPoint(place.point, UIParent, place.relPoint, place.x, place.y)
            end
        end
    end
end

function EAB_VTABLE.ExtraBars.RegisterDataBarsWithUnlockModeWhenReady()
    if CludesUI and CludesUI.RegisterUnlockElements then
        RegisterDataBarsWithUnlockMode()
        return
    end

    C_Timer_After(1, function()
        if CludesUI and CludesUI.RegisterUnlockElements then RegisterDataBarsWithUnlockMode() end
    end)
end

function EAB_VTABLE.ExtraBars.EnsureManagedDataBarRuntimeState()
    -- Apply the current combat/group/mouseover state now that every managed
    -- non-secure frame exists. ApplyAll runs earlier in startup before these
    -- holders/data bars are created.
    EAB_VTABLE.ExtraBars._managedNonSecureInCombat = InCombatLockdown()
    EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()

    if EAB_VTABLE.ExtraBars._managedDataBarCombatFrame then return end

    -- Managed non-secure bars need a runtime combat refresh because secure
    -- state drivers are not available for these frames.
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame = mod.TakeShell()
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    EAB_VTABLE.ExtraBars._managedDataBarCombatFrame:SetScript("OnEvent", function(_, evt)
        -- Rely on the combat event direction here instead of sampling
        -- `InCombatLockdown()` during the transition. That keeps the managed
        -- non-secure bars in sync with the same edge that triggered the event.
        EAB_VTABLE.ExtraBars._managedNonSecureInCombat = (evt == "PLAYER_REGEN_DISABLED")
        EAB_VTABLE.ExtraBars.RefreshManagedNonSecureVisibility()
    end)
end

local function SetupDataBars()
    -- Skip creating custom bars entirely if user wants Blizzard to control them
    if ABAR.db.profile.useBlizzardDataBars then return end

    -- Phase 1: create the frames and their update callbacks.
    EAB_VTABLE.ExtraBars.CreateManagedDataBarFrames()

    -- Phase 2: attach hover handling now that the holders exist.
    EAB_VTABLE.ExtraBars.InitializeDataBarHoverState()

    -- Phase 3: restore saved positions onto the live holders.
    EAB_VTABLE.ExtraBars.RestoreSavedDataBarPositions()

    -- Phase 4: register the frames with Unlock Mode once the shared shell is ready.
    EAB_VTABLE.ExtraBars.RegisterDataBarsWithUnlockModeWhenReady()

    -- Phase 5: apply the current runtime visibility state and keep it in sync.
    EAB_VTABLE.ExtraBars.EnsureManagedDataBarRuntimeState()
end

-- The profile's one Blizzard data bar switch (useBlizzardDataBars: the XP,
-- reputation and House Favor bars together), applied live. The XP Bar tab's
-- Blizz Default style and the Use Blizzard's Rep Bars toggle both set it
-- here. On: our built data bars hide (each update then runs its hidden
-- path, so the Favor bar disarms its events) and Blizzard's status tracking
-- bars return. Off: our built bars show unless set to Never and repaint, and
-- Blizzard's hide. Returns true when the switch needs a reload, so the caller
-- can offer one: a bar of ours this client builds does not exist yet (they are
-- built at login only while the switch is off), or Blizzard's bars come back
-- after their events were dropped this session. On ns.
function mod.SetUseBlizzardDataBars(val)
    local profile = ABAR.db.profile
    profile.useBlizzardDataBars = val
    local needsReload = false
    for _, details in ipairs(EXTRA_BARS) do
        local k = details.key
        -- WoW Forever builds no House Favor bar: never a reload for it there.
        if details.isDataBar and not (k == "FavorBar" and CludesUI.IS_FOREVER) then
            local widget = dataBarFrames[k]
            if not widget then
                if not val then needsReload = true end
            elseif val then
                widget:Hide()
                if widget._updateFunc then widget._updateFunc() end
            else
                local s = profile.bars[k]
                if not s or not ABAR.VisibilityCompat.IsNever(s) then
                    widget:Show()
                    if widget._updateFunc then widget._updateFunc() end
                end
            end
        end
    end
    if StatusTrackingBarManager then
        if val then
            StatusTrackingBarManager:Show()
            -- Dropped events come back only with a reload: a registration made
            -- from here would run every one of them, and the bottom bar stack
            -- pass a shown or hidden bar starts, under our taint.
            if mod._eabBlizzDataBarsDropped then needsReload = true end
        else
            StatusTrackingBarManager:UnregisterAllEvents()
            StatusTrackingBarManager:Hide()
            mod._eabBlizzDataBarsDropped = true
        end
    end
    return needsReload
end

Inner.SetupDataBars = SetupDataBars -- called by CUI_ActionBars_ExtraBars.lua
